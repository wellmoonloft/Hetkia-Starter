import SwiftUI
import SwiftData
#if !os(macOS)
import UIKit

final class HetkiaApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}
#endif

@main
struct HetkiaApp: App {
    @StateObject private var onboarding = OnboardingFlowModel.shared
#if !os(macOS)
    @UIApplicationDelegateAdaptor(HetkiaApplicationDelegate.self) private var applicationDelegate
#endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            PersistentAppRootView(onboarding: onboarding)
        }
        .defaultSize(width: 620, height: 1000)
        .modelContainer(for: [JournalRecord.self, JournalPhotoRecord.self, JournalGenerationTask.self])
        #else
        WindowGroup {
            PersistentAppRootView(onboarding: onboarding)
        }
        .modelContainer(for: [JournalRecord.self, JournalPhotoRecord.self, JournalGenerationTask.self])
        #endif
    }
}

private struct PersistentAppRootView: View {
    @ObservedObject var onboarding: OnboardingFlowModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var automation = JournalAutomationCoordinator.shared

    var body: some View {
        Group {
            if onboarding.isOnboardingComplete {
                TimelineHomeView()
            } else {
                OnboardingFlowView(model: onboarding)
            }
        }
        .environment(\.locale, HetkiaSystemLanguage.locale)
        .task {
            await recoverAndCatchUp()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await recoverAndCatchUp() }
        }
        .onChange(of: onboarding.isOnboardingComplete) { _, completed in
            guard completed else { return }
            Task { await recoverAndCatchUp() }
        }
    }

    @MainActor
    private func recoverAndCatchUp() async {
        // Upgrade pre-feature rows from date-only unique keys to date|source keys.
        // The renamed unique column preserves SwiftData's existing constraint.
        if let journals = try? modelContext.fetch(FetchDescriptor<JournalRecord>()) {
            for journal in journals where !journal.storageKey.contains("|") {
                // Existing AI drafts identify the legacy generated entries; records
                // without a draft are treated as user-created/imported journals.
                let legacySource: JournalSource = journal.aiDraftBody == nil ? .manual : .automatic
                journal.sourceRaw = legacySource.rawValue
                journal.storageKey = "\(journal.storageKey)|\(legacySource.rawValue)"
            }
            try? modelContext.save()
        }
        let descriptor = FetchDescriptor<JournalGenerationTask>(predicate: #Predicate { $0.statusRaw == "processing" })
        if let interrupted = try? modelContext.fetch(descriptor) {
            for task in interrupted {
                task.status = .pending
                task.lastError = NSLocalizedString("photos.generate.interrupted", comment: "")
                task.journal?.generationStatus = .pending
                task.journal?.generationError = task.lastError
            }
            try? modelContext.save()
        }
        automation.resumeHistoricalLibraryIndexIfNeeded(context: modelContext)
        guard onboarding.isOnboardingComplete else { return }
        await automation.catchUp(context: modelContext)
    }
}

enum HetkiaSystemLanguage {
    static let identifier: String = {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else { return "en" }
        if preferred.hasPrefix("zh") {
            if preferred.contains("hant") || preferred.contains("-tw") || preferred.contains("-hk") || preferred.contains("-mo") {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        if preferred.hasPrefix("es") { return "es" }
        if preferred.hasPrefix("th") { return "th" }
        if preferred.hasPrefix("en") { return "en" }
        return "en"
    }()

    static let locale = Locale(identifier: identifier)
    static let displayName = locale.localizedString(forIdentifier: identifier) ?? "English"
}
