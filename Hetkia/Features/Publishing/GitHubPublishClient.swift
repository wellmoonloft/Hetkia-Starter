import Foundation

struct GitHubPublishClient {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func validateAccess(config: PublishGitHubConfiguration, token: String) async throws {
    guard config.isFilled, !token.isEmpty else {
      throw PublishError.missingConfiguration(localized("publish.error.github.missing"))
    }
    let repoPath = "\(config.owner)/\(config.repository)"
    _ = try await request(
      path: "/repos/\(repoPath)",
      token: token,
      method: "GET"
    )
    _ = try await request(
      path: "/repos/\(repoPath)/branches/\(encoded(config.branch))",
      token: token,
      method: "GET"
    )
  }

  func pathExists(config: PublishGitHubConfiguration, token: String, path: String) async throws -> Bool {
    let repoPath = "\(config.owner)/\(config.repository)"
    do {
      _ = try await request(
        path: "/repos/\(repoPath)/contents/\(encoded(path))?ref=\(encoded(config.branch))",
        token: token,
        method: "GET"
      )
      return true
    } catch let error as PublishError {
      if case .github(let message) = error, message.contains("404") {
        return false
      }
      throw error
    }
  }

  func createMarkdownFile(
    config: PublishGitHubConfiguration,
    token: String,
    path: String,
    markdown: String,
    commitMessage: String
  ) async throws -> String {
    let repoPath = "\(config.owner)/\(config.repository)"
    let payload: [String: Any] = [
      "message": commitMessage,
      "content": Data(markdown.utf8).base64EncodedString(),
      "branch": config.branch,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    let response = try await request(
      path: "/repos/\(repoPath)/contents/\(encoded(path))",
      token: token,
      method: "PUT",
      body: data
    )
    if let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
       let commit = object["commit"] as? [String: Any],
       let sha = commit["sha"] as? String {
      return sha
    }
    return ""
  }

  private func request(path: String, token: String, method: String, body: Data? = nil) async throws -> Data {
    guard let url = URL(string: "https://api.github.com\(path)") else {
      throw PublishError.github(localized("publish.error.github.invalid"))
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Hetkia/1.0", forHTTPHeaderField: "User-Agent")
    request.httpBody = body
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw PublishError.github(localized("publish.error.github.network"))
    }
    if (200..<300).contains(http.statusCode) {
      return data
    }
    let message = parseGitHubError(data: data, status: http.statusCode)
    throw PublishError.github(message)
  }

  private func parseGitHubError(data: Data, status: Int) -> String {
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let message = object["message"] as? String {
      switch status {
      case 401:
        return localized("publish.error.github.unauthorized") + " (\(message))"
      case 403:
        return localized("publish.error.github.forbidden") + " (\(message))"
      case 404:
        return localized("publish.error.github.notFound") + " (404: \(message))"
      default:
        return "\(message) (HTTP \(status))"
      }
    }
    return "\(localized("publish.error.github.failed")) (HTTP \(status))"
  }

  private func encoded(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(.urlQueryAllowed)) ?? value
  }

  private func localized(_ key: String) -> String {
    HetkiaSystemLanguage.localizedString(key, comment: "")
  }
}
