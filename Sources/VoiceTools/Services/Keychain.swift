import Foundation
import Security

enum Keychain {
    private static let service = "io.github.brancusi.voice-tools"

    static func get(_ account: String) -> String? {
        #if SNAPSHOTS
        // The offscreen harness never touches the real Keychain (an unsigned binary would prompt for it).
        return account == SecretKey.openRouter ? "sk-or-v1-0000000000000000000000000003f9a" : "ts_live_0000000000000081c2"
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #endif
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum SecretKey {
    static let openRouter = "openrouter"
    static let typesafe = "typesafe"
}
