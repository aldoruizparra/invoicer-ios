import SwiftUI
import UIKit

// "Industry" system on native iOS structure: steel accent, Barlow / Barlow
// Condensed, square corners, hairline groups and registration marks on primary
// objects. Colors live in the asset catalog with dark variants.

// Asset-catalog colors (Ground, Ink, InkSecondary, AccentInk, AccentFill, AccentTint,
// Destructive, …) get generated `Color.ground`, `Color.ink`, … symbols.
extension Color {
    static let accentSteel = Color("Accent")
    /// Text at 16% — hairlines.
    static let divider = Color("Ink").opacity(0.16)
}

enum FontName {
    static let regular = "Barlow-Regular"
    static let medium = "Barlow-Medium"
    static let semibold = "Barlow-SemiBold"
    static let condensed = "BarlowCondensed-SemiBold"
}

extension Font {
    /// Barlow body text; scales with Dynamic Type.
    static func barlow(_ size: CGFloat = 17, _ name: String = FontName.regular,
                       relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(name, size: size, relativeTo: style)
    }

    /// Barlow Condensed SemiBold: titles, section headers, buttons, totals.
    static func condensed(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(FontName.condensed, size: size, relativeTo: style)
    }
}

extension UIFont {
    static func scaled(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

// MARK: - text styles

extension View {
    /// 40pt condensed large title, used where the screen draws its own heading.
    func largeTitleStyle() -> some View {
        font(.condensed(40, relativeTo: .largeTitle)).tracking(-0.6).foregroundStyle(Color.ink)
    }

    /// 14pt uppercase, tracked +0.08em section header.
    func sectionHeaderStyle() -> some View {
        font(.condensed(14, relativeTo: .footnote)).tracking(14 * 0.08).textCase(.uppercase)
            .foregroundStyle(Color.inkSecondary)
    }

    /// Small uppercase kicker in accent, e.g. "REPEAT LAST · #1043".
    func kickerStyle() -> some View {
        font(.condensed(13, relativeTo: .caption)).tracking(13 * 0.12).textCase(.uppercase)
            .foregroundStyle(Color.accentInk)
    }

    func footnoteStyle() -> some View {
        font(.barlow(13, relativeTo: .footnote)).foregroundStyle(Color.inkSecondary)
    }
}

/// Section header text for lists and forms.
struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).sectionHeaderStyle()
            .padding(.leading, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - hairline groups

/// Square, transparent group cell with a 1pt hairline border instead of a white
/// inset-grouped card. Each cell draws its sides and bottom; the first cell of a
/// group also draws the top, so stacked cells read as one bordered group.
struct HairlineCell: ViewModifier {
    var first: Bool
    var minHeight: CGFloat = 50
    var fill: Color = .clear
    var verticalPadding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(fill)
            .overlay(HairlineBorder(top: first))
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

struct HairlineBorder: View {
    var top: Bool
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            let w = size.width, h = size.height
            p.move(to: CGPoint(x: 0.5, y: 0)); p.addLine(to: CGPoint(x: 0.5, y: h))
            p.move(to: CGPoint(x: w - 0.5, y: 0)); p.addLine(to: CGPoint(x: w - 0.5, y: h))
            p.move(to: CGPoint(x: 0, y: h - 0.5)); p.addLine(to: CGPoint(x: w, y: h - 0.5))
            if top { p.move(to: CGPoint(x: 0, y: 0.5)); p.addLine(to: CGPoint(x: w, y: 0.5)) }
            ctx.stroke(p, with: .color(.divider), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func hairlineCell(first: Bool = false, minHeight: CGFloat = 50, fill: Color = .clear,
                      verticalPadding: CGFloat = 0) -> some View {
        modifier(HairlineCell(first: first, minHeight: minHeight, fill: fill, verticalPadding: verticalPadding))
    }

    /// Row chrome for a List row whose look comes from a ButtonStyle: clear background,
    /// no system separator, our insets. (List row modifiers must be on the row itself.)
    func listRowChrome() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// A list row that is just spacing/decoration (no border, no background).
    func plainRow(top: CGFloat = 0, bottom: CGFloat = 0, horizontal: CGFloat = 16) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Ground background behind a List/Form, with our tight row metrics.
    func industryList() -> some View {
        listStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.ground)
            .environment(\.defaultMinListRowHeight, 0)
            .listSectionSpacing(0)
    }
}

/// A tappable hairline row: tints accent on press, like the prototype's rows.
struct RowButtonStyle: ButtonStyle {
    var first = false
    var minHeight: CGFloat = 50
    var verticalPadding: CGFloat = 0
    var fill: Color = .clear

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.ink)
            .contentShape(Rectangle())
            .hairlineCell(first: first, minHeight: minHeight,
                          fill: configuration.isPressed ? .accentTint : fill,
                          verticalPadding: verticalPadding)
    }
}

/// "›" disclosure, as in the prototype.
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.inkTertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - blueprint registration marks

/// Small "+" crosshairs offset 6pt outside each corner. Only for primary buttons,
/// the Repeat card, the PDF page preview and the weekly totals plate.
struct BlueprintMarks: ViewModifier {
    var bordered = false

