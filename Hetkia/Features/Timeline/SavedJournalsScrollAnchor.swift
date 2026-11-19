import SwiftUI

enum SavedJournalScrollAnchorID {
    static func year(_ year: Int) -> String { "year-\(year)" }
    static func month(year: Int, month: Int) -> String { "month-\(year)-\(month)" }
    static func day(_ dayKey: String) -> String { "day-\(dayKey)" }
}

struct SavedJournalScrollAnchorPreference: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func savedJournalReportsScrollAnchor(id: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SavedJournalScrollAnchorPreference.self,
                    value: [id: geometry.frame(in: .named("savedJournalsScroll")).midY]
                )
            }
        }
    }
}

enum SavedJournalScrollAnchorResolver {
    static func centeredAnchorID(
        anchors: [String: CGFloat],
        viewportCenterY: CGFloat
    ) -> String? {
        guard !anchors.isEmpty else { return nil }
        return anchors.min { lhs, rhs in
            abs(lhs.value - viewportCenterY) < abs(rhs.value - viewportCenterY)
        }?.key
    }

    static func yearMonth(
        from anchorID: String?,
        records: [JournalRecord]
    ) -> (year: Int, month: Int)? {
        let calendar = Calendar.autoupdatingCurrent
        if let anchorID {
            if anchorID.hasPrefix("year-"), let year = Int(anchorID.dropFirst(5)) {
                let month = SavedJournalIndex.monthsWithPhotoDays(inYear: year, from: records).first
                    ?? calendar.component(.month, from: .now)
                return (year, month)
            }
            if anchorID.hasPrefix("month-") {
                let parts = anchorID.dropFirst(6).split(separator: "-")
                if parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) {
                    return (year, month)
                }
            }
            if anchorID.hasPrefix("day-") {
                let dayKey = String(anchorID.dropFirst(4))
                if let record = records.first(where: { $0.dayKey == dayKey }) {
                    let y = calendar.component(.year, from: record.localDay)
                    let m = calendar.component(.month, from: record.localDay)
                    return (y, m)
                }
            }
        }
        return SavedJournalIndex.latestMonthWithEntries(from: records)
    }
}