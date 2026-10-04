import SwiftUI
import AppKit

//  Scrolling.swift
//  Wellkept — App/Support
//
//  Lode's `StableScrollView` and Waypoint's `EmptyStateView`, plus the readable column.

// MARK: - Metrics

/// How much room a modal or a scrolling column may take, stated so it tracks the text size.
///
/// A box with a hardcoded pixel count and type that can double eventually puts a scroll bar
/// *inside a dialog* — which is the box being wrong, not the content. Waypoint's onboarding proved
/// it: a 340-pt scroll area held a 386-pt step at 100% text, so two of six steps scrolled for every
/// user before any zoom at all.
enum SheetMetrics {
    /// Room kept between a modal and the edge of the screen.
    static let screenMargin: CGFloat = 48

    /// What a scroll bar takes from the content: nothing with overlay scrollers (the macOS
    /// default), ~15 pt with the legacy ones.
    ///
    /// ⚠️ **This is not hypothetical.** System Settings ▸ Appearance ▸ Show scroll bars ▸ *Always*
    /// switches the whole Mac to legacy scrollers, and some people run it that way — so on such a
    /// Mac an appearing scroller really does steal width. Reserved up front rather than discovered later.
    ///
    /// `@MainActor` because both AppKit statics are. Without it this compiles with a concurrency
    /// warning that only appears in a **Release** build, which is how it survives every Debug build
    /// for months.
    @MainActor static var scrollBarInset: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
    }

    /// The screen the modal will open on. `visibleFrame` already excludes the menu bar and Dock.
    @MainActor private static var visible: CGSize {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? CGSize(width: 1_440, height: 900)
    }

    /// A base width at 100% text, scaled with the type and clamped to the screen.
    @MainActor static func width(_ base: CGFloat) -> CGFloat {
        min(base * AppFont.scale, max(320, visible.width - screenMargin * 2))
    }

    /// A base height at 100% text, scaled and clamped — for a modal whose content is a list of
    /// unknown length and so has to assert a height rather than follow one.
    @MainActor static func height(_ base: CGFloat) -> CGFloat {
        min(base * AppFont.scale, max(280, visible.height - screenMargin * 2))
    }
}

// MARK: - Scrolling

/// A vertical `ScrollView` whose **content width cannot change when the scroll bar appears.**
///
/// ⚠️ This is not a nicety. Without it, a page built from wrapping layouts can pin the main thread
/// in SwiftUI's layout engine *forever* — the app opens to a beachball and never recovers. It only
/// reproduces on some Macs, which is why it took a while to find, so here is the whole mechanism:
///
///  1. With **Show scroll bars: Always**, macOS uses legacy scrollers, which take ~15 pt of real
///     width *away* from the content rather than floating over it.
///  2. Any wrapping or reflowing content has a height that is a *step function* of width: take
///     15 pt away and a row re-wraps, changing the page height by far more than 15 pt.
///  3. That is easily enough to flip the answer to "does this page overflow?" — which is precisely
///     the question that decides whether a scroll bar is shown.
///
/// No bar → page overflows → show a bar → the bar steals width → the page no longer overflows →
/// hide the bar → … The two chase each other, layout never converges, and the main thread never
/// comes back. Nothing is "slow"; it simply never finishes.
///
/// The cure is to break the cycle rather than tune either half: measure the width **outside** the
/// scroll view and pin the content to it, reserving the scroller's width up front.
struct StableScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(width: max(320, geo.size.width - SheetMetrics.scrollBarInset),
                           alignment: .topLeading)
            }
            // Scroll indicators stay visible. Hiding them is how a control ends up 30 pt past the
            // fold with nothing to say it is there — DESIGN §12.2, and one of our own apps has
            // already shipped that bug.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - The readable column

