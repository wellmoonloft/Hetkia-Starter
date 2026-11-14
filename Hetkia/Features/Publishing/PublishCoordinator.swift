import Combine
import Foundation
import SwiftData

enum PublishProgressStage: Equatable {
  case checkingConnectivity
  case validatingGitHub
  case validatingR2
  case uploadingImage(current: Int, total: Int)
  case preparingMarkdown
  case uploadingGitHub
  case succeeded(commitSHA: String, path: String)
}

@MainActor
final class PublishCoordinator: ObservableObject {
  @Published var stage: PublishProgressStage?
  @Published var isPublishing = false

  private let github = GitHubPublishClient()
  private let r2 = R2S3Client()

  func publish(
    draft: RemotePublishDraft,
    photosByID: [UUID: JournalPhotoRecord],
    savedOnly: Bool,
    modelContext: ModelContext
  ) async -> Result<String, PublishError> {
    guard !isPublishing else { return .failure(.cancelled) }
    isPublishing = true
    defer {
      isPublishing = false
      stage = nil
    }

    let token = PublishSecretsStore.get(.githubToken) ?? ""
    let githubConfig = PublishConfiguration.loadGitHub()
    let r2Config = PublishConfiguration.loadR2()
    let accessKey = PublishSecretsStore.get(.r2AccessKeyID) ?? ""
    let secretKey = PublishSecretsStore.get(.r2SecretAccessKey) ?? ""

    let validationError = validateDraft(draft)
    if let validationError { return .failure(validationError) }

    let selectedPhotos: [JournalPhotoRecord] = draft.photoIDs.compactMap { photosByID[$0] }
    let requiresR2 = !selectedPhotos.isEmpty

    stage = .checkingConnectivity
    if let probeError = await PublishConnectivityProbe.probeBeforePublish(requiresR2: requiresR2, r2: r2Config) {
      return .failure(probeError)
    }

    stage = .validatingGitHub
    do {
      try await github.validateAccess(config: githubConfig, token: token)
    } catch let error as PublishError {
      return .failure(error)
    } catch {
      return .failure(.github(error.localizedDescription))
    }

    if requiresR2 {
      stage = .validatingR2
      do {
        try await r2.validateAccess(config: r2Config, accessKeyID: accessKey, secretAccessKey: secretKey)
      } catch let error as PublishError {
        return .failure(error)
      } catch {
        return .failure(.r2(error.localizedDescription))
      }
    }

    let task = PublishTask(
      contentType: draft.contentType,
      title: draft.title,
      body: draft.body,
      contentCreatedAt: draft.contentCreatedAt,
      sourceJournalDayKey: draft.sourceJournalDayKey
    )
    modelContext.insert(task)

    var imageRecords: [PublishImageUploadRecord] = selectedPhotos.map {
      PublishImageUploadRecord(localImageID: $0.id, remoteKey: nil, remoteURL: nil, status: .pending)
    }
    task.imageRecords = imageRecords
    task.status = requiresR2 ? .uploadingImages : .preparingMarkdown

    var imageURLs: [String] = []
    if requiresR2 {
      for (index, photo) in selectedPhotos.enumerated() {
        stage = .uploadingImage(current: index + 1, total: selectedPhotos.count)
        let recordIndex = imageRecords.firstIndex(where: { $0.localImageID == photo.id })
        if let recordIndex,
           let existing = imageRecords[safe: recordIndex], existing.status == .succeeded,
           let url = existing.remoteURL, !url.isEmpty {
          imageURLs.append(url)
          continue
        }
        do {
          let jpeg = try await PublishImageEncoder.jpegData(from: photo, savedOnly: savedOnly)
          let r2Prefix = draft.contentType == .essay ? "essay" : "moment"
          let key = uniqueObjectKey(
            prefix: r2Prefix,
            stem: HugoMarkdownBuilder.uniqueFileStem(contentType: draft.contentType, createdAt: draft.contentCreatedAt)
          )
          try await r2.putJPEG(
            data: jpeg,
            objectKey: key,
            config: r2Config,
            accessKeyID: accessKey,
            secretAccessKey: secretKey
          )
          guard let url = r2.cdnURL(for: key, config: r2Config), URL(string: url) != nil else {
            task.status = .imageUploadFailed
            task.lastErrorMessage = PublishError.r2(localized("publish.error.r2.cdn")).localizedDescription
            try? modelContext.save()
            return .failure(.r2(localized("publish.error.r2.cdn")))
          }
          if let recordIndex {
            imageRecords[recordIndex].remoteKey = key
            imageRecords[recordIndex].remoteURL = url
            imageRecords[recordIndex].status = .succeeded
            task.imageRecords = imageRecords
          }
          imageURLs.append(url)
        } catch let error as PublishError {
          if let recordIndex {
            imageRecords[recordIndex].status = .failed
            task.imageRecords = imageRecords
          }
          task.status = .imageUploadFailed
          task.lastErrorMessage = error.localizedDescription
          try? modelContext.save()
          return .failure(error)
        } catch {
          task.status = .imageUploadFailed
          task.lastErrorMessage = error.localizedDescription
          try? modelContext.save()
          return .failure(.r2(error.localizedDescription))
        }
      }
    }

    stage = .preparingMarkdown
    task.status = .preparingMarkdown
    let directory = draft.contentType == .essay ? githubConfig.normalizedEssayDirectory() : githubConfig.normalizedMomentsDirectory()
    var fileStem = HugoMarkdownBuilder.uniqueFileStem(contentType: draft.contentType, createdAt: draft.contentCreatedAt)
    var targetPath = PublishConfiguration.joinPath(directory, fileName: "\(fileStem).md")
    var attempts = 0
    while attempts < 5 {
      do {
        if try await github.pathExists(config: githubConfig, token: token, path: targetPath) {
          fileStem = HugoMarkdownBuilder.uniqueFileStem(contentType: draft.contentType, createdAt: draft.contentCreatedAt)
          targetPath = PublishConfiguration.joinPath(directory, fileName: "\(fileStem).md")
          attempts += 1
          continue
        }
        break
      } catch {
        return .failure(error as? PublishError ?? .github(error.localizedDescription))
      }
    }

    let markdown: String
    switch draft.contentType {
    case .essay:
      markdown = HugoMarkdownBuilder.buildEssayMarkdown(
        title: draft.title,
        body: draft.body,
        createdAt: draft.contentCreatedAt,
        imageURLs: imageURLs
      )
    case .moment:
      markdown = HugoMarkdownBuilder.buildMomentMarkdown(
        createdAt: draft.contentCreatedAt,
        body: draft.body,
        imageURLs: imageURLs
      )
    }
    task.markdownDraft = markdown
    task.githubPath = targetPath

    stage = .uploadingGitHub
    task.status = .uploadingGitHub
    do {
      let message = draft.contentType == .essay ? "Publish essay from Hetkia" : "Publish moment from Hetkia"
      let sha = try await github.createMarkdownFile(
        config: githubConfig,
        token: token,
        path: targetPath,
        markdown: markdown,
        commitMessage: message
      )
      task.githubCommitSHA = sha
      task.status = .published
      task.publishedAt = .now
      task.lastErrorMessage = nil
      try? modelContext.save()
      stage = .succeeded(commitSHA: sha, path: targetPath)
      return .success(localized("publish.success.detail"))
    } catch let error as PublishError {
      task.status = .githubUploadFailed
      task.lastErrorMessage = error.localizedDescription
      try? modelContext.save()
      return .failure(error)
    } catch {
      task.status = .githubUploadFailed
      task.lastErrorMessage = error.localizedDescription
      try? modelContext.save()
      return .failure(.github(error.localizedDescription))
    }
  }

  private func validateDraft(_ draft: RemotePublishDraft) -> PublishError? {
    let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasPhoto = !draft.photoIDs.isEmpty
    switch draft.contentType {
    case .essay:
      guard !body.isEmpty else {
        return .validation(localized("publish.error.body.empty"))
      }
      let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else {
        return .validation(localized("publish.error.title.empty"))
      }
    case .moment:
      guard !body.isEmpty || hasPhoto else {
        return .validation(localized("publish.error.moment.empty"))
      }
      if draft.photoIDs.count > 1 {
        return .validation(localized("publish.error.moment.tooManyPhotos"))
      }
    }
    return nil
  }

  private func uniqueObjectKey(prefix: String, stem: String) -> String {
    "\(prefix)/\(stem).jpg"
  }

  private func localized(_ key: String) -> String {
    HetkiaSystemLanguage.localizedString(key, comment: "")
  }
}

private extension Array {
  subscript(safe index: Int?) -> Element? {
    guard let index else { return nil }
    return indices.contains(index) ? self[index] : nil
  }
}
