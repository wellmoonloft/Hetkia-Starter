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
    @State private var hasRequiredPhotoAccess = PhotoLibraryService.hasFullReadAccess

    var body: some View {
        Group {
            if onboarding.isOnboardingComplete && hasRequiredPhotoAccess {
                TimelineHomeView()
            } else {
                OnboardingFlowView(model: onboarding)
            }
        }
        .environment(\.locale, HetkiaSystemLanguage.locale)
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
