import SwiftUI
import SwiftData
import PhotosUI

struct PhotoImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalRecord.localDay, order: .reverse) private var journals: [JournalRecord]
    @Query(sort: \JournalPhotoRecord.firstDiscoveredAt, order: .reverse) private var allPhotos: [JournalPhotoRecord]
    @StateObject private var library = PhotoLibraryService()
    @State private var selections: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var isGeneratingJournals = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var dateForUndatedPhotos = Date.now

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    accessCard
                    selectionCard
                    if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle")
                            .font(.system(size: 12)).foregroundStyle(HetkiaPalette.secondaryInk)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    }
                    if !undatedPhotos.isEmpty { undatedDateGroup }
                    if !journals.isEmpty { journalList }
                }
                .padding(18)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(HetkiaPalette.paper.ignoresSafeArea())
            .navigationTitle(Text("photos.library.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() } }
            }
            .onAppear { library.refreshAuthorization() }
            .onChange(of: selections) { _, selectedItems in
                guard !selectedItems.isEmpty, !isImporting else { return }
                Task { await importSelections(selectedItems) }
            }
            .alert("photos.import.error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("common.ok", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(HetkiaPalette.amber)
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("photos.access.title", systemImage: "hand.raised")
                .font(.system(size: 15, weight: .semibold, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            Text(accessDescription)
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(HetkiaPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(accessStatus).font(.system(size: 11, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                Spacer()
                if !library.canReadLibrary {
                    Button("photos.access.request") {
                        Task { _ = await library.requestAuthorization() }
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(HetkiaPalette.line.opacity(0.65), lineWidth: 0.7))
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("photos.choose.title", systemImage: "photo.stack")
                .font(.system(size: 15, weight: .semibold, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            Text("photos.choose.detail")
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(HetkiaPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            PhotosPicker(
                selection: $selections,
                maxSelectionCount: 100,
                matching: .all(of: [.images, .not(.screenshots), .not(.screenRecordings)])
            ) {
                Label(String(format: NSLocalizedString("photos.choose.count", comment: "Selected photo count"), selections.count), systemImage: "plus")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(HetkiaPalette.paper, in: Capsule())
            }
            .buttonStyle(.plain).disabled(isImporting || isGeneratingJournals)
            if isImporting || isGeneratingJournals {
                HStack(spacing: 10) {
                    ProgressView().tint(HetkiaPalette.amber)
                    Text(isImporting ? "photos.importing" : "photos.generating").font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.secondaryInk)
                    Spacer()
                }.padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(HetkiaPalette.line.opacity(0.65), lineWidth: 0.7))
    }

    private var journalList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("photos.journals.title").font(.system(size: 16, weight: .medium, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            ForEach(journals) { journal in
                NavigationLink {
                    PersistentJournalDetailView(record: journal)
                } label: {
                    HStack(spacing: 12) {
                        if let firstPhoto = journal.photos.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                            PhotoFallbackThumbnail(photo: firstPhoto, width: 58, height: 70)
                        } else {
                            Image(systemName: "book.closed").frame(width: 58, height: 70).background(HetkiaPalette.paper, in: RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(journal.localDay.formatted(date: .long, time: .omitted)).font(.system(size: 13, weight: .medium, design: .serif))
                            Text(journal.bodyText.isEmpty ? NSLocalizedString("photos.journal.pending", comment: "") : journal.bodyText)
                                .font(.system(size: 11)).lineLimit(2).foregroundStyle(HetkiaPalette.secondaryInk)
                            Text(generationStatusText(journal.generationStatus))
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(HetkiaPalette.line)
                    }
                    .foregroundStyle(HetkiaPalette.ink).padding(10)
                    .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var undatedPhotos: [JournalPhotoRecord] { allPhotos.filter { $0.journal == nil } }

    private var undatedDateGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(format: NSLocalizedString("photos.undated.title", comment: "Undated photo count"), undatedPhotos.count), systemImage: "calendar.badge.exclamationmark")
                .font(.system(size: 14, weight: .medium, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            Text("photos.undated.detail").font(.system(size: 11)).foregroundStyle(HetkiaPalette.secondaryInk)
            DatePicker("photos.undated.assign-date", selection: $dateForUndatedPhotos, displayedComponents: .date)
            Button("photos.undated.assign-action", action: assignUndatedPhotos)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
        }
        .padding(15).background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
    }

    private var accessDescription: LocalizedStringKey {
        switch library.authorizationStatus {
        case .authorized: "photos.access.full.detail"
        case .limited: "photos.access.limited.detail"
        case .denied: "photos.access.denied.detail"
        case .restricted: "photos.access.restricted.detail"
        case .notDetermined: "photos.access.request.detail"
        @unknown default: "photos.access.request.detail"
        }
    }

    private var accessStatus: LocalizedStringKey {
        switch library.authorizationStatus {
        case .authorized: "photos.access.full"
        case .limited: "photos.access.limited"
        case .denied: "photos.access.denied"
        case .restricted: "photos.access.restricted"
        case .notDetermined: "photos.access.not-determined"
        @unknown default: "photos.access.not-determined"
        }
    }

    private func importSelections(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false; isGeneratingJournals = false }
        do {
            let summary = try await library.importSelections(items, into: modelContext)
            statusMessage = String(format: NSLocalizedString("photos.import.summary", comment: "Photo import summary"), summary.photoCount, summary.journalCount, summary.undatedCount, summary.excludedCount)
            selections = []
            isImporting = false
            isGeneratingJournals = true
            await JournalAutomationCoordinator.shared.catchUp(context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assignUndatedPhotos() {
        let day = PhotoDayGrouping.representativeDate(for: dateForUndatedPhotos)
        let key = PhotoDayGrouping.key(for: day)
        let journal: JournalRecord
        let automaticKey = "\(key)|automatic"
        let manualKey = "\(key)|manual"
        let legacyKey = key
        let descriptor = FetchDescriptor<JournalRecord>(predicate: #Predicate {
            $0.storageKey == automaticKey || $0.storageKey == manualKey || $0.storageKey == legacyKey
        })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            journal = existing
        } else {
            journal = JournalRecord(dayKey: key, localDay: day, source: .manual)
            modelContext.insert(journal)
            modelContext.insert(JournalGenerationTask(dayKey: key, journal: journal, type: .manual))
        }
        for (index, photo) in undatedPhotos.enumerated() {
            photo.capturedAt = day
            photo.metadataReadStatus = .partial
            photo.journal = journal
            photo.sortOrder = journal.photos.count + index
        }
        if journal.bodyText.isEmpty { journal.generationStatus = .pending }
        try? modelContext.save()
        statusMessage = NSLocalizedString("photos.undated.assigned", comment: "")
    }

    private func generationStatusText(_ status: JournalGenerationStatus) -> String {
        let key: String
        switch status {
        case .pending: key = "photos.status.pending"
        case .processing: key = "photos.status.processing"
        case .completed: key = "photos.status.completed"
        case .failed: key = "photos.status.failed"
        case .skipped: key = "photos.status.skipped"
        case .cancelled: key = "photos.status.cancelled"
        }
        return NSLocalizedString(key, comment: "")
    }
}

struct PhotoFallbackThumbnail: View {
    let photo: JournalPhotoRecord
    let width: CGFloat
    let height: CGFloat
    var onTap: (() -> Void)? = nil
    @State private var image: CGImage?

    init(photo: JournalPhotoRecord, width: CGFloat, height: CGFloat, onTap: (() -> Void)? = nil) {
        self.photo = photo
        self.width = width
        self.height = height
        self.onTap = onTap
    }

    @ViewBuilder
    var body: some View {
        if let onTap {
            Button(action: onTap) { thumbnailContent }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("photos.open.fullscreen"))
        } else {
            thumbnailContent
        }
    }

    private var thumbnailContent: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(HetkiaPalette.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(HetkiaPalette.paper)
            }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 9))
        .task(id: "\(photo.id.uuidString)-\(Int(width.rounded()))x\(Int(height.rounded()))") {
            guard width > 0, height > 0 else { return }
            let size = CGSize(width: width * 2, height: height * 2)
            image = await PhotoAssetResolver.thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: size)
            if image == nil { image = await PhotoAssetResolver.displayImage(for: photo, targetSize: size) }
        }
    }
}
