import Foundation
import Photos
import AVFoundation
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
                    if let original = await previewImage(for: asset, targetSize: targetSize) { return original }
                }
            }
        }
        return await thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: targetSize)
    }

    /// Full-screen photo viewing must never use the aspect-filled collage rendition.
    /// Resolve the original PhotoKit asset by its stable local identifier first,
    /// then fall back to the persisted, full-frame compressed JPEG.
    @MainActor
    static func fullFrameImage(for photo: JournalPhotoRecord, targetSize: CGSize) async -> CGImage? {
        if let identifier = photo.assetLocalIdentifier {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .authorized || status == .limited,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
               asset.mediaType == .image,
               let original = await requestFullFrameImage(for: asset, targetSize: targetSize) {
                return original
            }
        }
        return await thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: targetSize)
    }

    @MainActor
    static func previewImage(for asset: PHAsset, targetSize: CGSize) async -> CGImage? {
        if asset.mediaType == .video, let avAsset = await requestAVAsset(for: asset) {
            let generator = AVAssetImageGenerator(asset: avAsset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = targetSize
            return try? await generator.image(at: .zero).image
        }
        return await requestImage(for: asset, targetSize: targetSize)
    }

    @MainActor
    static func videoAsset(for photo: JournalPhotoRecord) async -> AVAsset? {
        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard photo.mediaType == "video",
              let identifier = photo.assetLocalIdentifier,
              authorization == .authorized || authorization == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
              asset.mediaType == .video else { return nil }
        return await requestAVAsset(for: asset)
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

    /// Remote publish / persisted JPEG encoding: keep original aspect (`aspectFit`), unlike collage `displayImage`.
    @MainActor
    static func publishUploadImage(for photo: JournalPhotoRecord, targetSize: CGSize) async -> CGImage? {
        if let identifier = photo.assetLocalIdentifier {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .authorized || status == .limited,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
                if asset.mediaType == .image,
                   let original = await requestFullFrameImage(for: asset, targetSize: targetSize) {
                    return original
                }
                if asset.mediaType == .video,
                   let frame = await previewImage(for: asset, targetSize: targetSize) {
                    return frame
                }
            }
        }
        return await thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: targetSize)
    }

    static func thumbnailURL(relativePath: String) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return support.appendingPathComponent(relativePath)
    }

    @MainActor
    static func persistThumbnail(for asset: PHAsset, targetSize: CGSize = CGSize(width: 1600, height: 1600)) async throws -> String {
        let image: CGImage?
        if asset.mediaType == .image {
            image = await requestFullFrameImage(for: asset, targetSize: targetSize)
        } else {
            image = await previewImage(for: asset, targetSize: targetSize)
        }
        guard let image else { throw PhotoImportError.unreadableAsset }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            throw PhotoImportError.couldNotCreateJPEG
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoImportError.couldNotCreateJPEG }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("JournalImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).jpg"
        try (data as Data).write(to: directory.appendingPathComponent(filename), options: .atomic)
        return "JournalImages/\(filename)"
    }

    @MainActor
    private static func requestFullFrameImage(for asset: PHAsset, targetSize: CGSize) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
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

    private static func requestImage(for asset: PHAsset, targetSize: CGSize) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            // Match the requested display resolution exactly. `.fast` can
            // return a smaller Photos rendition that looks soft in the detail
            // collage, especially on 3x displays.
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
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

    @MainActor
    private static func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
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
