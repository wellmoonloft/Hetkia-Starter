import SwiftUI
import SwiftData
import Photos
import WidgetKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Combine

struct TimelineHomeView: View {
    @AppStorage(PhotoAssetEligibility.includeScreenshotsDefaultsKey, store: PhotoAssetEligibility.sharedDefaults) private var includeScreenshotsAndScreenRecordings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalRecord.localDay, order: .reverse) private var savedRecords: [JournalRecord]
    @State private var entries: [OnThisDayEntry] = []
    @State private var path: [TimelineRootRoute] = []
    @State private var rootTab: TimelineRootTab = .onThisDay
    @State private var savedJournalsBrowse: SavedJournalsBrowseMode = .all
    @State private var savedJournalsMonthScope: SavedJournalsMonthScope?
    @State private var onThisDayScrollMetrics = TimelineScrollMetrics()
    @State private var savedJournalsScrollMetrics = TimelineScrollMetrics()
    @State private var isLoading = true
    @State private var hasResolvedInitialCache = false
    @State private var progress = 0.0
    @State private var isRefreshing = false
    @State private var showsScanProgress = false
    @State private var didLeaveActiveState = false
    @State private var showSettings = false
    @State private var showMomentPublishSheet = false
    @State private var showEssayPublishSheet = false
    @State private var essayPublishSheetToken = UUID()
    @State private var showPublishSettings = false
    @State private var essayPublishPhotos: [JournalPhotoRecord] = []
    @State private var essayPublishTitle = ""
    @State private var essayPublishBody = ""
    @State private var essayPublishCaptureDate = Date()
    @State private var essayPublishDayKey = ""
    @State private var pendingPublishEssay = false
    @State private var momentPublishSheetToken = UUID()
    @State private var momentPublishPhotos: [JournalPhotoRecord] = []
    @State private var momentPublishBody = ""
    @State private var momentPublishDayKey = ""
    @State private var momentPublishCreatedAt = Date()
    @State private var pendingPublishMoment = false
    @State private var activeCalendarDay = PhotoDayGrouping.key(for: .now)
    @State private var pendingWidgetRoute: String?
    private let minuteTicker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
                count: geometry.size.width >= 700 ? 2 : 1
            )

            NavigationStack(path: $path) {
                ZStack {
                    onThisDayRootScroll(columns: columns)
                        .opacity(rootTab == .onThisDay ? 1 : 0)
                        .allowsHitTesting(rootTab == .onThisDay)
                    savedJournalsRootScroll
                        .opacity(rootTab == .savedJournals ? 1 : 0)
                        .allowsHitTesting(rootTab == .savedJournals)
                }
                .background(HetkiaPalette.paper.ignoresSafeArea())
                .overlay(alignment: .bottomLeading) {
#if !os(macOS)
                    if floatingBarVisible {
                        HomeHistoryFloatingBar(
                            rootTab: $rootTab,
                            historyBrowse: savedJournalsBrowse,
                            onSelectMonth: selectSavedJournalsMonth,
                            onSelectYear: selectSavedJournalsYear,
                            onSelectAll: selectSavedJournalsAll,
                            onSelectSavedJournalsTab: resetSavedJournalsBrowseToAll
                        )
                            .padding(.leading, 12)
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
#endif
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: floatingBarVisible)
                .navigationDestination(for: TimelineRootRoute.self) { route in
                    switch route {
                    case .onThisDay(let dayKey):
                        if let entry = entries.first(where: { $0.id == dayKey }) {
                            let existing = savedRecords.filter { $0.dayKey == dayKey }.max { $0.updatedAt < $1.updatedAt }
                            let record = existing ?? JournalRecord(dayKey: dayKey, localDay: entry.date, source: .manual)
                            PersistentJournalDetailView(record: record, liveAssets: entry.assets, isTransient: existing == nil)
                        } else {
                            ContentUnavailableView("onthisday.empty", systemImage: "calendar")
                        }
                    case .savedJournal(let dayKey):
                        if let record = savedRecords.filter({ $0.dayKey == dayKey }).max(by: { $0.updatedAt < $1.updatedAt }) {
                            PersistentJournalDetailView(record: record, savedOnly: true)
                        } else {
                            ContentUnavailableView("settings.saved-journals.empty", systemImage: "book.closed")
                        }
                    }
                }
                #if !os(macOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
            }
        }
        .tint(HetkiaPalette.amber)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showMomentPublishSheet) {
            MomentPublishSheet(
                publishPhotos: $momentPublishPhotos,
                initialBody: momentPublishBody,
                contentCreatedAt: momentPublishCreatedAt,
                sourceJournalDayKey: momentPublishDayKey,
                savedOnly: false,
                allowsInAppCamera: true,
                openSettings: {
                    showMomentPublishSheet = false
                    showPublishSettings = true
                }
            )
            .id(momentPublishSheetToken)
        }
        .sheet(isPresented: $showEssayPublishSheet) {
            EssayPublishSheet(
                publishPhotos: $essayPublishPhotos,
                initialTitle: essayPublishTitle,
                initialBody: essayPublishBody,
                captureReferenceDate: essayPublishCaptureDate,
                sourceJournalDayKey: essayPublishDayKey,
                savedOnly: false,
                allowsInAppCamera: true,
                openSettings: {
                    showEssayPublishSheet = false
                    showPublishSettings = true
                }
            )
            .id(essayPublishSheetToken)
        }
        .sheet(isPresented: $showPublishSettings) {
            NavigationStack {
                PublishSettingsView()
            }
            .presentationDetents([.large])
        }
        .task {
            guard !hasResolvedInitialCache else { return }
            await refresh(isInitialLoad: true)
            // Let the cached timeline paint before the recovery scan touches
            // persisted journals and their PhotoKit references.
            await Task.yield()
            PhotoLocationResolver.shared.resumePending(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                guard didLeaveActiveState else { return }
                didLeaveActiveState = false
                guard path.isEmpty else { return }
                let today = PhotoDayGrouping.key(for: .now)
                let crossedCalendarDay = today != activeCalendarDay
                activeCalendarDay = today
                PhotoLocationResolver.shared.resumePending(context: modelContext)
                Task {
                    await refresh(
                        forceFullScan: crossedCalendarDay,
                        showFullScanProgress: !crossedCalendarDay
                    )
                }
            } else {
                didLeaveActiveState = true
            }
        }
        .onChange(of: path) { _, newPath in
            guard newPath.isEmpty else { return }
            let today = PhotoDayGrouping.key(for: .now)
            guard today != activeCalendarDay else { return }
            activeCalendarDay = today
            Task { await refresh(forceFullScan: true, showFullScanProgress: false) }
        }
        .onChange(of: includeScreenshotsAndScreenRecordings) { _, _ in
            guard path.isEmpty else { return }
            Task { await refresh() }
        }
        .onReceive(minuteTicker) { _ in
            let newDay = PhotoDayGrouping.key(for: .now)
            if newDay != activeCalendarDay && path.isEmpty {
                activeCalendarDay = newDay
                Task { await refresh(forceFullScan: true, showFullScanProgress: false) }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "hetkia" else { return }
            rootTab = .onThisDay
            switch url.host {
            case "onthisday":
                let key = url.pathComponents.dropFirst().joined(separator: "/")
                if entries.contains(where: { $0.id == key }) { path = [.onThisDay(dayKey: key)] }
                else { pendingWidgetRoute = key; Task { await refresh() } }
            case "publish":
                let action = url.pathComponents.dropFirst().first ?? ""
                switch action {
                case "moment":
                    openMomentPublishFromDeepLink()
                case "essay":
                    openEssayPublishFromDeepLink()
                default:
                    break
                }
            default:
                break
            }
        }
    }

    private var hasBlockingSheetForPublishDeepLink: Bool {
        showSettings || showPublishSettings || showEssayPublishSheet || showMomentPublishSheet
    }

    private func dismissSheetsBlockingPublishDeepLink() {
        showSettings = false
        showPublishSettings = false
        showEssayPublishSheet = false
        showMomentPublishSheet = false
    }

    private func openMomentPublishFromDeepLink() {
        rootTab = .onThisDay
        pendingPublishMoment = true
        Task { @MainActor in
            if hasBlockingSheetForPublishDeepLink {
                dismissSheetsBlockingPublishDeepLink()
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard pendingPublishMoment else { return }
            if hasResolvedInitialCache {
                presentMomentPublishSheet()
            } else {
                await refresh(isInitialLoad: false)
                guard pendingPublishMoment else { return }
                presentMomentPublishSheet()
            }
        }
    }

    private func openEssayPublishFromDeepLink() {
        rootTab = .onThisDay
        pendingPublishEssay = true
        Task { @MainActor in
            if hasBlockingSheetForPublishDeepLink {
                dismissSheetsBlockingPublishDeepLink()
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard pendingPublishEssay else { return }
            if hasResolvedInitialCache {
                presentEssayPublishSheet()
            } else {
                await refresh(isInitialLoad: false)
                guard pendingPublishEssay else { return }
                presentEssayPublishSheet()
            }
        }
    }

    private func presentEssayPublishSheet() {
        rootTab = .onThisDay
        let context = todayEssayPublishContext()
        essayPublishPhotos = context.photos
        essayPublishTitle = context.title
        essayPublishBody = context.body
        essayPublishCaptureDate = context.captureDate
        essayPublishDayKey = context.dayKey
        pendingPublishEssay = false
        essayPublishSheetToken = UUID()
        showEssayPublishSheet = true
    }

    private func todayEssayPublishContext() -> (photos: [JournalPhotoRecord], title: String, body: String, captureDate: Date, dayKey: String) {
        let dayKey = PhotoDayGrouping.key(for: .now)
        let saved = savedRecords.filter { $0.dayKey == dayKey }.max { $0.updatedAt < $1.updatedAt }
        let entry = entries.first { $0.id == dayKey }
        var photos = saved?.photos ?? []
        let known = Set(photos.compactMap(\.assetLocalIdentifier))
        let fresh = OnThisDayLibrary.transientPhotoRecords(for: entry?.assets ?? [])
            .filter { record in
                guard let identifier = record.assetLocalIdentifier else { return true }
                return !known.contains(identifier)
            }
        photos.append(contentsOf: fresh)
        let captureDate = photos.compactMap(\.capturedAt).min() ?? saved?.localDay ?? entry?.date ?? .now
        return (
            photos,
            saved?.title ?? "",
            saved?.bodyText ?? "",
            captureDate,
            dayKey
        )
    }

    private func presentMomentPublishSheet() {
        rootTab = .onThisDay
        let context = todayEssayPublishContext()
        momentPublishPhotos = context.photos
        momentPublishBody = context.body
        momentPublishCreatedAt = .now
        momentPublishDayKey = context.dayKey
        pendingPublishMoment = false
        momentPublishSheetToken = UUID()
        showMomentPublishSheet = true
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("brand.name")
                    .font(.system(size: 31, weight: .regular, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink)
                Text("onthisday.tagline")
                    .font(.system(size: 13))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
            }
            Spacer(minLength: 0)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(HetkiaPalette.ink)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.75), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("settings.title")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("onthisday.scanning", systemImage: "photo.stack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HetkiaPalette.secondaryInk)
            ProgressView(value: progress).tint(HetkiaPalette.amber)
        }
        .padding(18)
        .background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptyOnThisDayState: some View {
        VStack(spacing: 11) {
            Spacer(minLength: 20)
            Text("onthisday.empty.title")
                .font(.system(size: 23, weight: .medium, design: .serif))
                .foregroundStyle(HetkiaPalette.ink)
                .multilineTextAlignment(.center)
            Text("onthisday.empty.message")
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 350)
                .padding(.top, 4)
            Image("OnThisDayEmptyIllustration")
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 360)
                // The flower adds visual weight to the left; offset the canvas so
                // the illustrated frame itself stays centered in the screen.
                .offset(x: -13)
                .accessibilityHidden(true)
                .padding(.top, 3)
            Text("onthisday.empty.invitation")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(HetkiaPalette.amber)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    presentMomentPublishSheet()
                } label: {
                    Text("onthisday.empty.publish-moment")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(HetkiaPalette.amber, in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    presentEssayPublishSheet()
                } label: {
                    Text("onthisday.empty.publish-essay")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(HetkiaPalette.amber)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.9), in: Capsule())
                        .overlay(Capsule().stroke(HetkiaPalette.amber, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 570)
        .padding(.horizontal, 12)
    }

    private var permissionState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("onboarding.photos.status.denied", systemImage: "hand.raised")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(HetkiaPalette.ink)
            Text("onboarding.photos.detail").font(.system(size: 13)).foregroundStyle(HetkiaPalette.secondaryInk)
            Button("settings.permissions") { openPhotoSettings() }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func refresh(
        forceFullScan: Bool = false,
        isInitialLoad: Bool = false,
        showFullScanProgress: Bool = true
    ) async {
        guard !isRefreshing else { return }
        if showEssayPublishSheet || showMomentPublishSheet { return }
        isRefreshing = true
        showsScanProgress = forceFullScan && showFullScanProgress
        defer {
            isRefreshing = false
            showsScanProgress = false
            // A cancelled SwiftUI refresh can otherwise leave the initial scan
            // state (and its completed progress indicator) on screen forever.
            isLoading = false
        }

        guard PhotoLibraryService.hasFullReadAccess else {
            entries = []
            isLoading = false
            hasResolvedInitialCache = true
            return
        }

        if hasResolvedInitialCache {
            // Keep the already-rendered cards in memory when returning to the
            // app. Reloading the disk snapshot first republishes every card,
            // even when the subsequent PhotoKit query finds no changes.
            if forceFullScan {
                progress = 0
                if let result = await OnThisDayScanCoordinator.shared.fullScan(progress: { progress = $0 }) {
                    publishEntriesIfChanged(result)
                }
            } else {
                if let result = await OnThisDayScanCoordinator.shared.currentYearRefresh(preserving: entries) {
                    publishEntriesIfChanged(result)
                }
            }
        } else if let cachedEntries = OnThisDayCacheStore.load() {
            // A valid cache, including a valid empty result, is rendered at once.
            // Routine launches only query the current year; older years are
            // rechecked by pull-to-refresh or when there is no same-day cache.
            publishEntriesIfChanged(cachedEntries)
            isLoading = false
            hasResolvedInitialCache = true
            await Task.yield()
            if forceFullScan {
                progress = 0
                let result = await OnThisDayScanCoordinator.shared.fullScan(progress: { progress = $0 })
                // PhotoKit's scan and cache write are not cancellation-aware. If
                // the refresh task is cancelled after the scan finishes, still
                // publish its result so the visible page matches the new cache.
                if let result { publishEntriesIfChanged(result) }
            } else {
                if let result = await OnThisDayScanCoordinator.shared.currentYearRefresh(preserving: entries) {
                    publishEntriesIfChanged(result)
                }
            }
        } else {
            // A missing/expired cache needs one full historical scan to build
            // today's index. This is normally the first run or a new calendar day.
            entries = []
            isLoading = true
            hasResolvedInitialCache = true
            showsScanProgress = forceFullScan || isInitialLoad
            progress = 0
            let result = await OnThisDayScanCoordinator.shared.fullScan { value in
                if showsScanProgress { progress = value }
            }
            if let result { publishEntriesIfChanged(result) }
        }
        isLoading = false
        if OnThisDayWidgetIndexStore.needsTimelineReload(force: forceFullScan) {
            HetkiaWidgetTimelineReloader.reloadVisibleKinds()
        }
        if let pendingWidgetRoute, entries.contains(where: { $0.id == pendingWidgetRoute }) {
            rootTab = .onThisDay
            path = [.onThisDay(dayKey: pendingWidgetRoute)]
            self.pendingWidgetRoute = nil
        }
    }

    private var listBottomInset: CGFloat {
#if os(macOS)
        28
#else
        guard floatingBarVisible else { return 28 }
        if rootTab == .savedJournals { return 88 }
        return 78
#endif
    }

    private var floatingBarVisible: Bool {
        guard path.isEmpty else { return false }
        guard !showSettings, !showEssayPublishSheet, !showMomentPublishSheet, !showPublishSettings else { return false }
#if os(macOS)
        return false
#else
        let metrics = rootTab == .onThisDay ? onThisDayScrollMetrics : savedJournalsScrollMetrics
        if !metrics.contentExceedsViewport { return true }
        return metrics.offset > 20
#endif
    }

    @ViewBuilder
    private func onThisDayRootScroll(columns: [GridItem]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !PhotoLibraryService.hasFullReadAccess {
                    permissionState
                } else if isLoading, rootTab == .onThisDay {
                    if showsScanProgress {
                        loadingState
                    } else {
                        Color.clear.frame(height: 54)
                    }
                } else {
                    if showsScanProgress, rootTab == .onThisDay {
                        loadingState
                    }
                    if entries.isEmpty {
                        emptyOnThisDayState
                    } else {
                        LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
                            ForEach(entries) { entry in
                                let saved = savedRecords
                                    .filter { $0.dayKey == entry.id }
                                    .max { $0.updatedAt < $1.updatedAt }
                                OnThisDayCard(entry: entry, savedRecord: saved) {
                                    path.append(.onThisDay(dayKey: entry.id))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, listBottomInset)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh(forceFullScan: true) }
#if !os(macOS)
        .timelineTracksScrollMetrics($onThisDayScrollMetrics)
#endif
    }

    private var meaningfulSavedJournalRecords: [JournalRecord] {
        SavedJournalIndex.meaningfulRecords(from: savedRecords)
    }

    private var savedJournalsRootScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                savedJournalsHeader
                savedJournalsBrowseBody
            }
            .padding(.top, 16)
            .padding(.bottom, listBottomInset)
        }
#if !os(macOS)
        .timelineTracksScrollMetrics($savedJournalsScrollMetrics)
#endif
    }

    @ViewBuilder
    private var savedJournalsBrowseBody: some View {
        let records = meaningfulSavedJournalRecords
        let openRecord: (JournalRecord) -> Void = { record in
            path.append(.savedJournal(dayKey: record.dayKey))
        }
        switch savedJournalsBrowse {
        case .all:
            SavedJournalsRootContent(
                savedRecords: savedRecords,
                bottomInset: 0,
                onSelectRecord: openRecord
            )
        case .year:
            SavedJournalsYearsBrowseView(records: records) { year in
                savedJournalsBrowse = .month
                savedJournalsMonthScope = .monthsInYear(year)
            }
        case .month:
            if case .monthsInYear(let year) = savedJournalsMonthScope {
                SavedJournalsMonthsInYearWaterfallView(
                    year: year,
                    records: records,
                    onSelectMonth: { y, m in
                        savedJournalsMonthScope = .entries(year: y, month: m)
                    }
                )
            } else if case .entries(let year, let month) = savedJournalsMonthScope {
                SavedJournalsMonthEntriesWaterfallView(
                    year: year,
                    month: month,
                    records: records,
                    onSelectRecord: openRecord
                )
            } else if let year = SavedJournalIndex.latestMonthWithEntries(from: records)?.year {
                SavedJournalsMonthsInYearWaterfallView(
                    year: year,
                    records: records,
                    onSelectMonth: { y, m in
                        savedJournalsMonthScope = .entries(year: y, month: m)
                    }
                )
                .onAppear {
                    savedJournalsMonthScope = .monthsInYear(year)
                }
            } else {
                ContentUnavailableView("settings.saved-journals.empty", systemImage: "book.closed")
                    .padding(.horizontal, 18)
            }
        }
    }

    private func resetSavedJournalsBrowseToAll() {
        savedJournalsBrowse = .all
        savedJournalsMonthScope = nil
    }

    private func selectSavedJournalsAll() {
        savedJournalsBrowse = .all
        savedJournalsMonthScope = nil
    }

    private func selectSavedJournalsYear() {
        savedJournalsBrowse = .year
        savedJournalsMonthScope = nil
    }

    private func selectSavedJournalsMonth() {
        switch savedJournalsMonthScope {
        case .entries(let year, _):
            savedJournalsBrowse = .month
            savedJournalsMonthScope = .monthsInYear(year)
        case .monthsInYear:
            break
        case nil:
            savedJournalsBrowse = .month
            applyDefaultSavedJournalsMonthsInYear()
        }
    }

    private func applyDefaultSavedJournalsMonthsInYear() {
        let records = meaningfulSavedJournalRecords
        guard let latest = SavedJournalIndex.latestMonthWithEntries(from: records) else { return }
        savedJournalsMonthScope = .monthsInYear(latest.year)
    }

    private var savedJournalsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings.saved-journals")
                .font(.system(size: 31, weight: .regular, design: .serif))
                .foregroundStyle(HetkiaPalette.ink)
            Text("timeline.tab.saved-journals.detail")
                .font(.system(size: 13))
                .foregroundStyle(HetkiaPalette.secondaryInk)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func publishEntriesIfChanged(_ updatedEntries: [OnThisDayEntry]) {
        guard !haveSameContent(entries, updatedEntries) else { return }
        entries = updatedEntries
    }

    private func haveSameContent(_ lhs: [OnThisDayEntry], _ rhs: [OnThisDayEntry]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { current, updated in
            current.id == updated.id &&
            current.assets.map(\.localIdentifier) == updated.assets.map(\.localIdentifier)
        }
    }

    private func openPhotoSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") { NSWorkspace.shared.open(url) }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}