    func body(content: Content) -> some View {
        content
            .overlay { if bordered { Rectangle().strokeBorder(Color.divider, lineWidth: 1) } }
            .overlay(alignment: .topLeading) { RegistrationMark().offset(x: -11, y: -11) }
            .overlay(alignment: .topTrailing) { RegistrationMark().offset(x: 11, y: -11) }
            .overlay(alignment: .bottomLeading) { RegistrationMark().offset(x: -11, y: 11) }
            .overlay(alignment: .bottomTrailing) { RegistrationMark().offset(x: 11, y: 11) }
    }
}

/// 11pt cross, 1pt stroke, text at 55%. Its center sits 0.5pt outside the corner
/// (CSS: top/left -6px on an 11px box).
struct RegistrationMark: View {
    var body: some View {
        Canvas { ctx, _ in
            var p = Path()
            p.move(to: CGPoint(x: 5.5, y: 0)); p.addLine(to: CGPoint(x: 5.5, y: 11))
            p.move(to: CGPoint(x: 0, y: 5.5)); p.addLine(to: CGPoint(x: 11, y: 5.5))
            ctx.stroke(p, with: .color(Color.ink.opacity(0.55)), lineWidth: 1)
        }
        .frame(width: 11, height: 11)
        .padding(5.5)   // keeps the offset math simple: the cross center is 11pt from the frame edge
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func blueprint(bordered: Bool = false) -> some View { modifier(BlueprintMarks(bordered: bordered)) }
}

// MARK: - buttons

/// Filled, square, uppercase condensed label, registration marks.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var marks = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.condensed(18, relativeTo: .headline))
            .tracking(18 * 0.06)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(configuration.isPressed ? Color.accentFillPressed : Color.accentFill)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .modifier(ConditionalMarks(enabled: marks))
    }
}

private struct ConditionalMarks: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.blueprint() } else { content }
    }
}

/// Hairline-bordered, transparent, uppercase condensed label.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .accentInk
    var pressedFill: Color = .accentTint
    var height: CGFloat = 48
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.condensed(16, relativeTo: .headline))
            .tracking(16 * 0.06)
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(configuration.isPressed ? pressedFill : .clear)
            .overlay(Rectangle().strokeBorder(Color.divider, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Square toolbar icon button with a hairline border (the "+" on Invoices).
struct SquareIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(Color.accentInk)
            .frame(width: 36, height: 36)
            .background(configuration.isPressed ? Color.accentTint : .clear)
            .overlay(Rectangle().strokeBorder(Color.divider, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Square-ish switch (2pt corners) in accent; keeps Toggle semantics for VoiceOver.
struct SquareToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(configuration.isOn ? Color.accentFill : Color.toggleOff)
                    .frame(width: 51, height: 31)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.2), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

/// Small square destructive "−" (remove a line, delete in edit mode).
struct MinusBadge: View {
    var body: some View {
        Image(systemName: "minus")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Color.destructive)
    }
}

// MARK: - toast

@MainActor
@Observable
final class Toast {
    var message: String?
    private var task: Task<Void, Never>?

    func show(_ message: String) {
        self.message = message
        UIAccessibility.post(notification: .announcement, argument: message)
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation { self?.message = nil }
        }
    }
}

struct ToastOverlay: ViewModifier {
    let toast: Toast
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = toast.message {
                Text(message)
                    .font(.barlow(15, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.toastBackground)
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 12)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { toast.message = nil } }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.snappy, value: toast.message)
    }
}

