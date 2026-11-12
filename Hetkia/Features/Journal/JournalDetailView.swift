import SwiftUI

struct JournalDetailView: View {
    let entry: JournalEntry

    @Environment(\.dismiss) private var dismiss
    @State private var photoCount: Int
    @State private var bodyText: String
    @State private var locationText: String
    @State private var moodText: String
    @State private var showEditor = false
    @State private var showPhotoOptions = false
    @State private var showPrototypeNotice = false
    @State private var showSharePreview = false

    init(entry: JournalEntry) {
        self.entry = entry
        _photoCount = State(initialValue: entry.photoCount)
        _bodyText = State(initialValue: HetkiaSystemLanguage.localizedString(entry.bodyKey, comment: "Sample journal body"))
        _locationText = State(initialValue: entry.locationKey.map { HetkiaSystemLanguage.localizedString($0, comment: "Sample journal location") } ?? "")
        _moodText = State(initialValue: entry.moodKey.map { HetkiaSystemLanguage.localizedString($0, comment: "Sample journal mood") } ?? "")
    }

    var body: some View {
        ZStack {
            HetkiaPalette.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    JournalPageView(
                        entry: entry,
                        photoCount: photoCount,
                        bodyOverride: bodyText,
                        locationOverride: locationText,
                        moodOverride: moodText
                    )
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxWidth: 520)
                    .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 18, y: 8)

                    actionPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(Text("common.back"))
                Spacer()
                Text(entry.date.formatted(.dateTime.year().month(.abbreviated).day()))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                Spacer()
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(Text("detail.share"))
            }
            .foregroundStyle(HetkiaPalette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showEditor) { editorSheet }
        .confirmationDialog("detail.photo-layout", isPresented: $showPhotoOptions, titleVisibility: .visible) {
            ForEach([1, 3, 5, 7, 9], id: \.self) { count in
                Button(String(format: HetkiaSystemLanguage.localizedString("detail.photo-count", comment: "Photo count option"), count)) {
                    withAnimation(.easeInOut(duration: 0.2)) { photoCount = count }
                }
            }
        }
        .alert("detail.regenerate.title", isPresented: $showPrototypeNotice) {
            Button("common.ok", role: .cancel) { }
        } message: {
            Text("detail.regenerate.message")
        }
        .sheet(isPresented: $showSharePreview) {
            NavigationStack {
                ScrollView { Text(shareText).frame(maxWidth: .infinity, alignment: .leading).padding(22) }
                    .background(HetkiaPalette.paper.ignoresSafeArea())
                    .navigationTitle(Text("detail.share.preview"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { showSharePreview = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var actionPanel: some View {
        HStack(spacing: 10) {
            actionButton("detail.edit", symbol: "pencil") { showEditor = true }
            actionButton("detail.photos", symbol: "photo.on.rectangle") { showPhotoOptions = true }
            actionButton("detail.regenerate", symbol: "sparkles") { showPrototypeNotice = true }
            actionButton("detail.share.preview", symbol: "text.page") { showSharePreview = true }
        }
        .frame(maxWidth: 560)
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(HetkiaPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var editorSheet: some View {
        NavigationStack {
            Form {
                Section("detail.edit.body") { TextEditor(text: $bodyText).frame(minHeight: 140) }
                Section("detail.edit.location") { TextField("detail.edit.location", text: $locationText) }
                Section("detail.edit.mood") { TextField("detail.edit.mood", text: $moodText) }
            }
            .scrollContentBackground(.hidden)
            .background(HetkiaPalette.paper)
            .navigationTitle(Text("detail.edit.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("detail.cancel") { showEditor = false } }
                ToolbarItem(placement: .confirmationAction) { Button("detail.save") { showEditor = false } }
            }
        }
    }

    private var shareText: String {
        "\(entry.date.formatted(date: .long, time: .omitted))\n\(HetkiaSystemLanguage.localizedString(entry.titleKey, comment: "Sample journal title"))\n\n\(bodyText)"
    }
}
