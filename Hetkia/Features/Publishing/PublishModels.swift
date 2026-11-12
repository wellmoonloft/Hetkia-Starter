import Foundation
import SwiftData

enum PublishContentType: String, Codable, CaseIterable {
  case essay
  case moment
}

enum EssayPublishDateMode: String, CaseIterable, Identifiable {
  case now
  case capture

  var id: String { rawValue }
}

enum PublishTaskStatus: String, Codable {
  case draft
  case checkingConfiguration
  case uploadingImages
  case imageUploadFailed
  case preparingMarkdown
  case uploadingGitHub
  case githubUploadFailed
  case published
}

enum PublishImageUploadStatus: String, Codable {
  case pending
  case succeeded
  case failed
}

struct PublishImageUploadRecord: Codable, Equatable, Identifiable {
  var id: UUID { localImageID }
  var localImageID: UUID
  var remoteKey: String?
  var remoteURL: String?
  var status: PublishImageUploadStatus
}

@Model
final class PublishTask {
  @Attribute(.unique) var id: UUID
  var sourceJournalDayKey: String?
  var contentTypeRaw: String
  var statusRaw: String
  var titleDraft: String
  var bodyDraft: String
  var contentCreatedAt: Date
  var imageRecordsData: Data?
  var markdownDraft: String?
  var githubPath: String?
  var githubCommitSHA: String?
  var publishedAt: Date?
  var lastErrorMessage: String?
  var createdAt: Date
  var updatedAt: Date

  init(
    contentType: PublishContentType,
    title: String,
    body: String,
    contentCreatedAt: Date,
    sourceJournalDayKey: String?
  ) {
    self.id = UUID()
    self.contentTypeRaw = contentType.rawValue
    self.statusRaw = PublishTaskStatus.draft.rawValue
    self.titleDraft = title
    self.bodyDraft = body
    self.contentCreatedAt = contentCreatedAt
    self.sourceJournalDayKey = sourceJournalDayKey
    self.imageRecordsData = nil
    self.markdownDraft = nil
    self.githubPath = nil
    self.githubCommitSHA = nil
    self.publishedAt = nil
    self.lastErrorMessage = nil
    self.createdAt = .now
    self.updatedAt = .now
  }

  var contentType: PublishContentType {
    get { PublishContentType(rawValue: contentTypeRaw) ?? .essay }
    set { contentTypeRaw = newValue.rawValue }
  }

  var status: PublishTaskStatus {
    get { PublishTaskStatus(rawValue: statusRaw) ?? .draft }
    set { statusRaw = newValue.rawValue; updatedAt = .now }
  }

  var imageRecords: [PublishImageUploadRecord] {
    get {
      guard let imageRecordsData else { return [] }
      return (try? JSONDecoder().decode([PublishImageUploadRecord].self, from: imageRecordsData)) ?? []
    }
    set {
      imageRecordsData = try? JSONEncoder().encode(newValue)
      updatedAt = .now
    }
  }
}

struct RemotePublishDraft: Equatable {
  var contentType: PublishContentType
  var title: String
  var body: String
  var contentCreatedAt: Date
  var sourceJournalDayKey: String?
  var photoIDs: [UUID]
}

enum PublishError: LocalizedError {
  case missingConfiguration(String)
  case connectivity(String)
  case validation(String)
  case github(String)
  case r2(String)
  case imageEncoding(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .missingConfiguration(let message),
         .connectivity(let message),
         .validation(let message),
         .github(let message),
         .r2(let message),
         .imageEncoding(let message):
      return message
    case .cancelled:
      return HetkiaSystemLanguage.localizedString("publish.error.cancelled", comment: "")
    }
  }
}
