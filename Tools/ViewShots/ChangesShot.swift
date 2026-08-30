// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI
import Testing
import WellkeptCore

//  ChangesShot.swift
//  ViewShots
//
//  **Pictures of the real Changes screen — the never-checked face, both demo Macs, one change with
//  its three sentences, the macOS-update attribution, and the Full Disk Access line. Light and
//  dark, and again at 200% text.**
//
//  Every one of these is `ChangesView` or a view it draws, driven by a real `AppState`. Nothing
//  here is a mock-up assembled out of the design vocabulary: a harness that photographs an
//  imitation certifies a screen nobody ships.
//
//  ## ⚠️ Nothing here reads this Mac, and this is the section where that would be worst
//
//  `ChangesModel` has **no launch check** — Changes runs only on a press — so a render cannot start
//  the eight-second sweep of this machine's protections, sockets, privacy database and startup
//  files. It also cannot take a snapshot: `check()` is the only thing that calls `Diff.run`, and
//  nothing below calls `check()`. **If a picture ever shows this Mac's own settings, that missing
//  launch check is what broke** — and the damage would not be a wrong picture, it would be this
//  harness writing a row into somebody's real settings record.
//
//  Both demo Macs come from `DemoData`, whose snapshots are invented and whose machine identifier
//  is a made-up `Mac15,3`.
//
//  ## ⚠️ Why the unwell Mac is the picture that matters here
//
//  Four of this section's paths will never appear on the machine of anybody building it: a firewall
//  that went off, a configuration profile that arrived on a Thursday, an app that gained the
//  screen, and a switch an organisation took over. Nobody is going to enrol their Mac in an MDM to
//  look at a screen, so unless it is invented it never gets looked at — and it is exactly where the
//  wording has to stay flat rather than alarming.
//
//      bin/make-shots.sh
//

@Suite("View shots — Changes", .serialized)
@MainActor
struct ChangesShot {

    // MARK: - Fixtures

    /// A shell state positioned on Changes.
    ///
    /// ⚠️ `demoMode` and `demoMachine` write to `UserDefaults.standard`, which under `xctest` is the
    /// test process's own domain rather than the app's. Nothing this touches survives the run.
    private func state(demo: DemoMachine? = nil) -> AppState {
        let app = AppState()
        app.demoMode = demo != nil
        if let demo { app.demoMachine = demo }
        app.selection = .changes
        return app
    }

