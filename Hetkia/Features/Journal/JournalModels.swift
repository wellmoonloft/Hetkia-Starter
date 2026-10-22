import Foundation
import SwiftData

/// A journal is keyed by the photo's local calendar day at import time. The day key stays
/// stable if the device later changes time zone; `capturedAt` on each photo remains absolute.
@Model
final class JournalRecord {
    @Attribute(.unique) var dayKey: String
    var localDay: Date
    var title: String
    var bodyText: String
    var aiDraftBody: String?
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

    init(dayKey: String, localDay: Date, title: String = "", bodyText: String = "", closingLine: String = "") {
        self.dayKey = dayKey
        self.localDay = localDay
        self.title = title
        self.bodyText = bodyText
        self.aiDraftBody = nil
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
    var statusRaw: String
    var attempts: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date
    var journal: JournalRecord?

    init(dayKey: String, journal: JournalRecord?) {
        self.id = UUID()
        self.dayKey = dayKey
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
}

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
