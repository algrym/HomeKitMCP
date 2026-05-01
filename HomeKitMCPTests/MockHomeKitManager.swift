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

    // MARK: - Error stubs

    var getDeviceStateError: Error?
    var controlDeviceError: Error?
    var executeSceneError: Error?
    var addRoomError: Error?
    var renameRoomError: Error?
    var removeRoomError: Error?
    var moveAccessoryToRoomError: Error?

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
}
