import Foundation

/// A fresh, bounded connection keeps teardown independent of SDK reconnect callbacks.
nonisolated enum AtollCleanup {
    static func dismiss() async -> Bool {
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:9020")!)
        socket.resume()
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }
        defer {
            deadline.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }
        let id = UUID().uuidString
        do {
            let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": "atoll.dismissLiveActivity",
                "params": ["activityID": "mi-break-presence", "bundleIdentifier": "app.mibreak.menu"]]
            try await socket.send(.data(JSONSerialization.data(withJSONObject: request)))
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .data(let bytes): data = bytes
                case .string(let string): data = Data(string.utf8)
                @unknown default: return false
                }
                guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["id"] as? String == id else { continue }
                return reply["error"] == nil && reply["result"] != nil
            }
        } catch { }
        return false
    }
}
