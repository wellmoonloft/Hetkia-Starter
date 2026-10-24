import SwiftUI
import Photos
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
private final class PermissionSettingsModel: NSObject, ObservableObject {
    @Published private(set) var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    func requestPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in self?.photoStatus = status }
        }
    }

    func refresh() {
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
}

private enum JournalStorageChoice: String {
    case local
    case iCloud
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var permissions = PermissionSettingsModel()
    @AppStorage("hetkia.storageChoice") private var storageChoice = JournalStorageChoice.local.rawValue
    @State private var showICloudNotice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    permissionSection
                    storageSection
                    aiSection
                    languageSection
                }
                .padding(18)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(HetkiaPalette.paper.ignoresSafeArea())
            .navigationTitle(Text("settings.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .onAppear {
                permissions.refresh()
            }
            .alert("settings.icloud.title", isPresented: $showICloudNotice) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text("settings.icloud.unavailable")
            }
        }
        .tint(HetkiaPalette.amber)
    }

    private var permissionSection: some View {
        settingsCard(title: "settings.permissions", symbol: "hand.raised") {
            permissionRow(
                title: "settings.permission.photos",
                detail: "settings.permission.photos.detail",
                symbol: "photo.on.rectangle",
                status: photoStatusText,
                actionTitle: photoActionTitle,
                action: handlePhotoPermission
            )
        }
    }

    private var storageSection: some View {
        settingsCard(title: "settings.storage", symbol: "externaldrive") {
            storageChoiceRow(.local, title: "settings.storage.local", detail: "settings.storage.local.detail", isAvailable: true)
            Divider().overlay(HetkiaPalette.line)
            storageChoiceRow(.iCloud, title: "settings.storage.icloud", detail: "settings.storage.icloud.detail", isAvailable: false)
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

    private var languageSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe.asia.australia")
                .foregroundStyle(HetkiaPalette.amber)
            Text("settings.language-note")
                .font(.system(size: 12))
                .foregroundStyle(HetkiaPalette.secondaryInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
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
        .padding(16)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(HetkiaPalette.line.opacity(0.65), lineWidth: 0.7))
    }

    private func permissionRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        status: LocalizedStringKey,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(HetkiaPalette.amber)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 8)
                    Text(status).font(.system(size: 10, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button(actionTitle, action: action)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(HetkiaPalette.amber)
                    .padding(.top, 2)
            }
        }
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

    private var photoStatusText: LocalizedStringKey {
        switch permissions.photoStatus {
        case .authorized: "settings.permission.granted"
        case .limited: "settings.permission.limited"
        case .denied: "settings.permission.denied"
        case .restricted: "settings.permission.restricted"
        case .notDetermined: "settings.permission.not-requested"
        @unknown default: "settings.permission.unknown"
        }
    }

    private var photoActionTitle: LocalizedStringKey {
        permissions.photoStatus == .notDetermined ? "settings.permission.request" : "settings.permission.manage"
    }

    private func handlePhotoPermission() {
        if permissions.photoStatus == .notDetermined {
            permissions.requestPhotos()
        } else {
            openPrivacySettings(section: "Photos")
        }
    }

    private func openPrivacySettings(section: String) {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
