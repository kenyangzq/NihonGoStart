import Foundation
import Security

// MARK: - Keychain Manager for Secure Token Storage

class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.ziqiyang.NihonGoStart.keychain"

    private init() {}

    // MARK: - Generic Keychain Operations

    func save(_ data: Data, forKey key: String) -> Bool {
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ] as CFDictionary

        // Delete existing item first
        SecItemDelete(query)

        // Add new item
        let status = SecItemAdd(query, nil)
        return status == errSecSuccess
    }

    func load(forKey key: String) -> Data? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)

        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        return nil
    }

    func delete(forKey key: String) -> Bool {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ] as CFDictionary

        let status = SecItemDelete(query)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Convenience Methods for Strings

    func saveString(_ string: String, forKey key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, forKey: key)
    }

    func loadString(forKey key: String) -> String? {
        guard let data = load(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Apple Music Specific Keys

    private enum Keys {
        static let userToken = "apple_music_user_token"
    }

    // MARK: - Apple Music Token Management

    func saveUserToken(_ token: String) -> Bool {
        return saveString(token, forKey: Keys.userToken)
    }

    func loadUserToken() -> String? {
        return loadString(forKey: Keys.userToken)
    }

    func deleteUserToken() -> Bool {
        return delete(forKey: Keys.userToken)
    }
}
