import SwiftUI
import SwiftData
#if !os(macOS)
import UIKit
import BackgroundTasks
import Photos
import WidgetKit

final class HetkiaApplicationDelegate: NSObject, UIApplicationDelegate {
    private let onThisDayTaskIdentifier = "com.hetkia.app.onthisday-refresh"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: onThisDayTaskIdentifier, using: nil) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleOnThisDayRefresh(refreshTask)
        }
        scheduleNextOnThisDayRefresh()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleNextOnThisDayRefresh()
    }

    private func handleOnThisDayRefresh(_ task: BGAppRefreshTask) {
        scheduleNextOnThisDayRefresh()
        let work = Task { @MainActor in
            _ = await OnThisDayScanCoordinator.shared.fullScan()
            if OnThisDayWidgetIndexStore.needsTimelineReload() {
                WidgetCenter.shared.reloadTimelines(ofKind: "Hetkia.OnThisDay")
            }
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    private func scheduleNextOnThisDayRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: onThisDayTaskIdentifier)
        request.earliestBeginDate = Calendar.autoupdatingCurrent.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
        try? BGTaskScheduler.shared.submit(request)
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HetkiaSystemLanguage.defaultsKey) private var languageSelection = HetkiaSystemLanguage.systemIdentifier
    @State private var hasRequiredPhotoAccess = PhotoLibraryService.hasFullReadAccess

    var body: some View {
        Group {
            if onboarding.isOnboardingComplete && hasRequiredPhotoAccess {
                TimelineHomeView()
            } else {
                OnboardingFlowView(model: onboarding)
            }
        }
        .environment(\.locale, HetkiaSystemLanguage.locale(for: languageSelection))
        .task { refreshPhotoAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshPhotoAuthorization() }
        }
    }

    private func refreshPhotoAuthorization() {
        let isAuthorized = PhotoLibraryService.hasFullReadAccess
        hasRequiredPhotoAccess = isAuthorized
        if !isAuthorized { onboarding.requirePhotoAccess() }
    }
}

enum HetkiaSystemLanguage {
    static let defaultsKey = "hetkia.languageOverride"
    static let systemIdentifier = "system"
    static let supportedIdentifiers = ["en", "es", "th", "zh-Hans", "zh-Hant"]

    static var identifier: String {
        resolvedIdentifier(for: UserDefaults.standard.string(forKey: defaultsKey) ?? systemIdentifier)
    }

    static func resolvedIdentifier(for selection: String) -> String {
        guard selection == systemIdentifier else {
            return supportedIdentifiers.contains(selection) ? selection : "en"
        }
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
    }

    static var locale: Locale { locale(for: identifier) }
    static func locale(for selection: String) -> Locale {
        Locale(identifier: resolvedIdentifier(for: selection))
    }
    static var displayName: String { locale.localizedString(forIdentifier: identifier) ?? "English" }

    static func localizedString(_ key: String, language: String? = nil, comment: String = "") -> String {
        let language = language.map(normalizedLanguageIdentifier) ?? identifier
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func normalizedLanguageIdentifier(_ identifier: String) -> String {
        let lowercased = identifier.lowercased()
        if lowercased.hasPrefix("zh") {
            return lowercased.contains("hant") || lowercased.contains("tw") || lowercased.contains("hk") || lowercased.contains("mo")
                ? "zh-Hant"
                : "zh-Hans"
        }
        if lowercased.hasPrefix("es") { return "es" }
        if lowercased.hasPrefix("th") { return "th" }
        if lowercased.hasPrefix("en") { return "en" }
        return "en"
    }
}
