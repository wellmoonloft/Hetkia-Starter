import SwiftUI
import SwiftData
import Combine

enum TimelineBrowseMode: Equatable {
    case all
    case year
    case month
}

struct TimelineHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var records: [JournalRecord] = []
    @State private var path: [String] = []
    @State private var browseMode: TimelineBrowseMode = .all
    @State private var selectedYear = Calendar.current.component(.year, from: .now)
    @State private var selectedMonth: Int?
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showPhotoImport = false
    #if os(macOS)
    @State private var isBottomBarVisible = true
    #else
    @State private var isBottomBarVisible = false
    #endif

    private var years: [Int] {
        Array(Set(records.map { Calendar.current.component(.year, from: $0.localDay) })).sorted(by: >)
    }

    private var visibleRecords: [JournalRecord] {
        records.filter { record in
            let parts = Calendar.current.dateComponents([.year, .month], from: record.localDay)
            if browseMode == .all, let selectedMonth {
                return parts.year == selectedYear && parts.month == selectedMonth
            }
            return true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { _ in
                ZStack(alignment: .bottom) {
                    HetkiaPalette.paper.ignoresSafeArea()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            switch browseMode {
                            case .year: yearGrid
                            case .month: monthGrid
                            case .all:
                                onThisDay
                                journalGrid
                            }
                            Color.clear.frame(height: 110)
                        }
                        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 128)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    }
#if os(iOS)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        let offset = max(0, geometry.visibleRect.minY)
                        let canScroll = geometry.contentSize.height > geometry.containerSize.height + 80
                        let reachesEnd = geometry.contentSize.height > geometry.containerSize.height + 80
                            && geometry.visibleRect.maxY >= geometry.contentSize.height - 18
                        // Compact year/month views cannot be scrolled to reveal the bar.
                        return !canScroll || (offset >= 12 && !reachesEnd)
                    } action: { _, shouldShow in
                        isBottomBarVisible = shouldShow
                    }
