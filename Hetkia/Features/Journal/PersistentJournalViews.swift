import SwiftUI
import SwiftData
import CoreGraphics
import ImageIO
import CoreLocation
import MapKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct PersistentJournalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: JournalRecord
    @State private var isGenerating = false
    @State private var notice: String?
    @State private var editingPostID: UUID?
    @State private var editDraft = ""
    @State private var newMessage = ""
    @State private var photoGallery: PhotoGallerySession?
    @State private var mapDestination: PhotoMapDestination?
    @State private var sharePayload: ShareImagePayload?
    @State private var isPreparingShare = false
    @FocusState private var focusedInput: InputTarget?
    @ScaledMetric(relativeTo: .body) private var bodyFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .headline) private var headingFontSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption) private var captionFontSize: CGFloat = 12

    private enum InputTarget: Hashable { case edit(UUID), compose }
    private var selectedPhotos: [JournalPhotoRecord] { JournalPhotoSelection.selected(from: record.photos) }
    private var posts: [JournalMessagePost] { record.messagePosts.sorted { $0.createdAt < $1.createdAt } }
    private var shareBody: String {
        posts.last?.text ?? (record.bodyText.isEmpty ? (record.aiDraftBody ?? "") : record.bodyText)
    }
    private var locationCities: [JournalLocationItem] {
        var seen = Set<String>()
        return selectedPhotos.compactMap { photo in
            guard photo.latitude != nil, photo.longitude != nil,
                  let name = photo.placeName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .components(separatedBy: .whitespacesAndNewlines).joined()
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

    var body: some View {
        GeometryReader { viewport in
            let pageWidth = min(max(viewport.size.width - 36, 1), 520)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 18) {
                        persistentPage(photoAreaHeight: pageWidth)
                            .frame(width: pageWidth)
                            .frame(minHeight: pageWidth * 4.0 / 3.0, alignment: .top)
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 18, y: 8)
                        actionPanel.frame(width: pageWidth)
                        messageBoard.frame(width: pageWidth)
                        if record.bodyWasEdited, let draft = record.aiDraftBody, draft != record.bodyText {
                            generatedDraftCard(draft).frame(width: pageWidth)
                        }
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
                        case .edit(let id): withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                        case .compose: withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("message-composer", anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .background(HetkiaPalette.paper.ignoresSafeArea())
        .navigationTitle(record.localDay.formatted(date: .long, time: .omitted))
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
        .task {
            migrateExistingBodyToMessagePost()
            await resolvePhotoLocations()
        }
        .alert("photos.generate.status", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("common.ok", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
    }

    private func persistentPage(photoAreaHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((mapPhoto?.capturedAt ?? record.localDay).formatted(.dateTime.year().month(.wide).day().hour().minute()))
                    .font(.system(size: headingFontSize, weight: .regular, design: .serif))
                Spacer()
                Text(LocalizedStringKey(record.source == .automatic ? "journal.source.automatic" : "journal.source.manual"))
                    .font(.system(size: captionFontSize, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                Image(systemName: "sun.max").font(.system(size: 13, weight: .light)).foregroundStyle(HetkiaPalette.amber)
            }
            persistentPhotoGrid(height: photoAreaHeight).padding(.vertical, 13)
            if !record.title.isEmpty { Text(verbatim: record.title).font(.system(size: headingFontSize, design: .serif)).padding(.bottom, 6) }
            let pageText = posts.last?.text ?? (record.bodyText.isEmpty ? (record.aiDraftBody ?? NSLocalizedString("photos.journal.empty", comment: "Empty journal")) : record.bodyText)
            Text(verbatim: pageText).font(.system(size: bodyFontSize)).lineSpacing(4).foregroundStyle(HetkiaPalette.secondaryInk).fixedSize(horizontal: false, vertical: true).lineLimit(5)
            Spacer(minLength: 10)
            if !locationCities.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(locationCities) { item in
                        Button {
                            guard let latitude = item.photo.latitude, let longitude = item.photo.longitude else { return }
                            mapDestination = PhotoMapDestination(
                                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                title: item.name
                            )
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
                        guard let latitude = mapPhoto.latitude, let longitude = mapPhoto.longitude else { return }
                        mapDestination = PhotoMapDestination(
                            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            title: location
                        )
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
            if let mood = record.moodText, !mood.isEmpty { Label(mood, systemImage: "heart").font(.system(size: captionFontSize)).foregroundStyle(HetkiaPalette.secondaryInk).padding(.top, 4) }
            Rectangle().fill(HetkiaPalette.line).frame(height: 0.7).padding(.top, 10).padding(.bottom, 7)
            HStack { Text("page.footer"); Spacer(); Text("brand.footer") }.font(.system(size: captionFontSize, design: .serif)).foregroundStyle(HetkiaPalette.secondaryInk)
        }
        .foregroundStyle(HetkiaPalette.ink).padding(.horizontal, 28).padding(.vertical, 28)
        .background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func persistentPhotoGrid(height: CGFloat) -> some View {
        GeometryReader { geometry in
            let photos = selectedPhotos
            let count = photos.count
            let gap: CGFloat = 5
            Group {
                if count == 1, let photo = photos.first {
                    photoTile(photo, index: 0, width: geometry.size.width, height: geometry.size.height)
                } else if count == 9 {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 3), spacing: gap) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            let tileSide = max(1, (geometry.size.width - gap * 2) / 3)
                            photoTile(photo, index: index, width: tileSide, height: tileSide)
                        }
                    }
                } else {
                    let columns = count >= 7 ? 3 : 2
                    let rows = max(1, Int(ceil(Double(max(count - 1, 0)) / Double(columns))))
                    let heroHeight = geometry.size.height * (count == 3 ? 0.64 : 0.44)
                    let tileGapHeight = CGFloat(rows) * gap
                    let tileHeight = max(1, (geometry.size.height - heroHeight - tileGapHeight) / CGFloat(rows))
                    VStack(spacing: gap) {
                        if let hero = photos.first { photoTile(hero, index: 0, width: geometry.size.width, height: heroHeight) }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), spacing: gap) {
                            ForEach(Array(photos.dropFirst().enumerated()), id: \.element.id) { offset, photo in
                                photoTile(photo, index: offset + 1, width: max(1, (geometry.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)), height: tileHeight)
                            }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 9))
        }.frame(height: max(1, height))
    }

    private func photoTile(_ photo: JournalPhotoRecord, index: Int, width: CGFloat, height: CGFloat) -> some View {
        PhotoFallbackThumbnail(photo: photo, width: width, height: height) {
            photoGallery = PhotoGallerySession(initialIndex: index)
        }
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { await prepareShareImage() }
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
            HStack {
                Label(generationStatusKey, systemImage: generationSymbol).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(record.generationStatus == .failed ? .red : HetkiaPalette.secondaryInk)
                Spacer()
                Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Photo count"), selectedPhotos.count))
                    .font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
            }
            if let generationError = record.generationError, !generationError.isEmpty {
                Text(verbatim: generationError).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if record.bodyText.isEmpty {
                Text(verbatim: JournalDraftService.availabilityDescription).font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: 520)
    }

    @MainActor
    private func prepareShareImage() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        guard !selectedPhotos.isEmpty else {
            notice = NSLocalizedString("photos.generate.needs-photos", comment: "")
            return
        }
        var images: [CGImage] = []
        for photo in selectedPhotos.prefix(9) {
            if let image = await PhotoAssetResolver.displayImage(
                for: photo,
                targetSize: CGSize(width: 1200, height: 1200)
            ) {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            notice = NSLocalizedString("detail.share.failed", comment: "Could not create share image")
            return
        }

        let card = JournalShareCard(
            date: (mapPhoto?.capturedAt ?? record.localDay).formatted(.dateTime.year().month(.wide).day().hour().minute()),
            title: record.title,
            diaryText: shareBody,
            source: record.source,
            locations: locationCities.map(\.name),
            photos: images
        )
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: 1080, height: nil)
        renderer.scale = 3
        guard let image = renderer.cgImage else {
            notice = NSLocalizedString("detail.share.failed", comment: "Could not create share image")
            return
        }
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hetkia-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, "public.png" as CFString, 1, nil) else {
            notice = NSLocalizedString("detail.share.failed", comment: "Could not create share image")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            notice = NSLocalizedString("detail.share.failed", comment: "Could not create share image")
            return
        }
        sharePayload = ShareImagePayload(image: image, url: imageURL)
    }

    private var messageBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("journal.message.board", systemImage: "text.bubble").font(.system(size: 15, weight: .semibold, design: .serif))
                Spacer()
                Text(record.localDay.formatted(date: .numeric, time: .omitted)).font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
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
                    Text(Date.now.formatted(date: .numeric, time: .shortened)).font(.system(size: 10, design: .rounded)).foregroundStyle(HetkiaPalette.secondaryInk)
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
                Image(systemName: post.kind == .automatic ? "sparkles" : "quote.bubble")
                    .foregroundStyle(post.kind == .automatic ? HetkiaPalette.amber : HetkiaPalette.secondaryInk)
                Text(post.kind == .automatic ? LocalizedStringKey("journal.message.generated") : LocalizedStringKey("journal.message.note"))
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
                }
            }
        }
        .padding(13).background(HetkiaPalette.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 13))
    }

    private func generatedDraftCard(_ draft: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("photos.draft.title", systemImage: "sparkles").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            Text(verbatim: draft).font(.system(size: bodyFontSize)).lineSpacing(4).foregroundStyle(HetkiaPalette.secondaryInk).frame(maxWidth: .infinity, alignment: .leading)
            Button("photos.draft.use") {
                record.bodyText = draft
                record.bodyWasEdited = false
                appendPost(text: draft, kind: .automatic)
                record.updatedAt = .now
                try? modelContext.save()
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
        }.padding(16).background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 16))
    }

    private var generationStatusKey: LocalizedStringKey {
        switch record.generationStatus {
        case .pending: "photos.status.pending"
        case .processing: "photos.status.processing"
        case .completed: "photos.status.completed"
        case .failed: "photos.status.failed"
        case .skipped: "photos.status.skipped"
        case .cancelled: "photos.status.cancelled"
        }
    }

    private var generationSymbol: String {
        switch record.generationStatus {
        case .pending: "clock"
        case .processing: "arrow.trianglehead.2.clockwise"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .skipped, .cancelled: "minus.circle"
        }
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(HetkiaPalette.ink).frame(maxWidth: .infinity).frame(height: 48)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func migrateExistingBodyToMessagePost() {
        guard record.messagePosts.isEmpty else { return }
        let body = record.bodyText.isEmpty ? (record.aiDraftBody ?? "") : record.bodyText
        guard !body.isEmpty else { return }
        var posts = record.messagePosts
        posts.append(JournalMessagePost(text: body, createdAt: record.updatedAt, kind: record.aiDraftBody == nil ? .note : .automatic))
        record.messagePosts = posts
        try? modelContext.save()
    }

    private func resolvePhotoLocations() async {
        var resolvedByCoordinate: [String: String] = [:]
        for photo in selectedPhotos where photo.latitude != nil && photo.longitude != nil {
            guard let latitude = photo.latitude, let longitude = photo.longitude else { continue }
            let coordinateKey = "\(latitude),\(longitude)"
            if let existing = photo.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
                resolvedByCoordinate[coordinateKey] = existing
                continue
            }
            if let cached = resolvedByCoordinate[coordinateKey] {
                photo.placeName = cached
                continue
            }
            let location = CLLocation(latitude: latitude, longitude: longitude)
            guard let place = await reverseGeocodedPlace(for: location), !place.isEmpty else { continue }
            photo.placeName = place
            resolvedByCoordinate[coordinateKey] = place
        }
        if let firstPlace = selectedPhotos.compactMap({ $0.placeName }).first(where: { !$0.isEmpty }) {
            record.locationText = firstPlace
        }
        try? modelContext.save()
    }

    private func reverseGeocodedPlace(for location: CLLocation) async -> String? {
        if #available(iOS 26, macOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else { return nil }
            let representations = item.addressRepresentations
            return representations?.cityWithContext(.full)
                ?? representations?.cityName
                ?? representations?.fullAddress(includingRegion: true, singleLine: true)
        } else {
            let geocoder = CLGeocoder()
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
            let city = placemark.locality
            let region = placemark.administrativeArea
            let regionIsCity = if let city, let region {
                region.localizedCaseInsensitiveContains(city) || city.localizedCaseInsensitiveContains(region)
            } else { false }
            let components = [placemark.subLocality ?? placemark.subAdministrativeArea, city, regionIsCity ? nil : region, placemark.country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var uniqueComponents: [String] = []
            for component in components where !uniqueComponents.contains(component) { uniqueComponents.append(component) }
            return uniqueComponents.joined(separator: " · ")
        }
    }

    private func appendPost(text: String, kind: JournalMessagePost.Kind) {
        var updated = record.messagePosts
        updated.append(JournalMessagePost(text: text, createdAt: .now, kind: kind))
        record.messagePosts = updated
    }

    private func addMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appendPost(text: text, kind: .note)
        newMessage = ""
        try? modelContext.save()
    }

    private func saveEditedPost(_ post: JournalMessagePost) {
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var updated = record.messagePosts
        guard let index = updated.firstIndex(where: { $0.id == post.id }) else { return }
        updated[index].text = text
        record.messagePosts = updated
        if post.kind == .automatic { record.aiDraftBody = record.aiDraftBody ?? post.text; record.bodyText = text; record.bodyWasEdited = true }
        record.updatedAt = .now
        try? modelContext.save()
        editingPostID = nil
        focusedInput = nil
    }

    private func cancelEditing() { editingPostID = nil; focusedInput = nil; editDraft = "" }

    private func generateDraft() async {
        guard !selectedPhotos.isEmpty else { notice = NSLocalizedString("photos.generate.needs-photos", comment: ""); return }
        guard #available(iOS 26, macOS 26, *) else {
            notice = JournalDraftService.availabilityDescription
            record.generationStatus = .failed
            record.generationError = notice
            try? modelContext.save()
            return
        }
        isGenerating = true
        let allTasks = (try? modelContext.fetch(FetchDescriptor<JournalGenerationTask>())) ?? []
        for pending in allTasks where pending.dayKey == record.dayKey && pending.status == .pending { pending.status = .skipped }
        let task = JournalGenerationTask(dayKey: record.dayKey, journal: record, type: .manual)
        task.status = .processing
        task.attempts += 1
        record.generationStatus = .processing
        record.generationError = nil
        modelContext.insert(task)
        try? modelContext.save()
        do {
            var images: [CGImage] = []
            if #available(iOS 27, macOS 27, *) {
                for photo in selectedPhotos { if let image = await PhotoAssetResolver.aiImage(for: photo) { images.append(image) } }
            }
            let result = try await JournalDraftService.generate(date: record.localDay, photoCount: selectedPhotos.count, imageSamples: images)
            record.aiDraftBody = result.body
            if !record.bodyWasEdited { record.bodyText = result.body }
            appendPost(text: result.body, kind: .automatic)
            record.generationStatus = .completed
            task.status = .completed
            task.lastError = nil
            try modelContext.save()
        } catch {
            record.generationStatus = .failed
            record.generationError = error.localizedDescription
            task.status = .failed
            task.lastError = error.localizedDescription
            notice = error.localizedDescription
            try? modelContext.save()
        }
        isGenerating = false
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

