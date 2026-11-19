import SwiftUI
import SwiftData

struct SavedJournalsRootContent: View {
    let savedRecords: [JournalRecord]
    let bottomInset: CGFloat
    let onSelectRecord: (JournalRecord) -> Void
    @Environment(\.locale) private var locale

    private var dayEntries: [JournalRecord] {
        SavedJournalIndex.meaningfulRecords(from: savedRecords)
    }

    var body: some View {
        Group {
            if dayEntries.isEmpty {
                ContentUnavailableView("settings.saved-journals.empty", systemImage: "book.closed")
                    .padding(.top, 60)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(dayEntries, id: \.persistentModelID) { record in
                        SavedJournalEntryPreview(
                            record: record,
                            locale: locale,
                            onOpen: { onSelectRecord(record) }
                        )
                        .id(SavedJournalScrollAnchorID.day(record.dayKey))
                        .savedJournalReportsScrollAnchor(id: SavedJournalScrollAnchorID.day(record.dayKey))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, bottomInset)
    }
}

/// Settings / previews: full-screen saved journals with system navigation chrome.
struct SavedJournalsView: View {
    @Query(sort: \JournalRecord.localDay, order: .reverse) private var savedRecords: [JournalRecord]

    var body: some View {
        ScrollView {
            SavedJournalsRootContent(savedRecords: savedRecords, bottomInset: 28) { _ in }
        }
        .background(HetkiaPalette.paper.ignoresSafeArea())
        .navigationTitle(Text("settings.saved-journals"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct SavedJournalEntryPreview: View {
    let record: JournalRecord
    let locale: Locale
    let onOpen: () -> Void

    private var photos: [JournalPhotoRecord] {
        JournalPhotoSelection.displayPhotos(from: record.photos)
    }

    private var dateTitle: String {
        record.localDay.formatted(.dateTime.year().month(.wide).day().locale(locale))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if photos.isEmpty {
                Button(action: onOpen) {
                    HetkiaPalette.paper
                        .frame(height: 160)
                        .overlay {
                            Image(systemName: "book.closed")
                                .foregroundStyle(HetkiaPalette.secondaryInk)
                        }
                }
                .buttonStyle(.plain)
            } else {
                SavedJournalPersistedMosaicGrid(
                    photos: photos,
                    onPhotoSelected: { _ in onOpen() },
                    onShowMore: onOpen
                )
            }
            SavedJournalsBottomScrim()
            SavedJournalsOverlayCaption(title: dateTitle)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(Text(dateTitle))
    }
}

struct SavedJournalPersistedMosaicGrid: View {
    let photos: [JournalPhotoRecord]
    let onPhotoSelected: (Int) -> Void
    let onShowMore: () -> Void

    private let gap: CGFloat = 5
    private var layoutTileCount: Int { PhotoMosaicPreviewLimits.layoutTileCount(totalPhotoCount: photos.count) }
    private var showsMore: Bool { PhotoMosaicPreviewLimits.showsMoreIndicator(totalPhotoCount: photos.count) }
    private var heightRatio: CGFloat {
        guard layoutTileCount > 0 else { return 1 }
        return PhotoMosaicLayout.height(width: 1_000, count: layoutTileCount, gap: gap) / 1_000
    }

    var body: some View {
        GeometryReader { geometry in
            let tiles = PhotoMosaicLayout.tiles(width: geometry.size.width, count: layoutTileCount, gap: gap)
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    if showsMore, tile.index == layoutTileCount - 1 {
                        Button(action: onShowMore) {
                            PhotoMosaicMoreTile(
                                hiddenCount: PhotoMosaicPreviewLimits.hiddenPhotoCount(totalPhotoCount: photos.count),
                                cornerRadius: 9
                            )
                            .frame(width: tile.rect.width, height: tile.rect.height)
                        }
                        .buttonStyle(.plain)
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                    } else {
                        Button {
                            onPhotoSelected(tile.index)
                        } label: {
                            PersistedJournalThumbnail(
                                photo: photos[tile.index],
                                width: tile.rect.width,
                                height: tile.rect.height,
                                cornerRadius: 9
                            )
                            .frame(width: tile.rect.width, height: tile.rect.height)
                        }
                        .buttonStyle(.plain)
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .aspectRatio(1 / heightRatio, contentMode: .fit)
    }
}

struct SavedJournalCard: View {
    let record: JournalRecord
    let locale: Locale

    private var cover: JournalPhotoRecord? {
        JournalPhotoSelection.selected(from: record.photos).first
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let cover {
                    PersistedJournalThumbnail(
                        photo: cover,
                        width: geometry.size.width,
                        height: geometry.size.height,
                        cornerRadius: 0
                    )
                } else {
                    HetkiaPalette.secondaryInk
                        .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.8)))
                }

                LinearGradient(
                    colors: [.black.opacity(0.56), .black.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 5) {
                    Text(record.localDay.formatted(.dateTime.year().month(.wide).day().locale(locale)))
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(String(format: HetkiaSystemLanguage.localizedString("timeline.photo-count", comment: "Saved journal photo count"), record.photos.count))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                .padding(12)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

/// Displays only the JPEG saved in Application Support; it never asks PhotoKit for an asset.
struct PersistedJournalThumbnail: View {
    let photo: JournalPhotoRecord
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 9

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                HetkiaPalette.paper.overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(HetkiaPalette.secondaryInk.opacity(0.7))
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: "\(photo.id.uuidString)-\(Int(width.rounded()))x\(Int(height.rounded()))") {
            guard width > 0, height > 0 else { return }
            image = await PhotoAssetResolver.thumbnailImage(
                relativePath: photo.thumbnailRelativePath,
                targetSize: CGSize(width: width * 2, height: height * 2)
            )
        }
    }
}
