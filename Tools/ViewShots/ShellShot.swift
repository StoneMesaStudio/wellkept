//
//  ShellShot.swift
//  ViewShots
//
//  **Pictures of the real shell: the real sidebar, the real seven faces, the real Overview.**
//
//  These are not mock-ups assembled out of the design vocabulary. They are `Sidebar`,
//  `OverviewView` and `SectionFace` — the same types the app puts on screen — driven by a real
//  `AppState`. A harness that photographs a hand-built imitation is a harness that certifies a
//  screen nobody ships; the first draft of this file did exactly that, and its picture of the
//  sidebar showed zebra striping the real one does not have.
//
//  Two states are worth photographing and both are here:
//
//   - **the shell as it ships** — nothing has scanned, every verb greyed, the coming-soon line;
//   - **demo mode** — the same faces carrying `DemoData`'s invented results, which is what a
//     finished section will look like months before its engine exists.
//
//  ⚠️ Nothing here reads this Mac. `AppState` in demo mode returns invented data by construction,
//  and in the shell there is nothing to read: no check exists yet.
//
//      bin/make-shots.sh
//

import AppKit
import SwiftUI
import Testing
import WellkeptCore

@Suite("View shots — the shell")
@MainActor
struct ShellShot {

    // MARK: - Fixtures

    /// A shell state, positioned on one section.
    ///
    /// ⚠️ `demoMode`'s setter writes to `UserDefaults.standard`, which under `xctest` is the test
    /// process's own domain and not the app's. Nothing this touches survives the run — but it is
    /// worth knowing before somebody adds a shot that flips it and wonders where the value went.
    private func state(_ selection: SectionID,
                       demo: Bool = false,
                       machine: DemoMachine = .healthy) -> AppState {
        let app = AppState()
        app.demoMode = demo
        app.demoMachine = machine
        app.selection = selection
        return app
    }

