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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalRecord.localDay, order: .reverse) private var savedRecords: [JournalRecord]
    @State private var entries: [OnThisDayEntry] = []
    @State private var path: [String] = []
    @State private var isLoading = true
    @State private var progress = 0.0
    @State private var showSettings = false
    @State private var activeCalendarDay = PhotoDayGrouping.key(for: .now)
    @State private var pendingWidgetRoute: String?
    private let minuteTicker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !PhotoLibraryService.hasFullReadAccess {
                        permissionState
                    } else if isLoading {
                        loadingState
                    } else if entries.isEmpty {
                        emptyOnThisDayState
                    } else {
                        LazyVStack(spacing: 16) {
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
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(HetkiaPalette.paper.ignoresSafeArea())
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
        .tint(HetkiaPalette.amber)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            PhotoLocationResolver.shared.resumePending(context: modelContext)
            await refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                PhotoLocationResolver.shared.resumePending(context: modelContext)
                Task { await refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hetkiaJournalRecordsDidChange)) { _ in
            // PhotoKit remains the source of truth; a detail commit can add a saved
            // journal without freezing the next year's matching photos.
            Task { await refresh() }
        }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { Task { await refresh() } }
        }
        .onReceive(minuteTicker) { _ in
            let newDay = PhotoDayGrouping.key(for: .now)
            if newDay != activeCalendarDay {
                activeCalendarDay = newDay
                Task { await refresh() }
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
    private func refresh() async {
        guard PhotoLibraryService.hasFullReadAccess else {
            entries = []
            isLoading = false
            return
        }

        // Restore the last successful metadata snapshot immediately after launch.
        // The fresh PhotoKit query below then adds newly imported photos or removes
        // assets that are no longer available, and atomically replaces the cache.
        if let cachedEntries = OnThisDayCacheStore.load() {
            entries = cachedEntries
        } else if PhotoDayGrouping.key(for: .now) != activeCalendarDay {
            entries = []
        }
        isLoading = entries.isEmpty
        progress = 0
        let result = await OnThisDayLibrary.fetch { progress = $0 }
        guard !Task.isCancelled else { return }
        entries = result
        isLoading = false
        WidgetCenter.shared.reloadTimelines(ofKind: "Hetkia.OnThisDay")
        if let pendingWidgetRoute, result.contains(where: { $0.id == pendingWidgetRoute }) {
            path = [pendingWidgetRoute]
            self.pendingWidgetRoute = nil
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
        ZStack(alignment: .topLeading) {
            OnThisDayPhotoGrid(assets: entry.assets)

            LinearGradient(
                colors: [.black.opacity(0.52), .black.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            Text(entry.date.formatted(date: .long, time: .omitted))
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                .padding(16)
                .allowsHitTesting(false)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct OnThisDayPhotoGrid: View {
    let assets: [PHAsset]
    private let gap: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let photos = JournalPhotoSelection.selectedAssets(from: assets)
            let count = photos.count
            Group {
                if count == 1, let photo = photos.first {
                    assetTile(photo, width: geometry.size.width, height: geometry.size.height)
                } else if count == 9 {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 3), spacing: gap) {
                        ForEach(Array(photos.enumerated()), id: \.element.localIdentifier) { _, photo in
                            let tileWidth = max(1, (geometry.size.width - gap * 2) / 3)
                            let tileHeight = max(1, (geometry.size.height - gap * 2) / 3)
                            assetTile(photo, width: tileWidth, height: tileHeight)
                        }
                    }
                } else {
                    let columns = count >= 7 ? 3 : 2
                    let rows = max(1, Int(ceil(Double(max(count - 1, 0)) / Double(columns))))
                    let heroHeight = geometry.size.height * (count == 3 ? 0.64 : 0.44)
                    let tileHeight = max(1, (geometry.size.height - heroHeight - CGFloat(rows) * gap) / CGFloat(rows))
                    VStack(spacing: gap) {
                        if let hero = photos.first { assetTile(hero, width: geometry.size.width, height: heroHeight) }
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
        .background(HetkiaPalette.page)
    }

    private func assetTile(_ asset: PHAsset, width: CGFloat, height: CGFloat) -> some View {
        OnThisDayAssetThumbnail(asset: asset)
            .frame(width: width, height: height)
            .clipped()
    }
}

private struct OnThisDayAssetThumbnail: View {
    let asset: PHAsset
    @State private var image: CGImage?

    var body: some View {
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
        .task(id: asset.localIdentifier) {
            image = await PhotoAssetResolver.previewImage(for: asset, targetSize: CGSize(width: 900, height: 900))
        }
    }
}
