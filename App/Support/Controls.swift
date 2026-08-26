import SwiftUI
import AppKit
import WellkeptCore

//  Controls.swift
//  Wellkept — App/Support
//
//  The controls the app has to draw itself, ported from Lode's and Waypoint's `Theme.swift`.
//
//  ## Why these exist at all
//
//  On macOS the bordered button families (`.bordered`, `.borderedProminent`, and the `.automatic`
//  style a bare `Button` resolves to) and the `.segmented` picker are drawn by **AppKit**, which
//  hardcodes the system font at the current `controlSize` and drops the environment font entirely.
//  Setting `.font(.appBody)` on the button — or on any ancestor, since `.font()` is only ever an
//  environment write — has no effect on them. Waypoint's onboarding buttons stayed system-face
//  under a panel-wide `.font(.appBody)` for exactly this reason.
//
//  A non-primitive `ButtonStyle` hands us `configuration.label` as plain SwiftUI, so the app face
//  sticks while SwiftUI keeps the button's behaviour — actions, `.disabled`, `.help`,
//  `.keyboardShortcut`. The `.plain` / `.link` / `.borderless` styles are drawn by SwiftUI and do
//  honour the environment font, so they are left alone.
//
//  ## What this file deliberately does NOT do
//
//  It does not replace `Toggle`, `Stepper`, `DatePicker`, `Menu` chrome or the focus ring. Those
//  are AppKit-drawn too, and hand-rolling them forfeits accessibility, focus rings, Increase
//  Contrast adaptation, and next September's platform refresh. macOS 27 restyles system chrome and
//  apps get it free on rebuild — which only works for the controls we did not replace.

// MARK: - Buttons

/// The app's push button. `.buttonStyle(.app)` where `.bordered` (or a bare `Button`) was,
/// `.buttonStyle(.appProminent)` where `.borderedProminent` was.
///
/// ⚠️ **Prominent fills with the palette's bronze, not with `.tint`.**
///
/// Lode fills with `.tint` and sets the tint once at the window root. Wellkept must not: bronze
/// appears in **exactly three places** — the selected sidebar row, the main button, and section
/// headings — and a root `.tint(bronze)` would put it on every checkbox, slider, focus ring and
/// menu highlight in the app. Naming the fill here is what keeps that promise enforceable.
struct AppButtonStyle: ButtonStyle {
    /// Filled with the app's identity colour, as `.borderedProminent` is filled with the accent.
    var prominent = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.palette) private var palette

    // Type and box metrics per `controlSize`, so a call site pairing this with
    // `.controlSize(.small)` still reads as small. Padding stays fixed while the label scales with
    // `AppFont.scale`, which is what lets the button grow with the app's text size.
    private var font: Font {
        switch controlSize {
        case .mini: .appCaption2
        case .small: .appCaption
        case .large: .appBody
        case .extraLarge: .appTitle3
        default: .appCallout
        }
    }
    private var hPad: CGFloat {
        switch controlSize {
        case .mini: 7
        case .small: 9
        case .large: 14
        case .extraLarge: 18
        default: 12
        }
    }
    private var vPad: CGFloat {
        switch controlSize {
        case .mini: 1
        case .small: 2
        case .large: 6
        case .extraLarge: 9
        default: 4
        }
    }
    private var minHeight: CGFloat {
        switch controlSize {
        case .mini: 14
        case .small: 18
        case .large: 28
        case .extraLarge: 36
        default: 22
        }
    }
    private var radius: CGFloat { controlSize == .mini || controlSize == .small ? 5 : Radius.small }

    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        let shape = Radius.shape(radius)
        let fill = destructive ? palette.problem : palette.identity
        return configuration.label
            .font(font)
            // Only claim the label colour where the native style does, so a call site that tints a
            // plain button's label from outside keeps working.
            .foregroundStyle(prominent ? AnyShapeStyle(palette.ink(on: fill))
                             : destructive ? AnyShapeStyle(palette.problem)
                             : AnyShapeStyle(.foreground))
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .frame(minHeight: minHeight)
            // ⚠️ Fill and press state both live in the background, and the label's frame never
            // changes. A button that resizes on press or on state is a moving target; in-place is
            // fine, moving is not.
            .background {
                if prominent {
                    shape.fill(fill)
                    if configuration.isPressed { shape.fill(Color.black.opacity(0.16)) }
                } else {
                    shape.fill(Color(nsColor: .controlColor))
                        .shadow(color: .black.opacity(0.10), radius: 0.5, y: 0.5)
                    if configuration.isPressed { shape.fill(Color.primary.opacity(0.12)) }
                }
            }
            .overlay { if !prominent { shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: Hairline.thin) } }
            .contentShape(shape)
            // The disabled look. A greyed button is the one place low contrast IS the message —
            // see DESIGN §3.5 — so this is deliberate rather than an oversight.
            .opacity(isEnabled ? 1 : 0.4)
            .appAnimation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    /// The app-font replacement for `.bordered` and for a bare `Button`.
    static var app: AppButtonStyle { .init() }
    /// The app-font replacement for `.borderedProminent`, filled with the app's bronze.
    /// **This is the section's one verb button.**
    static var appProminent: AppButtonStyle { .init(prominent: true) }
}

