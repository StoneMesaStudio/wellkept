import SwiftUI
import AppKit
import WellkeptCore

//  Palette.swift
//  Wellkept — App/Support
//
//  Ported from Lode's `App/Support/Palette.swift` (the AppearanceMode / AppearanceHost / `\.palette`
//  half) with the useful parts of Waypoint's `AppPalette.swift`.
//
//  **This file is the app's only source of colour.** Nothing anywhere else may name a colour: not
//  a hex, not `.orange`, not `Color(nsColor:)`. InForm's Watch target re-declared its interval
//  colours locally and they have already drifted from the phone's — one app, two answers, and no
//  way to tell which screen is wrong.

// MARK: - Appearance

/// Light / Dark / Match System.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    /// Raw value is storage; this is English. Renaming the option is one line here.
    var label: String {
        switch self {
        case .system: "Match System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    /// `nil` means "don't override" — the window follows the system and keeps tracking it.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    /// The AppKit half. `.preferredColorScheme` does not reach `.bar` (the sidebar material),
    /// `windowBackgroundColor`, `controlBackgroundColor` or `controlColor` — all of which this app
    /// sits on. Those follow `NSApp.appearance` and nothing else.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - The colour dial

/// How much colour the app uses. Settings ▸ Appearance ▸ Color. Stored as `colorLevel`.
///
/// It scales **saturation**, never brightness. A bronze drained toward grey is still where bronze
/// was; a bronze *darkened* toward grey reads as a different colour beside a figure.
enum ColorLevel: String, CaseIterable, Identifiable, Sendable {
    /// The app's own colour, untouched. The dial is an identity transform here, by short-circuit —
    /// so "Full is exactly the app" is true because nothing runs, not because the arithmetic
    /// happens to round-trip.
    case full
    /// The default.
    case calm
    /// Greys and warm paper.
    case minimal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full:    "Full"
        case .calm:    "Calm"
        case .minimal: "Minimal"
        }
    }

    var blurb: String {
        switch self {
        case .full:    "The app's full colour."
        case .calm:    "Softer fills and plates. Everything still means what it meant."
        case .minimal: "Greys and warm paper. Colour only where it carries information."
        }
    }

    /// Decoration — plates, washes, hover fills. Nothing here tells you anything the words beside
    /// it don't, so it can go almost all the way out.
    var decorative: Double {
        switch self {
        case .full:    1.00
        case .calm:    0.55
        case .minimal: 0.12
        }
    }

    /// The bronze. It is wayfinding — which section am I in, which row is selected, which button
    /// is the one — so it goes quieter and never absent. Floored well above decoration.
    var identity: Double {
        switch self {
        case .full:    1.00
        case .calm:    0.82
        case .minimal: max(0.70, Self.identityFloor)
        }
    }

    static let identityFloor: Double = 0.60
}

// MARK: - Identity

/// Wellkept's identity colour. **Bronze on day one; petrol and slate are reserved, not shipped.**
///
/// An enum of one case rather than a constant, because the stored key `identityColor` already
/// exists and a second colour must not require a migration to add.
enum IdentityColor: String, CaseIterable, Identifiable, Sendable {
    case bronze

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bronze: "Bronze"
        }
    }

    /// ⚠️ Two explicit literals, not one colour with an opacity. The page is **painted** warm
    /// paper, so DESIGN §3.4's rule applies: on a painted ground every colour on it is an explicit
    /// per-scheme literal. A single bronze that works on #FAF9F6 is either invisible or garish on
    /// #161514 — measured, this pair is 7.47∶1 and 6.50∶1 against their own grounds.
    var lightHex: String {
        switch self {
        case .bronze: "#6E4A26"
        }
    }

    var darkHex: String {
        switch self {
        case .bronze: "#BE9265"
        }
    }
}

// MARK: - The palette

/// The app's colour, resolved for one appearance and one dial setting.
///
/// ## Why this is an environment value and not a `Theme` static
///
/// A static that reads `UserDefaults` is invisible to SwiftUI's dependency tracking. Changing the
/// setting would re-run only the bodies that happened to observe something else, leaving every
/// other view holding its old colours — and the only cure for that is to re-identify the whole
/// tree on a colour change, which throws away scroll position and selection every time somebody
/// drags the dial. An `EnvironmentKey` is tracked properly: a view that reads `\.palette`
/// re-renders when it changes, and one that doesn't, doesn't.
struct Palette: Equatable, Sendable {
    var level: ColorLevel
    var scheme: ColorScheme
    var identityChoice: IdentityColor

