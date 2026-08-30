//
//  AppsShot.swift
//  ViewShots
//
//  **Pictures of the real Apps screen — never checked, both demo Macs, Options open, the update
//  consent sheet, a long list, and the refused-permission notice this section shows on one row.**
//
//  These are `AppsView`, `UpdateConsentAsk` and `PermissionNoticeLine`, the same types the app puts
//  on screen, driven by a real `AppState`. Nothing here is a mock-up assembled out of the design
//  vocabulary: a harness that photographs an imitation certifies a screen nobody ships.
//
//  ## ⚠️ Nothing here reads this Mac, and in Apps that is a hard requirement rather than a nicety
//
//  Apps does not run on launch — the inventory call alone is **7 to 8 seconds** — so a render
//  pumping a run loop cannot start one. Both demo shots come from `DemoData`, whose apps are
//  invented. **No shot in this file asks anybody anything**: the update check is behind consent,
//  and the consent sheet is photographed as a view with two closures, not as a check.
//
//  ⛔ And nothing here touches a gated place. `LeftoverReader.survey(fullDiskAccess:)` is not called
//  at all in this file; the refused picture is drawn from the notice, which is words. macOS raises
//  *"would like to access data from other apps"* on the attempt, and under a test harness the dialog
//  names **Xcode**. That happened twice on 2026-08-27 and will not happen again.
//
//  ## ⚠️ Why 200% text is where this section is judged
//
//  Apps is the only screen in the app that is a **list of proper nouns beside version numbers** —
//  "Visual Studio Code" against "1.104.2", thirty-one times. Every other section is a fixed set of
//  rows written by us, at lengths we chose. Here the content is whatever somebody installed, and a
//  layout that reads beautifully with "Pages 15.3.1" comes apart on "Microsoft Remote Desktop Beta"
//  at doubled type. That is not a hypothesis about a future bug; it is the shape of the data.
//
//      bin/make-shots.sh
//

import AppKit
import SwiftUI
import Testing
import WellkeptCore

@Suite("View shots — Apps", .serialized)
@MainActor
struct AppsShot {

    // MARK: - Fixtures

    /// A shell state positioned on Apps.
    ///
    /// ⚠️ `demoMode` and `demoMachine` write to `UserDefaults.standard`, which under `xctest` is the
    /// test process's own domain rather than the app's. Nothing this touches survives the run.
    private func state(demo: DemoMachine? = nil) -> AppState {
        let app = AppState()
        app.demoMode = demo != nil
        if let demo { app.demoMachine = demo }
        app.selection = .apps
        return app
    }

    /// The window: the hand-rolled rail beside the pane, which is the shape `RootView` builds. The
    /// sidebar is in the picture on purpose — a list of app names is judged against the rail beside
    /// it, and a page inset that reads correctly on its own can crowd it.
    private func window(_ app: AppState, optionsOpen: Bool = false) -> some View {
        if optionsOpen { app.openOptions.insert(.apps) }
        return HStack(spacing: 0) {
            Sidebar()
            AppsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    /// How tall a frame the whole page needs when nothing may scroll out of the picture.
    ///
    /// ⚠️ A shot at the window's real height photographs the top of the section and nothing else,
    /// which is fine for a face and useless here: **the list is the section**, and a 760-point frame
    /// reaches the summary and about four apps. Width is what governs reflow, so a taller frame
    /// changes nothing about the layout — it only stops `StableScrollView` hiding the rest of it.
    private enum PageHeight {
        /// The five rows and the block above them, Options shut.
        static let face: CGFloat = 2_400
        /// Options open: the other 391 bundles, the per-app detail, the leftovers.
        static let whole: CGFloat = 5_200
        /// Thirty-one apps, one per line, with a version and two facts each.
        static let longList: CGFloat = 6_000
        /// The same at doubled type, which is roughly twice as tall and then some, because the
        /// long names wrap where the short ones do not.
        static let wholeAtLargestText: CGFloat = 9_000
    }

    /// Render a view in both appearances, at the given size.
    private func bothAppearances(_ view: some View, width: CGFloat, height: CGFloat,
                                 _ number: Int, _ name: String) {
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number)-\(name)-light", scheme: .light)
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number + 1)-\(name)-dark", scheme: .dark)
    }

