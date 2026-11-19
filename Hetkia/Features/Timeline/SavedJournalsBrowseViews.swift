import SwiftUI
import SwiftData

enum SavedJournalsBrowseMode: Equatable {
    case all
    case year
    case month
}

struct SavedJournalYearMonth: Hashable, Identifiable {
    let year: Int
    let month: Int
    var id: String { "\(year)-\(month)" }
}

struct SavedJournalMonthDayItem: Identifiable {
    let record: JournalRecord
    let photo: JournalPhotoRecord
    var id: String { record.dayKey }
}

enum SavedJournalIndex {
    static func meaningfulRecords(from savedRecords: [JournalRecord]) -> [JournalRecord] {
        let perDay = Dictionary(grouping: savedRecords, by: \.dayKey).values.compactMap { records in
            records.max { $0.updatedAt < $1.updatedAt }
        }
        return perDay.filter { record in
            !record.title.isEmpty || !record.bodyText.isEmpty || record.aiDraftBody?.isEmpty == false
                || !record.messagePosts.isEmpty || !record.photos.isEmpty
        }
        .sorted { $0.localDay > $1.localDay }
    }

    static func years(from records: [JournalRecord]) -> [Int] {
        Set(records.map { Calendar.autoupdatingCurrent.component(.year, from: $0.localDay) }).sorted(by: >)
    }

    static func records(inYear year: Int, from records: [JournalRecord]) -> [JournalRecord] {
        records.filter { Calendar.autoupdatingCurrent.component(.year, from: $0.localDay) == year }
    }

    static func records(inYear year: Int, month: Int, from records: [JournalRecord]) -> [JournalRecord] {
        records.filter {
            let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: $0.localDay)
            return parts.year == year && parts.month == month
        }
    }

    static func monthsWithEntries(inYear year: Int, from records: [JournalRecord]) -> [Int] {
        let months = records
            .filter { Calendar.autoupdatingCurrent.component(.year, from: $0.localDay) == year }
            .map { Calendar.autoupdatingCurrent.component(.month, from: $0.localDay) }
        return Array(Set(months)).sorted(by: >)
    }

    static func monthsWithPhotoDays(inYear year: Int, from records: [JournalRecord]) -> [Int] {
        monthsWithEntries(inYear: year, from: records).filter { month in
            !monthDayItems(year: year, month: month, from: records).isEmpty
        }
    }

    static func latestMonthWithEntries(from records: [JournalRecord]) -> (year: Int, month: Int)? {
        guard let latest = records.first else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let year = calendar.component(.year, from: latest.localDay)
        let month = calendar.component(.month, from: latest.localDay)
        return (year, month)
    }

    static func coverPhoto(for record: JournalRecord) -> JournalPhotoRecord? {
        representativePhoto(for: record)
    }

    /// One thumbnail per saved day: geotagged and everyday media ahead of screenshots/recordings.
    static func representativePhoto(for record: JournalRecord) -> JournalPhotoRecord? {
        let ordered = JournalPhotoSelection.displayPhotos(from: record.photos)
        return ordered.sorted { lhs, rhs in
            let lhsHasLocation = lhs.latitude != nil && lhs.longitude != nil
            let rhsHasLocation = rhs.latitude != nil && rhs.longitude != nil
            if lhsHasLocation != rhsHasLocation { return lhsHasLocation && !rhsHasLocation }
            if lhs.isPriorityPhoto != rhs.isPriorityPhoto { return lhs.isPriorityPhoto && !rhs.isPriorityPhoto }
            return (lhs.capturedAt ?? .distantPast) < (rhs.capturedAt ?? .distantPast)
        }.first
    }

    static func representativeRecord(inYear year: Int, from records: [JournalRecord]) -> JournalRecord? {
        Self.records(inYear: year, from: records)
            .sorted { $0.localDay > $1.localDay }
            .first { representativePhoto(for: $0) != nil }
    }

    static func monthDayItems(year: Int, month: Int, from records: [JournalRecord]) -> [SavedJournalMonthDayItem] {
        Self.records(inYear: year, month: month, from: records)
            .sorted { $0.localDay < $1.localDay }
            .compactMap { record in
                guard let photo = representativePhoto(for: record) else { return nil }
                return SavedJournalMonthDayItem(record: record, photo: photo)
            }
    }

    /// All year-month buckets that have at least one day with a preview photo (newest first).
    static func allMonthsWithPhotoDays(from records: [JournalRecord]) -> [SavedJournalYearMonth] {
        let calendar = Calendar.autoupdatingCurrent
        let keys = Set(records.map { record in
            let parts = calendar.dateComponents([.year, .month], from: record.localDay)
            return (parts.year ?? 0) * 100 + (parts.month ?? 0)
        })
        return keys.sorted(by: >).compactMap { key in
            let year = key / 100
            let month = key % 100
            guard year > 0, month > 0 else { return nil }
            guard !monthDayItems(year: year, month: month, from: records).isEmpty else { return nil }
            return SavedJournalYearMonth(year: year, month: month)
        }
    }
}

