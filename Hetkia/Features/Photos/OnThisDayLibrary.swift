import Foundation
import Photos
import SwiftData
import CryptoKit

struct OnThisDayEntry: Identifiable, @unchecked Sendable {
    let date: Date
    let assets: [PHAsset]
    var id: String { PhotoDayGrouping.key(for: date) }
}

/// A small, read-only index of the current On This Day result. It stores PhotoKit
/// local identifiers only; image previews and journal content are persisted only
/// through the user's explicit journal actions.
@MainActor
enum OnThisDayCacheStore {
    private struct Snapshot: Codable {
        struct Entry: Codable {
            let date: Date
            let assetIdentifiers: [String]
        }

        let schemaVersion: Int
        let year: Int
        let month: Int
        let day: Int
        let timeZoneIdentifier: String
        let includesScreenshotsAndScreenRecordings: Bool
        let refreshedAt: Date
        let entries: [Entry]
    }

    private static let schemaVersion = 4
    private static let fileName = "on-this-day-index.json"

    /// Restores cards using the current PhotoKit library. A nil result means there
    /// is no compatible cache; an empty array is a valid cached empty result.
    static func load(today: Date = .now) -> [OnThisDayEntry]? {
        guard let snapshot = readCurrentSnapshot(today: today) else { return nil }
        guard PhotoLibraryService.hasFullReadAccess else { return nil }
        guard snapshot.includesScreenshotsAndScreenRecordings == PhotoAssetEligibility.includesScreenshotsAndScreenRecordings else { return nil }

        let identifiers = Array(Set(snapshot.entries.flatMap(\.assetIdentifiers)))
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetsByIdentifier: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in
            if PhotoAssetEligibility.allows(asset) {
                assetsByIdentifier[asset.localIdentifier] = asset
            }
        }

        return snapshot.entries.compactMap { saved in
            let assets = saved.assetIdentifiers.compactMap { assetsByIdentifier[$0] }
            guard !assets.isEmpty else { return nil }
            return OnThisDayEntry(date: saved.date, assets: assets)
        }.sorted { $0.date > $1.date }
    }

    static func save(_ entries: [OnThisDayEntry], today: Date = .now) {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        let snapshot = Snapshot(
            schemaVersion: schemaVersion,
            year: year,
            month: month,
            day: day,
            timeZoneIdentifier: calendar.timeZone.identifier,
            includesScreenshotsAndScreenRecordings: PhotoAssetEligibility.includesScreenshotsAndScreenRecordings,
            refreshedAt: .now,
            entries: entries.map { entry in
                Snapshot.Entry(date: entry.date, assetIdentifiers: entry.assets.map(\.localIdentifier))
            }
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            let directory = cacheURL().deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: cacheURL(), options: .atomic)
        } catch {
            // Cache writes are best-effort; the live PhotoKit query remains usable.
        }
    }

    /// Drops yesterday's index before the new local-day query. The cache is a single
    /// replaceable snapshot, so removing it also prevents stale identifiers accumulating.
    static func clearIfExpired(today: Date = .now) {
        guard FileManager.default.fileExists(atPath: cacheURL().path) else { return }
        guard let data = try? Data(contentsOf: cacheURL()),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            clear()
            return
        }
        let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: today)
        guard snapshot.schemaVersion == schemaVersion,
              snapshot.year == parts.year,
              snapshot.month == parts.month,
              snapshot.day == parts.day,
              snapshot.timeZoneIdentifier == Calendar.autoupdatingCurrent.timeZone.identifier else {
            clear()
            return
        }
    }

    /// Reads and validates the one-day snapshot in one disk pass. Invalid or
    /// expired files are removed; a valid snapshot with a different filter
    /// preference remains on disk but is not restored by `load`.
    private static func readCurrentSnapshot(today: Date) -> Snapshot? {
        guard FileManager.default.fileExists(atPath: cacheURL().path) else { return nil }
        guard let data = try? Data(contentsOf: cacheURL()),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            clear()
            return nil
        }
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard snapshot.schemaVersion == schemaVersion,
              snapshot.year == parts.year,
              snapshot.month == parts.month,
              snapshot.day == parts.day,
              snapshot.timeZoneIdentifier == calendar.timeZone.identifier else {
            clear()
            return nil
        }
        return snapshot
    }

    private static func clear() {
        try? FileManager.default.removeItem(at: cacheURL())
    }

    private static func cacheURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Hetkia", isDirectory: true).appendingPathComponent(fileName)
    }
}

