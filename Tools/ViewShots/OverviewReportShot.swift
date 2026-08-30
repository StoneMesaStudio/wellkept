// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI
import Testing
import WellkeptCore

//  OverviewReportShot.swift
//  ViewShots
//
//  ⭐ **Pictures of the four Overview states nobody sees by accident, and of the report as it
//  prints.**
//
//  `OverviewSweepShot` photographs the sweep while it is running. This file photographs the states
//  a person actually ends up in — and the page they hand to somebody else.
//
//  ## ⛔ Nothing here reads this Mac
//
//  Every record below is typed out and filed through `AppState.publish`, the same call a real check
//  makes. `runEverything()` is never called, no reader runs, and **nothing here prints or writes a
//  file** — the printed page is drawn into a bitmap from the identical attributed string
//  `NSPrintOperation` would be handed.
//
//  ## ⚠️ The four pictures, and what to look at in each
//
//  - **The clean state.** The one screen this whole app exists to be able to show. Look at what is
//    *not* on it: no score, no badge, no number out of anything — a sentence and a date, and the
//    audit trail open underneath it, because "everything looks fine" is worth exactly as much as
//    the evidence behind it. The developer asked for that list by name.
//
//    ⚠️ **On a Mac where Full Disk Access is off — which the test runner is — this picture also
//    carries the standing permission notice, directly under a headline saying everything looks
//    fine.** That is not the harness lying: the records here are typed out as `complete: true`,
//    while `PermissionNoticeRow` reads the machine's real grant. In the app the two agree, because
//    a section that ran without the grant files `complete: false` and the headline changes. But
//    they agree by *convention* rather than by construction — Overview's headline consults the
//    records and nothing else — so a section that ever filed `complete: true` with the grant off
//    would put those two sentences on one screen for real. `HealthReport` does not have that gap:
//    `AppState.reportPermissionsOff` reads the live grant, so a page made while the switch is off
//    is never a clean bill of health whatever the records say. Worth closing on the screen too.
//  - **Two sections in, at 200% text.** `OverviewSweepShot` has this at 100%; the question here is
//    whether the running sentence, the Stop button and the audit rows still hold their columns when
//    somebody has turned the type up in order to read them.
//  - **A permission refused.** Two pictures, because the state has two halves that appear on
//    different Macs: the headline and the audit rows on a Mac where the checks ran short, and the
//    standing notice card itself — which cannot be photographed at all on a Mac where the grant is
//    on, which is why `PermissionNoticeRow` carries a seam.
//  - **The report as it prints.** Every caveat is above the findings, the audit trail carries all
//    seven with the ones that never ran saying "Not run", and the serial number is on the page only
//    because the person left the switch on.
//
//      bin/make-shots.sh

@Suite("View shots — Overview and the report", .serialized)
@MainActor
struct OverviewReportShot {

    // MARK: - Fixtures

    private static let ran = Date(timeIntervalSince1970: 1_787_000_000)

    /// A window with the given records filed, and nothing running.
    ///
    /// ⚠️ `demoMode` writes to `UserDefaults.standard`, which under `xctest` is the test process's
    /// own domain. Nothing this touches survives the run.
    private func window(records: [SectionID: CheckRecord],
                        findings: [Finding] = [],
                        auditOpen: Bool? = nil) -> AppState {
        let app = AppState()
        app.demoMode = false
        app.selection = .overview
        for section in SectionID.allCases {
            guard let record = records[section] else { continue }
            app.publish(record, finding: findings.first { $0.section == section })
        }
        app.whatWasCheckedOpen = auditOpen
        return app
    }

    /// Every checkable section ran, saw everything, found nothing — plus Overview's own line, which
    /// is what a finished sweep files.
    private static func aCleanMac() -> [SectionID: CheckRecord] {
        var out: [SectionID: CheckRecord] = [:]
        for (index, section) in SectionID.checkable.enumerated() {
            out[section] = CheckRecord(section: section,
                                       ranAt: ran.addingTimeInterval(Double(index) * 4),
                                       status: .good, complete: true)
        }
        out[.overview] = CheckRecord(section: .overview, ranAt: ran.addingTimeInterval(31),
                                     status: .good, complete: true)
        return out
    }

