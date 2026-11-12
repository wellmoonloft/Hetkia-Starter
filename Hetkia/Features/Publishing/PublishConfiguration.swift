import Foundation

struct PublishGitHubConfiguration: Codable, Equatable {
    var owner: String = ""
    var repository: String = ""
    var branch: String = "main"
    var essayDirectory: String = "content/essay"
    var momentsDirectory: String = "content/moments"

    var isFilled: Bool {
        !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !essayDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !momentsDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func normalizedEssayDirectory() -> String {
        PublishConfiguration.normalizeDirectory(essayDirectory)
    }

    func normalizedMomentsDirectory() -> String {
        PublishConfiguration.normalizeDirectory(momentsDirectory)
    }
}

struct PublishR2Configuration: Codable, Equatable {
    var accountID: String = ""
    var bucketName: String = ""
    var cdnDomain: String = ""

    var endpoint: String {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "https://\(trimmed).r2.cloudflarestorage.com"
    }

    var isFilled: Bool {
        !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cdnDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func normalizedCDNDomain() -> String {
        var value = cdnDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.lowercased().hasPrefix("http") {
            value = "https://\(value)"
        }
        return value
    }

    /// CDN custom domain maps the bucket root; public URLs must not repeat the bucket name.
    func cdnRootURL() -> URL? {
        guard let url = URL(string: normalizedCDNDomain()) else { return nil }
        let bucket = bucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bucket.isEmpty else { return url }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path == bucket || path.split(separator: "/").last.map(String.init) == bucket else {
            return url
        }
        var trimmed = url
        while trimmed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").last.map(String.init) == bucket {
            trimmed = trimmed.deletingLastPathComponent()
        }
        return trimmed
    }

    func publicObjectKey(from storageKey: String) -> String {
        var key = storageKey.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bucket = bucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bucket.isEmpty, key.hasPrefix("\(bucket)/") {
            key = String(key.dropFirst(bucket.count + 1))
        }
        return key
    }

    func publicCDNURL(forStorageKey storageKey: String) -> String? {
        guard let root = cdnRootURL() else { return nil }
        let key = publicObjectKey(from: storageKey)
        guard !key.isEmpty else { return root.absoluteString }
        let base = root.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/\(key)"
    }
}

enum PublishConfiguration {
    static let githubDefaultsKey = "hetkia.publish.github"
    static let r2DefaultsKey = "hetkia.publish.r2"

    static func loadGitHub() -> PublishGitHubConfiguration {
        guard let data = UserDefaults.standard.data(forKey: githubDefaultsKey),
              let value = try? JSONDecoder().decode(PublishGitHubConfiguration.self, from: data) else {
            return PublishGitHubConfiguration()
        }
        return value
    }

    static func saveGitHub(_ configuration: PublishGitHubConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: githubDefaultsKey)
    }

    static func loadR2() -> PublishR2Configuration {
        guard let data = UserDefaults.standard.data(forKey: r2DefaultsKey),
              let value = try? JSONDecoder().decode(PublishR2Configuration.self, from: data) else {
            return PublishR2Configuration()
        }
        return value
    }

    static func saveR2(_ configuration: PublishR2Configuration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: r2DefaultsKey)
    }

    static func normalizeDirectory(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("/") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func joinPath(_ directory: String, fileName: String) -> String {
        let dir = normalizeDirectory(directory)
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return dir.isEmpty ? name : "\(dir)/\(name)"
    }
}
