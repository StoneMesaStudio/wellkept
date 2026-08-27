//
//  SecurityShot.swift
//  ViewShots
//
//  **Pictures of the real Security screen — the never-checked face, both demo Macs, the Options
//  panel open, and the whole thing again at 200% text.**
//
//  These are `SecurityView`, the same type the app puts on screen, driven by a real `AppState`.
//  Nothing here is a mock-up assembled out of the design vocabulary: a harness that photographs an
//  imitation certifies a screen nobody ships.
//
//  ## ⚠️ Nothing here reads this Mac, and Security is the section where that matters most
//
//  `SecurityModel` has **no launch check at all** — Security runs only on a press — so there is
//  nothing a render can trip that would start a six-second sweep of this machine's protections,
//  privacy database, startup files, browsers, sockets and system log. Both demo shots come from
//  `DemoData`, whose facts are invented. If a future edit makes a picture suddenly show this Mac's
//  own apps in the permission list, that absence of a launch check is what broke.
//
//  ## ⚠️ Why the unwell Mac is the important picture here
//
//  Five of the paths in this section will never run on the machine of anybody building it: FileVault
//  off, the firewall off, a permission still held by an app that is gone, an app whose signature no
//  longer matches what was approved, and a real XProtect Remediator finding. Nobody is going to turn
//  their own disk encryption off to look at a screen, so unless it is invented it never gets looked
//  at at all — and it is precisely the screen where the wording has to stay flat rather than
//  alarming.
//
//      bin/make-shots.sh
//

import AppKit
import SwiftUI
import Testing
import WellkeptCore

@Suite("View shots — Security", .serialized)
@MainActor
struct SecurityShot {

    // MARK: - Fixtures

    /// A shell state positioned on Security.
    ///
    /// ⚠️ `demoMode` and `demoMachine` write to `UserDefaults.standard`, which under `xctest` is the
    /// test process's own domain rather than the app's. Nothing this touches survives the run.
    private func state(demo: DemoMachine? = nil) -> AppState {
        let app = AppState()
        app.demoMode = demo != nil
        if let demo { app.demoMachine = demo }
        app.selection = .security
        return app
    }

