import Foundation
import os

/// App logging. Two sinks:
///   1. Apple unified logging (os.Logger) — the durable, readable home. Stream it with
///      `log stream --predicate 'subsystem == "ajwright.HomeKitMCP"'` or read history with
///      `log show --last 1h --predicate 'subsystem == "ajwright.HomeKitMCP"'`; also in Console.app.
///   2. stderr — kept so `claude --debug` (and any parent capturing the pipe) still sees output.
///
/// Messages are interpolated `.public`: os.Logger redacts interpolated values by default, and we
/// log only non-sensitive operational data (home/room/device names, tool names) — no credentials.
enum Log {
    private static let logger = Logger(subsystem: "ajwright.HomeKitMCP", category: "mcp")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        // .notice is the default level — persisted and shown by `log show` without extra flags.
        logger.notice("\(message, privacy: .public)")
        writeStderr("INFO", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writeStderr("ERROR", message)
    }

    static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        writeStderr("DEBUG", message)
        #endif
    }

    private static func writeStderr(_ level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
