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
}

/// Minimal JSON primitive holder so heterogeneous HomeKit characteristic values
/// survive Codable round-trips as raw JSON.
nonisolated enum JSONValue: Codable, Equatable {
    case bool(Bool), int(Int), double(Double), string(String), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Try Double before Int: JSON has one number type, so a whole-number
        // literal like "30" matches both Int and Double decoders. Foundation's
        // JSONDecoder doesn't expose whether the source literal had a decimal
        // point, so this order can't be "fixed" to perfectly recover the
        // original Swift type in all cases — it's an inherent JSON round-trip
        // ambiguity, not a bug in this reordering. Preferring Double here means
        // whole-number values written by `.int(n)` decode back as `.double(n)`;
        // `.int` remains reachable only for values constructed directly in code
        // (never produced by decoding a plain JSON number).
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .null: try c.encodeNil()
        }
    }

    /// The native value for handing to HomeKit as a characteristic target.
    var anyValue: Any {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .null: return NSNull()
        }
    }
}
