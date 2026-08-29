import Foundation
import Testing
import WellkeptCore

//  SecuritySectionTests.swift
//  Wellkept — Tools/AppTests
//
//  **The Security screen's own contracts: the two demo Macs, the in-flight stages, and the two
//  sentences this section is not allowed to say.**
//
//  These live in `Tools/AppTests` because it is the only bundle that compiles `App` — `DemoData`,
//  `SecurityModel` and `FullDiskAccess` are all app-target types, and `WellkeptTests` links only
//  `WellkeptCore`.
//
//  ## What is worth testing here, and what is not
//
//  The readers have their own suites and they test the reading. Nothing here reads this Mac. What
//  is tested here is what the *screen* promises, which is a different set of claims and all of them
//  are about words:
//
//  - **"Good" never stands alone.** A clean answer carries what was looked at and how far back.
//  - **The word "safe" never appears as a verdict.** Wellkept looks when you press the button and
//    does not watch, and a word implying live protection is a promise it cannot keep.
//  - **Nothing here is ever red**, however bad the Mac.
//  - **One row reaches Overview**, never one per finding.
//  - **The demo exercises the five paths nobody will otherwise see**, because unless they are
//    invented they never get looked at at all.

@Suite("Security — the section screen and its two demo Macs")
@MainActor
struct SecuritySectionTests {

    // MARK: - Every sentence the section is capable of showing

    /// Everything a person could read on the screen for one demo Mac, flattened.
    ///
    /// Deliberately includes the details behind Options and the words of every concern: a promise
    /// about wording that only holds above the fold is not a promise.
    private func words(_ answer: SecurityAnswer) -> [String] {
        var out = [answer.report.summary, answer.report.windowClause]
        for row in answer.report.rows {
            out.append(row.headline)
            out.append(row.topic.label)
            out.append(row.topic.explanation)
            if let measure = row.measure { out.append(measure) }
            if let reason = row.reason { out.append(reason) }
            if let remedy = row.remedy { out.append(remedy.title) }
            for pair in row.details { out.append(pair.label); out.append(pair.value) }
            for concern in row.concerns {
                out.append(concern.title)
                out.append(concern.explanation)
            }
        }
        for pair in answer.report.block.detailPairs { out.append(pair.label); out.append(pair.value) }
        for grant in answer.grants { out.append(grant.appName); out.append(grant.bundleID) }
        if let finding = answer.report.overviewFinding {
            out.append(finding.title)
            out.append(finding.reason)
        }
        return out
    }

    private var bothMacs: [SecurityAnswer] {
        [DemoData.security(.healthy), DemoData.security(.problems)]
    }

    // MARK: - The two sentences this section may not say

