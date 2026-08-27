//
//  HardwareShot.swift
//  ViewShots
//
//  **Pictures of the real Hardware screen — the never-checked face, both demo Macs, the Options
//  panel open, and the sheet that shows what is about to reach the clipboard.**
//
//  These are `HardwareView` and `RepairShopSheet`, the same types the app puts on screen, driven by
//  a real `AppState`. Nothing here is a mock-up assembled out of the design vocabulary: a harness
//  that photographs an imitation certifies a screen nobody ships, and `ShotWriter`'s own header is
//  the story of that mistake being made once already.
//
//  ## ⚠️ Nothing here reads this Mac
//
//  `HardwareModel.checkOnLaunch` refuses under `xctest` — it checks the environment for a test
//  bundle — so the render pumping a run loop cannot start a real sweep of the drive, the battery
//  and the panic log. The never-checked shot is genuinely a screen with no data behind it, and both
//  demo shots come from `DemoData`, whose facts are invented. If a future edit makes a picture
//  suddenly show this machine's own serial number, that gate is what broke.
//
//  ## ⚠️ Every screen is photographed at 200% text, and that is the point of the file
//
//  Hardware is the first section that is mostly numbers, and **a row of numbers is what breaks
//  first when the type doubles.** A two-column table looks tidy at 100% and comes apart at 200%:
//  the labels wrap to four lines and the figures drift away from what they describe. The rows are
//  built label-above-value precisely so that does not happen, and this is where the claim is
//  actually looked at rather than asserted in a comment.
//
//  ⚠️ **The text size is a `UserDefaults` value read live by `AppFont`, so setting it is a global
//  change for the duration of the render.** This suite is `.serialized` and puts the old value back
//  in a `defer`; a shot in another suite that happens to run during the pump would come out with
//  larger type, which is a wrong picture rather than a failed test. If the shots ever start
//  disagreeing with each other, this is the first thing to suspect.
//
//      bin/make-shots.sh
//

import AppKit
import SwiftUI
import Testing
import WellkeptCore

@Suite("View shots — Hardware", .serialized)
@MainActor
struct HardwareShot {

    // MARK: - Fixtures

    /// A shell state positioned on Hardware.
    ///
    /// ⚠️ `demoMode` and `demoMachine` write to `UserDefaults.standard`, which under `xctest` is
    /// the test process's own domain rather than the app's. Nothing this touches survives the run.
    private func state(demo: DemoMachine? = nil) -> AppState {
        let app = AppState()
        app.demoMode = demo != nil
        if let demo { app.demoMachine = demo }
        app.selection = .hardware
        return app
    }

