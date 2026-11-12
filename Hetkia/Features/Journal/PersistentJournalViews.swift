import SwiftUI
import SwiftData
import CoreGraphics
import ImageIO
import CoreLocation
import MapKit
import OSLog
import Photos
import AVKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum MapCoordinateSystemPreference: String, CaseIterable {
    case system
    case wgs84
    case gcj02

    static let defaultsKey = "hetkia.mapCoordinateSystem"

    var convertsWGS84ToGCJ02: Bool {
        switch self {
        case .system:
            Locale.autoupdatingCurrent.region?.identifier.uppercased() == "CN"
        case .wgs84:
            false
        case .gcj02:
            true
        }
    }
}

private enum MapCoordinateConverter {
    static func displayCoordinate(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let rawValue = UserDefaults.standard.string(forKey: MapCoordinateSystemPreference.defaultsKey)
        let preference = rawValue.flatMap(MapCoordinateSystemPreference.init(rawValue:)) ?? .system
        guard CLLocationCoordinate2DIsValid(coordinate),
              preference.convertsWGS84ToGCJ02,
              (0.8293...55.8271).contains(coordinate.latitude),
              (72.004...137.8347).contains(coordinate.longitude) else {
            return coordinate
        }

        let a = 6_378_245.0
        let eccentricitySquared = 0.00669342162296594323
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        let latitudeDelta = transformLatitude(longitude - 105.0, latitude - 35.0)
        let longitudeDelta = transformLongitude(longitude - 105.0, latitude - 35.0)
        let radians = latitude / 180.0 * .pi
        let magic = 1.0 - eccentricitySquared * sin(radians) * sin(radians)
        let rootMagic = sqrt(magic)
        let adjustedLatitude = latitudeDelta * 180.0 / ((a * (1.0 - eccentricitySquared)) / (magic * rootMagic) * .pi)
        let adjustedLongitude = longitudeDelta * 180.0 / (a / rootMagic * cos(radians) * .pi)
        return CLLocationCoordinate2D(latitude: latitude + adjustedLatitude, longitude: longitude + adjustedLongitude)
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var value = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        value += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        value += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        value += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return value
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var value = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        value += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        value += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        value += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return value
    }
}