#endif

                    if isBottomBarVisible {
                        BottomNavigationBar(
                            selectedMode: browseMode,
                            onSettings: { showSettings = true },
                            onYear: { browseMode = .year; selectedMonth = nil },
                            onMonth: { browseMode = .month; selectedMonth = nil },
                            onAll: { browseMode = .all; selectedMonth = nil },
                            onSearch: { showSearch = true }
                        )
                        .padding(.bottom, 8).transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: isBottomBarVisible)
            }
            .navigationDestination(for: String.self) { routeKey in
                if let record = records.first(where: { $0.routeKey == routeKey }) {
                    PersistentJournalDetailView(record: record)
                } else {
                    ContentUnavailableView("browse.no-entry-month", systemImage: "book.closed")
                }
            }
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showSettings, onDismiss: reloadRecords) { SettingsView() }
            .sheet(isPresented: $showPhotoImport, onDismiss: {
                Task {
                    await JournalAutomationCoordinator.shared.catchUp(context: modelContext)
                    reloadRecords()
                }
            }) { PhotoImportView() }
            .sheet(isPresented: $showSearch) {
                NavigationStack { PersistedJournalSearchView(records: records) { record in showSearch = false; path.append(record.routeKey) } }
            }
        }
        .tint(HetkiaPalette.amber)
        .task { reloadRecords() }
        .onReceive(NotificationCenter.default.publisher(for: .hetkiaJournalRecordsDidChange)) { _ in
            reloadRecords()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reloadRecords() }
        }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { reloadRecords() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("brand.name").font(.system(size: 31, weight: .regular, design: .serif)).foregroundStyle(HetkiaPalette.ink)
                Text("timeline.tagline").font(.system(size: 12)).foregroundStyle(HetkiaPalette.secondaryInk)
            }
            Spacer()
            Button(action: createManualToday) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15)).foregroundStyle(HetkiaPalette.ink).frame(width: 48, height: 48)
                    .background(.white.opacity(0.65), in: Circle())
            }.buttonStyle(.plain).contentShape(Rectangle()).zIndex(2).accessibilityLabel(Text("journal.create-today"))
        }
    }

    private var onThisDay: some View {
        let calendar = Calendar.autoupdatingCurrent
        let todayParts = calendar.dateComponents([.month, .day], from: .now)
        let memories = records.filter { record in
            let parts = calendar.dateComponents([.year, .month, .day], from: record.localDay)
            return parts.year != calendar.component(.year, from: .now)
                && parts.month == todayParts.month && parts.day == todayParts.day
        }
        return Group {
            if !memories.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    Text("timeline.on-this-day")
                        .font(.system(size: 19, weight: .medium, design: .serif)).foregroundStyle(HetkiaPalette.ink)
                    LazyVGrid(columns: journalColumns, spacing: 12) {
                        ForEach(memories) { record in diaryTile(record) }
                    }
                }
            }
        }
    }

    private func createManualToday() {
        let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
        let key = PhotoDayGrouping.key(for: today)
        let manualKey = "\(key)|manual"
        let legacyKey = key
        let descriptor = FetchDescriptor<JournalRecord>(predicate: #Predicate {
            $0.storageKey == manualKey || $0.storageKey == legacyKey
        })
        if let existing = (try? modelContext.fetch(descriptor))?.first(where: { $0.source == .manual }) {
            path.append(existing.routeKey)
            return
        }
        let record = JournalRecord(dayKey: key, localDay: today, source: .manual)
        modelContext.insert(record)
        do {
            try modelContext.save()
            reloadRecords()
            path.append(record.routeKey)
        } catch {
            modelContext.rollback()
        }
    }

    private func reloadRecords() {
        var descriptor = FetchDescriptor<JournalRecord>(sortBy: [SortDescriptor(\.localDay, order: .reverse)])
        descriptor.includePendingChanges = true
        records = (try? modelContext.fetch(descriptor)) ?? []
    }

    private let journalColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    @ViewBuilder private var journalGrid: some View {
        if visibleRecords.isEmpty {
            ContentUnavailableView {
                Label("photos.journal.empty-list", systemImage: "book.closed")
            } description: {
                Text("photos.journal.import-to-begin")
            } actions: {
                Button("photos.import.action") { showPhotoImport = true }.buttonStyle(.borderedProminent).tint(HetkiaPalette.amber)
            }
        } else {
            let groups = Dictionary(grouping: visibleRecords) { record in
                let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: record.localDay)
                return (parts.year ?? 0) * 100 + (parts.month ?? 0)
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { key in
                if let monthRecords = groups[key], let first = monthRecords.first {
                    TimelineSectionHeading(date: first.localDay)
                    LazyVGrid(columns: journalColumns, spacing: 12) {
                        ForEach(monthRecords) { record in diaryTile(record) }
                    }
                }
            }
        }
    }

    private func diaryTile(_ record: JournalRecord) -> some View {
        Button { path.append(record.routeKey) } label: {
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geometry in
                    if let photo = JournalPhotoSelection.selected(from: record.photos).first {
                        PhotoFallbackThumbnail(photo: photo, width: geometry.size.width, height: geometry.size.height)
                    } else {
                        placeholder
                    }
                }
                .aspectRatio(1.12, contentMode: .fit)
                Text(record.localDay.formatted(date: .long, time: .omitted))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Photo count"), JournalPhotoSelection.selected(from: record.photos).count))
                    .font(.system(size: 11)).foregroundStyle(HetkiaPalette.secondaryInk)
            }
            .padding(8)
            .background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var yearGrid: some View {
        Group {
            if years.isEmpty { emptyImport }
            else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(years, id: \.self) { year in
                        let yearly = records.filter { Calendar.current.component(.year, from: $0.localDay) == year }
                        Button { selectedYear = year; browseMode = .month } label: {
                            yearTile(title: String(year), count: yearly.count, photo: yearly.first.flatMap { JournalPhotoSelection.selected(from: $0.photos).first })
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var monthGrid: some View {
        let months = records.filter { Calendar.current.component(.year, from: $0.localDay) == selectedYear }
        let monthNumbers = Array(Set(months.map { Calendar.current.component(.month, from: $0.localDay) })).sorted(by: >)
        return Group {
            HStack {
                Button { browseMode = .year } label: { Label(String(selectedYear), systemImage: "chevron.left") }
                Spacer()
            }.buttonStyle(.plain).tint(HetkiaPalette.amber)
            if monthNumbers.isEmpty { emptyImport }
            else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(monthNumbers, id: \.self) { month in
                        let monthly = months.filter { Calendar.current.component(.month, from: $0.localDay) == month }
                        Button { selectedMonth = month; browseMode = .all } label: {
                            yearTile(title: DateFormatter.monthName(month, year: selectedYear), count: monthly.count, photo: monthly.first.flatMap { JournalPhotoSelection.selected(from: $0.photos).first })
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyImport: some View {
        ContentUnavailableView { Label("photos.journal.empty-list", systemImage: "photo.on.rectangle") }
            description: { Text("photos.journal.import-to-begin") }
            actions: { Button("photos.import.action") { showPhotoImport = true }.buttonStyle(.borderedProminent).tint(HetkiaPalette.amber) }
    }

    private func yearTile(title: String, count: Int, photo: JournalPhotoRecord?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let photo { AdaptiveJournalPhotoTile(photo: photo, height: 120) }
            else { placeholder.frame(height: 120) }
            HStack { Text(verbatim: title).font(.system(size: 17, weight: .medium, design: .serif)); Spacer(); Text("\(count)").font(.system(size: 11)).foregroundStyle(HetkiaPalette.secondaryInk) }
        }.padding(8).background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 14))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10).fill(HetkiaPalette.paper).overlay(Image(systemName: "photo").foregroundStyle(HetkiaPalette.line))
    }

}

private struct PersistedJournalCard: View {
    let record: JournalRecord
    private var ordered: [JournalPhotoRecord] { JournalPhotoSelection.selected(from: record.photos) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.localDay.formatted(date: .long, time: .omitted)).font(.system(size: 16, weight: .semibold, design: .serif))
                Spacer()
                Text(LocalizedStringKey(record.source == .automatic ? "journal.source.automatic" : "journal.source.manual"))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
            }.foregroundStyle(HetkiaPalette.ink)
            if ordered.isEmpty {
                RoundedRectangle(cornerRadius: 9).fill(HetkiaPalette.paper).frame(height: 104)
                    .overlay(Image(systemName: "photo").foregroundStyle(HetkiaPalette.line))
            } else {
                GeometryReader { geometry in
                    let photos = Array(ordered.prefix(3))
                    let gap: CGFloat = 8
                    let tileWidth = max(1, (geometry.size.width - gap * CGFloat(max(photos.count - 1, 0))) / CGFloat(photos.count))
                    HStack(spacing: gap) {
                        ForEach(photos) { photo in
                            PhotoFallbackThumbnail(photo: photo, width: tileWidth, height: 104)
                                .frame(width: tileWidth, height: 104).clipped()
                        }
                    }
                }
                .frame(height: 104)
            }
            Text(record.title.isEmpty ? (record.bodyText.isEmpty ? NSLocalizedString("photos.journal.pending", comment: "Pending journal") : String(record.bodyText.prefix(100))) : record.title)
                .font(.system(size: 13)).lineLimit(2).foregroundStyle(HetkiaPalette.secondaryInk)
            HStack {
                if let location = record.locationText, !location.isEmpty { Label(location, systemImage: "mappin") }
                Spacer()
                Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Photo count"), ordered.count))
            }.font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
        }.padding(14).background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(HetkiaPalette.line.opacity(0.6), lineWidth: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 19))
    }
}

