import SwiftUI
import WidgetKit
import Photos
import AVFoundation
import CryptoKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private struct WidgetMemory: Identifiable {
    let date: Date
    let imageData: Data

    var id: String {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

private struct HetkiaWidgetEntry: TimelineEntry {
    let date: Date
    let memories: [WidgetMemory]
    let hasPhotoAccess: Bool
}

private struct WidgetIndexSnapshot: Codable {
    struct Item: Codable {
        let date: Date
        let assetIdentifier: String
        let assetModificationDate: Date?
    }

    let schemaVersion: Int
    let year: Int
    let month: Int
    let day: Int
    let timeZoneIdentifier: String
    let includesScreenshotsAndScreenRecordings: Bool
    let refreshedAt: Date
    let entries: [Item]
    let contentFingerprint: String
}

private struct HetkiaWidgetProvider: TimelineProvider {
    private let settingsDefaults = UserDefaults(suiteName: "group.com.hetkia.app")

    func placeholder(in context: Context) -> HetkiaWidgetEntry {
        HetkiaWidgetEntry(date: .now, memories: [], hasPhotoAccess: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (HetkiaWidgetEntry) -> Void) {
        let imageSize: CGFloat = context.family == .systemSmall ? 480 : 1000
        Task { completion(await loadEntry(imageSize: imageSize)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HetkiaWidgetEntry>) -> Void) {
        let imageSize: CGFloat = context.family == .systemSmall ? 480 : 1000
        Task {
            let entry = await loadEntry(imageSize: imageSize)
            let refresh = Calendar.autoupdatingCurrent.nextDate(
                after: .now,
                matching: DateComponents(hour: 0, minute: 0),
                matchingPolicy: .nextTime
            ) ?? .now.addingTimeInterval(86_400)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    @MainActor
    private func loadEntry(imageSize: CGFloat) async -> HetkiaWidgetEntry {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            return HetkiaWidgetEntry(date: .now, memories: [], hasPhotoAccess: false)
        }

        let groups: [(date: Date, assets: [PHAsset])]
        if let cachedGroups = groupsFromSharedSnapshot() {
            groups = cachedGroups
        } else {
            groups = matchingPhotoGroups()
            writeSharedSnapshot(from: groups)
        }
        // Keep up to nine anniversary memories. The fixed widget canvas has
        // dedicated layouts for every count, including the two-photo inset.
        // Groups are reversed so the collage reads oldest anniversary to today.
        let availableCount = groups.count
        let selectedCount = min(9, availableCount)
        let chosenGroups = Array(groups.prefix(selectedCount).reversed())
        var memories: [WidgetMemory] = []
        for group in chosenGroups {
            guard let firstAsset = group.assets.first,
                  let image = await preview(for: firstAsset, targetSize: imageSize),
                  let data = jpegData(from: image) else { continue }
            memories.append(WidgetMemory(date: group.date, imageData: data))
        }
        return HetkiaWidgetEntry(date: .now, memories: memories, hasPhotoAccess: true)
    }

    @MainActor
    private func matchingPhotoGroups() -> [(date: Date, assets: [PHAsset])] {
        let includesScreenshots = settingsDefaults?.bool(forKey: "hetkia.includeScreenshotsAndScreenRecordings") ?? false
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: .now)
        guard let month = components.month, let day = components.day, let currentYear = components.year else { return [] }

        var groups: [(date: Date, assets: [PHAsset])] = []
        for year in stride(from: currentYear, through: 1900, by: -1) {
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let resolved = calendar.dateComponents([.month, .day], from: start)
            guard resolved.month == month, resolved.day == day else { continue }

            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let fetched = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            fetched.enumerateObjects { asset, _, _ in
                guard !asset.isHidden, asset.mediaType == .image || asset.mediaType == .video else { return }
                let isPriorityAsset = !asset.mediaSubtypes.contains(.photoScreenshot)
                    && !asset.mediaSubtypes.contains(.videoScreenRecording)
                guard includesScreenshots || isPriorityAsset else { return }
                assets.append(asset)
            }
            guard !assets.isEmpty else { continue }

            let selected = assets.sorted {
                let lhsHasLocation = $0.location != nil
                let rhsHasLocation = $1.location != nil
                if lhsHasLocation != rhsHasLocation { return lhsHasLocation && !rhsHasLocation }
                let lhsEveryday = !($0.mediaSubtypes.contains(.photoScreenshot) || $0.mediaSubtypes.contains(.videoScreenRecording))
                let rhsEveryday = !($1.mediaSubtypes.contains(.photoScreenshot) || $1.mediaSubtypes.contains(.videoScreenRecording))
                if lhsEveryday != rhsEveryday { return lhsEveryday && !rhsEveryday }
                return ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
            }
            groups.append((date: start, assets: selected))
        }
        return groups
    }

    /// Reads the app's widget-specific index so WidgetKit doesn't repeat the
    /// historical year-by-year PhotoKit queries during normal timeline loads.
    /// A missing, stale, incompatible, or partially deleted snapshot falls back
    /// to the established PhotoKit scan below.
    @MainActor
    private func groupsFromSharedSnapshot() -> [(date: Date, assets: [PHAsset])]? {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.hetkia.app"
        )?.appendingPathComponent("on-this-day-widget-index.json"),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetIndexSnapshot.self, from: data),
              isCurrent(snapshot),
              snapshot.contentFingerprint == fingerprint(for: snapshot.entries) else { return nil }

        let identifiers = snapshot.entries.map(\.assetIdentifier)
        guard !identifiers.isEmpty else {
            recordWidgetFingerprint(snapshot.contentFingerprint)
            return []
        }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetsByIdentifier: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in
            let includesScreenshots = settingsDefaults?.bool(forKey: "hetkia.includeScreenshotsAndScreenRecordings") ?? false
            let isVisibleMedia = !asset.isHidden && (asset.mediaType == .image || asset.mediaType == .video)
            let isPriority = !asset.mediaSubtypes.contains(.photoScreenshot)
                && !asset.mediaSubtypes.contains(.videoScreenRecording)
            if isVisibleMedia && (includesScreenshots || isPriority) {
                assetsByIdentifier[asset.localIdentifier] = asset
            }
        }
        guard assetsByIdentifier.count == Set(identifiers).count else { return nil }

        recordWidgetFingerprint(snapshot.contentFingerprint)
        return snapshot.entries.compactMap { item in
            guard let asset = assetsByIdentifier[item.assetIdentifier] else { return nil }
            return (date: item.date, assets: [asset])
        }
    }

    @MainActor
    private func isCurrent(_ snapshot: WidgetIndexSnapshot) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: .now)
        let includesScreenshots = settingsDefaults?.bool(forKey: "hetkia.includeScreenshotsAndScreenRecordings") ?? false
        return snapshot.schemaVersion == 1
            && snapshot.year == parts.year
            && snapshot.month == parts.month
            && snapshot.day == parts.day
            && snapshot.timeZoneIdentifier == calendar.timeZone.identifier
            && snapshot.includesScreenshotsAndScreenRecordings == includesScreenshots
    }

    private func fingerprint(for entries: [WidgetIndexSnapshot.Item]) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: .now)
        let includesScreenshots = settingsDefaults?.bool(forKey: "hetkia.includeScreenshotsAndScreenRecordings") ?? false
        let canonical = ([
            "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)",
            calendar.timeZone.identifier,
            includesScreenshots ? "1" : "0"
        ] + entries.sorted { $0.date > $1.date }.map { item in
            let modification = item.assetModificationDate.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "none"
            return "\(calendar.component(.year, from: item.date)):\(item.assetIdentifier):\(modification)"
        }).joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private func writeSharedSnapshot(from groups: [(date: Date, assets: [PHAsset])]) {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: .now)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.hetkia.app"
              )?.appendingPathComponent("on-this-day-widget-index.json") else { return }
        let items = groups.compactMap { group -> WidgetIndexSnapshot.Item? in
            guard let first = group.assets.first else { return nil }
            return WidgetIndexSnapshot.Item(
                date: group.date,
                assetIdentifier: first.localIdentifier,
                assetModificationDate: first.modificationDate
            )
        }.sorted { $0.date > $1.date }
        let includesScreenshots = settingsDefaults?.bool(forKey: "hetkia.includeScreenshotsAndScreenRecordings") ?? false
        let snapshot = WidgetIndexSnapshot(
            schemaVersion: 1,
            year: year,
            month: month,
            day: day,
            timeZoneIdentifier: calendar.timeZone.identifier,
            includesScreenshotsAndScreenRecordings: includesScreenshots,
            refreshedAt: .now,
            entries: items,
            contentFingerprint: fingerprint(for: items)
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: url, options: .atomic)
            recordWidgetFingerprint(snapshot.contentFingerprint)
        } catch {
            // A later WidgetKit request can retry the legacy PhotoKit path.
        }
    }

    private func recordWidgetFingerprint(_ fingerprint: String) {
        settingsDefaults?.set(fingerprint, forKey: "hetkia.widget.lastReloadedFingerprint")
    }

    @MainActor
    private func preview(for asset: PHAsset, targetSize: CGFloat) async -> CGImage? {
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            let video: AVAsset? = await withCheckedContinuation { continuation in
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, _ in
                    continuation.resume(returning: video)
                }
            }
            guard let video else { return nil }
            let generator = AVAssetImageGenerator(asset: video)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: targetSize, height: targetSize)
            return try? await generator.image(at: .zero).image
        }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: targetSize, height: targetSize),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                #if os(macOS)
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                #else
                continuation.resume(returning: image?.cgImage)
                #endif
            }
        }
    }

    private func jpegData(from image: CGImage) -> Data? {
        #if os(macOS)
        NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.76])
        #else
        UIImage(cgImage: image).jpegData(compressionQuality: 0.76)
        #endif
    }
}