    /// The same Mac with Full Disk Access off: four checks ran short, and they say so.
    private static func aMacThatCouldNotSeeEverything() -> [SectionID: CheckRecord] {
        var out = aCleanMac()
        for section in [SectionID.storage, .apps, .security, .changes] {
            out[section] = CheckRecord(section: section, ranAt: ran,
                                       status: .good, complete: false)
        }
        out[.overview] = CheckRecord(section: .overview, ranAt: ran.addingTimeInterval(31),
                                     status: .good, complete: false)
        return out
    }

    /// The window, assembled the way `ShellShot` and `OverviewSweepShot` assemble it, so these
    /// pictures are comparable with the rest of the set.
    private func screen(_ app: AppState) -> some View {
        HStack(spacing: 0) {
            Sidebar()
            OverviewView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    /// A block of real views inside the page's own chrome, for the pictures that are of one part of
    /// a screen rather than of the whole thing. Same shape as `BackupShot.page`.
    private func page(_ view: some View) -> some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) { view }
                .padding(Space.page)
                .readableColumn()
        }
        .fillsPane()
        .pageGround()
    }

    private func bothAppearances(_ view: some View, width: CGFloat, height: CGFloat,
                                 _ number: Int, _ name: String) {
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number)-\(name)-light", scheme: .light)
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number + 1)-\(name)-dark", scheme: .dark)
    }

    /// Run a block with the app's text size turned up. Restored whatever happens.
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

    /// ⚠️ **Taller than a window, and measured rather than guessed.** On a Mac where Full Disk
    /// Access is off the standing notice alone is about 900 points, and the first version of these
    /// pictures cut the audit trail off below the fold — a picture of the audit trail with no audit
    /// trail in it, which is exactly the kind of wrong-but-not-blank the harness cannot catch.
    private enum PageHeight {
        static let whole: CGFloat = 2_700
        static let atLargestText: CGFloat = 5_400
    }

    // MARK: - ⭐ The clean state

    /// ⭐ **"Everything looks fine" and the date — and never a score.**
    ///
    /// The audit trail opens by itself here and only here: on a Mac with nothing wrong, the list of
    /// what was actually checked *is* the reassurance, and a verdict with its evidence folded away
    /// is an opinion. The developer asked for it in those words on 2026-08-26.
    @Test("Overview, everything fine")
    func theCleanState() {
        let size = Layout.windowDefault
        bothAppearances(screen(window(records: Self.aCleanMac())),
                        width: size.width, height: PageHeight.whole,
                        700, "overview-clean")
    }

    @Test("Overview, everything fine, at 200% text")
    func theCleanStateAtTwoHundredPercent() {
        atLargestText {
            bothAppearances(screen(window(records: Self.aCleanMac())),
                            width: Layout.windowDefault.width, height: PageHeight.atLargestText,
                            702, "overview-200-clean")
        }
    }

    // MARK: - ⭐ The audit trail, open

    /// ⭐ **All seven, and when each ran — including the ones that did not.**
    ///
    /// Opened by hand on a Mac where two sections have run, which is the state where the list earns
    /// its keep: five rows saying "Not checked" beside two that carry a time. A list that quietly
    /// omitted the five would be reassurance about nothing.
    @Test("Overview, the audit trail open with five checks never run")
    func theAuditTrailOpen() {
        var records: [SectionID: CheckRecord] = [:]
        records[.hardware] = CheckRecord(section: .hardware, ranAt: Self.ran,
                                         status: .good, complete: true)
        records[.backup] = CheckRecord(section: .backup, ranAt: Self.ran.addingTimeInterval(2),
                                       status: .needsAttention, complete: true)
        let finding = Finding(section: .backup,
                              title: "No backup has run for 19 days",
                              reason: "The backup drive has not been connected since 9 August.",
                              severity: .problem,
                              measure: "19 days",
                              verb: "Open Backup")
        let size = Layout.windowDefault
        bothAppearances(screen(window(records: records, findings: [finding], auditOpen: true)),
                        width: size.width, height: PageHeight.whole,
                        710, "overview-audit-trail")

        atLargestText {
            bothAppearances(screen(window(records: records, findings: [finding], auditOpen: true)),
                            width: size.width, height: PageHeight.atLargestText,
                            712, "overview-200-audit-trail")
        }
    }

    // MARK: - ⚠️ A permission refused

    /// ⚠️ **The headline half.** Four checks ran short, so the verdict says so and the audit rows
    /// carry "saw part of this Mac". ⛔ Nothing on this screen says the Mac looks fine.
    @Test("Overview, four checks that could not see everything")
    func theRefusedState() {
        let size = Layout.windowDefault
        bothAppearances(screen(window(records: Self.aMacThatCouldNotSeeEverything(),
                                      auditOpen: true)),
                        width: size.width, height: PageHeight.whole,
                        714, "overview-refused")

        atLargestText {
            bothAppearances(screen(window(records: Self.aMacThatCouldNotSeeEverything(),
                                          auditOpen: true)),
                            width: size.width, height: PageHeight.atLargestText,
                            716, "overview-200-refused")
        }
    }

    /// ⚠️ **The notice card itself**, which draws only while Full Disk Access is off and therefore
    /// cannot be photographed at all on a Mac where it is on. `granted: false` is the harness seam;
    /// the app passes nothing and reads the real answer.
    @Test("Overview, the Full Disk Access notice")
    func thePermissionNotice() {
        let block = page(PermissionNoticeRow(granted: false))
        bothAppearances(block, width: Layout.windowDefault.width, height: 1_100,
                        718, "overview-permission-notice")

        atLargestText {
            bothAppearances(page(PermissionNoticeRow(granted: false)),
                            width: Layout.windowDefault.width, height: 1_800,
                            720, "overview-200-permission-notice")
        }
    }

    // MARK: - ⭐ Two sections in, at 200% text

    /// ⭐ **Mid-check, with the type turned up.** `OverviewSweepShot` has this at 100%; half a
    /// minute is a long time to look at a screen, and the person most likely to be looking at it is
    /// the one who made the text bigger.
    @Test("Overview, mid-check with two sections done, at 200% text")
    func midCheckAtTwoHundredPercent() {
        let app = AppState()
        app.demoMode = false
        app.selection = .overview
        let started = Self.ran
        app.sweep.begin(at: started)

        app.publish(CheckRecord(section: .hardware, ranAt: started, status: .good, complete: true),
                    finding: nil)
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

        atLargestText {
            bothAppearances(screen(app),
                            width: Layout.windowDefault.width, height: PageHeight.atLargestText,
                            722, "overview-200-sweep-running")
        }
    }

    // MARK: - ⭐ The report

    /// ⭐ **The sheet somebody presses Print from**, showing the whole page before any of it leaves
    /// the app.
    ///
    /// ⚠️ Shot at the sheet's own natural size rather than in a frame of my choosing: given a larger
    /// frame it centres a band in the middle of it and the picture stops being of a screen anybody
    /// ever sees.
    @Test("The report sheet, before anything is handed over")
    func theReportSheet() {
        let view = HealthReportSheet(intent: .save) { ReportMac.report(includeSerial: $0) }
            .padding(Space.page)
            .pageGround()
        bothAppearances(view, width: 1_460, height: 1_320, 730, "overview-report-sheet")
    }

    /// ⭐ **The page, as ink on paper, from the identical attributed string the printer is given.**
    ///
    /// `ReportPaper` below draws `HealthReportDocument.attributed(_:)` — the identical value
    /// `HealthReportDocument.page(_:info:)` hands to `NSPrintOperation` — at the paper's own text
    /// width and margins. Nothing about the type here is this file's.
    ///
    /// What to read on it: the caveats sit **above** the findings, all seven audit rows are present
    /// with the ones that never ran saying "Not run", and the serial number is there only because
    /// the switch on the sheet was left on.
    @Test("The report as it prints")
    func theReportAsItPrints() {
        // ⚠️ **Taller than one sheet, on purpose.** The page runs past a single sheet of US Letter —
        // the printer paginates it — and cropping at 792 points would show only the half somebody
        // would think to check.
        let ink = ReportPaper.image(of: ReportMac.report(includeSerial: true),
                                    width: ReportPaperSize.textWidth)
        let paper = VStack(spacing: 0) {
            Image(nsImage: ink)
                .resizable()
                .frame(width: ink.size.width, height: ink.size.height)
                .padding(ReportPaperSize.margin)
                .background(Color.white)
        }
        .padding(Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageGround()

        bothAppearances(paper,
                        width: ReportPaperSize.width + Space.page * 2,
                        height: ink.size.height + ReportPaperSize.margin * 2 + Space.page * 2,
                        732, "overview-report-printed")
    }
}