    /// Run a block with the app's text size turned up.
    ///
    /// ⚠️ The setting is the real one — `AppFont.scale` reads this key on every call — and it is
    /// global for the duration of the render, which is why this suite is `.serialized` and why
    /// `bin/make-shots.sh` disables parallel testing. Restored whatever happens, including a failed
    /// expectation.
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

    // MARK: - The faces

    /// **Nothing has been checked — and in Apps this is not an edge case, it is every launch.**
    ///
    /// Apps is the one section that deliberately does not run by itself: seven to eight seconds for
    /// the inventory alone. So this screen is what a person sees every single time they open the
    /// section, until they press the button. It has to read as a section waiting rather than a
    /// section broken, and it has to say why nothing ran.
    @Test("Apps, never checked")
    func neverChecked() {
        let size = Layout.windowDefault
        bothAppearances(window(state()), width: size.width, height: size.height,
                        150, "apps-never-checked")
    }

    /// **A healthy Mac.** Everything installed, accounted for, and nothing asking anything of
    /// anybody. The thing to look at in this picture is the summary line: it carries its
    /// denominator, and the coverage caveat sits beside the result rather than behind Options.
    @Test("Apps, the healthy demo Mac")
    func healthyMac() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .healthy)), width: size.width, height: PageHeight.face,
                        152, "apps-healthy")
    }

    /// **A Mac with problems** — apps with newer versions, an app that has been crashing, and
    /// removed apps that left things behind.
    ///
    /// ⚠️ **Everything on this screen is grey.** Apps posts nothing above `.information` this
    /// round: without vulnerability data, a version behind is not something wrong, and an Intel-only
    /// app is a fact rather than a countdown. If an amber or a red tag appears anywhere in this
    /// picture, something has reached past `AppsRow.severityCeiling` and set a severity by hand.
    @Test("Apps, the demo Mac with problems")
    func macWithProblems() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .problems)), width: size.width, height: PageHeight.face,
                        154, "apps-problems")
    }

    /// **Options open**, which in this section is where the honest bookkeeping lives: the 391 other
    /// bundles that are not apps, what each row set aside and why, and the per-app detail.
    @Test("Apps, with Options expanded")
    func optionsExpanded() {
        bothAppearances(window(state(demo: .problems), optionsOpen: true),
                        width: Layout.windowDefault.width, height: PageHeight.whole,
                        156, "apps-options")
    }

    /// **The long list.** Thirty-one apps is the real number on the measured Mac, and a list is the
    /// one thing in this app whose length is decided by somebody else. Photographed tall enough that
    /// nothing scrolls out: a section that looks tidy in its first screenful and repeats a heading
    /// forty rows down is a section nobody photographed whole.
    @Test("Apps, the whole list at once")
    func theWholeList() {
        bothAppearances(window(state(demo: .healthy), optionsOpen: true),
                        width: Layout.windowDefault.width, height: PageHeight.longList,
                        158, "apps-long-list")
    }

    // MARK: - The two moments that are not the face

    /// ⭐ **The update-consent sheet — the moment this app asks before anything leaves the Mac.**
    ///
    /// Decided 2026-08-27: *"Inform and consent."* The sheet is the inform half made visible, and it
    /// is the single most important picture in this file, because it is the screen that decides
    /// whether somebody trusts the rest of the app. What to look at: the register's own sentences,
    /// quoted rather than paraphrased; **"Don't check" first in reading order**, so the affirmative
    /// is not the button under the cursor; and a scroll view, so the buttons cannot be pushed below
    /// the fold at large type.
    ///
    /// ⚠️ It is photographed as a view with two closures. Pressing nothing, checking nothing,
    /// asking nobody.
    @Test("The update-consent sheet")
    func updateConsentSheet() {
        let sheet = UpdateConsentAsk(storeAppCount: 9, onAllow: {}, onDecline: {})
        // The sheet asserts its own size, which is stated at 100% text and scales — so it is asked
        // for a frame larger than it wants and allowed to settle at its own.
        bothAppearances(sheet, width: 700, height: 720, 160, "apps-update-consent")
    }

    /// ⭐ **Full Disk Access refused — the one row in Apps that needs it.**
    ///
    /// ⚠️ **What to check in this picture is the sentence, and it is a correction.** It used to read
    /// *"some apps will be missing from the list"*, which is not true of anything this section does:
    /// the inventory, the versions, the crashes and the update checks all work with the switch off.
    /// One row does not — the one that looks at what a removed app left behind, because that means
    /// reading another app's sandbox folder. A notice claiming the app list is short would send
    /// somebody to System Settings to fix a problem they do not have.
    ///
    /// It is drawn with the grant forced off, so this screen gets a picture on every Mac rather than
    /// only on one where the permission happens to be missing — see the seam on `PermissionNoticeLine`.
    @Test("Apps, with Full Disk Access refused")
    func fullDiskAccessRefused() {
        bothAppearances(refusedLeftovers(),
                        width: Layout.readableColumn, height: 560, 162, "apps-leftovers-refused")
    }

    /// The notice and the row it is about, drawn by the section's own `AppsRowView` from the row
    /// `LeftoverReader` actually produces when the Library cannot be read.
    ///
    /// ⛔ **The survey is not run.** A `Survey` with `nil` candidates is the shape a refusal
    /// produces, and handing one in is how the refused row is obtained without opening anything.
    private func refusedLeftovers() -> some View {
        let answer = LeftoverReader.answer(from: LeftoverReader.Survey(candidates: nil),
                                           appsOnThisMac: [],
                                           runningBundleIDs: [],
                                           isRegistered: { _ in false })
        return VStack(alignment: .leading, spacing: Space.section) {
            PermissionNoticeLine(section: .apps, granted: false)
            AppsRowView(row: answer.row, index: 0) { EmptyView() }
            Spacer(minLength: 0)
        }
        .padding(Space.page)
        .frame(width: Layout.readableColumn, alignment: .leading)
        .pageGround()
    }

    // MARK: - 200% text
    //
    // ⚠️ **This is the section where doubled type actually breaks something.** macOS ships no
    // Dynamic Type for Macs, the HIG still asks for 200% enlargement, and every measurement in this
    // app is stated as "N points at 100% text" so the page reflows rather than zooms. A list of
    // names beside version numbers is the hardest case in the app for that claim, because the names
    // are not ours and some of them are five words long.

    @Test("Apps at 200% text — every screen")
    func everyScreenAtLargestText() {
        atLargestText {
            let width = Layout.windowDefault.width
            bothAppearances(window(state()), width: width, height: Layout.windowDefault.height,
                            164, "apps-200-never-checked")
            bothAppearances(window(state(demo: .healthy)), width: width,
                            height: PageHeight.wholeAtLargestText, 166, "apps-200-healthy")
            bothAppearances(window(state(demo: .problems)), width: width,
                            height: PageHeight.wholeAtLargestText, 168, "apps-200-problems")
            bothAppearances(window(state(demo: .problems), optionsOpen: true), width: width,
                            height: PageHeight.wholeAtLargestText, 170, "apps-200-options")
            bothAppearances(UpdateConsentAsk(storeAppCount: 9, onAllow: {}, onDecline: {}),
                            width: 900, height: 900, 172, "apps-200-update-consent")
            bothAppearances(refusedLeftovers(),
                            width: Layout.readableColumn, height: 1_100,
                            174, "apps-200-leftovers-refused")
        }
    }

    /// ⚠️ **The floor size, at 200% text — the worst case the window allows.**
    ///
    /// 1020 × 640 is a size this app can genuinely be dragged to. A list of app names at doubled
    /// type in a 1020-point window is the hardest thing this layout is ever asked to do, and it is
    /// the size at which a version number ends up on a line of its own, three rows away from the app
    /// it belongs to.
    @Test("Apps at 200% text, at the smallest the window goes")
    func atTheFloorSizeWithLargestText() {
        atLargestText {
            let size = Layout.windowMinimum
            bothAppearances(window(state(demo: .problems), optionsOpen: true),
                            width: size.width, height: size.height, 176, "apps-200-floor")
        }
    }

    // MARK: - The one thing a picture proves better than a number

    /// **At 200% text the Apps face still holds the readable column.**
    ///
    /// The failure this catches is invisible to every other test in the build: a fixed measurement
    /// somewhere in a row — a version column's width, a size figure's frame, a padding written as a
    /// literal instead of through `AppFont.pt` — that holds at 100% and pushes content out past the
    /// column when the type doubles. The app builds, the tests pass, and the screenshot everybody
    /// takes is at 100%.
    ///
    /// A version number in a right-hand column is exactly the shape that gets written with a literal
    /// width, which is why this check is worth repeating here rather than trusting Hardware's.
    @Test("At 200% text the Apps face still holds the readable column")
    func theColumnHoldsAtLargestText() {
        atLargestText {
            for machine in DemoMachine.allCases {
                guard let rep = ShotWriter.render(
                    window(state(demo: machine), optionsOpen: true)
                        .frame(width: 2000, height: 900)
                        .environment(\.colorScheme, .light)
                        .environment(\.palette, Palette(level: .calm, scheme: .light)),
                    width: 2000, height: 900, scheme: .light)
                else { Issue.record("\(machine.rawValue): nothing rendered"); continue }

                let edge = ShotWriter.distinctColours(in: rep, fromFraction: 0.90, toFraction: 0.99)
                print("PROBE apps-200-\(machine.rawValue) right-edge colours at 2000pt: \(edge)")
                #expect(edge <= 3, """
                    apps (\(machine.rawValue)) at 200% text: the right-hand tenth of a 2000-point \
                    window has \(edge) distinct colours in it, so a row is drawing out there. The \
                    content column is 700 points and centres — something in the section is sized \
                    with a literal instead of through AppFont.pt.
                    """)
            }
        }
    }
}

// MARK: - The refused row has to say the right thing, whatever it looks like

/// ⭐ **The words on the refused screen, checked by a machine.**
///
/// The picture above shows the notice; this says what it is allowed to claim. Two separate failures
/// live here and only one of them is visible in a screenshot: a sentence that reads well and is
/// factually wrong about which part of the section is blind.
///
/// ⛔ Nothing here calls `survey(fullDiskAccess:)`. The refused row is built from a survey whose
/// candidates are `nil`, which is the shape a Library that could not be read produces — no folder is
/// opened to get it.
@Suite("Apps — what the refused screen is allowed to say")
@MainActor
struct AppsRefusedWordingTests {

    /// The section's own shortfall sentence names the row that is actually affected, and does not
    /// claim the app list is short. **The inventory needs no permission at all.**
    @Test func theShortfallSentenceNamesTheRightRow() throws {
        let line = try #require(FullDiskAccess.shortfall(for: .apps))
        #expect(line.contains("removed apps left behind"), """
            The Apps shortfall line reads "\(line)". Everything in this section except the leftovers \
            row works with the switch off — the inventory comes from LaunchServices, versions from \
            the storefront and Homebrew, crashes from a folder in your own Library.
            """)
        #expect(!line.contains("missing from the list"), """
            The old wording is back. It sends somebody to System Settings to fix an app list that \
            was never short.
            """)
    }

    /// The refused leftovers row: a sentence, a button that can clear it, and **no figure** — a
    /// count here would be a zero reported because we could not look.
    @Test func theRefusedRowCarriesNoFigureAndOffersAWayOut() {
        let answer = LeftoverReader.answer(from: LeftoverReader.Survey(candidates: nil),
                                           appsOnThisMac: [],
                                           runningBundleIDs: [],
                                           isRegistered: { _ in false })
        #expect(answer.leftovers.isEmpty)
        #expect(answer.row.measure == nil, """
            The refused row is carrying a figure. Whatever it says, it is a number arrived at by not \
            looking — the exact claim this section exists to avoid making.
            """)
        #expect(answer.row.unreadable != nil)
        #expect(answer.row.remedy != nil, "a refusal a person can lift has to come with the way to lift it")
        #expect(answer.row.severity == AppsRow.severityCeiling)
    }

    /// And the notice itself draws when the grant is off, which is what the picture depends on.
    /// A seam that silently stopped working would produce a blank shot, and the blank detector would
    /// call it a layout failure rather than a dead override.
    @Test func theSeamActuallyForcesTheRefusedState() {
        // Both directions, so a hard-coded `false` in the seam is caught as well as a dead one.
        #expect(FullDiskAccess.shortfall(for: .apps) != nil)
        #expect(FullDiskAccess.affectedSections.contains(.apps))
        #expect(!FullDiskAccess.affectedSections.contains(.hardware))
    }
}
