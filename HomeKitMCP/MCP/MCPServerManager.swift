import Combine
import Dispatch
import Foundation
import MCP

@MainActor
final class MCPServerManager: ObservableObject {
    private var server: Server?
    private var serverTask: Task<Void, Never>?
    private let homeKitManager: HomeKitProviding
    private var signalSources: [DispatchSourceSignal] = []

    init(homeKitManager: HomeKitProviding? = nil, startServer: Bool = true) {
        self.homeKitManager = homeKitManager ?? HomeKitManager()
        if startServer {
            serverTask = Task {
                await self.startServer()
            }
        }
    }

    func startServer() async {
        setupSignalHandlers()
        Log.info("Starting HomeKit MCP server...")

        // Create MCP server
        let server = Server(
            name: "HomeKitMCP",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        self.server = server

        // Register tool handlers
        await registerToolHandlers(server: server)

        // Initialize HomeKit in the background — do NOT block transport startup on it.
        // HomeKit can be slow, unauthorized, or (when launched headless from a pipe)
        // never report in. Blocking here starves the transport and, worse, prevents us
        // from ever reaching waitUntilCompleted(), so stdin-close never exits the
        // process — that is how orphaned instances pile up. Tool calls await readiness
        // individually via waitUntilReady().
        Task { await homeKitManager.start() }

        // Start transport
        let transport = StdioTransport()
        do {
            try await server.start(transport: transport)
            Log.info("MCP server started on stdio")
            await server.waitUntilCompleted()
            Log.info("MCP server stopped (stdin closed), exiting process")
            exit(0)
        } catch {
            if Task.isCancelled {
                Log.info("MCP server task cancelled")
            } else {
                Log.error("MCP server failed: \(error)")
            }
            exit(1)
        }
    }

    // MARK: - Signal Handling

    private func setupSignalHandlers() {
        // Ignore default signal behavior so we can handle them ourselves
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

        sigintSource.setEventHandler { [weak self] in
            Log.info("Received SIGINT, shutting down…")
            guard let self else { return }
            Task { @MainActor in await self.shutdown() }
        }

        sigtermSource.setEventHandler { [weak self] in
            Log.info("Received SIGTERM, shutting down…")
            guard let self else { return }
            Task { @MainActor in await self.shutdown() }
        }

        sigintSource.resume()
        sigtermSource.resume()

        signalSources = [sigintSource, sigtermSource]
    }

    // MARK: - Shutdown

    func shutdown() async {
        Log.info("Graceful shutdown started…")

        if let server {
            await server.stop()
            Log.info("MCP server stopped cleanly")
        }

        serverTask?.cancel()
        serverTask = nil

        Log.info("Graceful shutdown complete, exiting process")
        exit(0)
    }

    private func registerToolHandlers(server: Server) async {
        let allTools = ToolDefinitions.all
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: allTools)
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(content: [.text("Server shutting down")], isError: true)
            }
            return await self.handleToolCall(params)
        }
    }

    func handleToolCall(_ params: CallTool.Parameters) async -> CallTool.Result {
        // Every tool needs HomeKit. Wait (bounded) for it to be ready; return a clear,
        // actionable error rather than hanging or silently reporting no devices.
        guard await homeKitManager.waitUntilReady() else {
            return CallTool.Result(
                content: [.text("HomeKit is not available. Grant HomeKit access to HomeKitMCP in System Settings > Privacy & Security > HomeKit, make sure at least one home exists in the Home app, then restart the server.")],
                isError: true
            )
        }
        do {
            let args = params.arguments ?? [:]
            let result: Any

            switch params.name {
            case "list_homes":
                result = homeKitManager.listHomes()
                Log.info("Got [list_homes] result: \(result)")

            case "list_rooms":
                let home = args["home"]?.stringValue
                result = homeKitManager.listRooms(homeName: home)
                
                Log.info("Got [list_rooms] for home \(String(describing: home)) result: \(result)")

            case "list_devices":
                let home = args["home"]?.stringValue
                let room = args["room"]?.stringValue
                let type = args["type"]?.stringValue
                result = homeKitManager.listDevices(homeName: home, roomName: room, type: type)
                
                Log.info("Got [list_devices] for home \(String(describing: home)), room \(String(describing: room)), type \(String(describing: type)) result: \(result)")

            case "get_device_state":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                let home = args["home"]?.stringValue
                let room = args["room"]?.stringValue
                result = try await homeKitManager.getDeviceState(id: id, name: name, homeName: home, roomName: room)

            case "control_device":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                guard let action = args["action"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
                }
                let home = args["home"]?.stringValue
                let room = args["room"]?.stringValue
                let value = args["value"].map { convertValue($0) }
                result = try await homeKitManager.controlDevice(
                    id: id, name: name, homeName: home, roomName: room,
                    action: action, value: value
                )

            case "batch_control_devices":
                guard let commandValues = args["commands"]?.arrayValue, !commandValues.isEmpty else {
                    return CallTool.Result(content: [.text("Missing or empty required parameter: commands")], isError: true)
                }
                let commands = commandValues.map { convertValue($0) as? [String: Any] ?? [:] }
                result = await homeKitManager.batchControlDevices(commands: commands)

            case "batch_get_device_state":
                guard let deviceValues = args["devices"]?.arrayValue, !deviceValues.isEmpty else {
                    return CallTool.Result(content: [.text("Missing or empty required parameter: devices")], isError: true)
                }
                let devices = deviceValues.map { convertValue($0) as? [String: Any] ?? [:] }
                result = await homeKitManager.batchGetDeviceState(devices: devices)

            case "control_devices_by_filter":
                guard let action = args["action"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
                }
                let home = args["home"]?.stringValue
                let room = args["room"]?.stringValue
                let type = args["type"]?.stringValue
                guard home != nil || room != nil || type != nil else {
                    return CallTool.Result(content: [.text("At least one filter (home, room, or type) is required")], isError: true)
                }
                let value = args["value"].map { convertValue($0) }
                result = await homeKitManager.controlDevicesByFilter(
                    homeName: home, roomName: room, type: type,
                    action: action, value: value
                )

            case "list_scenes":
                let home = args["home"]?.stringValue
                result = homeKitManager.listScenes(homeName: home)
                Log.info("Got [list_scenes] for home \(String(describing: home)) result: \(result)")

            case "execute_scene":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.executeScene(name: name, homeName: home, id: id)

            case "add_room":
                guard let name = args["name"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: name")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.addRoom(homeName: home, name: name)

            case "rename_room":
                guard let room = args["room"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: room")], isError: true)
                }
                guard let newName = args["newName"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: newName")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.renameRoom(homeName: home, roomName: room, newName: newName)

            case "remove_room":
                guard let room = args["room"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: room")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.removeRoom(homeName: home, roomName: room)

            case "move_accessory_to_room":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                guard let room = args["room"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: room")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.moveAccessoryToRoom(id: id, name: name, homeName: home, roomName: room)

            case "list_zones":
                let home = args["home"]?.stringValue
                result = homeKitManager.listZones(homeName: home)

            case "add_zone":
                guard let name = args["name"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: name")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.addZone(homeName: home, name: name)

            case "rename_zone":
                guard let zone = args["zone"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: zone")], isError: true)
                }
                guard let newName = args["newName"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: newName")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.renameZone(homeName: home, zoneName: zone, newName: newName)

            case "remove_zone":
                guard let zone = args["zone"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: zone")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.removeZone(homeName: home, zoneName: zone)

            case "add_room_to_zone":
                guard let zone = args["zone"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: zone")], isError: true)
                }
                guard let room = args["room"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: room")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.addRoomToZone(homeName: home, zoneName: zone, roomName: room)

            case "remove_room_from_zone":
                guard let zone = args["zone"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: zone")], isError: true)
                }
                guard let room = args["room"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: room")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.removeRoomFromZone(homeName: home, zoneName: zone, roomName: room)

            case "rename_accessory":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                guard let newName = args["newName"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: newName")], isError: true)
                }
                let home = args["home"]?.stringValue
                let room = args["room"]?.stringValue
                result = try await homeKitManager.renameAccessory(id: id, name: name, homeName: home, roomName: room, newName: newName)

            case "remove_accessory":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                let confirm = args["confirm"]?.boolValue ?? false
                let home = args["home"]?.stringValue
                let room = args["room"]?.stringValue
                result = try await homeKitManager.removeAccessory(id: id, name: name, homeName: home, roomName: room, confirm: confirm)

            case "identify_accessory":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                let home = args["home"]?.stringValue
                let room = args["room"]?.stringValue
                result = try await homeKitManager.identifyAccessory(id: id, name: name, homeName: home, roomName: room)

            case "add_scene":
                guard let name = args["name"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: name")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.addScene(homeName: home, name: name)

            case "rename_scene":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                guard let newName = args["newName"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: newName")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.renameScene(homeName: home, name: name, id: id, newName: newName)

            case "remove_scene":
                let id = args["id"]?.stringValue
                let name = args["name"]?.stringValue
                guard id != nil || name != nil else {
                    return CallTool.Result(content: [.text("Either 'id' or 'name' is required")], isError: true)
                }
                let home = args["home"]?.stringValue
                result = try await homeKitManager.removeScene(homeName: home, name: name, id: id)

            case "rename_home":
                guard let home = args["home"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: home")], isError: true)
                }
                guard let newName = args["newName"]?.stringValue else {
                    return CallTool.Result(content: [.text("Missing required parameter: newName")], isError: true)
                }
                result = try await homeKitManager.renameHome(homeName: home, newName: newName)

            case "backup_home":
                let home = args["home"]?.stringValue
                let snapshot = try await homeKitManager.snapshotHome(homeName: home)
                result = try encodableToJSONObject(snapshot)

            case "restore_home":
                guard let backupValue = args["backup"] else {
                    return CallTool.Result(content: [.text("Missing required parameter: backup")], isError: true)
                }
                let confirm = args["confirm"]?.boolValue ?? false
                let backup = try decodeSnapshot(from: backupValue)
                let outcome = try await homeKitManager.restoreHome(backup: backup, confirm: confirm)
                result = try encodableToJSONObject(outcome)

            default:
                return CallTool.Result(
                    content: [.text("Unknown tool: \(params.name)")],
                    isError: true
                )
            }

            let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            let text = String(data: json, encoding: .utf8) ?? "{}"
            return CallTool.Result(content: [.text(text)])
        } catch {
            Log.error("Tool '\(params.name)' failed: \(error)")
            return CallTool.Result(
                content: [.text("Error: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Convert MCP Value to native Swift types for HomeKitManager
    func convertValue(_ value: Value) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s):
            // Models sometimes stringify JSON objects — try to parse them back
            if let data = s.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data),
               parsed is [String: Any] || parsed is [Any] {
                return parsed
            }
            return s
        case .array(let arr): return arr.map { convertValue($0) }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (k, v) in dict {
                result[k] = convertValue(v)
            }
            return result
        case .data(_, let d): return d
        }
    }

    /// Bridge a Codable value into the [String: Any] JSON object the tool path serializes.
    func encodableToJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Decode a backup snapshot from the incoming MCP Value argument.
    func decodeSnapshot(from value: Value) throws -> HomeSnapshot {
        let anyValue = convertValue(value)
        let data = try JSONSerialization.data(withJSONObject: anyValue)
        return try JSONDecoder().decode(HomeSnapshot.self, from: data)
    }
}
