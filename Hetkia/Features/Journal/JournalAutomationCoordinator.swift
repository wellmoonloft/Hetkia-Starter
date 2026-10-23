import Foundation
import Photos
import SwiftData
import CoreGraphics
#if !os(macOS)
import UIKit
#endif

private struct IndexedPhotoMetadata: Sendable {
    let identifier: String
    let creationDate: Date
    let modificationDate: Date?
    let latitude: Double?
    let longitude: Double?
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Runs only on foreground opportunities. The persistent task queue makes an interrupted
/// generation retryable on the next activation; iOS background timing is not guaranteed.
@MainActor
final class JournalAutomationCoordinator {
    static let shared = JournalAutomationCoordinator()
    private var isRunning = false
    private var historicalIndexTask: Task<Void, Never>?

    private let historicalIndexRequestedKey = "hetkia.historicalIndex.requested"
    private let historicalIndexCompletedKey = "hetkia.historicalIndex.completed"

    /// Creates photo-only journal entries for the most recent 30 calendar days. No AI task
    /// is inserted; users can request text generation later from each journal.
    func indexRecentJournals(context: ModelContext, progress: @escaping (Double) -> Void) async throws {
        guard canReadPhotoLibrary else {
            progress(1)
            return
        }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        try await indexPhotoDays(from: start, through: .now, context: context, progress: progress)
    }

    /// Starts a resumable metadata-only scan for all photos older than the recent 30-day
    /// window. The preference survives termination; the next foreground activation resumes it.
    func startHistoricalLibraryIndex(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: historicalIndexCompletedKey) else { return }
        UserDefaults.standard.set(true, forKey: historicalIndexRequestedKey)
        resumeHistoricalLibraryIndexIfNeeded(context: context)
    }