    /// The window: the hand-rolled rail beside the pane, which is the shape `RootView` builds. The
    /// sidebar is in the picture on purpose — the face is judged against the rail beside it, and a
    /// page inset that reads correctly on its own can crowd it.
    private func window(_ app: AppState, optionsOpen: Bool = false) -> some View {
        if optionsOpen { app.openOptions.insert(.security) }
        return HStack(spacing: 0) {
            Sidebar()
            SecurityView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    /// How tall a frame the whole page needs when nothing may scroll out of the picture.
    ///
    /// ⚠️ A shot at the window's real height photographs the top of the section and nothing else,
    /// which is fine for a face and useless for Options: this section's panel sits below the
    /// protections block and six rows, two of which carry named findings with their own buttons.
    /// Width is what governs reflow, so a taller frame changes nothing about the layout — it only
    /// stops `StableScrollView` hiding the rest of it.
    private enum PageHeight {
        /// Tall enough for the summary, the block and all six rows with Options shut.
        static let face: CGFloat = 2_200
        /// The unwell Mac, whose rows carry two named concerns with explanations and buttons.
        static let faceWithFindings: CGFloat = 2_800
        /// Options open: every row's details, plus the whole permission list.
        static let whole: CGFloat = 6_400
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
    /// The setting is the real one — `AppFont.scale` reads this key on every call, so the type, the
    /// page insets and the sidebar width all move together, exactly as they do when somebody presses
    /// ⌘+ four times. Restored whatever happens, including a failed expectation.
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

    /// **Nothing has been checked — and here that is the ordinary state, not an edge case.**
    ///
    /// Security never runs by itself, so this is what the screen looks like on every launch until
    /// somebody presses the button. It has to say why it is empty rather than looking like a screen
    /// that failed to load, and it has to say plainly that the app does not check this on its own.
    @Test("Security, never checked")
    func neverChecked() {
        let size = Layout.windowDefault
        bothAppearances(window(state()), width: size.width, height: size.height,
                        80, "security-never-checked")
    }

    /// **A healthy Mac.** Six rows of Good, the protections block above them, and the summary
    /// carrying its scope and its window — *"The protections we can see are on, and macOS found
    /// nothing in the last 12 days."* The word "safe" appears nowhere, which is the thing to check
    /// by eye in this picture.
    @Test("Security, the healthy demo Mac")
    func healthyMac() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .healthy)), width: size.width, height: PageHeight.face,
                        82, "security-healthy")
    }

    /// **A Mac with problems.** FileVault off, the firewall off, a permission held by an app that is
    /// gone, an app whose signature no longer matches, and something macOS found and dealt with four
    /// days ago.
    ///
    /// ⚠️ Everything on it is amber and nothing is red. All nine of this section's conditions are
    /// `.attention` by construction, and if a red tag ever appears in this picture something has
    /// reached past `SecurityConcern` to set a severity by hand.
    @Test("Security, the demo Mac with problems")
    func macWithProblems() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .problems)),
                        width: size.width, height: PageHeight.faceWithFindings,
                        84, "security-problems")
    }

    /// **Options open** — every row's exact detail, and the whole list of which app holds which
    /// permission. It is the densest thing in the section by a wide margin.
    @Test("Security, with Options expanded")
    func optionsExpanded() {
        bothAppearances(window(state(demo: .problems), optionsOpen: true),
                        width: Layout.windowDefault.width, height: PageHeight.whole,
                        86, "security-options")
    }

    /// The healthy Mac with Options open. Worth its own picture because the reassuring case is the
    /// one where a person goes looking for the working, and the audit block at the bottom — what
    /// ran, how far back it could see, what it changed — is the whole answer.
    @Test("Security, the healthy Mac with Options expanded")
    func healthyOptionsExpanded() {
        bothAppearances(window(state(demo: .healthy), optionsOpen: true),
                        width: Layout.windowDefault.width, height: PageHeight.whole,
                        88, "security-healthy-options")
    }

    // MARK: - The permission list on its own

    /// **The list of who holds what, at the width it actually gets.**
    ///
    /// `GrantList` is the real view the real Options panel draws; only the frame is the harness's.
    /// It is photographed separately because it is the one place in the app where two rows carry a
    /// coloured word — "No longer installed", "Signature changed" — beside a dozen that do not, and
    /// the whole design question is whether the twelve ordinary ones still read as ordinary.
    @Test("The permission list, both Macs")
    func permissionList() {
        let column = Layout.readableColumn
        bothAppearances(GrantList(answer: DemoData.security(.healthy))
                            .padding(Space.page)
                            .frame(width: column, alignment: .leading),
                        width: column, height: 1_500, 90, "security-permissions-healthy")
        bothAppearances(GrantList(answer: DemoData.security(.problems))
                            .padding(Space.page)
                            .frame(width: column, alignment: .leading),
                        width: column, height: 1_500, 92, "security-permissions-problems")
    }

    // MARK: - 200% text

    /// ⚠️ **Where this section breaks first.**
    ///
    /// Security is the wordiest screen in the app — a named concern carries a title, a paragraph of
    /// explanation and a button, and there can be several — so doubled type is the size at which a
    /// row that looked tidy becomes a wall. macOS ships no Dynamic Type for Macs, the HIG still asks
    /// for 200% enlargement, and a picture is the only thing that can say whether the page reflowed
    /// rather than zoomed.
    @Test("Security at 200% text")
    func atLargestTextSize() {
        atLargestText {
            let width = Layout.windowDefault.width
            bothAppearances(window(state()), width: width, height: Layout.windowDefault.height,
                            94, "security-200-never-checked")
            bothAppearances(window(state(demo: .healthy)), width: width, height: 4_200,
                            96, "security-200-healthy")
            bothAppearances(window(state(demo: .problems)), width: width, height: 5_600,
                            98, "security-200-problems")
        }
    }

    /// ⚠️ **The floor size, at 200% text — the worst case the window allows.**
    ///
    /// 1020 × 640 is a size this app can genuinely be dragged to, and the unwell Mac at doubled type
    /// is the hardest thing this layout is ever asked to do: a coloured finding block with a button
    /// inside a row inside a 700-point column that no longer fits.
    @Test("Security at 200% text, at the smallest the window goes")
    func atTheFloorSizeWithLargestText() {
        atLargestText {
            let size = Layout.windowMinimum
            bothAppearances(window(state(demo: .problems)),
                            width: size.width, height: size.height, 100, "security-200-floor")
        }
    }

    /// **The named-condition block on its own, at 200% text.**
    ///
    /// This is the piece with the most words per point anywhere in the app, and the one that decides
    /// whether the section reads as a health check or as an alarm.
    @Test("A named condition at 200% text")
    func concernAtLargestText() {
        atLargestText {
            bothAppearances(
                VStack(alignment: .leading, spacing: Space.block) {
                    ConcernView(concern: .fileVaultOff, pane: .fileVault)
                    ConcernView(concern: .permissionHeldByMissingApp, pane: nil)
                }
                .padding(Space.page)
                .frame(width: Layout.readableColumn, alignment: .leading),
                width: Layout.readableColumn, height: 1_400, 102, "security-200-concern")
        }
    }
}
