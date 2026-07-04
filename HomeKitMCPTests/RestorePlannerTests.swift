import Testing
@testable import HomeKitMCP

struct RestorePlannerTests {
    private func snap(
        rooms: [RoomSnapshot] = [],
        zones: [ZoneSnapshot] = [],
        accessories: [AccessorySnapshot] = [],
        scenes: [SceneSnapshot] = []
    ) -> HomeSnapshot {
        HomeSnapshot(formatVersion: 1, createdAt: "t",
            home: .init(name: "H", uniqueIdentifier: "H"),
            rooms: rooms, zones: zones, accessories: accessories, scenes: scenes)
    }

    @Test func identicalSnapshotsYieldEmptyPlan() {
        let s = snap(
            rooms: [RoomSnapshot(name: "LR", uniqueIdentifier: "r1")],
            accessories: [AccessorySnapshot(uniqueIdentifier: "a1", name: "Lamp", room: "LR")])
        let (plan, skipped) = RestorePlanner.plan(backup: s, current: s)
        #expect(plan.isEmpty)
        #expect(skipped.missingAccessories.isEmpty)
    }

    @Test func missingRoomIsCreated() {
        let backup = snap(rooms: [RoomSnapshot(name: "Den", uniqueIdentifier: "r9")])
        let (plan, _) = RestorePlanner.plan(backup: backup, current: snap())
        #expect(plan.createRooms == ["Den"])
    }

    @Test func renamedRoomMatchedByUUIDIsRenamedBack() {
        let backup = snap(rooms: [RoomSnapshot(name: "Living Room", uniqueIdentifier: "r1")])
        let current = snap(rooms: [RoomSnapshot(name: "LR", uniqueIdentifier: "r1")])
        let (plan, _) = RestorePlanner.plan(backup: backup, current: current)
        #expect(plan.renameRooms == [RestorePlan.Rename(from: "LR", to: "Living Room")])
        #expect(plan.createRooms.isEmpty)
    }

    @Test func accessoryMovedAndRenamedByUUID() {
        let backup = snap(
            rooms: [RoomSnapshot(name: "LR", uniqueIdentifier: "r1")],
            accessories: [AccessorySnapshot(uniqueIdentifier: "a1", name: "Corner Lamp", room: "LR")])
        let current = snap(
            rooms: [RoomSnapshot(name: "LR", uniqueIdentifier: "r1")],
            accessories: [AccessorySnapshot(uniqueIdentifier: "a1", name: "Lamp", room: "Default Room")])
        let (plan, _) = RestorePlanner.plan(backup: backup, current: current)
        #expect(plan.moveAccessories == [RestorePlan.Move(accessory: "Corner Lamp", fromRoom: "Default Room", toRoom: "LR")])
        #expect(plan.renameAccessories == [RestorePlan.Rename(from: "Lamp", to: "Corner Lamp")])
    }

    @Test func missingAccessoryIsSkippedNotCreated() {
        let backup = snap(accessories: [AccessorySnapshot(uniqueIdentifier: "gone", name: "Ghost", room: "LR")])
        let (plan, skipped) = RestorePlanner.plan(backup: backup, current: snap())
        #expect(plan.moveAccessories.isEmpty)
        #expect(skipped.missingAccessories == ["Ghost"])
    }

    @Test func zoneMembershipIsAdditiveOnly() {
        // backup zone has [LR]; current zone already has [LR, Kitchen] -> no change (never removes Kitchen)
        let backup = snap(zones: [ZoneSnapshot(name: "Down", uniqueIdentifier: "z1", rooms: ["LR"])])
        let current = snap(zones: [ZoneSnapshot(name: "Down", uniqueIdentifier: "z1", rooms: ["LR", "Kitchen"])])
        let (plan, _) = RestorePlanner.plan(backup: backup, current: current)
        #expect(plan.addRoomsToZones.isEmpty)
    }

