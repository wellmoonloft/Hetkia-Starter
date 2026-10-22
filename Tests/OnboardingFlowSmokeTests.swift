import Foundation

@main
struct OnboardingFlowSmokeTests {
    @MainActor
    static func main() async {
        let suite = "Hetkia.OnboardingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Could not create isolated test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = OnboardingFlowModel(defaults: defaults, storageKey: "flow")
        precondition(model.stage == .welcome)
        model.begin()
        model.choosePhotoAccess(.limited)
        model.continueFromPhotoAccess()
        model.setPreferredTime(Calendar.current.date(from: DateComponents(hour: 20, minute: 15))!)
        model.continueToToday()
        precondition(model.stage == .todayJournal)
        precondition(model.todayStatus == .idle)
        precondition(model.todayProgress == 0)
        model.startTodayGeneration(outcome: .failure)
        try? await Task.sleep(for: .seconds(1.8))
        precondition(model.todayStatus == .failed)
        model.retryToday()
        try? await Task.sleep(for: .seconds(1.8))
        precondition(model.todayStatus == .ready)

        model.continueFromToday()
        model.startBackfillFromHome()
        model.selectRange(.sevenDays)
        model.beginBackfillScan()
        try? await Task.sleep(for: .seconds(1.8))
        precondition(model.stage == .backfillConfirmation)
        precondition(!model.dateGroups.isEmpty)
        precondition(model.dateGroups.contains(where: \.hasExistingJournal))
        precondition(model.selectedDateCount > 0)

        model.beginQueue()
        model.pauseQueue()
        precondition(model.isQueuePaused)
        let recoveredQueue = OnboardingFlowModel(defaults: defaults, storageKey: "flow")
        precondition(recoveredQueue.stage == .backfillQueue)
        precondition(recoveredQueue.isQueuePaused)
        model.resumeQueue()
        await waitUntil(15) { model.isQueuePaused && model.failedCount > 0 }
        precondition(model.stage == .backfillQueue)
        model.retryFailedQueueItems()
        await waitUntil(15) { model.stage == .backfillComplete }
        precondition(model.failedCount == 0)
        precondition(model.completedCount > 0)

        let restored = OnboardingFlowModel(defaults: defaults, storageKey: "flow")
        precondition(restored.stage == .backfillComplete)
        precondition(restored.completedCount == model.completedCount)
        precondition(restored.photoAccess == .limited)

        print("PASS: onboarding, queue pause/resume, retry, completion, and state restore")
    }

    @MainActor
    private static func waitUntil(_ seconds: Int, condition: () -> Bool) async {
        for _ in 0..<(seconds * 10) {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        fatalError("Timed out while waiting for simulated queue")
    }
}
