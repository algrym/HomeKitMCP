import Foundation
import HomeKit

@MainActor
final class HomeKitManager: NSObject {
    private var homeManager: HMHomeManager?

    /// Readiness lifecycle. `.ready` and `.unavailable` resolve pending waiters;
    /// only `.idle`/`.waiting` are non-terminal. A late homes-loaded callback can
    /// still promote `.unavailable` back to `.ready`, so a permission granted while
    /// the server is running recovers without a restart.
    private enum ReadyState { case idle, waiting, ready, unavailable }
    private var state: ReadyState = .idle
    private var readyWaiters: [CheckedContinuation<Bool, Never>] = []

    /// How long to wait for HomeKit to report in before giving up. The authorization
    /// prompt cannot be answered when the app is launched headless from a pipe, so we
    /// must never wait forever — that is what wedged the whole server.
    private static let readinessTimeout: Duration = .seconds(10)

    override init() {
        super.init()
    }

    func start() async {
        _ = await waitUntilReady()
    }

    /// Ensure HomeKit has loaded, waiting at most `readinessTimeout`.
    /// - Returns: `true` once homes have loaded; `false` if access was denied or
    ///   HomeKit never reported in. Bounded — this never hangs.
    @discardableResult
    func waitUntilReady() async -> Bool {
        switch state {
        case .ready:
            return true
        case .unavailable:
            return false
        case .idle:
            state = .waiting
            let manager = HMHomeManager()
            manager.delegate = self
            homeManager = manager
            Log.info("HomeKitManager: waiting for homes to load...")

            // Arm a one-shot timeout so undetermined authorization (headless launch)
            // resolves waiters instead of stalling the server indefinitely.
            Task { @MainActor in
                try? await Task.sleep(for: Self.readinessTimeout)
                guard self.state == .waiting else { return }
                Log.error("HomeKitManager: timed out waiting for HomeKit. Grant access in System Settings > Privacy & Security > HomeKit and confirm at least one home exists in the Home app, then restart the server.")
                self.resolve(ready: false)
            }
            return await withCheckedContinuation { readyWaiters.append($0) }
        case .waiting:
            return await withCheckedContinuation { readyWaiters.append($0) }
        }
    }

