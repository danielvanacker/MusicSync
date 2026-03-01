import Foundation
import Security

enum KeychainHelper {
    static func save(_ data: Data, for key: String, service: String = Bundle.main.bundleIdentifier ?? "com.danielvanacker.MusicSync") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave(status: status)
        }
    }

    static func load(for key: String, service: String = Bundle.main.bundleIdentifier ?? "com.danielvanacker.MusicSync") throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unableToLoad(status: status)
        }
        return data
    }

    static func delete(for key: String, service: String = Bundle.main.bundleIdentifier ?? "com.danielvanacker.MusicSync") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unableToDelete(status: status)
        }
    }

    static func exists(for key: String, service: String = Bundle.main.bundleIdentifier ?? "com.danielvanacker.MusicSync") -> Bool {
        (try? load(for: key, service: service)) != nil
    }
}

enum KeychainError: Error {
    case unableToSave(status: OSStatus)
    case unableToLoad(status: OSStatus)
    case unableToDelete(status: OSStatus)
}
