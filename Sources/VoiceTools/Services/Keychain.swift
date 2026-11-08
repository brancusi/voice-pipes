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

    /// Saves (or, with nil or "", removes) a secret. Returns why it failed, in macOS's words, or nil when it worked;
    /// a key that silently didn't save looked like a paste that did nothing.
    @discardableResult
    static func set(_ value: String?, for account: String) -> String? {
        #if SNAPSHOTS
        return nil
        #else
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound ? nil : message(status)
        }
        let data = Data(value.utf8)
        // Update in place first: deleting can fail (an item another build made) and leave the old key behind.
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        } else if status != errSecSuccess {
            SecItemDelete(base as CFDictionary)
            var add = base
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess { NSLog("VoiceTools: Keychain save for \(account) failed: \(status)") }
        return status == errSecSuccess ? nil : message(status)
        #endif
    }

    /// Removes every Voice Pipes item (provider keys and your secrets): nil when it worked, or why not.
    static func removeAll() -> String? {
        #if SNAPSHOTS
        return nil
        #else
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound ? nil : message(status)
        #endif
    }

    private static func message(_ status: OSStatus) -> String {
        "\(SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error") (\(status))"
    }
}

enum SecretKey {
    static let openRouter = "openrouter"
    static let typesafe = "typesafe"
}
