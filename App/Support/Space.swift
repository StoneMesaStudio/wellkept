import SwiftUI
import AppKit

//  Space.swift
//  Wellkept — App/Support
//
//  Ported from Lode's `App/Support/Space.swift`. Spacing, radius, hairlines, the readable column,
//  the window's own size, and the three motion speeds.

/// The app's one spacing scale — seven steps, each named for the job it does rather than for its
/// size. Named steps are what stop twenty screens using twenty different numbers for the same gap.
///
/// ## Which steps scale with the text, and why only some
///
/// The **inner** steps are fixed. They separate a figure from its own caption, or two rows of a
/// list; they are about the *glyphs*, and glyph spacing that grows with the type just pushes the
/// content off the screen.
///
/// The **outer** steps go through `AppFont.pt`, so they are stated as "20 points at 100% text". A
/// fixed 28-pt page inset at 200% text is visually a 14-pt inset: *tighter*, not calmer, for the
/// one user who turned the text up because they needed the air. That is the failure this split
/// exists to prevent, and it is near-impossible to retrofit across seven faces later.
enum Space {
    /// A figure and its own caption. Fixed.
    static let hairline: CGFloat = 4
    /// Rows inside a block. Fixed.
    static let row: CGFloat = 8
    /// Blocks inside a card. Fixed.
    static let block: CGFloat = 12

    /// Between cards. Scales.
    static var gutter: CGFloat { AppFont.pt(16) }
    /// Card padding. Scales.
    static var card: CGFloat { AppFont.pt(20) }
    /// Between the bands of a page. Scales.
    static var section: CGFloat { AppFont.pt(24) }
    /// Outer page inset. Scales.
    static var page: CGFloat { AppFont.pt(28) }

    /// The dense screens' outer steps — the same four, at ×0.75.
    ///
    /// Applied **by rule, not by taste**: a screen whose content is a table uses these. Storage
    /// and Apps will each be a long list of rows with a measurement column, and handing them the
    /// same page inset as a section face takes width straight out of columns that need it.
    enum Compact {
        static var gutter: CGFloat { AppFont.pt(12) }
        static var card: CGFloat { AppFont.pt(15) }
        static var section: CGFloat { AppFont.pt(18) }
        static var page: CGFloat { AppFont.pt(21) }
    }
}

/// The app's one corner-radius ramp — four steps, **every one `.continuous`**.
///
/// Radius encodes elevation. Mixing `.continuous` and the default circular style puts an `8` drawn
/// one way beside an `8` drawn the other, and they are visibly different corners; Lode had
/// fourteen distinct radii and 60% of them were built without the style before this was settled.
enum Radius {
    /// Chips, swatches, inner rows.
    static let small: CGFloat = 6
    /// Controls, buttons, disclosure headers.
    static let control: CGFloat = 10
    /// Cards.
    static let card: CGFloat = 14
    /// Hero panels.
    static let hero: CGFloat = 20

    static func shape(_ r: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: r, style: .continuous)
    }
}

/// Line weights. Two numbers, and the second one means something.
enum Hairline {
    /// A separator, a card border, a row rule.
    static let thin: CGFloat = 0.5
    /// **Reserved for selection.** Nothing else in the app draws at this weight, which is what
    /// makes it readable as "this one" under Differentiate Without Color, where the plate behind
    /// the selected row carries nothing.
    static let selection: CGFloat = 1.2
}

/// Fixed measurements the whole app agrees on.
enum Layout {
    /// **The readable column: 700 pt.** One number across the house. Content stays this wide and
    /// centres on a wide display — a full-screen line of text on a 34-inch monitor is not
    /// generous, it is unreadable.
    static let readableColumn: CGFloat = 700

    /// The window's opening size and its floor. Below the floor the sidebar and a 700-pt column
    /// stop fitting side by side, which is the point at which dragging smaller starts destroying
    /// the layout rather than compressing it.
    static let windowDefault = CGSize(width: 1_100, height: 760)
    static let windowMinimum = CGSize(width: 1_020, height: 640)

    /// The sidebar's width. Scales with the text, because the rows are words: a fixed 196-pt rail
    /// truncates "Check for changes" at 150% text.
    static var sidebarWidth: CGFloat { AppFont.pt(196) }
}

/// The app's three speeds. Named for the job, so a new screen picks a speed rather than a number.
///
/// A closed set. Every one is `nil` under Reduce Motion — see `Motion.resolved(_:)` and the
/// `.appAnimation` modifier, which is the only wrapper any view should use.
enum Motion {
    /// Chrome moving: a disclosure opening, a hover state, a plate appearing.
    static let chrome: Animation = .easeInOut(duration: 0.20)
    /// Changing what you are looking at: the selected sidebar row, a switched face.
    static let selection: Animation = .snappy(duration: 0.26)
    /// A press. Short enough that it reads as the button responding rather than as an animation.
    static let press: Animation = .easeOut(duration: 0.12)

    /// The imperative half, for `withAnimation` call sites. Reads the setting from AppKit because
    /// a `withAnimation` inside a button action has no environment to read.
    @MainActor static func resolved(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }

    /// `withAnimation` that honours Reduce Motion.
    @MainActor static func run<R>(_ animation: Animation, _ body: () throws -> R) rethrows -> R {
        try withAnimation(resolved(animation), body)
    }
}

extension View {
    /// `.animation(_:value:)` that disappears under Reduce Motion.
    ///
    /// ⚠️ `nil` rather than a shorter duration. The setting says *don't move things*, and a fast
    /// move is still a move — for the people this setting exists for, a 120 ms slide is the same
    /// nausea as a 300 ms one. SwiftUI treats a `nil` animation as "apply the change instantly",
    /// which is exactly the requested behaviour.
    func appAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionAnimation(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension AnyTransition {
    /// **The only transition between our own screens.** Fade *in*; the outgoing screen leaves
    /// instantly.
    ///
    /// ⚠️ Never a slide. A slide keeps both screens laid out at full size and draws one outside
    /// the bounds — the documented window-explosion shape, shipped twice in this house. And a
    /// symmetric crossfade keeps two live screens mounted at once, which on a section that starts
    /// work when it appears reads as a stutter.
    static var faceFade: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .identity)
    }
}

extension View {
    /// Switching from one section face to another.
    ///
    /// ⚠️ **The animation goes on the VIEW, not on the writers.** The sidebar, the Overview rows
    /// and any deep link all assign the selected section, and wrapping each in `withAnimation`
    /// would give a link different behaviour from a click. One modifier covers every writer
    /// identically.
    func faceTransition<T: Equatable & Hashable>(_ face: T) -> some View {
        self.id(face)
            .transition(.faceFade)
            .appAnimation(Motion.selection, value: face)
    }
}
