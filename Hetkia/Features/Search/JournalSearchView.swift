import SwiftUI

struct JournalSearchView: View {
    let entries: [JournalEntry]
    let onSelect: (JournalEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchByPhoto = false
    @State private var selectedPhotoCategory: String?

    private var results: [JournalEntry] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return entries }
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return entries.filter { entry in
            if searchByPhoto {
                guard let selectedPhotoCategory else { return true }
                return entry.samplePhotoCategories.contains(selectedPhotoCategory)
            }
            let fields = [entry.titleKey, entry.excerptKey, entry.bodyKey, entry.locationKey, entry.moodKey]
                .compactMap { $0 }
                .map { Bundle.main.localizedString(forKey: $0, value: $0, table: nil) }
            let date = entry.date.formatted(date: .long, time: .omitted)
            return (fields + [date]).contains { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle) }
        }
    }

    var body: some View {
        List {
            Picker("search.method", selection: $searchByPhoto) {
                Text("search.text-mode").tag(false)
                Text("search.photo-mode").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if searchByPhoto {
                Section {
                    Text("search.photo.note")
                        .font(.system(size: 11))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                        .listRowBackground(Color.clear)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            photoCategoryChip(nil, title: "search.category.all")
                            photoCategoryChip("search.category.nature", title: "search.category.nature")
                            photoCategoryChip("search.category.plants", title: "search.category.plants")
                            photoCategoryChip("search.category.cafes", title: "search.category.cafes")
                            photoCategoryChip("search.category.streets", title: "search.category.streets")
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if results.isEmpty {
                ContentUnavailableView("search.no-results", systemImage: "magnifyingglass")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(results) { entry in
                    Button {
                        dismiss()
                        onSelect(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(LocalizedStringKey(entry.titleKey)).font(.system(size: 17, weight: .medium, design: .serif))
                                Spacer()
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11))
                            }
                            Text(LocalizedStringKey(entry.excerptKey))
                                .font(.system(size: 13)).lineLimit(2)
                            HStack(spacing: 5) {
                                Image(systemName: "photo")
                                Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Number of sample photos"), entry.photoCount))
                            }
                            .font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
                        }
                        .foregroundStyle(HetkiaPalette.ink)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(HetkiaPalette.page)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HetkiaPalette.paper)
        .searchable(text: $query, prompt: Text(searchByPhoto ? "search.photo.placeholder" : "search.placeholder"))
        .navigationTitle(Text("search.title"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } } }
    }

    private func photoCategoryChip(_ category: String?, title: LocalizedStringKey) -> some View {
        let isSelected = selectedPhotoCategory == category
        return Button {
            selectedPhotoCategory = category
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white : HetkiaPalette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? HetkiaPalette.amber : .white.opacity(0.8), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
