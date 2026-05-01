import MCP

enum ToolDefinitions {
    static let listHomes = Tool(
        name: "list_homes",
        description: "List all HomeKit homes configured on this Mac",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static let listRooms = Tool(
        name: "list_rooms",
        description: "List rooms in a HomeKit home. Returns room names with device counts.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to filter by. Omit to list rooms from all homes."),
                ]),
            ]),
        ])
    )

    static let listDevices = Tool(
        name: "list_devices",
        description: "List HomeKit devices, optionally filtered by home, room, or device type.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Filter by home name"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Filter by room name"),
                ]),
                "type": .object([
                    "type": .string("string"),
                    "description": .string("Filter by device type (light, switch, outlet, fan, thermostat, lock, garage_door, temperature_sensor, humidity_sensor, motion_sensor, contact_sensor, occupancy_sensor, window, window_covering, door)"),
                ]),
            ]),
        ])
    )

    static let getDeviceState = Tool(
        name: "get_device_state",
        description: "Get the current state and properties of a HomeKit device. Returns power state, brightness, temperature, lock state, etc. depending on device type. Specify the device by name or by unique ID (from list_devices). Use ID when multiple devices share the same name.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Device unique identifier (from list_devices uniqueIdentifier). If provided, name/home/room are ignored."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Device name (case-insensitive). Required if id is not provided."),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to disambiguate devices with the same name"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Room name to disambiguate devices with the same name"),
                ]),
            ]),
        ])
    )

    static let controlDevice = Tool(
        name: "control_device",
        description: """
            Control a HomeKit device. Specify the device by name or by unique ID (from list_devices). \
            Use ID when multiple devices share the same name. \
            Supported actions: \
            on, off, toggle (lights/switches/outlets/fans), \
            set_brightness (0-100), set_hue (0-360), set_saturation (0-100), \
            set_color ({hue, saturation}), \
            lock, unlock (locks), \
            open, close (garage doors), \
            set_temperature (celsius), set_thermostat_mode (off/heat/cool/auto)
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Device unique identifier (from list_devices uniqueIdentifier). If provided, name/home/room are ignored."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Device name (case-insensitive). Required if id is not provided."),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to disambiguate devices with the same name"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Room name to disambiguate devices with the same name"),
                ]),
                "action": .object([
                    "type": .string("string"),
                    "description": .string("Action to perform: on, off, toggle, set_brightness, set_hue, set_saturation, set_color, lock, unlock, open, close, set_temperature, set_thermostat_mode"),
                    "enum": .array([
                        .string("on"), .string("off"), .string("toggle"),
                        .string("set_brightness"), .string("set_hue"),
                        .string("set_saturation"), .string("set_color"),
                        .string("lock"), .string("unlock"),
                        .string("open"), .string("close"),
                        .string("set_temperature"), .string("set_thermostat_mode"),
                    ]),
                ]),
                "value": .object([
                    "description": .string("Value for the action. Required for set_brightness (int 0-100), set_hue (number 0-360), set_saturation (number 0-100), set_color ({hue, saturation}), set_temperature (number, celsius), set_thermostat_mode (string: off/heat/cool/auto)."),
                ]),
            ]),
            "required": .array([.string("action")]),
        ])
    )

    static let batchControlDevices = Tool(
        name: "batch_control_devices",
        description: """
            Control multiple HomeKit devices in a single call. Each command specifies a device and action. \
            All commands run independently — failures on one device do not affect others. \
            Returns per-device results with success/failure status.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "commands": .object([
                    "type": .string("array"),
                    "description": .string("Array of device control commands"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "id": .object([
                                "type": .string("string"),
                                "description": .string("Device unique identifier. If provided, name/home/room are ignored."),
                            ]),
                            "name": .object([
                                "type": .string("string"),
                                "description": .string("Device name (case-insensitive). Required if id is not provided."),
                            ]),
                            "action": .object([
                                "type": .string("string"),
                                "description": .string("Action to perform (on, off, toggle, set_brightness, etc.)"),
                            ]),
                            "home": .object([
                                "type": .string("string"),
                                "description": .string("Home name to disambiguate"),
                            ]),
                            "room": .object([
                                "type": .string("string"),
                                "description": .string("Room name to disambiguate"),
                            ]),
                            "value": .object([
                                "description": .string("Value for the action, if needed"),
                            ]),
                        ]),
                        "required": .array([.string("action")]),
                    ]),
                ]),
            ]),
            "required": .array([.string("commands")]),
        ])
    )

    static let batchGetDeviceState = Tool(
        name: "batch_get_device_state",
        description: """
            Get the current state of multiple HomeKit devices in a single call. \
            Each device is specified by name or unique ID. \
            All queries run independently — failures on one device do not affect others. \
            Returns per-device state with success/failure status.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "devices": .object([
                    "type": .string("array"),
                    "description": .string("Array of devices to query"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "id": .object([
                                "type": .string("string"),
                                "description": .string("Device unique identifier. If provided, name/home/room are ignored."),
                            ]),
                            "name": .object([
                                "type": .string("string"),
                                "description": .string("Device name (case-insensitive). Required if id is not provided."),
                            ]),
                            "home": .object([
                                "type": .string("string"),
                                "description": .string("Home name to disambiguate"),
                            ]),
                            "room": .object([
                                "type": .string("string"),
                                "description": .string("Room name to disambiguate"),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
            "required": .array([.string("devices")]),
        ])
    )

    static let controlDevicesByFilter = Tool(
        name: "control_devices_by_filter",
        description: """
            Apply a single action to all HomeKit devices matching a filter. \
            At least one filter (home, room, or type) is required. \
            All matching devices are controlled independently — failures on one do not affect others.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "description": .string("Action to perform on all matching devices (on, off, toggle, set_brightness, etc.)"),
                    "enum": .array([
                        .string("on"), .string("off"), .string("toggle"),
                        .string("set_brightness"), .string("set_hue"),
                        .string("set_saturation"), .string("set_color"),
                        .string("lock"), .string("unlock"),
                        .string("open"), .string("close"),
                        .string("set_temperature"), .string("set_thermostat_mode"),
                    ]),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Filter by home name"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Filter by room name"),
                ]),
                "type": .object([
                    "type": .string("string"),
                    "description": .string("Filter by device type (light, switch, outlet, fan, thermostat, lock, garage_door, etc.)"),
                ]),
                "value": .object([
                    "description": .string("Value for the action, if needed"),
                ]),
            ]),
            "required": .array([.string("action")]),
        ])
    )

    static let listScenes = Tool(
        name: "list_scenes",
        description: "List HomeKit scenes (action sets), optionally filtered by home. Returns scene names, types, and action counts.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to filter by. Omit to list scenes from all homes."),
                ]),
            ]),
        ])
    )

    static let executeScene = Tool(
        name: "execute_scene",
        description: """
            Execute (trigger) a HomeKit scene by name or unique ID. \
            Specify the scene by name or by unique ID (from list_scenes). \
            Use ID when multiple scenes share the same name across homes.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Scene unique identifier (from list_scenes uniqueIdentifier). If provided, name/home are ignored."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Scene name (case-insensitive). Required if id is not provided."),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to disambiguate scenes with the same name"),
                ]),
            ]),
        ])
    )

    static let addRoom = Tool(
        name: "add_room",
        description: "Create a new room in a HomeKit home.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Name for the new room"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("name")]),
        ])
    )

    static let renameRoom = Tool(
        name: "rename_room",
        description: "Rename an existing room in a HomeKit home.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Current room name (case-insensitive)"),
                ]),
                "newName": .object([
                    "type": .string("string"),
                    "description": .string("New name for the room"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("room"), .string("newName")]),
        ])
    )

    static let removeRoom = Tool(
        name: "remove_room",
        description: "Delete a room from a HomeKit home. Accessories in that room are moved to the Default Room.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Room name to remove (case-insensitive)"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("room")]),
        ])
    )

    static let moveAccessoryToRoom = Tool(
        name: "move_accessory_to_room",
        description: "Move a HomeKit accessory to a different room. Specify the accessory by name or unique ID.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Accessory unique identifier (from list_devices). Preferred over name."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Accessory name (case-insensitive). Required if id is not provided."),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Destination room name (case-insensitive)"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("room")]),
        ])
    )

    static let listZones = Tool(
        name: "list_zones",
        description: "List HomeKit zones (groups of rooms), optionally filtered by home.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to filter by. Omit to list zones from all homes."),
                ]),
            ]),
        ])
    )

    static let addZone = Tool(
        name: "add_zone",
        description: "Create a new zone in a HomeKit home. Zones group rooms together (e.g. 'Upstairs').",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Name for the new zone"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("name")]),
        ])
    )

    static let renameZone = Tool(
        name: "rename_zone",
        description: "Rename an existing zone in a HomeKit home.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "zone": .object([
                    "type": .string("string"),
                    "description": .string("Current zone name (case-insensitive)"),
                ]),
                "newName": .object([
                    "type": .string("string"),
                    "description": .string("New name for the zone"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("zone"), .string("newName")]),
        ])
    )

    static let removeZone = Tool(
        name: "remove_zone",
        description: "Delete a zone from a HomeKit home. Rooms and accessories are not affected.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "zone": .object([
                    "type": .string("string"),
                    "description": .string("Zone name to remove (case-insensitive)"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("zone")]),
        ])
    )

    static let addRoomToZone = Tool(
        name: "add_room_to_zone",
        description: "Add an existing room to a zone.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "zone": .object([
                    "type": .string("string"),
                    "description": .string("Zone name (case-insensitive)"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Room name to add to the zone (case-insensitive)"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("zone"), .string("room")]),
        ])
    )

    static let removeRoomFromZone = Tool(
        name: "remove_room_from_zone",
        description: "Remove a room from a zone. The room itself is not deleted.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "zone": .object([
                    "type": .string("string"),
                    "description": .string("Zone name (case-insensitive)"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Room name to remove from the zone (case-insensitive)"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("zone"), .string("room")]),
        ])
    )

    static let renameAccessory = Tool(
        name: "rename_accessory",
        description: "Rename a HomeKit accessory. Specify the accessory by name or unique ID (preferred).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Accessory unique identifier (from list_devices). Preferred over name."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Accessory name (case-insensitive). Required if id is not provided."),
                ]),
                "newName": .object([
                    "type": .string("string"),
                    "description": .string("New name for the accessory"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to disambiguate"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Room name to disambiguate"),
                ]),
            ]),
            "required": .array([.string("newName")]),
        ])
    )

    static let removeAccessory = Tool(
        name: "remove_accessory",
        description: "Permanently unpair a HomeKit accessory. Destructive and hard to reverse. Always ask the user for explicit confirmation before calling this tool. Pass confirm: true only after the user has confirmed.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Accessory unique identifier (from list_devices). Preferred over name."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Accessory name (case-insensitive). Required if id is not provided."),
                ]),
                "confirm": .object([
                    "type": .string("boolean"),
                    "description": .string("Must be true to execute. Without this, returns a warning instead of unpairing."),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to disambiguate"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Room name to disambiguate"),
                ]),
            ]),
        ])
    )

    static let identifyAccessory = Tool(
        name: "identify_accessory",
        description: "Trigger the identify action on a HomeKit accessory (typically causes it to blink or beep). Useful when reorganizing to confirm which physical device corresponds to a name.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Accessory unique identifier (from list_devices). Preferred over name."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Accessory name (case-insensitive). Required if id is not provided."),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to disambiguate"),
                ]),
                "room": .object([
                    "type": .string("string"),
                    "description": .string("Room name to disambiguate"),
                ]),
            ]),
        ])
    )

    static let addScene = Tool(
        name: "add_scene",
        description: "Create a new (empty) scene in a HomeKit home.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Name for the new scene"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name. Omit to use the primary home."),
                ]),
            ]),
            "required": .array([.string("name")]),
        ])
    )

    static let renameScene = Tool(
        name: "rename_scene",
        description: "Rename an existing HomeKit scene. Specify by name or unique ID (from list_scenes).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Scene unique identifier (from list_scenes). Preferred over name."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Scene name (case-insensitive). Required if id is not provided."),
                ]),
                "newName": .object([
                    "type": .string("string"),
                    "description": .string("New name for the scene"),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to disambiguate"),
                ]),
            ]),
            "required": .array([.string("newName")]),
        ])
    )

    static let removeScene = Tool(
        name: "remove_scene",
        description: "Delete a HomeKit scene. Specify by name or unique ID (from list_scenes).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Scene unique identifier (from list_scenes). Preferred over name."),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Scene name (case-insensitive). Required if id is not provided."),
                ]),
                "home": .object([
                    "type": .string("string"),
                    "description": .string("Home name to disambiguate"),
                ]),
            ]),
        ])
    )

    static let all: [Tool] = [
        listHomes, listRooms, listDevices, getDeviceState, controlDevice,
        batchControlDevices, batchGetDeviceState, controlDevicesByFilter,
        listScenes, executeScene,
        addRoom, renameRoom, removeRoom, moveAccessoryToRoom,
        listZones, addZone, renameZone, removeZone, addRoomToZone, removeRoomFromZone,
        renameAccessory, removeAccessory, identifyAccessory,
        addScene, renameScene, removeScene,
    ]
}
