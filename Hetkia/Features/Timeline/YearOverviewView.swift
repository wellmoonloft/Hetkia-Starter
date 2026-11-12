import SwiftUI

struct YearsOverviewView: View {
    let years: [Int]
    let onSelectYear: (Int) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(years, id: \.self) { year in
                let entries = JournalSampleData.entries(in: year)
                if let firstEntry = entries.first {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(year))
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .foregroundStyle(HetkiaPalette.ink)

                        LazyVGrid(columns: columns, spacing: 12) {
                            Button { onSelectYear(year) } label: {
                                ZStack(alignment: .bottomLeading) {
                                    SamplePhotoView(index: firstEntry.photoSeed)
                                    LinearGradient(colors: [.clear, .black.opacity(0.60)], startPoint: .center, endPoint: .bottom)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(String(year)).font(.system(size: 15, weight: .medium, design: .serif))
                                        Text(String(format: HetkiaSystemLanguage.localizedString("timeline.entry-count", comment: "Number of journal entries in a year"), entries.count))
                                            .font(.system(size: 10))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(11)
                                }
                                .frame(height: 156)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(String(year)))
                        }
                    }
                }
            }
        }
    }
}

struct YearOverviewView: View {
    let year: Int
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
                .accessibilityLabel(Text("year.previous"))

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
                .accessibilityLabel(Text("year.next"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HetkiaPalette.secondaryInk)

            Text(String(format: HetkiaSystemLanguage.localizedString("browse.months.in-year", comment: "Months in selected year"), year))
                .font(.system(size: 12))
                .foregroundStyle(HetkiaPalette.secondaryInk)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...12, id: \.self) { month in
                    monthTile(month)
                }
            }
        }
    }

    private func monthTile(_ month: Int) -> some View {
        let entries = JournalSampleData.entries(in: year, month: month)
        let firstEntry = entries.first
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
                    if let firstEntry {
                        SamplePhotoView(index: firstEntry.photoSeed)
                            .overlay(alignment: .bottomLeading) {
                                LinearGradient(colors: [.clear, .black.opacity(0.38)], startPoint: .center, endPoint: .bottom)
                                    .overlay(alignment: .bottomLeading) {
                                        Text(String(format: HetkiaSystemLanguage.localizedString("timeline.entry-count", comment: "Number of journal entries in a month"), entries.count))
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(.white)
                                            .padding(6)
                                    }
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(HetkiaPalette.paper)
                            .overlay {
                                Image(systemName: "circle.dotted")
                                    .font(.system(size: 17, weight: .light))
                                    .foregroundStyle(HetkiaPalette.line)
                            }
                    }
                }
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(HetkiaPalette.line.opacity(0.55), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date.formatted(.dateTime.year().month(.wide).locale(locale))))
    }
}
