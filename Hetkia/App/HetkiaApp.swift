import SwiftUI
import SwiftData

@main
struct HetkiaApp: App {
    @StateObject private var onboarding = OnboardingFlowModel.shared

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
            let descriptor = FetchDescriptor<JournalGenerationTask>(predicate: #Predicate { $0.statusRaw == "processing" })
            guard let interrupted = try? modelContext.fetch(descriptor) else { return }
            for task in interrupted {
                task.status = .failed
                task.lastError = NSLocalizedString("photos.generate.interrupted", comment: "")
                task.journal?.generationStatus = .failed
                task.journal?.generationError = task.lastError
            }
            try? modelContext.save()
        }
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
