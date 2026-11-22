import SwiftUI
import AppKit

/// WeChat-Input-inspired macOS Settings design tokens (adaptive Light & Dark mode).
public enum ConsoleTheme {
    /// Signature crisp emerald accent matching WeChat Input's calm, modern aesthetic.
    public static let accent = Color(red: 0.06, green: 0.76, blue: 0.48)

    public static func canvasBackground(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.09, green: 0.095, blue: 0.106)
            : Color(red: 0.945, green: 0.950, blue: 0.958)
    }

    public static func cardBackground(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.145, green: 0.150, blue: 0.165)
            : Color.white
    }

    public static func cardBorder(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    public static func cardShadow(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.28) : Color.black.opacity(0.045)
    }

    public static func divider(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    public static func buttonBackground(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.08) : Color.white
    }

    public static func buttonBorder(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.14)
    }
}

/// Full-bleed console page scaffold with generous WeChat-Input-style whitespace and clean page title.
public struct ConsolePageContainer<Trailing: View, Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let title: String
    public let subtitle: String?
    @ViewBuilder public let trailing: () -> Trailing
    @ViewBuilder public let content: () -> Content

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.primary)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    trailing()
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)

                content()
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(ConsoleTheme.canvasBackground(isDark: isDark))
    }
}

public extension ConsolePageContainer where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// Elevated rounded white/charcoal settings card with hairline border and subtle depth.
public struct ConsoleCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let title: String?
    @ViewBuilder public let content: () -> Content

    public init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(ConsoleTheme.cardBackground(isDark: isDark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(ConsoleTheme.cardBorder(isDark: isDark), lineWidth: 0.7)
                    )
                    .shadow(color: ConsoleTheme.cardShadow(isDark: isDark), radius: 7, x: 0, y: 2)
            )
        }
    }
}

/// Standard two-column settings row matching WeChat Input's generous typography & spacing.
public struct ConsoleRow<Trailing: View>: View {
    public let title: String
    public let subtitle: String?
    @ViewBuilder public let trailing: () -> Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

/// Hairline inset divider between rows inside a `ConsoleCard`.
public struct ConsoleRowDivider: View {
    @Environment(\.colorScheme) private var colorScheme
    public var inset: CGFloat

    public init(inset: CGFloat = 18) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(ConsoleTheme.divider(isDark: colorScheme == .dark))
            .frame(height: 0.7)
            .padding(.horizontal, inset)
    }
}

/// WeChat-Input-style custom pill toggle switch (zero `@State` macro, emerald active track).
public struct ConsoleSwitch: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding public var isOn: Bool
    public var disabled: Bool

    public init(isOn: Binding<Bool>, disabled: Bool = false) {
        self._isOn = isOn
        self.disabled = disabled
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)
        Button {
            guard !disabled else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? ConsoleTheme.accent : (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)))
                    .frame(width: 38, height: 22)

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, x: 0, y: 0.8)
                    .padding(2)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.45 : 1.0)
        .disabled(disabled)
    }
}

/// WeChat-Input-style radio selection row with crisp emerald outer ring and centered white dot.
public struct ConsoleRadioRow<Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let title: String
    public let subtitle: String?
    public let isSelected: Bool
    public let action: () -> Void
    @ViewBuilder public let trailing: () -> Trailing

    @StateObject private var hover = HoverTracker()

    public init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)
        Button(action: action) {
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(ConsoleTheme.accent)
                            .frame(width: 17, height: 17)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6.5, height: 6.5)
                    } else {
                        Circle()
                            .strokeBorder(isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.22), lineWidth: 1.4)
                            .frame(width: 17, height: 17)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12.5)
            .background(hover.isHovering ? Color.primary.opacity(isDark ? 0.04 : 0.025) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
    }
}

public extension ConsoleRadioRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.init(title: title, subtitle: subtitle, isSelected: isSelected, action: action, trailing: { EmptyView() })
    }
}

public enum ConsoleButtonVariant {
    case standard
    case prominent
    case destructive
}

/// Crisp WeChat-Input-style bordered action button (`设置...`, `管理...`, `启用...`).
public struct ConsoleActionButton: View {
    @Environment(\.colorScheme) private var colorScheme
    public let title: String
    public let variant: ConsoleButtonVariant
    public let disabled: Bool
    public let action: () -> Void

    @StateObject private var hover = HoverTracker()

    public init(
        _ title: String,
        variant: ConsoleButtonVariant = .standard,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: variant == .prominent ? .semibold : .regular))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 13)
                .padding(.vertical, 5.5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(backgroundColor(isDark: isDark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(borderColor(isDark: isDark), lineWidth: 0.8)
                        )
                        .shadow(color: variant == .standard && !isDark ? Color.black.opacity(0.04) : .clear, radius: 1.5, y: 0.8)
                )
                .opacity(disabled ? 0.42 : (hover.isHovering ? 0.86 : 1.0))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover.isHovering = $0 }
    }

    private var foregroundColor: Color {
        switch variant {
        case .standard: return .primary
        case .prominent: return .white
        case .destructive: return .red
        }
    }

    private func backgroundColor(isDark: Bool) -> Color {
        switch variant {
        case .standard: return ConsoleTheme.buttonBackground(isDark: isDark)
        case .prominent: return ConsoleTheme.accent
        case .destructive: return Color.red.opacity(isDark ? 0.16 : 0.08)
        }
    }

    private func borderColor(isDark: Bool) -> Color {
        switch variant {
        case .standard: return ConsoleTheme.buttonBorder(isDark: isDark)
        case .prominent: return Color.clear
        case .destructive: return Color.red.opacity(0.28)
        }
    }
}

/// Clean rounded sidebar navigation row with solid emerald active pill.
public struct ConsoleSidebarItem: View {
    @Environment(\.colorScheme) private var colorScheme
    public let title: String
    public let icon: String
    public let isSelected: Bool
    public let action: () -> Void

    @StateObject private var hover = HoverTracker()

    public init(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.74))
                    .frame(width: 20, alignment: .center)

                Text(title)
                    .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.88))
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? ConsoleTheme.accent
                            : (hover.isHovering ? Color.primary.opacity(isDark ? 0.07 : 0.05) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
    }
}

/// Compact inline notice banner for status/permission messages inside console pages.
public struct ConsoleBanner<Trailing: View>: View {
    public let icon: String
    public let tint: Color
    public let title: String
    public let subtitle: String?
    @ViewBuilder public let trailing: () -> Trailing

    public init(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tint.opacity(0.24), lineWidth: 0.7)
                )
        )
    }
}

public extension ConsoleBanner where Trailing == EmptyView {
    init(icon: String, tint: Color, title: String, subtitle: String? = nil) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}
