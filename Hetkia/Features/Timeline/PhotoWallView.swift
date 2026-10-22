import SwiftUI

struct PhotoWallView: View {
    let entries: [JournalEntry]
    let onSelectEntry: (JournalEntry) -> Void

    private let columns = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]

    private var monthGroups: [JournalMonthGroupForWall] {
        let grouped = Dictionary(grouping: entries) { entry in
            let components = Calendar.current.dateComponents([.year, .month], from: entry.date)
            return (components.year ?? 0) * 100 + (components.month ?? 0)
        }
        return grouped.keys.sorted(by: >).compactMap { key in
            guard let groupEntries = grouped[key], let first = groupEntries.first else { return nil }
            return JournalMonthGroupForWall(id: key, date: first.date, entries: groupEntries.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(monthGroups) { group in
                VStack(alignment: .leading, spacing: 11) {
                    TimelineSectionHeading(date: group.date)
                    LazyVGrid(columns: columns, spacing: 11) {
                        ForEach(group.entries) { entry in
                            wallCard(entry)
                        }
                    }
                }
            }
        }
    }

    private func wallCard(_ entry: JournalEntry) -> some View {
        Button {
            onSelectEntry(entry)
        } label: {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    SamplePhotoView(index: entry.photoSeed)

                    if entry.photoCount > 1 {
                        HStack(spacing: 4) {
                            ForEach(1..<min(entry.photoCount, 3), id: \.self) { index in
                                SamplePhotoView(index: (entry.photoSeed + index) % 9)
                                    .frame(width: max(34, geometry.size.width * 0.22), height: max(34, geometry.size.width * 0.22))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1.2))
                            }
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    LinearGradient(colors: [.clear, .black.opacity(0.73)], startPoint: .center, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(LocalizedStringKey(entry.excerptKey))
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .frame(height: entry.photoSeed.isMultiple(of: 2) ? 176 : 198)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(entry.titleKey)))
    }
}

private struct JournalMonthGroupForWall: Identifiable {
    let id: Int
    let date: Date
    let entries: [JournalEntry]
}
