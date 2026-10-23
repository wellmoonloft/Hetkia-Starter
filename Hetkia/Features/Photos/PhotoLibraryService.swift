import Foundation
import SwiftUI
import Photos
import ImageIO
import UniformTypeIdentifiers
import CoreLocation
import SwiftData
import Combine

struct ImportedPhotoSummary {
    var photoCount = 0
    var journalCount = 0
    var undatedCount = 0
    var excludedCount = 0
}

enum PhotoAssetEligibility {
    static func allows(_ asset: PHAsset) -> Bool {
        asset.mediaType == .image
            && !asset.isHidden
            && !asset.mediaSubtypes.contains(.photoScreenshot)
            && !asset.mediaSubtypes.contains(.videoScreenRecording)
    }
}

@MainActor
final class PhotoLibraryService: ObservableObject {
    @Published private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var canReadLibrary: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func refreshAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    func importAssets(_ assets: [PHAsset], into context: ModelContext) async throws -> ImportedPhotoSummary {
        var summary = ImportedPhotoSummary()
        var dirtyJournals: [String: JournalRecord] = [:]
        var tasksInsertedForDays = Set<String>()
        let completedDayKeys = Set(((try? context.fetch(FetchDescriptor<JournalRecord>())) ?? [])
            .filter { $0.generationStatus == .completed }
            .map(\.dayKey))
        var createdThumbnailPaths: [String] = []
        var committed = false
        defer {
            if !committed {
                context.rollback()
                for path in createdThumbnailPaths {
                    if let url = try? PhotoAssetResolver.thumbnailURL(relativePath: path) {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }

        for (index, asset) in assets.enumerated() {
            let identifier = asset.localIdentifier
            guard PhotoAssetEligibility.allows(asset) else {
                summary.excludedCount += 1
                continue
            }
            if let captureDate = asset.creationDate,
               completedDayKeys.contains(PhotoDayGrouping.key(for: captureDate)) {
                summary.excludedCount += 1
                continue
            }
            if try fetchPhoto(identifier: identifier, context: context) != nil {
                continue
            }
            let imported = try await prepare(asset: asset)
            createdThumbnailPaths.append(imported.relativePath)
            let addedDate: Date?
            if #available(iOS 26, macOS 26, *) { addedDate = asset.addedDate }
            else { addedDate = nil }
            let journal: JournalRecord?
            if let captureDate = imported.creationDate {
                let key = PhotoDayGrouping.key(for: captureDate)
                if let existing = try fetchJournal(dayKey: key, context: context) {
                    journal = existing
                } else {
                    let day = PhotoDayGrouping.representativeDate(for: captureDate)
                    let record = JournalRecord(dayKey: key, localDay: day, source: .automatic)
                    context.insert(record)
                    let type: JournalTaskType = key == PhotoDayGrouping.key(for: .now) ? .dailyAutomatic : .onThisDayBackfill
                    context.insert(JournalGenerationTask(dayKey: key, journal: record, type: type))
                    tasksInsertedForDays.insert(key)
                    journal = record
                    summary.journalCount += 1
                }
                if let journal { dirtyJournals[journal.dayKey] = journal }
            } else {
                journal = nil
                summary.undatedCount += 1
            }

            let photo = JournalPhotoRecord(
                assetLocalIdentifier: identifier,
                capturedAt: imported.creationDate,
                addedAt: addedDate,
                modificationDate: asset.modificationDate,
                latitude: asset.location?.coordinate.latitude ?? imported.latitude,
                longitude: asset.location?.coordinate.longitude ?? imported.longitude,
                locationStatus: (asset.location != nil || imported.latitude != nil) ? .available : .unavailable,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                orientationRaw: imported.orientation,
                thumbnailRelativePath: imported.relativePath,
                metadataReadStatus: imported.metadataComplete ? .complete : .partial,
                sortOrder: index
            )
            photo.journal = journal
            context.insert(photo)
            summary.photoCount += 1
        }

        for (key, journal) in dirtyJournals {
            journal.photos.sort { ($0.capturedAt ?? .distantFuture) < ($1.capturedAt ?? .distantFuture) }
            for (index, photo) in journal.photos.enumerated() { photo.sortOrder = index }
            journal.updatedAt = .now
            if journal.bodyText.isEmpty {
                journal.generationStatus = .pending
                let taskDescriptor = FetchDescriptor<JournalGenerationTask>(predicate: #Predicate { $0.dayKey == key })
                let hasPendingTask = ((try? context.fetch(taskDescriptor)) ?? []).contains { $0.status == .pending }
                if !tasksInsertedForDays.contains(key), !hasPendingTask {
                    context.insert(JournalGenerationTask(dayKey: key, journal: journal))
                    tasksInsertedForDays.insert(key)
                }
            }
        }
        try context.save()
        committed = true
        return summary
    }

    private func prepare(asset: PHAsset) async throws -> PreparedPhoto {
        if let data = await imageData(for: asset), let prepared = try? persistThumbnail(
            data: data,
            preferredDate: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude
        ) {
            return PreparedPhoto(
                creationDate: asset.creationDate ?? prepared.creationDate,
                latitude: asset.location?.coordinate.latitude ?? prepared.latitude,
                longitude: asset.location?.coordinate.longitude ?? prepared.longitude,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                orientation: prepared.orientation,
                relativePath: prepared.relativePath,
                metadataComplete: asset.creationDate != nil
            )
        }
        throw PhotoImportError.unreadableAsset
    }

    private func imageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func persistThumbnail(data: Data, preferredDate: Date?, latitude: Double?, longitude: Double?) throws -> PreparedPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw PhotoImportError.invalidImage
        }
        let orientation = (sourceProperties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw PhotoImportError.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoImportError.couldNotCreateJPEG
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoImportError.couldNotCreateJPEG }

        let directory = try thumbnailDirectory()
        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        try (output as Data).write(to: fileURL, options: .atomic)

        let exif = sourceProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let exifDate = parseExifDate(exif)
        let gps = sourceProperties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let gpsLatitude = latitude ?? coordinate(gps, valueKey: kCGImagePropertyGPSLatitude, refKey: kCGImagePropertyGPSLatitudeRef)
        let gpsLongitude = longitude ?? coordinate(gps, valueKey: kCGImagePropertyGPSLongitude, refKey: kCGImagePropertyGPSLongitudeRef)
        let width = (sourceProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? image.width
        let height = (sourceProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? image.height

        return PreparedPhoto(
            creationDate: preferredDate ?? exifDate,
            latitude: gpsLatitude,
            longitude: gpsLongitude,
            pixelWidth: width,
            pixelHeight: height,
            orientation: orientation,
            relativePath: "JournalImages/\(fileName)",
            metadataComplete: preferredDate != nil || exifDate != nil
        )
    }

    private func parseExifDate(_ exif: [CFString: Any]?) -> Date? {
        guard let value = exif?[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }

    private func coordinate(_ gps: [CFString: Any]?, valueKey: CFString, refKey: CFString) -> Double? {
        guard let value = (gps?[valueKey] as? NSNumber)?.doubleValue else { return nil }
        let ref = gps?[refKey] as? String
        return (ref == "S" || ref == "W") ? -value : value
    }

    private func thumbnailDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("JournalImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fetchJournal(dayKey: String, context: ModelContext) throws -> JournalRecord? {
        let automaticKey = "\(dayKey)|automatic"
        let manualKey = "\(dayKey)|manual"
        let legacyKey = dayKey
        let descriptor = FetchDescriptor<JournalRecord>(predicate: #Predicate {
            $0.storageKey == automaticKey || $0.storageKey == manualKey || $0.storageKey == legacyKey
        })
        return try context.fetch(descriptor).sorted { $0.source == .manual && $1.source == .automatic }.first
    }

    private func fetchPhoto(identifier: String, context: ModelContext) throws -> JournalPhotoRecord? {
        let descriptor = FetchDescriptor<JournalPhotoRecord>(predicate: #Predicate { $0.assetLocalIdentifier == identifier })
        return try context.fetch(descriptor).first
    }
}

private struct PreparedPhoto {
    let creationDate: Date?
    let latitude: Double?
    let longitude: Double?
    let pixelWidth: Int
    let pixelHeight: Int
    let orientation: Int?
    let relativePath: String
    let metadataComplete: Bool
}

enum PhotoImportError: LocalizedError {
    case unreadableAsset
    case invalidImage
    case couldNotCreateJPEG

    var errorDescription: String? {
        switch self {
        case .unreadableAsset: "This selected photo could not be read."
        case .invalidImage: "This selected item is not a readable image."
        case .couldNotCreateJPEG: "A compressed preview could not be created."
        }
    }
}
