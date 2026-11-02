import Foundation
import TranslationCore

/// Credentials live only in the app's local data directory, separate from history.
/// No Keychain lookup or migration is performed, including on first launch.
enum APICredentials {
    private static let store = APICredentialStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LinguaMac/Credentials", isDirectory: true))

    static func read(endpoint: URL) throws -> String? { try store.read(endpoint: endpoint) }
    static func save(_ key: String, endpoint: URL) throws { try store.save(key, endpoint: endpoint) }
}

/// Serializes read-modify-write operations so endpoint changes cannot lose keys.
final class APICredentialStore: Sendable {
    private let directory: URL
    private let lock = NSLock()
    private var file: URL { directory.appendingPathComponent("api-keys.json") }

    init(directory: URL) { self.directory = directory }

    private func account(_ endpoint: URL) -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.port == 443 && components.scheme == "https" { components.port = nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.string!
    }

    private func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
    }

    func read(endpoint: URL) throws -> String? {
        try lock.withLock {
            do { return try load()[account(endpoint)] }
            catch { throw TranslationError.backend("无法读取本地 API 凭据。可重新输入 API Key，本次会话仍可使用。") }
        }
    }

    func save(_ key: String, endpoint: URL) throws {
        try lock.withLock {
            do {
                var keys = try load()
                let account = account(endpoint)
                if key.isEmpty {
                    guard keys.removeValue(forKey: account) != nil else { return }
                    if keys.isEmpty {
                        try FileManager.default.removeItem(at: file)
                        return
                    }
                } else { keys[account] = key }
                // The private directory protects even the temporary file used by
                // atomic writes. Restrict the final file as well after replacement.
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                try JSONEncoder().encode(keys).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            } catch { throw TranslationError.backend("无法保存本地 API 凭据。可重新输入 API Key，本次会话仍可使用。") }
        }
    }
}
