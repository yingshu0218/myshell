import Foundation
import Security
import XCTest
@testable import MyShell

final class KeychainSecretStoreTests: XCTestCase {
    func testStoresAndDeletesNonSynchronizableDeviceOnlySecret() throws {
        let service = "com.yingshu0218.myshell.tests.\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        defer { try? store.delete(kind: .syncHubToken) }

        try store.save(Data("test-secret".utf8), kind: .syncHubToken)
        XCTAssertEqual(
            try store.load(kind: .syncHubToken),
            Data("test-secret".utf8)
        )

        XCTAssertEqual(
            matchingStatus(
                service: service,
                account: SecretKind.syncHubToken.rawValue,
                synchronizable: false,
                accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ),
            errSecSuccess
        )
        XCTAssertEqual(
            matchingStatus(
                service: service,
                account: SecretKind.syncHubToken.rawValue,
                synchronizable: true,
                accessible: nil
            ),
            errSecItemNotFound
        )

        try store.delete(kind: .syncHubToken)
        XCTAssertNil(try store.load(kind: .syncHubToken))
    }

    private func matchingStatus(
        service: String,
        account: String,
        synchronizable: Bool,
        accessible: CFString?
    ) -> OSStatus {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let accessible {
            query[kSecAttrAccessible] = accessible
        }
        return SecItemCopyMatching(query as CFDictionary, nil)
    }
}