    init(level: ColorLevel = .calm,
         scheme: ColorScheme = .light,
         identity: IdentityColor = .bronze) {
        self.level = level
        self.scheme = scheme
        self.identityChoice = identity
    }

    /// What a colour is *for*. Part of the cache key, so one colour used two ways can't have one
    /// treatment cached over the other.
    enum Role: Hashable, Sendable { case decorative, identity }

    // MARK: The page ground

    /// The numeric ground, for arithmetic — `preserveContrast` needs real components and an asset
    /// colour has none until it is resolved.
    ///
    /// ⚠️ **These two hexes and `PageGround.colorset` must stay in step.** The asset is what gets
    /// painted (it carries the increased-contrast variants the system already honours); these are
    /// what the contrast floor measures against. If they drift, the dial will hold a colour legible
    /// against a ground nothing is drawn on.
    static let lightGroundHex = "#FAF9F6"
    static let darkGroundHex  = "#161514"

    var groundHex: String { scheme == .dark ? Self.darkGroundHex : Self.lightGroundHex }

    /// Warm paper. **Painted from the asset catalog**, which is what gives it light, dark and
    /// increased-contrast variants without a branch in code.
    var ground: Color { Color("PageGround") }

    var groundRGB: ColorMath.RGB { ColorMath.rgb(hex: groundHex) ?? ColorMath.RGB(1, 1, 1) }

    /// The card surface. Deliberately **derived from AppKit** and never drained: it is the one
    /// colour here that tracks the user's Increase Contrast setting, and re-deriving it ourselves
    /// would opt every card out of an accessibility setting the system already honours. The warm
    /// offset is on the PAGE only, so a card reads as a card by being cooler than the paper.
    var cardFill: Color { Color(nsColor: .controlBackgroundColor) }

    // MARK: Identity

    /// The bronze. **It appears in exactly three places** — the selected sidebar row, the main
    /// button, and section headings. A fourth use is a bug, not a decision.
    @MainActor var identity: Color {
        transform(Color(hex: scheme == .dark ? identityChoice.darkHex : identityChoice.lightHex),
                  role: .identity)
    }

    /// The soft bronze plate behind the selected sidebar row.
    ///
    /// A mix toward the ground rather than `identity.opacity(…)`: the sidebar sits on a system
    /// material, so an alpha would composite against whatever the material happens to be showing
    /// and the plate would change colour when a window moved over a dark desktop. A mixed opaque
    /// colour is the same plate everywhere.
    ///
    /// The plate is never the only cue — the selected row's words also go bolder — because a plate
    /// alone is colour carrying meaning, which Differentiate Without Color turns off.
    @MainActor var identitySoft: Color {
        let base = ColorMath.rgb(hex: scheme == .dark ? identityChoice.darkHex : identityChoice.lightHex)
            ?? ColorMath.RGB(0.43, 0.29, 0.15)
        // Dark mode needs more of the colour to register at all against near-black paper.
        let amount = scheme == .dark ? 0.22 : 0.16
        let mixed = ColorMath.mixPerceptual(groundRGB, base, amount)
        return transform(Color(rgb: mixed), role: .decorative)
    }

    /// Ink on the bronze button — computed from the fill, never assumed. See `ColorMath.ink(on:)`.
    @MainActor var onIdentity: Color { ink(on: identity) }

    // MARK: The semantic vocabulary

    // ⚠️ **These three are EXEMPT from the colour dial, at every level.** They are not decoration
    // and they are not identity: they are the answer. A user turning colour down is asking for a
    // quieter app, not for a red that no longer reads as red — and "your drive is failing" is
    // exactly the sentence that must survive every setting the app offers. Stated as calls rather
    // than left undrained by omission, so a reader sees a decision instead of an oversight.
    //
    // They are also **not user-changeable**. There is no picker for these. The dial has a floor
    // here of 1.0, permanently.
    //
    // Explicit per-scheme literals for the reason in §3.4: the ground is painted, so every colour
    // on it is a literal. Measured against their own grounds — light 6.06∶1 / 5.62∶1 / 6.85∶1,
    // dark 9.24∶1 / 8.65∶1 / 7.51∶1 — all clear the 4.5∶1 bar at body size.