    /// The window: the hand-rolled rail beside the pane, which is the shape `RootView` builds. The
    /// sidebar is in the picture on purpose — the face is judged against the rail beside it.
    private func window(_ app: AppState, optionsOpen: Bool = false) -> some View {
        if optionsOpen { app.openOptions.insert(.changes) }
        return HStack(spacing: 0) {
            Sidebar()
            ChangesView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    /// How tall a frame the whole page needs when nothing may scroll out of the picture.
    ///
    /// ⚠️ **This section is the tallest in the app and it is not close.** Every change carries three
    /// sentences of our own, and the unwell Mac has five of them across four rows. A shot at the
    /// window's real height photographs the scope paragraph and stops. Width is what governs
    /// reflow, so a taller frame changes nothing about the layout — it only stops
    /// `StableScrollView` hiding the rest.
    private enum PageHeight {
        /// The empty face: heading, sentence, button, scope, and the empty state.
        static let face: CGFloat = 1_200
        /// The healthy Mac: three changes, each with its three sentences.
        static let healthy: CGFloat = 3_600
        /// The unwell Mac: five changes, one of them an organisation's.
        static let unwell: CGFloat = 5_200
        /// Options open on top of that: the audit grid and all 34 watched things.
        static let whole: CGFloat = 9_600
    }

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
    /// page insets and the sidebar width all move together, exactly as they do when somebody
    /// presses ⌘+ four times. Restored whatever happens, including a failed expectation.
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

    /// One change out of a demo report, by topic. `nil` fails the test that asked for it rather
    /// than photographing something else — a picture of the wrong row is worse than no picture.
    private func change(_ machine: DemoMachine, _ topic: ChangesTopic,
                        named name: String? = nil) -> Change? {
        DemoData.changes(machine).changes(in: topic)
            .first { name == nil || $0.key.name == name }
    }

    // MARK: - The faces

    /// **Nothing has been compared yet — and here that is the ordinary state, not an edge case.**
    ///
    /// Changes never runs by itself, so this is the screen on every launch until somebody presses
    /// the button. Two things to judge by eye: it has to say plainly that the app does not check
    /// this on its own, and the scope paragraph has to be legible *above* the fold, because a person
    /// who believes this watches every preference on the Mac will read a quiet screen wrongly.
    @Test("Changes, never checked")
    func neverChecked() {
        let size = Layout.windowDefault
        bothAppearances(window(state()), width: size.width, height: PageHeight.face,
                        500, "changes-never-checked")
    }

    /// **A healthy Mac.** One macOS update, two harmless things that moved during it, and six
    /// values Wellkept keeps and does not describe.
    ///
    /// ⚠️ **Nothing in this picture is amber, and that is the thing to check.** The macOS version
    /// going up is never a fault, and one more login item is a fact about a Mac somebody installed
    /// software on. Neither carries a `safeValue`, so neither can reach `.attention` however the
    /// screen is drawn — if a tag appears here, something has set a severity by hand.
    @Test("Changes, the healthy demo Mac")
    func healthyMac() {
        bothAppearances(window(state(demo: .healthy)),
                        width: Layout.windowDefault.width, height: PageHeight.healthy,
                        502, "changes-healthy")
    }

    /// **A Mac with problems.** The firewall off, a configuration profile that appeared, an app
    /// that gained the screen, automatic updates taken over by an organisation, and a new macOS.
    ///
    /// ⚠️ Two different things must read differently in this one picture: an amber change somebody
    /// can act on, and the organisation's switch, which is stated in full and carries no colour and
    /// no imperative. A Mac configured by an employer is not a Mac with something wrong with it.
    @Test("Changes, the demo Mac with problems")
    func macWithProblems() {
        bothAppearances(window(state(demo: .problems)),
                        width: Layout.windowDefault.width, height: PageHeight.unwell,
                        504, "changes-problems")
    }

    /// **Options open** — the audit grid, and the whole list of what this section watches by name.
    ///
    /// The list is the answer to "so what does it actually look at", which the scope paragraph
    /// promises and only this panel delivers. It is 34 rows and it is the densest thing here.
    @Test("Changes, with Options expanded")
    func optionsExpanded() {
        bothAppearances(window(state(demo: .problems), optionsOpen: true),
                        width: Layout.windowDefault.width, height: PageHeight.whole,
                        506, "changes-options")
    }

    // MARK: - ⭐ One change, with its three sentences

    /// ⭐ **The picture asked for with "let's show him up and do it better".**
    ///
    /// One change, at the width it actually gets, carrying what the setting does, what turning it
    /// off costs you, and why it might have changed. The prior art everybody points at attempts the
    /// first of those and not the other two, and this is the only place the difference is visible
    /// rather than argued.
    ///
    /// The firewall, because it is the one where all three sentences carry real weight: what it
    /// does is not obvious, the cost is concrete — a café's network — and the innocent reason is
    /// the usual one.
    @Test("One change with its full description")
    func oneChangeWithItsDescription() throws {
        let firewall = try #require(change(.problems, .protections, named: "firewall"),
                                    "the unwell demo Mac no longer has a firewall change to draw")
        let column = Layout.readableColumn
        bothAppearances(ChangeBlockView(change: firewall, now: DemoData.changes(.problems).ranAt)
                            .padding(Space.page)
                            .frame(width: column, alignment: .leading),
                        width: column, height: 900, 508, "changes-description")
    }

    /// **The whole Protections row**, which is how a person actually meets a description: a heading,
    /// what the row means, and the changes inside it.
    @Test("A whole topic row, open")
    func aWholeTopicRow() {
        let report = DemoData.changes(.problems)
        let column = Layout.readableColumn
        bothAppearances(ChangesTopicRow(topic: .protections,
                                        changes: report.changes(in: .protections),
                                        index: 0,
                                        now: report.ranAt)
                            .padding(Space.page)
                            .frame(width: column, alignment: .leading),
                        width: column, height: 1_600, 510, "changes-topic-row")
    }

    // MARK: - ⭐ The macOS-update attribution

    /// ⭐ **The strongest sentence this section has, photographed in both of its strengths.**
    ///
    /// *"This changed while your Mac was off for the macOS 26.6.2 update — it was off for four
    /// minutes and 52 seconds."* Changed **during**, never *the update changed it*: two things
    /// happened in the same window, and that is not evidence one caused the other.
    ///
    /// Both Macs are in the picture because their outages were measured differently, and the
    /// difference is deliberate and easy to lose:
    ///
    /// - the healthy Mac's is **to the second**, which is what a second-precision source at both
    ///   ends buys;
    /// - the unwell Mac's is **to the minute** — "about six minutes" — because the shutdown record
    ///   has minute resolution and inventing 52 seconds out of it would be the most persuasive kind
    ///   of wrong answer.
    @Test("The macOS-update attribution, at both precisions")
    func theUpdateAttribution() throws {
        let sharp = try #require(change(.healthy, .macOSItself),
                                 "the healthy demo Mac no longer records a macOS update")
        let blunt = try #require(change(.problems, .macOSItself),
                                 "the unwell demo Mac no longer records a macOS update")
        let column = Layout.readableColumn