extension View {
    func toastOverlay(_ toast: Toast) -> some View { modifier(ToastOverlay(toast: toast)) }
}

// MARK: - UIKit appearance (nav bar, tab bar, segmented control)

enum Appearance {
    @MainActor
    static func apply() {
        let ink = UIColor(named: "Ink")!
        let inkSecondary = UIColor(named: "InkSecondary")!
        let accentInk = UIColor(named: "AccentInk")!
        let accentFill = UIColor(named: "AccentFill")!
        let ground = UIColor(named: "Ground")!
        let divider = ink.withAlphaComponent(0.16)

        // Navigation bar: condensed titles, ground background, hairline when scrolled.
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        nav.backgroundColor = ground.withAlphaComponent(0.86)
        nav.shadowColor = divider
        nav.largeTitleTextAttributes = [.font: UIFont.scaled(FontName.condensed, 40, .largeTitle),
                                        .foregroundColor: ink, .kern: -0.6]
        nav.titleTextAttributes = [.font: UIFont.scaled(FontName.condensed, 19, .headline),
                                   .foregroundColor: ink, .kern: 0.4]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: UIFont.scaled(FontName.regular, 17, .body)]
        nav.buttonAppearance = button
        nav.backButtonAppearance = button
        let done = UIBarButtonItemAppearance()
        done.normal.titleTextAttributes = [.font: UIFont.scaled(FontName.semibold, 17, .body)]
        nav.doneButtonAppearance = done
        let edge = nav.copy()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = nav.largeTitleTextAttributes
        edge.titleTextAttributes = nav.titleTextAttributes
        edge.buttonAppearance = button
        edge.backButtonAppearance = button
        edge.doneButtonAppearance = done
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = edge

        // Tab bar: full width, blurred ground, uppercase condensed labels, 2pt accent
        // line above the selected tab (drawn by the selection indicator image).
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        tab.backgroundColor = ground.withAlphaComponent(0.86)
        tab.shadowColor = divider
        let font = UIFont.scaled(FontName.condensed, 15, .footnote)
        for layout in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = [.font: font, .foregroundColor: inkSecondary, .kern: 15 * 0.08]
            layout.selected.titleTextAttributes = [.font: font, .foregroundColor: accentInk, .kern: 15 * 0.08]
            layout.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -13)
            layout.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -13)
        }
        tab.selectionIndicatorImage = selectionLine(color: accentInk)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().selectionIndicatorImage = tab.selectionIndicatorImage
        UITabBar.appearance().itemPositioning = .fill
        UITabBar.appearance().itemSpacing = 0

        // Segmented control: accent selected segment, condensed uppercase labels.
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = accentFill
        let segFont = UIFont.scaled(FontName.condensed, 15, .subheadline)
        seg.setTitleTextAttributes([.font: segFont, .foregroundColor: ink, .kern: 15 * 0.06], for: .normal)
        seg.setTitleTextAttributes([.font: segFont, .foregroundColor: UIColor.white, .kern: 15 * 0.06], for: .selected)
        seg.backgroundColor = .clear

        UITextField.appearance().tintColor = accentInk
    }

    /// A tab-height image that is transparent except for a 2pt line at the top.
    @MainActor
    static func selectionLine(color: UIColor) -> UIImage {
        let size = CGSize(width: 8, height: 49)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 2))
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0),
                                    resizingMode: .stretch)
    }
}