    /// Checked, nothing wrong.
    var good: Color { Color(hex: scheme == .dark ? "#7FC98D" : "#2F6B3D") }
    /// Not wrong yet. A disk at 92%, a battery at 78% health.
    var attention: Color { Color(hex: scheme == .dark ? "#E0A94E" : "#8A5A12") }
    /// Something is actually wrong. **Only ever this.**
    var problem: Color { Color(hex: scheme == .dark ? "#F08A80" : "#A32A21") }

    /// The colour for a finding's severity. One switch, so no face invents a fourth reading.
    ///
    /// `.information` is `Theme.textSecondary` and not a hue: a revealed fact is not a fault, and
    /// giving it a colour would put a 40 GB folder in the same visual class as a failing drive.
    func color(for severity: Severity) -> Color {
        switch severity {
        case .problem:     problem
        case .attention:   attention
        case .information: Theme.textSecondary
        }
    }

    /// The colour for a section's status.
    ///
    /// `.notChecked` is `Theme.textTertiary`: "we haven't looked" is the absence of an answer, and
    /// a hue would make it read as one.
    func color(for status: SectionStatus) -> Color {
        switch status {
        case .good:           good
        case .needsAttention: attention
        case .notChecked:     Theme.textTertiary
        }
    }

    // MARK: The dial

    /// Decoration — plates, hover fills, washes. Drained hard; at Minimal this is very nearly
    /// grey, which is the point.
    @MainActor func decorative(_ c: Color) -> Color { transform(c, role: .decorative) }

    /// White or near-black on a given fill, whichever the fill can carry. Cached, because callers
    /// run it inside `body`.
    @MainActor func ink(on fill: Color) -> Color {
        PaletteCache.shared.ink(on: fill, scheme: scheme)
    }

    /// A fill darkened (or, in dark mode, kept dark enough) until **white text on it reaches AA**.
    /// Kept for the day a badge needs white on colour; `ink(on:)` is the usual answer.
    @MainActor func fillBehindWhiteText(_ c: Color, target: Double = 4.5) -> Color {
        PaletteCache.shared.legibleFill(c, level: level, scheme: scheme, target: target)
    }

    /// Row hover. Achromatic, so the dial has nothing to do to it.
    var rowHover: Color { Color.primary.opacity(0.06) }

    // MARK: - Machinery

    @MainActor private func transform(_ c: Color, role: Role) -> Color {
        guard level != .full else { return c }
        return PaletteCache.shared.color(c, role: role, level: level, scheme: scheme,
                                         ground: groundRGB)
    }

    /// The factor for a role at a level, in one place so the cache and any test agree.
    static func factor(_ role: Role, _ level: ColorLevel) -> Double {
        switch role {
        case .decorative: level.decorative
        case .identity:   level.identity
        }
    }
}

// MARK: - Resolved-colour cache

/// `Color.resolve(in:)` runs inside `body`. A sidebar of seven rows plus a face full of findings
/// is enough that an unmemoised resolve is hundreds of colour-space conversions per frame.
/// Keyed by (colour, role, level, scheme): the appearance is part of the key because every dynamic
/// colour resolves differently in dark, and caching across an appearance change is exactly how a
/// dark-mode screen ends up wearing light-mode colours.
@MainActor
final class PaletteCache {
    static let shared = PaletteCache()

    private struct Key: Hashable {
        let color: Color
        let role: Palette.Role
        let level: ColorLevel
        let scheme: ColorScheme
        /// Set only for `legibleFill` / `ink`, whose answers don't depend on the dial.
        var target: Double = 0
    }
    private var store: [Key: Color] = [:]