        bothAppearances(
            VStack(alignment: .leading, spacing: Space.block) {
                ChangeBlockView(change: sharp, now: DemoData.changes(.healthy).ranAt)
                ChangeBlockView(change: blunt, now: DemoData.changes(.problems).ranAt)
            }
            .padding(Space.page)
            .frame(width: column, alignment: .leading),
            width: column, height: 1_600, 512, "changes-update-attribution")
    }

    // MARK: - Full Disk Access refused

    /// ⭐ **Answer 4, 2026-08-28** — one line saying the privacy permissions changed and we
    /// could not see what, with the button that grants access. **Once, never repeated per
    /// permission.**
    ///
    /// This is the state `DemoData` cannot show, for the same reason `SecurityRefusedShot` exists:
    /// demo mode offers two *machines*, and this is not a machine — it is a permission this app was
    /// refused. It is also the likeliest real screen in the section, because setup's last step
    /// offers "Finish later".
    ///
    /// ⚠️ The wording below is checked against the wording `ChangesView` actually draws — see
    /// `ChangesRefusedWordTests`. A picture of a sentence the app no longer says is worse than no
    /// picture, because it looks current.
    @Test("Changes, with the privacy permissions unreadable")
    func privacyWentDark() {
        let column = Layout.readableColumn
        bothAppearances(
            VStack(alignment: .leading, spacing: Space.block) {
                ChangesNoticeLine(symbol: "eye.slash",
                                  text: ChangesShotWords.privacyWentDark,
                                  severity: .attention,
                                  buttonTitle: "Open System Settings…") { }
                PermissionNoticeLine(section: .changes)
            }
            .padding(Space.page)
            .frame(width: column, alignment: .leading),
            width: column, height: 700, 514, "changes-privacy-unreadable")
    }

    // MARK: - 200% text

    /// ⚠️ **Where this section breaks first, and it breaks worse than Security.**
    ///
    /// Every change carries three labelled sentences, so doubled type turns one row into most of a
    /// screen. macOS ships no Dynamic Type for Macs, the HIG still asks for 200% enlargement, and a
    /// picture is the only thing that can say whether the page reflowed rather than zoomed.
    @Test("Changes at 200% text")
    func atLargestTextSize() {
        atLargestText {
            let width = Layout.windowDefault.width
            bothAppearances(window(state()), width: width, height: 2_000,
                            516, "changes-200-never-checked")
            bothAppearances(window(state(demo: .healthy)), width: width, height: 7_000,
                            518, "changes-200-healthy")
            bothAppearances(window(state(demo: .problems)), width: width, height: 10_000,
                            520, "changes-200-problems")
        }
    }

    /// ⚠️ **The floor size at 200% text — the hardest thing this layout is ever asked to do.**
    ///
    /// 1020 × 640 is a size the window genuinely drags to, and three labelled sentences inside a
    /// tinted block inside a 700-point column that no longer fits is the worst case in the app.
    @Test("Changes at 200% text, at the smallest the window goes")
    func atTheFloorSizeWithLargestText() {
        atLargestText {
            let size = Layout.windowMinimum
            bothAppearances(window(state(demo: .problems)),
                            width: size.width, height: size.height, 522, "changes-200-floor")
        }
    }

    /// **One change and its three sentences at 200% text.** The densest words-per-point in the app,
    /// and the thing that decides whether this section reads as a health check or as a lecture.
    @Test("A change with its description at 200% text")
    func descriptionAtLargestText() throws {
        let firewall = try #require(change(.problems, .protections, named: "firewall"))
        atLargestText {
            bothAppearances(ChangeBlockView(change: firewall, now: DemoData.changes(.problems).ranAt)
                                .padding(Space.page)
                                .frame(width: Layout.readableColumn, alignment: .leading),
                            width: Layout.readableColumn, height: 2_000, 524, "changes-200-description")
        }
    }

    /// The refusal line at 200% text. It carries a button under a paragraph, which is the shape
    /// that collapses first when the column stops fitting.
    @Test("The Full Disk Access line at 200% text")
    func refusalAtLargestText() {
        atLargestText {
            bothAppearances(
                ChangesNoticeLine(symbol: "eye.slash",
                                  text: ChangesShotWords.privacyWentDark,
                                  severity: .attention,
                                  buttonTitle: "Open System Settings…") { }
                    .padding(Space.page)
                    .frame(width: Layout.readableColumn, alignment: .leading),
                width: Layout.readableColumn, height: 900, 526, "changes-200-privacy-unreadable")
        }
    }
}

