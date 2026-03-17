import Foundation
import Security

public struct KeychainManager: Sendable {
    private let service: String

    public enum AccessLevel: Sendable {
        case background
        case interactive
    }

    public init(service: String = "com.hackervalley.eddingsindex") {
        self.service = service
    }

    private func baseQuery(key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        #if os(iOS)
        query[kSecAttrAccessGroup as String] = "group.com.hackervalley.eddingsindex"
        #endif
        return query
    }

    public func store(key: String, data: Data, access: AccessLevel = .background, biometric: Bool = false) throws {
        let accessibility: CFString = switch access {
        case .background: kSecAttrAccessibleAfterFirstUnlock
        case .interactive: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        var attrs: [String: Any] = [
            kSecValueData as String: data,
        ]

        if biometric {
            var error: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                accessibility,
                .userPresence,
                &error
            ) else {
                throw KeychainError.storeFailed(errSecParam)
            }
            attrs[kSecAttrAccessControl as String] = accessControl
        } else {
            attrs[kSecAttrAccessible as String] = accessibility
        }

        let searchQuery = baseQuery(key: key)

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var addQuery = searchQuery
        for (k, v) in attrs { addQuery[k] = v }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.storeFailed(addStatus)
        }
    }

    public func retrieve(key: String) throws -> Data? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        if status == errSecInteractionNotAllowed {
            throw KeychainError.biometricDenied
        }

        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }

        return result as? Data
    }

    public func delete(key: String) throws {
        let query = baseQuery(key: key)

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - SimpleFin Convenience

    private static let simpleFinKey = "simplefin-access-url"

    public func storeSimpleFinAccessURL(_ urlString: String) throws {
        guard let data = urlString.data(using: .utf8) else {
            throw KeychainError.storeFailed(errSecParam)
        }
        try store(key: Self.simpleFinKey, data: data)
    }

    public func retrieveSimpleFinAccessURL() throws -> String? {
        guard let data = try retrieve(key: Self.simpleFinKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func deleteSimpleFinAccessURL() throws {
        try delete(key: Self.simpleFinKey)
    }

    public enum KeychainError: Error, Sendable {
        case storeFailed(OSStatus)
        case retrieveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case biometricDenied
    }
}