private struct OnThisDayCard: View {
    let entry: OnThisDayEntry
    let savedRecord: JournalRecord?
    let onOpenDetail: () -> Void
    @State private var photoGallery: PhotoGallerySession?

    private var galleryPhotos: [JournalPhotoRecord] {
        OnThisDayLibrary.transientPhotoRecords(for: entry.assets)
    }

    private var savedBodyText: String? {
        guard let text = savedRecord?.bodyText.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpenDetail) {
                Text(entry.date.formatted(date: .long, time: .omitted))
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.date.formatted(date: .long, time: .omitted))

            OnThisDayPhotoGrid(assets: entry.assets) { index in
                photoGallery = PhotoGallerySession(initialIndex: index)
            }

            Button(action: onOpenDetail) {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        if let savedBodyText {
                            Text(verbatim: savedBodyText)
                                .foregroundStyle(HetkiaPalette.ink)
                        } else {
                            Text("photos.journal.empty")
                                .foregroundStyle(HetkiaPalette.secondaryInk)
                        }
                    }
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Text(savedBodyText == nil ? "onthisday.home.write-journal" : "onthisday.home.read-journal")
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(HetkiaPalette.ink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
#if os(macOS)
        .sheet(item: $photoGallery) { session in
            PhotoFullScreenGallery(photos: galleryPhotos, initialIndex: session.initialIndex)
                .frame(minWidth: 760, minHeight: 620)
        }
#else
        .fullScreenCover(item: $photoGallery) { session in
            PhotoFullScreenGallery(photos: galleryPhotos, initialIndex: session.initialIndex)
        }
#endif
    }
}

