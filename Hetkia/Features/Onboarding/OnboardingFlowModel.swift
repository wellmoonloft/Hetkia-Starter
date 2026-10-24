import Foundation
import Combine

enum OnboardingStage: String, Codable {
    case welcome
    case photoAccess
    case generationTime
    case todayJournal
    case historyInvitation
    case backfillRange
    case backfillScanning
    case backfillConfirmation
    case backfillQueue
    case backfillComplete
    case finished
}

enum DemoPhotoAccess: String, Codable {
    case full
    case limited
    case denied
}

enum TodayDemoOutcome: String, Codable, CaseIterable {
    case samplePhotos
    case noPhotos
    case existingJournal
    case modelUnavailable
    case failure
}

enum TodayJournalStatus: String, Codable {
    case idle
    case existing
    case scanning
    case preparing
    case writing
    case ready
    case noPhotos
    case modelUnavailable
    case failed
}

enum BackfillRangePreset: String, Codable, CaseIterable {
    case sevenDays
    case thirtyDays
    case yearToDate
    case custom
}

enum BackfillItemStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
    case skipped
    case cancelled
}

struct BackfillDateGroup: Identifiable, Codable, Equatable {
    let id: String
    let date: Date
    let photoCount: Int
    let hasExistingJournal: Bool
    var isSelected: Bool
}

struct BackfillQueueItem: Identifiable, Codable, Equatable {
    let id: String
    let date: Date
    let photoCount: Int
    var status: BackfillItemStatus
    var progress: Double
    var attempts: Int
    var simulatesFirstAttemptFailure: Bool
}

@MainActor
final class OnboardingFlowModel: ObservableObject {
    static let shared = OnboardingFlowModel()

    @Published private(set) var stage: OnboardingStage
    @Published private(set) var isOnboardingComplete: Bool
    @Published private(set) var photoAccess: DemoPhotoAccess
    @Published private(set) var todayStatus: TodayJournalStatus
    @Published private(set) var todayProgress: Double
    @Published private(set) var todayOutcome: TodayDemoOutcome
    @Published private(set) var rangePreset: BackfillRangePreset
    @Published private(set) var customStartDate: Date
    @Published private(set) var customEndDate: Date
    @Published private(set) var scanProgress: Double
    @Published private(set) var dateGroups: [BackfillDateGroup]
    @Published private(set) var queueItems: [BackfillQueueItem]
    @Published private(set) var isQueuePaused: Bool

