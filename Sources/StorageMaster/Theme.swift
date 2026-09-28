import SwiftUI
import StorageCore

enum Theme {
    static let blue = Color(hex: 0x356AE6)
    static let ink = Color(hex: 0x202B3C)
    static let secondary = Color(hex: 0x7B8494)
    static let background = Color(hex: 0xF8FAFD)
    static let sidebar = Color(hex: 0xF0F3F8)
    static let line = Color(hex: 0xE8EDF4)
    static let green = Color(hex: 0x2DA995)
    static let orange = Color(hex: 0xD9983D)
    static let purple = Color(hex: 0x9384D5)
    static let mapColors: [Color] = [
        Color(hex: 0x557AE7), Color(hex: 0x72A0EE), Color(hex: 0x56B8AD),
        Color(hex: 0x8C81CA), Color(hex: 0xC49ACD), Color(hex: 0xE4B76D),
        Color(hex: 0x8198AE), Color(hex: 0x84B7CB), Color(hex: 0x9FBCC5),
        Color(hex: 0x9FA9D6), Color(hex: 0xA9BDC6), Color(hex: 0xB6C8D3)
    ]
    static func color(_ kind: CleanupKind) -> Color {
        switch kind {
        case .cache: blue
        case .build: purple
        case .stale: Color(hex: 0x997747)
        case .installer: orange
        case .log: green
        case .large: Color(hex: 0x7394B6)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 17).padding(.vertical, 11)
            .foregroundStyle(.white)
            .background(Theme.blue.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 10)
            .foregroundStyle(Theme.ink)
            .background(configuration.isPressed ? Theme.line : .white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line, lineWidth: 1))
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.string(title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            if let subtitle { Text(L10n.string(subtitle)).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
        }
    }
}

struct FolderBreadcrumbs: View {
    let url: URL
    let enabled: Bool
    let onSelect: (URL) -> Void
    var fontSize: CGFloat = 11
    private var crumbs: [(title: String, url: URL)] { StorageFormat.breadcrumbs(url) }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(crumbs.indices, id: \.self) { index in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 8))
                        .foregroundStyle(Theme.secondary)
                }
                if index == crumbs.count - 1 {
                    Text(crumbs[index].title).foregroundStyle(Theme.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(crumbs[index].url.path)
                } else {
                    Button { onSelect(crumbs[index].url) } label: {
                        Text(crumbs[index].title).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.blue)
                    .disabled(!enabled)
                    .help(L10n.format("扫描 %@", crumbs[index].url.path))
                    .accessibilityLabel(L10n.format("扫描上级目录 %@", crumbs[index].title))
                }
            }
        }
        .font(.system(size: fontSize))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SymbolBadge: View {
    var symbol: String
    var color: Color = Theme.blue
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(color).frame(width: size, height: size)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }
}

@MainActor
struct AppBrandIcon: View {
    private static let icon = Bundle.main.url(forResource: "StorageMasterIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        if let icon = Self.icon {
            Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(Theme.blue)
                Image(systemName: "externaldrive.fill").font(.system(size: 23)).foregroundStyle(.white)
            }
        }
    }
}

struct FileDatesView: View {
    let created: Date?
    let modified: Date?
    var modificationLabel = "修改"
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.format("%@ %@", L10n.string(modificationLabel), StorageFormat.date(modified)))
                .foregroundStyle(Theme.ink.opacity(0.8))
            Text(L10n.format("创建 %@", StorageFormat.date(created)))
                .foregroundStyle(Theme.secondary)
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .lineLimit(1)
        .frame(width: 132, alignment: .leading)
        .help(L10n.format("%@时间：%@\n创建时间：%@", L10n.string(modificationLabel),
                          StorageFormat.date(modified, includeTime: true),
                          StorageFormat.date(created, includeTime: true)))
        .accessibilityElement(children: .combine)
    }
}
