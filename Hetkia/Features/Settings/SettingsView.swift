import SwiftUI
import WidgetKit
#if !os(macOS)
import AVFoundation
import CoreLocation
import UIKit
#endif

private enum JournalStorageChoice: String {
    case local
    case iCloud
}

struct SettingsView: View {
    @AppStorage("hetkia.storageChoice") private var storageChoice = JournalStorageChoice.local.rawValue
    @AppStorage(PhotoAssetEligibility.includeScreenshotsDefaultsKey, store: PhotoAssetEligibility.sharedDefaults) private var includeScreenshotsAndScreenRecordings = false
    @AppStorage(JournalDraftService.promptDefaultsKey) private var journalPrompt = JournalDraftService.defaultPrompt
    @AppStorage(HetkiaSystemLanguage.defaultsKey) private var languageSelection = HetkiaSystemLanguage.systemIdentifier
    @AppStorage(MapCoordinateSystemPreference.defaultsKey) private var mapCoordinateSystem = MapCoordinateSystemPreference.system.rawValue
    @AppStorage(CapturePreferences.writeLocationToLibraryKey) private var writeLocationToSavedPhotos = true
    @State private var showICloudNotice = false
    @State private var showPromptEditor = false
    @State private var showPublishSettings = false
    @State private var capturePermissionRefresh = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("settings.title")
                        .font(.system(size: 31, weight: .regular, design: .serif))
                        .foregroundStyle(HetkiaPalette.ink)
                    savedJournalsSection
                    publishServiceSection
#if !os(macOS)
                    capturePermissionsSection
#endif
                    photoSelectionSection
                    mapCoordinateSection
                    storageSection
                    aiSection
                    aiPromptSection
                    languageSection
                }
                .padding(18)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(HetkiaPalette.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .alert("settings.icloud.title", isPresented: $showICloudNotice) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text("settings.icloud.unavailable")
            }
            .sheet(isPresented: $showPromptEditor) {
                JournalPromptEditorView(initialPrompt: journalPrompt) { updatedPrompt in
                    journalPrompt = updatedPrompt
                }
            }
            .navigationDestination(isPresented: $showPublishSettings) {
                PublishSettingsView()
            }
        }
        .tint(HetkiaPalette.amber)
        .onChange(of: includeScreenshotsAndScreenRecordings) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "Hetkia.OnThisDay")
        }
    }

    private var storageSection: some View {
        settingsCard(title: "settings.storage", symbol: "externaldrive") {
            storageChoiceRow(.local, title: "settings.storage.local", detail: "settings.storage.local.detail", isAvailable: true)
            Divider().overlay(HetkiaPalette.line)
            storageChoiceRow(.iCloud, title: "settings.storage.icloud", detail: "settings.storage.icloud.detail", isAvailable: false)
        }
    }

    private var capturePermissionsSection: some View {
        let _ = capturePermissionRefresh
        return settingsCard(title: "settings.capture.title", symbol: "camera") {
            Text("settings.capture.request-hint")
                .font(.system(size: 11))
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            capturePermissionRow(
                title: "settings.capture.camera",
                granted: CapturePermissionStatus.isCameraAuthorized,
                denied: CapturePermissionStatus.isCameraDeniedOrRestricted
            ) {
                Task {
                    _ = await CapturePermissionStatus.requestCameraAccess()
                    capturePermissionRefresh += 1
                }
            }
            Divider().overlay(HetkiaPalette.line)
            capturePermissionRow(
                title: "settings.capture.location",
                granted: CapturePermissionStatus.isLocationAuthorized,
                denied: CapturePermissionStatus.isLocationDeniedOrRestricted
            ) {
                Task {
                    _ = await CapturePermissionStatus.requestLocationAccess()
                    capturePermissionRefresh += 1
                }
            }
            Divider().overlay(HetkiaPalette.line)
            Toggle(isOn: $writeLocationToSavedPhotos) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.capture.write-location")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HetkiaPalette.ink)
                    Text("settings.capture.write-location.detail")
                        .font(.system(size: 11))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!CapturePermissionStatus.isLocationAuthorized)
            .tint(HetkiaPalette.amber)
        }
        .onAppear { capturePermissionRefresh += 1 }
    }

    private func capturePermissionDetail(granted: Bool, denied: Bool) -> LocalizedStringKey {
        if granted { return "settings.capture.status.granted" }
        if denied { return "settings.capture.status.denied" }
        return "settings.capture.status.prompt"
    }

    private func capturePermissionRow(
        title: LocalizedStringKey,
        granted: Bool,
        denied: Bool,
        requestInApp: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetkiaPalette.ink)
                Text(capturePermissionDetail(granted: granted, denied: denied))
                    .font(.system(size: 11))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
            }
            Spacer(minLength: 4)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(HetkiaPalette.amber)
            } else if denied {
                Button("settings.capture.open-system") { openSystemSettings() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HetkiaPalette.amber)
            } else {
                Button("settings.capture.enable", action: requestInApp)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HetkiaPalette.amber)
            }
        }
    }

    private func openSystemSettings() {
#if !os(macOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
#endif
    }

    private var publishServiceSection: some View {
        settingsCard(title: "publish.settings.title", symbol: "square.and.arrow.up.on.square") {
            Button {
                showPublishSettings = true
            } label: {
                HStack(spacing: 10) {
                    Text("publish.settings.open")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                }
                .foregroundStyle(HetkiaPalette.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var savedJournalsSection: some View {
        settingsCard(title: "settings.saved-journals", symbol: "book.closed") {
            NavigationLink {
                SavedJournalsView()
            } label: {
                HStack(spacing: 10) {
                    Text("settings.saved-journals.open")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                }
                .foregroundStyle(HetkiaPalette.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var photoSelectionSection: some View {
        settingsCard(title: "settings.photos", symbol: "photo.on.rectangle.angled") {
            Toggle(isOn: $includeScreenshotsAndScreenRecordings) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.photos.include-screenshots")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HetkiaPalette.ink)
                    Text("settings.photos.include-screenshots.detail")
                        .font(.system(size: 11))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(HetkiaPalette.amber)
        }
    }

    private var mapCoordinateSection: some View {
        settingsCard(title: "settings.map-coordinate.title", symbol: "map") {
            Picker("settings.map-coordinate.title", selection: $mapCoordinateSystem) {
                mapCoordinateOption("settings.map-coordinate.system").tag(MapCoordinateSystemPreference.system.rawValue)
                mapCoordinateOption("settings.map-coordinate.wgs84").tag(MapCoordinateSystemPreference.wgs84.rawValue)
                mapCoordinateOption("settings.map-coordinate.gcj02").tag(MapCoordinateSystemPreference.gcj02.rawValue)
            }
            .tint(HetkiaPalette.amber)
            Text("settings.map-coordinate.detail")
                .font(.system(size: 11))
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aiSection: some View {
        settingsCard(title: "settings.ai", symbol: "sparkles") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cpu")
                    .foregroundStyle(HetkiaPalette.amber)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("settings.ai.status").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("settings.ai.on-device")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(HetkiaPalette.secondaryInk)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(HetkiaPalette.paper, in: Capsule())
                    }
                    Text(JournalDraftService.availabilityDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var aiPromptSection: some View {
        settingsCard(title: "settings.ai.prompt.title", symbol: "text.alignleft") {
            Text("settings.ai.prompt.detail")
                .font(.system(size: 11))
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showPromptEditor = true
            } label: {
                HStack(spacing: 8) {
                    Text("settings.ai.prompt.edit")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                }
                .foregroundStyle(HetkiaPalette.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var languageSection: some View {
        settingsCard(title: "settings.language.title", symbol: "globe.asia.australia") {
            Picker("settings.language.title", selection: $languageSelection) {
                languageOption("settings.language.system").tag(HetkiaSystemLanguage.systemIdentifier)
                languageOption("settings.language.english").tag("en")
                languageOption("settings.language.spanish").tag("es")
                languageOption("settings.language.thai").tag("th")
                languageOption("settings.language.zh-hans").tag("zh-Hans")
                languageOption("settings.language.zh-hant").tag("zh-Hant")
            }
            .tint(HetkiaPalette.amber)
            Text("settings.language.detail")
                .font(.system(size: 11))
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func languageOption(_ key: String) -> some View {
        let effectiveLanguage = HetkiaSystemLanguage.resolvedIdentifier(for: languageSelection)
        return Text(verbatim: HetkiaSystemLanguage.localizedString(key, language: effectiveLanguage))
    }

    private func mapCoordinateOption(_ key: String) -> some View {
        let effectiveLanguage = HetkiaSystemLanguage.resolvedIdentifier(for: languageSelection)
        return Text(verbatim: HetkiaSystemLanguage.localizedString(key, language: effectiveLanguage))
    }

    private func settingsCard<Content: View>(
        title: LocalizedStringKey,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(HetkiaPalette.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(HetkiaPalette.line.opacity(0.65), lineWidth: 0.7))
    }

    private func storageChoiceRow(_ choice: JournalStorageChoice, title: LocalizedStringKey, detail: LocalizedStringKey, isAvailable: Bool) -> some View {
        Button {
            guard isAvailable else { showICloudNotice = true; return }
            storageChoice = choice.rawValue
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: storageChoice == choice.rawValue ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(storageChoice == choice.rawValue ? HetkiaPalette.amber : HetkiaPalette.secondaryInk)
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        if !isAvailable {
                            Text("settings.storage.not-configured")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(HetkiaPalette.secondaryInk)
                        }
                    }
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(HetkiaPalette.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

private struct JournalPromptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var showPromptLengthAlert = false
    let onSave: (String) -> Void

    init(initialPrompt: String, onSave: @escaping (String) -> Void) {
        _draft = State(initialValue: initialPrompt)
        self.onSave = onSave
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var characterCount: Int { draft.count }
    private let maximumCharacterCount = 1_500

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.ai.prompt.editor.detail")
                    .font(.system(size: 12))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $draft)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(HetkiaPalette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HetkiaPalette.line.opacity(0.75), lineWidth: 0.8))
                    .frame(minHeight: 280)
                HStack {
                    Spacer()
                    Text("\(characterCount) / \(maximumCharacterCount)")
                        .foregroundStyle(characterCount > maximumCharacterCount ? Color.red : HetkiaPalette.secondaryInk)
                    Text("settings.ai.prompt.characters")
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                }
                .font(.system(size: 11, design: .rounded))
                Button("settings.ai.prompt.restore-default", systemImage: "arrow.counterclockwise") {
                    draft = JournalDraftService.defaultPrompt
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HetkiaPalette.amber)
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(HetkiaPalette.page.ignoresSafeArea())
            .navigationTitle("settings.ai.prompt.editor.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("settings.ai.prompt.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.ai.prompt.save") {
                        guard characterCount <= maximumCharacterCount else {
                            showPromptLengthAlert = true
                            return
                        }
                        onSave(trimmedDraft)
                        dismiss()
                    }
                    .disabled(trimmedDraft.isEmpty)
                }
            }
            .alert("settings.ai.prompt.too-long.title", isPresented: $showPromptLengthAlert) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text("settings.ai.prompt.too-long.detail")
            }
        }
        .tint(HetkiaPalette.amber)
    }
}
