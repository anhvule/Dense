import Foundation
import Security

public protocol KeyValueStore {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

public final class KeychainStore: KeyValueStore {
    private let service = "app.dense.mac"

    public init() {}

    public func string(forKey key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            return str
        }
        return UserDefaults.standard.string(forKey: "kv.\(key)") // file fallback
    }

    public func set(_ value: String, forKey key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(base as CFDictionary,
                                              [kSecValueData as String: Data(value.utf8)] as CFDictionary)
            if updateStatus == errSecSuccess {
                return
            }
        }
        // Both add and update (if attempted) failed: fall back to UserDefaults, and
        // best-effort remove any stale Keychain item so it can't shadow the fallback value.
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.set(value, forKey: "kv.\(key)")
    }
}

public enum LicenseStatus: Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed
}

public final class LicenseState {
    public static let trialDays = 7
    public static let offlineGraceDays = 14

    private let store: KeyValueStore
    private let now: () -> Date
    private let iso = ISO8601DateFormatter()

    public init(store: KeyValueStore, now: @escaping () -> Date = Date.init) {
        self.store = store; self.now = now
    }

    public func status() -> LicenseStatus {
        if store.string(forKey: "licenseKey") != nil {
            if let lastStr = store.string(forKey: "lastValidation"), let last = iso.date(from: lastStr) {
                let sinceValidation = now().timeIntervalSince(last)
                if sinceValidation > Double(Self.offlineGraceDays) * 86400 { return .trialExpired }
            }
            return .licensed
        }
        let start: Date
        if let s = store.string(forKey: "trialStart"), let d = iso.date(from: s) {
            start = d
        } else {
            start = now()
            store.set(iso.string(from: start), forKey: "trialStart")
        }
        let elapsed = now().timeIntervalSince(start)
        if elapsed < 0 { return .trialExpired } // clock rolled back
        let daysUsed = Int(elapsed / 86400)
        let left = Self.trialDays - daysUsed
        return left > 0 ? .trial(daysLeft: left) : .trialExpired
    }

    public func recordActivation(key: String, instanceID: String) {
        store.set(key, forKey: "licenseKey")
        store.set(instanceID, forKey: "instanceID")
        store.set(iso.string(from: now()), forKey: "lastValidation")
    }

    public func recordValidation(succeeded: Bool) {
        if succeeded { store.set(iso.string(from: now()), forKey: "lastValidation") }
    }
}