/// Widget-only metadata shared through the App Group. It deliberately stores
/// one selected PhotoKit identifier per anniversary year, matching the
/// widget's established representative-photo ordering without storing pixels.
@MainActor
enum OnThisDayWidgetIndexStore {
    struct Entry: Codable {
        let date: Date
        let assetIdentifier: String
        let assetModificationDate: Date?
    }

    struct Summary: Codable, Equatable {
        let totalPhotoCount: Int
        let anniversaryYearCount: Int
        let heroAssetIdentifier: String?
    }

    struct Snapshot: Codable {
        let schemaVersion: Int
        let year: Int
        let month: Int
        let day: Int
        let timeZoneIdentifier: String
        let includesScreenshotsAndScreenRecordings: Bool
        let refreshedAt: Date
        let entries: [Entry]
        let totalPhotoCount: Int?
        let anniversaryYearCount: Int?
        let heroAssetIdentifier: String?
        let contentFingerprint: String

        var summary: Summary {
            Summary(
                totalPhotoCount: totalPhotoCount ?? 0,
                anniversaryYearCount: anniversaryYearCount ?? entries.count,
                heroAssetIdentifier: heroAssetIdentifier
            )
        }
    }

    private static let schemaVersion = 2
    private static let fileName = "on-this-day-widget-index.json"
    private static let fingerprintDefaultsKey = "hetkia.widget.lastReloadedFingerprint"
    private static let groupIdentifier = PhotoAssetEligibility.appGroupIdentifier

    static func load(today: Date = .now) -> Snapshot? {
        guard let url = snapshotURL(),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              isCurrent(snapshot, today: today),
              snapshot.contentFingerprint == fingerprint(for: snapshot.entries, summary: snapshot.summary, today: today) else {
            return nil
        }
        return snapshot
    }

    /// Replaces the complete index after a full historical scan.
    static func replace(with entries: [Entry], summary: Summary, today: Date = .now) {
        guard let snapshot = makeSnapshot(entries: entries, summary: summary, today: today) else { return }
        write(snapshot)
    }

    /// Updates the current anniversary year only when a complete shared index
    /// already exists. If it does not, the widget performs its legacy scan once
    /// and seeds the shared index itself.
    static func updateCurrentYear(with entry: Entry?, summary: Summary, today: Date = .now) {
        guard let existing = load(today: today) else { return }
        let calendar = Calendar.autoupdatingCurrent
        let currentYear = calendar.component(.year, from: today)
        var entries = existing.entries.filter { calendar.component(.year, from: $0.date) != currentYear }
        if let entry { entries.append(entry) }
        entries.sort { $0.date > $1.date }
        guard let snapshot = makeSnapshot(entries: entries, summary: summary, today: today) else { return }
        write(snapshot)
    }

