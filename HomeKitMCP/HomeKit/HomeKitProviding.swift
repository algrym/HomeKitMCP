import Foundation

@MainActor
protocol HomeKitProviding {
    func start() async
    func listHomes() -> [[String: Any]]
    func listRooms(homeName: String?) -> [[String: Any]]
    func listDevices(homeName: String?, roomName: String?, type: String?) -> [[String: Any]]
    func getDeviceState(id: String?, name: String?, homeName: String?, roomName: String?) async throws -> [String: Any]
    func controlDevice(id: String?, name: String?, homeName: String?, roomName: String?, action: String, value: Any?) async throws -> [String: Any]
    func batchControlDevices(commands: [[String: Any]]) async -> [[String: Any]]
    func batchGetDeviceState(devices: [[String: Any]]) async -> [[String: Any]]
    func controlDevicesByFilter(homeName: String?, roomName: String?, type: String?, action: String, value: Any?) async -> [[String: Any]]
    func listScenes(homeName: String?) -> [[String: Any]]
    func executeScene(name: String?, homeName: String?, id: String?) async throws -> [String: Any]
    func addRoom(homeName: String?, name: String) async throws -> [String: Any]
    func renameRoom(homeName: String?, roomName: String, newName: String) async throws -> [String: Any]
    func removeRoom(homeName: String?, roomName: String) async throws -> [String: Any]
    func moveAccessoryToRoom(id: String?, name: String?, homeName: String?, roomName: String) async throws -> [String: Any]
}
