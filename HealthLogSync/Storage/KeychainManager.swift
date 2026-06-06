import Foundation
import Security

enum KeychainKey: String {
    case accessToken = "com.healthlogsync.accessToken"
    case refreshToken = "com.healthlogsync.refreshToken"
    case biometricEmail = "com.healthlogsync.biometricEmail"
    case biometricPassword = "com.healthlogsync.biometricPassword"
    /// Plain (no biometry gate) marker — set when biometric credentials are saved.
    case biometricCredentialsSaved = "com.healthlogsync.biometricCredentialsSaved"
}

final class KeychainManager {
    static let shared = KeychainManager()
    private init() {}

    func save(_ value: String, for key: KeychainKey) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func get(_ key: KeychainKey) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: KeychainKey) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func deleteAll() {
        delete(.accessToken)
        delete(.refreshToken)
    }

    // MARK: - Biometric credentials

    /// Saves email and password protected by biometry. Returns true on success.
    @discardableResult
    func saveBiometricCredentials(email: String, password: String) -> Bool {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            nil
        ) else { return false }

        let emailData = Data(email.utf8)
        let passwordData = Data(password.utf8)

        func storeItem(account: KeychainKey, data: Data) -> Bool {
            let deleteQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: account.rawValue,
            ]
            SecItemDelete(deleteQuery as CFDictionary)
            let addQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: account.rawValue,
                kSecValueData: data,
                kSecAttrAccessControl: access,
            ]
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        let stored = storeItem(account: .biometricEmail, data: emailData)
            && storeItem(account: .biometricPassword, data: passwordData)
        if stored {
            // Store a plain (no biometry gate) marker so hasBiometricCredentials
            // can be checked without triggering a biometric prompt.
            save("1", for: .biometricCredentialsSaved)
        }
        return stored
    }

    /// Returns stored biometric email+password pair, or nil if none saved.
    func biometricCredentials() -> (email: String, password: String)? {
        func loadItem(account: KeychainKey) -> String? {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: account.rawValue,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard let email = loadItem(account: .biometricEmail),
              let password = loadItem(account: .biometricPassword) else { return nil }
        return (email, password)
    }

    func deleteBiometricCredentials() {
        delete(.biometricEmail)
        delete(.biometricPassword)
        delete(.biometricCredentialsSaved)
    }

    /// Returns true without triggering a biometric prompt.
    var hasBiometricCredentials: Bool {
        get(.biometricCredentialsSaved) != nil
    }
}