// MARK: - The Mac on the page

/// A Mac typed out, so a picture of the report can be taken without reading a Mac.
///
/// ⚠️ Built from the real vocabulary rather than from finished sentences, so a picture can never
/// show wording the app is no longer capable of producing. The permission sentence is
/// `FullDiskAccess.shortfall(for:)` — the app's own, quoted — for the same reason.
@MainActor
enum ReportMac {

    private static let writtenOn = Date(timeIntervalSince1970: 1_787_000_000)

    private static let facts = MachineFacts(
        name: "Ada's MacBook Air",
        modelName: "MacBook Air (15-inch, M3, 2024)",
        modelIdentifier: "Mac15,13",
        chip: "Apple M3",
        memory: "16 GB",
        driveSize: "460 GB",
        systemVersion: "macOS 26.1",
        systemMajorVersion: 26,
        inUseSince: Date(timeIntervalSince1970: 1_712_000_000),
        serialNumber: "C02XY1234567")

    /// A page with something of every kind on it: a sweep that ran five of six, one section that
    /// saw part of the Mac, a problem, a permission that was off, and an update question nobody has
    /// answered.
    static func report(includeSerial: Bool) -> HealthReport {
        var records: [SectionID: CheckRecord] = [:]
        for (index, section) in [SectionID.hardware, .backup, .security, .changes].enumerated() {
            records[section] = CheckRecord(section: section,
                                           ranAt: writtenOn.addingTimeInterval(Double(index) * 5),
                                           status: section == .backup ? .needsAttention : .good,
                                           complete: true)
        }
        records[.storage] = CheckRecord(section: .storage,
                                        ranAt: writtenOn.addingTimeInterval(25),
                                        status: .good, complete: false)
        records[.overview] = CheckRecord(section: .overview,
                                         ranAt: writtenOn.addingTimeInterval(31),
                                         status: .needsAttention, complete: false)

        let findings = [
            Finding(section: .backup,
                    title: "No backup has run for 19 days",
                    reason: "The backup drive has not been connected since 9 August.",
                    severity: .problem,
                    measure: "19 days",
                    verb: "Open Backup"),
            Finding(section: .hardware,
                    title: "The battery holds 78% of what it did when new",
                    reason: "Apple's own check still calls it Normal. It will keep getting shorter.",
                    severity: .attention,
                    measure: "78%"),
        ]

        return HealthReport(
            writtenOn: writtenOn,
            machine: facts,
            includeSerial: includeSerial,
            findings: findings,
            records: records,
            permissionsOff: [PermissionShortfall(
                permission: "Full Disk Access",
                sentences: FullDiskAccess.affectedSections
                    .compactMap { FullDiskAccess.shortfall(for: $0) })],
            appUpdateChecking: nil)
    }
}