    /// The window: the hand-rolled rail beside the pane, which is the shape `RootView` builds and
    /// the one that sidesteps the centred-detail-band bug.
    ///
    /// Assembled here rather than photographing `RootView` itself because `RootView` also carries
    /// the setup cover, which needs `SetupState` and would put the welcome page in every picture.
    /// ⚠️ **Hardware and Security are photographed as the REAL views, not as generic faces.** They
    /// are the two sections with an engine behind them, and a harness that kept showing the
    /// placeholder here would certify a screen the app no longer draws.
    ///
    /// It reads nothing from this Mac. In demo mode `AppState` returns an invented machine by
    /// construction, and outside demo mode `HardwareModel` has no report — the launch check is
    /// started by `RootView`, which this harness does not render, and `checkOnLaunch` refuses under
    /// `xctest` in any case. `SecurityModel` has no launch check at all: Security runs only on a
    /// press, so there is nothing here that could start its six-second sweep of this Mac.
    private func window(_ section: SectionID,
                        demo: Bool = false,
                        machine: DemoMachine = .healthy) -> some View {
        let app = state(section, demo: demo, machine: machine)
        return HStack(spacing: 0) {
            Sidebar()
            Group {
                switch section {
                case .overview: AnyView(OverviewView())
                case .hardware: AnyView(HardwareView())
                case .security: AnyView(SecurityView())
                default:        AnyView(SectionFace(section))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    // MARK: - The shots

    /// Overview at the window's opening size, in both appearances. The bronze is a different hex in
    /// each and only one of the two was ever judged by eye.
    @Test("Overview, at the opening size, light and dark")
    func overviewBothAppearances() {
        let size = Layout.windowDefault
        ShotWriter.write(window(.overview), width: size.width, height: size.height,
                         name: "01-overview-light", scheme: .light)
        ShotWriter.write(window(.overview), width: size.width, height: size.height,
                         name: "02-overview-dark", scheme: .dark)
    }

    /// ⚠️ Every face at the window's FLOOR size, not its opening size. A face that reads correctly
    /// at 1100 points and clips at 1020 is a face nobody photographed at a size the window can
    /// actually be dragged to — and 1020 × 640 is a size this app allows.
    @Test("All seven faces, at the smallest the window goes")
    func everyFace() {
        let size = Layout.windowMinimum
        for (index, section) in SectionID.allCases.enumerated() {
            // Numbered so the folder sorts in sidebar order rather than alphabetically — "apps"
            // first is not the order anybody reviews them in.
            ShotWriter.write(window(section), width: size.width, height: size.height,
                             name: "\(index + 10)-\(section.rawValue)")
        }
    }

    /// The same seven carrying invented results.
    ///
    /// This is the set worth looking at hardest: the shell's faces are nearly empty, so a spacing
    /// or contrast mistake that only shows up under real content would otherwise stay invisible
    /// until the first engine lands.
    @Test("The seven faces with sample results in them")
    func everyFaceInDemoMode() {
        let size = Layout.windowDefault
        for (index, section) in SectionID.allCases.enumerated() {
            ShotWriter.write(window(section, demo: true), width: size.width, height: size.height,
                             name: "\(index + 40)-demo-\(section.rawValue)")
        }
    }

    /// **Overview under each of the two demo Macs.**
    ///
    /// Decided 2026-08-27: *"I would give them both. The goal is a healthy mac."* This is the pair of
    /// pictures that decides whether that worked: Overview on the healthy Mac says "Everything
    /// looks fine" with the audit trail open beneath it, and on the unwell one it carries **one**
    /// row from Hardware — never five — beside whatever the other sections found.
    ///
    /// The Hardware face itself is photographed in `HardwareShot`, in both appearances, at 200%
    /// text, and with the Options panel open. This test is only about what reaches the summary.
    @Test("Overview, on a healthy Mac and on one with problems")
    func overviewUnderBothDemoMachines() {
        let size = Layout.windowDefault
        ShotWriter.write(window(.overview, demo: true, machine: .healthy),
                         width: size.width, height: size.height,
                         name: "80-overview-healthy-mac")
        ShotWriter.write(window(.overview, demo: true, machine: .problems),
                         width: size.width, height: size.height,
                         name: "81-overview-unwell-mac")
    }

    /// The sidebar on its own, large, because the selected row is one of only three places bronze
    /// is allowed to appear — and a soft plate is easy to get too strong to read a word against.
    @Test("The sidebar, with a row selected")
    func theSidebar() {
        ShotWriter.write(Sidebar().environment(state(.storage)),
                         width: Layout.sidebarWidth, height: 420, name: "20-sidebar-light")
        ShotWriter.write(Sidebar().environment(state(.storage)),
                         width: Layout.sidebarWidth, height: 420, name: "21-sidebar-dark",
                         scheme: .dark)
    }

    /// The house controls in one frame, so a change to any of them is one picture to look at rather
    /// than seven. This is the sheet to answer "does this still look right?" with.
    @Test("The control vocabulary")
    func theControls() {
        ShotWriter.write(
            VStack(alignment: .leading, spacing: Space.section) {
                Text("Controls").sectionHeading()
                HStack(spacing: Space.gutter) {
                    Button("Check my Mac") {}.buttonStyle(.appProminent)
                    Button("Finish later") {}.buttonStyle(.app)
                    Button("Check my Mac") {}.buttonStyle(.appProminent).disabled(true)
                }
                HStack(spacing: Space.gutter) {
                    StatusChip(status: .good)
                    StatusChip(status: .needsAttention)
                    StatusChip(status: .notChecked)
                }
                SegmentedControl(items: ColorLevel.allCases.map { (value: $0, label: $0.label) },
                                 selection: .constant(ColorLevel.calm))
                LabelledDisclosure("Options", isExpanded: .constant(false)) { EmptyView() }
                InlineEmptyNote(text: "Nothing checked yet.")
                Spacer(minLength: 0)
            }
            .padding(Space.page)
            .readableColumn()
            .pageGround(),
            width: 720, height: 460, name: "30-controls-light")
    }

    /// The empty state, greedy, photographed at a tall frame precisely because that is where the
    /// centred-band bug shows: if the symbol and the words sit near the top instead of the middle,
    /// the greedy frame is missing.
    @Test("The empty state fills its pane")
    func theEmptyState() {
        ShotWriter.write(
            EmptyStateView(symbol: "stethoscope",
                           title: "Nothing checked yet",
                           message: "Wellkept has not looked at this Mac. Nothing is scanned until you ask.")
                .pageGround(),
            width: 720, height: 620, name: "31-empty-state-light")
    }

    // MARK: - The one thing a picture proves better than a number

    /// **On a wide display the content stays in the 700-point column and the rest is ground.**
    ///
    /// This is decision B9, and it is the promise that quietly breaks first: a pane whose content
    /// is greedy in width looks perfect on the 1100-point window everybody develops against and
    /// runs a line of text across a 34-inch monitor for the person who has one. Nothing else in the
    /// suite can see it — the app builds, the tests pass, and the screenshot everybody takes is at
    /// the default size.
    ///
    /// So: render at 2000 points and ask whether the right-hand tenth of the picture is empty. A
    /// column that holds leaves several hundred points of bare ground there; a column that has
    /// spread fills it with words.
    ///
    /// ⚠️ This replaced an ideal-width probe ported from Waypoint, which measured 206 points for
    /// all seven faces — the sidebar's width and nothing else. `StableScrollView` pins its content
    /// to the width it is *offered*, so a Wellkept face has no ideal width to report and the probe
    /// could only ever have passed. A test that cannot fail is worse than no test.
    @Test("On a wide window the content stays in the readable column")
    func theReadableColumnHoldsOnAWideDisplay() {
        // Every section on the healthy Mac, plus Hardware on the unwell one — which is the widest
        // content in the app: a full-bleed alarm card, a machine block and an eight-column grid of
        // details, any of which could spread if one of them forgot the column.
        var cases: [(SectionID, DemoMachine)] = SectionID.allCases.map { ($0, .healthy) }
        cases.append((.hardware, .problems))

        for (section, machine) in cases {
            guard let rep = ShotWriter.render(
                window(section, demo: true, machine: machine)
                    .frame(width: 2000, height: 760)
                    .environment(\.colorScheme, .light)
                    .environment(\.palette, Palette(level: .calm, scheme: .light)),
                width: 2000, height: 760, scheme: .light)
            else { Issue.record("\(section.rawValue): nothing rendered"); continue }

            let edge = ShotWriter.distinctColours(in: rep, fromFraction: 0.90, toFraction: 0.99)
            print("PROBE \(section.rawValue) right-edge colours at 2000pt: \(edge)")
            #expect(edge <= 3, """
                \(section.rawValue): the right-hand tenth of a 2000-point window has \(edge) distinct \
                colours in it, so something is drawing out there. The content column is 700 points \
                and centres; a face that spreads past it is unreadable on a large display.
                """)
        }
    }
}
