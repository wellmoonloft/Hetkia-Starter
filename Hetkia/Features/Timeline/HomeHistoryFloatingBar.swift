import SwiftUI

struct HomeHistoryFloatingBar: View {
  @Binding var rootTab: TimelineRootTab

  var body: some View {
    HStack(spacing: 0) {
      tab("timeline.tab.onthisday", isSelected: rootTab == .onThisDay) {
        rootTab = .onThisDay
      }
      tab("timeline.tab.saved-journals", isSelected: rootTab == .savedJournals) {
        rootTab = .savedJournals
      }
    }
    .padding(.horizontal, 5)
    .frame(height: 52)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.44), lineWidth: 0.8))
    .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 12, x: 0, y: 5)
    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: rootTab)
  }

  private func tab(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .foregroundStyle(isSelected ? HetkiaPalette.amber : HetkiaPalette.ink)
        .frame(minWidth: 72)
        .frame(height: 42)
        .padding(.horizontal, 6)
        .background(isSelected ? .white.opacity(0.58) : .clear, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}