    /// ⚠️ **"Safe" is not a verdict this app is entitled to.** Wellkept reads when the button is
    /// pressed, and the one part of Wellkept that keeps running backs up and nothing else — it
    /// watches no protection and reads no security setting. So any wording that implies live
    /// protection is a
    /// promise it cannot keep — and somebody would reasonably rely on it.
    ///
    /// The section's *question* is still "Am I safe?", which is the thing a person is asking. It is
    /// the answer that may never use the word.
    @Test("The word safe never appears in anything the section says")
    func theWordSafeIsNeverAVerdict() {
        for answer in bothMacs {
            for sentence in words(answer) {
                #expect(!sentence.lowercased().contains("safe"),
                        Comment(rawValue: "Security said “safe”: \(sentence)"))
            }
        }
    }

    /// **Good never stands alone.** John's rule, 2026-08-27: the clean sentence carries its scope
    /// and its window, because "everything is fine" is worth exactly as much as the list of what
    /// was actually looked at.
    @Test("A clean answer carries what was looked at and how far back")
    func goodNeverStandsAlone() {
        let healthy = DemoData.security(.healthy)
        #expect(healthy.report.status == .good)
        #expect(healthy.report.concerns.isEmpty)

        let summary = healthy.report.summary
        #expect(summary.contains("protections we can see"))
        // The window, measured on the run rather than assumed. If this ever reads "in the records
        // it still keeps", `measuredDays` stopped travelling out of the log reader.
        #expect(summary.contains(healthy.report.windowClause))
        #expect(healthy.report.measuredDays == 12)
        #expect(summary.contains("12 days"))
    }

    /// ⚠️ **The number nobody measured.** There is no fallback fourteen anywhere in this section:
    /// the window comes from what the log store actually reached back to, and `nil` is a real
    /// answer with its own honest sentence.
    @Test("An unmeasured window says so rather than printing a number")
    func anUnmeasuredWindowIsNeverInvented() {
        let report = SecurityReport(block: .unknown, rows: [], measuredDays: nil)
        #expect(!report.windowClause.contains("14"))
        #expect(report.windowClause.contains("do not say how far back"))
    }

    // MARK: - Nothing here is red

    /// All nine of this section's conditions are `.attention`. The unwell demo Mac is the most
    /// alarming screen this section can draw, and even it may not reach `.problem`.
    @Test("Nothing in Security is a problem, however bad the Mac")
    func securityIsNeverRed() {
        for answer in bothMacs {
            for row in answer.report.rows {
                #expect(row.severity != .problem,
                        Comment(rawValue: "\(row.topic.label) went red"))
            }
            if let finding = answer.report.overviewFinding {
                #expect(finding.severity != .problem)
            }
        }
    }

    // MARK: - The healthy Mac

    /// Six rows, every one of them read, and nothing asking anything of anybody. This is the case
    /// the product exists to be able to show.
    @Test("The healthy demo Mac has all six rows and nothing wrong")
    func theHealthyMacIsClean() {
        let answer = DemoData.security(.healthy)
        #expect(answer.report.rows.count == SecurityTopic.allCases.count)
        #expect(answer.report.rows.map(\.topic) == SecurityTopic.allCases)
        #expect(answer.report.status == .good)
        #expect(answer.report.complete)
        // Nothing goes to Overview from a clean section. A row saying "all clear" on the summary is
        // how the summary becomes a list of things that are fine.
        #expect(answer.report.overviewFinding == nil)
    }

    /// ⚠️ **A working Mac's permission list is not a list of faults.** Six apps hold permissions on
    /// the healthy demo Mac and the row is still Good — if this ever fails, something started
    /// treating "holds the camera" as a finding.
    @Test("Holding a permission is not by itself a finding")
    func aWorkingMacsPermissionListIsStillGood() {
        let answer = DemoData.security(.healthy)
        #expect(!answer.grants.isEmpty)
        let row = answer.report.row(.whoCanWatch)
        #expect(row?.status == .good)
        #expect(row?.concerns.isEmpty == true)
    }

    /// Wellkept holds Full Disk Access, so Wellkept is in its own list. John's call, 2026-08-27:
    /// say so rather than filter ourselves out.
    @Test("Wellkept appears in its own permission list")
    func wellkeptIsInItsOwnList() {
        for answer in bothMacs {
            #expect(answer.grants.contains { $0.isWellkept },
                    "Wellkept filtered itself out of the list of apps that can read your disk")
        }
    }

    // MARK: - The Mac with problems

    /// **The five paths nobody will otherwise see.** Nobody is going to turn their own disk
    /// encryption off to look at a screen, so unless the demo exercises these they never get looked
    /// at at all.
    @Test("The unwell demo Mac exercises all five of the paths it exists for")
    func theUnwellMacExercisesTheHardPaths() {
        let answer = DemoData.security(.problems)
        let raised = Set(answer.report.concerns)

        #expect(raised.contains(.fileVaultOff))
        #expect(raised.contains(.firewallOff))
        #expect(raised.contains(.permissionHeldByMissingApp))
        #expect(raised.contains(.signatureChangedSinceApproved))

        // The fifth is not a concern at all — macOS dealt with it before Wellkept looked — so it is
        // checked in the row's own words.
        let found = answer.report.row(.macOSFindings)
        #expect(found?.headline.contains("dealt with") == true,
                "the unwell Mac lost its XProtect Remediator finding")
        #expect(found?.status == .good,
                "something macOS already removed is not a thing that needs the person")
    }

    /// The FileVault row carries the recovery-key sentence on the row itself, never behind Options.
    ///
    /// ⚠️ It is the single piece of advice in this app that can cost somebody every file they own —
    /// turn encryption on, lose the key, lose the lot — so it says what the key is for and stops.
    /// It never says "you should".
    @Test("FileVault off carries the recovery-key sentence, and no imperative")
    func fileVaultOffSaysWhatARecoveryKeyIsFor() {
        let answer = DemoData.security(.problems)
        let row = answer.report.row(.protections)
        #expect(row?.reason?.contains("recovery key") == true)
        for sentence in words(answer) {
            #expect(!sentence.lowercased().contains("you should"),
                    Comment(rawValue: "Security told somebody what they should do: \(sentence)"))
        }
    }

    /// ⚠️ **A Mac with things worth a look is not a Mac we failed to read.** Every row on the
    /// unwell demo Mac was read, so the check reports itself complete — otherwise Overview would
    /// carry a caveat about a partial look that nothing on the screen explains.
    @Test("Findings do not make the check incomplete")
    func theUnwellMacStillSawEverything() {
        #expect(DemoData.security(.problems).report.complete)
    }

    /// One row up to Overview, never one per finding. Five concerns on the unwell Mac; one row.
    @Test("However much is wrong, Security sends Overview exactly one row")
    func onlyOneRowReachesOverview() {
        let answer = DemoData.security(.problems)
        #expect(answer.report.concerns.count > 1)
        #expect(answer.report.overviewFinding != nil)

        let fromSecurity = DemoData.findings(.problems).filter { $0.section == .security }
        #expect(fromSecurity.count == 1)
    }

    /// ⚠️ Built once and cached. `SecurityReport.overviewFinding` mints a fresh `UUID`, and a
    /// `Finding` whose identity changes on every draw is how a list animates itself to pieces.
    @Test("The demo answer keeps its identity between draws")
    func theDemoAnswerIsStable() {
        let first = DemoData.security(.problems).report.overviewFinding
        let second = DemoData.security(.problems).report.overviewFinding
        #expect(first?.id == second?.id)
    }

    /// The chip on the sidebar's audit trail and the chip on the Security screen are one fact.
    @Test("The demo audit trail takes Security's line from the report itself")
    func theAuditTrailAgreesWithTheScreen() {
        for machine in DemoMachine.allCases {
            let answer = DemoData.security(machine)
            let record = DemoData.records(machine)[.security]
            #expect(record == answer.report.record)
        }
    }

    // MARK: - The permission list

    /// Every grant appears under exactly one heading, and no heading is drawn with nothing under
    /// it. A list of empty headings is a list of things a person thinks are missing.
    @Test("The permission list groups every grant exactly once and shows no empty headings")
    func thePermissionListIsWholeAndHasNoEmptyGroups() {
        for answer in bothMacs {
            var counted = 0
            for permission in answer.permissionsHeld {
                let group = answer.grants(for: permission)
                #expect(!group.isEmpty,
                        Comment(rawValue: "\(permission.label) was drawn with nothing under it"))
                counted += group.count
            }
            #expect(counted == answer.grants.count)
        }
    }

    // MARK: - The in-flight state

    /// ⚠️ **One stage per row, in the same order.** The placeholder rows during a run are matched
    /// to the stage by topic, so a stage without a row — or a row without a stage — leaves a
    /// placeholder that never resolves or a spinner beside nothing.
    @Test("Every row has a reading stage, and they run in the section's own order")
    func theStagesMatchTheRows() {
        #expect(SecurityModel.Stage.allCases.map(\.topic) == SecurityTopic.allCases)
        #expect(SecurityModel.Stage.count == SecurityTopic.allCases.count)
        for stage in SecurityModel.Stage.allCases {
            #expect(!stage.sentence.isEmpty)
            #expect(stage.step >= 1 && stage.step <= SecurityModel.Stage.count)
        }
    }

    /// Nothing has been checked until somebody presses the button. Security has no launch check at
    /// all — its log read is the slowest thing in the app — so this is the state on every launch.
    @Test("A fresh model has read nothing and is not running")
    func aFreshModelHasReadNothing() {
        let model = SecurityModel()
        #expect(model.answer == nil)
        #expect(!model.isChecking)
        #expect(model.stage == nil)
        #expect(model.arrived.isEmpty)
        #expect(model.arrivedBlock == nil)
    }

    // MARK: - Setup asks for the right reason

    /// ⚠️ **The correction of 2026-08-27.** Setup used to sell Full Disk Access on storage. Without
    /// it, eleven of the twelve permissions read exactly zero — so the camera, microphone and screen
    /// screen is *empty*, not short, and that is the strongest true reason to grant it.
    @Test("The Full Disk Access ask leads with the camera, microphone and screen")
    func setupLeadsWithWhatIsActuallyLost() {
        let purpose = FullDiskAccess.purpose.lowercased()
        guard let camera = purpose.range(of: "camera") else {
            Issue.record("the Full Disk Access ask no longer mentions the camera at all")
            return
        }
        guard let storage = purpose.range(of: "storage") else {
            Issue.record("the Full Disk Access ask no longer mentions storage at all")
            return
        }
        #expect(camera.lowerBound < storage.lowerBound,
                "storage is being sold ahead of the thing that is actually empty without the grant")
        #expect(purpose.contains("microphone"))
        #expect(purpose.contains("screen"))
    }

    /// Security's own line says the list is empty rather than short. "Some of it is missing" invites
    /// somebody to read the near-empty list as the answer.
    @Test("Security's shortfall line says empty, not short")
    func theSecurityShortfallSaysEmpty() {
        let line = FullDiskAccess.shortfall(for: .security)
        #expect(line?.contains("empty") == true)
        // Hardware needs nothing, and saying otherwise on its face would be a warning about
        // something untrue.
        #expect(FullDiskAccess.shortfall(for: .hardware) == nil)
    }

    // MARK: - The grant that has not taken effect yet

    /// ⚠️ **The dead end, and the measurement that makes it honest.**
    ///
    /// A grant given to an app that is already running does not reach it; macOS offers "Quit &
    /// Reopen" and somebody who declines is left with an app insisting it was not allowed. The
    /// detection is the privacy store's own modification date, which reads with **no permission at
    /// all** — measured on this Mac, 2026-08-27: `stat` succeeds where `open` is refused.
    ///
    /// If this ever returns `nil`, the store moved and the reopen offer has quietly stopped
    /// appearing for anybody who granted the permission after tapping "Finish later".
    @Test("The privacy list's date reads without any permission")
    func thePrivacyListDateIsReadableUnprivileged() {
        #expect(FullDiskAccess.privacyListLastChanged() != nil,
                Comment(rawValue: "the privacy store's modification date could not be read — the "
                                + "reopen offer has lost its evidence"))
    }

    /// The offer can never appear on a Mac where the grant is already working, whatever else is
    /// true. An app that asks to restart when restarting would change nothing is an app that
    /// teaches people to ignore it.
    @Test("The reopen offer needs both a reason and an actual refusal")
    func theReopenOfferNeedsARealRefusal() {
        let center = PermissionCenter.shared
        if center.fullDiskAccessGranted {
            #expect(!center.needsReopenToSee)
        }
        // Both wordings exist and neither asks the person whether they really did it.
        #expect(!center.reopenSentence.isEmpty)
        #expect(!center.reopenSentence.contains("?"))
    }
}
