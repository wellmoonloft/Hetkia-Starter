import Foundation
import SwiftData
import Photos
import CoreGraphics

/// A journal is keyed by the photo's local calendar day at import time. The day key stays
/// stable if the device later changes time zone; `capturedAt` on each photo remains absolute.
@Model
final class JournalRecord {
    // Preserve the existing unique column as a renamed storage key. Values use
    // date|source so a day can hold one automatic and one manual journal.
    @Attribute(.unique, originalName: "dayKey") var storageKey: String
    var sourceRaw: String = JournalSource.manual.rawValue
    var localDay: Date
    var title: String
    var bodyText: String
    var aiDraftBody: String?
    /// Encoded message-board posts keep the original text and its timestamp together.
    var messagePostsData: Data?
    var bodyWasEdited: Bool
    var locationText: String?
    var moodText: String?
    var closingLine: String
    var generationStatusRaw: String
    var generationError: String?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \JournalPhotoRecord.journal)
    var photos: [JournalPhotoRecord] = []

    var dayKey: String {
        String(storageKey.split(separator: "|", maxSplits: 1).first ?? Substring(storageKey))
    }

    init(dayKey: String, localDay: Date, title: String = "", bodyText: String = "", closingLine: String = "", source: JournalSource = .manual) {
        self.storageKey = "\(dayKey)|\(source.rawValue)"
        self.sourceRaw = source.rawValue
        self.localDay = localDay
        self.title = title
        self.bodyText = bodyText
        self.aiDraftBody = nil
        self.messagePostsData = nil
        self.bodyWasEdited = false
        self.locationText = nil
        self.moodText = nil
        self.closingLine = closingLine
        self.generationStatusRaw = JournalGenerationStatus.pending.rawValue
        self.generationError = nil
        self.createdAt = .now
        self.updatedAt = .now
    }

    var generationStatus: JournalGenerationStatus {
        get { JournalGenerationStatus(rawValue: generationStatusRaw) ?? .pending }
        set { generationStatusRaw = newValue.rawValue; updatedAt = .now }
    }

    var source: JournalSource {
        get { JournalSource(rawValue: sourceRaw) ?? .manual }
        set {
            sourceRaw = newValue.rawValue
            storageKey = "\(dayKey)|\(newValue.rawValue)"
            updatedAt = .now
        }
    }

    var routeKey: String { "\(dayKey)|\(sourceRaw)" }

    var messagePosts: [JournalMessagePost] {
        get {
            guard let messagePostsData else { return [] }
            return (try? JSONDecoder().decode([JournalMessagePost].self, from: messagePostsData)) ?? []
        }
        set { messagePostsData = try? JSONEncoder().encode(newValue) }
    }
}

struct JournalMessagePost: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case automatic, note }

    var id: UUID
    var text: String
    var createdAt: Date
    var kind: Kind

    init(id: UUID = UUID(), text: String, createdAt: Date = .now, kind: Kind) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.kind = kind
    }
}