private struct PersistedJournalSearchView: View {
    let records: [JournalRecord]
    let onSelect: (JournalRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchByPhotoMetadata = false

    private var results: [JournalRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return records.filter { record in
            let metadata = record.photos.flatMap { photo -> [String] in
                var fields = [String]()
                if let date = photo.capturedAt { fields.append(date.formatted(date: .long, time: .omitted)) }
                if let place = photo.placeName { fields.append(place) }
                if let latitude = photo.latitude { fields.append(String(latitude)) }
                if let longitude = photo.longitude { fields.append(String(longitude)) }
                return fields
            }.joined(separator: " ")
            let fields = searchByPhotoMetadata ? metadata : [record.title, record.bodyText, record.locationText ?? "", record.moodText ?? "", metadata].joined(separator: " ")
            return needle.isEmpty || fields.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle)
        }
    }

    var body: some View {
        List {
            Picker("search.method", selection: $searchByPhotoMetadata) {
                Text("search.text-mode").tag(false)
                Text("search.photo-mode").tag(true)
            }.pickerStyle(.segmented).listRowBackground(Color.clear)
            if searchByPhotoMetadata { Text("photos.search.metadata-only").font(.system(size: 11)).foregroundStyle(HetkiaPalette.secondaryInk).listRowBackground(Color.clear) }
            if results.isEmpty { ContentUnavailableView("search.no-results", systemImage: "magnifyingglass").listRowBackground(Color.clear) }
            ForEach(results) { record in
                Button { dismiss(); onSelect(record) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.localDay.formatted(date: .long, time: .omitted)).font(.system(size: 15, weight: .medium, design: .serif))
                        Text(record.title.isEmpty ? record.bodyText : record.title).font(.system(size: 12)).lineLimit(2)
                        Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Photo count"), JournalPhotoSelection.selected(from: record.photos).count)).font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
                    }.foregroundStyle(HetkiaPalette.ink)
                }.buttonStyle(.plain).listRowBackground(HetkiaPalette.page)
            }
        }.scrollContentBackground(.hidden).background(HetkiaPalette.paper)
            .searchable(text: $query, prompt: Text("search.placeholder"))
            .navigationTitle(Text("search.title"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } } }
    }
}

private struct AdaptiveJournalPhotoTile: View {
    let photo: JournalPhotoRecord
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            PhotoFallbackThumbnail(photo: photo, width: geometry.size.width, height: height)
                .frame(width: geometry.size.width, height: height)
                .clipped()
        }
        .frame(height: height)
    }
}

private extension DateComponents {
    var yearMonthKey: Int { (year ?? 0) * 100 + (month ?? 0) }
}

private extension DateFormatter {
    static func monthName(_ month: Int, year: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "LLLL"
        return formatter.monthSymbols[safe: month - 1] ?? "\(year)-\(month)"
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
