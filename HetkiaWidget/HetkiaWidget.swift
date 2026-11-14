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
    let totalPhotoCount: Int
    let anniversaryYearCount: Int
    let calendarMonth: Int
    let calendarDay: Int
}

private struct WidgetIndexSummary: Codable, Equatable {
    let totalPhotoCount: Int
    let anniversaryYearCount: Int
    let heroAssetIdentifier: String?
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
    let totalPhotoCount: Int?
    let anniversaryYearCount: Int?
    let heroAssetIdentifier: String?
    let contentFingerprint: String

    var summary: WidgetIndexSummary {
        WidgetIndexSummary(
            totalPhotoCount: totalPhotoCount ?? 0,
            anniversaryYearCount: anniversaryYearCount ?? entries.count,
            heroAssetIdentifier: heroAssetIdentifier
        )
    }
}

private struct PublishQuickEntry: TimelineEntry {
    let date: Date
    let heroImageData: Data?
    let totalPhotoCount: Int
    let anniversaryYearCount: Int
    let calendarMonth: Int
    let calendarDay: Int
    let hasPhotoAccess: Bool
}

private enum WidgetSnapshotStore {
    private static let schemaVersion = 2
    private static let fileName = "on-this-day-widget-index.json"
    private static let appGroup = "group.com.hetkia.app"
    private static let settingsDefaults = UserDefaults(suiteName: appGroup)

    @MainActor
    static func read() -> WidgetIndexSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetIndexSnapshot.self, from: data),
              isCurrent(snapshot),
              snapshot.contentFingerprint == fingerprint(snapshot) else {
            return nil
        }
        recordWidgetFingerprint(snapshot.contentFingerprint)
        return snapshot
    }

    @MainActor
    static func groups(from snapshot: WidgetIndexSnapshot) -> [(date: Date, assets: [PHAsset])]? {
        let identifiers = snapshot.entries.map(\.assetIdentifier)
        guard !identifiers.isEmpty else { return [] }

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

        return snapshot.entries.compactMap { item in
            guard let asset = assetsByIdentifier[item.assetIdentifier] else { return nil }
            return (date: item.date, assets: [asset])
        }
    }

    @MainActor
    private static func isCurrent(_ snapshot: WidgetIndexSnapshot) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: .now)
        let includesScreenshots = settingsDefaults?.bool(forKey: "hetkia.includeScreenshotsAndScreenRecordings") ?? false
        return snapshot.schemaVersion == schemaVersion
            && snapshot.year == parts.year
            && snapshot.month == parts.month
            && snapshot.day == parts.day
            && snapshot.timeZoneIdentifier == calendar.timeZone.identifier
            && snapshot.includesScreenshotsAndScreenRecordings == includesScreenshots
    }

    static func fingerprint(_ snapshot: WidgetIndexSnapshot) -> String {
        fingerprint(for: snapshot.entries, summary: snapshot.summary)
    }

    private static func fingerprint(for entries: [WidgetIndexSnapshot.Item], summary: WidgetIndexSummary) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: .now)
        let includesScreenshots = settingsDefaults?.bool(forKey: "hetkia.includeScreenshotsAndScreenRecordings") ?? false
        let summaryLine = "photos:\(summary.totalPhotoCount):years:\(summary.anniversaryYearCount):hero:\(summary.heroAssetIdentifier ?? "none")"
        let canonical = ([
            "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)",
            calendar.timeZone.identifier,
            includesScreenshots ? "1" : "0",
            summaryLine
        ] + entries.sorted { $0.date > $1.date }.map { item in
            let modification = item.assetModificationDate.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "none"
            return "\(calendar.component(.year, from: item.date)):\(item.assetIdentifier):\(modification)"
        }).joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    static func writeFallback(from groups: [(date: Date, assets: [PHAsset])]) {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: .now)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName) else { return }
        let items = groups.compactMap { group -> WidgetIndexSnapshot.Item? in
            guard let first = group.assets.first else { return nil }
            return WidgetIndexSnapshot.Item(
                date: group.date,
                assetIdentifier: first.localIdentifier,
                assetModificationDate: first.modificationDate
            )
        }.sorted { $0.date > $1.date }
        let includesScreenshots = settingsDefaults?.bool(forKey: "hetkia.includeScreenshotsAndScreenRecordings") ?? false
        let currentYear = year
        let heroID = items.first { calendar.component(.year, from: $0.date) == currentYear }?.assetIdentifier
            ?? items.first?.assetIdentifier
        let summary = WidgetIndexSummary(
            totalPhotoCount: items.count,
            anniversaryYearCount: items.count,
            heroAssetIdentifier: heroID
        )
        let fingerprint = fingerprint(for: items, summary: summary)
        let snapshot = WidgetIndexSnapshot(
            schemaVersion: schemaVersion,
            year: year,
            month: month,
            day: day,
            timeZoneIdentifier: calendar.timeZone.identifier,
            includesScreenshotsAndScreenRecordings: includesScreenshots,
            refreshedAt: .now,
            entries: items,
            totalPhotoCount: summary.totalPhotoCount,
            anniversaryYearCount: summary.anniversaryYearCount,
            heroAssetIdentifier: summary.heroAssetIdentifier,
            contentFingerprint: fingerprint
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        recordWidgetFingerprint(fingerprint)
    }

    private static func recordWidgetFingerprint(_ fingerprint: String) {
        settingsDefaults?.set(fingerprint, forKey: "hetkia.widget.lastReloadedFingerprint")
    }
}