struct PersistentJournalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var record: JournalRecord
    private let savedOnly: Bool
    @State private var displayPhotos: [JournalPhotoRecord]
    @State private var hasPersistedRecord: Bool
    @State private var isGenerating = false
    @State private var notice: String?
    @State private var isEditingDiary = false
    @State private var editingPostID: UUID?
    @State private var deletingPostID: UUID?
    @State private var editDraft = ""
    @State private var newMessage = ""
    @State private var photoGallery: PhotoGallerySession?
    @State private var mapDestination: PhotoMapDestination?
    @State private var sharePayload: ShareImagePayload?
    @State private var showsSharePhotoPicker = false
    @State private var sharePhotoIDs = Set<UUID>()
    @State private var pendingGeneratedDraft: String?
    @State private var isPreparingShare = false
    @State private var showDraftReplacementConfirmation = false
    @State private var showDeleteConfirmation = false
    @FocusState private var focusedInput: InputTarget?
    @ScaledMetric(relativeTo: .body) private var bodyFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .headline) private var headingFontSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption) private var captionFontSize: CGFloat = 12

    private enum InputTarget: Hashable { case diary, edit(UUID), compose }
    private var selectedPhotos: [JournalPhotoRecord] { JournalPhotoSelection.displayPhotos(from: displayPhotos) }
    private var posts: [JournalMessagePost] {
        record.messagePosts
            .filter { $0.kind == .note }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var shareBody: String {
        diaryText ?? ""
    }
    private var diaryText: String? {
        if !record.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return record.bodyText
        }
        return record.messagePosts.last(where: { $0.kind == .automatic })?.text
    }
    private var locationCities: [JournalLocationItem] {
        var seen = Set<String>()
        return selectedPhotos.compactMap { photo in
            guard let latitude = photo.latitude, let longitude = photo.longitude else { return nil }
            let storedName = photo.placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = storedName.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(format: "%.5f, %.5f", latitude, longitude)
            let key: String
            if storedName?.isEmpty == false {
                key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .components(separatedBy: .whitespacesAndNewlines).joined()
            } else {
                // Keep unresolved photos at their actual coordinate until a name is found.
                key = String(format: "%.5f,%.5f", latitude, longitude)
            }
            guard seen.insert(key).inserted else { return nil }
            return JournalLocationItem(name: name, photo: photo)
        }
    }
    private var resolvedLocationText: String? {
        let places = selectedPhotos.compactMap(\.placeName).filter { !$0.isEmpty }
        var uniquePlaces: [String] = []
        for place in places where !uniquePlaces.contains(place) { uniquePlaces.append(place) }
        let text = uniquePlaces.prefix(2).joined(separator: " · ")
        if !text.isEmpty { return text }
        return record.locationText?.isEmpty == false ? record.locationText : nil
    }
    private var mapPhoto: JournalPhotoRecord? {
        selectedPhotos.first { $0.latitude != nil && $0.longitude != nil }
    }
    private var displayedCaptureDate: Date {
        selectedPhotos.first?.capturedAt ?? record.localDay
    }

    init(record: JournalRecord, liveAssets: [PHAsset] = [], isTransient: Bool = false, savedOnly: Bool = false) {
        self.record = record
        self.savedOnly = savedOnly
        self._hasPersistedRecord = State(initialValue: !isTransient)
        var photos = record.photos
        let knownIdentifiers = Set(photos.compactMap(\.assetLocalIdentifier))
        let fresh = OnThisDayLibrary.transientPhotoRecords(for: liveAssets)
            .filter { $0.assetLocalIdentifier.map { !knownIdentifiers.contains($0) } ?? true }
        photos.append(contentsOf: fresh)
        self._displayPhotos = State(initialValue: photos)
    }

    var body: some View {
        GeometryReader { viewport in
            let pageWidth = min(max(viewport.size.width - 36, 1), 520)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 18) {
                        persistentPage(photoAreaWidth: pageWidth - 24)
                            .frame(width: pageWidth)
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 18, y: 8)
                        actionPanel.frame(width: pageWidth)
                        if let draft = pendingGeneratedDraft {
                            generatedDraftCard(draft).frame(width: pageWidth)
                        }
                        messageBoard.frame(width: pageWidth)
                    }
                    .frame(width: viewport.size.width)
                    .padding(.top, 12).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedInput) { _, target in
                    guard let target else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        switch target {
                        case .diary: withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("diary-editor", anchor: .center) }
                        case .edit(let id): withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                        case .compose: withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("message-composer", anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .background(HetkiaPalette.paper.ignoresSafeArea())
        .task {
            discardUnappliedLegacyDraft()
            resolvePhotoLocations()
        }
        .navigationTitle(Text(displayedCaptureDate.formatted(.dateTime.year().month(.wide).day().hour().minute())))
        .toolbar {
            if hasPersistedRecord {
              ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(Text("journal.delete.action"))
              }
            }
        }
#if os(macOS)
        .sheet(item: $photoGallery) { session in
            PhotoFullScreenGallery(photos: selectedPhotos, initialIndex: session.initialIndex)
                .frame(minWidth: 760, minHeight: 620)
        }
#else
        .fullScreenCover(item: $photoGallery) { session in
            PhotoFullScreenGallery(photos: selectedPhotos, initialIndex: session.initialIndex)
        }
#endif
        .sheet(item: $mapDestination) { destination in
            PhotoLocationMapView(destination: destination)
#if os(macOS)
                .frame(minWidth: 520, minHeight: 420)
#else
                .presentationDetents([.medium, .large])
#endif
        }
        .sheet(isPresented: $showsSharePhotoPicker) {
            SharePhotoSelectionView(
                photos: selectedPhotos,
                selectedPhotoIDs: $sharePhotoIDs,
                onCancel: { showsSharePhotoPicker = false },
                onCreate: {
                    let photos = selectedPhotos.filter { sharePhotoIDs.contains($0.id) }
                    showsSharePhotoPicker = false
                    Task { await prepareShareImage(using: photos) }
                }
            )
        }
#if os(iOS)
        .sheet(item: $sharePayload) { payload in
            JournalActivityShareSheet(image: UIImage(cgImage: payload.image))
        }
#elseif os(macOS)
        .sheet(item: $sharePayload) { payload in
            ShareLink(item: payload.url) {
                Label("detail.share", systemImage: "square.and.arrow.up")
                    .padding(24)
            }
            .frame(minWidth: 240, minHeight: 100)
        }
#endif
        .alert("photos.generate.status", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("common.ok", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        .confirmationDialog("journal.delete.confirm-title", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("journal.delete.action", role: .destructive, action: deleteJournal)
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("journal.delete.confirm-detail")
        }
    }

    private func persistentPage(photoAreaWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("page.footer")
                Spacer(minLength: 8)
                Text("brand.name")
            }
            .font(.system(size: captionFontSize, design: .serif))
            .foregroundStyle(HetkiaPalette.secondaryInk)
            .padding(.top, 24)
            .padding(.bottom, 20)

            persistentPhotoGrid(width: photoAreaWidth)
            if !record.title.isEmpty {
                Text(verbatim: record.title)
                    .font(.system(size: headingFontSize, design: .serif))
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }
            Group {
                if isEditingDiary {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $editDraft)
                            .focused($focusedInput, equals: .diary)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: bodyFontSize))
                            .frame(minHeight: 100, maxHeight: 240)
                            .padding(8)
                            .background(HetkiaPalette.paper, in: RoundedRectangle(cornerRadius: 12))
                        HStack {
                            Button("journal.message.cancel") { cancelDiaryEditing() }
                                .foregroundStyle(HetkiaPalette.secondaryInk)
                            Spacer()
                            Button("journal.message.save") { saveDiaryText() }
                                .foregroundStyle(HetkiaPalette.amber)
                                .disabled(editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(verbatim: diaryText ?? HetkiaSystemLanguage.localizedString("photos.journal.empty", comment: "Empty journal"))
                            .font(.system(size: bodyFontSize))
                            .lineSpacing(4)
                            .foregroundStyle(HetkiaPalette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Spacer()
                            Button {
                                editDraft = diaryText ?? ""
                                isEditingDiary = true
                                focusedInput = .diary
                            } label: {
                                Label("journal.message.edit", systemImage: "pencil")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(HetkiaPalette.secondaryInk)
                        }
                    }
                }
            }
            .padding(.top, record.title.isEmpty ? 12 : 0)
            .id("diary-editor")
            if let mood = record.moodText, !mood.isEmpty {
                Label(mood, systemImage: "heart")
                    .font(.system(size: captionFontSize))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                    .padding(.top, 8)
            }
            if !locationCities.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(locationCities) { item in
                        Button {
                            openMap(for: item.photo, title: item.name)
                        } label: {
                            Label(item.name, systemImage: "mappin.and.ellipse")
                                .font(.system(size: captionFontSize)).foregroundStyle(HetkiaPalette.secondaryInk)
                        }
                        .buttonStyle(.plain).contentShape(Rectangle())
                    }
                }
                .padding(.top, 8)
            } else if let location = resolvedLocationText {
                if let mapPhoto {
                    Button {
                        openMap(for: mapPhoto, title: location)
                    } label: {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.system(size: captionFontSize)).foregroundStyle(HetkiaPalette.secondaryInk)
                    }
                    .buttonStyle(.plain).contentShape(Rectangle()).padding(.top, 8)
                } else {
                    Label(location, systemImage: "mappin").font(.system(size: captionFontSize)).foregroundStyle(HetkiaPalette.secondaryInk).padding(.top, 8)
                }
            } else if selectedPhotos.contains(where: { $0.locationStatus == .available }) {
                Label("photos.location.metadata-present", systemImage: "location").font(.system(size: captionFontSize)).foregroundStyle(HetkiaPalette.secondaryInk).padding(.top, 8)
            }
        }
        .foregroundStyle(HetkiaPalette.ink).padding(.horizontal, 12).padding(.bottom, 12)
        .background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func persistentPhotoGrid(width: CGFloat) -> some View {
        let photos = selectedPhotos
        let height = PhotoMosaicLayout.height(width: max(1, width), count: photos.count, gap: 5)
        return GeometryReader { geometry in
            let gap: CGFloat = 5
            let tiles = PhotoMosaicLayout.tiles(width: geometry.size.width, count: photos.count, gap: gap)
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    photoTile(photos[tile.index], index: tile.index, width: tile.rect.width, height: tile.rect.height)
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .frame(height: max(1, height))
    }

    @MainActor
    private func openMap(for photo: JournalPhotoRecord, title: String) {
        guard let latitude = photo.latitude, let longitude = photo.longitude else { return }
        var coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        // Prefer PhotoKit's current coordinate for this exact asset. The persisted
        // full-precision value remains the fallback when the original is unavailable.
        if let identifier = photo.assetLocalIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
           let liveCoordinate = asset.location?.coordinate,
           CLLocationCoordinate2DIsValid(liveCoordinate) {
            coordinate = liveCoordinate
        }
        mapDestination = PhotoMapDestination(
            coordinate: MapCoordinateConverter.displayCoordinate(for: coordinate),
            title: title
        )
    }

    private func photoTile(_ photo: JournalPhotoRecord, index: Int, width: CGFloat, height: CGFloat) -> some View {
        Group {
            PhotoFallbackThumbnail(photo: photo, width: width, height: height, showsVideoIndicator: false) {
                photoGallery = PhotoGallerySession(initialIndex: index)
            }
        }
        // Keep both the rendered media and its tap target inside this collage cell.
        // Tall portrait video posters can otherwise draw outside their fixed tile.
        .frame(width: width, height: height, alignment: .center)
        .clipped()
        .overlay {
            if photo.mediaType == "video" {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(11)
                    .background(.black.opacity(0.48), in: Circle())
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    guard !selectedPhotos.isEmpty else {
                        notice = HetkiaSystemLanguage.localizedString("photos.generate.needs-photos", comment: "")
                        return
                    }
                    sharePhotoIDs = Set(selectedPhotos.map(\.id))
                    showsSharePhotoPicker = true
                } label: {
                    Label(isPreparingShare ? "photos.generating" : "detail.share", systemImage: isPreparingShare ? "hourglass" : "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HetkiaPalette.ink).frame(maxWidth: .infinity).frame(height: 48)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isPreparingShare)
                actionButton(isGenerating ? "photos.generating" : "photos.generate", symbol: "sparkles") { Task { await generateDraft() } }
                    .disabled(isGenerating || record.generationStatus == .processing)
            }
        }.frame(maxWidth: 520)
    }

    @MainActor
    private func prepareShareImage(using photos: [JournalPhotoRecord]) async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        guard !photos.isEmpty else {
            notice = HetkiaSystemLanguage.localizedString("photos.generate.needs-photos", comment: "")
            return
        }
        var images: [CGImage] = []
        for photo in photos {
            let targetSize = CGSize(width: 1200, height: 1200)
            let image: CGImage?
            if savedOnly {
                image = await PhotoAssetResolver.thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: targetSize)
            } else {
                image = await PhotoAssetResolver.displayImage(for: photo, targetSize: targetSize)
            }
            if let image {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            notice = HetkiaSystemLanguage.localizedString("detail.share.failed", comment: "Could not create share image")
            return
        }

        let card = JournalShareCard(
            date: displayedCaptureDate.formatted(.dateTime.year().month(.wide).day().hour().minute()),
            title: record.title,
            diaryText: shareBody,
            locations: uniqueLocationNames(in: photos),
            photos: images
        )
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: 1080, height: nil)
        renderer.scale = 3
        guard let image = renderer.cgImage else {
            notice = HetkiaSystemLanguage.localizedString("detail.share.failed", comment: "Could not create share image")
            return
        }
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hetkia-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, "public.png" as CFString, 1, nil) else {
            notice = HetkiaSystemLanguage.localizedString("detail.share.failed", comment: "Could not create share image")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            notice = HetkiaSystemLanguage.localizedString("detail.share.failed", comment: "Could not create share image")
            return
        }
        sharePayload = ShareImagePayload(image: image, url: imageURL)
    }

    private func uniqueLocationNames(in photos: [JournalPhotoRecord]) -> [String] {
        var seen = Set<String>()
        return photos.compactMap { photo in
            guard let name = photo.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  seen.insert(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
            else { return nil }
            return name
        }
    }

    private var messageBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("journal.message.board", systemImage: "text.bubble").font(.system(size: 15, weight: .semibold, design: .serif))
                Spacer()
            }
            if posts.isEmpty {
                Text("journal.message.empty").font(.system(size: 13)).foregroundStyle(HetkiaPalette.secondaryInk).padding(.vertical, 6)
            }
            ForEach(posts) { post in
                messagePost(post)
                    .id(post.id)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("journal.message.new-note").font(.system(size: 11, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                TextEditor(text: $newMessage)
                    .focused($focusedInput, equals: .compose)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: bodyFontSize))
                    .frame(minHeight: 88, maxHeight: 170)
                    .padding(8)
                    .background(HetkiaPalette.paper, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if newMessage.isEmpty { Text("journal.message.placeholder").font(.system(size: bodyFontSize)).foregroundStyle(HetkiaPalette.secondaryInk.opacity(0.65)).padding(.horizontal, 13).padding(.vertical, 17).allowsHitTesting(false) }
                    }
                HStack {
                    Spacer()
                    Button("journal.message.post") { addMessage() }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(HetkiaPalette.ink)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .background(HetkiaPalette.amber.opacity(0.28), in: Capsule())
                        .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .id("message-composer")
        }
        .padding(16).background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func messagePost(_ post: JournalMessagePost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                Text("journal.message.note")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                Spacer()
                Text(post.createdAt.formatted(date: .numeric, time: .shortened)).font(.system(size: 10, design: .rounded)).foregroundStyle(HetkiaPalette.secondaryInk)
            }
            if editingPostID == post.id {
                TextEditor(text: $editDraft)
                    .focused($focusedInput, equals: .edit(post.id))
                    .scrollContentBackground(.hidden).font(.system(size: bodyFontSize))
                    .frame(minHeight: 100, maxHeight: 240).padding(8)
                    .background(HetkiaPalette.paper, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("journal.message.cancel") { cancelEditing() }.foregroundStyle(HetkiaPalette.secondaryInk)
                    Spacer()
                    Button("journal.message.save") { saveEditedPost(post) }.foregroundStyle(HetkiaPalette.amber)
                }.font(.system(size: 12, weight: .medium))
            } else {
                Text(verbatim: post.text).font(.system(size: bodyFontSize)).lineSpacing(4).foregroundStyle(HetkiaPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer()
                    Button { editDraft = post.text; editingPostID = post.id; focusedInput = .edit(post.id) } label: {
                        Label("journal.message.edit", systemImage: "pencil").font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(HetkiaPalette.secondaryInk)
                    Button(role: .destructive) { deletingPostID = post.id } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                    .accessibilityLabel(Text("journal.message.delete"))
                }
            }
        }
        .padding(13).background(HetkiaPalette.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 13))
        .confirmationDialog(
            Text(willDeleteJournalAfterRemoving(post)
                ? "journal.message.delete-journal.confirm-title"
                : "journal.message.delete.confirm-title"),
            isPresented: Binding(
                get: { deletingPostID == post.id },
                set: { if !$0 && deletingPostID == post.id { deletingPostID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("journal.message.delete", role: .destructive) { deletePost(post) }
            Button("common.cancel", role: .cancel) { deletingPostID = nil }
        } message: {
            Text(willDeleteJournalAfterRemoving(post)
                ? "journal.message.delete-journal.confirm-detail"
                : "journal.message.delete.confirm-detail")
        }
    }

    private func generatedDraftCard(_ draft: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("photos.draft.title", systemImage: "sparkles").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            Text(verbatim: draft).font(.system(size: bodyFontSize)).lineSpacing(4).foregroundStyle(HetkiaPalette.secondaryInk).frame(maxWidth: .infinity, alignment: .leading)
            Button("photos.draft.use") {
                let currentBody = record.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                if currentBody.isEmpty {
                    applyGeneratedDraft(draft)
                } else {
                    showDraftReplacementConfirmation = true
                }
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
        }.padding(16).background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 16))
            .confirmationDialog(
                "photos.draft.replace.title",
                isPresented: $showDraftReplacementConfirmation,
                titleVisibility: .visible
            ) {
                Button("photos.draft.replace.confirm", role: .destructive) {
                    applyGeneratedDraft(draft)
                }
                Button("common.cancel", role: .cancel) { }
            } message: {
                Text("photos.draft.replace.message")
            }
    }

    private func applyGeneratedDraft(_ draft: String) {
        Task {
            await commitJournalForUserAction()
            record.bodyText = draft
            record.bodyWasEdited = false
            record.aiDraftBody = nil
            pendingGeneratedDraft = nil
            record.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(HetkiaPalette.ink).frame(maxWidth: .infinity).frame(height: 48)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func resolvePhotoLocations() {
        PhotoLocationResolver.shared.enqueue(photos: selectedPhotos, record: record, context: modelContext)
    }

    private func cancelDiaryEditing() {
        isEditingDiary = false
        editDraft = ""
        focusedInput = nil
    }

    private func saveDiaryText() {
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            await commitJournalForUserAction()
            record.bodyText = text
            record.bodyWasEdited = true
            record.updatedAt = .now
            try? modelContext.save()
            isEditingDiary = false
            editDraft = ""
            focusedInput = nil
        }
    }

    @MainActor
    private func commitJournalForUserAction() async {
        if !record.storageKey.contains("|") {
            // Defer legacy-key migration until an explicit user save operation.
            record.storageKey = "\(record.dayKey)|\(record.source.rawValue)"
        }
        if !hasPersistedRecord {
            modelContext.insert(record)
            hasPersistedRecord = true
        }
        guard !savedOnly else {
            record.updatedAt = .now
            try? modelContext.save()
            return
        }
        var existingByIdentifier = Dictionary(
            record.photos.compactMap { photo in photo.assetLocalIdentifier.map { ($0, photo) } },
            uniquingKeysWith: { first, _ in first }
        )
        for photo in selectedPhotos {
            if let identifier = photo.assetLocalIdentifier, let storedPhoto = existingByIdentifier[identifier] {
                // A saved diary can gain new matching-day photos next year. Keep its
                // old links, and only fill a missing owned preview on explicit action.
                if storedPhoto.thumbnailRelativePath.isEmpty,
                   let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
                   let path = try? await PhotoAssetResolver.persistThumbnail(for: asset) {
                    storedPhoto.thumbnailRelativePath = path
                }
                continue
            }
            photo.journal = record
            record.photos.append(photo)
            modelContext.insert(photo)
            if let identifier = photo.assetLocalIdentifier {
                existingByIdentifier[identifier] = photo
                if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
                   let path = try? await PhotoAssetResolver.persistThumbnail(for: asset) {
                    photo.thumbnailRelativePath = path
                }
            }
        }
        record.updatedAt = .now
        try? modelContext.save()
        resolvePhotoLocations()
    }

    private func appendPost(text: String, kind: JournalMessagePost.Kind, createdAt: Date = .now) {
        var updated = record.messagePosts
        updated.append(JournalMessagePost(text: text, createdAt: createdAt, kind: kind))
        record.messagePosts = updated
    }

    private func deleteJournal() {
        let thumbnailPaths = Set(record.photos.map(\.thumbnailRelativePath).filter { !$0.isEmpty })
        let tasks = (try? modelContext.fetch(FetchDescriptor<JournalGenerationTask>())) ?? []
        for task in tasks where task.journal?.persistentModelID == record.persistentModelID {
            modelContext.delete(task)
        }
        modelContext.delete(record)
        do {
            try modelContext.save()
            for path in thumbnailPaths {
                if let url = try? PhotoAssetResolver.thumbnailURL(relativePath: path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            dismiss()
        } catch {
            modelContext.rollback()
            notice = error.localizedDescription
        }
    }

    private func addMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let postedAt = Date.now
        Task {
            await commitJournalForUserAction()
            appendPost(text: text, kind: .note, createdAt: postedAt)
            newMessage = ""
            try? modelContext.save()
        }
    }

    private func saveEditedPost(_ post: JournalMessagePost) {
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
        await commitJournalForUserAction()
        var updated = record.messagePosts
        if updated.isEmpty { updated = posts }
        guard let index = updated.firstIndex(where: { $0.id == post.id }) else { return }
        updated[index].text = text
        record.messagePosts = updated
        record.updatedAt = .now
        try? modelContext.save()
        editingPostID = nil
        focusedInput = nil
        }
    }

    private func deletePost(_ post: JournalMessagePost) {
        var updated = record.messagePosts
        guard let index = updated.firstIndex(where: { $0.id == post.id && $0.kind == .note }) else { return }
        updated.remove(at: index)
        if shouldDeleteJournal(afterRemoving: post, remainingPosts: updated) {
            deleteJournal()
            return
        }
        record.messagePosts = updated
        record.updatedAt = .now
        do {
            try modelContext.save()
            if editingPostID == post.id { cancelEditing() }
            deletingPostID = nil
        } catch {
            modelContext.rollback()
            notice = error.localizedDescription
        }
    }

    private func willDeleteJournalAfterRemoving(_ post: JournalMessagePost) -> Bool {
        let remainingPosts = record.messagePosts.filter { $0.id != post.id }
        return shouldDeleteJournal(afterRemoving: post, remainingPosts: remainingPosts)
    }

    private func shouldDeleteJournal(afterRemoving post: JournalMessagePost, remainingPosts: [JournalMessagePost]) -> Bool {
        guard post.kind == .note,
              !remainingPosts.contains(where: { $0.kind == .note }) else { return false }
        let hasDiaryBody = !record.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDraft = !(record.aiDraftBody?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasGeneratedText = remainingPosts.contains {
            $0.kind == .automatic && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !hasDiaryBody && !hasDraft && !hasGeneratedText
    }

    private func cancelEditing() { editingPostID = nil; focusedInput = nil; editDraft = "" }

    private func generateDraft() async {
        guard !selectedPhotos.isEmpty else { notice = HetkiaSystemLanguage.localizedString("photos.generate.needs-photos", comment: ""); return }
        guard #available(iOS 26, macOS 26, *) else {
            notice = JournalDraftService.availabilityDescription
            return
        }
        guard JournalDraftService.isAvailable else {
            notice = JournalDraftService.availabilityDescription
            return
        }
        isGenerating = true
        defer { isGenerating = false }
        do {
            var images: [CGImage] = []
            if #available(iOS 27, macOS 27, *) {
                for photo in selectedPhotos {
                    let image: CGImage?
                    if savedOnly {
                        image = await PhotoAssetResolver.thumbnailImage(
                            relativePath: photo.thumbnailRelativePath,
                            targetSize: CGSize(width: 1100, height: 1100)
                        )
                    } else {
                        image = await PhotoAssetResolver.aiImage(for: photo)
                    }
                    if let image { images.append(image) }
                }
            }
            let locationContext = Array(Set(selectedPhotos.compactMap { photo -> String? in
                if let place = photo.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty { return place }
                guard let latitude = photo.latitude, let longitude = photo.longitude else { return nil }
                return String(format: "%.5f, %.5f", latitude, longitude)
            }))
            let photoMetadata = selectedPhotos.enumerated().map { index, photo in
                JournalDraftService.photoMetadata(
                    index: index + 1,
                    capturedAt: photo.capturedAt,
                    placeName: photo.placeName,
                    latitude: photo.latitude,
                    longitude: photo.longitude
                )
            }
            let result = try await JournalDraftService.generate(
                date: record.localDay,
                photoCount: selectedPhotos.count,
                imageSamples: images,
                locationContext: locationContext,
                photoMetadata: photoMetadata
            )
            pendingGeneratedDraft = result.body
        } catch {
            notice = error.localizedDescription
        }
    }

    private func discardUnappliedLegacyDraft() {
        // Older builds persisted generated text before the user tapped Apply.
        // Treat those drafts as abandoned when reopening the journal.
        guard record.aiDraftBody != nil else { return }
        record.aiDraftBody = nil
        try? modelContext.save()
    }
}

