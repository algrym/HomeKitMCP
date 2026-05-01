import Foundation
import MCP
import Testing
@testable import HomeKitMCP

@MainActor
struct HomeKitManagementTests {

    private func makeSUT() -> (manager: MCPServerManager, mock: MockHomeKitManager) {
        let mock = MockHomeKitManager()
        let manager = MCPServerManager(homeKitManager: mock, startServer: false)
        return (manager, mock)
    }

    // MARK: - add_room

    @Test func addRoomRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedAddRoomResult = ["success": true, "name": "Office", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "add_room",
            arguments: ["home": .string("My Home"), "name": .string("Office")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.addRoomCalledWith?.homeName == "My Home")
        #expect(mock.addRoomCalledWith?.name == "Office")
        #expect(result.isError != true)
    }

    @Test func addRoomMissingNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "add_room", arguments: [:])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func addRoomErrorPropagates() async {
        let (manager, mock) = makeSUT()
        mock.addRoomError = HomeKitError.homeNotFound("Ghost Home")
        let params = CallTool.Parameters(
            name: "add_room",
            arguments: ["home": .string("Ghost Home"), "name": .string("Office")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
        if case .text(let textContent) = result.content.first {
            #expect(textContent.text.contains("Ghost Home"))
        }
    }

    // MARK: - rename_room

    @Test func renameRoomRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRenameRoomResult = ["success": true, "oldName": "Office", "newName": "Study", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "rename_room",
            arguments: ["room": .string("Office"), "newName": .string("Study")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.renameRoomCalledWith?.roomName == "Office")
        #expect(mock.renameRoomCalledWith?.newName == "Study")
        #expect(result.isError != true)
    }

    @Test func renameRoomMissingRoomReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(
            name: "rename_room",
            arguments: ["newName": .string("Study")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameRoomMissingNewNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(
            name: "rename_room",
            arguments: ["room": .string("Office")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameRoomNotFoundErrorPropagates() async {
        let (manager, mock) = makeSUT()
        mock.renameRoomError = HomeKitError.roomNotFound("Ghost Room")
        let params = CallTool.Parameters(
            name: "rename_room",
            arguments: ["room": .string("Ghost Room"), "newName": .string("Study")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
        if case .text(let textContent) = result.content.first {
            #expect(textContent.text.contains("Ghost Room"))
        }
    }

    // MARK: - remove_room

    @Test func removeRoomRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRemoveRoomResult = [
            "success": true, "room": "Office", "home": "My Home",
            "movedAccessories": ["Desk Lamp"] as [String],
        ]
        let params = CallTool.Parameters(
            name: "remove_room",
            arguments: ["room": .string("Office")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.removeRoomCalledWith?.roomName == "Office")
        #expect(result.isError != true)
    }

    @Test func removeRoomMissingRoomReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "remove_room", arguments: [:])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func removeRoomNotFoundErrorPropagates() async {
        let (manager, mock) = makeSUT()
        mock.removeRoomError = HomeKitError.roomNotFound("Ghost Room")
        let params = CallTool.Parameters(
            name: "remove_room",
            arguments: ["room": .string("Ghost Room")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - move_accessory_to_room

    @Test func moveAccessoryToRoomRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedMoveAccessoryToRoomResult = [
            "success": true, "accessory": "Desk Lamp", "fromRoom": "Default Room", "toRoom": "Office",
        ]
        let params = CallTool.Parameters(
            name: "move_accessory_to_room",
            arguments: ["name": .string("Desk Lamp"), "room": .string("Office")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.moveAccessoryToRoomCalledWith?.name == "Desk Lamp")
        #expect(mock.moveAccessoryToRoomCalledWith?.roomName == "Office")
        #expect(result.isError != true)
    }

    @Test func moveAccessoryToRoomMissingRoomReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(
            name: "move_accessory_to_room",
            arguments: ["name": .string("Desk Lamp")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func moveAccessoryToRoomMissingIdAndNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(
            name: "move_accessory_to_room",
            arguments: ["room": .string("Office")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }
}
