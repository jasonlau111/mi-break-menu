import Foundation
import Security

nonisolated struct CloudSession: Codable, Sendable {
    let region: String
    let user: String
    let token: String
    let security: String
}
nonisolated struct Sensor: Codable, Identifiable, Sendable {
    let name: String
    let model: String
    let did: String
    let supported: Bool
    var id: String { did }
}
nonisolated struct Account: Codable, Sendable {
    let session: CloudSession
    let sensor: Sensor
}
nonisolated struct Reading: Decodable, Sendable {
    let presence: Presence
    let online: Bool?
    let note: String
    let deviceName: String?
}
nonisolated struct Reply: Decodable, Sendable {
    var error: String?
    var session: CloudSession?
    var devices: [Sensor]?
    var reading: Reading?
}
nonisolated enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}

@MainActor enum Vault {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MiBreakMenu", kSecAttrAccount as String: "cloud"] }
    static func load() throws -> Account? {
        var q = query; q[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AppFailure.message("无法读取钥匙串，请检查系统授权") }
        return try JSONDecoder().decode(Account.self, from: data)
    }
    static func save(_ account: Account) throws {
        let data = try JSONEncoder().encode(account)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw AppFailure.message("无法保存登录会话到钥匙串") }
        } else if result != errSecSuccess { throw AppFailure.message("无法更新钥匙串") }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppFailure.message("无法删除钥匙串中的登录会话") }
    }
}

@MainActor final class Journal {
    private let url: URL
    private var writable = true
    init(root: URL? = nil) throws {
        let folder = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MiBreakMenu", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        url = folder.appendingPathComponent("history.json")
    }
    func load() throws -> BreakEngine {
        guard FileManager.default.fileExists(atPath: url.path) else { return BreakEngine() }
        do {
            let data = try Data(contentsOf: url)
            let saved = try JSONDecoder().decode(Snapshot.self, from: data)
            guard saved.version == 1 else { throw AppFailure.message("记录版本不兼容") }
            return saved.engine
        } catch {
            writable = false
            throw AppFailure.message("历史记录无法读取，已停止写入以保护原文件")
        }
    }
    func save(_ engine: BreakEngine) throws {
        guard writable else { throw AppFailure.message("历史文件需修复，当前记录尚未保存") }
        let data = try JSONEncoder().encode(Snapshot(version: 1, engine: engine))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private struct Snapshot: Codable { let version: Int; let engine: BreakEngine }
}