private struct PhotoGallerySession: Identifiable {
    let id = UUID()
    let initialIndex: Int
}

private struct PhotoMapDestination: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
}

private struct JournalLocationItem: Identifiable {
    let name: String
    let photo: JournalPhotoRecord
    var id: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}

private struct ShareImagePayload: Identifiable {
    let id = UUID()
    let image: CGImage
    let url: URL
}

private struct SharePhotoSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [JournalPhotoRecord]
    @Binding var selectedPhotoIDs: Set<UUID>
    let onCancel: () -> Void
    let onCreate: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 112), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(photos) { photo in
                        let isSelected = selectedPhotoIDs.contains(photo.id)
                        Button {
                            if isSelected { selectedPhotoIDs.remove(photo.id) }
                            else { selectedPhotoIDs.insert(photo.id) }
                        } label: {
                            GeometryReader { proxy in
                                ZStack(alignment: .topTrailing) {
                                    PhotoFallbackThumbnail(
                                        photo: photo,
                                        width: proxy.size.width,
                                        height: proxy.size.height,
                                        showsVideoIndicator: true
                                    )
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 23, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, isSelected ? HetkiaPalette.amber : .black.opacity(0.35))
                                        .padding(8)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(isSelected ? HetkiaPalette.amber : .clear, lineWidth: 3)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(isSelected ? "share.photos.selected" : "share.photos.unselected"))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(HetkiaPalette.paper.ignoresSafeArea())
            .navigationTitle(Text("share.photos.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("share.photos.select-all") {
                        selectedPhotoIDs = Set(photos.map(\.id))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("share.photos.select-none") { selectedPhotoIDs.removeAll() }
                        .buttonStyle(.bordered)
                    Button("share.photos.create", action: onCreate)
                        .buttonStyle(.borderedProminent)
                        .tint(HetkiaPalette.amber)
                        .disabled(selectedPhotoIDs.isEmpty)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(.regularMaterial)
            }
        }
        .tint(HetkiaPalette.amber)
    }
}