private struct HetkiaWidgetView: View {
    let entry: HetkiaWidgetEntry
    @Environment(\.widgetFamily) private var family
    private var isStandBySize: Bool { family == .systemSmall }

    var body: some View {
        Group {
            if isStandBySize {
                if entry.memories.isEmpty {
                    emptyState
                } else {
                    WidgetMemoryCollage(memories: entry.memories, rounded: false, showsDates: true)
                }
            } else {
                if entry.memories.isEmpty {
                    emptyState
                } else {
                    WidgetMemoryCollage(memories: entry.memories, rounded: false, showsDates: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Keep collage gaps transparent; WidgetKit can still remove or tint
        // the container background for contexts such as StandBy and Clear mode.
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var emptyState: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Image("Unknown")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    if entry.hasPhotoAccess {
                        Text("widget.empty.today")
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                        Text("widget.empty.no-memories")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                    } else {
                        Text("onboarding.photos.status.denied")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
                .padding(16)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WidgetMemoryCollage: View {
    let memories: [WidgetMemory]
    let rounded: Bool
    // A zero-width seam avoids exposing a system-composited widget background
    // between photos, which can look opaque in Clear or StandBy presentations.
    private var gap: CGFloat { 0 }
    var showsDates: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let layoutWidth: CGFloat = 1_000
            let layoutHeight = WidgetMosaicLayout.height(width: layoutWidth, count: memories.count)
            let tiles = WidgetMosaicLayout.tiles(width: layoutWidth, count: memories.count)
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    let x = tile.rect.minX / layoutWidth * geometry.size.width
                    let y = tile.rect.minY / layoutHeight * geometry.size.height
                    let width = tile.rect.width / layoutWidth * geometry.size.width
                    let height = tile.rect.height / layoutHeight * geometry.size.height
                    linkedPhoto(memories[tile.index], width: width, height: height)
                        .frame(width: width, height: height)
                        .position(x: x + width / 2, y: y + height / 2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(Color.clear)
        .clipShape(rounded ? AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) : AnyShape(Rectangle()))
    }

    private func linkedPhoto(_ memory: WidgetMemory, width: CGFloat, height: CGFloat) -> some View {
        Link(destination: URL(string: "hetkia://onthisday/\(memory.id)")!) {
            ZStack(alignment: .topLeading) {
                photo(for: memory.imageData)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()

                if showsDates {
                    WidgetDateOverlay(date: memory.date, width: width, height: height)
                }
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }

    private func photo(for data: Data) -> Image {
        #if os(macOS)
        Image(nsImage: NSImage(data: data) ?? NSImage(size: .zero))
        #else
        Image(uiImage: UIImage(data: data) ?? UIImage())
        #endif
    }
}

/// Widget-local copy of the app mosaic geometry. The extension is a separate
/// target/process, so it cannot depend on the app target's SwiftData model file.
private enum WidgetMosaicLayout {
    struct Tile: Identifiable {
        let index: Int
        let rect: CGRect
        var id: Int { index }
    }

    static func height(width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return width }
        // The widget canvas is fixed. Each count-specific arrangement fills the
        // same square, so the view can scale to any WidgetKit family size.
        return width
    }

    static func tiles(width: CGFloat, count: Int) -> [Tile] {
        guard count > 0 else { return [] }
        if count == 1 { return [Tile(index: 0, rect: CGRect(x: 0, y: 0, width: width, height: width))] }
        let unit = width / 3
        if count == 2 {
            // A full image with a small lower-right inset uses all memories
            // without making two equal half-sized photos dominate the widget.
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: width, height: width)),
                Tile(index: 1, rect: CGRect(x: unit * 2, y: unit * 2, width: unit, height: unit))
            ]
        }
        if count == 3 {
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: unit * 2, height: width)),
                Tile(index: 1, rect: CGRect(x: unit * 2, y: 0, width: unit, height: unit * 2)),
                Tile(index: 2, rect: CGRect(x: unit * 2, y: unit * 2, width: unit, height: unit))
            ]
        }
        if count == 4 {
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: unit * 2, height: unit * 2)),
                Tile(index: 1, rect: CGRect(x: unit * 2, y: 0, width: unit, height: unit * 2)),
                Tile(index: 2, rect: CGRect(x: 0, y: unit * 2, width: unit * 2, height: unit)),
                Tile(index: 3, rect: CGRect(x: unit * 2, y: unit * 2, width: unit, height: unit))
            ]
        }
        if count == 5 {
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: unit * 2, height: unit * 2)),
                Tile(index: 1, rect: CGRect(x: unit * 2, y: 0, width: unit, height: unit * 2)),
                Tile(index: 2, rect: CGRect(x: 0, y: unit * 2, width: unit, height: unit)),
                Tile(index: 3, rect: CGRect(x: unit, y: unit * 2, width: unit, height: unit)),
                Tile(index: 4, rect: CGRect(x: unit * 2, y: unit * 2, width: unit, height: unit))
            ]
        }
        if count == 6 {
            // Mix one horizontal and two separated vertical double tiles.
            // The remaining single cells fill every part of the 3×3 canvas.
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: unit * 2, height: unit)),
                Tile(index: 1, rect: CGRect(x: 0, y: unit, width: unit, height: unit * 2)),
                Tile(index: 2, rect: CGRect(x: unit * 2, y: unit, width: unit, height: unit * 2)),
                Tile(index: 3, rect: CGRect(x: unit * 2, y: 0, width: unit, height: unit)),
                Tile(index: 4, rect: CGRect(x: unit, y: unit, width: unit, height: unit)),
                Tile(index: 5, rect: CGRect(x: unit, y: unit * 2, width: unit, height: unit))
            ]
        }
        if count == 7 {
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: unit, height: unit * 2)),
                Tile(index: 1, rect: CGRect(x: unit, y: 0, width: unit, height: unit)),
                Tile(index: 2, rect: CGRect(x: unit * 2, y: 0, width: unit, height: unit)),
                Tile(index: 3, rect: CGRect(x: unit, y: unit, width: unit * 2, height: unit)),
                Tile(index: 4, rect: CGRect(x: 0, y: unit * 2, width: unit, height: unit)),
                Tile(index: 5, rect: CGRect(x: unit, y: unit * 2, width: unit, height: unit)),
                Tile(index: 6, rect: CGRect(x: unit * 2, y: unit * 2, width: unit, height: unit))
            ]
        }
        if count == 8 {
            return [
                Tile(index: 0, rect: CGRect(x: 0, y: 0, width: unit * 2, height: unit)),
                Tile(index: 1, rect: CGRect(x: unit * 2, y: 0, width: unit, height: unit)),
                Tile(index: 2, rect: CGRect(x: 0, y: unit, width: unit, height: unit)),
                Tile(index: 3, rect: CGRect(x: unit, y: unit, width: unit, height: unit)),
                Tile(index: 4, rect: CGRect(x: unit * 2, y: unit, width: unit, height: unit)),
                Tile(index: 5, rect: CGRect(x: 0, y: unit * 2, width: unit, height: unit)),
                Tile(index: 6, rect: CGRect(x: unit, y: unit * 2, width: unit, height: unit)),
                Tile(index: 7, rect: CGRect(x: unit * 2, y: unit * 2, width: unit, height: unit))
            ]
        }
        return (0..<9).map { index in
            Tile(index: index, rect: CGRect(x: CGFloat(index % 3) * unit, y: CGFloat(index / 3) * unit, width: unit, height: unit))
        }
    }
}

private struct WidgetDateOverlay: View {
    let date: Date
    let width: CGFloat
    let height: CGFloat
    @Environment(\.locale) private var locale

    private var dateBlockWidth: CGFloat { width / 2 }
    private var yearFontSize: CGFloat { min(68, max(14, min(dateBlockWidth * 0.34, height * 0.26))) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.56), .black.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )

            Text(date.formatted(.dateTime.year().locale(locale)))
                .font(.system(size: yearFontSize, weight: .regular, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: dateBlockWidth, height: height, alignment: .center)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

@main
struct HetkiaWidgetBundle: WidgetBundle {
    var body: some Widget { OnThisDayWidget() }
}

private struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Hetkia.OnThisDay", provider: HetkiaWidgetProvider()) { entry in
            HetkiaWidgetView(entry: entry)
        }
        .configurationDisplayName("timeline.on-this-day")
        .description("timeline.tagline")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}