private struct OnThisDayPhotoGrid: View {
    let assets: [PHAsset]
    let onPhotoSelected: (Int) -> Void
    private let gap: CGFloat = 5

    private var photos: [PHAsset] { JournalPhotoSelection.displayAssets(from: assets) }
    private var heightRatio: CGFloat {
        PhotoMosaicLayout.height(width: 1_000, count: photos.count, gap: gap) / 1_000
    }

    var body: some View {
        GeometryReader { geometry in
            let tiles = PhotoMosaicLayout.tiles(width: geometry.size.width, count: photos.count, gap: gap)
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    Button {
                        onPhotoSelected(tile.index)
                    } label: {
                        assetTile(photos[tile.index], width: tile.rect.width, height: tile.rect.height)
                    }
                    .buttonStyle(.plain)
                    .frame(width: tile.rect.width, height: tile.rect.height)
                    .position(x: tile.rect.midX, y: tile.rect.midY)
                    .accessibilityLabel(Text("photos.open.fullscreen"))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .aspectRatio(1 / heightRatio, contentMode: .fit)
        .background(Color.clear)
    }

    private func assetTile(_ asset: PHAsset, width: CGFloat, height: CGFloat) -> some View {
        OnThisDayAssetThumbnail(asset: asset, tileWidth: width)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct OnThisDayAssetThumbnail: View {
    let asset: PHAsset
    let tileWidth: CGFloat
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    HetkiaPalette.page.overlay {
                        Image(systemName: asset.mediaType == .video ? "play.rectangle" : "photo")
                            .foregroundStyle(HetkiaPalette.secondaryInk.opacity(0.7))
                    }
                }
            }
            if asset.mediaType == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(11)
                    .background(.black.opacity(0.48), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .background(Color.clear)
        .task(id: "\(asset.localIdentifier)-\(Int(tileWidth * displayScale))") {
            let targetSize = CGSize(width: tileWidth * displayScale, height: tileWidth * displayScale)
            image = await PhotoAssetResolver.previewImage(for: asset, targetSize: targetSize)
        }
    }

    @Environment(\.displayScale) private var displayScale
}
