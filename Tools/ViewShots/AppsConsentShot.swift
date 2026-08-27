//
//  AppsConsentShot.swift
//  ViewShots
//
//  ⭐ **The consent question as it actually appears — in the Apps page, not over it.**
//
//  `AppsShot` photographs `UpdateConsentAsk`, the sheet form of the same question, on its own. This
//  file photographs the thing the app really puts on screen: `AppsView` with the question up,
//  inside the section it is about, with the sidebar beside it.
//
//  ## ⚠️ Why the panel exists at all, and why it needs its own picture
//
//  The sheet carries a `StableScrollView` so its buttons cannot be pushed below the fold at large
//  type. `StableScrollView` is built on a `GeometryReader`, which is greedy — nesting one inside
//  the section's own scrolling page hands it the whole visible height and produces a scroll view
//  inside a scroll view. So the page form is a separate layout of the same words, and a separate
//  layout is exactly the thing that has to be looked at rather than assumed.
//
//  It is numbered after `AppsShot`'s range so the two files can be edited without colliding.
//
//  ⛔ Nothing here checks anything. The panel is two closures and a number; pressing nothing,
//  asking nobody.
//
//      bin/make-shots.sh
//

import AppKit
import SwiftUI
import Testing
import WellkeptCore

@Suite("View shots — the Apps consent question", .serialized)
@MainActor
struct AppsConsentShot {

    /// A shell state positioned on Apps with the question up.
    ///
    /// ⚠️ It goes through `runAppsCheck()`, which is how the question actually gets on screen — a
    /// state that set the flag by hand would photograph a screen the app has no route to. Demo mode
    /// is off, and the call returns at the question without starting anything: `runAppsCheck` puts
    /// the question up and stops, precisely so nothing is read before the answer is known.
    private func asking() async -> AppState {
        let app = AppState()
        // ⚠️ **Set explicitly, not assumed.** `AppState.init` reads `demoMode` from
        // `UserDefaults.standard`, which under `xctest` is the test process's own domain — and
        // every other shot suite in this bundle writes that key when it asks for a demo Mac. A
        // fresh `AppState()` here therefore inherits whatever the last suite left behind, and
        // `runAppsCheck()` returns immediately in demo mode. The first version of this file did
        // not set it, and the picture came back showing an invented Mac with no question on it.
        app.demoMode = false
        app.selection = .apps
        app.updateConsent.forget()
        await app.runAppsCheck()
        return app
    }

    private func window(_ app: AppState) -> some View {
        HStack(spacing: 0) {
            Sidebar()
            AppsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    private func bothAppearances(_ view: some View, width: CGFloat, height: CGFloat,
                                 _ number: Int, _ name: String) {
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number)-\(name)-light", scheme: .light)
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number + 1)-\(name)-dark", scheme: .dark)
    }

    private func atLargestText(_ body: () -> Void) {
        let key = AppearancePrefs.textScaleKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(Double(AppFont.maxScale), forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        body()
    }

    /// **The whole screen, mid-question.** What to look at: the question sits in the page under the
    /// button that raised it, the verb above is greyed while it is up, and "Don't check" is first in
    /// reading order so the affirmative is not the button under the cursor.
    @Test("Apps, with the consent question up")
    func questionInThePage() async {
        let app = await asking()
        #expect(app.askingUpdateConsent, "the question never came up, so this picture is of nothing")
        bothAppearances(window(app), width: Layout.windowDefault.width, height: 1_800,
                        178, "apps-consent-in-page")
        app.updateConsent.forget()
    }

    /// ⚠️ **200% text is where a two-button row breaks.** Two large buttons do not fit side by side
    /// in a 700-point column at doubled type, so the panel wraps them onto separate lines rather
    /// than compressing until "Don't check" truncates — on the one screen in the app where the exact
    /// words of a button are the whole point.
    @Test("The consent question at 200% text")
    func questionAtLargestText() async {
        let app = await asking()
        #expect(app.askingUpdateConsent, "the question never came up, so these pictures are of nothing")
        atLargestText {
            bothAppearances(window(app), width: Layout.windowDefault.width, height: 3_600,
                            180, "apps-200-consent-in-page")
            // And at the floor size, which is the narrowest column this layout is ever given.
            bothAppearances(window(app),
                            width: Layout.windowMinimum.width, height: 2_400,
                            182, "apps-200-consent-floor")
        }
        app.updateConsent.forget()
    }

    /// The panel on its own, at the readable column, in both appearances — the picture to read the
    /// words off.
    @Test("The consent panel on its own")
    func panelAlone() {
        let panel = UpdateConsentPanel(storeAppCount: 8, onAllow: {}, onDecline: {})
            .padding(Space.page)
            .frame(width: Layout.readableColumn, alignment: .leading)
        bothAppearances(panel, width: Layout.readableColumn, height: 1_000,
                        184, "apps-consent-panel")

        // And the one before any inventory exists, where the count is genuinely unknown and the
        // line is left out rather than padded with a guess.
        let unknown = UpdateConsentPanel(storeAppCount: nil, onAllow: {}, onDecline: {})
            .padding(Space.page)
            .frame(width: Layout.readableColumn, alignment: .leading)
        bothAppearances(unknown, width: Layout.readableColumn, height: 1_000,
                        186, "apps-consent-panel-unknown")
    }
}