    private init() {
        // The system colours can change while the app is running, and a cached entry would outlive
        // the change. Cheap to drop everything and re-resolve.
        NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PaletteCache.shared.store.removeAll() }
            }
        // Increase Contrast / Reduce Transparency move `controlBackgroundColor` and friends.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PaletteCache.shared.store.removeAll() }
            }
    }

    func color(_ c: Color, role: Palette.Role, level: ColorLevel,
               scheme: ColorScheme, ground: ColorMath.RGB) -> Color {
        let key = Key(color: c, role: role, level: level, scheme: scheme)
        if let hit = store[key] { return hit }
        let out = compute(c, role: role, level: level, scheme: scheme, ground: ground)
        store(out, for: key)
        return out
    }

    func legibleFill(_ c: Color, level: ColorLevel, scheme: ColorScheme, target: Double) -> Color {
        let key = Key(color: c, role: .identity, level: level, scheme: scheme, target: target)
        if let hit = store[key] { return hit }
        let (rgb, alpha) = resolve(c, scheme: scheme)
        let out = ColorMath.meet(rgb, against: ColorMath.RGB(1, 1, 1), target: target)
        let color = Color(.sRGB, red: out.r, green: out.g, blue: out.b, opacity: alpha)
        store(color, for: key)
        return color
    }

    func ink(on fill: Color, scheme: ColorScheme) -> Color {
        let key = Key(color: fill, role: .decorative, level: .full, scheme: scheme, target: -1)
        if let hit = store[key] { return hit }
        let out = ColorMath.ink(on: resolve(fill, scheme: scheme).0)
        let color = Color(.sRGB, red: out.r, green: out.g, blue: out.b, opacity: 1)
        store(color, for: key)
        return color
    }

    /// A cap, not a policy: the app's real colour vocabulary is well under a hundred values, so
    /// passing this means something is minting colours per row — drop it all rather than grow
    /// without bound.
    private func store(_ color: Color, for key: Key) {
        if store.count > 2_000 { store.removeAll() }
        store[key] = color
    }

    /// The one place `Color.Resolved` is unpacked.
    ///
    /// ⚠️ `red` / `green` / `blue`, **NOT** `linearRed` / `linearGreen` / `linearBlue`.
    /// `Color.Resolved` exposes both pairs, and `Color(.sRGB, …)` wants the gamma-encoded one.
    /// Feeding it the linear components turns #6E4A26 into a near-black — every colour in the app
    /// subtly wrong, each one individually plausible, nothing to point at. Lode shipped exactly
    /// this and needed a round-trip test to find it.
    private func resolve(_ c: Color, scheme: ColorScheme) -> (ColorMath.RGB, Double) {
        var env = EnvironmentValues()
        env.colorScheme = scheme
        let r = c.resolve(in: env)
        return (ColorMath.RGB(Double(r.red), Double(r.green), Double(r.blue)), Double(r.opacity))
    }

    private func compute(_ c: Color, role: Palette.Role, level: ColorLevel,
                         scheme: ColorScheme, ground: ColorMath.RGB) -> Color {
        let (rgb, opacity) = resolve(c, scheme: scheme)

        // A grey has no vividness to remove. Returning the ORIGINAL colour rather than a rebuilt
        // one matters: `Color.primary`, `.white` and the AppKit greys are dynamic, and rebuilding
        // them as fixed sRGB would freeze them into whichever appearance resolved them.
        guard ColorMath.hsb(rgb).s > 0.001 else { return c }

        let drained = ColorMath.desaturate(rgb, by: Palette.factor(role, level))
        // Decoration is a background — its job is to recede, so no floor. Identity carries meaning
        // and gets the floor: quieter, never fainter.
        let out = role == .decorative
            ? drained
            : ColorMath.preserveContrast(drained, original: rgb, ground: ground)
        return Color(.sRGB, red: out.r, green: out.g, blue: out.b, opacity: opacity)
    }
}

// MARK: - Theme: the colours that do not depend on the dial

/// The achromatic half of the app's colour — text, separators, plates.
///
/// It is a `enum` of statics rather than part of `Palette` because none of it has a hue for the
/// dial to act on, and a `Text` in a helper function with no environment can still reach it.
enum Theme {

    // MARK: Supporting-text colours
    //
    // ⚠️ **Never a bare `.secondary` or `.tertiary` as a TEXT colour, anywhere in this app.**
    // Measured on macOS 26.6.2: `secondaryLabelColor` is 3.95∶1 on white against Apple's own
    // 4.5∶1 bar, and `tertiaryLabelColor` is 1.88∶1 — failing even the 3∶1 large-text bar. Neither
    // moves under the accessibility high-contrast appearance, so the "accessible variant" Apple's
    // guidance promises does not arrive.
    //
    // A fixed fraction of `.primary` instead: still correct in dark mode, and landing much darker
    // in light. Keep the system pair for **disabled states and separators**, where low contrast is
    // the message.