    /// Transition to a terminal state and wake all pending waiters.
    private func resolve(ready: Bool) {
        guard state == .waiting else { return }
        state = ready ? .ready : .unavailable
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: ready) }
    }

    /// Promote to ready from any non-ready state (homes can load after we gave up).
    private func markReady() {
        guard state != .ready else { return }
        state = .ready
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: true) }
    }

    // MARK: - Homes

    func listHomes() -> [[String: Any]] {
        guard let manager = homeManager else { return [] }
        return manager.homes.map { home in
            [
                "name": home.name,
                "isPrimary": home == manager.primaryHome,
                "roomCount": home.rooms.count,
                "accessoryCount": home.accessories.count,
            ] as [String: Any]
        }
    }

    // MARK: - Rooms

    func listRooms(homeName: String?) -> [[String: Any]] {
        let homes = matchingHomes(name: homeName)
        return homes.flatMap { home in
            home.rooms.map { room in
                [
                    "name": room.name,
                    "home": home.name,
                    "deviceCount": room.accessories.count,
                ] as [String: Any]
            }
        }
    }

    // MARK: - Devices

    func listDevices(homeName: String?, roomName: String?, type: String?) -> [[String: Any]] {
        let accessories = matchingAccessories(homeName: homeName, roomName: roomName)
        return accessories.compactMap { (accessory: HMAccessory) -> [String: Any]? in
            let deviceType = self.deviceType(for: accessory)
            if let type = type, deviceType.lowercased() != type.lowercased() {
                return nil
            }
            return [
                "name": accessory.name,
                "room": accessory.room?.name ?? "Default Room",
                "home": self.homeNameForAccessory(accessory),
                "type": deviceType,
                "reachable": accessory.isReachable,
                "uniqueIdentifier": accessory.uniqueIdentifier.uuidString,
            ] as [String: Any]
        }
    }

    // MARK: - Device State

    func getDeviceState(id: String?, name: String?, homeName: String?, roomName: String?) async throws -> [String: Any] {
        guard let accessory = resolveAccessory(id: id, name: name, homeName: homeName, roomName: roomName) else {
            throw HomeKitError.deviceNotFound(id ?? name ?? "unknown")
        }

        var properties: [String: Any] = [:]

        for service in accessory.services {
            for characteristic in service.characteristics {
                if characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                    do {
                        try await characteristic.readValue()
                        if let key = characteristicKey(for: characteristic),
                           let value = characteristic.value
                        {
                            properties[key] = formatValue(value, for: characteristic)
                        }
                    } catch {
                        Log.debug("Failed to read \(characteristic.characteristicType): \(error)")
                    }
                }
            }
        }

        return [
            "name": accessory.name,
            "room": accessory.room?.name ?? "Default Room",
            "home": homeNameForAccessory(accessory),
            "type": deviceType(for: accessory),
            "reachable": accessory.isReachable,
            "properties": properties,
        ] as [String: Any]
    }

    // MARK: - Device Control

    func controlDevice(
        id: String?,
        name: String?,
        homeName: String?,
        roomName: String?,
        action: String,
        value: Any?
    ) async throws -> [String: Any] {
        let identifier = id ?? name ?? "unknown"
        guard let accessory = resolveAccessory(id: id, name: name, homeName: homeName, roomName: roomName) else {
            throw HomeKitError.deviceNotFound(identifier)
        }
        guard accessory.isReachable else {
            throw HomeKitError.deviceUnreachable(identifier)
        }

        switch action.lowercased() {
        case "on":
            try await setPowerState(accessory: accessory, on: true)
        case "off":
            try await setPowerState(accessory: accessory, on: false)
        case "toggle":
            let currentState = try await getPowerState(accessory: accessory)
            try await setPowerState(accessory: accessory, on: !currentState)
        case "set_brightness":
            guard let brightness = intValue(value) else {
                throw HomeKitError.invalidValue("brightness requires an integer 0-100")
            }
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeBrightness,
                                        value: max(0, min(100, brightness)))
        case "set_hue":
            guard let hue = doubleValue(value) else {
                throw HomeKitError.invalidValue("hue requires a number 0-360")
            }
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeHue,
                                        value: max(0, min(360, hue)))
        case "set_saturation":
            guard let saturation = doubleValue(value) else {
                throw HomeKitError.invalidValue("saturation requires a number 0-100")
            }
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeSaturation,
                                        value: max(0, min(100, saturation)))
        case "set_color":
            guard let colorDict = value as? [String: Any],
                  let hue = doubleValue(colorDict["hue"]),
                  let saturation = doubleValue(colorDict["saturation"])
            else {
                throw HomeKitError.invalidValue("set_color requires {hue: 0-360, saturation: 0-100}")
            }
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeHue,
                                        value: max(0, min(360, hue)))
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeSaturation,
                                        value: max(0, min(100, saturation)))
        case "lock":
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeTargetLockMechanismState,
                                        value: HMCharacteristicValueLockMechanismState.secured.rawValue)
        case "unlock":
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeTargetLockMechanismState,
                                        value: HMCharacteristicValueLockMechanismState.unsecured.rawValue)
        case "open":
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeTargetDoorState,
                                        value: HMCharacteristicValueDoorState.open.rawValue)
        case "close":
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeTargetDoorState,
                                        value: HMCharacteristicValueDoorState.closed.rawValue)
        case "set_temperature":
            guard let temp = doubleValue(value) else {
                throw HomeKitError.invalidValue("set_temperature requires a number (celsius)")
            }
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeTargetTemperature,
                                        value: temp)
        case "set_thermostat_mode":
            guard let modeStr = value as? String else {
                throw HomeKitError.invalidValue("set_thermostat_mode requires: off, heat, cool, auto")
            }
            let mode: Int = switch modeStr.lowercased() {
            case "off": HMCharacteristicValueHeatingCooling.off.rawValue
            case "heat": HMCharacteristicValueHeatingCooling.heat.rawValue
            case "cool": HMCharacteristicValueHeatingCooling.cool.rawValue
            case "auto": HMCharacteristicValueHeatingCooling.auto.rawValue
            default: throw HomeKitError.invalidValue("Unknown mode: \(modeStr). Use off/heat/cool/auto")
            }
            try await setCharacteristic(accessory: accessory,
                                        type: HMCharacteristicTypeTargetHeatingCooling,
                                        value: mode)
        default:
            throw HomeKitError.unknownAction(action)
        }

        return [
            "success": true,
            "device": accessory.name,
            "action": action,
            "value": value ?? NSNull(),
        ] as [String: Any]
    }

    // MARK: - Batch Control

    func batchControlDevices(commands: [[String: Any]]) async -> [[String: Any]] {
        var results: [[String: Any]] = []
        for command in commands {
            let id = command["id"] as? String
            let name = command["name"] as? String
            guard id != nil || name != nil else {
                results.append(["success": false, "error": "Each command requires 'id' or 'name'"])
                continue
            }
            guard let action = command["action"] as? String else {
                results.append(["success": false, "device": id ?? name ?? "unknown", "error": "Missing required field: action"])
                continue
            }
            let home = command["home"] as? String
            let room = command["room"] as? String
            let value = command["value"]

            do {
                let result = try await controlDevice(id: id, name: name, homeName: home, roomName: room, action: action, value: value)
                results.append(result)
            } catch {
                results.append([
                    "success": false,
                    "device": id ?? name ?? "unknown",
                    "action": action,
                    "error": error.localizedDescription,
                ])
            }
        }
        return results
    }

    func batchGetDeviceState(devices: [[String: Any]]) async -> [[String: Any]] {
        var results: [[String: Any]] = []
        for device in devices {
            let id = device["id"] as? String
            let name = device["name"] as? String
            guard id != nil || name != nil else {
                results.append(["success": false, "error": "Each device requires 'id' or 'name'"])
                continue
            }
            let home = device["home"] as? String
            let room = device["room"] as? String

            do {
                var state = try await getDeviceState(id: id, name: name, homeName: home, roomName: room)
                state["success"] = true
                results.append(state)
            } catch {
                results.append([
                    "success": false,
                    "device": id ?? name ?? "unknown",
                    "error": error.localizedDescription,
                ])
            }
        }
        return results
    }

    func controlDevicesByFilter(
        homeName: String?,
        roomName: String?,
        type: String?,
        action: String,
        value: Any?
    ) async -> [[String: Any]] {
        let accessories = matchingAccessories(homeName: homeName, roomName: roomName)
        let filtered = accessories.filter { accessory in
            guard let type else { return true }
            return deviceType(for: accessory).lowercased() == type.lowercased()
        }

        if filtered.isEmpty {
            return [["success": false, "error": "No devices matched the given filters"]]
        }

        var results: [[String: Any]] = []
        for accessory in filtered {
            do {
                let result = try await controlDevice(
                    id: accessory.uniqueIdentifier.uuidString,
                    name: nil,
                    homeName: nil,
                    roomName: nil,
                    action: action,
                    value: value
                )
                results.append(result)
            } catch {
                results.append([
                    "success": false,
                    "device": accessory.name,
                    "action": action,
                    "error": error.localizedDescription,
                ])
            }
        }
        return results
    }

    // MARK: - Scenes

    func listScenes(homeName: String?) -> [[String: Any]] {
        let homes = matchingHomes(name: homeName)
        return homes.flatMap { home in
            home.actionSets.map { actionSet in
                var info: [String: Any] = [
                    "name": actionSet.name,
                    "home": home.name,
                    "uniqueIdentifier": actionSet.uniqueIdentifier.uuidString,
                    "actionCount": actionSet.actions.count,
                ]
                if let type = actionSetType(for: actionSet) {
                    info["type"] = type
                }
                return info
            }
        }
    }

    func executeScene(name: String?, homeName: String?, id: String?) async throws -> [String: Any] {
        guard let actionSet = resolveActionSet(name: name, homeName: homeName, id: id) else {
            throw HomeKitError.sceneNotFound(id ?? name ?? "unknown")
        }
        guard let home = homeForActionSet(actionSet) else {
            throw HomeKitError.sceneNotFound(id ?? name ?? "unknown")
        }

        try await home.executeActionSet(actionSet)

        return [
            "success": true,
            "scene": actionSet.name,
            "home": home.name,
        ] as [String: Any]
    }

    // MARK: - Room Management

    func addRoom(homeName: String?, name: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        let room = try await home.addRoom(named: name)
        return ["success": true, "name": room.name, "home": home.name] as [String: Any]
    }

    func renameRoom(homeName: String?, roomName: String, newName: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        guard let room = home.rooms.first(where: {
            $0.name.localizedCaseInsensitiveCompare(roomName) == .orderedSame
        }) else {
            throw HomeKitError.roomNotFound(roomName)
        }
        try await room.updateName(newName)
        return ["success": true, "oldName": roomName, "newName": newName, "home": home.name] as [String: Any]
    }

    func removeRoom(homeName: String?, roomName: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        guard let room = home.rooms.first(where: {
            $0.name.localizedCaseInsensitiveCompare(roomName) == .orderedSame
        }) else {
            throw HomeKitError.roomNotFound(roomName)
        }
        let movedAccessories = room.accessories.map { $0.name }
        try await home.removeRoom(room)
        return [
            "success": true,
            "room": roomName,
            "home": home.name,
            "movedAccessories": movedAccessories,
        ] as [String: Any]
    }

    func moveAccessoryToRoom(id: String?, name: String?, homeName: String?, roomName: String) async throws -> [String: Any] {
        guard let accessory = resolveAccessory(id: id, name: name, homeName: homeName, roomName: nil) else {
            throw HomeKitError.deviceNotFound(id ?? name ?? "unknown")
        }
        guard let manager = homeManager,
              let home = manager.homes.first(where: {
                  $0.accessories.contains(where: { $0.uniqueIdentifier == accessory.uniqueIdentifier })
              })
        else {
            throw HomeKitError.homeNotFound(homeName ?? "unknown")
        }
        guard let targetRoom = home.rooms.first(where: {
            $0.name.localizedCaseInsensitiveCompare(roomName) == .orderedSame
        }) else {
            throw HomeKitError.roomNotFound(roomName)
        }
        let fromRoom = accessory.room?.name ?? "Default Room"
        try await home.assignAccessory(accessory, to: targetRoom)
        return [
            "success": true,
            "accessory": accessory.name,
            "fromRoom": fromRoom,
            "toRoom": targetRoom.name,
        ] as [String: Any]
    }

    // MARK: - Zone Management

    func listZones(homeName: String?) -> [[String: Any]] {
        let homes = matchingHomes(name: homeName)
        return homes.flatMap { home in
            home.zones.map { zone in
                [
                    "name": zone.name,
                    "home": home.name,
                    "rooms": zone.rooms.map { $0.name },
                    "uniqueIdentifier": zone.uniqueIdentifier.uuidString,
                ] as [String: Any]
            }
        }
    }

    func addZone(homeName: String?, name: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        let zone = try await home.addZone(named: name)
        return ["success": true, "name": zone.name, "home": home.name] as [String: Any]
    }

    func renameZone(homeName: String?, zoneName: String, newName: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        guard let zone = home.zones.first(where: {
            $0.name.localizedCaseInsensitiveCompare(zoneName) == .orderedSame
        }) else {
            throw HomeKitError.zoneNotFound(zoneName)
        }
        try await zone.updateName(newName)
        return ["success": true, "oldName": zoneName, "newName": newName, "home": home.name] as [String: Any]
    }

    func removeZone(homeName: String?, zoneName: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        guard let zone = home.zones.first(where: {
            $0.name.localizedCaseInsensitiveCompare(zoneName) == .orderedSame
        }) else {
            throw HomeKitError.zoneNotFound(zoneName)
        }
        try await home.removeZone(zone)
        return ["success": true, "zone": zoneName, "home": home.name] as [String: Any]
    }

    func addRoomToZone(homeName: String?, zoneName: String, roomName: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        guard let zone = home.zones.first(where: {
            $0.name.localizedCaseInsensitiveCompare(zoneName) == .orderedSame
        }) else {
            throw HomeKitError.zoneNotFound(zoneName)
        }
        guard let room = home.rooms.first(where: {
            $0.name.localizedCaseInsensitiveCompare(roomName) == .orderedSame
        }) else {
            throw HomeKitError.roomNotFound(roomName)
        }
        try await zone.addRoom(room)
        return ["success": true, "zone": zone.name, "room": room.name, "home": home.name] as [String: Any]
    }

    func removeRoomFromZone(homeName: String?, zoneName: String, roomName: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        guard let zone = home.zones.first(where: {
            $0.name.localizedCaseInsensitiveCompare(zoneName) == .orderedSame
        }) else {
            throw HomeKitError.zoneNotFound(zoneName)
        }
        guard let room = home.rooms.first(where: {
            $0.name.localizedCaseInsensitiveCompare(roomName) == .orderedSame
        }) else {
            throw HomeKitError.roomNotFound(roomName)
        }
        try await zone.removeRoom(room)
        return ["success": true, "zone": zone.name, "room": room.name, "home": home.name] as [String: Any]
    }

    // MARK: - Accessory Management

    func renameAccessory(id: String?, name: String?, homeName: String?, roomName: String?, newName: String) async throws -> [String: Any] {
        guard let accessory = resolveAccessory(id: id, name: name, homeName: homeName, roomName: roomName) else {
            throw HomeKitError.deviceNotFound(id ?? name ?? "unknown")
        }
        let oldName = accessory.name
        try await accessory.updateName(newName)
        return ["success": true, "oldName": oldName, "newName": newName] as [String: Any]
    }

    func removeAccessory(id: String?, name: String?, homeName: String?, roomName: String?, confirm: Bool) async throws -> [String: Any] {
        guard let accessory = resolveAccessory(id: id, name: name, homeName: homeName, roomName: roomName) else {
            throw HomeKitError.deviceNotFound(id ?? name ?? "unknown")
        }
        guard confirm else {
            return [
                "success": false,
                "requiresConfirmation": true,
                "message": "This will permanently unpair '\(accessory.name)' from HomeKit. Pass confirm: true to proceed.",
            ] as [String: Any]
        }
        guard let manager = homeManager,
              let home = manager.homes.first(where: {
                  $0.accessories.contains(where: { $0.uniqueIdentifier == accessory.uniqueIdentifier })
              })
        else {
            throw HomeKitError.homeNotFound(homeName ?? "unknown")
        }
        let accessoryName = accessory.name
        let foundHomeName = home.name
        try await home.removeAccessory(accessory)
        return ["success": true, "accessory": accessoryName, "home": foundHomeName] as [String: Any]
    }

    func identifyAccessory(id: String?, name: String?, homeName: String?, roomName: String?) async throws -> [String: Any] {
        guard let accessory = resolveAccessory(id: id, name: name, homeName: homeName, roomName: roomName) else {
            throw HomeKitError.deviceNotFound(id ?? name ?? "unknown")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            accessory.identify { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        return ["success": true, "accessory": accessory.name] as [String: Any]
    }

    // MARK: - Scene Management (write/delete)

    func addScene(homeName: String?, name: String) async throws -> [String: Any] {
        let home = try resolveHome(name: homeName)
        let actionSet = try await home.addActionSet(named: name)
        return [
            "success": true,
            "name": actionSet.name,
            "home": home.name,
            "uniqueIdentifier": actionSet.uniqueIdentifier.uuidString,
        ] as [String: Any]
    }

    func renameScene(homeName: String?, name: String?, id: String?, newName: String) async throws -> [String: Any] {
        guard let actionSet = resolveActionSet(name: name, homeName: homeName, id: id) else {
            throw HomeKitError.sceneNotFound(id ?? name ?? "unknown")
        }
        let oldName = actionSet.name
        let foundHomeName = homeForActionSet(actionSet)?.name ?? "unknown"
        try await actionSet.updateName(newName)
        return ["success": true, "oldName": oldName, "newName": newName, "home": foundHomeName] as [String: Any]
    }

    func removeScene(homeName: String?, name: String?, id: String?) async throws -> [String: Any] {
        guard let actionSet = resolveActionSet(name: name, homeName: homeName, id: id) else {
            throw HomeKitError.sceneNotFound(id ?? name ?? "unknown")
        }
        guard let home = homeForActionSet(actionSet) else {
            throw HomeKitError.sceneNotFound(id ?? name ?? "unknown")
        }
        let sceneName = actionSet.name
        let foundHomeName = home.name
        try await home.removeActionSet(actionSet)
        return ["success": true, "scene": sceneName, "home": foundHomeName] as [String: Any]
    }

    // MARK: - Home Management

    func renameHome(homeName: String, newName: String) async throws -> [String: Any] {
        guard let manager = homeManager,
              let home = manager.homes.first(where: {
                  $0.name.localizedCaseInsensitiveCompare(homeName) == .orderedSame
              })
        else {
            throw HomeKitError.homeNotFound(homeName)
        }
        try await home.updateName(newName)
        return ["success": true, "oldName": homeName, "newName": newName] as [String: Any]
    }

    // MARK: - Backup / Restore

    func snapshotHome(homeName: String?) async throws -> HomeSnapshot {
        let home = try resolveHome(name: homeName)

        let rooms = home.rooms.map {
            RoomSnapshot(name: $0.name, uniqueIdentifier: $0.uniqueIdentifier.uuidString)
        }
        let zones = home.zones.map {
            ZoneSnapshot(name: $0.name, uniqueIdentifier: $0.uniqueIdentifier.uuidString,
                         rooms: $0.rooms.map { $0.name })
        }
        let accessories = home.accessories.map {
            AccessorySnapshot(uniqueIdentifier: $0.uniqueIdentifier.uuidString,
                              name: $0.name, room: $0.room?.name ?? "Default Room")
        }
        let scenes = home.actionSets
            .filter { $0.actionSetType == HMActionSetTypeUserDefined }
            .map { actionSet -> SceneSnapshot in
                let actions: [SceneAction] = actionSet.actions.compactMap { action in
                    guard let write = action as? HMCharacteristicWriteAction<NSCopying>,
                          let accUUID = write.characteristic.service?.accessory?.uniqueIdentifier
                    else { return nil }
                    return SceneAction(
                        accessory: accUUID.uuidString,
                        characteristicType: write.characteristic.characteristicType,
                        targetValue: Self.jsonValue(from: write.targetValue))
                }
                return SceneSnapshot(name: actionSet.name,
                                     uniqueIdentifier: actionSet.uniqueIdentifier.uuidString,
                                     actions: actions)
            }

        let iso = ISO8601DateFormatter()
        return HomeSnapshot(
            formatVersion: HomeSnapshot.currentFormatVersion,
            createdAt: iso.string(from: Date()),
            home: HomeSnapshot.HomeRef(name: home.name, uniqueIdentifier: home.uniqueIdentifier.uuidString),
            rooms: rooms, zones: zones, accessories: accessories, scenes: scenes)
    }

    /// Coerce a HomeKit characteristic value (NSNumber/NSString/Bool) to a JSONValue.
    private static func jsonValue(from value: Any?) -> JSONValue {
        switch value {
        case let n as NSNumber:
            // Bool is toll-free with NSNumber; distinguish it.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        default: return .null
        }
    }

    func restoreHome(backup: HomeSnapshot, confirm: Bool) async throws -> RestoreOutcome {
        guard backup.formatVersion == HomeSnapshot.currentFormatVersion else {
            throw HomeKitError.invalidValue("Unsupported backup formatVersion \(backup.formatVersion); expected \(HomeSnapshot.currentFormatVersion)")
        }
        // Resolve the target home: prefer the backup's home name, else primary.
        let current = try await snapshotHome(homeName: backup.home.name)
        let (plan, skipped) = RestorePlanner.plan(backup: backup, current: current)

        let summary = "\(plan.changeCount) change(s); skipped \(skipped.missingAccessories.count) missing accessor" +
            "\(skipped.missingAccessories.count == 1 ? "y" : "ies"), \(skipped.missingCharacteristics.count) scene action(s)"

        guard confirm else {
            return RestoreOutcome(dryRun: true, willApply: plan, skipped: skipped, summary: summary)
        }

        var failures: [String] = []
        let homeName = backup.home.name

        func attempt(_ label: String, _ op: () async throws -> Void) async {
            do { try await op() } catch { failures.append("\(label): \(error.localizedDescription)") }
        }

        for name in plan.createRooms { await attempt("createRoom \(name)") { _ = try await self.addRoom(homeName: homeName, name: name) } }
        for r in plan.renameRooms { await attempt("renameRoom \(r.from)->\(r.to)") { _ = try await self.renameRoom(homeName: homeName, roomName: r.from, newName: r.to) } }
        for m in plan.moveAccessories { await attempt("move \(m.accessory)") { _ = try await self.moveAccessoryToRoom(id: nil, name: m.accessory, homeName: homeName, roomName: m.toRoom) } }
        for r in plan.renameAccessories { await attempt("renameAccessory \(r.from)->\(r.to)") { _ = try await self.renameAccessory(id: nil, name: r.from, homeName: homeName, roomName: nil, newName: r.to) } }
        for name in plan.createZones { await attempt("createZone \(name)") { _ = try await self.addZone(homeName: homeName, name: name) } }
        for zr in plan.addRoomsToZones {
            for room in zr.rooms { await attempt("addRoomToZone \(zr.zone)/\(room)") { _ = try await self.addRoomToZone(homeName: homeName, zoneName: zr.zone, roomName: room) } }
        }
        for name in plan.createScenes { await attempt("createScene \(name)") { _ = try await self.addScene(homeName: homeName, name: name) } }

        // Scene actions: rebuild the action set to match the backup's applicable actions.
        for scenePlan in plan.setSceneActions {
            guard let backupScene = backup.scenes.first(where: { $0.name == scenePlan.scene }) else { continue }
            await attempt("setSceneActions \(scenePlan.scene)") {
                try await self.applySceneActions(homeName: homeName, scene: backupScene)
            }
        }

        return RestoreOutcome(dryRun: false, willApply: plan, skipped: skipped, summary: summary,
                              failures: failures.isEmpty ? nil : failures)
    }

    /// Replace an action set's characteristic-write actions to match the snapshot.
    /// Only actions whose accessory + characteristic still exist are written.
    private func applySceneActions(homeName: String?, scene: SceneSnapshot) async throws {
        guard let actionSet = resolveActionSet(name: scene.name, homeName: homeName, id: nil) else {
            throw HomeKitError.sceneNotFound(scene.name)
        }
        // Clear existing actions, then add the snapshot's.
        for action in actionSet.actions { try await actionSet.removeAction(action) }
        for sceneAction in scene.actions {
            guard let accessory = resolveAccessory(id: sceneAction.accessory, name: nil, homeName: homeName, roomName: nil),
                  let characteristic = accessory.services
                    .flatMap({ $0.characteristics })
                    .first(where: { $0.characteristicType == sceneAction.characteristicType })
            else { continue }  // accessory/characteristic gone — skip (already reported in plan/skipped)
            guard let targetValue = Self.coerce(sceneAction.targetValue, to: characteristic) else { continue }
            let write = HMCharacteristicWriteAction<NSCopying>(characteristic: characteristic, targetValue: targetValue)
            try await actionSet.addAction(write)
        }
    }

    /// Coerce a snapshot value to an NSCopying object matching the characteristic's HAP
    /// format, so integer characteristics (brightness, hue, …) receive NSNumber ints
    /// rather than the Doubles that JSON round-tripping produces.
    private static func coerce(_ value: JSONValue, to characteristic: HMCharacteristic) -> NSCopying? {
        switch value {
        case .number(let d):
            switch characteristic.metadata?.format {
            case HMCharacteristicMetadataFormatBool: return NSNumber(value: d != 0)
            case HMCharacteristicMetadataFormatFloat: return NSNumber(value: d)
            default: return NSNumber(value: Int(d))   // int / uint8 / uint16 / uint32 / uint64
            }
        case .bool(let b): return NSNumber(value: b)
        case .string(let s): return s as NSString
        case .null: return nil
        }
    }

    // MARK: - Private: Scene Helpers

    private func resolveActionSet(name: String?, homeName: String?, id: String?) -> HMActionSet? {
        if let id, let uuid = UUID(uuidString: id) {
            return findActionSetById(uuid)
        }
        if let name {
            return findActionSet(name: name, homeName: homeName)
        }
        return nil
    }

    private func findActionSetById(_ uuid: UUID) -> HMActionSet? {
        guard let manager = homeManager else { return nil }
        for home in manager.homes {
            if let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier == uuid }) {
                return actionSet
            }
        }
        return nil
    }

    private func findActionSet(name: String, homeName: String?) -> HMActionSet? {
        let homes = matchingHomes(name: homeName)
        for home in homes {
            if let actionSet = home.actionSets.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                return actionSet
            }
        }
        return nil
    }

    private func homeForActionSet(_ actionSet: HMActionSet) -> HMHome? {
        guard let manager = homeManager else { return nil }
        return manager.homes.first { home in
            home.actionSets.contains(where: { $0.uniqueIdentifier == actionSet.uniqueIdentifier })
        }
    }

    private func actionSetType(for actionSet: HMActionSet) -> String? {
        switch actionSet.actionSetType {
        case HMActionSetTypeWakeUp: return "wake_up"
        case HMActionSetTypeSleep: return "sleep"
        case HMActionSetTypeHomeDeparture: return "home_departure"
        case HMActionSetTypeHomeArrival: return "home_arrival"
        case HMActionSetTypeUserDefined: return "user_defined"
        default: return nil
        }
    }

    // MARK: - Private: Lookup Helpers

    private func resolveHome(name: String?) throws -> HMHome {
        guard let manager = homeManager else {
            throw HomeKitError.homeNotFound(name ?? "primary")
        }
        if let name {
            guard let home = manager.homes.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else {
                throw HomeKitError.homeNotFound(name)
            }
            return home
        }
        guard let home = manager.primaryHome ?? manager.homes.first else {
            throw HomeKitError.homeNotFound("primary")
        }
        return home
    }

    private func matchingHomes(name: String?) -> [HMHome] {
        guard let manager = homeManager else { return [] }
        if let name = name {
            return manager.homes.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }
        return manager.homes
    }

    private func matchingAccessories(homeName: String?, roomName: String?) -> [HMAccessory] {
        let homes = matchingHomes(name: homeName)
        var accessories: [HMAccessory] = []
        for home in homes {
            if let roomName = roomName {
                let rooms = home.rooms.filter {
                    $0.name.localizedCaseInsensitiveCompare(roomName) == .orderedSame
                }
                for room in rooms {
                    accessories.append(contentsOf: room.accessories)
                }
            } else {
                accessories.append(contentsOf: home.accessories)
            }
        }
        return accessories
    }

    private func findAccessory(name: String, homeName: String?, roomName: String?) -> HMAccessory? {
        let candidates = matchingAccessories(homeName: homeName, roomName: roomName)
        return candidates.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func findAccessoryById(_ id: String) -> HMAccessory? {
        guard let manager = homeManager, let uuid = UUID(uuidString: id) else { return nil }
        for home in manager.homes {
            if let accessory = home.accessories.first(where: { $0.uniqueIdentifier == uuid }) {
                return accessory
            }
        }
        return nil
    }

    private func resolveAccessory(id: String?, name: String?, homeName: String?, roomName: String?) -> HMAccessory? {
        if let id {
            return findAccessoryById(id)
        }
        if let name {
            return findAccessory(name: name, homeName: homeName, roomName: roomName)
        }
        return nil
    }

    private func homeNameForAccessory(_ accessory: HMAccessory) -> String {
        guard let manager = homeManager else { return "Unknown" }
        for home in manager.homes {
            if home.accessories.contains(where: { $0.uniqueIdentifier == accessory.uniqueIdentifier }) {
                return home.name
            }
        }
        return "Unknown"
    }

    // MARK: - Private: Characteristic Helpers

    private func findCharacteristic(accessory: HMAccessory, type: String) -> HMCharacteristic? {
        for service in accessory.services {
            for characteristic in service.characteristics where characteristic.characteristicType == type {
                return characteristic
            }
        }
        return nil
    }

    private func setCharacteristic(accessory: HMAccessory, type: String, value: Any) async throws {
        guard let characteristic = findCharacteristic(accessory: accessory, type: type) else {
            throw HomeKitError.characteristicNotFound(type)
        }
        guard characteristic.properties.contains(HMCharacteristicPropertyWritable) else {
            throw HomeKitError.characteristicReadOnly(type)
        }
        try await characteristic.writeValue(value)
    }

    private func setPowerState(accessory: HMAccessory, on: Bool) async throws {
        try await setCharacteristic(accessory: accessory,
                                    type: HMCharacteristicTypePowerState,
                                    value: on)
    }

    private func getPowerState(accessory: HMAccessory) async throws -> Bool {
        guard let characteristic = findCharacteristic(accessory: accessory, type: HMCharacteristicTypePowerState)
        else {
            throw HomeKitError.characteristicNotFound("power state")
        }
        try await characteristic.readValue()
        return characteristic.value as? Bool ?? false
    }

    // MARK: - Private: Type Detection

    private func deviceType(for accessory: HMAccessory) -> String {
        for service in accessory.services {
            switch service.serviceType {
            case HMServiceTypeLightbulb: return "light"
            case HMServiceTypeSwitch: return "switch"
            case HMServiceTypeOutlet: return "outlet"
            case HMServiceTypeFan: return "fan"
            case HMServiceTypeThermostat: return "thermostat"
            case HMServiceTypeLockMechanism: return "lock"
            case HMServiceTypeGarageDoorOpener: return "garage_door"
            case HMServiceTypeTemperatureSensor: return "temperature_sensor"
            case HMServiceTypeHumiditySensor: return "humidity_sensor"
            case HMServiceTypeMotionSensor: return "motion_sensor"
            case HMServiceTypeContactSensor: return "contact_sensor"
            case HMServiceTypeOccupancySensor: return "occupancy_sensor"
            case HMServiceTypeWindow: return "window"
            case HMServiceTypeWindowCovering: return "window_covering"
            case HMServiceTypeDoor: return "door"
            default: continue
            }
        }
        return "unknown"
    }

    // MARK: - Private: Value Formatting

    private func characteristicKey(for characteristic: HMCharacteristic) -> String? {
        switch characteristic.characteristicType {
        case HMCharacteristicTypePowerState: return "power"
        case HMCharacteristicTypeBrightness: return "brightness"
        case HMCharacteristicTypeHue: return "hue"
        case HMCharacteristicTypeSaturation: return "saturation"
        case HMCharacteristicTypeCurrentTemperature: return "currentTemperature"
        case HMCharacteristicTypeTargetTemperature: return "targetTemperature"
        case HMCharacteristicTypeCurrentRelativeHumidity: return "humidity"
        case HMCharacteristicTypeTargetHeatingCooling: return "thermostatMode"
        case HMCharacteristicTypeCurrentHeatingCooling: return "currentThermostatMode"
        case HMCharacteristicTypeCurrentLockMechanismState: return "lockState"
        case HMCharacteristicTypeTargetLockMechanismState: return "lockTargetState"
        case HMCharacteristicTypeCurrentDoorState: return "doorState"
        case HMCharacteristicTypeTargetDoorState: return "doorTargetState"
        case HMCharacteristicTypeMotionDetected: return "motionDetected"
        case HMCharacteristicTypeContactState: return "contactState"
        case HMCharacteristicTypeOccupancyDetected: return "occupancyDetected"
        case HMCharacteristicTypeRotationSpeed: return "fanSpeed"
        case HMCharacteristicTypeName: return nil  // skip, already in top-level
        default: return nil
        }
    }

    private func formatValue(_ value: Any, for characteristic: HMCharacteristic) -> Any {
        switch characteristic.characteristicType {
        case HMCharacteristicTypeCurrentLockMechanismState:
            guard let raw = value as? Int else { return value }
            return switch raw {
            case HMCharacteristicValueLockMechanismState.unsecured.rawValue: "unlocked"
            case HMCharacteristicValueLockMechanismState.secured.rawValue: "locked"
            case HMCharacteristicValueLockMechanismState.jammed.rawValue: "jammed"
            case HMCharacteristicValueLockMechanismState.unknown.rawValue: "unknown"
            default: "unknown"
            }
        case HMCharacteristicTypeCurrentDoorState:
            guard let raw = value as? Int else { return value }
            return switch raw {
            case HMCharacteristicValueDoorState.open.rawValue: "open"
            case HMCharacteristicValueDoorState.closed.rawValue: "closed"
            case HMCharacteristicValueDoorState.opening.rawValue: "opening"
            case HMCharacteristicValueDoorState.closing.rawValue: "closing"
            case HMCharacteristicValueDoorState.stopped.rawValue: "stopped"
            default: "unknown"
            }
        case HMCharacteristicTypeTargetHeatingCooling, HMCharacteristicTypeCurrentHeatingCooling:
            guard let raw = value as? Int else { return value }
            return switch raw {
            case HMCharacteristicValueHeatingCooling.off.rawValue: "off"
            case HMCharacteristicValueHeatingCooling.heat.rawValue: "heat"
            case HMCharacteristicValueHeatingCooling.cool.rawValue: "cool"
            case HMCharacteristicValueHeatingCooling.auto.rawValue: "auto"
            default: "unknown"
            }
        default:
            return value
        }
    }

    // MARK: - Private: Value Conversion

    private func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String, let i = Int(s) { return i }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String, let d = Double(s) { return d }
        return nil
    }
}

