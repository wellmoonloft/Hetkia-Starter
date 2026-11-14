import Foundation

enum HugoMarkdownBuilder {
  private static var hugoDateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.autoupdatingCurrent
    formatter.timeZone = TimeZone.autoupdatingCurrent
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
  }

  private static var momentTitleFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.autoupdatingCurrent
    formatter.timeZone = TimeZone.autoupdatingCurrent
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter
  }

  static func hugoDateString(for date: Date) -> String {
    hugoDateFormatter.string(from: date)
  }

  static func momentTitle(for date: Date, uniqueSuffix: String? = nil) -> String {
    let base = momentTitleFormatter.string(from: date)
    guard let uniqueSuffix, !uniqueSuffix.isEmpty else { return base }
    return "\(base)-\(uniqueSuffix)"
  }

  static func uniqueFileStem(contentType: PublishContentType, createdAt: Date) -> String {
    let prefix = contentType == .essay ? "essay" : "moment"
    let stamp = momentTitleFormatter.string(from: createdAt)
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    return "\(prefix)-\(stamp)-\(suffix)"
  }

  static func buildEssayMarkdown(title: String, body: String, createdAt: Date, imageURLs: [String]) -> String {
    let frontMatter = essayFrontMatter(title: title, createdAt: createdAt)
  return assemble(frontMatter: frontMatter, body: body, imageURLs: imageURLs)
  }

  static func buildMomentMarkdown(createdAt: Date, body: String, imageURLs: [String] = [], uniqueSuffix: String? = nil) -> String {
    let title = momentTitle(for: createdAt, uniqueSuffix: uniqueSuffix)
    let frontMatter = momentFrontMatter(title: title, createdAt: createdAt)
    return assemble(frontMatter: frontMatter, body: body, imageURLs: imageURLs)
  }

  private static func essayFrontMatter(title: String, createdAt: Date) -> String {
    """
    ---
    title: "\(yamlEscaped(title))"
    categories:
      - essay
    order:
    date: \(hugoDateString(for: createdAt))
    tags:
    url:
    ---
    """
  }

  private static func momentFrontMatter(title: String, createdAt: Date) -> String {
    """
    ---
    title: "\(yamlEscaped(title))"
    categories:
      - moment
    order:
    date: \(hugoDateString(for: createdAt))
    tags:
    ---
    """
  }

  private static func assemble(frontMatter: String, body: String, imageURLs: [String]) -> String {
    var lines = [frontMatter, ""]
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedBody.isEmpty {
      lines.append(trimmedBody)
    }
    if !imageURLs.isEmpty {
      if !trimmedBody.isEmpty { lines.append("") }
      for url in imageURLs {
        lines.append("![](\(url))")
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func yamlEscaped(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}