    static var textSecondary: Color { Color.primary.opacity(ColorMath.textSecondaryFraction) }
    static var textTertiary: Color { Color.primary.opacity(ColorMath.textTertiaryFraction) }

    // MARK: Rows

    /// The zebra stripe. Achromatic, so the dial has nothing to do to it.
    static let stripe = Color.primary.opacity(0.04)
    /// Row hover. Present on every row treatment, not just the sidebar.
    static let rowHover = Color.primary.opacity(0.06)
    /// The hairline that separates without dividing — a card border, a row rule.
    static let hairlineInk = Color.primary.opacity(0.12)

    // MARK: Type

    /// Rounded numerals for a measurement. Independent of the chosen text family, matching the
    /// other StoneMesa apps. Reach it through `Figure`, which scales it.
    static func figure(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Color conveniences

extension Color {
    /// `#RRGGBB` → `Color`. A malformed string yields magenta rather than black, because an
    /// invisible mistake is worse than a loud one: black would look like a deliberate ink colour.
    init(hex: String) {
        guard let c = ColorMath.rgb(hex: hex) else {
            self = Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)
            return
        }
        self = Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    init(rgb: ColorMath.RGB, opacity: Double = 1) {
        self = Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    /// Deliberately `.full`: if injection is ever missed, the view renders as the app's own colour
    /// rather than half-drained. Wrong-but-familiar beats wrong-and-novel for a default.
    static let defaultValue = Palette(level: .full, scheme: .light, identity: .bronze)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Stored preferences

/// The appearance and type keys, in one place so no two files drift apart on a string literal.
///
/// ⚠️ **Raw values are permanent.** They are written into the user's defaults; renaming one is a
/// migration, and a released build that reads back an unknown string silently reverts the user's
/// setting. The labels live on `label`, and John may edit those freely.
///
/// The three keys this app stores that are *not* about looks — `setupFinished`, `demoMode`,
/// `fullDiskAccessAsked` — belong to the onboarding and settings work and are not declared here.
enum AppearancePrefs {
    static let modeKey = "appearanceMode"
    static let colorLevelKey = "colorLevel"
    static let identityKey = "identityColor"
    static let fontFamilyKey = "fontFamily"
    static let textScaleKey = "textScale"

    static let defaultMode = AppearanceMode.system
    /// **Calm is the default**, and it is a real default rather than a migration: a fresh install
    /// with no stored value lands here too.
    static let defaultLevel = ColorLevel.calm
    static let defaultIdentity = IdentityColor.bronze

    /// Straight reads, for the handful of places that are not SwiftUI views and so cannot hold an
    /// `@AppStorage`. **Views must not use these** — a static read is invisible to SwiftUI's
    /// dependency tracking, so a view that reads one keeps its old colour when the setting changes.
    static var mode: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? defaultMode
    }
    static var level: ColorLevel {
        ColorLevel(rawValue: UserDefaults.standard.string(forKey: colorLevelKey) ?? "") ?? defaultLevel
    }
    static var identity: IdentityColor {
        IdentityColor(rawValue: UserDefaults.standard.string(forKey: identityKey) ?? "") ?? defaultIdentity
    }
}

// MARK: - Applying it

/// Wraps the window's whole content and applies every Appearance setting.
///
/// A `View` and not a modifier on the `App`, for one concrete reason: `@Environment(\.colorScheme)`
/// read on an `App` does not track the window's appearance. It reports `.light` forever, so "Match
/// System" in dark mode would hand the palette a light-mode scheme and every colour in the app
/// would be resolved for the wrong appearance — visible only in dark, and individually plausible
/// everywhere.
///
/// ⚠️ **`.id(AppFont.typeKey)` is applied here, and it resets the state of everything inside.**
/// The type settings are read from `UserDefaults` by `AppFont`, which SwiftUI cannot observe, so
/// the tree has to be re-identified when they change or half the app keeps the old face. That
/// means **anything that must survive a font change — the selected section, an open sheet, scroll
/// position — has to live above this view**, in the model, not in a `@State` inside it.
struct AppearanceHost<Content: View>: View {
    @AppStorage(AppearancePrefs.modeKey) private var modeRaw = AppearancePrefs.defaultMode.rawValue
    @AppStorage(AppearancePrefs.colorLevelKey) private var levelRaw = AppearancePrefs.defaultLevel.rawValue
    @AppStorage(AppearancePrefs.identityKey) private var identityRaw = AppearancePrefs.defaultIdentity.rawValue
    @AppStorage(AppearancePrefs.fontFamilyKey) private var fontFamily = AppFont.defaultFamily
    @AppStorage(AppearancePrefs.textScaleKey) private var textScale = 1.0

    /// The window's real appearance, which is the system's unless overridden below. The palette
    /// needs a concrete one — there is no "either" to resolve a colour against.
    @Environment(\.colorScheme) private var windowScheme

    @ViewBuilder var content: Content

    private var mode: AppearanceMode { AppearanceMode(rawValue: modeRaw) ?? AppearancePrefs.defaultMode }
    private var level: ColorLevel { ColorLevel(rawValue: levelRaw) ?? AppearancePrefs.defaultLevel }
    private var identity: IdentityColor { IdentityColor(rawValue: identityRaw) ?? AppearancePrefs.defaultIdentity }

    private var palette: Palette {
        Palette(level: level, scheme: mode.colorScheme ?? windowScheme, identity: identity)
    }

    var body: some View {
        content
            .environment(\.palette, palette)
            // Re-identify on a type change. See the ⚠️ on this type.
            .id("\(fontFamily)|\(textScale)")
            .preferredColorScheme(mode.colorScheme)
            // ⚠️ `.preferredColorScheme` is NOT sufficient on its own. It moves SwiftUI's own
            // colours and leaves every AppKit-drawn surface where it was — and this app sits on
            // `.bar` (the sidebar), `windowBackgroundColor` and `controlBackgroundColor`. Dark mode
            // without this line is dark text on light AppKit chrome, which is worse than not
            // offering the setting at all.
            //
            // ⚠️ **Never assigned from a view body.** `NSApp.appearance` is shared state, and
            // writing it during view update is "Modifying state during view update" at best and a
            // render loop at worst. `.task(id:)` runs it outside the update, on first appearance
            // and again on every change.
            .task(id: modeRaw) {
                // `nil` hands the app back to the system, which is what "Match System" has to mean.
                // Assigning `NSAppearance.currentDrawing()` would PIN whatever the system happened
                // to be at that moment and stop tracking it afterwards.
                NSApp.appearance = mode.nsAppearance
            }
    }
}

// MARK: - Surfaces

/// The page ground, as a **filling layer** rather than a `.background` on whatever happens to be
/// inside.
///
/// ⚠️ This is the centred-band bug, and it has bitten three apps in this house. A view whose root
/// does not claim its full height gets vertically centred by its container — the symptom is a
/// heading stranded mid-window with empty gutters above and below, and a ground that only covers
/// the band. `ZStack` + a greedy frame on both layers is the fix; `.background(ground)` on a
/// shrink-wrapped child is the bug.
private struct PageGround: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Neutral elevated surface.
private struct SoftCard: ViewModifier {
    var cornerRadius: CGFloat
    func body(content: Content) -> some View {
        let shape = Radius.shape(cornerRadius)
        return content
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: Hairline.thin))
            // A card should look like paper lying on paper, not paper hovering an inch above it.
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

extension View {
    /// The page ground. Apply it **once**, on the detail wrapper — and on any surface outside that
    /// wrapper (a sheet, the welcome window), which is the only reason it is a modifier and not a
    /// single line in the shell.
    func pageGround() -> some View { modifier(PageGround()) }

    /// Neutral elevated surface.
    func softCard(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(SoftCard(cornerRadius: cornerRadius))
    }

    /// **Every screen-level view calls this on its root.** See `PageGround`'s ⚠️ for what happens
    /// when one doesn't: the content floats as a centred band with gaps above and below it.
    ///
    /// `.topLeading` because a page reads from the top; content that should centre in the pane
    /// (an empty state, a spinner) asks for that itself with its own greedy frame.
    func fillsPane(alignment: Alignment = .topLeading) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