// MARK: - HomeKitProviding

extension HomeKitManager: HomeKitProviding {}

// MARK: - HMHomeManagerDelegate

extension HomeKitManager: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            Log.info("HomeKitManager: homes updated (\(manager.homes.count) home(s))")
            self.markReady()
        }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in
            let authorized = status.contains(.authorized)
            let determined = status.contains(.determined)
            Log.info("HomeKitManager: authorization status (authorized=\(authorized), determined=\(determined))")
            // A determined-but-denied status will never yield homes, so fail fast
            // rather than waiting out the timeout. Undetermined (prompt pending) is
            // left to the timeout, since it may still resolve if the user responds.
            if determined && !authorized {
                Log.error("HomeKitManager: HomeKit access denied or restricted. Enable it in System Settings > Privacy & Security > HomeKit, then restart the server.")
                self.resolve(ready: false)
            }
        }
    }
}

// MARK: - Errors

enum HomeKitError: LocalizedError {
    case deviceNotFound(String)
    case deviceUnreachable(String)
    case characteristicNotFound(String)
    case characteristicReadOnly(String)
    case invalidValue(String)
    case unknownAction(String)
    case sceneNotFound(String)
    case roomNotFound(String)
    case zoneNotFound(String)
    case homeNotFound(String)
    case sceneAlreadyExists(String)
    case cannotRemoveDefaultRoom

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let name): "Device '\(name)' not found"
        case .deviceUnreachable(let name): "Device '\(name)' is not reachable"
        case .characteristicNotFound(let type): "Characteristic '\(type)' not found on device"
        case .characteristicReadOnly(let type): "Characteristic '\(type)' is read-only"
        case .invalidValue(let msg): "Invalid value: \(msg)"
        case .unknownAction(let action): "Unknown action: '\(action)'"
        case .sceneNotFound(let name): "Scene '\(name)' not found"
        case .roomNotFound(let name): "Room '\(name)' not found"
        case .zoneNotFound(let name): "Zone '\(name)' not found"
        case .homeNotFound(let name): "Home '\(name)' not found"
        case .sceneAlreadyExists(let name): "Scene '\(name)' already exists"
        case .cannotRemoveDefaultRoom: "Cannot remove the default room"
        }
    }
}
