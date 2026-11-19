import SwiftUI

struct PhotoMosaicMoreTile: View {
    let hiddenCount: Int
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(.black.opacity(0.28))
            VStack(spacing: 4) {
                Text("timeline.photos.more")
                    .font(.system(size: 13, weight: .semibold))
                if hiddenCount > 0 {
                    Text(String(format: HetkiaSystemLanguage.localizedString("timeline.photos.more.count", comment: ""), hiddenCount))
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}