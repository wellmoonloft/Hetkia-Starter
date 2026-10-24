import SwiftUI
import WidgetKit
import Photos
import AVFoundation
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

private struct HetkiaWidgetProvider: TimelineProvider {
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

        let groups = matchingPhotoGroups()
        // The collage uses odd counts only. Walk from the oldest anniversary
        // toward today, with a five-memory cap to keep the layout readable.
        let availableCount = groups.count
        let selectedCount = min(5, availableCount.isMultiple(of: 2) ? max(0, availableCount - 1) : availableCount)
        let chosenGroups = Array(groups.reversed().prefix(selectedCount))
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
                assets.append(asset)
            }
            guard !assets.isEmpty else { continue }

            let count = assets.count
            let desired = count > 9 ? 9 : (count.isMultiple(of: 2) ? max(0, count - 1) : count)
            let selected = Array(assets.sorted {
                let lhsEveryday = !($0.mediaSubtypes.contains(.photoScreenshot) || $0.mediaSubtypes.contains(.videoScreenRecording))
                let rhsEveryday = !($1.mediaSubtypes.contains(.photoScreenshot) || $1.mediaSubtypes.contains(.videoScreenRecording))
                if lhsEveryday != rhsEveryday { return lhsEveryday && !rhsEveryday }
                return ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
            }.prefix(desired))
            groups.append((date: start, assets: selected))
        }
        return groups
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
    private let ink = Color(red: 0.25, green: 0.23, blue: 0.20)
    private let mutedInk = Color(red: 0.53, green: 0.49, blue: 0.42)

    private var isStandBySize: Bool { family == .systemSmall }

    var body: some View {
        Group {
            if isStandBySize {
                if entry.memories.isEmpty {
                    emptyState
                } else {
                    WidgetMemoryCollage(memories: entry.memories, rounded: false)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("timeline.on-this-day")
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                        Spacer(minLength: 4)
                        Text("brand.footer")
                            .font(.system(size: 12, weight: .regular, design: .serif))
                            .foregroundStyle(mutedInk)
                            .lineLimit(1)
                    }

                    if entry.memories.isEmpty {
                        emptyState
                    } else {
                        WidgetMemoryCollage(memories: entry.memories, rounded: true)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Color(red: 0.99, green: 0.98, blue: 0.95), for: .widget)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(mutedInk)
            Text(entry.hasPhotoAccess ? "photos.selection.empty" : "onboarding.photos.status.denied")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(mutedInk)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WidgetMemoryCollage: View {
    let memories: [WidgetMemory]
    let rounded: Bool
    private var gap: CGFloat { 5 }

    var body: some View {
        GeometryReader { geometry in
            if memories.count == 1, let memory = memories.first {
                linkedPhoto(memory, width: geometry.size.width, height: geometry.size.height)
            } else if memories.count == 2 {
                VStack(spacing: gap) {
                    ForEach(memories) { memory in
                        linkedPhoto(memory, width: geometry.size.width, height: (geometry.size.height - gap) / 2)
                    }
                }
            } else if memories.count == 3 {
                VStack(spacing: gap) {
                    if let hero = memories.first {
                        linkedPhoto(hero, width: geometry.size.width, height: geometry.size.height * 0.62)
                    }
                    HStack(spacing: gap) {
                        ForEach(Array(memories.dropFirst()), id: \.id) { memory in
                            linkedPhoto(memory, width: (geometry.size.width - gap) / 2, height: geometry.size.height * 0.36)
                        }
                    }
                }
            } else {
                VStack(spacing: gap) {
                    if let hero = memories.first {
                        linkedPhoto(hero, width: geometry.size.width, height: geometry.size.height * 0.48)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 2), spacing: gap) {
                        ForEach(Array(memories.dropFirst()), id: \.id) { memory in
                            linkedPhoto(memory, width: (geometry.size.width - gap) / 2, height: max(24, (geometry.size.height * 0.50 - gap) / 2))
                        }
                    }
                }
            }
        }
        .clipShape(rounded ? AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) : AnyShape(Rectangle()))
    }

    private func linkedPhoto(_ memory: WidgetMemory, width: CGFloat, height: CGFloat) -> some View {
        Link(destination: URL(string: "hetkia://onthisday/\(memory.id)")!) {
            photo(for: memory.imageData)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
        }
        .buttonStyle(.plain)
    }

    private func photo(for data: Data) -> Image {
        #if os(macOS)
        Image(nsImage: NSImage(data: data) ?? NSImage(size: .zero))
        #else
        Image(uiImage: UIImage(data: data) ?? UIImage())
        #endif
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
