import SwiftUI

struct MonthCalendarView: View {
    let year: Int
    let month: Int
    let onChangeMonth: (Int) -> Void
    let onSelectEntry: (JournalEntry) -> Void

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

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = max(0, calendar.firstWeekday - 1)
        return Array(symbols[shift...]) + Array(symbols[..<shift])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { onChangeMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .accessibilityLabel(Text("month.previous"))

                Spacer()
                Text(monthDate.formatted(.dateTime.year().month(.wide).locale(locale)))
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink)
                Spacer()

                Button { onChangeMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .accessibilityLabel(Text("month.next"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HetkiaPalette.secondaryInk)

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
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
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(HetkiaPalette.line.opacity(0.55), lineWidth: 0.7)
            }

            if let selectedEmptyDate {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed")
                    Text(selectedEmptyDate.formatted(.dateTime.month(.wide).day().locale(locale)))
                    Text("calendar.no-entry")
                }
                .font(.system(size: 12))
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .padding(.horizontal, 3)
            } else {
                Text("calendar.hint")
                    .font(.system(size: 12))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                    .padding(.horizontal, 3)
            }
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let entry = JournalSampleData.entry(on: date)
        let day = calendar.component(.day, from: date)

        return Button {
            if let entry {
                selectedEmptyDate = nil
                onSelectEntry(entry)
            } else {
                selectedEmptyDate = date
            }
        } label: {
            VStack(spacing: 3) {
                Text(String(day))
                    .font(.system(size: 12, weight: entry == nil ? .regular : .medium, design: .rounded))
                    .foregroundStyle(entry == nil ? HetkiaPalette.ink : HetkiaPalette.ink)
                Circle()
                    .fill(entry == nil ? .clear : HetkiaPalette.amber)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(entry == nil ? .clear : HetkiaPalette.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date.formatted(.dateTime.year().month(.wide).day().locale(locale))))
        .accessibilityHint(Text(entry == nil ? "calendar.empty-day-hint" : "calendar.entry-day-hint"))
    }
}
