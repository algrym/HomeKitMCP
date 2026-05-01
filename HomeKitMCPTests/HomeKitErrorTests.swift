import Testing
@testable import HomeKitMCP

struct HomeKitErrorTests {

    @Test func deviceNotFoundDescription() {
        let error = HomeKitError.deviceNotFound("Living Room Light")
        #expect(error.errorDescription == "Device 'Living Room Light' not found")
    }

    @Test func deviceUnreachableDescription() {
        let error = HomeKitError.deviceUnreachable("Kitchen Switch")
        #expect(error.errorDescription == "Device 'Kitchen Switch' is not reachable")
    }

    @Test func characteristicNotFoundDescription() {
        let error = HomeKitError.characteristicNotFound("brightness")
        #expect(error.errorDescription == "Characteristic 'brightness' not found on device")
    }

    @Test func characteristicReadOnlyDescription() {
        let error = HomeKitError.characteristicReadOnly("temperature")
        #expect(error.errorDescription == "Characteristic 'temperature' is read-only")
    }

    @Test func invalidValueDescription() {
        let error = HomeKitError.invalidValue("brightness requires an integer 0-100")
        #expect(error.errorDescription == "Invalid value: brightness requires an integer 0-100")
    }

    @Test func unknownActionDescription() {
        let error = HomeKitError.unknownAction("fly")
        #expect(error.errorDescription == "Unknown action: 'fly'")
    }

    @Test func roomNotFoundHasDescription() {
        let error = HomeKitError.roomNotFound("Office")
        #expect(error.errorDescription == "Room 'Office' not found")
    }

    @Test func zoneNotFoundHasDescription() {
        let error = HomeKitError.zoneNotFound("Upstairs")
        #expect(error.errorDescription == "Zone 'Upstairs' not found")
    }

    @Test func homeNotFoundHasDescription() {
        let error = HomeKitError.homeNotFound("Beach House")
        #expect(error.errorDescription == "Home 'Beach House' not found")
    }

    @Test func sceneAlreadyExistsHasDescription() {
        let error = HomeKitError.sceneAlreadyExists("Good Night")
        #expect(error.errorDescription == "Scene 'Good Night' already exists")
    }

    @Test func cannotRemoveDefaultRoomHasDescription() {
        let error = HomeKitError.cannotRemoveDefaultRoom
        #expect(error.errorDescription == "Cannot remove the default room")
    }
}
