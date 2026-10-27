import Foundation

// MARK: - Synchronous commands (git, ps, pip, dotnet, ditto)
//
// Executables are started directly with an argument array – no `zsh -c` and no
// quoting, so paths containing quotes cannot break or inject commands.

enum CommandRunner {
    struct Result {
        let output: String
        let exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
        var trimmedOutput: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Runs an executable synchronously. Do not call on the main thread.
    @discardableResult
    static func run(_ executable: String,
                    _ arguments: [String],
                    environment: [String: String]? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment ?? NXPaths.toolEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return Result(output: error.localizedDescription, exitCode: -1)
        }

        // Read first, then wait – otherwise a full pipe buffer (> ~64 KB) deadlocks.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(output: String(decoding: data, as: UTF8.self), exitCode: process.terminationStatus)
    }

    /// Runs a tool via the (extended) PATH, e.g. `git`.
    @discardableResult
    static func tool(_ name: String, _ arguments: [String]) -> Result {
        run("/usr/bin/env", [name] + arguments)
    }

    @discardableResult
    static func git(_ repo: String, _ arguments: String...) -> Result {
        tool("git", ["-C", repo] + arguments)
    }
}

// MARK: - Long-running process with line-based output (build script)
//
// Shared by BuildManager and ImportBatchManager.
//  - A trailing line without a newline is still delivered.
//  - `onExit` fires only after ALL output lines have been delivered.
//  - All callbacks run on the main thread.

final class StreamingProcess {
    var onStdoutLine: ((String) -> Void)?
    var onStderrLine: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?

    private let process = Process()
    private let outputGroup = DispatchGroup()
    private let readQueue = DispatchQueue(label: "org.nxnative.processOutput",
                                          qos: .userInitiated,
                                          attributes: .concurrent)

    init(executable: String, arguments: [String], environment: [String: String] = NXPaths.toolEnvironment()) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
    }

    var isRunning: Bool { process.isRunning }

    func start() throws {
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        outputGroup.enter()
        outputGroup.enter()

        let group = outputGroup
        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            group.notify(queue: .main) {
                self?.onExit?(status)
            }
        }

        do {
            try process.run()
        } catch {
            outputGroup.leave()
            outputGroup.leave()
            throw error
        }

        readLines(from: outPipe.fileHandleForReading) { [weak self] line in self?.onStdoutLine?(line) }
        readLines(from: errPipe.fileHandleForReading) { [weak self] line in self?.onStderrLine?(line) }
    }

    /// Sends SIGINT (graceful cancel, lets Python clean up).
    func interrupt() {
        if process.isRunning { process.interrupt() }
    }

    /// Sends SIGTERM.
    func terminate() {
        if process.isRunning { process.terminate() }
    }

    private func readLines(from handle: FileHandle, deliver: @escaping (String) -> Void) {
        let group = outputGroup
        readQueue.async {
            var buffer = Data()

            func emit(_ data: Data) {
                let line = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { deliver(line) }
            }

            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    emit(buffer.subdata(in: buffer.startIndex..<newline))
                    buffer.removeSubrange(buffer.startIndex...newline)
                }
            }
            if !buffer.isEmpty { emit(buffer) }

            // Enqueued on main after all lines → ordering is guaranteed.
            DispatchQueue.main.async { group.leave() }
        }
    }
}
