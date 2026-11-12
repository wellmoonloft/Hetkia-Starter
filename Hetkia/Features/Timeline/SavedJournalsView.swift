import SwiftUI
import SwiftData

struct SavedJournalsRootContent: View {
    let savedRecords: [JournalRecord]
    let bottomInset: CGFloat
    let onSelectRecord: (JournalRecord) -> Void
    @Environment(\.locale) private var locale

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var monthGroups: [SavedJournalMonthGroup] {
        let perDay = Dictionary(grouping: savedRecords, by: \.dayKey).values.compactMap { records in
            records.max { $0.updatedAt < $1.updatedAt }
        }
        let meaningful = perDay.filter { record in
            !record.title.isEmpty || !record.bodyText.isEmpty || record.aiDraftBody?.isEmpty == false
                || !record.messagePosts.isEmpty || !record.photos.isEmpty
        }
        let grouped = Dictionary(grouping: meaningful) { record in
            let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: record.localDay)
            return (parts.year ?? 0) * 100 + (parts.month ?? 0)
        }
        return grouped.keys.sorted(by: >).compactMap { key in
            guard let entries = grouped[key]?.sorted(by: { $0.localDay > $1.localDay }),
                  let first = entries.first else { return nil }
            return SavedJournalMonthGroup(id: key, date: first.localDay, entries: entries)
        }
    }

    var body: some View {
        Group {
            if monthGroups.isEmpty {
                ContentUnavailableView("settings.saved-journals.empty", systemImage: "book.closed")
                    .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(monthGroups) { group in
                        VStack(alignment: .leading, spacing: 11) {
                            Text(group.date.formatted(.dateTime.year().month(.wide).locale(locale)))
                                .font(.system(size: 16, weight: .medium, design: .serif))
                                .foregroundStyle(HetkiaPalette.secondaryInk)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(group.entries, id: \.persistentModelID) { record in
                                    Button {
                                        onSelectRecord(record)
                                    } label: {
                                        SavedJournalCard(record: record, locale: locale)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
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

private struct SavedJournalMonthGroup: Identifiable {
    let id: Int
    let date: Date
    let entries: [JournalRecord]
}

private struct SavedJournalCard: View {
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
