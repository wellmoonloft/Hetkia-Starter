#if os(iOS)
import WidgetKit

enum HetkiaWidgetTimelineReloader {
    static func reloadVisibleKinds() {
        WidgetCenter.shared.reloadTimelines(ofKind: "Hetkia.OnThisDay")
        WidgetCenter.shared.reloadTimelines(ofKind: "Hetkia.PublishQuick")
    }
}
#endif