/// Resolves photo coordinates independently of the detail view lifecycle. Requests are
/// grouped by effectively identical coordinates, serialized, cached locally, and retried
/// when a lookup fails or the app is interrupted.
@MainActor
final class PhotoLocationResolver {
    static let shared = PhotoLocationResolver()

    private final class Request {
        let key: String
        let location: CLLocation
        var photos: [JournalPhotoRecord]
        var records: [JournalRecord]
        let context: ModelContext

        init(key: String, location: CLLocation, photos: [JournalPhotoRecord], records: [JournalRecord], context: ModelContext) {
            self.key = key
            self.location = location
            self.photos = photos
            self.records = records
            self.context = context
        }
    }

    private static let groupingRadius: CLLocationDistance = 5_000

    private static let cacheKey = "hetkia.reverseGeocoding.cache.v2"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Hetkia",
        category: "PhotoLocationResolver"
    )

    private var requests: [Request] = []
    private var activeRequest: Request?
    private var worker: Task<Void, Never>?
    private var didResumePendingRequests = false

    private init() { }

    /// Re-queue unresolved photo locations after launch or when the app becomes active.
    /// This runs once per process; newly changed journals enter through enqueue().
    func resumePending(context: ModelContext) {
        guard !didResumePendingRequests else { return }
        guard let journals = try? context.fetch(FetchDescriptor<JournalRecord>()) else { return }
        didResumePendingRequests = true
        for record in journals {
            let unresolved = JournalPhotoSelection.selected(from: record.photos).filter { photo in
                photo.latitude != nil && photo.longitude != nil
                    && Self.needsDetailedPlace(photo.placeName)
            }
            enqueue(photos: unresolved, record: record, context: context)
        }
    }

    func enqueue(photos: [JournalPhotoRecord], record: JournalRecord, context: ModelContext) {
        var didMutateStoredData = false
        let eligible = photos.filter { photo in
            photo.latitude != nil && photo.longitude != nil
                && Self.needsDetailedPlace(photo.placeName)
        }

        for photo in eligible {
            guard let latitude = photo.latitude, let longitude = photo.longitude else { continue }
            let location = CLLocation(latitude: latitude, longitude: longitude)

            if let request = matchingRequest(for: location) {
                didMutateStoredData = add(photo, to: request, record: record) || didMutateStoredData
                continue
            }
            if let cached = cachedPlace(near: location) {
                didMutateStoredData = apply(cached, to: photo, record: record) || didMutateStoredData
                continue
            }

            let request = Request(
                key: Self.key(latitude: latitude, longitude: longitude),
                location: location,
                photos: [photo],
                records: [record],
                context: context
            )
            if photo.locationStatus != .geocodingPending {
                photo.locationStatus = .geocodingPending
                didMutateStoredData = true
            }
            requests.append(request)
        }

        if didMutateStoredData { try? context.save() }
        guard worker == nil, !requests.isEmpty else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await self.processQueue()
        }
    }

    private func processQueue() async {
        defer { worker = nil }
        while !requests.isEmpty, !Task.isCancelled {
            let request = requests.removeFirst()
            activeRequest = request
            if let cached = cachedPlace(near: request.location) {
                finish(request, place: cached)
            } else if let place = await reverseGeocodeWithRetries(request.location) {
                var cache = Self.cache
                cache[request.key] = place
                Self.cache = cache
                finish(request, place: place)
            } else {
                request.photos.forEach { $0.locationStatus = .geocodingFailed }
                try? request.context.save()
                // Keep the existing retry-on-next-foreground behavior for
                // transient network or geocoder failures.
                didResumePendingRequests = false
                NotificationCenter.default.post(name: .hetkiaJournalRecordsDidChange, object: nil)
                Self.logger.error("Reverse geocoding returned no place name; retained photo coordinates for map display.")
            }
            activeRequest = nil
            if !requests.isEmpty {
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func finish(_ request: Request, place: String) {
        request.photos.forEach { $0.placeName = place; $0.locationStatus = .available }
        request.records.forEach { record in
            if Self.needsDetailedPlace(record.locationText) { record.locationText = place }
        }
        try? request.context.save()
        NotificationCenter.default.post(name: .hetkiaJournalRecordsDidChange, object: nil)
    }

    private func matchingRequest(for location: CLLocation) -> Request? {
        if let activeRequest,
           activeRequest.location.distance(from: location) <= Self.groupingRadius {
            return activeRequest
        }
        return requests.first { $0.location.distance(from: location) <= Self.groupingRadius }
    }

    @discardableResult
    private func add(_ photo: JournalPhotoRecord, to request: Request, record: JournalRecord) -> Bool {
        var didMutateStoredData = false
        if !request.photos.contains(where: { $0.id == photo.id }) {
            request.photos.append(photo)
            if photo.locationStatus != .geocodingPending {
                photo.locationStatus = .geocodingPending
                didMutateStoredData = true
            }
        }
        if !request.records.contains(where: { $0.persistentModelID == record.persistentModelID }) {
            request.records.append(record)
        }
        return didMutateStoredData
    }

    @discardableResult
    private func apply(_ place: String, to photo: JournalPhotoRecord, record: JournalRecord) -> Bool {
        var didMutateStoredData = false
        if photo.placeName != place {
            photo.placeName = place
            didMutateStoredData = true
        }
        if photo.locationStatus != .available {
            photo.locationStatus = .available
            didMutateStoredData = true
        }
        if Self.needsDetailedPlace(record.locationText), record.locationText != place {
            record.locationText = place
            didMutateStoredData = true
        }
        return didMutateStoredData
    }

    private func cachedPlace(near location: CLLocation) -> String? {
        var nearest: (distance: CLLocationDistance, place: String)?
        for (coordinate, place) in Self.cache {
            let components = coordinate.split(separator: ",", omittingEmptySubsequences: false)
            guard components.count == 2,
                  let latitude = Double(components[0]),
                  let longitude = Double(components[1]) else { continue }
            let cachedLocation = CLLocation(latitude: latitude, longitude: longitude)
            let distance = cachedLocation.distance(from: location)
            guard distance <= Self.groupingRadius else { continue }
            if let current = nearest, distance < current.distance {
                nearest = (distance, place)
            } else if nearest == nil {
                nearest = (distance, place)
            }
        }
        return nearest?.place
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        #if os(macOS)
        if #available(macOS 26, *) { return await mapKitReverseGeocode(location) }
        return await legacyMacReverseGeocode(location)
        #else
        if let address = await detailedIOSReverseGeocode(location) { return address }
        if #available(iOS 26, *) { return await mapKitReverseGeocode(location) }
        return nil
        #endif
    }

    #if os(iOS)
    private func detailedIOSReverseGeocode(_ location: CLLocation) async -> String? {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: HetkiaSystemLanguage.identifier)
            )
            guard let place = placemarks.first else { return nil }
            let city = place.locality ?? place.administrativeArea
            let detail = place.subLocality ?? place.subAdministrativeArea ?? place.name
            let components = [place.country, city, detail]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var unique: [String] = []
            for component in components where !unique.contains(where: { $0.caseInsensitiveCompare(component) == .orderedSame }) {
                unique.append(component)
            }
            return unique.isEmpty ? nil : unique.joined(separator: " · ")
        } catch {
            Self.logger.error("Detailed reverse-geocoding request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    #endif

    private static func needsDetailedPlace(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return true }
        return value.split(separator: "·").count < 3
    }

    private func reverseGeocodeWithRetries(_ location: CLLocation) async -> String? {
        let retryDelays: [Duration] = [.seconds(2), .seconds(6), .seconds(15), .seconds(30)]
        for attempt in 0...retryDelays.count {
            if let place = await reverseGeocode(location) { return place }
            guard attempt < retryDelays.count else { break }
            try? await Task.sleep(for: retryDelays[attempt])
        }
        return nil
    }

    @available(iOS 26, macOS 26, *)
    private func mapKitReverseGeocode(_ location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: HetkiaSystemLanguage.identifier)
        do {
            guard let item = try await request.mapItems.first else { return nil }
            let representations = item.addressRepresentations
            let address = representations?.cityWithContext(.full)
                ?? representations?.cityName
                ?? representations?.fullAddress(includingRegion: true, singleLine: true)
                ?? item.address?.shortAddress
                ?? item.name
            guard let address,
                  !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return address
        } catch {
            Self.logger.error("MapKit reverse-geocoding request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    #if os(macOS)
    @available(macOS, introduced: 14, obsoleted: 26)
    private func legacyMacReverseGeocode(_ location: CLLocation) async -> String? {
        do {
            let results = try await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: HetkiaSystemLanguage.identifier)
            )
            guard let placemark = results.first else { return nil }
            let components = [placemark.name, placemark.subLocality, placemark.locality,
                              placemark.administrativeArea, placemark.country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var unique: [String] = []
            for component in components where !unique.contains(where: { $0.caseInsensitiveCompare(component) == .orderedSame }) {
                unique.append(component)
            }
            return unique.isEmpty ? nil : unique.joined(separator: " · ")
        } catch {
            Self.logger.error("Core Location reverse-geocoding request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    #endif

    private static var cache: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: cacheKey) }
    }

    private static func key(latitude: Double, longitude: Double) -> String {
        // Cache the representative coordinate. Nearby locations reuse its city label
        // only when they fall within the explicit five-kilometre radius.
        String(format: "%.5f,%.5f", latitude, longitude)
    }
}

private struct JournalShareCard: View {
    let date: String
    let title: String
    let diaryText: String
    let locations: [String]
    let photos: [CGImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: date)
                    .font(.system(size: 42, weight: .regular, design: .serif))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                Spacer()
                Text("brand.name")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
            }
            JournalSharePhotoGrid(photos: photos)
                .frame(height: PhotoMosaicLayout.height(width: 968, count: photos.count, gap: 10))
                .padding(.vertical, 26)
            if !title.isEmpty {
                Text(verbatim: title).font(.system(size: 42, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink).padding(.bottom, 12)
            }
            if !diaryText.isEmpty {
                Text(verbatim: diaryText).font(.system(size: 34)).lineSpacing(8)
                    .lineLimit(5).foregroundStyle(HetkiaPalette.secondaryInk)
            }
            if !locations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(locations, id: \.self) { location in
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 26)).foregroundStyle(HetkiaPalette.secondaryInk)
                    }
                }
                .padding(.top, 24)
            }
            Spacer(minLength: 24)
            Rectangle().fill(HetkiaPalette.line).frame(height: 2).padding(.bottom, 18)
            HStack { Text("page.footer"); Spacer(); Text("brand.name") }
                .font(.system(size: 24, design: .serif)).foregroundStyle(HetkiaPalette.secondaryInk)
        }
        .foregroundStyle(HetkiaPalette.ink)
        .padding(.horizontal, 56).padding(.vertical, 56)
        .frame(width: 1080, alignment: .topLeading)
        .frame(minHeight: 1440, alignment: .topLeading)
        .background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

