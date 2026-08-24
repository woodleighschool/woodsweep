import Foundation
import Security
import Testing
@testable import WoodSweep

@Suite("Credential store")
struct CredentialStoreTests {
    @Test("queries the private data-protection Keychain group")
    func usesDataProtectionKeychain() {
        let query = KeychainCredentialStore.itemQuery(
            for: .serverPassword
        )

        #expect(query[kSecClass as String] as? String
            == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String
            == "au.edu.vic.woodleigh.WoodSweep.credentials")
        #expect(query[kSecAttrAccount as String] as? String
            == CredentialKey.serverPassword.rawValue)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(query[kSecAttrAccessGroup as String] == nil)
        #expect(query[kSecAttrAccessible as String] == nil)
    }

    @Test("new credentials remain available after unlock on this Mac only")
    func constrainsNewCredentialAccessibility() {
        let query = KeychainCredentialStore.addQuery(
            "machine-password",
            for: .serverPassword
        )

        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(query[kSecAttrAccessGroup as String] == nil)
        #expect(query[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(query[kSecValueData as String] as? Data
            == Data("machine-password".utf8))
    }
}
