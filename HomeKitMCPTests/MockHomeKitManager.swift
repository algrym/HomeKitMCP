import Foundation
@testable import HomeKitMCP

@MainActor
final class MockHomeKitManager: HomeKitProviding {
    // MARK: - Stub data

    var stubbedHomes: [[String: Any]] = []
    var stubbedRooms: [[String: Any]] = []
    var stubbedDevices: [[String: Any]] = []
    var stubbedDeviceState: [String: Any] = [:]
    var stubbedControlResult: [String: Any] = [:]

    var stubbedBatchControlResult: [[String: Any]] = []
    var stubbedBatchGetDeviceStateResult: [[String: Any]] = []
    var stubbedControlByFilterResult: [[String: Any]] = []
    var stubbedScenes: [[String: Any]] = []
    var stubbedExecuteSceneResult: [String: Any] = [:]
    var stubbedAddRoomResult: [String: Any] = [:]
    var stubbedRenameRoomResult: [String: Any] = [:]
    var stubbedRemoveRoomResult: [String: Any] = [:]
    var stubbedMoveAccessoryToRoomResult: [String: Any] = [:]
    var stubbedZones: [[String: Any]] = []
    var stubbedAddZoneResult: [String: Any] = [:]
    var stubbedRenameZoneResult: [String: Any] = [:]
    var stubbedRemoveZoneResult: [String: Any] = [:]
    var stubbedAddRoomToZoneResult: [String: Any] = [:]
    var stubbedRemoveRoomFromZoneResult: [String: Any] = [:]
    var stubbedRenameAccessoryResult: [String: Any] = [:]
    var stubbedRemoveAccessoryResult: [String: Any] = [:]
    var stubbedIdentifyAccessoryResult: [String: Any] = [:]
    var stubbedAddSceneResult: [String: Any] = [:]
    var stubbedRenameSceneResult: [String: Any] = [:]
    var stubbedRemoveSceneResult: [String: Any] = [:]
    var stubbedRenameHomeResult: [String: Any] = [:]

    // MARK: - Error stubs

    var getDeviceStateError: Error?
    var controlDeviceError: Error?
    var executeSceneError: Error?
    var addRoomError: Error?
    var renameRoomError: Error?
    var removeRoomError: Error?
    var moveAccessoryToRoomError: Error?
    var addZoneError: Error?
    var renameZoneError: Error?
    var removeZoneError: Error?
    var addRoomToZoneError: Error?
    var removeRoomFromZoneError: Error?
    var renameAccessoryError: Error?
    var removeAccessoryError: Error?
    var identifyAccessoryError: Error?
    var addSceneError: Error?
    var renameSceneError: Error?
    var removeSceneError: Error?
    var renameHomeError: Error?

    // MARK: - Call recording

    var startCalled = false
    var listHomesCalled = false
    var listRoomsCalledWith: String??
    var listDevicesCalledWith: (homeName: String?, roomName: String?, type: String?)?
    var getDeviceStateCalledWith: (id: String?, name: String?, homeName: String?, roomName: String?)?
    var controlDeviceCalledWith: (id: String?, name: String?, homeName: String?, roomName: String?, action: String, value: Any?)?
    var batchControlDevicesCalledWith: [[String: Any]]?
    var batchGetDeviceStateCalledWith: [[String: Any]]?
    var controlDevicesByFilterCalledWith: (homeName: String?, roomName: String?, type: String?, action: String, value: Any?)?
    var listScenesCalledWith: String??
    var executeSceneCalledWith: (name: String?, homeName: String?, id: String?)?
    var addRoomCalledWith: (homeName: String?, name: String)?
    var renameRoomCalledWith: (homeName: String?, roomName: String, newName: String)?
    var removeRoomCalledWith: (homeName: String?, roomName: String)?
    var moveAccessoryToRoomCalledWith: (id: String?, name: String?, homeName: String?, roomName: String)?
    var listZonesCalledWith: String??
    var addZoneCalledWith: (homeName: String?, name: String)?
    var renameZoneCalledWith: (homeName: String?, zoneName: String, newName: String)?
    var removeZoneCalledWith: (homeName: String?, zoneName: String)?
    var addRoomToZoneCalledWith: (homeName: String?, zoneName: String, roomName: String)?
    var removeRoomFromZoneCalledWith: (homeName: String?, zoneName: String, roomName: String)?
    var renameAccessoryCalledWith: (id: String?, name: String?, homeName: String?, roomName: String?, newName: String)?
    var removeAccessoryCalledWith: (id: String?, name: String?, homeName: String?, roomName: String?, confirm: Bool)?
    var identifyAccessoryCalledWith: (id: String?, name: String?, homeName: String?, roomName: String?)?
    var addSceneCalledWith: (homeName: String?, name: String)?
    var renameSceneCalledWith: (homeName: String?, name: String?, id: String?, newName: String)?
    var removeSceneCalledWith: (homeName: String?, name: String?, id: String?)?
    var renameHomeCalledWith: (homeName: String, newName: String)?

    // MARK: - Protocol conformance

    func start() async {
        startCalled = true
    }

    func listHomes() -> [[String: Any]] {
        listHomesCalled = true
        return stubbedHomes
    }

    func listRooms(homeName: String?) -> [[String: Any]] {
        listRoomsCalledWith = .some(homeName)
        return stubbedRooms
    }

    func listDevices(homeName: String?, roomName: String?, type: String?) -> [[String: Any]] {
        listDevicesCalledWith = (homeName, roomName, type)
        return stubbedDevices
    }

    func getDeviceState(id: String?, name: String?, homeName: String?, roomName: String?) async throws -> [String: Any] {
        getDeviceStateCalledWith = (id, name, homeName, roomName)
        if let error = getDeviceStateError { throw error }
        return stubbedDeviceState
    }

