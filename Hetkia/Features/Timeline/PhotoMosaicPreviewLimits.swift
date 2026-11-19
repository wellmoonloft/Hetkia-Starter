import Foundation

enum PhotoMosaicPreviewLimits {
    /// Maximum mosaic cells drawn on home/history previews (includes the “more” tile when needed).
    static let maxTiles = 31
    /// Photo tiles shown before the trailing “more” cell.
    static let maxPhotoTiles = 30

    static func showsMoreIndicator(totalPhotoCount: Int) -> Bool {
        totalPhotoCount > maxTiles
    }

    static func layoutTileCount(totalPhotoCount: Int) -> Int {
        guard totalPhotoCount > 0 else { return 0 }
        if totalPhotoCount <= maxTiles { return totalPhotoCount }
        return maxTiles
    }

    static func visiblePhotoCount(totalPhotoCount: Int) -> Int {
        guard totalPhotoCount > 0 else { return 0 }
        if totalPhotoCount <= maxTiles { return totalPhotoCount }
        return maxPhotoTiles
    }

    static func hiddenPhotoCount(totalPhotoCount: Int) -> Int {
        max(0, totalPhotoCount - visiblePhotoCount(totalPhotoCount: totalPhotoCount))
    }
}