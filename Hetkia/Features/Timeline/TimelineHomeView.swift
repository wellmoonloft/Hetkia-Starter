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
                                        let saved = savedRecords
                                            .filter { $0.dayKey == entry.id }
                                            .max { $0.updatedAt < $1.updatedAt }
                                        OnThisDayCard(entry: entry, savedRecord: saved) {
                                            path.append(entry.id)
                                        }
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
