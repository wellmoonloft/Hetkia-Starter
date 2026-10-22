import Foundation

struct JournalEntry: Identifiable, Hashable {
    let id: String
    let date: Date
    let titleKey: String
    let excerptKey: String
    let bodyKey: String
    let locationKey: String?
    let moodKey: String?
    let photoCount: Int
    let photoSeed: Int

    var samplePhotoCategories: [String] {
        var categories: [String] = []
        if bodyKey == "story.coast.body" || bodyKey == "story.walk.body" {
            categories.append("search.category.nature")
        }
        if bodyKey == "story.garden.body" || bodyKey == "story.flowers.body" {
            categories.append("search.category.plants")
        }
        if bodyKey == "story.cafe.body" {
            categories.append("search.category.cafes")
        }
        if locationKey == "location.oldstreet" {
            categories.append("search.category.streets")
        }
        return categories
    }
}

enum JournalSampleData {
    static let entries: [JournalEntry] = [
        make("2026-10-18", story: "story.walk", location: "location.daan", mood: "mood.calm", photos: 3, seed: 0),
        make("2026-10-12", story: "story.cafe", location: "location.oldstreet", mood: "mood.content", photos: 5, seed: 1),
        make("2026-09-22", story: "story.coast", location: "location.coast", mood: "mood.curious", photos: 1, seed: 2),
        make("2026-08-09", story: "story.garden", location: nil, mood: "mood.calm", photos: 7, seed: 3),
        make("2026-05-17", story: "story.flowers", location: "location.flower-market", mood: "mood.grateful", photos: 9, seed: 4),
        make("2025-12-24", story: "story.cafe", location: "location.home", mood: "mood.content", photos: 3, seed: 5),
        make("2025-11-08", story: "story.coast", location: "location.coast", mood: nil, photos: 5, seed: 6),
        make("2025-06-16", story: "story.garden", location: "location.home", mood: "mood.calm", photos: 1, seed: 7)
    ].sorted { $0.date > $1.date }

    static var years: [Int] {
        Array(Set(entries.map { Calendar.current.component(.year, from: $0.date) })).sorted(by: >)
    }

    static func entries(in year: Int) -> [JournalEntry] {
        entries.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    static func entries(in year: Int, month: Int) -> [JournalEntry] {
        entries.filter {
            let components = Calendar.current.dateComponents([.year, .month], from: $0.date)
            return components.year == year && components.month == month
        }
    }

    static func entry(on date: Date) -> JournalEntry? {
        entries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private static func make(
        _ dateText: String,
        story: String,
        location: String?,
        mood: String?,
        photos: Int,
        seed: Int
    ) -> JournalEntry {
        let parts = dateText.split(separator: "-").compactMap { Int($0) }
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        ) ?? .now

        return JournalEntry(
            id: dateText,
            date: date,
            titleKey: "\(story).title",
            excerptKey: "\(story).excerpt",
            bodyKey: "\(story).body",
            locationKey: location,
            moodKey: mood,
            photoCount: photos,
            photoSeed: seed
        )
    }
}
