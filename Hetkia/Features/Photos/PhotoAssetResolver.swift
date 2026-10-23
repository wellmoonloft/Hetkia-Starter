import Foundation
import Photos
import ImageIO
import SwiftData
import CoreGraphics
#if os(macOS)
import AppKit
typealias HetkiaImage = NSImage
#else
import UIKit
typealias HetkiaImage = UIImage
#endif

enum PhotoAssetResolver {
    @MainActor
    static func displayImage(for photo: JournalPhotoRecord, targetSize: CGSize) async -> CGImage? {
        if let identifier = photo.assetLocalIdentifier {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .authorized || status == .limited {
                if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
                    if let original = await requestImage(for: asset, targetSize: targetSize) {
                        photo.lastVerifiedAt = .now
                        photo.originalAvailabilityRaw = PhotoOriginalAvailability.available.rawValue
                        return original
                    }
                    photo.originalAvailabilityRaw = PhotoOriginalAvailability.missing.rawValue
                } else {
                    photo.originalAvailabilityRaw = PhotoOriginalAvailability.missing.rawValue
                }
            } else {
                photo.originalAvailabilityRaw = PhotoOriginalAvailability.permissionUnavailable.rawValue
            }
        }
        return await thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: targetSize)
    }

    static func thumbnailImage(relativePath: String, targetSize: CGSize) async -> CGImage? {
        guard !relativePath.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            guard let fileURL = try? thumbnailURL(relativePath: relativePath),
                  let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(max(max(targetSize.width, targetSize.height), 100))
            ] as CFDictionary)
        }.value
    }

    static func aiImage(for photo: JournalPhotoRecord) async -> CGImage? {
        await displayImage(for: photo, targetSize: CGSize(width: 1100, height: 1100))
    }

    static func thumbnailURL(relativePath: String) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return support.appendingPathComponent(relativePath)
    }

    private static func requestImage(for asset: PHAsset, targetSize: CGSize) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                guard (info?[PHImageCancelledKey] as? Bool) != true,
                      (info?[PHImageErrorKey] as? Error) == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image.flatMap(Self.cgImage(from:)))
            }
        }
    }

    private static func cgImage(from image: HetkiaImage) -> CGImage? {
        #if os(macOS)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }
}
