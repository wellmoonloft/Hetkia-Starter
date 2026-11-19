import SwiftUI

/// White serif captions used on year, month, and day browse tiles.
struct SavedJournalsOverlayCaption: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .allowsHitTesting(false)
    }
}

struct SavedJournalsBottomScrim: View {
    var body: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
            .allowsHitTesting(false)
    }
}