import SwiftUI

struct PublishSettingsView: View {
  @State private var github = PublishConfiguration.loadGitHub()
  @State private var r2 = PublishConfiguration.loadR2()
  @State private var githubToken = PublishSecretsStore.get(.githubToken) ?? ""
  @State private var r2AccessKeyID = PublishSecretsStore.get(.r2AccessKeyID) ?? ""
  @State private var r2Secret = PublishSecretsStore.get(.r2SecretAccessKey) ?? ""
  @State private var githubTestMessage: String?
  @State private var r2TestMessage: String?
  @State private var isTestingGitHub = false
  @State private var isTestingR2 = false

  private let githubClient = GitHubPublishClient()
  private let r2Client = R2S3Client()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        settingsCard(title: "publish.settings.github.title", symbol: "chevron.left.forwardslash.chevron.right") {
          field("publish.settings.github.owner", text: $github.owner)
          field("publish.settings.github.repository", text: $github.repository)
          field("publish.settings.github.branch", text: $github.branch)
          secureField("publish.settings.github.token", text: $githubToken)
          field("publish.settings.github.essayDir", text: $github.essayDirectory)
          field("publish.settings.github.momentsDir", text: $github.momentsDirectory)
          testButton(
            title: "publish.settings.test.github",
            isLoading: isTestingGitHub,
            action: testGitHub
          )
          if let githubTestMessage {
            settingsFeedback(githubTestMessage, isError: isGitHubTestError(githubTestMessage))
          }
        }
        settingsCard(title: "publish.settings.r2.title", symbol: "externaldrive.badge.icloud") {
          field("publish.settings.r2.account", text: $r2.accountID)
          secureField("publish.settings.r2.accessKey", text: $r2AccessKeyID)
          secureField("publish.settings.r2.secret", text: $r2Secret)
          field("publish.settings.r2.bucket", text: $r2.bucketName)
          field("publish.settings.r2.cdn", text: $r2.cdnDomain)
          Text("publish.settings.r2.endpoint")
            .font(.system(size: 11))
            .foregroundStyle(HetkiaPalette.secondaryInk)
          Text(r2.endpoint.isEmpty ? "—" : r2.endpoint)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(HetkiaPalette.ink)
          testButton(
            title: "publish.settings.test.r2",
            isLoading: isTestingR2,
            action: testR2
          )
          if let r2TestMessage {
            settingsFeedback(r2TestMessage, isError: isR2TestError(r2TestMessage))
          }
        }
      }
      .padding(18)
    }
    .background(HetkiaPalette.paper.ignoresSafeArea())
    .navigationTitle(Text("publish.settings.title"))
    .navigationBarTitleDisplayMode(.inline)
    .onDisappear(perform: persist)
  }

  private func persist() {
    PublishConfiguration.saveGitHub(github)
    PublishConfiguration.saveR2(r2)
    PublishSecretsStore.set(githubToken, for: .githubToken)
    PublishSecretsStore.set(r2AccessKeyID, for: .r2AccessKeyID)
    PublishSecretsStore.set(r2Secret, for: .r2SecretAccessKey)
  }

  private func testGitHub() {
    persist()
    isTestingGitHub = true
    githubTestMessage = nil
    Task {
      defer { isTestingGitHub = false }
      do {
        try await githubClient.validateAccess(config: github, token: githubToken)
        githubTestMessage = HetkiaSystemLanguage.localizedString("publish.settings.test.github.ok", comment: "")
      } catch {
        githubTestMessage = error.localizedDescription
      }
    }
  }

  private func testR2() {
    persist()
    isTestingR2 = true
    r2TestMessage = nil
    Task {
      defer { isTestingR2 = false }
      do {
        try await r2Client.validateAccess(
          config: r2,
          accessKeyID: r2AccessKeyID,
          secretAccessKey: r2Secret
        )
        r2TestMessage = HetkiaSystemLanguage.localizedString("publish.settings.test.r2.ok", comment: "")
      } catch {
        r2TestMessage = error.localizedDescription
      }
    }
  }

  private func isGitHubTestError(_ message: String) -> Bool {
    message != HetkiaSystemLanguage.localizedString("publish.settings.test.github.ok", comment: "")
  }

  private func isR2TestError(_ message: String) -> Bool {
    message != HetkiaSystemLanguage.localizedString("publish.settings.test.r2.ok", comment: "")
  }

  private func settingsFeedback(_ message: String, isError: Bool) -> some View {
    Text(message)
      .font(.system(size: 12))
      .foregroundStyle(isError ? Color.red : HetkiaPalette.ink)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 2)
  }

  @ViewBuilder
  private func settingsCard<Content: View>(title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(HetkiaPalette.ink)
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 11))
        .foregroundStyle(HetkiaPalette.secondaryInk)
      TextField(title, text: text)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
  }

  private func secureField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 11))
        .foregroundStyle(HetkiaPalette.secondaryInk)
      SecureField(title, text: text)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
  }

  private func testButton(title: LocalizedStringKey, isLoading: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        if isLoading { ProgressView().controlSize(.small) }
        Text(title)
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(HetkiaPalette.amber)
    }
    .buttonStyle(.plain)
    .disabled(isLoading)
    .padding(.top, 4)
  }
}

