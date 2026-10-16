import Foundation

// Blocking pipe reads stay off the UI executor. Each helper emits a bounded JSON reply.
@concurrent nonisolated func collectPipe(_ handle: FileHandle) async -> Data { handle.readDataToEndOfFile() }

@MainActor final class Bridge {
    private var process: Process?
    func cancel() { if let process, process.isRunning { process.terminate() } }
    func call(_ request: [String: Any]) async throws -> Reply {
        guard process == nil else { throw AppFailure.message("正在连接，请稍候") }
        guard let root = Bundle.main.resourceURL else { throw AppFailure.message("应用资源缺失") }
        let input = Pipe(), output = Pipe(), child = Process()
        child.executableURL = root.appendingPathComponent("mi-break-core")
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        let data = try JSONSerialization.data(withJSONObject: request)
        try child.run(); process = child
        defer {
            if child.isRunning { child.terminate() }
            process = nil
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        async let bytes = collectPipe(output.fileHandleForReading)
        try input.fileHandleForWriting.write(contentsOf: data)
        try input.fileHandleForWriting.close()
        let timeout = ContinuousClock.now.advanced(by: .seconds(request["op"] as? String == "pair" ? 180 : 40))
        do {
            while child.isRunning {
                try await Task.sleep(for: .milliseconds(100))
                if ContinuousClock.now > timeout { throw AppFailure.message("连接超时，请重试") }
            }
        } catch {
            if child.isRunning { child.terminate() }
            throw error
        }
        let result = await bytes
        try Task.checkCancellation()
        guard child.terminationStatus == 0, !result.isEmpty else { throw AppFailure.message("连接已结束，请重新尝试") }
        let reply = try JSONDecoder().decode(Reply.self, from: result)
        if let error = reply.error { throw AppFailure.message(error) }
        return reply
    }
}