private struct JournalSharePhotoGrid: View {
    let photos: [CGImage]

    var body: some View {
        GeometryReader { geometry in
            let count = photos.count
            let gap: CGFloat = 10
            let tiles = PhotoMosaicLayout.tiles(width: geometry.size.width, count: count, gap: gap)
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tileLayout in
                    tile(photos[tileLayout.index], width: tileLayout.rect.width, height: tileLayout.rect.height)
                        .frame(width: tileLayout.rect.width, height: tileLayout.rect.height)
                        .position(x: tileLayout.rect.midX, y: tileLayout.rect.midY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func tile(_ image: CGImage, width: CGFloat, height: CGFloat) -> some View {
        Image(decorative: image, scale: 1).resizable().scaledToFill()
            .frame(width: width, height: height).clipped()
    }
}

#if os(iOS)
private struct JournalActivityShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

private struct PhotoLocationMapView: View {
    let destination: PhotoMapDestination

    var body: some View {
        Map(
            initialPosition: .camera(
                // Start at neighborhood scale so the selected point has useful
                // context around it instead of opening at a street-level zoom.
                MapCamera(centerCoordinate: destination.coordinate, distance: 1_000)
            )
        ) {
            Marker(destination.title, coordinate: destination.coordinate)
        }
        .mapStyle(.standard)
    }
}

private struct PhotoFullScreenGallery: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [JournalPhotoRecord]
    @State private var selection: Int
    @State private var zoomedIndex: Int?

    init(photos: [JournalPhotoRecord], initialIndex: Int) {
        self.photos = photos
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoGalleryPage(photo: photo) { isZoomed in
                        zoomedIndex = isZoomed ? index : (zoomedIndex == index ? nil : zoomedIndex)
                    }
                    .tag(index)
                }
            }
#if os(macOS)
            .tabViewStyle(.automatic)
#else
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
#endif
            .onChange(of: selection) { _, _ in zoomedIndex = nil }
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(Text("common.close"))
                }
                Spacer()
                if photos.count > 1 {
#if os(macOS)
                    HStack(spacing: 22) {
                        Button { selection = max(0, selection - 1) } label: { Image(systemName: "chevron.left") }
                            .disabled(selection == 0)
                        Text("\(selection + 1) / \(photos.count)")
                        Button { selection = min(photos.count - 1, selection + 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(selection == photos.count - 1)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.9)).padding(.bottom, 12)
#else
                    // The native page dots are the only page indicator on iOS.
#endif
                }
            }
            .padding(.horizontal, 18).padding(.top, 10)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let translation = value.translation
                    guard zoomedIndex == nil,
                          translation.height > 100,
                          translation.height > abs(translation.width) * 1.25 else { return }
                    dismiss()
                }
        )
        .preferredColorScheme(.dark)
