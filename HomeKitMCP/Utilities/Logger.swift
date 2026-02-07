import Foundation

enum Log {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    static func debug(_ message: String) {
        #if DEBUG
        write("DEBUG", message)
        #endif
    }

    private static func write(_ level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
