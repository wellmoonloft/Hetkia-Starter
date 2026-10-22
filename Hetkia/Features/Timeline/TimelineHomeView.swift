import SwiftUI
import SwiftData

enum TimelineBrowseMode: Equatable {
    case all
    case year
    case month
}

struct TimelineHomeView: View {
    @Query(sort: \JournalRecord.localDay, order: .reverse) private var records: [JournalRecord]
    @State private var path: [String] = []
    @State private var browseMode: TimelineBrowseMode = .all
    @State private var selectedYear = Calendar.current.component(.year, from: .now)
    @State private var selectedMonth: Int?
    @State private var isPhotoWall = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showPhotoImport = false
    #if os(macOS)
    @State private var isBottomBarVisible = true
    #else
    @State private var isBottomBarVisible = false
    #endif
    @State private var lastOffset: CGFloat = 0
    @State private var atEnd = false

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
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    HetkiaPalette.paper.ignoresSafeArea()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            switch browseMode {
                            case .year: yearGrid
                            case .month: monthGrid
                            case .all:
                                if isPhotoWall { photoWall }
                                else { journalList }
                            }
                            Color.clear.frame(height: 110)
                        }
                        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 128)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ScrollContentFrameKey.self, value: proxy.frame(in: .named("timeline-scroll")))
                        })
                    }
                    .coordinateSpace(name: "timeline-scroll")
                    #if !os(macOS)
                    .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                        if value.translation.height < -22 && !atEnd { isBottomBarVisible = true }
                        else if value.translation.height > 22 { isBottomBarVisible = false }
                    })
                    #endif
                    .onPreferenceChange(ScrollContentFrameKey.self) { frame in updateScroll(frame, viewport: geometry.size.height) }

                    if isBottomBarVisible {
                        BottomNavigationBar(
                            selectedMode: browseMode, isPhotoWall: isPhotoWall,
                            onSettings: { showSettings = true },
                            onYear: { browseMode = .year; selectedMonth = nil },
                            onMonth: { browseMode = .month; isPhotoWall = false; selectedMonth = nil },
                            onAll: { browseMode = .all; isPhotoWall = false; selectedMonth = nil },
                            onSearch: { showSearch = true }
                        )
                        .padding(.bottom, 8).transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: isBottomBarVisible)
            }
            .navigationDestination(for: String.self) { dayKey in
                if let record = records.first(where: { $0.dayKey == dayKey }) {
                    PersistentJournalDetailView(record: record)
                } else {
                    ContentUnavailableView("browse.no-entry-month", systemImage: "book.closed")
                }
            }
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showPhotoImport) { PhotoImportView() }
            .sheet(isPresented: $showSearch) {
                NavigationStack { PersistedJournalSearchView(records: records) { record in showSearch = false; path.append(record.dayKey) } }
            }
        }
        .tint(HetkiaPalette.amber)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("brand.name").font(.system(size: 31, weight: .regular, design: .serif)).foregroundStyle(HetkiaPalette.ink)
                Text("timeline.tagline").font(.system(size: 12)).foregroundStyle(HetkiaPalette.secondaryInk)
            }
            Spacer()
            Button { isPhotoWall.toggle(); browseMode = .all } label: {
                Image(systemName: isPhotoWall ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 16)).foregroundStyle(HetkiaPalette.ink).frame(width: 42, height: 42)
                    .background(.white.opacity(0.65), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(Text(isPhotoWall ? "timeline.show-list" : "timeline.show-wall"))
        }
    }

    @ViewBuilder private var journalList: some View {
        if visibleRecords.isEmpty {
            ContentUnavailableView {
                Label("photos.journal.empty-list", systemImage: "book.closed")
            } description: {
                Text("photos.journal.import-to-begin")
            } actions: {
                Button("photos.import.action") { showPhotoImport = true }.buttonStyle(.borderedProminent).tint(HetkiaPalette.amber)
            }
        } else {
            let groups = Dictionary(grouping: visibleRecords) { Calendar.current.dateComponents([.year, .month], from: $0.localDay).yearMonthKey }
            ForEach(groups.keys.sorted(by: >), id: \.self) { key in
                if let group = groups[key], let first = group.first {
                    TimelineSectionHeading(date: first.localDay)
                    ForEach(group) { record in
                        Button { path.append(record.dayKey) } label: { PersistedJournalCard(record: record) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var photoWall: some View {
        if records.isEmpty {
            ContentUnavailableView("photos.journal.empty-list", systemImage: "photo.on.rectangle")
        } else {
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(visibleRecords) { record in
                    Button { path.append(record.dayKey) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let photo = record.photos.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                                AdaptiveJournalPhotoTile(photo: photo, height: 160)
                            } else { placeholder.frame(height: 160) }
                            Text(record.localDay.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 12, weight: .medium))
                            Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Photo count"), record.photos.count)).font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
                        }.padding(8).background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var yearGrid: some View {
        Group {
            if years.isEmpty { emptyImport }
            else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(years, id: \.self) { year in
                        let yearly = records.filter { Calendar.current.component(.year, from: $0.localDay) == year }
                        Button { selectedYear = year; browseMode = .month } label: {
                            yearTile(title: String(year), count: yearly.count, photo: yearly.first?.photos.sorted(by: { $0.sortOrder < $1.sortOrder }).first)
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
                            yearTile(title: DateFormatter.monthName(month, year: selectedYear), count: monthly.count, photo: monthly.first?.photos.sorted(by: { $0.sortOrder < $1.sortOrder }).first)
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

    private func updateScroll(_ frame: CGRect, viewport: CGFloat) {
        guard frame != .zero else { return }
        let offset = max(0, -frame.minY)
        atEnd = frame.maxY <= viewport + 18
        #if os(macOS)
        isBottomBarVisible = true
        #else
        if atEnd || offset < 12 { isBottomBarVisible = false }
        else if offset - lastOffset > 2.5 { isBottomBarVisible = true }
        else if lastOffset - offset > 2.5 { isBottomBarVisible = false }
        #endif
        lastOffset = offset
    }
}

private struct PersistedJournalCard: View {
    let record: JournalRecord
    private var ordered: [JournalPhotoRecord] { record.photos.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.localDay.formatted(date: .long, time: .omitted)).font(.system(size: 16, weight: .semibold, design: .serif))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
            }.foregroundStyle(HetkiaPalette.ink)
            if ordered.isEmpty {
                RoundedRectangle(cornerRadius: 9).fill(HetkiaPalette.paper).frame(height: 104)
                    .overlay(Image(systemName: "photo").foregroundStyle(HetkiaPalette.line))
            } else {
                GeometryReader { geometry in
                    let photos = Array(ordered.prefix(3))
                    let gap: CGFloat = 8
                    let tileWidth = max(0, (geometry.size.width - gap * CGFloat(max(photos.count - 1, 0))) / CGFloat(photos.count))
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
                        Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Photo count"), record.photos.count)).font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
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