    /// The app calls this after a successful index update. Routine refreshes
    /// invalidate WidgetKit only when widget-visible metadata changed; explicit
    /// user refreshes can force the old refresh behavior.
    static func needsTimelineReload(today: Date = .now, force: Bool = false) -> Bool {
        guard let snapshot = load(today: today) else { return true }
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return force }
        let previous = defaults.string(forKey: fingerprintDefaultsKey)
        let changed = previous != snapshot.contentFingerprint
        if changed || force {
            defaults.set(snapshot.contentFingerprint, forKey: fingerprintDefaultsKey)
            return true
        }
        return false
    }

    private static func isCurrent(_ snapshot: Snapshot, today: Date) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        return snapshot.schemaVersion == schemaVersion
            && snapshot.year == parts.year
            && snapshot.month == parts.month
            && snapshot.day == parts.day
            && snapshot.timeZoneIdentifier == calendar.timeZone.identifier
            && snapshot.includesScreenshotsAndScreenRecordings == PhotoAssetEligibility.includesScreenshotsAndScreenRecordings
    }

    private static func makeSnapshot(entries: [Entry], summary: Summary, today: Date) -> Snapshot? {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        let orderedEntries = entries.sorted { $0.date > $1.date }
        let contentFingerprint = fingerprint(for: orderedEntries, summary: summary, today: today)
        return Snapshot(
            schemaVersion: schemaVersion,
            year: year,
            month: month,
            day: day,
            timeZoneIdentifier: calendar.timeZone.identifier,
            includesScreenshotsAndScreenRecordings: PhotoAssetEligibility.includesScreenshotsAndScreenRecordings,
            refreshedAt: .now,
            entries: orderedEntries,
            totalPhotoCount: summary.totalPhotoCount,
            anniversaryYearCount: summary.anniversaryYearCount,
            heroAssetIdentifier: summary.heroAssetIdentifier,
            contentFingerprint: contentFingerprint
        )
    }

    private static func fingerprint(for entries: [Entry], summary: Summary, today: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        let summaryLine = "photos:\(summary.totalPhotoCount):years:\(summary.anniversaryYearCount):hero:\(summary.heroAssetIdentifier ?? "none")"
        let canonical = ([
            "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)",
            calendar.timeZone.identifier,
            PhotoAssetEligibility.includesScreenshotsAndScreenRecordings ? "1" : "0",
            summaryLine
        ] + entries.sorted { $0.date > $1.date }.map { entry in
            let year = calendar.component(.year, from: entry.date)
            let modification = entry.assetModificationDate.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "none"
            return "\(year):\(entry.assetIdentifier):\(modification)"
        }).joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func write(_ snapshot: Snapshot) {
        guard let url = snapshotURL(), let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // The widget retains its PhotoKit scan as a recovery path.
        }
    }

    private static func snapshotURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(fileName)
    }
}

