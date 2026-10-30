import Foundation
import Security

struct Credentials: Codable {
    var idType: String   // LoginIDType.rawValue
    var id: String
    var password: String
}

/// 자격증명만 Keychain에 저장. 카드정보는 저장하지 않는다.
enum KeychainStore {
    private static let service = "com.rob.korail4iOS.credentials"
    private static let account = "korail"

    static func save(_ c: Credentials) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Credentials? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let c = try? JSONDecoder().decode(Credentials.self, from: data) else { return nil }
        return c
    }

    static func clear() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
    }
}