    func controlDevice(
        id: String?,
        name: String?,
        homeName: String?,
        roomName: String?,
        action: String,
        value: Any?
    ) async throws -> [String: Any] {
        controlDeviceCalledWith = (id, name, homeName, roomName, action, value)
        if let error = controlDeviceError { throw error }
        return stubbedControlResult
    }

    func batchControlDevices(commands: [[String: Any]]) async -> [[String: Any]] {
        batchControlDevicesCalledWith = commands
        return stubbedBatchControlResult
    }

    func batchGetDeviceState(devices: [[String: Any]]) async -> [[String: Any]] {
        batchGetDeviceStateCalledWith = devices
        return stubbedBatchGetDeviceStateResult
    }

    func controlDevicesByFilter(
        homeName: String?,
        roomName: String?,
        type: String?,
        action: String,
        value: Any?
    ) async -> [[String: Any]] {
        controlDevicesByFilterCalledWith = (homeName, roomName, type, action, value)
        return stubbedControlByFilterResult
    }

    func listScenes(homeName: String?) -> [[String: Any]] {
        listScenesCalledWith = .some(homeName)
        return stubbedScenes
    }

    func executeScene(name: String?, homeName: String?, id: String?) async throws -> [String: Any] {
        executeSceneCalledWith = (name, homeName, id)
        if let error = executeSceneError { throw error }
        return stubbedExecuteSceneResult
    }

    func addRoom(homeName: String?, name: String) async throws -> [String: Any] {
        addRoomCalledWith = (homeName, name)
        if let error = addRoomError { throw error }
        return stubbedAddRoomResult
    }

    func renameRoom(homeName: String?, roomName: String, newName: String) async throws -> [String: Any] {
        renameRoomCalledWith = (homeName, roomName, newName)
        if let error = renameRoomError { throw error }
        return stubbedRenameRoomResult
    }

    func removeRoom(homeName: String?, roomName: String) async throws -> [String: Any] {
        removeRoomCalledWith = (homeName, roomName)
        if let error = removeRoomError { throw error }
        return stubbedRemoveRoomResult
    }

    func moveAccessoryToRoom(id: String?, name: String?, homeName: String?, roomName: String) async throws -> [String: Any] {
        moveAccessoryToRoomCalledWith = (id, name, homeName, roomName)
        if let error = moveAccessoryToRoomError { throw error }
        return stubbedMoveAccessoryToRoomResult
    }

    func listZones(homeName: String?) -> [[String: Any]] {
        listZonesCalledWith = .some(homeName)
        return stubbedZones
    }

    func addZone(homeName: String?, name: String) async throws -> [String: Any] {
        addZoneCalledWith = (homeName, name)
        if let error = addZoneError { throw error }
        return stubbedAddZoneResult
    }

    func renameZone(homeName: String?, zoneName: String, newName: String) async throws -> [String: Any] {
        renameZoneCalledWith = (homeName, zoneName, newName)
        if let error = renameZoneError { throw error }
        return stubbedRenameZoneResult
    }

    func removeZone(homeName: String?, zoneName: String) async throws -> [String: Any] {
        removeZoneCalledWith = (homeName, zoneName)
        if let error = removeZoneError { throw error }
        return stubbedRemoveZoneResult
    }

    func addRoomToZone(homeName: String?, zoneName: String, roomName: String) async throws -> [String: Any] {
        addRoomToZoneCalledWith = (homeName, zoneName, roomName)
        if let error = addRoomToZoneError { throw error }
        return stubbedAddRoomToZoneResult
    }

    func removeRoomFromZone(homeName: String?, zoneName: String, roomName: String) async throws -> [String: Any] {
        removeRoomFromZoneCalledWith = (homeName, zoneName, roomName)
        if let error = removeRoomFromZoneError { throw error }
        return stubbedRemoveRoomFromZoneResult
    }

    func renameAccessory(id: String?, name: String?, homeName: String?, roomName: String?, newName: String) async throws -> [String: Any] {
        renameAccessoryCalledWith = (id, name, homeName, roomName, newName)
        if let error = renameAccessoryError { throw error }
        return stubbedRenameAccessoryResult
    }

    func removeAccessory(id: String?, name: String?, homeName: String?, roomName: String?, confirm: Bool) async throws -> [String: Any] {
        removeAccessoryCalledWith = (id, name, homeName, roomName, confirm)
        if let error = removeAccessoryError { throw error }
        return stubbedRemoveAccessoryResult
    }

    func identifyAccessory(id: String?, name: String?, homeName: String?, roomName: String?) async throws -> [String: Any] {
        identifyAccessoryCalledWith = (id, name, homeName, roomName)
        if let error = identifyAccessoryError { throw error }
        return stubbedIdentifyAccessoryResult
    }

    func addScene(homeName: String?, name: String) async throws -> [String: Any] {
        addSceneCalledWith = (homeName, name)
        if let error = addSceneError { throw error }
        return stubbedAddSceneResult
    }

    func renameScene(homeName: String?, name: String?, id: String?, newName: String) async throws -> [String: Any] {
        renameSceneCalledWith = (homeName, name, id, newName)
        if let error = renameSceneError { throw error }
        return stubbedRenameSceneResult
    }

    func removeScene(homeName: String?, name: String?, id: String?) async throws -> [String: Any] {
        removeSceneCalledWith = (homeName, name, id)
        if let error = removeSceneError { throw error }
        return stubbedRemoveSceneResult
    }

    func renameHome(homeName: String, newName: String) async throws -> [String: Any] {
        renameHomeCalledWith = (homeName, newName)
        if let error = renameHomeError { throw error }
        return stubbedRenameHomeResult
    }
}