// MARK: - Segmented control

/// A segmented control in the app's face — native `.segmented` renders in the system font and
/// ignores a custom one.
///
/// Selection is carried by **three** channels, not one: a fill, a weight change, and a border. The
/// border is what survives Differentiate Without Color, where the fill says nothing.
///
/// ⚠️ Every measurement scales with the text. The label is `.appCallout`, which doubles at the
/// largest text size; a box with literal 12/5 padding around it is visually *tighter* at 200% for
/// the one user who turned the text up because they needed the air, and eventually clips.
struct SegmentedControl<T: Hashable>: View {
    let items: [(value: T, label: String)]
    @Binding var selection: T

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    init(items: [(value: T, label: String)], selection: Binding<T>) {
        self.items = items
        self._selection = selection
    }

    var body: some View {
        // Neutral, not bronze: this is a control, and bronze is spoken for three times over.
        let ink = Color.primary
        let shape = Radius.shape(AppFont.pt(Radius.small))
        return HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let isSel = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.label)
                        .font(.appCallout.weight(isSel ? .semibold : .regular))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .padding(.horizontal, AppFont.pt(Space.block))
                        .padding(.vertical, AppFont.pt(5))
                        .background(isSel ? ink.opacity(0.10) : Color.clear, in: shape)
                        .overlay(isSel
                                 ? shape.strokeBorder(ink.opacity(differentiate ? 0.85 : 0.35),
                                                      lineWidth: differentiate ? Hairline.selection : Hairline.thin)
                                 : nil)
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSel ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(AppFont.pt(3))
        .background(Color.primary.opacity(0.06),
                    in: Radius.shape(AppFont.pt(Radius.control)))
        .appAnimation(Motion.selection, value: selection)
    }
}

// MARK: - Disclosure

/// The app's one disclosure control — **"Options", "What was checked", and nothing anonymous.**
///
/// ⚠️ A bare chevron is banned, and so is hover-to-reveal and any gesture. Hide detail, never hide
/// capability: the control is a full-width labelled button that says what is behind it, states
/// whether it is open, and is reachable by keyboard. Engst's test is whether you could talk
/// someone through this over the phone; "click the small grey arrow" fails it.
///
/// **At most one of these per view** (Apple's rule, adopted). The most-used items stay above it.
struct LabelledDisclosure<Content: View>: View {
    let label: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    init(_ label: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.label = label
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Button {
                Motion.run(Motion.chrome) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Space.row) {
                    Text(label).font(.appHeadline)
                    Image(systemName: "chevron.right")
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        // The chevron restates the button's own state, which the label and the
                        // expanded trait already say out loud.
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, AppFont.pt(6))
                .padding(.horizontal, Space.block)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: Radius.shape(Radius.control))
                .contentShape(Radius.shape(Radius.control))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .appAnimation(Motion.chrome, value: isExpanded)