/// A read-only PhotoKit query for the matching local month/day in each year.
/// It deliberately stores no JournalRecord and never requests image data.
@MainActor
enum OnThisDayLibrary {
    static func performFullScan(today: Date = .now, progress: ((Double) -> Void)? = nil) async -> OnThisDayScanPayload {
        OnThisDayCacheStore.clearIfExpired(today: today)
        guard PhotoLibraryService.hasFullReadAccess else {
            return OnThisDayScanPayload(entries: [], widgetUpdate: .replace([]))
        }
        let calendar = Calendar.autoupdatingCurrent
        let nowParts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let month = nowParts.month, let day = nowParts.day, let currentYear = nowParts.year else {
            return OnThisDayScanPayload(entries: [], widgetUpdate: .replace([]), today: today)
        }
        let earliestYear = 1900
        var found: [OnThisDayEntry] = []
        var widgetEntries: [OnThisDayWidgetIndexStore.Entry] = []
        let yearCount = max(1, currentYear - earliestYear + 1)

        for year in earliestYear...currentYear {
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                progress?(Double(year - earliestYear + 1) / Double(yearCount))
                continue
            }
            let resolved = calendar.dateComponents([.month, .day], from: start)
            guard resolved.month == month, resolved.day == day else {
                progress?(Double(year - earliestYear + 1) / Double(yearCount))
                continue
            }
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let result = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                if PhotoAssetEligibility.allows(asset) { assets.append(asset) }
            }
            if !assets.isEmpty {
                if let widgetAsset = widgetRepresentativeAsset(from: assets) {
                    widgetEntries.append(.init(
                        date: start,
                        assetIdentifier: widgetAsset.localIdentifier,
                        assetModificationDate: widgetAsset.modificationDate
                    ))
                }
                found.append(OnThisDayEntry(date: start, assets: JournalPhotoSelection.displayAssets(from: assets)))
            }
            progress?(Double(year - earliestYear + 1) / Double(yearCount))
            if year % 8 == 0 { await Task.yield() }
        }
        let entries = found.sorted { $0.date > $1.date }
        return OnThisDayScanPayload(entries: entries, widgetUpdate: .replace(widgetEntries), today: today)
    }

    /// A same-day refresh only needs to discover photos captured in the current
    /// year. Older anniversary groups stay in the metadata cache unless the user
    /// explicitly requests a full refresh.
    static func performCurrentYearRefresh(
        preserving entries: [OnThisDayEntry],
        today: Date = .now
    ) -> OnThisDayScanPayload {
        guard PhotoLibraryService.hasFullReadAccess else {
            return OnThisDayScanPayload(entries: entries, widgetUpdate: .updateCurrentYear(nil), today: today)
        }
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return OnThisDayScanPayload(entries: entries, widgetUpdate: .updateCurrentYear(nil), today: today)
        }

        let currentResult = fetchEntry(start: start, end: end)
        var merged = entries.filter { calendar.component(.year, from: $0.date) != year }
        if let currentResult { merged.append(currentResult.entry) }
        merged.sort { $0.date > $1.date }
        return OnThisDayScanPayload(
            entries: merged,
            widgetUpdate: .updateCurrentYear(currentResult?.widgetEntry),
            today: today
        )
    }

    @MainActor
    static func persist(_ payload: OnThisDayScanPayload) {
        OnThisDayCacheStore.save(payload.entries, today: payload.today)
        let summary = widgetIndexSummary(from: payload.entries, today: payload.today)
        switch payload.widgetUpdate {
        case .replace(let entries):
            OnThisDayWidgetIndexStore.replace(with: entries, summary: summary, today: payload.today)
        case .updateCurrentYear(let entry):
            OnThisDayWidgetIndexStore.updateCurrentYear(with: entry, summary: summary, today: payload.today)
        }
    }

    static func widgetIndexSummary(from entries: [OnThisDayEntry], today: Date) -> OnThisDayWidgetIndexStore.Summary {
        let totalPhotoCount = entries.reduce(0) { partial, entry in
            partial + JournalPhotoSelection.displayAssets(from: entry.assets).count
        }
        let anniversaryYearCount = entries.count
        let calendar = Calendar.autoupdatingCurrent
        let currentYear = calendar.component(.year, from: today)
        let heroAssetIdentifier: String? = {
            if let current = entries.first(where: { calendar.component(.year, from: $0.date) == currentYear }),
               let asset = widgetRepresentativeAsset(from: current.assets) {
                return asset.localIdentifier
            }
            if let newest = entries.sorted(by: { $0.date > $1.date }).first,
               let asset = widgetRepresentativeAsset(from: newest.assets) {
                return asset.localIdentifier
            }
            return nil
        }()
        return OnThisDayWidgetIndexStore.Summary(
            totalPhotoCount: totalPhotoCount,
            anniversaryYearCount: anniversaryYearCount,
            heroAssetIdentifier: heroAssetIdentifier
        )
    }

    private static func fetchEntry(start: Date, end: Date) -> (entry: OnThisDayEntry, widgetEntry: OnThisDayWidgetIndexStore.Entry?)? {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if PhotoAssetEligibility.allows(asset) { assets.append(asset) }
        }
        guard !assets.isEmpty else { return nil }
        let widgetEntry = widgetRepresentativeAsset(from: assets).map {
            OnThisDayWidgetIndexStore.Entry(
                date: start,
                assetIdentifier: $0.localIdentifier,
                assetModificationDate: $0.modificationDate
            )
        }
        return (OnThisDayEntry(date: start, assets: JournalPhotoSelection.displayAssets(from: assets)), widgetEntry)
    }

    /// Matches the widget's existing representative-photo ordering exactly:
    /// geotagged assets first, then ordinary media, then earlier capture time.
    private static func widgetRepresentativeAsset(from assets: [PHAsset]) -> PHAsset? {
        assets.sorted { lhs, rhs in
            let lhsHasLocation = lhs.location != nil
            let rhsHasLocation = rhs.location != nil
            if lhsHasLocation != rhsHasLocation { return lhsHasLocation && !rhsHasLocation }
            let lhsEveryday = PhotoAssetEligibility.isPriorityAsset(lhs)
            let rhsEveryday = PhotoAssetEligibility.isPriorityAsset(rhs)
            if lhsEveryday != rhsEveryday { return lhsEveryday && !rhsEveryday }
            return (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
        }.first
    }

    static func transientPhotoRecords(for assets: [PHAsset]) -> [JournalPhotoRecord] {
        JournalPhotoSelection.displayAssets(from: assets).enumerated().map { index, asset in
            let addedDate: Date?
            if #available(iOS 26, macOS 26, *) { addedDate = asset.addedDate }
            else { addedDate = nil }
            let photo = JournalPhotoRecord(
                assetLocalIdentifier: asset.localIdentifier,
                capturedAt: asset.creationDate,
                addedAt: addedDate,
                modificationDate: asset.modificationDate,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude,
                locationStatus: asset.location == nil ? .unavailable : .available,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                orientationRaw: nil,
                thumbnailRelativePath: "",
                metadataReadStatus: .complete,
                sortOrder: index,
                mediaType: asset.mediaType == .video ? "video" : "image",
                isPriorityPhoto: PhotoAssetEligibility.isPriorityAsset(asset)
            )
            return photo
        }
    }
}

