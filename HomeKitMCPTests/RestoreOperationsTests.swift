import Testing
@testable import HomeKitMCP

/// Coverage for RestorePlanner.operations — the pure flattening of a plan into ordered
/// apply steps. This is where restore's two historical bugs lived (move-before-rename
/// ordering; name-vs-UUID accessory resolution), so they get locked down here.
struct RestoreOperationsTests {
    private func snap(scenes: [SceneSnapshot] = []) -> HomeSnapshot {
        HomeSnapshot(formatVersion: 1, createdAt: "t",
            home: .init(name: "H", uniqueIdentifier: "H"),
            rooms: [], zones: [], accessories: [], scenes: scenes)
    }

    @Test func emptyPlanYieldsNoOps() {
        #expect(RestorePlanner.operations(for: RestorePlan(), backup: snap()).isEmpty)
    }

    @Test func accessoryIsRenamedBeforeItIsMoved() {
        var plan = RestorePlan()
        plan.renameAccessories = [.init(from: "Lamp", to: "Corner Lamp", uuid: "a1")]
        plan.moveAccessories = [.init(accessory: "Corner Lamp", uuid: "a1", fromRoom: "R1", toRoom: "R2")]
        let ops = RestorePlanner.operations(for: plan, backup: snap())
        let ri = ops.firstIndex(of: .renameAccessory(uuid: "a1", to: "Corner Lamp"))
        let mi = ops.firstIndex(of: .moveAccessory(uuid: "a1", toRoom: "R2"))
        #expect(ri != nil && mi != nil && ri! < mi!)
    }

    @Test func accessoryOpsCarryUUIDNotName() {
        var plan = RestorePlan()
        plan.moveAccessories = [.init(accessory: "Corner Lamp", uuid: "a1", fromRoom: "R1", toRoom: "R2")]
        plan.renameAccessories = [.init(from: "Lamp", to: "Corner Lamp", uuid: "a1")]
        let ops = RestorePlanner.operations(for: plan, backup: snap())
        #expect(ops.contains(.moveAccessory(uuid: "a1", toRoom: "R2")))
        #expect(ops.contains(.renameAccessory(uuid: "a1", to: "Corner Lamp")))
    }

    @Test func addRoomsToZonesFlattenToOneOpPerRoom() {
        var plan = RestorePlan()
        plan.addRoomsToZones = [.init(zone: "Down", rooms: ["LR", "Kitchen"])]
        let ops = RestorePlanner.operations(for: plan, backup: snap())
        #expect(ops == [.addRoomToZone(zone: "Down", room: "LR"),
                        .addRoomToZone(zone: "Down", room: "Kitchen")])
    }

    @Test func setSceneActionsResolvesBackupSceneOrSkips() {
        var plan = RestorePlan()
        plan.setSceneActions = [.init(scene: "Movie", actionCount: 1)]
        let scene = SceneSnapshot(name: "Movie", uniqueIdentifier: "s1",
            actions: [SceneAction(accessory: "a1", characteristicType: "bright", targetValue: .number(30))])
        #expect(RestorePlanner.operations(for: plan, backup: snap(scenes: [scene])) == [.setSceneActions(scene)])
        // scene not present in the backup -> the op is skipped, not fabricated
        #expect(RestorePlanner.operations(for: plan, backup: snap()).isEmpty)
    }

    @Test func everyCategoryEmittedInApplyOrder() {
        var plan = RestorePlan()
        plan.createRooms = ["NewRoom"]
        plan.renameRooms = [.init(from: "R1", to: "R1b")]
        plan.renameAccessories = [.init(from: "L", to: "Lb", uuid: "a1")]
        plan.moveAccessories = [.init(accessory: "Lb", uuid: "a1", fromRoom: "R1", toRoom: "R2")]
        plan.createZones = ["NewZone"]
        plan.renameZones = [.init(from: "Z1", to: "Z1b")]
        plan.addRoomsToZones = [.init(zone: "Z1b", rooms: ["R1b"])]
        plan.createScenes = ["NewScene"]
        plan.renameScenes = [.init(from: "S1", to: "S1b")]
        plan.setSceneActions = [.init(scene: "S1b", actionCount: 1)]
        let scene = SceneSnapshot(name: "S1b", uniqueIdentifier: "s1",
            actions: [SceneAction(accessory: "a1", characteristicType: "t", targetValue: .number(1))])
        let ops = RestorePlanner.operations(for: plan, backup: snap(scenes: [scene]))
        #expect(ops == [
            .createRoom("NewRoom"),
            .renameRoom(from: "R1", to: "R1b"),
            .renameAccessory(uuid: "a1", to: "Lb"),
            .moveAccessory(uuid: "a1", toRoom: "R2"),
            .createZone("NewZone"),
            .renameZone(from: "Z1", to: "Z1b"),
            .addRoomToZone(zone: "Z1b", room: "R1b"),
            .createScene("NewScene"),
            .renameScene(from: "S1", to: "S1b"),
            .setSceneActions(scene),
        ])
    }
}
