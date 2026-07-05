import Foundation

/// A portable snapshot of a home's organizational structure (format version 1).
nonisolated struct HomeSnapshot: Codable, Equatable {
    nonisolated struct HomeRef: Codable, Equatable {
        let name: String
        let uniqueIdentifier: String
    }
    var formatVersion: Int
    var createdAt: String
    var home: HomeRef
    var rooms: [RoomSnapshot]
    var zones: [ZoneSnapshot]
    var accessories: [AccessorySnapshot]
    var scenes: [SceneSnapshot]

    static let currentFormatVersion = 1
}

nonisolated struct RoomSnapshot: Codable, Equatable {
    let name: String
    let uniqueIdentifier: String
}

nonisolated struct ZoneSnapshot: Codable, Equatable {
    let name: String
    let uniqueIdentifier: String
    let rooms: [String]   // room names in this zone
}

nonisolated struct AccessorySnapshot: Codable, Equatable {
    let uniqueIdentifier: String
    let name: String
    let room: String
}

nonisolated struct SceneSnapshot: Codable, Equatable {
    let name: String
    let uniqueIdentifier: String
    let actions: [SceneAction]
}

/// One characteristic-write inside a scene. `targetValue` preserves the JSON
/// primitive (number/bool/string) so it round-trips without a wrapper object.
nonisolated struct SceneAction: Codable, Equatable {
    let accessory: String          // accessory uniqueIdentifier
    let characteristicType: String
    let targetValue: JSONValue
    // The exact characteristic's uniqueIdentifier. Disambiguates multi-service accessories
    // (e.g. a multi-gang switch exposing the same characteristicType on several services),
    // where matching by type alone would target an arbitrary one. Optional for backward
    // compatibility with v1 backups written before this field existed.
    var characteristicIdentifier: String? = nil
}

/// Minimal JSON primitive holder so heterogeneous HomeKit characteristic values
/// survive Codable round-trips as raw JSON.
///
/// JSON has exactly one numeric type, so there's no way to distinguish an
/// "int" from a "double" once a value has been through an encode/decode
/// cycle (which every persisted snapshot goes through). Modeling two numeric
/// cases here would leave one of them permanently dead after a JSON
/// round-trip, so numbers are represented with a single `.number(Double)`
/// case that matches what JSON actually is. A later task coerces this to the
/// exact HomeKit characteristic type (Int, Bool, etc.) at write time.
nonisolated enum JSONValue: Codable, Equatable {
    case number(Double), bool(Bool), string(String), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Bool MUST be tried before Double: Foundation's JSONDecoder will
        // happily decode `true`/`false` as 1.0/0.0 if Double is tried first.
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .string(let s): try c.encode(s)
        case .null: try c.encodeNil()
        }
    }

    /// The native value for handing to HomeKit as a characteristic target.
    var anyValue: Any {
        switch self {
        case .number(let d): return d
        case .bool(let b): return b
        case .string(let s): return s
        case .null: return NSNull()
        }
    }
}