// MARK: - The one sentence this file has to keep in step with the app

/// ⚠️ **The Full Disk Access sentence lives inside `ChangesView` as a private view**, so a picture
/// of it cannot be taken by calling into the app; it has to be typed here.
///
/// That is a copy, and a copy drifts. `ChangesRefusedWordTests` below compares this string with the
/// source of `ChangesView.swift` and fails the build when the two part company — which turns the
/// only duplication in this harness from a silent liability into a named one.
enum ChangesShotWords {
    static let privacyWentDark =
        "Which apps can use your camera, your microphone and your screen changed between these two "
        + "looks, and Wellkept could not see what moved. macOS keeps that list private without "
        + "Full Disk Access."
}

// MARK: - What the pictures are checked to be showing

/// ⚠️ **A picture proves a screen laid out; it does not prove the screen was right.**
///
/// These are the things somebody would otherwise have to notice by eye in a PNG, and would not: an
/// amber tag on a Mac where nothing is wrong, an app named as the cause of something, a copied
/// sentence that has drifted from the app.
@Suite("What the Changes pictures are showing")
@MainActor
struct ChangesShotContentTests {

    /// ⚠️ **Nothing on the healthy Mac is amber.** A macOS update and one more login item are not
    /// faults, and neither carries a `safeValue`, so neither can reach `.attention` — unless
    /// somebody sets a severity by hand, which this is here to catch.
    @Test func nothingInTheHealthyPictureIsAmber() {
        let report = DemoData.changes(.healthy)
        #expect(!report.changes.isEmpty, "the quiet picture has nothing in it to look at")
        #expect(report.worst == .information)
        #expect(report.status == .good)
        for change in report.changes {
            #expect(change.severity(Watched.of(change.key)) == .information,
                    "\(change.what) is coloured on a Mac where nothing is wrong")
        }
    }

    /// ⚠️ **And nothing in any picture is red.** `Change.severity` has no route to `.problem` —
    /// whether the resulting state is a problem is Security's question, answered there once.
    @Test func nothingInAnyPictureIsRed() {
        for machine in [DemoMachine.healthy, .problems] {
            let report = DemoData.changes(machine)
            #expect(report.worst != .problem)
            for change in report.changes {
                #expect(change.severity(Watched.of(change.key)) != .problem,
                        "\(change.what) is red, and this section's ceiling is amber")
            }
        }
    }

    /// ⛔ **No app is named as the cause of anything, in either picture.**
    ///
    /// "Sample Remote — Screen recording" names the app that *holds* the permission, which is what
    /// the reader actually knows. The clause beside it still says we cannot tell what did it.
    @Test func noPictureNamesAnAppAsTheCause() {
        for machine in [DemoMachine.healthy, .problems] {
            for change in DemoData.changes(machine).changes {
                let clause = change.cause.clause.lowercased()
                for word in ["zoom", "rectangle", "sample", "remote", "weather", "app"] {
                    #expect(!clause.contains(word),
                            "the cause beside \(change.what) names software: \(change.cause.clause)")
                }
            }
        }
    }

    /// ⭐ Both attribution pictures say **during**, and neither says **because** — and the two
    /// precisions are genuinely different, which is the only reason the second picture exists.
    @Test func theAttributionPicturesSayDuringAndNeverBecause() throws {
        let sharp = try #require(DemoData.changes(.healthy).changes(in: .macOSItself).first)
        let blunt = try #require(DemoData.changes(.problems).changes(in: .macOSItself).first)

        for change in [sharp, blunt] {
            let said = change.sentence(now: Date()).lowercased()
            #expect(said.contains("while your Mac was off for the macos".lowercased()))
            #expect(!said.contains("caused"))
            #expect(!said.contains("the update changed"))
            #expect(change.confidence == .consistent)
        }

        #expect(sharp.cause.clause.contains(" and "), "the second-precision outage lost its seconds")
        #expect(blunt.cause.clause.contains("about "),
                "the minute-precision outage is claiming seconds it never measured")
        #expect(!blunt.cause.clause.contains("second"))
    }

    /// The unwell picture carries the organisation's switch, stated in full and coloured not at all.
    @Test func theOrganisationsSwitchIsInThePictureAndIsNotAFault() throws {
        let report = DemoData.changes(.problems)
        let managed = try #require(report.changes.first { $0.cause == .setByAnOrganisation },
                                   "the one branch nobody will otherwise see is not in the picture")
        #expect(managed.confidence == .certain)
        #expect(managed.severity(Watched.of(managed.key)) == .information)
        #expect(managed.cause.clause == "an organisation's profile sets this")
    }

    /// ⚠️ The undescribed count is in the picture as **a number in a sentence**, and there are no
    /// rows for it. 41 rows of raw preference keys is what makes a journal opened once.
    @Test func theUndescribedCountIsASentenceAndNotRows() {
        let report = DemoData.changes(.problems)
        #expect(report.undescribed > 0, "the counted-never-listed line is not in any picture")
        #expect(report.summary.contains("other values also changed"))
        for change in report.changes {
            #expect(Watched.of(change.key) != nil,
                    "\(change.key.storageKey) is drawn as a row with nothing able to describe it")
        }
    }

    /// Every change in every picture has all three of our sentences behind it. A row drawn with a
    /// missing description would photograph as a gap nobody would notice.
    @Test func everyChangeInThePicturesHasThreeSentences() {
        for machine in [DemoMachine.healthy, .problems] {
            for change in DemoData.changes(machine).changes {
                guard let watched = Watched.of(change.key) else {
                    Issue.record("\(change.key.storageKey) has no description and is still a row")
                    continue
                }
                #expect(watched.description.isComplete)
                #expect(watched.description.sentences.count == 3)
            }
        }
    }
}

