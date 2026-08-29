//
//  OverviewSweepShot.swift
//  ViewShots
//
//  **Pictures of "Check my Mac" while it is running, and of what it leaves behind.**
//
//  These are the three states nobody would otherwise ever see in a screenshot, because they last a
//  few seconds each and only on a real Mac:
//
//   1. **mid-sweep** — the section being read, the count of sections, the audit trail open
//      underneath it with rows landing;
//   2. **stopping** — Stop pressed, the current section still finishing, and the sentence that
//      says so rather than pretending the press was instant;
//   3. **skipped** — a finished sweep that left Apps alone because nobody has answered the update
//      question, with the row that says why and opens the place to answer.
//
//  ⚠️ **Nothing here reads this Mac.** The sweep's state machine holds no results, so it is driven
//  by hand; the records beside it are constructed values. No section model is started and
//  `runEverything` is never called — see `SweepTests` for why that matters in a gate.
//
//      bin/make-shots.sh
//

import AppKit
import SwiftUI
import Testing
import WellkeptCore

@Suite("View shots — Check my Mac", .serialized)
@MainActor
struct OverviewSweepShot {

    /// ⚠️ **`demoMode` is a stored preference and `xctest` shares one defaults domain across every
    /// suite in this bundle.** A suite that ran earlier and left the switch on would make these
    /// pictures show the invented Mac while claiming to show a sweep of this one.
    private func realState() -> AppState {
        let app = AppState()
        app.demoMode = false
        return app
    }

    /// A Mac two sections into a sweep: Hardware and Backup are in, Security is being read.
    private func partWaySweep() -> AppState {
        let app = realState()
        let started = Date()
        app.sweep.begin(at: started)

        app.publish(CheckRecord(section: .hardware, ranAt: started,
                                status: .good, complete: true), finding: nil)
        app.sweep.enter(.hardware)
        app.sweep.leave(.hardware, landed: true)

        app.publish(CheckRecord(section: .backup, ranAt: started.addingTimeInterval(1),
                                status: .needsAttention, complete: true),
                    finding: Finding(section: .backup,
                                     title: "No backup has run for 19 days",
                                     reason: "The backup drive has not been connected since 9 August.",
                                     severity: .problem,
                                     measure: "19 days",
                                     verb: "Open Backup"))
        app.sweep.enter(.backup)
        app.sweep.leave(.backup, landed: true)

        app.sweep.enter(.security)
        return app
    }

    /// The window, assembled the way `ShellShot` assembles it, so these pictures are comparable
    /// with the rest of the set.
    private func window(_ app: AppState) -> some View {
        HStack(spacing: 0) {
            Sidebar()
            OverviewView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    /// Half a minute is a long time to look at a button that has gone grey. This is the picture
    /// that decides whether the waiting reads as work rather than as a hang.
    @Test("Overview, mid-sweep, light and dark")
    func midSweep() {
        let size = Layout.windowDefault
        ShotWriter.write(window(partWaySweep()), width: size.width, height: size.height,
                         name: "90-overview-sweep-running", scheme: .light)
        ShotWriter.write(window(partWaySweep()), width: size.width, height: size.height,
                         name: "91-overview-sweep-running-dark", scheme: .dark)
    }

    /// ⚠️ Stop is not instant — the readers run on detached tasks and the current section finishes
    /// first. This is the picture of the app saying so.
    @Test("Overview, after Stop is pressed and before the section lets go")
    func stopping() {
        let app = partWaySweep()
        app.sweep.requestStop()
        let size = Layout.windowDefault
        ShotWriter.write(window(app), width: size.width, height: size.height,
                         name: "92-overview-sweep-stopping")
    }

    /// ⭐ **The consent skip, on screen.** A sweep ran everything it was allowed to and left Apps
    /// alone, because pressing this button is not an answer to the update question.
    @Test("Overview, after a sweep that skipped Apps for want of an answer")
    func skippedApps() {
        let app = realState()
        let started = Date()
        app.sweep.begin(at: started)
        for section in Sweep.order {
            if section == .apps {
                app.sweep.skip(section, why: SweepWords.appsNotAsked)
                continue
            }
            app.publish(CheckRecord(section: section, ranAt: started,
                                    status: .good, complete: true), finding: nil)
            app.sweep.enter(section)
            app.sweep.leave(section, landed: true)
        }
        app.closeSweep(startedAt: started, now: started.addingTimeInterval(31))

        let size = Layout.windowDefault
        ShotWriter.write(window(app), width: size.width, height: size.height,
                         name: "93-overview-sweep-apps-skipped")
    }
}