    /// The window: the hand-rolled rail beside the pane, which is the shape `RootView` builds. The
    /// sidebar is in the picture on purpose — the Hardware face is judged against the rail beside
    /// it, and a page inset that reads correctly on its own can crowd it.
    private func window(_ app: AppState, optionsOpen: Bool = false) -> some View {
        if optionsOpen { app.openOptions.insert(.hardware) }
        return HStack(spacing: 0) {
            Sidebar()
            HardwareView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    /// How tall a frame the whole page needs when nothing is allowed to scroll out of the picture.
    ///
    /// ⚠️ **A shot at the window's real height photographs the top of the section and nothing
    /// else**, which is fine for the faces and useless for Options: the panel sits below the
    /// machine block and five rows, so a 760-point frame produced a picture named "options" that
    /// did not contain the options. At 200% text it did not even reach the first row.
    ///
    /// Width is what governs reflow, so a taller frame changes nothing about how the content lays
    /// out — it only stops `StableScrollView` hiding the rest of it. The width stays exactly the
    /// window's, which is the number that has to be honest.
    /// ⚠️ At 200% text the whole page with Options open is around nine thousand points, and a
    /// picture eighteen thousand pixels tall is both a 150 MB bitmap and unreviewable. So the
    /// 200% face shot reaches the top of the Options panel and the details themselves are
    /// photographed separately, at the width they actually get — see `optionDetailsAtLargestText`.
    private enum PageHeight {
        static let whole: CGFloat = 3_400
        static let wholeAtLargestText: CGFloat = 4_600
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
    /// The setting is the real one — `AppFont.scale` reads this key on every call, so the type,
    /// the page insets and the sidebar width all move together, exactly as they do when somebody
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

    // MARK: - The four faces

    /// **Nothing has been checked.** The state a person can genuinely reach — setup ends on
    /// Overview, so Hardware can be opened before anything has run — and the one that has to say
    /// why it is empty rather than looking like a screen that failed to load.
    @Test("Hardware, never checked")
    func neverChecked() {
        let size = Layout.windowDefault
        bothAppearances(window(state()), width: size.width, height: size.height,
                        50, "hardware-never-checked")
    }

    /// **A healthy Mac.** John, 2026-08-27: *"I would give them both. The goal is a healthy mac."*
    /// This is the case the product exists to be able to show, not the boring one to skip: five
    /// rows of Good, a machine block, and nothing asking anything of anybody.
    @Test("Hardware, the healthy demo Mac")
    func healthyMac() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .healthy)), width: size.width, height: size.height,
                        52, "hardware-healthy")
    }

    /// **A Mac with problems.** A drive declaring failure, a battery Apple's own check calls
    /// failed, kernel panics inside the month and macOS force-quitting running programs to free
    /// memory. Nobody is going to break a drive to look at this screen, so unless it is invented it
    /// never gets looked at at all.
    @Test("Hardware, the demo Mac with problems")
    func macWithProblems() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .problems)), width: size.width, height: size.height,
                        54, "hardware-problems")
    }

    /// **Options open**, which is where the label-above-value pairs live — the serials, the cycle
    /// counts, the error counts, and the speed test's own button. It is the densest thing in the
    /// section and the most likely to come apart.
    @Test("Hardware, with Options expanded")
    func optionsExpanded() {
        bothAppearances(window(state(demo: .problems), optionsOpen: true),
                        width: Layout.windowDefault.width, height: PageHeight.whole,
                        56, "hardware-options")
    }

    /// **The repair-shop copy sheet**, showing exactly what is about to reach the clipboard,
    /// serial number included, before anything is copied. Photographed on the unwell Mac, because
    /// that is the report somebody actually pastes into an email.
    @Test("The repair-shop copy sheet")
    func repairShopSheet() {
        let report = DemoData.hardware(.problems)
        let sheet = RepairShopSheet(report: report)
        // The sheet asserts its own size, which is stated at 100% text and scales — so it is asked
        // for a frame larger than it wants and allowed to settle at its own.
        bothAppearances(sheet, width: 700, height: 720, 58, "hardware-repair-copy")
    }

    // MARK: - The same five at 200% text
    //
    // ⚠️ **This is where a row of numbers breaks.** Not a nicety: macOS ships no Dynamic Type for
    // Macs, the HIG still asks for 200% enlargement, and every measurement in this app is stated as
    // "N points at 100% text" so that the page can genuinely reflow rather than zoom. A picture is
    // the only thing that can say whether it did.

    @Test("Hardware at 200% text — every screen")
    func everyScreenAtLargestText() {
        atLargestText {
            // The whole page, not the first screenful. At 200% text a 760-point frame reaches the
            // heading and the first sentence, which says nothing about the rows — and the rows are
            // the reason this test exists.
            let width = Layout.windowDefault.width
            let height = PageHeight.wholeAtLargestText
            bothAppearances(window(state()), width: width, height: Layout.windowDefault.height,
                            60, "hardware-200-never-checked")
            bothAppearances(window(state(demo: .healthy)), width: width, height: height,
                            62, "hardware-200-healthy")
            bothAppearances(window(state(demo: .problems)), width: width, height: height,
                            64, "hardware-200-problems")
            bothAppearances(window(state(demo: .problems), optionsOpen: true),
                            width: width, height: height, 66, "hardware-200-options")
            bothAppearances(RepairShopSheet(report: DemoData.hardware(.problems)),
                            width: 900, height: 900, 68, "hardware-200-repair-copy")
        }
    }

    /// ⚠️ **The floor size, at 200% text — the worst case the window allows.**
    ///
    /// 1020 × 640 is a size this app can genuinely be dragged to, and a face that reads correctly
    /// at the opening size and clips at the floor is a face nobody photographed at a size the
    /// window can actually be. Combined with doubled type it is the hardest thing the layout is
    /// ever asked to do.
    @Test("Hardware at 200% text, at the smallest the window goes")
    func atTheFloorSizeWithLargestText() {
        atLargestText {
            let size = Layout.windowMinimum
            bothAppearances(window(state(demo: .problems), optionsOpen: true),
                            width: size.width, height: size.height, 70, "hardware-200-floor")
        }
    }

    /// **The label-above-value pairs on their own, at 200% text, at the width they actually get.**
    ///
    /// This is the densest thing in the section — a failing drive's Options block is sixteen pairs,
    /// several of them a serial number or a byte count — and at 200% text it is the first thing
    /// that would come apart if a fixed column width had crept in anywhere. It is photographed
    /// separately because the whole page at that size is nine thousand points tall and a picture
    /// that tall is not a picture anybody looks at.
    ///
    /// `ReadingDetails` is the real view the real Options panel draws; only the frame is the
    /// harness's.
    @Test("The Options details at 200% text")
    func optionDetailsAtLargestText() {
        let report = DemoData.hardware(.problems)
        guard let drive = report.reading(.drive) else {
            Issue.record("the unwell demo Mac has no drive row to photograph")
            return
        }
        atLargestText {
            bothAppearances(
                VStack(alignment: .leading, spacing: Space.section) {
                    ReadingDetails(reading: drive)
                    Spacer(minLength: 0)
                }
                .padding(Space.page)
                .readableColumn()
                .pageGround(),
                width: Layout.readableColumn + 120, height: 2_000, 72, "hardware-200-drive-details")
        }
    }

    // MARK: - The one thing a picture proves better than a number

    /// **At 200% text the content still stays inside the readable column.**
    ///
    /// The failure this catches is specific and invisible to every other test in the build: a fixed
    /// measurement somewhere in a row — a column width, a figure's frame, a padding written as a
    /// literal instead of through `AppFont.pt` — that holds at 100% and pushes content out past the
    /// column when the type doubles. The app builds, the tests pass, and the screenshot everybody
    /// takes is at 100%.
    ///
    /// So: render at 2000 points with the type at 200% and ask whether the right-hand tenth of the
    /// picture is empty. A column that holds leaves several hundred points of bare ground there; a
    /// row that has spread fills it with words.
    @Test("At 200% text the Hardware face still holds the readable column")
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
                print("PROBE hardware-200-\(machine.rawValue) right-edge colours at 2000pt: \(edge)")
                #expect(edge <= 3, """
                    hardware (\(machine.rawValue)) at 200% text: the right-hand tenth of a \
                    2000-point window has \(edge) distinct colours in it, so a row is drawing out \
                    there. The content column is 700 points and centres — something in the section \
                    is sized with a literal instead of through AppFont.pt.
                    """)
            }
        }
    }
}

// MARK: - The demo Macs have to be what they claim

/// ⭐ **The two invented Macs are the only way the failing-drive path is ever exercised**, so what
/// they claim to be is checked rather than assumed.
///
/// This suite is in `ViewShots` rather than in `WellkeptTests` for one structural reason:
/// `WellkeptTests` compiles `Tests/` against the `WellkeptCore` package alone and cannot see an
/// app-internal type. `ViewShots` compiles the whole app, so `DemoData`, `DriveReader` and
/// `DriveFacts` are reachable here and nowhere else in the suite.
///
/// ⚠️ Nothing here touches a drive. `DriveReader.reading(for:)` and `DriveReader.alarm(for:)` are
/// pure functions over facts that are typed out in `DriveReader.swift`, which is what makes it
/// possible to look at the failing screen without breaking a disk.
@Suite("Hardware — the demo Macs are what they claim")
struct DemoMachineTests {

    /// The healthy Mac is Good, complete, and sends nothing to Overview. If this ever fails, the
    /// screenshot everybody uses to show what the product is for has a warning on it.
    @Test func theHealthyMacIsHealthy() {
        let report = DemoData.hardware(.healthy)
        #expect(report.status == .good)
        #expect(report.complete)
        #expect(report.overviewFinding == nil)
        #expect(DemoData.driveAlarm(.healthy) == nil)

        // Every row read something. A demo Mac quietly reporting "this Mac does not report it" on
        // four rows would photograph as a screen that could not do its job.
        for reading in report.readings {
            #expect(reading.unreadable == nil,
                    "the healthy demo Mac cannot read its own \(reading.topic.label)")
        }
    }

    /// The unwell Mac has a real problem in it, and it is the drive.
    @Test func theMacWithProblemsHasAFailingDrive() throws {
        let report = DemoData.hardware(.problems)
        #expect(report.status == .needsAttention)

        let drive = try #require(report.reading(.drive))
        #expect(drive.severity == .problem)
        #expect(drive.status == .needsAttention)

        // The one row that reaches Overview is the worst one, and it carries its reason.
        let finding = try #require(report.overviewFinding)
        #expect(finding.severity == .problem)
        #expect(finding.section == .hardware)
        #expect(!finding.reason.isEmpty)
    }

    /// The failing-drive screen is two steps and nothing else: copy the files off, then get it
    /// replaced. It quotes Apple's own word rather than inventing a diagnosis.
    @Test func theFailingDriveScreenIsTwoStepsAndQuotesTheDriveItself() throws {
        let alarm = try #require(DemoData.driveAlarm(.problems))
        #expect(alarm.steps.count == 2)
        #expect(!alarm.headline.isEmpty)
        #expect(!alarm.verdictQuote.isEmpty)
        #expect(!alarm.identification.isEmpty)
        for step in alarm.steps { #expect(!step.sentence.isEmpty) }
    }

    /// ⚠️ **A drive that declares a fault is a problem; a drive that is merely worn is not.** The
    /// same reader, the same call, two invented drives — which is the cheapest possible check on
    /// the distinction the whole section is built around.
    @Test func aWornDriveIsNotAFaultButADeclaredFaultIs() {
        let healthy = DriveReader.reading(for: [DriveFacts.exampleHealthy])
        #expect(healthy.severity == .information)
        #expect(healthy.status == .good)

        let failing = DriveReader.reading(for: [DriveFacts.exampleFailing])
        #expect(failing.severity == .problem)
        #expect(failing.status == .needsAttention)
        // The failing row gives files to copy rather than a percentage to puzzle over.
        #expect(failing.measure == nil)

        // A drive that keeps its health check to itself is neither: not a fault, and not a zero.
        let quiet = DriveReader.reading(for: [DriveFacts.exampleExternal])
        #expect(quiet.severity == .information)
    }

    /// Demo mode's whole promise. Both Macs report an invented serial, and neither is this one.
    @Test func neitherDemoMacIsThisMac() {
        for machine in DemoMachine.allCases {
            let serial = DemoData.hardware(machine).facts.serialNumber
            #expect(serial?.hasPrefix("DEMO") == true,
                    "\(machine.rawValue) is carrying a serial that is not obviously invented: \(serial ?? "nil")")
        }
        #expect(Set(DemoMachine.allCases.map(\.label)).count == DemoMachine.allCases.count)
        for machine in DemoMachine.allCases {
            #expect(!machine.blurb.isEmpty, "\(machine.rawValue) has no blurb — the two options are two words apart")
        }
    }
}