// MARK: - The one copied sentence, kept honest

/// ⚠️ **`ChangesShotWords.privacyWentDark` is the only string in this harness that is a copy of
/// something in the app**, because the sentence lives inside a private view and cannot be reached.
///
/// A copy that drifts is how a picture starts certifying wording the app no longer uses — which is
/// worse than having no picture, because it looks current. So the copy is compared with the source.
@Suite("The refusal sentence in the picture is the one the app draws")
struct ChangesRefusedWordTests {

    @Test func theCopiedSentenceIsStillTheAppsSentence() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tools/ViewShots
            .deletingLastPathComponent()   // Tools
            .deletingLastPathComponent()   // the repository
        let file = root.appendingPathComponent("App/Sections/ChangesView.swift")
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            Issue.record("ChangesView.swift could not be read, so the copy cannot be checked")
            return
        }

        // The source spells it across several concatenated literals. Compare on the words rather
        // than on the formatting, which is a matter of where the line breaks fell.
        let flattened = source.replacingOccurrences(of: "\"\n", with: "")
            .replacingOccurrences(of: "+ \"", with: "")
            .replacingOccurrences(of: " ", with: "")
        let wanted = ChangesShotWords.privacyWentDark.replacingOccurrences(of: " ", with: "")

        #expect(flattened.contains(wanted),
                "the Full Disk Access sentence in the picture is not the one ChangesView draws")
    }
}
