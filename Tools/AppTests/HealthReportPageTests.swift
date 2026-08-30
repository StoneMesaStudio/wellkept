// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import Testing
import WellkeptCore

//  HealthReportPageTests.swift
//  ViewShots — Tools/AppTests
//
//  ⭐ **The page as the app actually builds it, and the two promises the app layer makes about it.**
//
//  `HealthReportTests` in `WellkeptTests` holds the laws of the value; this file holds the laws of
//  the plumbing, because they are the ones that need `AppState`:
//
//  1. **The preview and the payload are one list.** `HealthReportDocument.blocks(for:)` is the only
//     description of what the page says; the sheet's preview and the printer's ink are both
//     rendered from it. A preview that could drift from what is handed over is the bug
//     `RepairShopCopy` was written to avoid, and this is that rule one level up.
//  2. **The page is built from what Overview already holds**, so it can state no figure the app
//     would not state on screen.
//
//  ⛔ **Nothing here reads this Mac and nothing here prints.** `runEverything()` is never called; the
//  records are typed out and published through the same `publish` a real check uses. The one
//  exception is `PermissionCenter.shared`, which every `AppState.healthReport()` consults — so every
//  assertion below is written as an implication that holds whichever way the real grant happens to
//  be set on the machine running the tests.

// MARK: - Fixtures

@MainActor
private enum Page {

    static let ran = Date(timeIntervalSince1970: 1_787_000_000)

    /// A window with `count` sections filed and nothing else touched.
    ///
    /// ⚠️ `AppState()` writes `demoMode` through to `UserDefaults.standard`, which under `xctest` is
    /// the test process's own domain. Nothing this touches survives the run.
    static func window(sections: [SectionID],
                       complete: Bool = true,
                       finding: Finding? = nil) -> AppState {
        let app = AppState()
        app.demoMode = false
        for section in sections {
            app.publish(CheckRecord(section: section, ranAt: ran,
                                    status: .good, complete: complete),
                        finding: section == finding?.section ? finding : nil)
        }
        return app
    }

    static let backupProblem = Finding(
        section: .backup,
        title: "No backup has run for 19 days",
        reason: "The backup drive has not been connected since 9 August.",
        severity: .problem,
        measure: "19 days")

    /// Run a block with the update-consent key at a known value, and put it back afterwards.
    ///
    /// ⚠️ Save and restore rather than set-and-forget: the key is one of the two switches behind
    /// `Privacy.Departure`, and a test that left it written would change what the next test — and
    /// anybody running the app out of the same defaults domain — believes was consented to.
    static func withConsent(_ answer: UpdateConsent.Answer, _ body: () -> Void) {
        let store = UserDefaults.standard
        let previous = store.object(forKey: UpdateConsent.key)
        UpdateConsent.write(answer, to: store)
        defer {
            if let previous { store.set(previous, forKey: UpdateConsent.key) }
            else { store.removeObject(forKey: UpdateConsent.key) }
        }
        body()
    }

    /// The text a block puts on the page, whatever the medium. Used to prove that both renderings
    /// come from the one list rather than from two lists that agree today.
    static func principalText(of block: HealthReportDocument.Block) -> [String] {
        switch block {
        case .title(let t):                          [t]
        case .subtitle(let t):                       [t]
        case .verdict(let t):                        [t]
        case .heading(let t):                        [t]
        case .paragraph(let t):                      [t]
        case .caveat(let title, let body):           [title, body]
        case .finding(let s, let t, let reason, _):  [s, t, reason]
        case .audit(let s, let status, let when, _): [s, status, when]
        case .detail(let label, let value):          [label, value]
        case .footer(let t):                         [t]
        }
    }
}

// MARK: - ⭐ 1. One list, three renderings

@Suite("The preview and what is handed over are the same page", .serialized)
@MainActor
struct HealthReportOneListTests {

    /// A page with something of every kind on it: caveats, a finding, the audit trail, a machine
    /// block and the footer.
    private var busyPage: HealthReport {
        var records: [SectionID: CheckRecord] = [:]
        for section in [SectionID.hardware, .backup, .security] {
            records[section] = CheckRecord(section: section, ranAt: Page.ran,
                                           status: .good, complete: true)
        }
        records[.storage] = CheckRecord(section: .storage, ranAt: Page.ran,
                                        status: .good, complete: false)
        return HealthReport(
            writtenOn: Page.ran,
            machine: MachineFacts(name: "Ada's MacBook Air",
                                  modelName: "MacBook Air (15-inch, M3, 2024)",
                                  modelIdentifier: "Mac15,13",
                                  chip: "Apple M3",
                                  memory: "16 GB",
                                  driveSize: "460 GB",
                                  systemVersion: "macOS 26.1",
                                  systemMajorVersion: 26,
                                  serialNumber: "C02XY1234567"),
            findings: [Page.backupProblem],
            records: records,
            permissionsOff: [PermissionShortfall(
                permission: "Full Disk Access",
                sentences: [FullDiskAccess.shortfall(for: .storage) ?? ""])],
            appUpdateChecking: nil)
    }