private enum WidgetPhotoKitRenderer {
    @MainActor
    static func preview(for asset: PHAsset, targetSize: CGFloat) async -> CGImage? {
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

    static func jpegData(from image: CGImage) -> Data? {
        #if os(macOS)
        NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.76])
        #else
        UIImage(cgImage: image).jpegData(compressionQuality: 0.76)
        #endif
    }
}

private struct HetkiaWidgetProvider: TimelineProvider {
    private let settingsDefaults = UserDefaults(suiteName: "group.com.hetkia.app")

    func placeholder(in context: Context) -> HetkiaWidgetEntry {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.month, .day], from: .now)
        return HetkiaWidgetEntry(
            date: .now,
            memories: [],
            hasPhotoAccess: false,
            totalPhotoCount: 0,
            anniversaryYearCount: 0,
            calendarMonth: parts.month ?? 1,
            calendarDay: parts.day ?? 1
        )
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
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.month, .day], from: .now)
        let defaultMonth = parts.month ?? 1
        let defaultDay = parts.day ?? 1

        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            return HetkiaWidgetEntry(
                date: .now,
                memories: [],
                hasPhotoAccess: false,
                totalPhotoCount: 0,
                anniversaryYearCount: 0,
                calendarMonth: defaultMonth,
                calendarDay: defaultDay
            )
        }

        let sharedSnapshot = WidgetSnapshotStore.read()
        let groups: [(date: Date, assets: [PHAsset])]
        if let snapshot = sharedSnapshot, let cachedGroups = WidgetSnapshotStore.groups(from: snapshot) {
            groups = cachedGroups
        } else {
            groups = matchingPhotoGroups()
            WidgetSnapshotStore.writeFallback(from: groups)
        }

        let summary = sharedSnapshot?.summary
        let calendarMonth = sharedSnapshot?.month ?? defaultMonth
        let calendarDay = sharedSnapshot?.day ?? defaultDay
        // Keep up to nine anniversary memories. The fixed widget canvas has
        // dedicated layouts for every count, including the two-photo inset.
        // Groups are reversed so the collage reads oldest anniversary to today.
        let availableCount = groups.count
        let selectedCount = min(9, availableCount)
        let chosenGroups = Array(groups.prefix(selectedCount).reversed())
        var memories: [WidgetMemory] = []
        for group in chosenGroups {
            guard let firstAsset = group.assets.first,
                  let image = await WidgetPhotoKitRenderer.preview(for: firstAsset, targetSize: imageSize),
                  let data = WidgetPhotoKitRenderer.jpegData(from: image) else { continue }
            memories.append(WidgetMemory(date: group.date, imageData: data))
        }
        return HetkiaWidgetEntry(
            date: .now,
            memories: memories,
            hasPhotoAccess: true,
            totalPhotoCount: summary?.totalPhotoCount ?? memories.count,
            anniversaryYearCount: summary?.anniversaryYearCount ?? memories.count,
            calendarMonth: calendarMonth,
            calendarDay: calendarDay
        )
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

}