struct SavedJournalsYearsBrowseView: View {
    let records: [JournalRecord]
    let onSelectYear: (Int) -> Void

    private var years: [Int] { SavedJournalIndex.years(from: records) }

    var body: some View {
        if years.isEmpty {
            ContentUnavailableView("settings.saved-journals.empty", systemImage: "book.closed")
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 14) {
                ForEach(years, id: \.self) { year in
                    let yearRecords = SavedJournalIndex.records(inYear: year, from: records)
                    let representative = SavedJournalIndex.representativeRecord(inYear: year, from: records)
                    Button { onSelectYear(year) } label: {
                        SavedJournalsYearTile(
                            year: year,
                            record: representative,
                            count: yearRecords.count
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .id(SavedJournalScrollAnchorID.year(year))
                    .savedJournalReportsScrollAnchor(id: SavedJournalScrollAnchorID.year(year))
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Full month browse: every month in history as one day-mosaic block (newest first).
struct SavedJournalsAllMonthsBrowseView: View {
    let records: [JournalRecord]
    let onSelectRecord: (JournalRecord) -> Void

    @Environment(\.locale) private var locale

    private var months: [SavedJournalYearMonth] {
        SavedJournalIndex.allMonthsWithPhotoDays(from: records)
    }

    var body: some View {
        Group {
            if months.isEmpty {
                ContentUnavailableView("settings.saved-journals.empty", systemImage: "book.closed")
                    .padding(.top, 20)
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(months) { bucket in
                        SavedJournalsMonthDayMosaicSection(
                            year: bucket.year,
                            month: bucket.month,
                            items: SavedJournalIndex.monthDayItems(year: bucket.year, month: bucket.month, from: records),
                            locale: locale,
                            onSelectRecord: onSelectRecord
                        )
                        .id(SavedJournalScrollAnchorID.month(year: bucket.year, month: bucket.month))
                        .savedJournalReportsScrollAnchor(id: SavedJournalScrollAnchorID.month(year: bucket.year, month: bucket.month))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }
}

struct SavedJournalsMonthDayMosaicSection: View {
    let year: Int
    let month: Int
    let items: [SavedJournalMonthDayItem]
    let locale: Locale
    let onSelectRecord: (JournalRecord) -> Void

    private var monthDate: Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) ?? .now
    }

    private var monthTitle: String {
        monthDate.formatted(.dateTime.year().month(.wide).locale(locale))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SavedJournalsDayMosaicGrid(items: items, onSelectRecord: onSelectRecord)
            SavedJournalsBottomScrim()
            SavedJournalsOverlayCaption(
                title: monthTitle,
                subtitle: String(format: HetkiaSystemLanguage.localizedString("timeline.entry-count", comment: ""), items.count)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(Text(monthTitle))
    }
}

struct SavedJournalsDayMosaicGrid: View {
    let items: [SavedJournalMonthDayItem]
    let onSelectRecord: (JournalRecord) -> Void

    private let gap: CGFloat = 3

    private var heightRatio: CGFloat {
        PhotoMosaicLayout.height(width: 1_000, count: items.count, gap: gap) / 1_000
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let tiles = PhotoMosaicLayout.tiles(width: width, count: items.count, gap: gap)
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    let item = items[tile.index]
                    let day = Calendar.autoupdatingCurrent.component(.day, from: item.record.localDay)
                    Button {
                        onSelectRecord(item.record)
                    } label: {
                        ZStack(alignment: .topLeading) {
                            PersistedJournalThumbnail(
                                photo: item.photo,
                                width: tile.rect.width,
                                height: tile.rect.height,
                                cornerRadius: 6
                            )
                            Text(verbatim: "\(day)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                                .padding(6)
                        }
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .position(x: tile.rect.midX, y: tile.rect.midY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .aspectRatio(1 / heightRatio, contentMode: .fit)
    }
}

struct SavedJournalsYearTile: View {
    let year: Int
    let record: JournalRecord?
    let count: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let record, let cover = SavedJournalIndex.coverPhoto(for: record) {
                GeometryReader { geometry in
                    PersistedJournalThumbnail(
                        photo: cover,
                        width: geometry.size.width,
                        height: geometry.size.height,
                        cornerRadius: 0
                    )
                }
            } else {
                HetkiaPalette.paper
                    .overlay(Image(systemName: "book.closed").foregroundStyle(HetkiaPalette.secondaryInk))
            }
            SavedJournalsBottomScrim()
            SavedJournalsOverlayCaption(
                title: String(year),
                subtitle: String(format: HetkiaSystemLanguage.localizedString("timeline.entry-count", comment: ""), count)
            )
        }
        .frame(height: 220)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(Text(String(year)))
    }
}