struct EssayPublishSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @StateObject private var coordinator = PublishCoordinator()

  let photos: [JournalPhotoRecord]
  let initialTitle: String
  let initialBody: String
  let captureReferenceDate: Date
  let sourceJournalDayKey: String?
  let savedOnly: Bool
  let openSettings: () -> Void

  @State private var title: String
  @State private var bodyText: String
  @State private var selectedPhotoIDs: Set<UUID>
  @State private var dateMode: EssayPublishDateMode
  @State private var errorMessage: String?

  init(
    photos: [JournalPhotoRecord],
    initialTitle: String,
    initialBody: String,
    captureReferenceDate: Date,
    sourceJournalDayKey: String?,
    savedOnly: Bool,
    openSettings: @escaping () -> Void
  ) {
    self.photos = photos
    self.initialTitle = initialTitle
    self.initialBody = initialBody
    self.captureReferenceDate = captureReferenceDate
    self.sourceJournalDayKey = sourceJournalDayKey
    self.savedOnly = savedOnly
    self.openSettings = openSettings
    _title = State(initialValue: initialTitle)
    _bodyText = State(initialValue: initialBody)
    _selectedPhotoIDs = State(initialValue: Set(photos.map(\.id)))
    let calendar = Calendar.autoupdatingCurrent
    let startOfToday = calendar.startOfDay(for: .now)
    let defaultMode: EssayPublishDateMode =
      captureReferenceDate < startOfToday ? .capture : .now
    _dateMode = State(initialValue: defaultMode)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("publish.essay.title.section") {
          TextField("publish.essay.title.placeholder", text: $title)
        }
        Section {
          Picker("", selection: $dateMode) {
            Text("publish.essay.date.now").tag(EssayPublishDateMode.now)
            Text("publish.essay.date.capture").tag(EssayPublishDateMode.capture)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          Text(publishDatePreview)
            .font(.system(size: 12))
            .foregroundStyle(HetkiaPalette.secondaryInk)
        } header: {
          Text("publish.essay.date.section")
        }
        Section("publish.essay.body.section") {
          TextEditor(text: $bodyText)
            .frame(minHeight: 140)
        }
        if !photos.isEmpty {
          Section("publish.essay.photos.section") {
            PublishPhotoSelectionGrid(photos: photos, selectedPhotoIDs: $selectedPhotoIDs)
          }
        }
        if let stage = coordinator.stage {
          Section {
            publishProgress(stage)
          }
        }
        if let errorMessage {
          Section {
            Text(errorMessage)
              .font(.system(size: 13))
              .foregroundStyle(.red)
            Button("publish.open.settings", action: openSettings)
              .font(.system(size: 13, weight: .medium))
          }
        }
      }
      .navigationTitle(Text("publish.essay.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("publish.action.submit") { submit() }
            .disabled(coordinator.isPublishing)
        }
      }
    }
  }

  private var publishDatePreview: String {
    let date = resolvedPublishDate()
    let formatted = date.formatted(date: .long, time: .shortened)
    return String(format: HetkiaSystemLanguage.localizedString("publish.essay.date.preview", comment: ""), formatted)
  }

  private func resolvedPublishDate() -> Date {
    switch dateMode {
    case .now:
      return .now
    case .capture:
      let selected = photos.filter { selectedPhotoIDs.contains($0.id) }
      let captureDates = selected.compactMap(\.capturedAt)
      if let earliest = captureDates.min() { return earliest }
      if let fallback = photos.compactMap(\.capturedAt).min() { return fallback }
      return captureReferenceDate
    }
  }

  private func submit() {
    errorMessage = nil
    let draft = RemotePublishDraft(
      contentType: .essay,
      title: title,
      body: bodyText,
      contentCreatedAt: resolvedPublishDate(),
      sourceJournalDayKey: sourceJournalDayKey,
      photoIDs: Array(selectedPhotoIDs)
    )
    let map = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
    Task {
      let result = await coordinator.publish(
        draft: draft,
        photosByID: map,
        savedOnly: savedOnly,
        modelContext: modelContext
      )
      switch result {
      case .success:
        dismiss()
      case .failure(let error):
        errorMessage = error.localizedDescription
      }
    }
  }

  @ViewBuilder
  private func publishProgress(_ stage: PublishProgressStage) -> some View {
    switch stage {
    case .checkingConnectivity:
      Text("publish.progress.connectivity")
    case .validatingGitHub:
      Text("publish.progress.github")
    case .validatingR2:
      Text("publish.progress.r2")
    case .uploadingImage(let current, let total):
      Text(String(format: HetkiaSystemLanguage.localizedString("publish.progress.images", comment: ""), current, total))
    case .preparingMarkdown:
      Text("publish.progress.markdown")
    case .uploadingGitHub:
      Text("publish.progress.github.upload")
    case .succeeded:
      Text("publish.progress.success")
    }
  }
}

