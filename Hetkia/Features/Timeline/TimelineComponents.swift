import SwiftUI

struct ScrollContentFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct TimelineDateLabel: View {
    let date: Date
    @Environment(\.locale) private var locale

    var body: some View {
        Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale)))
    }
}

struct TodayStatusCard: View {
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(HetkiaPalette.amber)
                .frame(width: 42, height: 42)
                .background(HetkiaPalette.paper, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("timeline.today.title")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink)
                Text("timeline.today.message")
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    Text("timeline.today.action")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HetkiaPalette.amber)
                        .padding(.top, 3)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(HetkiaPalette.line.opacity(0.65), lineWidth: 0.7)
        }
    }
}

struct TimelineEntryCard: View {
    let entry: JournalEntry
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationLink(value: entry) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.date.formatted(.dateTime.month(.wide).day().locale(locale)))
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(HetkiaPalette.ink)
                    Text(entry.date.formatted(.dateTime.weekday(.wide).locale(locale)))
                        .font(.system(size: 11))
                        .foregroundStyle(HetkiaPalette.secondaryInk)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HetkiaPalette.secondaryInk.opacity(0.8))
                }

                HStack(spacing: 10) {
                    SamplePhotoView(index: entry.photoSeed)
                        .frame(width: 88, height: 102)
                    if entry.photoCount > 1 {
                        SamplePhotoView(index: (entry.photoSeed + 1) % 9)
                            .frame(maxWidth: .infinity)
                            .frame(height: 102)
                    }
                    if entry.photoCount > 3 {
                        SamplePhotoView(index: (entry.photoSeed + 2) % 9)
                            .frame(maxWidth: .infinity)
                            .frame(height: 102)
                    }
                }

                Text(LocalizedStringKey(entry.titleKey))
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink)
                Text(LocalizedStringKey(entry.excerptKey))
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(HetkiaPalette.secondaryInk)

                HStack(spacing: 8) {
                    if let locationKey = entry.locationKey {
                        Label {
                            Text(LocalizedStringKey(locationKey))
                        } icon: {
                            Image(systemName: "mappin")
                        }
                    }
                    if let moodKey = entry.moodKey {
                        Label {
                            Text(LocalizedStringKey(moodKey))
                        } icon: {
                            Image(systemName: "heart")
                        }
                    }
                    Spacer(minLength: 0)
                    Text(String(format: NSLocalizedString("timeline.photo-count", comment: "Number of sample photos"), entry.photoCount))
                }
                .font(.system(size: 9))
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .lineLimit(1)
            }
            .padding(14)
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(HetkiaPalette.line.opacity(0.6), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

struct TimelineSectionHeading: View {
    let date: Date
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(date.formatted(.dateTime.year().month(.wide).locale(locale)))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HetkiaPalette.secondaryInk)
            Spacer()
            Rectangle()
                .fill(HetkiaPalette.line)
                .frame(height: 0.7)
        }
        .padding(.top, 6)
    }
}

struct BottomNavigationBar: View {
    let selectedMode: TimelineBrowseMode
    let isPhotoWall: Bool
    let onSettings: () -> Void
    let onYear: () -> Void
    let onMonth: () -> Void
    let onAll: () -> Void
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                tab("bottom.year", symbol: "calendar", isSelected: selectedMode == .year, action: onYear)
                tab("bottom.month", symbol: "calendar.day.timeline.left", isSelected: selectedMode == .month, action: onMonth)
                tab("bottom.all", symbol: "list.bullet", isSelected: selectedMode == .all, action: onAll)
            }
            .padding(.horizontal, 5)
            .frame(height: 52)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.44), lineWidth: 0.8))
            .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 12, x: 0, y: 5)

            roundButton("bottom.settings", symbol: "slider.horizontal.3", action: onSettings)

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(HetkiaPalette.ink)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.44), lineWidth: 0.8))
                    .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 12, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("bottom.search"))
        }
        .padding(.horizontal, 12)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedMode)
        .animation(.easeInOut(duration: 0.2), value: isPhotoWall)
    }

    private func roundButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(HetkiaPalette.ink)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.44), lineWidth: 0.8))
                .shadow(color: HetkiaPalette.ink.opacity(0.12), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    private func tab(_ title: LocalizedStringKey, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? HetkiaPalette.amber : HetkiaPalette.ink)
            .frame(width: 72)
            .frame(height: 42)
            .background(isSelected ? .white.opacity(0.58) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