private struct WidgetFrostedCapsule<Content: View>: View {
    var fillOpacity: CGFloat = 0.65
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(fillOpacity)
                    }
            }
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
    }
}

private struct WidgetFrostedPanel<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var fillOpacity: CGFloat = 0.65
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(fillOpacity)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            )
    }
}

private struct WidgetGlassPublishButton: View {
    let titleKey: LocalizedStringKey
    let symbol: String
    let destination: String
    var expands: Bool = false
    var compact: Bool = false

    var body: some View {
        Link(destination: URL(string: destination)!) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                Text(titleKey)
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 0 : 8)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: compact ? 26 : nil)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.1))
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.55)
                    }
            }
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.32), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct WidgetDashboardLargeHeader: View {
    let month: Int
    let day: Int

    private var dateSubtitle: String {
        String(
            format: Bundle.main.localizedString(forKey: "widget.dashboard.date", value: nil, table: nil),
            month,
            day
        )
    }

    var body: some View {
        WidgetFrostedCapsule(fillOpacity: 0.65) {
            HStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 11, weight: .semibold))
                Text("widget.dashboard.brand")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("|")
                    .opacity(0.85)
                Text(verbatim: dateSubtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }
}

private struct WidgetDashboardSmallTitleRow: View {
    private var titleText: String {
        let brand = Bundle.main.localizedString(forKey: "widget.dashboard.brand", value: nil, table: nil)
        let album = Bundle.main.localizedString(forKey: "widget.dashboard.album", value: nil, table: nil)
        return "\(brand) | \(album)"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.caption2.weight(.semibold))
            Text(verbatim: titleText)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
    }
}

private struct WidgetStatsInlineRow: View {
    let totalPhotoCount: Int
    let anniversaryYearCount: Int
    var emphasizeNumbers: Bool
    var showsChevron: Bool

    private var photosUnit: String {
        Bundle.main.localizedString(forKey: "widget.dashboard.photos-unit", value: nil, table: nil)
    }

    private var yearsUnit: String {
        Bundle.main.localizedString(forKey: "widget.dashboard.years-unit", value: nil, table: nil)
    }

    private var countFontSize: CGFloat { emphasizeNumbers ? 14 : 11 }
    private var unitFontSize: CGFloat { emphasizeNumbers ? 9 : 9 }