struct OnThisDayScanPayload: @unchecked Sendable {
    enum WidgetUpdate: @unchecked Sendable {
        case replace([OnThisDayWidgetIndexStore.Entry])
        case updateCurrentYear(OnThisDayWidgetIndexStore.Entry?)
    }

    let entries: [OnThisDayEntry]
    let widgetUpdate: WidgetUpdate
    let today: Date

    init(
        entries: [OnThisDayEntry],
        widgetUpdate: WidgetUpdate,
        today: Date = .now
    ) {
        self.entries = entries
        self.widgetUpdate = widgetUpdate
        self.today = today
    }
}

/// Coalesces PhotoKit scans inside the app process. WidgetKit runs in a separate
/// process and continues to communicate through its small App Group snapshot.
actor OnThisDayScanCoordinator {
    static let shared = OnThisDayScanCoordinator()

    typealias ProgressHandler = @MainActor @Sendable (Double) -> Void

    private enum Scope: Hashable, Sendable {
        case full
        case currentYear
    }

    private struct Context: Hashable, Sendable {
        let year: Int
        let month: Int
        let day: Int
        let timeZoneIdentifier: String
        let includesScreenshotsAndScreenRecordings: Bool

        init(today: Date) {
            let calendar = Calendar.autoupdatingCurrent
            let components = calendar.dateComponents([.year, .month, .day], from: today)
            year = components.year ?? 0
            month = components.month ?? 0
            day = components.day ?? 0
            timeZoneIdentifier = calendar.timeZone.identifier
            includesScreenshotsAndScreenRecordings = PhotoAssetEligibility.includesScreenshotsAndScreenRecordings
        }
    }

    private struct Key: Hashable, Sendable {
        let context: Context
        let scope: Scope
    }

    private struct Operation {
        let id: UUID
        let generation: UInt64
        let task: Task<OnThisDayScanPayload, Never>
        var progress: Double = 0
        var subscribers: [UUID: AsyncStream<Double>.Continuation] = [:]
    }

    private var operations: [Key: Operation] = [:]
    private var nextGeneration: UInt64 = 0
    private var latestGeneration: UInt64 = 0
    private var lastCommittedGeneration: UInt64 = 0
    private var isCommitting = false
    private var commitWaiters: [CheckedContinuation<Void, Never>] = []

    func fullScan(
        today: Date = .now,
        progress: ProgressHandler? = nil
    ) async -> [OnThisDayEntry]? {
        await request(context: Context(today: today), scope: .full, preserving: nil, today: today, progress: progress)
    }

    func currentYearRefresh(
        preserving entries: [OnThisDayEntry],
        today: Date = .now,
        progress: ProgressHandler? = nil
    ) async -> [OnThisDayEntry]? {
        let context = Context(today: today)
        let fullKey = Key(context: context, scope: .full)
        if operations[fullKey] != nil {
            // A complete historical scan contains everything needed by this
            // narrower check, so let the caller share its result.
            return await request(context: context, scope: .full, preserving: nil, today: today, progress: progress)
        }
        return await request(context: context, scope: .currentYear, preserving: entries, today: today, progress: progress)
    }

    private func request(
        context: Context,
        scope: Scope,
        preserving entriesToPreserve: [OnThisDayEntry]?,
        today: Date,
        progress handler: ProgressHandler?
    ) async -> [OnThisDayEntry]? {
        await waitForCommitIfNeeded()
        let key = Key(context: context, scope: scope)
        let operation: Operation
        if let existing = operations[key] {
            operation = existing
        } else {
            nextGeneration &+= 1
            latestGeneration = nextGeneration
            let id = UUID()
            let generation = nextGeneration
            let task = Task { @MainActor in
                switch scope {
                case .full:
                    return await OnThisDayLibrary.performFullScan(today: today) { value in
                        Task { await self.publish(value, for: key, operationID: id) }
                    }
                case .currentYear:
                    return OnThisDayLibrary.performCurrentYearRefresh(
                        preserving: entriesToPreserve ?? [],
                        today: today
                    )
                }
            }
            operation = Operation(id: id, generation: generation, task: task)
            operations[key] = operation
        }

        let subscriberID = UUID()
        var progressTask: Task<Void, Never>?
        if let handler {
            let streamPair = AsyncStream<Double>.makeStream()
            if let currentProgress = operations[key]?.progress {
                streamPair.continuation.yield(currentProgress)
            }
            operations[key]?.subscribers[subscriberID] = streamPair.continuation
            progressTask = Task { @MainActor in
                for await value in streamPair.stream {
                    guard !Task.isCancelled else { break }
                    handler(value)
                }
            }
        }

        let payload = await operation.task.value
        progressTask?.cancel()
        removeSubscriber(subscriberID, from: key)

        // Persistence crosses to the main actor. While that hop is pending, the
        // actor can process another request, so serialize commits and validate
        // the generation again after waiting.
        await waitForCommitIfNeeded()
        guard operation.generation == latestGeneration,
              context == Context(today: .now) else {
            removeOperation(operation.id, for: key)
            return nil
        }
        if operation.generation > lastCommittedGeneration {
            isCommitting = true
            await OnThisDayLibrary.persist(payload)
            lastCommittedGeneration = operation.generation
            finishCommit()
        }
        removeOperation(operation.id, for: key)
        return payload.entries
    }

    private func publish(_ value: Double, for key: Key, operationID: UUID) {
        guard var operation = operations[key], operation.id == operationID else { return }
        operation.progress = value
        for continuation in operation.subscribers.values {
            continuation.yield(value)
        }
        operations[key] = operation
    }

    private func removeSubscriber(_ id: UUID, from key: Key) {
        guard var operation = operations[key] else { return }
        operation.subscribers.removeValue(forKey: id)?.finish()
        operations[key] = operation
    }

    private func removeOperation(_ id: UUID, for key: Key) {
        guard operations[key]?.id == id else { return }
        operations[key]?.subscribers.values.forEach { $0.finish() }
        operations.removeValue(forKey: key)
    }

    private func waitForCommitIfNeeded() async {
        guard isCommitting else { return }
        await withCheckedContinuation { continuation in
            commitWaiters.append(continuation)
        }
    }

    private func finishCommit() {
        isCommitting = false
        let waiters = commitWaiters
        commitWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }
}
