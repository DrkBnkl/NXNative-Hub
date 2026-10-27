import Foundation

// MARK: - Live log file (~/NXNative/build_live.log)
//
// Keeps one file handle open and writes on a serial background queue
// (shader builds produce tens of thousands of lines).

final class LiveLogWriter {
    static let shared = LiveLogWriter()

    private let queue = DispatchQueue(label: "org.nxnative.liveLog", qos: .utility)
    private var handle: FileHandle?
    private let path = NXPaths.liveLogPath

    /// Truncates the log file (start of a new build).
    func reset() {
        queue.async {
            try? self.handle?.close()
            self.handle = nil
            let dir = (self.path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: self.path, contents: nil)
        }
    }

    func append(_ line: String) {
        queue.async {
            if self.handle == nil {
                if !FileManager.default.fileExists(atPath: self.path) {
                    let dir = (self.path as NSString).deletingLastPathComponent
                    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: self.path, contents: nil)
                }
                self.handle = FileHandle(forWritingAtPath: self.path)
                _ = try? self.handle?.seekToEnd()
            }
            if let data = (line + "\n").data(using: .utf8) {
                try? self.handle?.write(contentsOf: data)
            }
        }
    }
}

// MARK: - Bounded log buffer for the UI

extension Array where Element == String {
    /// Appends a line and drops the oldest ones once `limit` is exceeded.
    /// Prevents unbounded memory growth during very long builds.
    mutating func appendCapped(_ line: String, limit: Int = 5_000) {
        append(line)
        if count > limit {
            removeFirst(count - limit)
        }
    }
}