#if !os(macOS)
        .statusBarHidden()
#endif
    }
}

private struct PhotoGalleryPage: View {
    let photo: JournalPhotoRecord
    let onZoomChanged: (Bool) -> Void
    @State private var image: CGImage?
    @State private var player: AVPlayer?
    @State private var isLoadingVideo = false

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .onDisappear { player.pause() }
                } else if let image {
                    ZStack {
                        ZoomableGalleryImage(image: image, onZoomChanged: onZoomChanged)
                        if photo.mediaType == "video" {
                            Button {
                                Task { await loadAndPlayVideo() }
                            } label: {
                                Group {
                                    if isLoadingVideo {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 25, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .background(.black.opacity(0.58), in: Circle())
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingVideo)
                            .accessibilityLabel(Text("photos.open.fullscreen"))
                        }
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: photo.id) {
                let targetSize = CGSize(
                    width: max(geometry.size.width * 2, 1800),
                    height: max(geometry.size.height * 2, 1800)
                )
                if photo.mediaType == "video" {
                    image = await PhotoAssetResolver.thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: targetSize)
                    await loadAndPlayVideo()
                } else {
                    image = await PhotoAssetResolver.fullFrameImage(for: photo, targetSize: targetSize)
                }
            }
        }
    }

    @MainActor
    private func loadAndPlayVideo() async {
        guard photo.mediaType == "video", player == nil, !isLoadingVideo else { return }
        isLoadingVideo = true
        defer { isLoadingVideo = false }
        guard let videoAsset = await PhotoAssetResolver.videoAsset(for: photo) else { return }
        let videoPlayer = AVPlayer(playerItem: AVPlayerItem(asset: videoAsset))
        player = videoPlayer
        videoPlayer.play()
    }
}