            if isExpanded {
                content
                    .padding(.horizontal, Space.block)
                    .transition(.faceFade)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

/// The shared row treatment: stripe, hover, selection, one row height.
///
/// One treatment rather than one per list. Lode had twenty private row builders that disagreed on
/// the stripe alpha (three values), on which rows to stripe (two phases — one list striped odd
/// rows while another striped even), and on row height.
private struct AppRow: ViewModifier {
    var index: Int
    var selected: Bool
    /// A semantic wash laid *over* the stripe rather than replacing it, so striping still does its
    /// job on a screen where forty rows are read at a time.
    var wash: Color?
    var compact: Bool
    /// How far the row is inset horizontally.
    ///
    /// ⚠️ **Pass `0` when the row's columns are budgeted against the full width.** A grid that
    /// resolves fixed column widths from the container has already spent every point of it; an
    /// inset added afterwards takes that width back out of the columns, and the widest figure is
    /// the first thing to wrap.
    var hPad: CGFloat

    @State private var hovering = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @Environment(\.palette) private var palette

    private var striped: Bool { !index.isMultiple(of: 2) }

    func body(content: Content) -> some View {
        content
            .padding(.vertical, AppFont.pt(compact ? 5 : 7))
            .padding(.horizontal, hPad)
            .background {
                ZStack {
                    if striped { Theme.stripe }
                    if let wash { wash.opacity(striped ? 0.15 : 0.10) }
                    if selected { palette.identitySoft }
                    if hovering && !selected { Theme.rowHover }
                }
            }
            .overlay(alignment: .leading) {
                // Selection without colour: a leading bar at the reserved weight.
                if selected && differentiate {
                    Rectangle().fill(Color.primary).frame(width: Hairline.selection)
                }
            }
            .clipShape(Radius.shape(Radius.small))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .appAnimation(Motion.chrome, value: hovering)
    }
}

extension View {
    /// The shared row treatment. `index` drives the stripe; `wash` is a semantic tint laid over it.
    func appRow(_ index: Int, selected: Bool = false, wash: Color? = nil,
                compact: Bool = false, hPad: CGFloat? = nil) -> some View {
        modifier(AppRow(index: index, selected: selected, wash: wash,
                        compact: compact, hPad: hPad ?? Space.row))
    }
}

// MARK: - Section heading

/// A section heading — **one of the three places bronze appears.**
private struct SectionHeading: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content
            .font(.sectionTitle)
            .foregroundStyle(palette.identity)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The page or card heading: the shared type style in the app's bronze.
    func sectionHeading() -> some View { modifier(SectionHeading()) }
}

// MARK: - Status

/// A section's status, said in words with a colour behind them.
///
/// ⚠️ The dot is `.accessibilityHidden`, and the word is always present. Colour is never the only
/// signal — under Differentiate Without Color the dot gains a ring, and the word is what a screen
/// reader gets either way.
struct StatusChip: View {
    let status: SectionStatus

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        let c = palette.color(for: status)
        return HStack(spacing: Space.hairline + 2) {
            Circle()
                .fill(c)
                .frame(width: AppFont.pt(8), height: AppFont.pt(8))
                .overlay(differentiate
                         ? Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                         : nil)
                .accessibilityHidden(true)
            Text(status.label)
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(c)
                .lineLimit(1)
        }
        .padding(.horizontal, AppFont.pt(8))
        .padding(.vertical, AppFont.pt(3))
        .background(c.opacity(0.10), in: Capsule(style: .continuous))
        .overlay(differentiate ? Capsule(style: .continuous)
            .strokeBorder(c.opacity(0.7), lineWidth: Hairline.thin) : nil)
        .accessibilityElement(children: .combine)
    }
}
