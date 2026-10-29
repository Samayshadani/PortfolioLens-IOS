import Foundation
import LocalAuthentication
import Security

enum KeychainStore {
    static func save(_ value: String, account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func read(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// API keys live only in the Keychain, never in UserDefaults or source code.
enum CredentialStore {
    private static let service = "com.portfoliolens.alpaca"

    static func loadAlpaca() -> AlpacaCredentials? {
        guard let keyID = KeychainStore.read(account: "keyID", service: service),
              let secret = KeychainStore.read(account: "secretKey", service: service),
              !keyID.isEmpty, !secret.isEmpty else { return nil }
        return AlpacaCredentials(keyID: keyID, secretKey: secret)
    }

    static func saveAlpaca(_ credentials: AlpacaCredentials) throws {
        try KeychainStore.save(credentials.keyID, account: "keyID", service: service)
        try KeychainStore.save(credentials.secretKey, account: "secretKey", service: service)
    }

    static func deleteAlpaca() {
        KeychainStore.delete(account: "keyID", service: service)
        KeychainStore.delete(account: "secretKey", service: service)
    }
}

enum BiometricAuthenticator {
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Falls back to the device passcode. Devices with no passcode at all are never locked out.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
