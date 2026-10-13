import Foundation
import Security

enum SecretKind: String, Sendable {
    case syncHubToken = "sync-hub-token"
    case vaultMasterKey = "vault-master-key"
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain error \(status)"
        case .invalidData:
            "The Keychain item contains invalid data."
        }
    }
}

struct KeychainSecretStore: Sendable {
    private let service: String

    init(service: String = "com.yingshu0218.myshell") {
        self.service = service
    }

    func save(_ data: Data, kind: SecretKind) throws {
        let query = baseQuery(kind: kind)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: false,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0] = $1 }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func load(kind: SecretKind) throws -> Data? {
        var query = baseQuery(kind: kind)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        return data
    }

    func delete(kind: SecretKind) throws {
        let status = SecItemDelete(baseQuery(kind: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(kind: SecretKind) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: kind.rawValue,
            kSecAttrSynchronizable: false,
        ]
    }
}
