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

    // MARK: - list_zones

    @Test func listZonesRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedZones = [["name": "Upstairs", "home": "My Home", "rooms": ["Bedroom", "Office"], "uniqueIdentifier": "ABC"]]

        let params = CallTool.Parameters(name: "list_zones", arguments: ["home": .string("My Home")])
        let result = await manager.handleToolCall(params)

        #expect(mock.listZonesCalledWith == .some("My Home"))
        #expect(result.isError != true)
    }

    @Test func listZonesPassesNilWhenNoHome() async {
        let (manager, mock) = makeSUT()
        let params = CallTool.Parameters(name: "list_zones", arguments: [:])
        _ = await manager.handleToolCall(params)
        #expect(mock.listZonesCalledWith == .some(nil))
    }

    // MARK: - add_zone

    @Test func addZoneRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedAddZoneResult = ["success": true, "name": "Upstairs", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "add_zone",
            arguments: ["name": .string("Upstairs"), "home": .string("My Home")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.addZoneCalledWith?.name == "Upstairs")
        #expect(mock.addZoneCalledWith?.homeName == "My Home")
        #expect(result.isError != true)
    }

    @Test func addZoneMissingNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "add_zone", arguments: [:])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - rename_zone

    @Test func renameZoneRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRenameZoneResult = ["success": true, "oldName": "Upstairs", "newName": "Upper Floor", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "rename_zone",
            arguments: ["zone": .string("Upstairs"), "newName": .string("Upper Floor")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.renameZoneCalledWith?.zoneName == "Upstairs")
        #expect(mock.renameZoneCalledWith?.newName == "Upper Floor")
        #expect(result.isError != true)
    }

    @Test func renameZoneMissingZoneReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "rename_zone", arguments: ["newName": .string("Upper Floor")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameZoneMissingNewNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "rename_zone", arguments: ["zone": .string("Upstairs")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameZoneNotFoundPropagates() async {
        let (manager, mock) = makeSUT()
        mock.renameZoneError = HomeKitError.zoneNotFound("Ghost Zone")
        let params = CallTool.Parameters(
            name: "rename_zone",
            arguments: ["zone": .string("Ghost Zone"), "newName": .string("Real Zone")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
        if case .text(let textContent) = result.content.first {
            #expect(textContent.text.contains("Ghost Zone"))
        }
    }

    // MARK: - remove_zone

    @Test func removeZoneRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRemoveZoneResult = ["success": true, "zone": "Upstairs", "home": "My Home"]

        let params = CallTool.Parameters(name: "remove_zone", arguments: ["zone": .string("Upstairs")])
        let result = await manager.handleToolCall(params)

        #expect(mock.removeZoneCalledWith?.zoneName == "Upstairs")
        #expect(result.isError != true)
    }

    @Test func removeZoneMissingZoneReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "remove_zone", arguments: [:])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - add_room_to_zone

    @Test func addRoomToZoneRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedAddRoomToZoneResult = ["success": true, "zone": "Upstairs", "room": "Bedroom", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "add_room_to_zone",
            arguments: ["zone": .string("Upstairs"), "room": .string("Bedroom")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.addRoomToZoneCalledWith?.zoneName == "Upstairs")
        #expect(mock.addRoomToZoneCalledWith?.roomName == "Bedroom")
        #expect(result.isError != true)
    }

    @Test func addRoomToZoneMissingZoneReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "add_room_to_zone", arguments: ["room": .string("Bedroom")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func addRoomToZoneMissingRoomReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "add_room_to_zone", arguments: ["zone": .string("Upstairs")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - remove_room_from_zone

    @Test func removeRoomFromZoneRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRemoveRoomFromZoneResult = ["success": true, "zone": "Upstairs", "room": "Bedroom", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "remove_room_from_zone",
            arguments: ["zone": .string("Upstairs"), "room": .string("Bedroom")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.removeRoomFromZoneCalledWith?.zoneName == "Upstairs")
        #expect(mock.removeRoomFromZoneCalledWith?.roomName == "Bedroom")
        #expect(result.isError != true)
    }

    @Test func removeRoomFromZoneMissingZoneReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "remove_room_from_zone", arguments: ["room": .string("Bedroom")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func removeRoomFromZoneMissingRoomReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "remove_room_from_zone", arguments: ["zone": .string("Upstairs")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - rename_accessory

    @Test func renameAccessoryRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRenameAccessoryResult = ["success": true, "oldName": "Lamp 3", "newName": "Desk Lamp"]

        let params = CallTool.Parameters(
            name: "rename_accessory",
            arguments: ["name": .string("Lamp 3"), "newName": .string("Desk Lamp")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.renameAccessoryCalledWith?.name == "Lamp 3")
        #expect(mock.renameAccessoryCalledWith?.newName == "Desk Lamp")
        #expect(result.isError != true)
    }

    @Test func renameAccessoryByIdRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRenameAccessoryResult = ["success": true, "oldName": "Lamp 3", "newName": "Desk Lamp"]

        let params = CallTool.Parameters(
            name: "rename_accessory",
            arguments: ["id": .string("ABCD-1234"), "newName": .string("Desk Lamp")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.renameAccessoryCalledWith?.id == "ABCD-1234")
        #expect(result.isError != true)
    }

    @Test func renameAccessoryMissingIdAndNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "rename_accessory", arguments: ["newName": .string("Desk Lamp")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameAccessoryMissingNewNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "rename_accessory", arguments: ["name": .string("Lamp 3")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameAccessoryNotFoundPropagates() async {
        let (manager, mock) = makeSUT()
        mock.renameAccessoryError = HomeKitError.deviceNotFound("Ghost Lamp")
        let params = CallTool.Parameters(
            name: "rename_accessory",
            arguments: ["name": .string("Ghost Lamp"), "newName": .string("Real Lamp")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - remove_accessory

    @Test func removeAccessoryWithConfirmRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRemoveAccessoryResult = ["success": true, "accessory": "Old Lamp", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "remove_accessory",
            arguments: ["name": .string("Old Lamp"), "confirm": .bool(true)]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.removeAccessoryCalledWith?.name == "Old Lamp")
        #expect(mock.removeAccessoryCalledWith?.confirm == true)
        #expect(result.isError != true)
    }

    @Test func removeAccessoryWithoutConfirmPassesFalse() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRemoveAccessoryResult = [
            "success": false,
            "requiresConfirmation": true,
            "message": "Pass confirm: true to proceed.",
        ]
        let params = CallTool.Parameters(
            name: "remove_accessory",
            arguments: ["name": .string("Old Lamp")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.removeAccessoryCalledWith?.confirm == false)
        #expect(result.isError != true)
    }

    @Test func removeAccessoryMissingIdAndNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "remove_accessory", arguments: ["confirm": .bool(true)])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - identify_accessory

    @Test func identifyAccessoryRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedIdentifyAccessoryResult = ["success": true, "accessory": "Lamp 3"]

        let params = CallTool.Parameters(
            name: "identify_accessory",
            arguments: ["name": .string("Lamp 3")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.identifyAccessoryCalledWith?.name == "Lamp 3")
        #expect(result.isError != true)
    }

    @Test func identifyAccessoryMissingIdAndNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "identify_accessory", arguments: [:])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func identifyAccessoryNotFoundPropagates() async {
        let (manager, mock) = makeSUT()
        mock.identifyAccessoryError = HomeKitError.deviceNotFound("Ghost")
        let params = CallTool.Parameters(
            name: "identify_accessory",
            arguments: ["name": .string("Ghost")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - add_scene

    @Test func addSceneRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedAddSceneResult = [
            "success": true, "name": "Movie Time", "home": "My Home", "uniqueIdentifier": "ABC-123",
        ]
        let params = CallTool.Parameters(
            name: "add_scene",
            arguments: ["name": .string("Movie Time"), "home": .string("My Home")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.addSceneCalledWith?.name == "Movie Time")
        #expect(mock.addSceneCalledWith?.homeName == "My Home")
        #expect(result.isError != true)
    }

    @Test func addSceneMissingNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "add_scene", arguments: [:])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - rename_scene

    @Test func renameSceneByNameRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRenameSceneResult = ["success": true, "oldName": "Movie", "newName": "Movie Time", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "rename_scene",
            arguments: ["name": .string("Movie"), "newName": .string("Movie Time")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.renameSceneCalledWith?.name == "Movie")
        #expect(mock.renameSceneCalledWith?.newName == "Movie Time")
        #expect(result.isError != true)
    }

    @Test func renameSceneByIdRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRenameSceneResult = ["success": true, "oldName": "Movie", "newName": "Movie Time", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "rename_scene",
            arguments: ["id": .string("ABCD-1234"), "newName": .string("Movie Time")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.renameSceneCalledWith?.id == "ABCD-1234")
        #expect(result.isError != true)
    }

    @Test func renameSceneMissingIdAndNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "rename_scene", arguments: ["newName": .string("Movie Time")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameSceneMissingNewNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "rename_scene", arguments: ["name": .string("Movie")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameSceneNotFoundPropagates() async {
        let (manager, mock) = makeSUT()
        mock.renameSceneError = HomeKitError.sceneNotFound("Ghost Scene")
        let params = CallTool.Parameters(
            name: "rename_scene",
            arguments: ["name": .string("Ghost Scene"), "newName": .string("Real Scene")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - remove_scene

    @Test func removeSceneByNameRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRemoveSceneResult = ["success": true, "scene": "Movie Time", "home": "My Home"]

        let params = CallTool.Parameters(
            name: "remove_scene",
            arguments: ["name": .string("Movie Time")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.removeSceneCalledWith?.name == "Movie Time")
        #expect(result.isError != true)
    }

    @Test func removeSceneMissingIdAndNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "remove_scene", arguments: [:])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    // MARK: - rename_home

    @Test func renameHomeRoutesToManager() async {
        let (manager, mock) = makeSUT()
        mock.stubbedRenameHomeResult = ["success": true, "oldName": "My Home", "newName": "Casa"]

        let params = CallTool.Parameters(
            name: "rename_home",
            arguments: ["home": .string("My Home"), "newName": .string("Casa")]
        )
        let result = await manager.handleToolCall(params)

        #expect(mock.renameHomeCalledWith?.homeName == "My Home")
        #expect(mock.renameHomeCalledWith?.newName == "Casa")
        #expect(result.isError != true)
    }

    @Test func renameHomeMissingHomeReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "rename_home", arguments: ["newName": .string("Casa")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameHomeMissingNewNameReturnsError() async {
        let (manager, _) = makeSUT()
        let params = CallTool.Parameters(name: "rename_home", arguments: ["home": .string("My Home")])
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
    }

    @Test func renameHomeNotFoundPropagates() async {
        let (manager, mock) = makeSUT()
        mock.renameHomeError = HomeKitError.homeNotFound("Ghost Home")
        let params = CallTool.Parameters(
            name: "rename_home",
            arguments: ["home": .string("Ghost Home"), "newName": .string("Casa")]
        )
        let result = await manager.handleToolCall(params)
        #expect(result.isError == true)
        if case .text(let textContent) = result.content.first {
            #expect(textContent.text.contains("Ghost Home"))
        }
    }
}