private struct ReadableColumn: ViewModifier {
    var width: CGFloat
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: width, alignment: .leading)
            // The outer greedy frame is what centres the column on a wide display *and* keeps the
            // page filling its pane. Without it the content is a band floating in the middle of
            // the window with gaps above and below — the bug this house has shipped three times.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// The 700-pt readable column, centred in whatever pane it is given. One number across the
    /// house; a full-screen line of text on a 34-inch monitor is not generous, it is unreadable.
    ///
    /// ⚠️ **The width does NOT scale with the type, and that is load-bearing.** Making it
    /// `AppFont.pt(width)` looks obviously right — a readable measure is characters per line, not
    /// points, so a 700-pt column holds half as many words at 200% text. It was tried on
    /// 2026-08-30 and two tests killed it inside a minute: `ShellShot`'s "On a wide window the
    /// content stays in the readable column" and `HardwareShot`'s 200% twin both render at 2000
    /// points and fail if anything draws in the right-hand tenth. A column that doubles reaches
    /// the edge of a large display, which is the exact failure they exist to catch.
    ///
    /// So the narrow ribbon at 200% text is the house's decision, not an oversight — and it is
    /// the same on all seven faces. Reopening it means changing `~/Development/Applications/DESIGN.md` §210 and both
    /// probes, for all six apps at once. Do not do it as a side effect of some other fix.
    func readableColumn(_ width: CGFloat = Layout.readableColumn) -> some View {
        modifier(ReadableColumn(width: width))
    }
}

// MARK: - Empty states

/// The app's one empty state.
///
/// ⚠️ **`greedy` defaults to true, and that default is the whole point.** An intrinsically-sized
/// view dropped into a detail pane — or into any `ZStack` / `.background` parent that sizes to its
/// content — gets **vertically centred as a narrow band**, leaving a stranded strip with empty
/// gutters above and below it. `ContentUnavailableView` does exactly this. So this view claims the
/// full pane by default and centres its content inside the *whole* space.
///
/// Pass `greedy: false` only when it sits inside a scrolling column of cards, where taking the
/// full height would push everything below it off screen.
struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String?
    var greedy: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    init(symbol: String,
         title: String,
         message: String? = nil,
         greedy: Bool = true,
         actionTitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.greedy = greedy
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Space.block) {
            Image(systemName: symbol)
                .font(.system(size: AppFont.pt(34), weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                // Always paired with a title that says the same thing.
                .accessibilityHidden(true)

            Text(title)
                .font(.appTitle3)
                .multilineTextAlignment(.center)

            if let message {
                // ⚠️ NO `.fixedSize(horizontal: false, vertical: true)` HERE. Waypoint removed it
                // on 2026-08-18 and it must not come back without measuring first.
                //
                // `fixedSize(vertical:)` means "report my ideal height for whatever width I am
                // offered". Paired with a `maxWidth` — which is a ceiling, not a width — a sizing
                // pass that offers a narrow width gets back the height of this sentence set a word
                // or two per line. Measured: **2,374 points** for one empty message, which made the
                // window's content 2,454 points tall on a 982-point screen. SwiftUI centred the
                // overflow, so the header was laid out 573 points ABOVE the top of the screen: a
                // window with no navigation, no header, and no way back. `onAppear` still fired on
                // everything, which is why it read as a render bug rather than a layout one.
                //
                // The width ceiling alone gives a wrapped, fully visible message and a finite
                // height.
                Text(message)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: AppFont.pt(420))
            }

            if let actionTitle, let action {
                Button(actionTitle) { action() }
                    .buttonStyle(.appProminent)
                    .controlSize(.large)
                    .padding(.top, Space.hairline)
            }
        }
        .padding(Space.page)
        .frame(maxWidth: .infinity, maxHeight: greedy ? .infinity : nil)
    }
}

/// A quieter inline note for the inside of a card. Never greedy: it lives in a stack of cards, so
/// claiming the pane would be wrong.
struct InlineEmptyNote: View {
    var symbol: String
    var text: String

    init(symbol: String = "tray", text: String) {
        self.symbol = symbol
        self.text = text
    }

    var body: some View {
        HStack(spacing: Space.row) {
            Image(systemName: symbol)
                .font(.appCallout)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text(text)
                .font(.appCallout)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.row)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