enum JournalPhotoSelection {
    /// Selects the bounded set used for diary generation and representative previews.
    static func selected(from photos: [JournalPhotoRecord]) -> [JournalPhotoRecord] {
        let eligible = PhotoAssetEligibility.eligiblePersistedPhotos(photos)
        let ordered = eligible.sorted {
            if $0.isPriorityPhoto != $1.isPriorityPhoto { return $0.isPriorityPhoto && !$1.isPriorityPhoto }
            let lhsHasLocation = $0.latitude != nil && $0.longitude != nil
            let rhsHasLocation = $1.latitude != nil && $1.longitude != nil
            if lhsHasLocation != rhsHasLocation { return lhsHasLocation && !rhsHasLocation }
            if $0.capturedAt != $1.capturedAt { return ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
            return $0.sortOrder < $1.sortOrder
        }
        let count = ordered.count
        let selectedCount = count > 9 ? 9 : (count.isMultiple(of: 2) ? max(0, count - 1) : count)
        return Array(ordered.prefix(selectedCount))
    }

    /// Keeps the established 1/3/5/7/9 composition while ranking ordinary camera
    /// photos ahead of screenshots and screen recordings. Those lower-priority
    /// assets remain eligible when needed to fill the day's selected count.
    static func selectedAssets(from assets: [PHAsset]) -> [PHAsset] {
        let eligible = assets.filter(PhotoAssetEligibility.allows)
        let targetCount = eligible.count > 9 ? 9 : (eligible.count.isMultiple(of: 2) ? max(0, eligible.count - 1) : eligible.count)
        let ranked = eligible.sorted { lhs, rhs in
            let lhsPriority = PhotoAssetEligibility.isPriorityAsset(lhs)
            let rhsPriority = PhotoAssetEligibility.isPriorityAsset(rhs)
            if lhsPriority != rhsPriority { return lhsPriority && !rhsPriority }
            let lhsHasLocation = lhs.location != nil
            let rhsHasLocation = rhs.location != nil
            if lhsHasLocation != rhsHasLocation { return lhsHasLocation && !rhsHasLocation }
            return (lhs.creationDate ?? .distantPast) > (rhs.creationDate ?? .distantPast)
        }
        return Array(ranked.prefix(targetCount))
    }

    /// The timeline and journal detail present every eligible image. Ranking and
    /// count reduction belong only to generation/widget selection, never display.
    static func displayAssets(from assets: [PHAsset]) -> [PHAsset] {
        assets.filter(PhotoAssetEligibility.allows).sorted {
            let lhsPriority = PhotoAssetEligibility.isPriorityAsset($0)
            let rhsPriority = PhotoAssetEligibility.isPriorityAsset($1)
            if lhsPriority != rhsPriority { return lhsPriority && !rhsPriority }
            let lhsHasLocation = $0.location != nil
            let rhsHasLocation = $1.location != nil
            if lhsHasLocation != rhsHasLocation { return lhsHasLocation && !rhsHasLocation }
            return ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
        }
    }

    static func displayPhotos(from photos: [JournalPhotoRecord]) -> [JournalPhotoRecord] {
        PhotoAssetEligibility.eligiblePersistedPhotos(photos).sorted {
            if $0.isPriorityPhoto != $1.isPriorityPhoto { return $0.isPriorityPhoto && !$1.isPriorityPhoto }
            let lhsHasLocation = $0.latitude != nil && $0.longitude != nil
            let rhsHasLocation = $1.latitude != nil && $1.longitude != nil
            if lhsHasLocation != rhsHasLocation { return lhsHasLocation && !rhsHasLocation }
            if $0.capturedAt != $1.capturedAt { return ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
            return $0.sortOrder < $1.sortOrder
        }
    }
}

/// Responsive mosaic positions expressed in normalized card coordinates.
/// One base unit is one third of the card width; every source image gets a tile.
enum PhotoMosaicLayout {
    struct Tile: Identifiable {
        let index: Int
        let rect: CGRect
        var id: Int { index }
    }

    static func height(width: CGFloat, count: Int, gap: CGFloat = 0) -> CGFloat {
        guard count > 0 else { return width }
        let rowCount = gridRowCount(for: count)
        let unit = (width - gap * 2) / 3
        return unit * CGFloat(rowCount) + gap * CGFloat(max(0, rowCount - 1))
    }

    static func tiles(width: CGFloat, count: Int, gap: CGFloat) -> [Tile] {
        guard count > 0 else { return [] }
        let height = height(width: width, count: count, gap: gap)
        if count == 1 { return [Tile(index: 0, rect: CGRect(x: 0, y: 0, width: width, height: height))] }
        let unit = (width - gap * 2) / 3
        let step = unit + gap
        let wide = unit * 2 + gap
        if count == 2 {
            // Two photos use a 2/3 + 1/3 split and share a two-unit height.
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: wide, height: height)),
                Tile(index: 1, rect: CGRect(x: wide + gap, y: 0, width: unit, height: height))
            ]
        }
        if count == 3 {
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: wide, height: wide)),
                Tile(index: 1, rect: CGRect(x: 2 * step, y: 0, width: unit, height: unit)),
                Tile(index: 2, rect: CGRect(x: 2 * step, y: step, width: unit, height: unit))
            ]
        }
        if count == 6 {
            // Fill a 3×3 block with one horizontal and two separated vertical
            // double tiles. This avoids a rigid row of three portrait tiles.
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: wide, height: unit)),
                Tile(index: 1, rect: CGRect(x: 0, y: step, width: unit, height: wide)),
                Tile(index: 2, rect: CGRect(x: 2 * step, y: step, width: unit, height: wide)),
                Tile(index: 3, rect: CGRect(x: 2 * step, y: 0, width: unit, height: unit)),
                Tile(index: 4, rect: CGRect(x: step, y: step, width: unit, height: unit)),
                Tile(index: 5, rect: CGRect(x: step, y: 2 * step, width: unit, height: unit))
            ]
        }
        let tailCount = count % 3 == 1 ? 4 : (count % 3 == 2 ? 5 : 0)
        let fullCount = count - tailCount
        var result: [Tile] = []

        for index in 0..<fullCount {
            let column = index % 3
            let row = index / 3
            result.append(Tile(
                index: index, rect: CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: unit, height: unit)
            ))
        }

        guard tailCount > 0 else { return result }
        let baseIndex = fullCount
        let baseRow = fullCount / 3
        let x0: CGFloat = 0
        let x1 = step
        let x2 = step * 2
        let y0 = CGFloat(baseRow) * step
        let y1 = y0 + step
        let y2 = y1 + step

        if tailCount == 4 {
            // Separate the vertical and horizontal double tiles instead of
            // stacking all oversized tiles together on the same edge.
            // The final 3×3 block remains completely covered.
            result.append(Tile(index: baseIndex, rect: CGRect(x: x0, y: y0, width: wide, height: wide)))
            result.append(Tile(index: baseIndex + 1, rect: CGRect(x: x2, y: y0, width: unit, height: unit)))
            result.append(Tile(index: baseIndex + 2, rect: CGRect(x: x2, y: y1, width: unit, height: wide)))
            result.append(Tile(index: baseIndex + 3, rect: CGRect(x: x0, y: y2, width: wide, height: unit)))
        } else {
            // Fill a 3×2 block with one 2×1 tile and four single cells.
            result.append(Tile(index: baseIndex, rect: CGRect(x: x0, y: y0, width: wide, height: unit)))
            result.append(Tile(index: baseIndex + 1, rect: CGRect(x: x2, y: y0, width: unit, height: unit)))
            result.append(Tile(index: baseIndex + 2, rect: CGRect(x: x0, y: y1, width: unit, height: unit)))
            result.append(Tile(index: baseIndex + 3, rect: CGRect(x: x1, y: y1, width: unit, height: unit)))
            result.append(Tile(index: baseIndex + 4, rect: CGRect(x: x2, y: y1, width: unit, height: unit)))
        }
        return result
    }

    private static func gridRowCount(for count: Int) -> Int {
        guard count > 0 else { return 0 }
        if count == 1 { return 3 }
        if count == 2 || count == 3 { return 2 }
        if count == 6 { return 3 }
        let tailCount = count % 3 == 1 ? 4 : (count % 3 == 2 ? 5 : 0)
        let fullCount = count - tailCount
        let fullRows = fullCount / 3
        let tailRows = tailCount == 4 ? 3 : (tailCount == 5 ? 2 : 0)
        return max(1, fullRows + tailRows)
    }
}