    func resumeHistoricalLibraryIndexIfNeeded(context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: historicalIndexRequestedKey), historicalIndexTask == nil else { return }
        historicalIndexTask = Task { [weak self] in
            guard let self else { return }
            defer { self.historicalIndexTask = nil }
#if !os(macOS)
            let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "HetkiaHistoricalPhotoIndex") {
                self.historicalIndexTask?.cancel()
            }
            defer {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
#endif
            guard self.canReadPhotoLibrary else { return }
            do {
                let calendar = Calendar.autoupdatingCurrent
                let recentStart = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: .now)) ?? .now
                try await self.indexPhotoDays(from: .distantPast, through: recentStart.addingTimeInterval(-1), context: context) { _ in }
                UserDefaults.standard.set(true, forKey: self.historicalIndexCompletedKey)
                UserDefaults.standard.set(false, forKey: self.historicalIndexRequestedKey)
            } catch {
                // Keep the request flag set so a later foreground activation can resume safely.
            }
        }
    }

    func catchUp(context: ModelContext) async {
        await run(context: context, includeOnThisDay: true)
    }

    func catchUpToday(context: ModelContext) async {
        await run(context: context, includeOnThisDay: false)
    }

    func retryFailedTask(dayKey: String, context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        guard let tasks = try? context.fetch(FetchDescriptor<JournalGenerationTask>()),
              let task = tasks.first(where: { $0.dayKey == dayKey && $0.status == .failed }) else { return }
        task.status = .pending
        task.lastError = nil
        task.journal?.generationStatus = .pending
        task.journal?.generationError = nil
        try? context.save()
        await processOnePendingTask(context: context, onlyDayKey: dayKey)
    }

    func cancelPendingTask(for journal: JournalRecord, context: ModelContext) {
        guard let tasks = try? context.fetch(FetchDescriptor<JournalGenerationTask>()),
              let task = tasks.first(where: {
                  $0.dayKey == journal.dayKey && $0.status == .pending
                      && $0.journal?.persistentModelID == journal.persistentModelID
              }) else { return }
        task.status = .cancelled
        journal.generationStatus = .cancelled
        try? context.save()
    }

    private func run(context: ModelContext, includeOnThisDay: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        do {
            let todayKey = PhotoDayGrouping.key(for: today, calendar: calendar)
            if try records(dayKey: todayKey, context: context).isEmpty,
               canReadPhotoLibrary {
                let assets = Self.assets(on: today, calendar: calendar)
                if !assets.isEmpty {
                    let journal = JournalRecord(dayKey: todayKey, localDay: today, source: .automatic)
                    context.insert(journal)
                    attach(assets, to: journal, context: context)
                    context.insert(JournalGenerationTask(dayKey: todayKey, journal: journal, type: .dailyAutomatic))
                }
            }

            if includeOnThisDay, canReadPhotoLibrary {
                let parts = calendar.dateComponents([.month, .day], from: today)
                let currentYear = calendar.component(.year, from: today)
                if let month = parts.month, let day = parts.day {
                    // This scans only one calendar date per past year, never all history.
                    for year in stride(from: currentYear - 1, through: 1970, by: -1) {
                        if year.isMultiple(of: 5) { await Task.yield() }
                        var dateParts = DateComponents()
                        dateParts.year = year
                        dateParts.month = month
                        dateParts.day = day
                        guard let historicDate = calendar.date(from: dateParts),
                              calendar.component(.year, from: historicDate) == year,
                              calendar.component(.month, from: historicDate) == month,
                              calendar.component(.day, from: historicDate) == day else { continue }

                        let key = PhotoDayGrouping.key(for: historicDate, calendar: calendar)
                        let assets = Self.assets(on: historicDate, calendar: calendar)
                        guard !assets.isEmpty else { continue }
                        let existing = try records(dayKey: key, context: context)
                        if let journal = existing.first {
                            if journal.photos.isEmpty { attach(assets, to: journal, context: context) }
                            // Existing manual or automatic records are displayed, never regenerated.
                            continue
                        }
                        let journal = JournalRecord(dayKey: key, localDay: calendar.startOfDay(for: historicDate), source: .automatic)
                        context.insert(journal)
                        attach(assets, to: journal, context: context)
                        context.insert(JournalGenerationTask(dayKey: key, journal: journal, type: .onThisDayBackfill))
                    }
                }
            }

            try context.save()
            await processOnePendingTask(context: context, onlyDayKey: includeOnThisDay ? nil : todayKey)
        } catch {
            // A later foreground activation retries the scan without creating empty records.
            try? context.save()
        }
    }

    private var canReadPhotoLibrary: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    private func indexPhotoDays(
        from start: Date,
        through end: Date,
        context: ModelContext,
        progress: @escaping (Double) -> Void
    ) async throws {
        let calendar = Calendar.autoupdatingCurrent
        // PhotoKit enumeration and metadata extraction can cover thousands of assets;
        // keep it off the main actor so the progress screen remains responsive.
        let photosByDay = await Task.detached(priority: .utility) {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            options.includeHiddenAssets = false
            let fetch = PHAsset.fetchAssets(with: .image, options: options)
            var grouped: [String: [IndexedPhotoMetadata]] = [:]
            fetch.enumerateObjects { asset, _, _ in
                guard PhotoAssetEligibility.allows(asset), let capturedAt = asset.creationDate else { return }
                let coordinate = asset.location?.coordinate
                let photo = IndexedPhotoMetadata(
                    identifier: asset.localIdentifier,
                    creationDate: capturedAt,
                    modificationDate: asset.modificationDate,
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight
                )
                grouped[PhotoDayGrouping.key(for: capturedAt, calendar: calendar), default: []].append(photo)
            }
            return grouped
        }.value

        let groups = photosByDay.keys.sorted()
        guard !groups.isEmpty else {
            progress(1)
            return
        }
        for (index, key) in groups.enumerated() {
            let assets = photosByDay[key] ?? []
            let existing = try records(dayKey: key, context: context)
            let journal = existing.first(where: { $0.source == .automatic }) ?? {
                let date = assets.first?.creationDate ?? .now
                let record = JournalRecord(dayKey: key, localDay: PhotoDayGrouping.representativeDate(for: date, calendar: calendar), source: .automatic)
                context.insert(record)
                return record
            }()
            attachMetadata(assets, to: journal, context: context)
            if journal.bodyText.isEmpty && journal.messagePosts.isEmpty && journal.generationStatus != .processing {
                journal.generationStatus = .skipped
            }
            if index.isMultiple(of: 24) || index == groups.count - 1 {
                try context.save()
                progress(Double(index + 1) / Double(groups.count))
                await Task.yield()
                try Task.checkCancellation()
            }
        }
    }

    private static func assets(on date: Date, calendar: Calendar) -> [PHAsset] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        var results: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            if PhotoAssetEligibility.allows(asset) { results.append(asset) }
        }
        return results
    }

    private func attach(_ assets: [PHAsset], to journal: JournalRecord, context: ModelContext) {
        let known = Set(journal.photos.compactMap(\.assetLocalIdentifier))
        for (index, asset) in assets.enumerated() where !known.contains(asset.localIdentifier) {
            let photo = JournalPhotoRecord(
                assetLocalIdentifier: asset.localIdentifier,
                capturedAt: asset.creationDate,
                addedAt: nil,
                modificationDate: asset.modificationDate,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude,
                locationStatus: asset.location == nil ? .unavailable : .available,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                orientationRaw: nil,
                thumbnailRelativePath: "",
                metadataReadStatus: asset.creationDate == nil ? .partial : .complete,
                sortOrder: journal.photos.count + index
            )
            photo.journal = journal
            context.insert(photo)
        }
        journal.photos.sort { ($0.capturedAt ?? .distantFuture) < ($1.capturedAt ?? .distantFuture) }
        for (index, photo) in journal.photos.enumerated() { photo.sortOrder = index }
    }

    private func attachMetadata(_ assets: [IndexedPhotoMetadata], to journal: JournalRecord, context: ModelContext) {
        let known = Set(journal.photos.compactMap(\.assetLocalIdentifier))
        for (index, asset) in assets.enumerated() where !known.contains(asset.identifier) {
            let photo = JournalPhotoRecord(
                assetLocalIdentifier: asset.identifier,
                capturedAt: asset.creationDate,
                addedAt: nil,
                modificationDate: asset.modificationDate,
                latitude: asset.latitude,
                longitude: asset.longitude,
                locationStatus: asset.latitude != nil && asset.longitude != nil ? .available : .unavailable,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                orientationRaw: nil,
                thumbnailRelativePath: "",
                metadataReadStatus: .complete,
                sortOrder: journal.photos.count + index
            )
            photo.journal = journal
            context.insert(photo)
        }
        journal.photos.sort { ($0.capturedAt ?? .distantFuture) < ($1.capturedAt ?? .distantFuture) }
        for (index, photo) in journal.photos.enumerated() { photo.sortOrder = index }
    }

    private func records(dayKey: String, context: ModelContext) throws -> [JournalRecord] {
        let automaticKey = "\(dayKey)|automatic"
        let manualKey = "\(dayKey)|manual"
        let legacyKey = dayKey
        let descriptor = FetchDescriptor<JournalRecord>(predicate: #Predicate {
            $0.storageKey == automaticKey || $0.storageKey == manualKey || $0.storageKey == legacyKey
        })
        return try context.fetch(descriptor)
    }

    private func processOnePendingTask(context: ModelContext, onlyDayKey: String? = nil) async {
        guard let tasks = try? context.fetch(FetchDescriptor<JournalGenerationTask>()) else { return }
        let pending = tasks.filter { $0.status == .pending && (onlyDayKey == nil || $0.dayKey == onlyDayKey) }
        guard let task = pending.sorted(by: {
            if ($0.taskType == .dailyAutomatic) != ($1.taskType == .dailyAutomatic) {
                return $0.taskType == .dailyAutomatic
            }
            return $0.createdAt < $1.createdAt
        }).first,
              let journal = task.journal else { return }
        do {
            let sameDay = try records(dayKey: task.dayKey, context: context)
            guard !hasDateConflict(sameDay, task: task, journal: journal),
                  !journal.bodyWasEdited, journal.bodyText.isEmpty else {
                task.status = .skipped
                try context.save()
                return
            }
            let photos = Self.selectedPhotos(journal.photos)
            guard !photos.isEmpty else {
                task.status = .skipped
                journal.generationStatus = .skipped
                try context.save()
                return
            }

            task.status = .processing
            task.attempts += 1
            task.lastError = nil
            journal.generationStatus = .processing
            journal.generationError = nil
            try context.save()

            guard #available(iOS 26, macOS 26, *) else {
                throw JournalDraftError.unavailable(JournalDraftService.availabilityDescription)
            }

            var images: [CGImage] = []
            if #available(iOS 27, macOS 27, *) {
                for photo in photos {
                    if let image = await PhotoAssetResolver.aiImage(for: photo) { images.append(image) }
                }
            }
            let beforeAI = try records(dayKey: task.dayKey, context: context)
            guard !hasDateConflict(beforeAI, task: task, journal: journal),
                  !journal.bodyWasEdited, journal.bodyText.isEmpty else {
                task.status = .skipped
                journal.generationStatus = .skipped
                try context.save()
                return
            }
            let result = try await JournalDraftService.generate(date: journal.localDay, photoCount: photos.count, imageSamples: images)

            // Recheck immediately before saving, in case the user created the manual entry while AI ran.
            let refreshed = try records(dayKey: task.dayKey, context: context)
            guard !hasDateConflict(refreshed, task: task, journal: journal),
                  !journal.bodyWasEdited, journal.bodyText.isEmpty else {
                task.status = .skipped
                journal.generationStatus = .skipped
                try context.save()
                return
            }
            journal.aiDraftBody = result.body
            journal.bodyText = result.body
            var posts = journal.messagePosts
            posts.append(JournalMessagePost(text: result.body, createdAt: .now, kind: .automatic))
            journal.messagePosts = posts
            journal.generationStatus = .completed
            journal.generationError = nil
            task.status = .completed
            task.lastError = nil
            try context.save()
        } catch {
            task.status = .failed
            task.lastError = error.localizedDescription
            journal.generationStatus = .failed
            journal.generationError = error.localizedDescription
            try? context.save()
        }
    }

    private func hasDateConflict(_ records: [JournalRecord], task: JournalGenerationTask, journal: JournalRecord) -> Bool {
        guard records.contains(where: { $0.persistentModelID == journal.persistentModelID }) else { return true }
        // Explicit manual generation is allowed alongside the other source for that day.
        return task.taskType != .manual && records.count > 1
    }

    private static func selectedPhotos(_ photos: [JournalPhotoRecord]) -> [JournalPhotoRecord] {
        JournalPhotoSelection.selected(from: photos)
    }
}
