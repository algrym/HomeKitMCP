import Foundation
import Testing
@testable import HomeKitMCP

struct HomeSnapshotTests {
    private func sample() -> HomeSnapshot {
        HomeSnapshot(
            formatVersion: 1,
            createdAt: "2026-07-03T12:00:00Z",
            home: HomeSnapshot.HomeRef(name: "Home", uniqueIdentifier: "H-UUID"),
            rooms: [RoomSnapshot(name: "Living Room", uniqueIdentifier: "R-UUID")],
            zones: [ZoneSnapshot(name: "Downstairs", uniqueIdentifier: "Z-UUID", rooms: ["Living Room"])],
            accessories: [AccessorySnapshot(uniqueIdentifier: "A-UUID", name: "Lamp", room: "Living Room")],
            scenes: [SceneSnapshot(name: "Movie", uniqueIdentifier: "S-UUID",
                actions: [SceneAction(accessory: "A-UUID", characteristicType: "public.hap.characteristic.brightness", targetValue: .number(30))])]
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let snapshot = sample()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(HomeSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test func targetValueEncodesAsRawJSON() throws {
        // A brightness of 30 must serialize as the number 30, not a wrapper object.
        let action = SceneAction(accessory: "A", characteristicType: "t", targetValue: .number(30))
        let json = String(data: try JSONEncoder().encode(action), encoding: .utf8)!
        #expect(json.contains("\"targetValue\":30"))
    }

    @Test func numbersRoundTripWholeAndFractional() throws {
        for original in [JSONValue.number(30), JSONValue.number(30.5)] {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            #expect(decoded == original)
        }
    }
}