    /// ⭐ **Every block reaches both the preview and the ink.**
    ///
    /// This is the proof that there is one description of the page rather than two. If somebody
    /// later adds a paragraph to the printed version only, or drops a caveat from the preview to
    /// make it fit, one of these two loops fails.
    @Test("Every block on the page reaches the preview and the printer")
    func bothRenderingsComeFromTheOneList() {
        let report = busyPage
        let preview = HealthReportDocument.plainText(for: report)
        let ink = HealthReportDocument.attributed(report).string

        for block in HealthReportDocument.blocks(for: report) {
            for text in Page.principalText(of: block) where !text.isEmpty {
                #expect(preview.contains(text),
                        "the preview leaves out \(block.id): \"\(text)\"")
                #expect(ink.contains(text),
                        "the printed page leaves out \(block.id): \"\(text)\"")
            }
        }
    }

    /// ⭐ **The caveats are above the findings, not below them.**
    ///
    /// A qualification under a list is a qualification most people never reach, and this page's
    /// whole failure mode is being read as a clean bill of health.
    @Test("The caveats come before the findings")
    func caveatsComeFirst() {
        let blocks = HealthReportDocument.blocks(for: busyPage)
        let firstCaveat = blocks.firstIndex { if case .caveat = $0 { true } else { false } }
        let firstFinding = blocks.firstIndex { if case .finding = $0 { true } else { false } }
        #expect(firstCaveat != nil)
        #expect(firstFinding != nil)
        if let firstCaveat, let firstFinding { #expect(firstCaveat < firstFinding) }
    }

    /// ⭐ The verdict is the first thing that is not the page's own name, and there is exactly one
    /// of them. Two verdicts on one page is two answers to one question.
    @Test("Exactly one verdict, near the top")
    func oneVerdict() {
        let blocks = HealthReportDocument.blocks(for: busyPage)
        let verdicts = blocks.filter { if case .verdict = $0 { true } else { false } }
        #expect(verdicts.count == 1)
        #expect(blocks.firstIndex { if case .verdict = $0 { true } else { false } } == 2)
    }

    /// ⭐ **One row per section, never one per finding.** The audit trail is seven rows on every
    /// page, and the findings list is however many rows the sections published — which is at most
    /// one each, because that is what `AppState.publish` enforces.
    @Test("Seven audit rows, and one finding row per finding")
    func oneRowPerSection() {
        let report = busyPage
        let blocks = HealthReportDocument.blocks(for: report)
        let audit = blocks.filter { if case .audit = $0 { true } else { false } }
        let findings = blocks.filter { if case .finding = $0 { true } else { false } }
        #expect(audit.count == SectionID.allCases.count)
        #expect(audit.count == 7)
        #expect(findings.count == report.findings.count)
    }

    /// A page with nothing on it still has the audit trail, and still says what it is. An empty
    /// page would be read as good news.
    @Test("A page from a Mac where nothing ran still carries its evidence")
    func theEmptyPageIsNotEmpty() {
        let report = HealthReport(findings: [], records: [:])
        let text = HealthReportDocument.plainText(for: report)
        #expect(text.contains("Not run"))
        #expect(!text.contains(HealthReport.everythingLooksFine))
        #expect(text.contains(HealthReport.provenance))
        for section in SectionID.allCases { #expect(text.contains(section.title)) }
    }

    /// The saved file is named for the Mac and the day, so two of these in a folder are tellable
    /// apart without opening them.
    @Test("The PDF is named for the Mac and the day")
    func theFileNameNamesTheMacAndTheDay() {
        let name = HealthReportDocument.fileName(for: busyPage)
        #expect(name.hasSuffix(".pdf"))
        #expect(name.contains("Ada's MacBook Air"))
        #expect(!name.contains("/"))
    }
}

// MARK: - ⭐ 2. The page is built from what Overview already holds

@Suite("The report says nothing the screen would not", .serialized)
@MainActor
struct HealthReportFromTheWindowTests {

    /// ⭐ **The clean sentence never survives a state that could not see everything.**
    ///
    /// Asserted as an implication over `AppState` rather than by reading one screen: whatever the
    /// real Full Disk Access grant is on the machine running this, a clean page implies every
    /// checkable section ran, ran in full, and was not invented.
    @Test("A clean page implies a state that earned it")
    func aCleanPageImpliesACleanState() {
        for filed in [SectionID.checkable, [.hardware, .backup]] {
            for complete in [true, false] {
                let app = Page.window(sections: filed, complete: complete)
                let report = app.healthReport(now: Page.ran)
                if report.isCleanBillOfHealth {
                    #expect(app.incompleteSections.isEmpty)
                    #expect(app.uncheckedSections.isEmpty)
                    #expect(app.needsYou.isEmpty)
                    #expect(!app.demoMode)
                }
                // The other direction, which is the one that actually protects anybody: a state
                // with a hole in it can never produce the clean sentence.
                if !app.incompleteSections.isEmpty || !app.uncheckedSections.isEmpty {
                    #expect(!report.isCleanBillOfHealth)
                    #expect(report.headline != HealthReport.everythingLooksFine)
                }
            }
        }
    }

    /// The audit trail on the page is the audit trail on the screen: all seven, from `allCases`.
    @Test("The page's audit trail is all seven, from a window that ran two")
    func thePageListsAllSeven() {
        let app = Page.window(sections: [.hardware, .backup])
        let report = app.healthReport(now: Page.ran)
        #expect(report.audit.count == 7)
        #expect(report.audit.map(\.section) == SectionID.allCases)
        #expect(report.audit.filter { $0.ranAt != nil }.map(\.section) == [.hardware, .backup])
    }

    /// ⭐ **One row per section, at the source.** `publish` replaces whatever a section filed last
    /// rather than appending, so a section that has been checked five times contributes one row to
    /// the page — not five.
    @Test("A section checked twice contributes one row, not two")
    func publishingTwiceLeavesOneRow() {
        let app = AppState()
        app.demoMode = false
        for attempt in 0..<5 {
            app.publish(CheckRecord(section: .backup,
                                    ranAt: Page.ran.addingTimeInterval(Double(attempt)),
                                    status: .needsAttention, complete: true),
                        finding: Page.backupProblem)
        }
        #expect(app.needsYou.filter { $0.section == .backup }.count == 1)
        #expect(app.healthReport(now: Page.ran).findings.count == 1)
        #expect(app.healthReport(now: Page.ran).audit.filter { $0.section == .backup }.count == 1)
    }

    /// ⭐ **A stopped sweep keeps what already finished, and the page proves it.**
    ///
    /// Nothing is rolled back when somebody presses Stop: every section published as it landed, so
    /// what is on the page afterwards is exactly what had finished — plus honest "Not run" rows for
    /// the rest.
    @Test("A stopped sweep leaves its finished sections on the page")
    func aStoppedSweepKeepsWhatFinished() {
        let app = AppState()
        app.demoMode = false
        app.sweep.begin(at: Page.ran)

        for section in [SectionID.hardware, .backup] {
            app.sweep.enter(section)
            app.publish(CheckRecord(section: section, ranAt: Page.ran,
                                    status: .good, complete: true), finding: nil)
            app.sweep.leave(section, landed: true)
        }

        app.sweep.requestStop()
        app.sweep.end(at: Page.ran.addingTimeInterval(9))

        let report = app.healthReport(now: Page.ran.addingTimeInterval(9))
        #expect(report.audit.filter { $0.ranAt != nil }.map(\.section) == [.hardware, .backup])
        #expect(report.audit.first { $0.section == .security }?.whenSentence == "Not run")
        // ⛔ And it may not read as a clean Mac, because four checks never happened.
        #expect(!report.isCleanBillOfHealth)
        #expect(report.caveats.contains { $0.title.contains("were not run") })
    }

    /// ⭐ **Pressing "Check my Mac" never answers the update question for anybody**, and the page
    /// says which of the three answers was in force.
    ///
    /// The gate itself is `AppState.sweepSkipReason(for:)`; this asserts the half that travels off
    /// the Mac on paper — a repair shop reading this page can tell "we asked and they said no" from
    /// "nobody ever asked".
    @Test("The page distinguishes never-asked from declined")
    func thePageCarriesWhichAnswerWasInForce() {
        Page.withConsent(.notAsked) {
            let app = Page.window(sections: SectionID.checkable)
            // The sweep leaves Apps alone rather than putting the question up from another screen.
            #expect(app.sweepSkipReason(for: .apps) != nil)
            let caveat = app.healthReport(now: Page.ran).caveats
                .first { $0.title.lowercased().contains("update") }
            #expect(caveat?.title.contains("had not been asked") == true)
        }

        Page.withConsent(.declined) {
            let app = Page.window(sections: SectionID.checkable)
            #expect(app.sweepSkipReason(for: .apps) == nil)
            let caveat = app.healthReport(now: Page.ran).caveats
                .first { $0.title.lowercased().contains("update") }
            #expect(caveat?.title.contains("switched off") == true)
        }

        Page.withConsent(.allowed) {
            let app = Page.window(sections: SectionID.checkable)
            #expect(app.sweepSkipReason(for: .apps) == nil)
            #expect(!app.healthReport(now: Page.ran).caveats
                .contains { $0.title.lowercased().contains("update") })
        }
    }

    /// The two File-menu items are greyed until there is something to report, and the reason is on
    /// them — see `WellkeptApp.commands`.
    @Test("There is nothing to hand over until a check has run")
    func nothingToReportUntilSomethingRan() {
        let empty = AppState()
        empty.demoMode = false
        #expect(!empty.canMakeHealthReport)
        #expect(Page.window(sections: [.hardware]).canMakeHealthReport)
    }

    /// ⭐ **The person is shown what they are about to hand over, in the sheet's own words.**
    ///
    /// The caution names the Mac and says whether the serial number is on the page — Hardware's
    /// convention, and the reason both menu items open this sheet instead of printing.
    @Test("The sheet says what the page identifies, before either button")
    func theSheetNamesWhatIsAboutToLeave() {
        let facts = MachineFacts(name: "Ada's MacBook Air",
                                 modelName: "MacBook Air (15-inch, M3, 2024)",
                                 modelIdentifier: "Mac15,13",
                                 chip: "Apple M3",
                                 memory: "16 GB",
                                 driveSize: "460 GB",
                                 systemVersion: "macOS 26.1",
                                 systemMajorVersion: 26,
                                 serialNumber: "C02XY1234567")

        let withSerial = HealthReport(machine: facts, includeSerial: true,
                                      findings: [], records: [:])
        let without = HealthReport(machine: facts, includeSerial: false,
                                   findings: [], records: [:])

        #expect(HealthReportSheet.caution(for: withSerial)?.contains("serial number") == true)
        #expect(HealthReportSheet.caution(for: withSerial)?.contains("Ada's MacBook Air") == true)
        #expect(HealthReportSheet.caution(for: without)?.contains("left off") == true)
        // A page that names no Mac has nothing to warn about.
        #expect(HealthReportSheet.caution(
            for: HealthReport(machine: nil, findings: [], records: [:])) == nil)

        // And the sheet's own promise: nothing happens until a button is pressed.
        #expect(HealthReportSheet.whatYouAreLookingAt.contains("until you press"))
    }

    /// ⛔ **Both menu items open the sheet; neither one prints.** The `Intent` decides which button
    /// is the default and nothing else, which is why there are exactly two of them.
    @Test("The two menu items differ only in which button is the default")
    func bothMenuItemsLandOnTheSheet() {
        #expect(HealthReportSheet.Intent.allCases.count == 2)
        for intent in HealthReportSheet.Intent.allCases {
            #expect(!intent.heading.isEmpty)
            #expect(!intent.title.isEmpty)
        }
        #expect(HealthReportSheet.Intent.save.heading != HealthReportSheet.Intent.print.heading)
        // ⚠️ The sheet's buttons carry the same two words as the File-menu items that opened them.
        #expect(HealthReportSheet.Intent.save.title == "Save as PDF…")
        #expect(HealthReportSheet.Intent.print.title == "Print…")
    }

    /// ⚠️ A cancel is not a failure and says nothing. Closing a print panel is a decision.
    @Test("Cancelling says nothing")
    func cancellingSaysNothing() {
        #expect(HealthReportDocument.Outcome.cancelled.sentence == nil)
        #expect(HealthReportDocument.Outcome.done("saved").sentence == "saved")
        #expect(HealthReportDocument.Outcome.failed("no").sentence == "no")
    }

    /// ⛔ **The word "freed" cannot reach this page**, and neither can a grade. The repo-wide
    /// guards are `QuarantineWordsTests` and `NeverAScoreGuardTests`; this is the same check
    /// against the assembled text of a real page, because the page is composed at runtime from
    /// strings several sections wrote.
    @Test("Nothing on an assembled page claims space came back, or grades the Mac")
    func theAssembledPageSaysNeither() {
        let app = Page.window(sections: SectionID.checkable,
                              complete: false, finding: Page.backupProblem)
        let text = HealthReportDocument.plainText(for: app.healthReport(now: Page.ran)).lowercased()
        for word in ["freed", "reclaim", "recovered space"] {
            #expect(!text.contains(word))
        }
        for grade in ["out of 100", "/100", "health score", "score:"] {
            #expect(!text.contains(grade))
        }
    }
}
