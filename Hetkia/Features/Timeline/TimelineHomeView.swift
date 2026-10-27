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

enum TimelineBrowseMode: Equatable { case all, year, month }

struct TimelineHomeView: View {
    @AppStorage(PhotoAssetEligibility.includeScreenshotsDefaultsKey, store: PhotoAssetEligibility.sharedDefaults) private var includeScreenshotsAndScreenRecordings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalRecord.localDay, order: .reverse) private var savedRecords: [JournalRecord]
    @State private var entries: [OnThisDayEntry] = []
    @State private var path: [String] = []
    @State private var isLoading = true
    @State private var hasResolvedInitialCache = false
    @State private var progress = 0.0
    @State private var isRefreshing = false
    @State private var showsScanProgress = false
    @State private var didLeaveActiveState = false
    @State private var showSettings = false
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if !PhotoLibraryService.hasFullReadAccess {
                            permissionState
                        } else if isLoading {
                            if showsScanProgress {
                                loadingState
                            } else {
                                Color.clear.frame(height: 54)
                            }
                        } else {
                            if showsScanProgress {
                                loadingState
                            }
                            if entries.isEmpty {
                                emptyOnThisDayState
                            } else {
                                LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
                                    ForEach(entries) { entry in
                                        Button { path.append(entry.id) } label: {
                                            OnThisDayCard(entry: entry)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(entry.date.formatted(date: .long, time: .omitted))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 1_100)
                    .frame(maxWidth: .infinity)
                }
                .background(HetkiaPalette.paper.ignoresSafeArea())
                .refreshable { await refresh(forceFullScan: true) }
                .navigationDestination(for: String.self) { dayKey in
                    if let entry = entries.first(where: { $0.id == dayKey }) {
                        let existing = savedRecords.filter { $0.dayKey == dayKey }.max { $0.updatedAt < $1.updatedAt }
                        let record = existing ?? JournalRecord(dayKey: dayKey, localDay: entry.date, source: .manual)
                        PersistentJournalDetailView(record: record, liveAssets: entry.assets, isTransient: existing == nil)
                    } else {
                        ContentUnavailableView("onthisday.empty", systemImage: "calendar")
                    }
                }
                #if !os(macOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
            }
        }
        .tint(HetkiaPalette.amber)
        .sheet(isPresented: $showSettings) { SettingsView() }
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
            guard url.scheme == "hetkia", url.host == "onthisday" else { return }
            let key = url.pathComponents.dropFirst().joined(separator: "/")
            if entries.contains(where: { $0.id == key }) { path = [key] }
            else { pendingWidgetRoute = key; Task { await refresh() } }
        }
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
            WidgetCenter.shared.reloadTimelines(ofKind: "Hetkia.OnThisDay")
        }
        if let pendingWidgetRoute, entries.contains(where: { $0.id == pendingWidgetRoute }) {
            path = [pendingWidgetRoute]
            self.pendingWidgetRoute = nil
        }
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

    var body: some View {
        OnThisDayPhotoGrid(assets: entry.assets, date: entry.date)
        .aspectRatio(1, contentMode: .fit)
        .background(HetkiaPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct OnThisDayPhotoGrid: View {
    let assets: [PHAsset]
    let date: Date
    @Environment(\.displayScale) private var displayScale
    private let gap: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let photos = JournalPhotoSelection.selectedAssets(from: assets)
            let count = photos.count
            Group {
                if count == 1, let photo = photos.first {
                    assetTile(photo, width: geometry.size.width, height: geometry.size.height, showsDate: true)
                } else if count == 9 {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 3), spacing: gap) {
                        ForEach(Array(photos.enumerated()), id: \.element.localIdentifier) { _, photo in
                            let tileWidth = max(1, (geometry.size.width - gap * 2) / 3)
                            let tileHeight = max(1, (geometry.size.height - gap * 2) / 3)
                            assetTile(photo, width: tileWidth, height: tileHeight, showsDate: photo.localIdentifier == photos.first?.localIdentifier)
                        }
                    }
                } else {
                    let columns = count >= 7 ? 3 : 2
                    let rows = max(1, Int(ceil(Double(max(count - 1, 0)) / Double(columns))))
                    let heroHeight = geometry.size.height * (count == 3 ? 0.64 : 0.44)
                    let tileHeight = max(1, (geometry.size.height - heroHeight - CGFloat(rows) * gap) / CGFloat(rows))
                    VStack(spacing: gap) {
                        if let hero = photos.first { assetTile(hero, width: geometry.size.width, height: heroHeight, showsDate: true) }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), spacing: gap) {
                            ForEach(Array(photos.dropFirst().enumerated()), id: \.element.localIdentifier) { _, asset in
                                let width = max(1, (geometry.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
                                assetTile(asset, width: width, height: tileHeight)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.clear)
    }

    private func assetTile(_ asset: PHAsset, width: CGFloat, height: CGFloat, showsDate: Bool = false) -> some View {
        OnThisDayAssetThumbnail(asset: asset, tileWidth: width)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                if showsDate {
                    ZStack(alignment: .topLeading) {
                        LinearGradient(
                            colors: [.black.opacity(0.52), .black.opacity(0.12), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        Text(date.formatted(date: .long, time: .omitted))
                            .font(.system(size: min(17, max(10, width * 0.043)), weight: .semibold, design: .serif))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                            .padding(min(16, max(8, width * 0.04)))
                    }
                    .frame(width: width, height: height, alignment: .topLeading)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
