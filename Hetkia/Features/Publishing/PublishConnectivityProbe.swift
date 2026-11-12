import Foundation

enum PublishConnectivityProbe {
  private static let probeSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 12
    return URLSession(configuration: configuration)
  }()

  static func probeBeforePublish(requiresR2: Bool, r2: PublishR2Configuration) async -> PublishError? {
    if let githubError = await probeGitHubAPI() {
      return githubError
    }
    if requiresR2 {
      if let endpointError = await probeR2Endpoint(r2: r2) {
        return endpointError
      }
      if let cdnError = await probeCDNDomain(r2: r2) {
        return cdnError
      }
    }
    return nil
  }

  private static func probeGitHubAPI() async -> PublishError? {
    guard let url = URL(string: "https://api.github.com/zen") else {
      return .connectivity(localized("publish.probe.github.failed"))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    do {
      let (_, response) = try await probeSession.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) else {
        return .connectivity(localized("publish.probe.github.failed"))
      }
      return nil
    } catch {
      return .connectivity(localized("publish.probe.github.failed"))
    }
  }

  private static func probeR2Endpoint(r2: PublishR2Configuration) async -> PublishError? {
    let endpoint = r2.endpoint
    guard let url = URL(string: endpoint) else {
      return .connectivity(localized("publish.probe.r2.failed"))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    do {
      let (_, response) = try await probeSession.data(for: request)
      guard response is HTTPURLResponse else {
        return .connectivity(localized("publish.probe.r2.failed"))
      }
      return nil
    } catch {
      return .connectivity(localized("publish.probe.r2.failed"))
    }
  }

  private static func probeCDNDomain(r2: PublishR2Configuration) async -> PublishError? {
    let domain = r2.normalizedCDNDomain()
    guard let url = URL(string: domain) else {
      return .connectivity(localized("publish.probe.cdn.failed"))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    do {
      let (_, response) = try await probeSession.data(for: request)
      guard response is HTTPURLResponse else {
        return .connectivity(localized("publish.probe.cdn.failed"))
      }
      return nil
    } catch {
      return .connectivity(localized("publish.probe.cdn.failed"))
    }
  }

  private static func localized(_ key: String) -> String {
    HetkiaSystemLanguage.localizedString(key, comment: "")
  }
}
