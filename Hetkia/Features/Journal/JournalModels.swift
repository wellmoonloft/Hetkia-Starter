import Foundation
import SwiftData

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
    /// Selects the same set for diary generation, detail pages, and timeline previews.
    static func selected(from photos: [JournalPhotoRecord]) -> [JournalPhotoRecord] {
        let ordered = photos.sorted { $0.sortOrder < $1.sortOrder }
        let count = ordered.count
        let selectedCount = count > 9 ? 9 : (count.isMultiple(of: 2) ? max(0, count - 1) : count)
        return Array(ordered.prefix(selectedCount))
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
        metadataReadStatus: PhotoMetadataReadStatus, sortOrder: Int
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
        self.mediaType = "image"
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