private struct JournalShareCard: View {
    let date: String
    let title: String
    let diaryText: String
    let source: JournalSource
    let locations: [String]
    let photos: [CGImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: date)
                    .font(.system(size: 42, weight: .regular, design: .serif))
                Spacer()
                Text(LocalizedStringKey(source == .automatic ? "journal.source.automatic" : "journal.source.manual"))
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                Image(systemName: "sun.max").font(.system(size: 28, weight: .light)).foregroundStyle(HetkiaPalette.amber)
            }
            JournalSharePhotoGrid(photos: photos)
                .frame(height: 1080)
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
            HStack { Text("page.footer"); Spacer(); Text("brand.footer") }
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
            Group {
                if count == 1, let photo = photos.first {
                    tile(photo, width: geometry.size.width, height: geometry.size.height)
                } else if count == 9 {
                    VStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(0..<3, id: \.self) { column in
                                    let index = row * 3 + column
                                    if photos.indices.contains(index) {
                                        tile(photos[index], width: (geometry.size.width - 2 * gap) / 3, height: (geometry.size.height - 2 * gap) / 3)
                                    }
                                }
                            }
                        }
                    }
                } else if count > 1 {
                    let columns = count >= 7 ? 3 : 2
                    let rows = max(1, Int(ceil(Double(count - 1) / Double(columns))))
                    let heroHeight = geometry.size.height * (count == 3 ? 0.64 : 0.44)
                    let tileHeight = (geometry.size.height - heroHeight - CGFloat(rows) * gap) / CGFloat(rows)
                    VStack(spacing: gap) {
                        tile(photos[0], width: geometry.size.width, height: heroHeight)
                        ForEach(0..<rows, id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(0..<columns, id: \.self) { column in
                                    let index = 1 + row * columns + column
                                    if photos.indices.contains(index) {
                                        tile(photos[index], width: (geometry.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns), height: tileHeight)
                                    }
                                }
                            }
                        }
                    }
                }
            }
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
                MapCamera(centerCoordinate: destination.coordinate, distance: 180)
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

    init(photos: [JournalPhotoRecord], initialIndex: Int) {
        self.photos = photos
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoGalleryPage(photo: photo).tag(index)
                }
            }
#if os(macOS)
            .tabViewStyle(.automatic)
#else
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
#endif
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
                    Text("\(selection + 1) / \(photos.count)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85)).padding(.bottom, 12)
#endif
                }
            }
            .padding(.horizontal, 18).padding(.top, 10)
        }
        .preferredColorScheme(.dark)
#if !os(macOS)
        .statusBarHidden()
#endif
    }
}

private struct PhotoGalleryPage: View {
    let photo: JournalPhotoRecord
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
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
                image = await PhotoAssetResolver.thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: targetSize)
                if let highResolution = await PhotoAssetResolver.displayImage(for: photo, targetSize: targetSize) {
                    image = highResolution
                }
            }
        }
    }
}
