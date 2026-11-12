import SwiftUI

struct HomeHistoryFloatingBar: View {
  @Binding var rootTab: TimelineRootTab
  var historyBrowse: SavedJournalsBrowseMode?
  var onSelectMonth: (() -> Void)?
  var onSelectYear: (() -> Void)?
  var onSelectAll: (() -> Void)?
  var onSelectSavedJournalsTab: (() -> Void)?

  var body: some View {
    HStack(spacing: 8) {
      homeHistoryCapsule
      if rootTab == .savedJournals, let historyBrowse {
        historyBrowseCapsule(historyBrowse)
      }
    }
    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: rootTab)
    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: historyBrowse)
  }

  private var homeHistoryCapsule: some View {
    HStack(spacing: 0) {
      segment("timeline.tab.onthisday", isSelected: rootTab == .onThisDay) {
        rootTab = .onThisDay
      }
      segment("timeline.tab.saved-journals", isSelected: rootTab == .savedJournals) {
        onSelectSavedJournalsTab?()
        rootTab = .savedJournals
      }
    }
    .padding(.horizontal, 5)
    .frame(height: 52)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.44), lineWidth: 0.8))
    .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 12, x: 0, y: 5)
  }

  private func historyBrowseCapsule(_ mode: SavedJournalsBrowseMode) -> some View {
    HStack(spacing: 0) {
      segment("bottom.month", isSelected: mode == .month) {
        onSelectMonth?()
      }
      segment("bottom.year", isSelected: mode == .year) {
        onSelectYear?()
      }
      segment("bottom.all", isSelected: mode == .all) {
        onSelectAll?()
      }
    }
    .padding(.horizontal, 5)
    .frame(height: 52)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.44), lineWidth: 0.8))
    .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 12, x: 0, y: 5)
  }

  private func segment(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .foregroundStyle(isSelected ? HetkiaPalette.amber : HetkiaPalette.ink)
        .frame(minWidth: 56)
        .frame(height: 42)
        .padding(.horizontal, 4)
        .background(isSelected ? .white.opacity(0.58) : .clear, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}