private struct ZoomableGalleryImage: View {
    let image: CGImage
    let onZoomChanged: (Bool) -> Void
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let imageView = Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(committedScale * value.magnification, 1), 5)
                        }
                        .onEnded { _ in
                            committedScale = scale
                            if committedScale <= 1.02 {
                                resetZoom()
                            } else {
                                onZoomChanged(true)
                                offset = clamped(offset, in: geometry.size, scale: committedScale)
                                committedOffset = offset
                            }
                        }
                )

            if committedScale > 1.02 {
                imageView.simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            // Let the enclosing TabView own horizontal swipes so
                            // paging remains reliable while an image is zoomed.
                            guard abs(value.translation.height) > abs(value.translation.width) else { return }
                            offset = clamped(
                                CGSize(width: committedOffset.width + value.translation.width,
                                       height: committedOffset.height + value.translation.height),
                                in: geometry.size,
                                scale: committedScale
                            )
                        }
                        .onEnded { _ in committedOffset = offset }
                )
                .onTapGesture(count: 2) {
                    resetZoom()
                }
            } else {
                imageView.onTapGesture(count: 2) {
                    committedScale = 2
                    scale = 2
                    onZoomChanged(true)
                }
            }
        }
    }

    private func clamped(_ value: CGSize, in size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(
            width: min(max(value.width, -size.width * (scale - 1) / 2), size.width * (scale - 1) / 2),
            height: min(max(value.height, -size.height * (scale - 1) / 2), size.height * (scale - 1) / 2)
        )
    }

    private func resetZoom() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
        onZoomChanged(false)
    }
}
