import SwiftUI

//  AppFont.swift
//  Wellkept — App/Support
//
//  The type half of Lode's and Waypoint's `Theme.swift`.
//
//  ⚠️ **Waypoint shipped a bug here and it must not be repeated.** Its own note, at
//  `App/Shared/WaypointSettings.swift:31`: on iOS "`AppFont.scale` read the 1.0 default forever and
//  `AppFont.family` read 'Avenir' forever — both were consulted app-wide and settable nowhere."
//  Every string below is read by every screen in the app; if Settings does not expose a control for
//  it, the setting is not a setting, it is a constant with a UserDefaults lookup in front of it.
//
//  **So: `fontFamily` and `textScale` each need a real control in Settings ▸ Appearance, and
//  `textScale` also needs View ▸ Text Size in the menu bar** (macOS provides no Dynamic Type, and
//  the HIG still asks for 200% enlargement). Anything read here and not settable there is the same
//  defect.

/// The app's UI type. Family and size are read live from `UserDefaults`; sizes track the native
/// macOS text styles so they stay Dynamic-Type aware.
enum AppFont {

    // MARK: Family

    /// **Avenir**, matching Lode, Waypoint and the rest of the house.
    static let defaultFamily = "Avenir"

    /// What Settings offers. "System" means the native face — the escape hatch for anyone who
    /// finds Avenir's small x-height hard going, and for anyone whose Mac has lost the font.
    static let families = ["Avenir", "System"]

    static var family: String {
        UserDefaults.standard.string(forKey: AppearancePrefs.fontFamilyKey) ?? defaultFamily
    }

    // MARK: Size

    /// The one text-size range in the app. Every control that writes `textScale` — the Settings
    /// slider, View ▸ Text Size, ⌘+ / ⌘− / ⌘0 — bounds itself with these, so none of them can push
    /// the stored value past what `scale` will honour. Lode's ⌘+ counted to 250% while `scale`
    /// stopped at 200%, so the readout lied and ⌘− had to walk back down before anything moved.
    static let minScale: CGFloat = 1.0, maxScale: CGFloat = 2.0

    /// The text-size setting.
    ///
    /// ⚠️ This scales the **type**, never the pixels. A `scaleEffect` zoom quietly shrinks the
    /// layout space — at 150% the views get two-thirds of the width to lay out in, dense content
    /// overflows its frame, and `scaleEffect` does not clip, so it paints straight over the
    /// sidebar and out past the window edge. Scaling type means the layout genuinely reflows.
    static var scale: CGFloat {
        let v = UserDefaults.standard.object(forKey: AppearancePrefs.textScaleKey) as? Double ?? 1.0
        return min(maxScale, max(minScale, CGFloat(v)))
    }

    /// A key that changes whenever the type does.
    ///
    /// `AppFont` reads `UserDefaults` statically, which SwiftUI cannot observe, so a font change
    /// repaints only the views that happened to rebuild for some other reason — about half the
    /// screen. `AppearanceHost` hangs `.id(typeKey)` on the tree to force the rest. That resets
    /// state inside it, which is why navigation state lives above it.
    static var typeKey: String { "\(family)|\(scale)" }

    // MARK: Building a font

    static func f(_ size: CGFloat, _ weight: Font.Weight = .regular,
                  relativeTo style: Font.TextStyle) -> Font {
        let s = size * scale
        return family == "System"
            ? .system(size: s, weight: weight)
            : .custom(family, size: s, relativeTo: style).weight(weight)
    }

    /// Rounded numerals for a measurement — "4.2 GB", "83%" — independent of the chosen text
    /// family, matching Lode, Cloudbreak and InForm.
    ///
    /// ⚠️ **Never call this directly from a view.** It returns a fixed `.system(size:)` font,
    /// which — unlike the `relativeTo:` path above — ignores Dynamic Type entirely, so a direct
    /// call freezes a number at its 100% size while the label beside it grows. Use the `Figure`
    /// view, which wraps the size in `@ScaledMetric` first.
    static func figure(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size * scale, weight: weight, design: .rounded)
    }

    /// A hardcoded point measurement, scaled with the text.
    ///
    /// Any box holding text has to grow with the text, or the text outgrows the box: a 48-pt field
    /// fits "100" at 100% and clips it at 150%. `pt(48)` is that measurement stated as "48 points
    /// at 100% text".
    static func pt(_ base: CGFloat) -> CGFloat { base * scale }
}

// MARK: - The text styles

extension Font {
    // Avenir has a small x-height, so this scale reads noticeably smaller than its numbers
    // suggest; the sizes are set a little large on purpose, captions most of all.
    static var appBody: Font        { AppFont.f(14.5, relativeTo: .body) }
    static var appCallout: Font     { AppFont.f(13.5, relativeTo: .callout) }
    static var appSubheadline: Font { AppFont.f(12.5, relativeTo: .subheadline) }
    static var appCaption: Font     { AppFont.f(12, relativeTo: .caption) }
    static var appCaption2: Font    { AppFont.f(11, relativeTo: .caption2) }
    static var appHeadline: Font    { AppFont.f(14.5, .semibold, relativeTo: .headline) }
    static var appTitle3: Font      { AppFont.f(17, .semibold, relativeTo: .title3) }
    static var appTitle2: Font      { AppFont.f(20, .semibold, relativeTo: .title2) }
    static var appTitle: Font       { AppFont.f(24, .bold, relativeTo: .title) }

    /// The section heading. Reach it through `.sectionHeading()`, which also puts the bronze on it.
    static var sectionTitle: Font { appTitle2 }
}

// MARK: - A measurement

/// A rounded numeric figure that scales with the text setting.
///
/// Fixed `.system(size:)` fonts ignore Dynamic Type, so every number on screen goes through here
/// rather than through `AppFont.figure` directly.
struct Figure: View {
    let text: String
    var weight: Font.Weight = .bold
    @ScaledMetric private var size: CGFloat

    init(_ text: String, size: CGFloat = 20, weight: Font.Weight = .bold) {
        self.text = text
        self.weight = weight
        self._size = ScaledMetric(wrappedValue: size)
    }

    var body: some View {
        Text(text)
            .font(AppFont.figure(size, weight))
            .monospacedDigit()
            .lineLimit(1)                 // never break a number across lines
            .minimumScaleFactor(0.5)      // shrink to fit rather than wrap
            .fixedSize(horizontal: false, vertical: true)
    }
}
