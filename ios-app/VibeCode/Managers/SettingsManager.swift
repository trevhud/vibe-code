import Foundation
import Security
import OSLog

class SettingsManager {
    private let userDefaults = UserDefaults.standard
    private let profileKey = "vibe_code_profile"
    private let keychainService = "com.vibecode.app"
    
    func saveProfile(_ profile: ConnectionProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            userDefaults.set(data, forKey: profileKey)
        } catch {
            Logger.settings.error("Failed to save profile: \(error)")
        }
    }
    
    func loadProfile() -> ConnectionProfile? {
        guard let data = userDefaults.data(forKey: profileKey) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(ConnectionProfile.self, from: data)
        } catch {
            Logger.settings.error("Failed to load profile: \(error)")
            return nil
        }
    }
    
    func clearProfile() {
        userDefaults.removeObject(forKey: profileKey)
        // Also clear any stored credentials
        clearStoredCredentials()
    }
    
    // MARK: - ElevenLabs Agent ID

    private let elevenLabsAgentIdKey = "vibe_code_elevenlabs_agent_id"

    var elevenLabsAgentId: String? {
        get { userDefaults.string(forKey: elevenLabsAgentIdKey) }
        set { userDefaults.set(newValue, forKey: elevenLabsAgentIdKey) }
    }

    // MARK: - Relay Token

    private let relayTokenAccount = "relay_token"
    private let relayUrlKey = "vibe_code_relay_url"

    @discardableResult
    func storeRelayToken(_ token: String) -> Bool {
        return storePassword(token, for: relayTokenAccount)
    }

    func retrieveRelayToken() -> String? {
        return retrievePassword(for: relayTokenAccount)
    }

    // MARK: - Keychain Management

    func storePassword(_ password: String, for account: String) -> Bool {
        let data = password.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func retrievePassword(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    func storeSSHKey(_ privateKey: String, for account: String) -> Bool {
        let data = privateKey.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "\(account)_ssh_key",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func retrieveSSHKey(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "\(account)_ssh_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    private func clearStoredCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}