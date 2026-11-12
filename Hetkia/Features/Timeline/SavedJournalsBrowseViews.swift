import SwiftUI
import SwiftData

enum SavedJournalsBrowseMode: Equatable {
    case all
    case year
    case month
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

    static func record(on date: Date, from records: [JournalRecord]) -> JournalRecord? {
        let key = PhotoDayGrouping.key(for: date)
        return records.first { $0.dayKey == key }
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
            VStack(alignment: .leading, spacing: 20) {
                ForEach(years, id: \.self) { year in
                    let yearRecords = SavedJournalIndex.records(inYear: year, from: records)
                    let coverRecord = yearRecords.first
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(year))
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .foregroundStyle(HetkiaPalette.ink)
                        LazyVGrid(columns: columns, spacing: 12) {
                            Button { onSelectYear(year) } label: {
                                yearTile(year: year, record: coverRecord, count: yearRecords.count)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func yearTile(year: Int, record: JournalRecord?, count: Int) -> some View {
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

struct SavedJournalsYearMonthsBrowseView: View {
    let year: Int
    let records: [JournalRecord]
    let onChangeYear: (Int) -> Void
    let onSelectMonth: (Int, Int) -> Void

    @Environment(\.locale) private var locale
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Button { onChangeYear(year - 1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                Spacer()
                Text(String(year))
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink)
                Spacer()
                Button { onChangeYear(year + 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(HetkiaPalette.secondaryInk)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...12, id: \.self) { month in
                    monthTile(month)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private func monthTile(_ month: Int) -> some View {
        let monthRecords = SavedJournalIndex.records(inYear: year, month: month, from: records)
        let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) ?? .now
        return Button {
            onSelectMonth(year, month)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(date.formatted(.dateTime.month(.wide).locale(locale)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HetkiaPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if let first = monthRecords.first, let cover = SavedJournalIndex.coverPhoto(for: first) {
                        GeometryReader { geometry in
                            PersistedJournalThumbnail(
                                photo: cover,
                                width: geometry.size.width,
                                height: geometry.size.height,
                                cornerRadius: 10
                            )
                        }
                        .overlay(alignment: .bottomLeading) {
                            Text(String(format: HetkiaSystemLanguage.localizedString("timeline.entry-count", comment: ""), monthRecords.count))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(6)
                                .shadow(radius: 2)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(HetkiaPalette.paper)
                            .overlay {
                                Image(systemName: "circle.dotted")
                                    .foregroundStyle(HetkiaPalette.line)
                            }
                    }
                }
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(8)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(monthRecords.isEmpty)
        .opacity(monthRecords.isEmpty ? 0.45 : 1)
    }
}

struct SavedJournalsMonthCalendarBrowseView: View {
    let year: Int
    let month: Int
    let records: [JournalRecord]
    let onChangeMonth: (Int) -> Void
    let onSelectRecord: (JournalRecord) -> Void

    @Environment(\.locale) private var locale
    @State private var selectedEmptyDate: Date?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    private var monthDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) ?? .now
    }

    private var days: [Date] {
        guard let interval = Calendar.current.range(of: .day, in: .month, for: monthDate) else { return [] }
        return interval.compactMap { day in
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        }
    }

    private var leadingEmptyCells: Int {
        guard let firstDay = days.first else { return 0 }
        let weekday = Calendar.current.component(.weekday, from: firstDay)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { onChangeMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                Spacer()
                Text(monthDate.formatted(.dateTime.year().month(.wide).locale(locale)))
                    .font(.system(size: 21, weight: .regular, design: .serif))
                Spacer()
                Button { onChangeMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(HetkiaPalette.secondaryInk)

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(calendar.veryShortStandaloneWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                }
                ForEach(0..<leadingEmptyCells, id: \.self) { _ in
                    Color.clear.frame(height: 46)
                }
                ForEach(days, id: \.self) { date in
                    dayButton(date)
                }
            }
            .padding(12)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let selectedEmptyDate {
                Text("calendar.no-entry")
                    .font(.system(size: 12))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
            }
        }
        .padding(.horizontal, 18)
    }

    private func dayButton(_ date: Date) -> some View {
        let record = SavedJournalIndex.record(on: date, from: records)
        let day = calendar.component(.day, from: date)
        return Button {
            if let record {
                selectedEmptyDate = nil
                onSelectRecord(record)
            } else {
                selectedEmptyDate = date
            }
        } label: {
            VStack(spacing: 3) {
                Text(String(day))
                    .font(.system(size: 12, weight: record == nil ? .regular : .medium, design: .rounded))
                Circle()
                    .fill(record == nil ? .clear : HetkiaPalette.amber)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(record == nil ? .clear : HetkiaPalette.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}
