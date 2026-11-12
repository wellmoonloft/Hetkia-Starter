import Foundation
import Security

enum PublishSecretsStore {
  enum Key: String {
    case githubToken = "hetkia.publish.github.token"
    case r2AccessKeyID = "hetkia.publish.r2.accessKeyID"
    case r2SecretAccessKey = "hetkia.publish.r2.secretAccessKey"
  }

  static func set(_ value: String, for key: Key) {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key.rawValue,
      kSecAttrService as String: "com.hetkia.publish",
    ]
    SecItemDelete(query as CFDictionary)
    guard !value.isEmpty else { return }
    var writeQuery = query
    writeQuery[kSecValueData as String] = data
    writeQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(writeQuery as CFDictionary, nil)
  }

  static func get(_ key: Key) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key.rawValue,
      kSecAttrService as String: "com.hetkia.publish",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static var hasGitHubToken: Bool {
    !(get(.githubToken)?.isEmpty ?? true)
  }

  static var hasR2Credentials: Bool {
    !(get(.r2AccessKeyID)?.isEmpty ?? true) && !(get(.r2SecretAccessKey)?.isEmpty ?? true)
  }
}