    var body: some View {
        HStack(spacing: 6) {
            metricGroup(icon: "photo.on.rectangle", count: totalPhotoCount, unit: photosUnit)
            Text("|")
                .font(.system(size: unitFontSize, weight: .medium))
                .opacity(0.7)
            metricGroup(icon: "clock.arrow.circlepath", count: anniversaryYearCount, unit: yearsUnit)
            if showsChevron {
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
        .lineLimit(1)
        .minimumScaleFactor(0.45)
        .allowsTightening(true)
    }

    private func metricGroup(icon: String, count: Int, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: unitFontSize, weight: .semibold))
            Text("\(count)")
                .font(.system(size: countFontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: unit)
                .font(.system(size: unitFontSize, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct WidgetSmallBottomActions: View {
    var body: some View {
        VStack(spacing: 4) {
            WidgetGlassPublishButton(
                titleKey: "detail.share.post-moment",
                symbol: "text.bubble",
                destination: "hetkia://publish/moment",
                expands: true,
                compact: true
            )
            WidgetGlassPublishButton(
                titleKey: "detail.share.upload-journal",
                symbol: "square.and.pencil",
                destination: "hetkia://publish/essay",
                expands: true,
                compact: true
            )
        }
    }
}

private struct WidgetDashboardSmallLayout: View {
    let totalPhotoCount: Int
    let anniversaryYearCount: Int

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                WidgetDashboardSmallTitleRow()
                WidgetStatsInlineRow(
                    totalPhotoCount: totalPhotoCount,
                    anniversaryYearCount: anniversaryYearCount,
                    emphasizeNumbers: true,
                    showsChevron: true
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WidgetSmallBottomActions()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WidgetDashboardLargeFooter: View {
    let totalPhotoCount: Int
    let anniversaryYearCount: Int

    var body: some View {
        WidgetFrostedPanel(cornerRadius: 18, fillOpacity: 0.65) {
            HStack(alignment: .center, spacing: 6) {
                WidgetStatsInlineRow(
                    totalPhotoCount: totalPhotoCount,
                    anniversaryYearCount: anniversaryYearCount,
                    emphasizeNumbers: false,
                    showsChevron: false
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                HStack(spacing: 6) {
                    WidgetGlassPublishButton(
                        titleKey: "detail.share.post-moment",
                        symbol: "text.bubble",
                        destination: "hetkia://publish/moment",
                        compact: true
                    )
                    WidgetGlassPublishButton(
                        titleKey: "detail.share.upload-journal",
                        symbol: "square.and.pencil",
                        destination: "hetkia://publish/essay",
                        compact: true
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
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
                largeDashboard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var largeDashboard: some View {
        ZStack(alignment: .topLeading) {
            if entry.memories.isEmpty {
                emptyState
            } else {
                WidgetMemoryCollage(memories: entry.memories, rounded: false, showsDates: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                WidgetDashboardLargeHeader(month: entry.calendarMonth, day: entry.calendarDay)
                    .padding(10)

                Spacer(minLength: 0)

                WidgetDashboardLargeFooter(
                    totalPhotoCount: entry.totalPhotoCount,
                    anniversaryYearCount: entry.anniversaryYearCount
                )
                .padding(10)
            }
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

private struct PublishQuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> PublishQuickEntry {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.month, .day], from: .now)
        return PublishQuickEntry(
            date: .now,
            heroImageData: nil,
            totalPhotoCount: 0,
            anniversaryYearCount: 0,
            calendarMonth: parts.month ?? 1,
            calendarDay: parts.day ?? 1,
            hasPhotoAccess: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PublishQuickEntry) -> Void) {
        Task { completion(await loadEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PublishQuickEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let refresh = Calendar.autoupdatingCurrent.nextDate(
                after: .now,
                matching: DateComponents(hour: 0, minute: 0),
                matchingPolicy: .nextTime
            ) ?? .now.addingTimeInterval(86_400)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    @MainActor
    private func loadEntry() async -> PublishQuickEntry {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.month, .day], from: .now)
        let defaultMonth = parts.month ?? 1
        let defaultDay = parts.day ?? 1

        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            return PublishQuickEntry(
                date: .now,
                heroImageData: nil,
                totalPhotoCount: 0,
                anniversaryYearCount: 0,
                calendarMonth: defaultMonth,
                calendarDay: defaultDay,
                hasPhotoAccess: false
            )
        }

        guard let snapshot = WidgetSnapshotStore.read() else {
            return PublishQuickEntry(
                date: .now,
                heroImageData: nil,
                totalPhotoCount: 0,
                anniversaryYearCount: 0,
                calendarMonth: defaultMonth,
                calendarDay: defaultDay,
                hasPhotoAccess: true
            )
        }

        var heroData: Data?
        if let heroID = snapshot.summary.heroAssetIdentifier {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [heroID], options: nil)
            if let asset = fetched.firstObject,
               let image = await WidgetPhotoKitRenderer.preview(for: asset, targetSize: 480),
               let data = WidgetPhotoKitRenderer.jpegData(from: image) {
                heroData = data
            }
        }

        return PublishQuickEntry(
            date: .now,
            heroImageData: heroData,
            totalPhotoCount: snapshot.summary.totalPhotoCount,
            anniversaryYearCount: snapshot.summary.anniversaryYearCount,
            calendarMonth: snapshot.month,
            calendarDay: snapshot.day,
            hasPhotoAccess: true
        )
    }
}

private struct PublishQuickWidgetView: View {
    let entry: PublishQuickEntry

    var body: some View {
        WidgetDashboardSmallLayout(
            totalPhotoCount: entry.totalPhotoCount,
            anniversaryYearCount: entry.anniversaryYearCount
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            ZStack {
                widgetBackground
                LinearGradient(
                    colors: [.black.opacity(0.25), .clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if let data = entry.heroImageData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                Color(red: 0.22, green: 0.24, blue: 0.28)
                Image("Unknown")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.45)
            }
        }
    }
}

private struct PublishQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Hetkia.PublishQuick", provider: PublishQuickProvider()) { entry in
            PublishQuickWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.publish.displayName")
        .description("widget.publish.description")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct HetkiaWidgetBundle: WidgetBundle {
    var body: some Widget {
        OnThisDayWidget()
        PublishQuickWidget()
    }
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
