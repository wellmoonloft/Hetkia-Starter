import SwiftUI
import SwiftData

enum SavedJournalsBrowseMode: Equatable {
    case all
    case year
    case month
}

enum SavedJournalsMonthScope: Equatable {
    case monthsInYear(Int)
    case entries(year: Int, month: Int)
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

    static func latestMonthWithEntries(from records: [JournalRecord]) -> (year: Int, month: Int)? {
        guard let latest = records.first else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let year = calendar.component(.year, from: latest.localDay)
        let month = calendar.component(.month, from: latest.localDay)
        return (year, month)
    }

    static func coverPhoto(for record: JournalRecord) -> JournalPhotoRecord? {
        JournalPhotoSelection.selected(from: record.photos).first
    }
}

struct SavedJournalsYearsBrowseView: View {
    let records: [JournalRecord]
    let onSelectYear: (Int) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var years: [Int] { SavedJournalIndex.years(from: records) }

    var body: some View {
        if years.isEmpty {
            ContentUnavailableView("settings.saved-journals.empty", systemImage: "book.closed")
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(years, id: \.self) { year in
                    let yearRecords = SavedJournalIndex.records(inYear: year, from: records)
                    Button { onSelectYear(year) } label: {
                        SavedJournalsYearTile(year: year, record: yearRecords.first, count: yearRecords.count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}

struct SavedJournalsMonthsInYearWaterfallView: View {
    let year: Int
    let records: [JournalRecord]
    let onSelectMonth: (Int, Int) -> Void

    @Environment(\.locale) private var locale
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var months: [Int] { SavedJournalIndex.monthsWithEntries(inYear: year, from: records) }

    var body: some View {
        Group {
            if months.isEmpty {
                ContentUnavailableView("settings.saved-journals.empty", systemImage: "book.closed")
                    .padding(.top, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(months, id: \.self) { month in
                        let monthRecords = SavedJournalIndex.records(inYear: year, month: month, from: records)
                        let monthDate = Calendar.autoupdatingCurrent.date(
                            from: DateComponents(year: year, month: month, day: 1, hour: 12)
                        ) ?? .now
                        Button { onSelectMonth(year, month) } label: {
                            SavedJournalsMonthBucketCard(
                                title: monthDate.formatted(.dateTime.year().month(.wide).locale(locale)),
                                record: monthRecords.first,
                                entryCount: monthRecords.count,
                                locale: locale
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }
}

struct SavedJournalsMonthEntriesWaterfallView: View {
    let year: Int
    let month: Int
    let records: [JournalRecord]
    let onSelectRecord: (JournalRecord) -> Void

    @Environment(\.locale) private var locale
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var monthRecords: [JournalRecord] {
        SavedJournalIndex.records(inYear: year, month: month, from: records)
            .sorted { $0.localDay > $1.localDay }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if monthRecords.isEmpty {
                ContentUnavailableView("calendar.no-entry", systemImage: "book.closed")
                    .padding(.top, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(monthRecords, id: \.persistentModelID) { record in
                        Button { onSelectRecord(record) } label: {
                            SavedJournalCard(record: record, locale: locale)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
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
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(year))
                    .font(.system(size: 15, weight: .medium, design: .serif))
                Text(String(format: HetkiaSystemLanguage.localizedString("timeline.entry-count", comment: ""), count))
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white)
            .padding(11)
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text(String(year)))
    }
}

struct SavedJournalsMonthBucketCard: View {
    let title: String
    let record: JournalRecord?
    let entryCount: Int
    let locale: Locale

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let record, let cover = SavedJournalIndex.coverPhoto(for: record) {
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
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(String(format: HetkiaSystemLanguage.localizedString("timeline.entry-count", comment: ""), entryCount))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}