struct MomentPublishSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @StateObject private var coordinator = PublishCoordinator()

  let initialBody: String
  let contentCreatedAt: Date
  let sourceJournalDayKey: String?
  let openSettings: () -> Void

  @State private var bodyText: String
  @State private var errorMessage: String?

  init(
    initialBody: String,
    contentCreatedAt: Date,
    sourceJournalDayKey: String?,
    openSettings: @escaping () -> Void
  ) {
    self.initialBody = initialBody
    self.contentCreatedAt = contentCreatedAt
    self.sourceJournalDayKey = sourceJournalDayKey
    self.openSettings = openSettings
    _bodyText = State(initialValue: initialBody)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("publish.moment.body.section") {
          TextEditor(text: $bodyText)
            .frame(minHeight: 160)
        }
        if let stage = coordinator.stage {
          Section { publishProgress(stage) }
        }
        if let errorMessage {
          Section {
            Text(errorMessage).foregroundStyle(.red)
            Button("publish.open.settings", action: openSettings)
          }
        }
      }
      .navigationTitle(Text("publish.moment.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("publish.action.submit") { submit() }
            .disabled(coordinator.isPublishing)
        }
      }
    }
  }

  private func submit() {
    errorMessage = nil
    let draft = RemotePublishDraft(
      contentType: .moment,
      title: "",
      body: bodyText,
      contentCreatedAt: contentCreatedAt,
      sourceJournalDayKey: sourceJournalDayKey,
      photoIDs: []
    )
    Task {
      let result = await coordinator.publish(
        draft: draft,
        photosByID: [:],
        savedOnly: false,
        modelContext: modelContext
      )
      switch result {
      case .success:
        dismiss()
      case .failure(let error):
        errorMessage = error.localizedDescription
      }
    }
  }

  @ViewBuilder
  private func publishProgress(_ stage: PublishProgressStage) -> some View {
    switch stage {
    case .checkingConnectivity:
      Text("publish.progress.connectivity")
    case .validatingGitHub:
      Text("publish.progress.github")
    case .validatingR2:
      Text("publish.progress.r2")
    case .uploadingImage(let current, let total):
      Text(String(format: HetkiaSystemLanguage.localizedString("publish.progress.images", comment: ""), current, total))
    case .preparingMarkdown:
      Text("publish.progress.markdown")
    case .uploadingGitHub:
      Text("publish.progress.github.upload")
    case .succeeded:
      Text("publish.progress.success")
    }
  }
}

private struct PublishPhotoSelectionGrid: View {
  let photos: [JournalPhotoRecord]
  @Binding var selectedPhotoIDs: Set<UUID>

  private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 10) {
      ForEach(photos) { photo in
        let selected = selectedPhotoIDs.contains(photo.id)
        Button {
          if selected { selectedPhotoIDs.remove(photo.id) }
          else { selectedPhotoIDs.insert(photo.id) }
        } label: {
          GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
              PhotoFallbackThumbnail(
                photo: photo,
                width: proxy.size.width,
                height: proxy.size.height,
                showsVideoIndicator: true
              )
              Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, selected ? HetkiaPalette.amber : .black.opacity(0.35))
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
          .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
  }
}