@Model
final class JournalPhotoRecord {
    @Attribute(.unique) var id: UUID
    var assetLocalIdentifier: String?
    var capturedAt: Date?
    var addedAt: Date?
    var modificationDate: Date?
    var firstDiscoveredAt: Date
    var latitude: Double?
    var longitude: Double?
    var locationStatusRaw: String
    var placeName: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var mediaType: String
    var isPriorityPhoto: Bool = true
    var orientationRaw: Int?
    var thumbnailRelativePath: String
    var metadataReadStatusRaw: String
    var lastVerifiedAt: Date?
    var originalAvailabilityRaw: String
    var sortOrder: Int
    var journal: JournalRecord?

    init(
        assetLocalIdentifier: String?, capturedAt: Date?, addedAt: Date?, modificationDate: Date?,
        latitude: Double?, longitude: Double?, locationStatus: PhotoLocationStatus,
        pixelWidth: Int, pixelHeight: Int, orientationRaw: Int?, thumbnailRelativePath: String,
        metadataReadStatus: PhotoMetadataReadStatus, sortOrder: Int,
        mediaType: String = "image", isPriorityPhoto: Bool = true
    ) {
        self.id = UUID()
        self.assetLocalIdentifier = assetLocalIdentifier
        self.capturedAt = capturedAt
        self.addedAt = addedAt
        self.modificationDate = modificationDate
        self.firstDiscoveredAt = .now
        self.latitude = latitude
        self.longitude = longitude
        self.locationStatusRaw = locationStatus.rawValue
        self.placeName = nil
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.mediaType = mediaType
        self.isPriorityPhoto = isPriorityPhoto
        self.orientationRaw = orientationRaw
        self.thumbnailRelativePath = thumbnailRelativePath
        self.metadataReadStatusRaw = metadataReadStatus.rawValue
        self.lastVerifiedAt = assetLocalIdentifier == nil ? nil : .now
        self.originalAvailabilityRaw = assetLocalIdentifier == nil ? PhotoOriginalAvailability.notLinked.rawValue : PhotoOriginalAvailability.unknown.rawValue
        self.sortOrder = sortOrder
    }

