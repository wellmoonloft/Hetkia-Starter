import Foundation
import Photos
import SwiftData

struct OnThisDayEntry: Identifiable {
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
        let refreshedAt: Date
        let entries: [Entry]
    }

    private static let schemaVersion = 2
    private static let fileName = "on-this-day-index.json"

    /// Restores cards using the current PhotoKit library. A nil result means there
    /// is no compatible cache; an empty array is a valid cached empty result.
    static func load(today: Date = .now) -> [OnThisDayEntry]? {
        clearIfExpired(today: today)
        guard PhotoLibraryService.hasFullReadAccess else { return nil }
        guard let data = try? Data(contentsOf: cacheURL()),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }

        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.month, .day], from: today)
        guard snapshot.year == parts.year,
              snapshot.month == parts.month,
              snapshot.day == parts.day,
              snapshot.timeZoneIdentifier == calendar.timeZone.identifier else { return nil }

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

/// A read-only PhotoKit query for the matching local month/day in each year.
/// It deliberately stores no JournalRecord and never requests image data.
@MainActor
enum OnThisDayLibrary {
    static func fetch(today: Date = .now, progress: ((Double) -> Void)? = nil) async -> [OnThisDayEntry] {
        OnThisDayCacheStore.clearIfExpired(today: today)
        guard PhotoLibraryService.hasFullReadAccess else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let nowParts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let month = nowParts.month, let day = nowParts.day, let currentYear = nowParts.year else { return [] }
        let earliestYear = 1900
        var found: [OnThisDayEntry] = []
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
                found.append(OnThisDayEntry(date: start, assets: JournalPhotoSelection.selectedAssets(from: assets)))
            }
            progress?(Double(year - earliestYear + 1) / Double(yearCount))
            if year % 8 == 0 { await Task.yield() }
        }
        let entries = found.sorted { $0.date > $1.date }
        OnThisDayCacheStore.save(entries, today: today)
        return entries
    }

    /// A same-day refresh only needs to discover photos captured in the current
    /// year. Older anniversary groups stay in the metadata cache unless the user
    /// explicitly requests a full refresh.
    static func refreshCurrentYear(
        preserving entries: [OnThisDayEntry],
        today: Date = .now
    ) -> [OnThisDayEntry] {
        guard PhotoLibraryService.hasFullReadAccess else { return entries }
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return entries }

        let currentEntry = fetchEntry(start: start, end: end)
        var merged = entries.filter { calendar.component(.year, from: $0.date) != year }
        if let currentEntry { merged.append(currentEntry) }
        merged.sort { $0.date > $1.date }
        OnThisDayCacheStore.save(merged, today: today)
        return merged
    }

    private static func fetchEntry(start: Date, end: Date) -> OnThisDayEntry? {
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
        return OnThisDayEntry(date: start, assets: JournalPhotoSelection.selectedAssets(from: assets))
    }

    static func transientPhotoRecords(for assets: [PHAsset]) -> [JournalPhotoRecord] {
        JournalPhotoSelection.selectedAssets(from: assets).enumerated().map { index, asset in
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
