import Foundation

enum TimelineRootTab: Equatable {
  case onThisDay
  case savedJournals
}

enum TimelineRootRoute: Hashable {
  case onThisDay(dayKey: String)
  case savedJournal(dayKey: String)
}

struct TimelineScrollMetrics: Equatable {
  var offset: CGFloat = 0
  var contentHeight: CGFloat = 0
  var viewportHeight: CGFloat = 0

  var contentExceedsViewport: Bool {
    guard viewportHeight > 0, contentHeight > 0 else { return false }
    return contentHeight > viewportHeight + 4
  }
}

#if !os(macOS)
import SwiftUI

extension View {
  @ViewBuilder
  func timelineTracksScrollMetrics(_ metrics: Binding<TimelineScrollMetrics>) -> some View {
    if #available(iOS 18.0, *) {
      onScrollGeometryChange(for: TimelineScrollMetrics.self) { geometry in
        TimelineScrollMetrics(
          offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
          contentHeight: geometry.contentSize.height,
          viewportHeight: geometry.containerSize.height
        )
      } action: { _, newValue in
        metrics.wrappedValue = newValue
      }
    } else {
      self
    }
  }
}
#endif