    private let defaults: UserDefaults
    private let storageKey: String
    private var simulationTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        var stage: OnboardingStage
        var isOnboardingComplete: Bool
        var photoAccess: DemoPhotoAccess
        var todayStatus: TodayJournalStatus
        var todayProgress: Double
        var todayOutcome: TodayDemoOutcome
        var rangePreset: BackfillRangePreset
        var customStartDate: Date
        var customEndDate: Date
        var scanProgress: Double
        var dateGroups: [BackfillDateGroup]
        var queueItems: [BackfillQueueItem]
        var isQueuePaused: Bool
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "hetkia.onboarding.flow.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        let now = Date()
        let initial = Snapshot(
            stage: .welcome,
            isOnboardingComplete: false,
            photoAccess: .full,
            todayStatus: .idle,
            todayProgress: 0,
            todayOutcome: .samplePhotos,
            rangePreset: .thirtyDays,
            customStartDate: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now,
            customEndDate: now,
            scanProgress: 0,
            dateGroups: [],
            queueItems: [],
            isQueuePaused: true
        )
        let restored = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? initial
        // Migrate snapshots from retired onboarding steps.
        switch restored.stage {
        case .historyInvitation, .backfillRange, .backfillScanning, .backfillConfirmation, .backfillQueue, .backfillComplete, .generationTime:
            stage = restored.isOnboardingComplete ? .finished : .photoAccess
        default:
            stage = restored.stage
        }
        isOnboardingComplete = restored.isOnboardingComplete
        photoAccess = restored.photoAccess
        todayStatus = restored.todayStatus
        todayProgress = restored.todayProgress
        todayOutcome = restored.todayOutcome
        rangePreset = restored.rangePreset
        customStartDate = restored.customStartDate
        customEndDate = restored.customEndDate
        scanProgress = restored.scanProgress
        dateGroups = restored.dateGroups
        queueItems = restored.queueItems
        isQueuePaused = restored.isQueuePaused
        restoreInterruptedWorkIfNeeded()
    }

    var completedCount: Int { queueItems.filter { $0.status == .completed }.count }
    var failedCount: Int { queueItems.filter { $0.status == .failed }.count }
    var skippedCount: Int { queueItems.filter { $0.status == .skipped || $0.status == .cancelled }.count }
    var selectedDateCount: Int { dateGroups.filter(\.isSelected).count }
    var isLimitedPhotoAccess: Bool { photoAccess == .limited }

    func begin() {
        stage = .photoAccess
        persist()
    }

    func choosePhotoAccess(_ access: DemoPhotoAccess) {
        photoAccess = access
        persist()
    }

    func continueFromPhotoAccess() {
        // The metadata-only same-day lookup runs as soon as photo access is granted.
        stage = .todayJournal
        todayStatus = .scanning
        todayProgress = 0
        persist()
    }

    func continueToToday() {
        stage = .todayJournal
        if photoAccess == .denied {
            todayOutcome = .noPhotos
            todayStatus = .noPhotos
            todayProgress = 0
        } else {
            todayOutcome = .samplePhotos
            todayStatus = .idle
            todayProgress = 0
        }
        persist()
    }

    func updateInitialIndexProgress(_ progress: Double) {
        todayStatus = .scanning
        todayProgress = min(max(progress, 0), 1)
        persist()
    }

    func initialIndexFailed() {
        todayStatus = .failed
        persist()
    }

    func initialIndexCompleted() {
        todayStatus = .ready
        todayProgress = 1
        completeOnboarding()
    }

    func startTodayGeneration(outcome: TodayDemoOutcome) {
        simulationTask?.cancel()
        todayOutcome = outcome
        todayProgress = 0
        stage = .todayJournal

        switch outcome {
        case .noPhotos:
            todayStatus = .noPhotos
            persist()
        case .existingJournal:
            todayStatus = .existing
            todayProgress = 1
            persist()
        default:
            todayStatus = .scanning
            persist()
            simulationTask = Task { [weak self] in
                guard let self else { return }
                await self.advanceToday(to: 0.25, status: .scanning)
                guard !Task.isCancelled else { return }
                await self.advanceToday(to: 0.58, status: .preparing)
                guard !Task.isCancelled else { return }
                await self.advanceToday(to: 0.82, status: .writing)
                guard !Task.isCancelled else { return }
                switch outcome {
                case .modelUnavailable: self.todayStatus = .modelUnavailable
                case .failure: self.todayStatus = .failed
                default: self.todayStatus = .ready
                }
                self.todayProgress = self.todayStatus == .ready ? 1 : 0.82
                self.persist()
            }
        }
    }

    func retryToday() {
        startTodayGeneration(outcome: [.noPhotos, .modelUnavailable, .failure].contains(todayOutcome) ? .samplePhotos : todayOutcome)
    }

    func continueManuallyWithoutAI() {
        todayStatus = .ready
        todayProgress = 1
        persist()
    }

    func continueFromToday() {
        completeOnboarding()
    }

    func skipHistory() {
        completeOnboarding()
    }

    func startBackfillFromHome() {
        if stage == .backfillQueue {
            isQueuePaused = true
            persist()
            return
        }
        stage = .backfillRange
        dateGroups = []
        queueItems = []
        isQueuePaused = true
        persist()
    }

    func selectRange(_ preset: BackfillRangePreset) {
        rangePreset = preset
        persist()
    }

    func setCustomRange(start: Date, end: Date) {
        customStartDate = min(start, end)
        customEndDate = max(start, end)
        rangePreset = .custom
        persist()
    }

    func beginBackfillScan() {
        simulationTask?.cancel()
        stage = .backfillScanning
        scanProgress = 0
        persist()
        simulationTask = Task { [weak self] in
            guard let self else { return }
            for progress in [0.18, 0.38, 0.61, 0.82, 1.0] {
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                self.scanProgress = progress
                self.persist()
            }
            self.dateGroups = self.makeSampleDateGroups()
            self.stage = .backfillConfirmation
            self.persist()
        }
    }

    func toggleDate(_ id: String) {
        guard let index = dateGroups.firstIndex(where: { $0.id == id }), !dateGroups[index].hasExistingJournal else { return }
        dateGroups[index].isSelected.toggle()
        persist()
    }

    func setAllDatesSelected(_ selected: Bool) {
        for index in dateGroups.indices where !dateGroups[index].hasExistingJournal {
            dateGroups[index].isSelected = selected
        }
        persist()
    }

    func beginQueue() {
        let selected = dateGroups.filter(\.isSelected)
        let firstSelectedID = selected.first?.id
        queueItems = dateGroups.map { group in
            let status: BackfillItemStatus = group.hasExistingJournal ? .completed : (group.isSelected ? .pending : .skipped)
            return BackfillQueueItem(
                id: group.id,
                date: group.date,
                photoCount: group.photoCount,
                status: status,
                progress: 0,
                attempts: 0,
                simulatesFirstAttemptFailure: group.id == firstSelectedID
            )
        }
        stage = .backfillQueue
        isQueuePaused = false
        persist()
        processNextQueueItem()
    }

    func pauseQueue() {
        isQueuePaused = true
        simulationTask?.cancel()
        for index in queueItems.indices where queueItems[index].status == .processing {
            queueItems[index].status = .pending
            queueItems[index].progress = 0
        }
        persist()
    }

    func resumeQueue() {
        guard stage == .backfillQueue else { return }
        isQueuePaused = false
        persist()
        processNextQueueItem()
    }

    func cancelQueueItem(_ id: String) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }), queueItems[index].status == .pending else { return }
        queueItems[index].status = .cancelled
        persist()
    }

    func retryFailedQueueItems() {
        for index in queueItems.indices where queueItems[index].status == .failed {
            queueItems[index].status = .pending
            queueItems[index].progress = 0
        }
        stage = .backfillQueue
        isQueuePaused = false
        persist()
        processNextQueueItem()
    }

    func finishFlow() {
        completeOnboarding()
    }

    private func advanceToday(to progress: Double, status: TodayJournalStatus) async {
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        todayProgress = progress
        todayStatus = status
        persist()
    }

    private func makeSampleDateGroups() -> [BackfillDateGroup] {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: .now)
        let records: [(Int, Int, Bool)] = [(1, 5, false), (2, 12, false), (4, 8, true), (6, 3, false), (10, 7, true), (15, 4, false), (24, 9, false), (45, 6, true), (90, 10, false), (180, 4, false), (300, 11, false)]
        let cutoff: Date
        switch rangePreset {
        case .sevenDays: cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .thirtyDays: cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .yearToDate: cutoff = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        case .custom: cutoff = calendar.startOfDay(for: customStartDate)
        }
        let upperBound = rangePreset == .custom ? calendar.startOfDay(for: customEndDate) : now
        return records.compactMap { dayOffset, count, hasEntry in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now), date >= cutoff, date <= upperBound else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let id = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            return BackfillDateGroup(id: id, date: date, photoCount: count, hasExistingJournal: hasEntry, isSelected: !hasEntry)
        }
    }

    private func processNextQueueItem() {
        guard !isQueuePaused else { return }
        guard let index = queueItems.firstIndex(where: { $0.status == .pending }) else {
            if queueItems.contains(where: { $0.status == .failed }) {
                isQueuePaused = true
            } else {
                stage = .backfillComplete
            }
            persist()
            return
        }
        queueItems[index].status = .processing
        queueItems[index].progress = 0
        persist()
        simulationTask?.cancel()
        simulationTask = Task { [weak self] in
            guard let self else { return }
            for step in 1...4 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, !self.isQueuePaused else { return }
                self.queueItems[index].progress = Double(step) / 4
                self.persist()
            }
            let shouldFail = self.queueItems[index].simulatesFirstAttemptFailure && self.queueItems[index].attempts == 0
            self.queueItems[index].attempts += 1
            self.queueItems[index].status = shouldFail ? .failed : .completed
            self.queueItems[index].progress = 1
            self.persist()
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, !self.isQueuePaused else { return }
            self.processNextQueueItem()
        }
    }

    private func restoreInterruptedWorkIfNeeded() {
        if stage == .todayJournal && [.scanning, .preparing, .writing].contains(todayStatus) {
            todayStatus = .failed
            todayProgress = 0
        }
        if stage == .backfillScanning {
            stage = .backfillRange
            scanProgress = 0
        }
        if stage == .backfillQueue {
            isQueuePaused = true
            for index in queueItems.indices where queueItems[index].status == .processing {
                queueItems[index].status = .pending
                queueItems[index].progress = 0
            }
        }
        persist()
    }

    private func completeOnboarding() {
        isOnboardingComplete = true
        stage = .finished
        isQueuePaused = true
        persist()
    }

    private func persist() {
        let snapshot = Snapshot(
            stage: stage,
            isOnboardingComplete: isOnboardingComplete,
            photoAccess: photoAccess,
            todayStatus: todayStatus,
            todayProgress: todayProgress,
            todayOutcome: todayOutcome,
            rangePreset: rangePreset,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            scanProgress: scanProgress,
            dateGroups: dateGroups,
            queueItems: queueItems,
            isQueuePaused: isQueuePaused
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
        objectWillChange.send()
    }
}
