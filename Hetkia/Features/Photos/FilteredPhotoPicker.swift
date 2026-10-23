import SwiftUI
import Photos
#if os(macOS)
import AppKit
private typealias PhotoPickerImage = NSImage
#else
import UIKit
private typealias PhotoPickerImage = UIImage
#endif

struct FilteredPhotoPicker: View {
    @Environment(\.dismiss) private var dismiss
    let excludedDayKeys: Set<String>
    let onSelect: ([PHAsset]) -> Void

    @State private var assets: [PHAsset] = []
    @State private var selectedIdentifiers = Set<String>()
    @State private var isLoading = true
    @State private var hasPhotoAccess = true

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().tint(HetkiaPalette.amber)
                } else if !hasPhotoAccess {
                    ContentUnavailableView("photos.selection.permission-required", systemImage: "hand.raised")
                } else if assets.isEmpty {
                    ContentUnavailableView("photos.selection.empty", systemImage: "photo.on.rectangle")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                Button { toggle(asset) } label: {
                                    PhotoAssetSelectionThumbnail(asset: asset, isSelected: selectedIdentifiers.contains(asset.localIdentifier))
                                        .aspectRatio(0.92, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(asset.creationDate?.formatted(date: .long, time: .omitted) ?? NSLocalizedString("photos.undated.title", comment: "Undated photo"))
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .background(HetkiaPalette.paper.ignoresSafeArea())
            .navigationTitle(Text("photos.selection.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSelect(assets.filter { selectedIdentifiers.contains($0.localIdentifier) })
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Text("photos.selection.confirm")
                            Text("(\(selectedIdentifiers.count))")
                        }
                    }
                    .disabled(selectedIdentifiers.isEmpty)
                }
            }
            .task { await loadAssets() }
        }
        .tint(HetkiaPalette.amber)
    }

    private func toggle(_ asset: PHAsset) {
        let identifier = asset.localIdentifier
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else if selectedIdentifiers.count < 100 {
            selectedIdentifiers.insert(identifier)
        }
    }

    @MainActor
    private func loadAssets() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            hasPhotoAccess = false
            isLoading = false
            return
        }

        let excluded = excludedDayKeys
        let loaded = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var found: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                guard PhotoAssetEligibility.allows(asset) else { return }
                if let date = asset.creationDate, excluded.contains(PhotoDayGrouping.key(for: date)) { return }
                found.append(asset)
            }
            return found
        }.value
        assets = loaded
        isLoading = false
    }
}

private struct PhotoAssetSelectionThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var image: PhotoPickerImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        platformImage(image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        HetkiaPalette.page.overlay {
                            Image(systemName: "photo").foregroundStyle(HetkiaPalette.secondaryInk)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, HetkiaPalette.amber)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(isSelected ? HetkiaPalette.amber : .clear, lineWidth: 2))
            .task(id: "\(asset.localIdentifier)-\(Int(geometry.size.width))") {
                image = await requestThumbnail(for: asset, size: CGSize(width: geometry.size.width * 2, height: geometry.size.height * 2))
            }
        }
    }

    @ViewBuilder
    private func platformImage(_ image: PhotoPickerImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
    }

    private func requestThumbnail(for asset: PHAsset, size: CGSize) async -> PhotoPickerImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
