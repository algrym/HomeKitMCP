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
}