    @Test func missingZoneRoomIsAdded() {
        let backup = snap(zones: [ZoneSnapshot(name: "Down", uniqueIdentifier: "z1", rooms: ["LR", "Kitchen"])])
        let current = snap(zones: [ZoneSnapshot(name: "Down", uniqueIdentifier: "z1", rooms: ["LR"])])
        let (plan, _) = RestorePlanner.plan(backup: backup, current: current)
        #expect(plan.addRoomsToZones == [RestorePlan.ZoneRooms(zone: "Down", rooms: ["Kitchen"])])
    }

    @Test func sceneActionsPlannedOnlyWhenDifferent() {
        let act = SceneAction(accessory: "a1", characteristicType: "bright", targetValue: .number(30))
        let scene = SceneSnapshot(name: "Movie", uniqueIdentifier: "s1", actions: [act])
        let backup = snap(accessories: [AccessorySnapshot(uniqueIdentifier: "a1", name: "Lamp", room: "LR")], scenes: [scene])
        // current identical -> no scene work
        let (samePlan, _) = RestorePlanner.plan(backup: backup, current: backup)
        #expect(samePlan.setSceneActions.isEmpty)
        // current scene has no actions -> plan to set them
        let currentEmptyScene = snap(
            accessories: [AccessorySnapshot(uniqueIdentifier: "a1", name: "Lamp", room: "LR")],
            scenes: [SceneSnapshot(name: "Movie", uniqueIdentifier: "s1", actions: [])])
        let (plan, _) = RestorePlanner.plan(backup: backup, current: currentEmptyScene)
        #expect(plan.setSceneActions == [RestorePlan.SceneActionsPlan(scene: "Movie", actionCount: 1)])
    }

    @Test func sceneActionForMissingAccessoryIsSkipped() {
        let act = SceneAction(accessory: "gone", characteristicType: "bright", targetValue: .number(30))
        let scene = SceneSnapshot(name: "Movie", uniqueIdentifier: "s1", actions: [act])
        let backup = snap(scenes: [scene])  // no accessories present anywhere
        let (plan, skipped) = RestorePlanner.plan(backup: backup, current: snap())
        #expect(plan.createScenes == ["Movie"])
        #expect(plan.setSceneActions.isEmpty)   // its only action references a missing accessory
        #expect(skipped.missingCharacteristics == [RestoreSkipped.MissingCharacteristic(scene: "Movie", accessory: "gone", characteristicType: "bright")])
    }

    @Test func zoneMatchedByNameOnlyStillAddsMissingRoom() {
        let backup = snap(zones: [ZoneSnapshot(name: "Down", uniqueIdentifier: "z1", rooms: ["LR", "Kitchen"])])
        let current = snap(zones: [ZoneSnapshot(name: "Down", uniqueIdentifier: "z9", rooms: ["LR"])]) // uuid drifted
        let (plan, _) = RestorePlanner.plan(backup: backup, current: current)
        #expect(plan.createZones.isEmpty)
        #expect(plan.addRoomsToZones == [RestorePlan.ZoneRooms(zone: "Down", rooms: ["Kitchen"])])
    }

    @Test func sceneMatchedByNameOnlyWithIdenticalActionsIsIdempotent() {
        let act = SceneAction(accessory: "a1", characteristicType: "bright", targetValue: .number(30))
        let backup = snap(accessories: [AccessorySnapshot(uniqueIdentifier: "a1", name: "Lamp", room: "LR")],
                          scenes: [SceneSnapshot(name: "Movie", uniqueIdentifier: "s1", actions: [act])])
        let current = snap(accessories: [AccessorySnapshot(uniqueIdentifier: "a1", name: "Lamp", room: "LR")],
                           scenes: [SceneSnapshot(name: "Movie", uniqueIdentifier: "s9", actions: [act])]) // uuid drifted, same content
        let (plan, _) = RestorePlanner.plan(backup: backup, current: current)
        #expect(plan.createScenes.isEmpty)
        #expect(plan.setSceneActions.isEmpty)
    }
}