// MARK: - The paper

/// US Letter with the three-quarter-inch margins `HealthReportDocument` sets on its own
/// `NSPrintInfo`.
private enum ReportPaperSize {
    static let width: CGFloat = 612
    static let margin: CGFloat = 54
    static var textWidth: CGFloat { width - margin * 2 }
}

/// **The printed page itself** — `HealthReportDocument.attributed(_:)` drawn at the paper's own text
/// width.
///
/// ⚠️ It goes into a bitmap rather than onto the screen through an `NSViewRepresentable`, and that
/// is not fussiness: hosted in SwiftUI the text view is handed the proposed height, overflows it,
/// and AppKit anchors the overflow at the **bottom** — so the photograph begins halfway down, with
/// the title and the caveats above the frame. A picture of the wrong half of a page is worse than
/// no picture, because it looks exactly like the page.
@MainActor
private enum ReportPaper {

    static func image(of report: HealthReport, width: CGFloat) -> NSImage {
        let ink = HealthReportDocument.attributed(report)

        // ⚠️ Measured with the same options it is drawn with. Anything else and the last paragraph
        // is clipped by however much the two disagree.
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let measured = ink.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude), options: options)
        let size = NSSize(width: width, height: ceil(measured.height) + 8)

        let image = NSImage(size: size)
        // ⚠️ **Flipped.** Unflipped, AppKit draws from the bottom up and the picture comes out
        // starting partway down the page.
        image.lockFocusFlipped(true)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        ink.draw(with: NSRect(origin: .zero, size: size), options: options)
        image.unlockFocus()
        return image
    }
}