    var locationStatus: PhotoLocationStatus {
        get { PhotoLocationStatus(rawValue: locationStatusRaw) ?? .unavailable }
        set { locationStatusRaw = newValue.rawValue }
    }

    var metadataReadStatus: PhotoMetadataReadStatus {
        get { PhotoMetadataReadStatus(rawValue: metadataReadStatusRaw) ?? .partial }
        set { metadataReadStatusRaw = newValue.rawValue }
    }
}

@Model
final class JournalGenerationTask {
    @Attribute(.unique) var id: UUID
    var dayKey: String
    var taskTypeRaw: String = JournalTaskType.manual.rawValue
    var statusRaw: String
    var attempts: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date
    var journal: JournalRecord?

    init(dayKey: String, journal: JournalRecord?, type: JournalTaskType = .manual) {
        self.id = UUID()
        self.dayKey = dayKey
        self.taskTypeRaw = type.rawValue
        self.statusRaw = JournalGenerationStatus.pending.rawValue
        self.attempts = 0
        self.lastError = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.journal = journal
    }

    var status: JournalGenerationStatus {
        get { JournalGenerationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue; updatedAt = .now }
    }

    var taskType: JournalTaskType {
        get { JournalTaskType(rawValue: taskTypeRaw) ?? .manual }
        set { taskTypeRaw = newValue.rawValue; updatedAt = .now }
    }
}

enum JournalSource: String, Codable { case automatic, manual }

enum JournalTaskType: String, Codable { case dailyAutomatic, onThisDayBackfill, manual }

enum JournalGenerationStatus: String, Codable {
    case pending, processing, completed, failed, skipped, cancelled
}

enum PhotoLocationStatus: String, Codable {
    case available, unavailable, geocodingPending, geocodingFailed
}

enum PhotoMetadataReadStatus: String, Codable {
    case complete, partial, failed
}

enum PhotoOriginalAvailability: String, Codable {
    case unknown, available, missing, permissionUnavailable, notLinked
}

enum PhotoDayGrouping {
    /// Capture timestamps are grouped using the current device calendar/time zone when
    /// imported. Once saved, the `yyyy-MM-dd` key does not shift with later time-zone changes.
    static func key(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func representativeDate(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: parts) ?? date
    }
}
