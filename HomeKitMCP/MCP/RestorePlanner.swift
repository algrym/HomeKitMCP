import Foundation

/// A merge plan describing the additive changes needed to bring `current`
/// state back in line with a `HomeSnapshot` backup. Never destructive: it
/// only creates, renames, moves, or adds — it never deletes or removes.
nonisolated struct RestorePlan: Codable, Equatable {
    nonisolated struct Rename: Codable, Equatable { let from: String; let to: String }
    // Accessory renames/moves carry the accessory's UUID so apply resolves the exact
    // object rather than a namesake — HomeKit permits duplicate accessory names.
    nonisolated struct AccessoryRename: Codable, Equatable { let from: String; let to: String; let uuid: String }
    nonisolated struct Move: Codable, Equatable { let accessory: String; let uuid: String; let fromRoom: String; let toRoom: String }
    nonisolated struct ZoneRooms: Codable, Equatable { let zone: String; let rooms: [String] }
    nonisolated struct SceneActionsPlan: Codable, Equatable { let scene: String; let actionCount: Int }

    var createRooms: [String] = []
    var renameRooms: [Rename] = []
    var moveAccessories: [Move] = []
    var renameAccessories: [AccessoryRename] = []
    var createZones: [String] = []
    var renameZones: [Rename] = []
    var addRoomsToZones: [ZoneRooms] = []
    var createScenes: [String] = []
    var renameScenes: [Rename] = []
    var setSceneActions: [SceneActionsPlan] = []

    var changeCount: Int {
        createRooms.count + renameRooms.count + moveAccessories.count + renameAccessories.count
        + createZones.count + renameZones.count + addRoomsToZones.count
        + createScenes.count + renameScenes.count + setSceneActions.count
    }
    var isEmpty: Bool { changeCount == 0 }
}

/// Items from the backup that could not be planned because their referenced
/// HomeKit object no longer exists in the current home.
nonisolated struct RestoreSkipped: Codable, Equatable {
    nonisolated struct MissingCharacteristic: Codable, Equatable {
        let scene: String; let accessory: String; let characteristicType: String
    }
    var missingAccessories: [String] = []
    var missingCharacteristics: [MissingCharacteristic] = []
}

/// Outcome of a `restore_home` MCP tool call: the plan that was (or would be)
/// applied, anything skipped, a human-readable summary, and any failures
/// encountered while applying (nil/empty on a dry run or full success).
nonisolated struct RestoreOutcome: Codable, Equatable {
    let dryRun: Bool
    let willApply: RestorePlan
    let skipped: RestoreSkipped
    let summary: String
    var failures: [String]? = nil
}

/// Pure diff/merge logic: compares a backup `HomeSnapshot` against the
/// current live snapshot and produces an additive `RestorePlan` plus a
/// `RestoreSkipped` record of anything that couldn't be matched. No HomeKit
/// access here — this is intentionally free of side effects so it can be
/// unit tested without a real home.
nonisolated enum RestorePlanner {
    static func plan(backup: HomeSnapshot, current: HomeSnapshot) -> (plan: RestorePlan, skipped: RestoreSkipped) {
        var plan = RestorePlan()
        var skipped = RestoreSkipped()

        // Indexes of current state
        let curRoomsByUUID = Dictionary(current.rooms.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let curRoomNames = Set(current.rooms.map { $0.name.lowercased() })
        let curAccByUUID = Dictionary(current.accessories.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let curZonesByUUID = Dictionary(current.zones.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let curZonesByName = Dictionary(current.zones.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let curScenesByUUID = Dictionary(current.scenes.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let curScenesByName = Dictionary(current.scenes.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let presentAccessoryUUIDs = Set(current.accessories.map { $0.uniqueIdentifier })

        // Rooms: create-missing (by uuid then name) or rename-back
        for room in backup.rooms {
            if let cur = curRoomsByUUID[room.uniqueIdentifier] {
                if cur.name != room.name { plan.renameRooms.append(.init(from: cur.name, to: room.name)) }
            } else if !curRoomNames.contains(room.name.lowercased()) {
                plan.createRooms.append(room.name)
            }
        }

        // Accessories: match by uuid only (never create); move + rename
        for acc in backup.accessories {
            guard let cur = curAccByUUID[acc.uniqueIdentifier] else {
                skipped.missingAccessories.append(acc.name)
                continue
            }
            if cur.room.lowercased() != acc.room.lowercased() {
                plan.moveAccessories.append(.init(accessory: acc.name, uuid: acc.uniqueIdentifier, fromRoom: cur.room, toRoom: acc.room))
            }
            if cur.name != acc.name {
                plan.renameAccessories.append(.init(from: cur.name, to: acc.name, uuid: acc.uniqueIdentifier))
            }
        }

        // Zones: create-missing or rename-back; add missing memberships (additive)
        for zone in backup.zones {
            if let curByUUID = curZonesByUUID[zone.uniqueIdentifier] {
                if curByUUID.name != zone.name { plan.renameZones.append(.init(from: curByUUID.name, to: zone.name)) }
                let have = Set(curByUUID.rooms.map { $0.lowercased() })
                let missing = zone.rooms.filter { !have.contains($0.lowercased()) }
                if !missing.isEmpty { plan.addRoomsToZones.append(.init(zone: zone.name, rooms: missing)) }
            } else if let cur = curZonesByName[zone.name.lowercased()] {
                // Name-only match: the name already agrees, so no rename is needed.
                let have = Set(cur.rooms.map { $0.lowercased() })
                let missing = zone.rooms.filter { !have.contains($0.lowercased()) }
                if !missing.isEmpty { plan.addRoomsToZones.append(.init(zone: zone.name, rooms: missing)) }
            } else {
                plan.createZones.append(zone.name)
                if !zone.rooms.isEmpty { plan.addRoomsToZones.append(.init(zone: zone.name, rooms: zone.rooms)) }
            }
        }

        // Scenes: create-missing or rename-back; set actions only when the applicable action set differs
        // HMActionSet.actions is an unordered NSSet, so compare action lists by a canonical
        // sort rather than array order to avoid spurious re-planning across launches.
        func canon(_ a: [SceneAction]) -> [SceneAction] {
            a.sorted { ($0.accessory, $0.characteristicType) < ($1.accessory, $1.characteristicType) }
        }
        for scene in backup.scenes {
            let existingByUUID = curScenesByUUID[scene.uniqueIdentifier]
            let existing = existingByUUID ?? curScenesByName[scene.name.lowercased()]
            if existing == nil {
                plan.createScenes.append(scene.name)
            } else if let existingByUUID, existingByUUID.name != scene.name {
                plan.renameScenes.append(.init(from: existingByUUID.name, to: scene.name))
            }
            // applicable actions = those whose accessory is still present
            var applicable: [SceneAction] = []
            for action in scene.actions {
                if presentAccessoryUUIDs.contains(action.accessory) {
                    applicable.append(action)
                } else {
                    skipped.missingCharacteristics.append(.init(scene: scene.name, accessory: action.accessory, characteristicType: action.characteristicType))
                }
            }
            let currentActions = existing?.actions ?? []
            if canon(applicable) != canon(currentActions) && !applicable.isEmpty {
                plan.setSceneActions.append(.init(scene: scene.name, actionCount: applicable.count))
            }
        }

        return (plan, skipped)
    }
}
