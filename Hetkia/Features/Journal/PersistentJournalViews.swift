import SwiftUI
import SwiftData
import CoreGraphics

struct PersistentJournalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: JournalRecord
    @State private var editingBody = false
    @State private var editDraft = ""
    @State private var isGenerating = false
    @State private var notice: String?

    private var orderedPhotos: [JournalPhotoRecord] {
        record.photos.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedPhotos: [JournalPhotoRecord] {
        let count = orderedPhotos.count
        let selectedCount = count > 9 ? 9 : (count.isMultiple(of: 2) ? max(0, count - 1) : count)
        return Array(orderedPhotos.prefix(selectedCount))
    }

    var body: some View {
        GeometryReader { viewport in
            let pageWidth = min(max(viewport.size.width - 36, 0), 520)
            ScrollView(.vertical) {
                VStack(spacing: 18) {
                    persistentPage
                        .frame(width: pageWidth, height: pageWidth * 4.0 / 3.0)
                        .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 18, y: 8)
                    actionPanel.frame(width: pageWidth)
                    if record.bodyWasEdited, let draft = record.aiDraftBody, draft != record.bodyText {
                        generatedDraftCard(draft).frame(width: pageWidth)
                    }
                }
                .frame(width: viewport.size.width)
                .padding(.top, 12).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(HetkiaPalette.paper.ignoresSafeArea())
        .navigationTitle(record.localDay.formatted(date: .long, time: .omitted))
        .sheet(isPresented: $editingBody) { editorSheet }
        .alert("photos.generate.status", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("common.ok", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
    }

    private var persistentPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("brand.name").font(.system(size: 16, weight: .regular, design: .serif)).tracking(1.5)
                Spacer()
                Image(systemName: "sun.max").font(.system(size: 13, weight: .light)).foregroundStyle(HetkiaPalette.amber)
            }
            Text(record.localDay.formatted(date: .complete, time: .omitted))
                .font(.system(size: 9, design: .rounded)).tracking(1.1).foregroundStyle(HetkiaPalette.secondaryInk).padding(.top, 5)
            persistentPhotoGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 13)
            if !record.title.isEmpty {
                Text(verbatim: record.title).font(.system(size: 13, design: .serif)).padding(.bottom, 6)
            }
            Text(verbatim: !record.bodyText.isEmpty ? record.bodyText : (record.aiDraftBody ?? NSLocalizedString("photos.journal.empty", comment: "Empty journal")))
                .font(.system(size: 10)).lineSpacing(3).foregroundStyle(HetkiaPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 10)
            if let location = record.locationText, !location.isEmpty {
                Label(location, systemImage: "mappin").font(.system(size: 8)).foregroundStyle(HetkiaPalette.secondaryInk).padding(.top, 8)
            } else if selectedPhotos.contains(where: { $0.locationStatus == .available }) {
                Label("photos.location.metadata-present", systemImage: "location")
                    .font(.system(size: 8)).foregroundStyle(HetkiaPalette.secondaryInk).padding(.top, 8)
            }
            if let mood = record.moodText, !mood.isEmpty {
                Label(mood, systemImage: "heart").font(.system(size: 8)).foregroundStyle(HetkiaPalette.secondaryInk).padding(.top, 4)
            }
            Rectangle().fill(HetkiaPalette.line).frame(height: 0.7).padding(.top, 10).padding(.bottom, 7)
            HStack { Text("page.footer"); Spacer(); Text("brand.footer") }
                .font(.system(size: 7, design: .serif)).foregroundStyle(HetkiaPalette.secondaryInk)
        }
        .foregroundStyle(HetkiaPalette.ink)
        .padding(.horizontal, 28).padding(.vertical, 28)
        .background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var persistentPhotoGrid: some View {
        GeometryReader { geometry in
            let photos = selectedPhotos
            let count = photos.count
            let gap: CGFloat = 5
            Group {
                if count == 1, let photo = photos.first {
                    PhotoFallbackThumbnail(photo: photo, width: geometry.size.width, height: geometry.size.height)
                } else if count <= 3 {
                    VStack(spacing: gap) {
                        if let first = photos.first { PhotoFallbackThumbnail(photo: first, width: geometry.size.width, height: geometry.size.height * 0.64) }
                        HStack(spacing: gap) {
                            ForEach(Array(photos.dropFirst().prefix(2))) { photo in
                                PhotoFallbackThumbnail(photo: photo, width: (geometry.size.width - gap) / 2, height: geometry.size.height * 0.32)
                            }
                            if count == 2 { emptyPhotoSlot.frame(maxWidth: .infinity).frame(height: geometry.size.height * 0.32) }
                        }
                    }
                } else {
                    let columns = count <= 5 ? 2 : 3
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: gap) {
                        ForEach(photos) { photo in
                            PhotoFallbackThumbnail(photo: photo, width: (geometry.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns), height: (geometry.size.height - gap * 2) / 3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private var emptyPhotoSlot: some View {
        RoundedRectangle(cornerRadius: 9).fill(HetkiaPalette.paper)
            .overlay(Image(systemName: "photo").foregroundStyle(HetkiaPalette.line))
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                actionButton("detail.edit", symbol: "pencil") { editDraft = record.bodyText; editingBody = true }
                actionButton(isGenerating ? "photos.generating" : "photos.generate", symbol: "sparkles") {
                    Task { await generateDraft() }
                }
                .disabled(isGenerating || record.generationStatus == .processing)
            }
            HStack {
                Label(generationStatusKey, systemImage: generationSymbol)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(record.generationStatus == .failed ? .red : HetkiaPalette.secondaryInk)
                Spacer()
                Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Photo count"), selectedPhotos.count))
                    .font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk)
            }
            if let generationError = record.generationError, !generationError.isEmpty {
                Text(verbatim: generationError).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if record.bodyText.isEmpty {
                Text(verbatim: JournalDraftService.availabilityDescription)
                    .font(.system(size: 10)).foregroundStyle(HetkiaPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 520)
    }

    private func generatedDraftCard(_ draft: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("photos.draft.title", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(HetkiaPalette.ink)
            Text(verbatim: draft).font(.system(size: 13)).lineSpacing(4).foregroundStyle(HetkiaPalette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("photos.draft.use") {
                record.bodyText = draft
                record.bodyWasEdited = false
                record.updatedAt = .now
                try? modelContext.save()
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(HetkiaPalette.amber)
        }
        .padding(16).background(HetkiaPalette.page, in: RoundedRectangle(cornerRadius: 16))
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

    private var editorSheet: some View {
        NavigationStack {
            Form {
                Section("detail.edit.body") { TextEditor(text: $editDraft).frame(minHeight: 150) }
                Section("detail.edit.location") { TextField("detail.edit.location", text: Binding(get: { record.locationText ?? "" }, set: { record.locationText = $0.isEmpty ? nil : $0 })) }
                Section("detail.edit.mood") { TextField("detail.edit.mood", text: Binding(get: { record.moodText ?? "" }, set: { record.moodText = $0.isEmpty ? nil : $0 })) }
            }
            .navigationTitle(Text("detail.edit.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("detail.cancel") { editingBody = false } }
                ToolbarItem(placement: .confirmationAction) { Button("detail.save") { saveEdits() } }
            }
        }
    }

    private func saveEdits() {
        record.bodyText = editDraft
        record.bodyWasEdited = true
        record.updatedAt = .now
        try? modelContext.save()
        editingBody = false
    }

    private func generateDraft() async {
        guard !selectedPhotos.isEmpty else {
            notice = NSLocalizedString("photos.generate.needs-photos", comment: "")
            return
        }
        guard #available(iOS 26, macOS 26, *) else {
            notice = JournalDraftService.availabilityDescription
            record.generationStatus = .failed
            record.generationError = notice
            try? modelContext.save()
            return
        }

        isGenerating = true
        let allTasks = (try? modelContext.fetch(FetchDescriptor<JournalGenerationTask>())) ?? []
        for pending in allTasks where pending.dayKey == record.dayKey && pending.status == .pending {
            pending.status = .skipped
        }
        let task = JournalGenerationTask(dayKey: record.dayKey, journal: record)
        task.status = .processing
        task.attempts += 1
        record.generationStatus = .processing
        record.generationError = nil
        modelContext.insert(task)
        try? modelContext.save()

        do {
            var images: [CGImage] = []
            if #available(iOS 27, macOS 27, *) {
                for photo in selectedPhotos {
                    if let image = await PhotoAssetResolver.aiImage(for: photo) { images.append(image) }
                }
            }
            let result = try await JournalDraftService.generate(date: record.localDay, photoCount: selectedPhotos.count, imageSamples: images)
            record.aiDraftBody = result.body
            if !record.bodyWasEdited { record.bodyText = result.body }
            record.generationStatus = .completed
            task.status = .completed
            task.lastError = nil
            notice = result.usedImageUnderstanding
                ? NSLocalizedString("photos.generate.visual-ready", comment: "")
                : NSLocalizedString("photos.generate.metadata-only", comment: "")
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
