import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidDataEncoding
}

/// Secure secret storage backed by macOS Keychain (`Security.framework`).
/// Never writes credentials in plaintext to SQLite or the filesystem (PRD Section 8).
public final class KeychainAdapter: @unchecked Sendable {
    public let service: String
    private let inMemoryFallback: Bool
    private var memoryStore: [String: String] = [:]
    private let lock = NSLock()

    public init(service: String = "com.projectisland.secrets", inMemoryFallback: Bool = false) {
        self.service = service
        self.inMemoryFallback = inMemoryFallback
    }

    public func setSecret(_ value: String, for account: String) throws {
        if inMemoryFallback {
            lock.lock()
            defer { lock.unlock() }
            memoryStore[account] = value
            return
        }

        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidDataEncoding
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        throw KeychainError.unexpectedStatus(updateStatus)
    }

    public func getSecret(for account: String) throws -> String? {
        if inMemoryFallback {
            lock.lock()
            defer { lock.unlock() }
            return memoryStore[account]
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let decoded = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidDataEncoding
        }
        return decoded
    }

    public func deleteSecret(for account: String) throws {
        if inMemoryFallback {
            lock.lock()
            defer { lock.unlock() }
            memoryStore.removeValue(forKey: account)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
