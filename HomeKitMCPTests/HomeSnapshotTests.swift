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
                actions: [SceneAction(accessory: "A-UUID", characteristicType: "public.hap.characteristic.brightness", targetValue: .double(30))])]
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
        let action = SceneAction(accessory: "A", characteristicType: "t", targetValue: .double(30))
        let json = String(data: try JSONEncoder().encode(action), encoding: .utf8)!
        #expect(json.contains("\"targetValue\":30"))
    }
}
