import SwiftUI

enum HetkiaPalette {
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let page = Color(red: 0.99, green: 0.98, blue: 0.95)
    static let ink = Color(red: 0.25, green: 0.23, blue: 0.20)
    static let secondaryInk = Color(red: 0.51, green: 0.47, blue: 0.41)
    static let amber = Color(red: 0.75, green: 0.52, blue: 0.27)
    static let line = Color(red: 0.87, green: 0.83, blue: 0.76)
}

struct JournalPageView: View {
    let entry: JournalEntry
    var photoCount: Int? = nil
    var bodyOverride: String? = nil
    var locationOverride: String? = nil
    var moodOverride: String? = nil

    @Environment(\.locale) private var locale

    private var dateText: String {
        entry.date.formatted(.dateTime.year().month(.wide).day().locale(locale))
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset = geometry.size.width * 0.075

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("brand.name")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .tracking(1.5)
                    Spacer()
                    Image(systemName: "sun.max")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(HetkiaPalette.amber)
                }

                Text(dateText)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                    .padding(.top, 4)

                PhotoMosaic(photoCount: photoCount ?? entry.photoCount, seed: entry.photoSeed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 13)
                    .padding(.bottom, 13)
                    .accessibilityLabel(String(format: HetkiaSystemLanguage.localizedString("page.photo-layout.accessibility", comment: "Photo layout accessibility label"), photoCount ?? entry.photoCount))

                Text(LocalizedStringKey(entry.titleKey))
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(HetkiaPalette.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    if let bodyOverride {
                        Text(verbatim: bodyOverride)
                    } else {
                        Text(LocalizedStringKey(entry.bodyKey))
                    }
                }
                .font(.system(size: 9))
                .lineSpacing(3)
                .foregroundStyle(HetkiaPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

                Spacer(minLength: 10)

                if locationOverride != nil || moodOverride != nil || entry.locationKey != nil || entry.moodKey != nil {
                    HStack(spacing: 5) {
                        if let location = locationOverride ?? entry.locationKey {
                            Image(systemName: "mappin")
                            if locationOverride != nil {
                                Text(verbatim: location)
                            } else {
                                Text(LocalizedStringKey(location))
                            }
                        }
                        Spacer(minLength: 4)
                        if let mood = moodOverride ?? entry.moodKey {
                            Image(systemName: "heart")
                            if moodOverride != nil {
                                Text(verbatim: mood)
                            } else {
                                Text(LocalizedStringKey(mood))
                            }
                        }
                    }
                    .font(.system(size: 8))
                    .foregroundStyle(HetkiaPalette.secondaryInk)
                }

                Rectangle()
                    .fill(HetkiaPalette.line)
                    .frame(height: 0.7)
                    .padding(.top, 9)
                    .padding(.bottom, 7)

                HStack {
                    Text("page.footer")
                    Spacer()
                    Text("brand.footer")
                }
                .font(.system(size: 7, weight: .regular, design: .serif))
                .foregroundStyle(HetkiaPalette.secondaryInk)
            }
            .foregroundStyle(HetkiaPalette.ink)
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, geometry.size.height * 0.045)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HetkiaPalette.page)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PhotoMosaic: View {
    let photoCount: Int
    let seed: Int
    private let gap: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            Group {
                switch photoCount {
                case 1:
                    tile(0)
                case 3:
                    VStack(spacing: gap) {
                        tile(0).frame(height: size.height * 0.64)
                        HStack(spacing: gap) {
                            tile(1)
                            tile(2)
                        }
                    }
                case 5:
                    VStack(spacing: gap) {
                        tile(0).frame(height: size.height * 0.57)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: gap) {
                            ForEach(1..<5, id: \.self) { index in tile(index) }
                        }
                    }
                case 7:
                    VStack(spacing: gap) {
                        tile(0).frame(height: size.height * 0.43)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: gap) {
                            ForEach(1..<7, id: \.self) { index in tile(index).aspectRatio(1, contentMode: .fit) }
                        }
                    }
                default:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: gap) {
                        ForEach(0..<9, id: \.self) { index in
                            tile(index).aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tile(_ index: Int) -> some View {
        SamplePhotoView(index: (seed + index) % 9)
    }
}

/// Offline, code-drawn sample scenes stand in for real photo assets in the prototype.
struct SamplePhotoView: View {
    let index: Int

    private var skyColors: [Color] {
        [
            Color(red: 0.83, green: 0.72, blue: 0.57),
            Color(red: 0.76, green: 0.79, blue: 0.72),
            Color(red: 0.84, green: 0.68, blue: 0.54),
            Color(red: 0.70, green: 0.75, blue: 0.70),
            Color(red: 0.88, green: 0.77, blue: 0.61),
            Color(red: 0.78, green: 0.72, blue: 0.66),
            Color(red: 0.72, green: 0.78, blue: 0.75),
            Color(red: 0.87, green: 0.73, blue: 0.57),
            Color(red: 0.77, green: 0.73, blue: 0.64)
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                LinearGradient(colors: [skyColors[index % skyColors.count], Color(red: 0.94, green: 0.84, blue: 0.67)], startPoint: .top, endPoint: .bottom)

                Circle()
                    .fill(Color(red: 0.98, green: 0.88, blue: 0.65).opacity(0.95))
                    .frame(width: min(width, height) * 0.23)
                    .position(x: width * (0.68 - CGFloat(index % 3) * 0.13), y: height * (0.30 + CGFloat(index % 2) * 0.08))

                HillShape(crest: 0.54 + CGFloat(index % 3) * 0.07, curve: 0.18)
                    .fill(Color(red: 0.62, green: 0.62, blue: 0.49))
                HillShape(crest: 0.68 - CGFloat(index % 2) * 0.06, curve: 0.23)
                    .fill(Color(red: 0.43, green: 0.49, blue: 0.40))
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct HillShape: Shape {
    let crest: CGFloat
    let curve: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height * crest))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height * (crest + curve)),
            control: CGPoint(x: rect.width * 0.48, y: rect.height * (crest - curve))
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}
