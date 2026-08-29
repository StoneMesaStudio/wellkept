// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  BackupTests.swift
//  WellkeptTests
//
//  **What the Backup vocabulary has to be true for.**
//
//  Two of these suites are not about values at all. They are about the two mistakes that have
//  already been made out loud:
//
//  1. Reading a Mac with automatic backups switched off and calling it **failing**. That happened
//     in front of the owner on 2026-08-28.
//  2. Counting a file that also lives in iCloud as a **backup gap**. That has not happened yet, and
//     on this Mac it would open the section with a 72 GB alarm about an arrangement that works.
//
//  ⛔ Nothing here touches a drive, a volume, or Time Machine.

// MARK: - ⭐ 1. Switched off is not failing

/// **The precedence in `TimeMachineState.standing`, walked case by case.**
///
/// The order of those tests is the type's whole reason for existing, and it is the kind of thing a
/// later reader "tidies" into a more natural-looking order. Every one of these fails loudly if they
/// do.
@Suite("Switched off is not failing")
struct TimeMachinePrecedenceTests {

    /// This Mac, exactly as measured on 2026-08-29: `AutoBackup = 0`, destination configured,
    /// drive unplugged, last success 25 August, and errors in the log because nothing is running.
    private func thisMac(now: Date) -> TimeMachineState {
        TimeMachineState(
            isConfigured: true,
            automaticBackupsOn: false,
            destination: BackupDestination(name: "JDS Backup", kind: .localDrive, isConnected: false),
            lastSuccess: now.addingTimeInterval(-4 * 86_400),
            failure: TimeMachineFailure(code: 45, message: "Backup failed with error 45", cause: .driveNotConnected))
    }

    @Test("The owner's Mac reads as switched off, not as failing")
    func theRealMacReadsCorrectly() {
        let now = Date()
        let state = thisMac(now: now)
        #expect(state.standing(now: now) == .switchedOff)
        #expect(state.standing(now: now) != .failing)
        #expect(state.standing(now: now).isAMalfunction == false)
    }

    @Test("Switched off outranks a failure, whatever the log says")
    func offBeatsFailure() {
        let now = Date()
        let state = TimeMachineState(
            isConfigured: true,
            automaticBackupsOn: false,
            destination: BackupDestination(name: "Backup", kind: .localDrive, isConnected: true),
            lastSuccess: now.addingTimeInterval(-2 * 86_400),
            failure: TimeMachineFailure(code: 19, cause: .destinationDamaged))
        #expect(state.standing(now: now) == .switchedOff,
                "a Mac with backups switched off accumulates errors as a matter of course — off explains the errors, not the other way round")
    }

    @Test("An unplugged drive is waiting, not failing")
    func unpluggedIsWaiting() {
        let now = Date()
        let state = TimeMachineState(
            isConfigured: true,
            automaticBackupsOn: true,
            destination: BackupDestination(name: "Backup", kind: .localDrive, isConnected: false),
            lastSuccess: now.addingTimeInterval(-3 * 86_400),
            failure: TimeMachineFailure(code: 45, cause: .driveNotConnected))
        #expect(state.standing(now: now) == .waitingForTheDrive)
    }

    @Test("On, connected and failing is the one standing that is a malfunction")
    func failingIsFailing() {
        let now = Date()
        let state = TimeMachineState(
            isConfigured: true,
            automaticBackupsOn: true,
            destination: BackupDestination(name: "Backup", kind: .localDrive, isConnected: true),
            lastSuccess: now.addingTimeInterval(-2 * 86_400),
            failure: TimeMachineFailure(code: 19, cause: .destinationDamaged))
        #expect(state.standing(now: now) == .failing)
        #expect(state.standing(now: now).isAMalfunction)
        #expect(TimeMachineStanding.allCases.filter(\.isAMalfunction) == [.failing])
    }

    @Test("Nothing configured is an absence, and it says we can only see Time Machine")
    func neverSetUpIsNotAFault() {
        let now = Date()
        let state = TimeMachineState(isConfigured: false, automaticBackupsOn: false)
        #expect(state.standing(now: now) == .neverSetUp)
        #expect(state.severity(now: now) == .attention,
                "somebody using Backblaze or Carbon Copy Cloner has a backup we cannot see — calling their Mac unprotected asserts something we did not measure")
        #expect(state.headline(now: now).contains("Wellkept cannot see it"))
    }

    @Test("Switched off is the problem this section exists to find")
    func switchedOffIsAProblem() {
        let now = Date()
        #expect(thisMac(now: now).severity(now: now) == .problem)
        #expect(thisMac(now: now).reason(now: now)?.contains("Nothing is broken") == true)
    }

    @Test("A state we could not read claims nothing else")
    func unreadableClaimsNothing() {
        let state = TimeMachineState.couldNotRead(.notPermitted)
        #expect(state.standing() == .notReadable)
        #expect(state.isConfigured == false)
        #expect(state.destination == nil)
        #expect(state.lastSuccess == nil)
        #expect(state.severity() == .information, "not knowing is never a fault")
        #expect(state.status() == .notChecked)
    }

    @Test("A drive that is never plugged in stops being ordinary")
    func aDriveInADrawerForeverIsAProblem() {
        let now = Date()
        func waiting(daysAgo: Int) -> TimeMachineState {
            TimeMachineState(isConfigured: true,
                             automaticBackupsOn: true,
                             destination: BackupDestination(name: "Backup", kind: .localDrive, isConnected: false),
                             lastSuccess: now.addingTimeInterval(-Double(daysAgo) * 86_400))
        }
        #expect(waiting(daysAgo: 3).severity(now: now) == .attention)
        #expect(waiting(daysAgo: 120).severity(now: now) == .problem)
    }

    @Test("Nothing in the app ever switches Time Machine on")
    func theButtonOnlyOpensSettings() {
        let now = Date()
        let state = TimeMachineState(isConfigured: true, automaticBackupsOn: false)
        #expect(state.remedy(now: now)?.settingsPane == "timeMachine")
        #expect(state.remedy(now: now)?.title == "Open Time Machine settings")
    }
}

// MARK: - Freshness

@Suite("Nine days is the line, and it is the owner's number")
struct FreshnessTests {

    @Test func nineDaysIsStale() {
        let now = Date()
        #expect(BackupFreshness.staleAfterDays == 9)
        #expect(BackupFreshness.of(now.addingTimeInterval(-8 * 86_400), now: now) == .recent)
        #expect(BackupFreshness.of(now.addingTimeInterval(-9 * 86_400), now: now) == .stale)
        #expect(BackupFreshness.of(now.addingTimeInterval(-3600), now: now) == .today)
        #expect(BackupFreshness.of(nil, now: now) == .never)
    }

    @Test func aClockThatWentBackwardsDoesNotProduceANegativeAge() {
        let now = Date()
        #expect(BackupFreshness.days(from: now.addingTimeInterval(86_400), to: now) == 0)
        #expect(BackupFreshness.phrase(for: now.addingTimeInterval(86_400), now: now) == "today")
    }

    @Test func theWordsAreEnglish() {
        let now = Date()
        #expect(BackupFreshness.phrase(for: nil, now: now) == "never")
        #expect(BackupFreshness.phrase(for: now.addingTimeInterval(-1.5 * 86_400), now: now) == "yesterday")
        #expect(BackupFreshness.phrase(for: now.addingTimeInterval(-4 * 86_400), now: now) == "4 days ago")
    }
}

// MARK: - ⚠️ The noise filter

/// **Filtering in the safe direction, proved both ways.**
@Suite("Teardown noise is dropped, and nothing else is")
struct LogNoiseTests {

    @Test("The measured teardown lines are recognised")
    func noiseIsNoise() {
        #expect(LogNoise.isTeardownNoise("XPC error: connection invalid"))
        #expect(LogNoise.isTeardownNoise("The connection to service was invalidated"))
        #expect(LogNoise.isTeardownNoise("Error Domain=NSCocoaErrorDomain Code=4097"))
    }

    @Test("⚠️ A message we do not recognise is KEPT")
    func unknownMessagesSurvive() {
        let unknown = "Backup destination is out of space and cannot be thinned any further"
        #expect(LogNoise.isTeardownNoise(unknown) == false)
        #expect(LogNoise.realErrors(in: [unknown]) == [unknown],
                "a denylist that grows quietly is how a health tool learns to say nothing")
    }

    @Test("A long message that merely mentions XPC is not noise")
    func aRealMessageThatMentionsXPCSurvives() {
        let real = "The backup disk image could not be mounted because the volume is damaged; "
            + "the helper reported an XPC error while reporting it, and the backup did not run at all today"
        #expect(LogNoise.isTeardownNoise(real) == false)
    }

    @Test("Duplicates collapse, order is kept")
    func realErrorsAreTidy() {
        let messages = ["connection invalid", "Disk full", "Disk full", "XPC error", "Repair needed"]
        #expect(LogNoise.realErrors(in: messages) == ["Disk full", "Repair needed"])
    }

    @Test("⭐ Noise alone can never become a failure")
    func noiseCannotBuildAFailure() {
        #expect(TimeMachineFailure(message: "XPC error: connection invalid") == nil)
        #expect(TimeMachineFailure(code: 0, message: "connection interrupted", cause: .unknown) == nil)
        #expect(TimeMachineFailure(code: 45, message: "connection invalid") != nil,
                "a result code is evidence on its own")
        #expect(TimeMachineFailure(cause: .driveFull) != nil,
                "a cause established from something other than the log is evidence too")
        #expect(TimeMachineFailure(message: "The backup disk is full") != nil)
    }
}

// MARK: - ⭐ 2. Only what lives on this Mac alone can be a gap

/// **Every combination of where a thing lives and whether it is in the backup.**
///
/// Four residences × three inclusions is twelve states, small enough to enumerate and far too
/// important to spot-check. Exactly three of them are gaps, and they are all the same residence.
@Suite("A file that also lives in iCloud is not a backup gap")
struct CoverageLawTests {

    private func coverage(_ lives: WhereItLives, _ included: Included) -> Coverage {
        Coverage(name: "Something", lives: lives, included: included, why: "Because.")
    }

    @Test("⭐ Only .onlyOnThisMac can ever be a gap")
    func onlyOneResidenceCanBeAGap() {
        #expect(WhereItLives.allCases.filter(\.canBeAGap) == [.onlyOnThisMac])
    }

    @Test("Every one of the twelve states, and only three are gaps")
    func theWholeStateSpace() {
        var gaps: [String] = []
        let inclusions: [Included] = [.yes, .no, .notKnown(.notPermitted)]
        for lives in WhereItLives.allCases {
            for included in inclusions {
                let c = coverage(lives, included)
                if c.isGap { gaps.append("\(lives.rawValue)/\(included.label)") }
            }
        }
        #expect(gaps == ["onlyOnThisMac/Not in the backup"],
                "these were counted as backup gaps and should not have been: \(gaps)")
    }

    @Test("72.2 GB of cloud-only files are not a gap")
    func theCloudHoleIsNotAnAlarm() {
        let c = Coverage(name: "Documents/Media",
                         lives: .onlyInTheCloud,
                         included: .no,
                         why: "It is not on this disk to copy.",
                         bytes: SizeOnDisk(72_200_000_000))
        #expect(c.isGap == false)
        #expect(c.lives.whyItIsNotAGap != nil)
    }

    @Test("Something we could not check is unknown, not missing")
    func unknownIsNotAGap() {
        let c = coverage(.onlyOnThisMac, .notKnown(.notPermitted))
        #expect(c.isGap == false, "guessing in either direction is how a backup tool lies or cries wolf")
        #expect(c.isUnknown)
    }
}

// MARK: - ⚠️ The silent refusal

@Suite("A backup made without Full Disk Access is not complete")
struct CompletenessTests {

    @Test("⭐ Without the grant, it cannot be called complete")
    func noGrantNoCompleteness() {
        let c = BackupCompleteness(fullDiskAccessHeld: false)
        #expect(c.mayBeCalledComplete == false)
        #expect(c.headline == "This is not a complete backup.")
        #expect(c.missingSentences.first?.contains("without any error") == true)
        #expect(c.remedy?.settingsPane == "fullDiskAccess")
    }

    @Test("The six things that go missing are named")
    func theSixAreNamed() {
        #expect(ProtectedPlace.allCases.count == 6)
        let sentence = BackupCompleteness(fullDiskAccessHeld: false).missingSentences.first ?? ""
        for place in ProtectedPlace.allCases {
            let bare = place.label.replacingOccurrences(of: "Your ", with: "")
            #expect(sentence.contains(bare), "\(bare) is not named in the sentence about what is missing")
        }
    }

    @Test("Cloud-only files are named and skipped, and do not make a run incomplete")
    func cloudSkipsAreNotFailures() {
        let c = BackupCompleteness(fullDiskAccessHeld: true,
                                   cloudOnlySkipped: 15_593,
                                   cloudOnlyApparent: SizeOnDisk(72_200_000_000))
        #expect(c.mayBeCalledComplete)
        #expect(c.missingSentences.contains { $0.contains("15,593") })
        #expect(NotCopied.inTheCloudOnly.countsAgainstCompleteness == false)
        #expect(NotCopied.refusedSilently.countsAgainstCompleteness)
        #expect(NotCopied.failed.countsAgainstCompleteness)
    }
}

// MARK: - Rows and the report

@Suite("The four rows, and what a row is allowed to say")
struct BackupRowTests {

    @Test("The order is fixed and exactly one row is gated")
    func theRowOrder() {
        #expect(BackupTopic.allCases == [.appleBackup, .notCovered, .wellkeptBackup, .recoveryPlan])
        #expect(BackupTopic.allCases.filter(\.needsRehearsal) == [.wellkeptBackup])
        #expect(BackupTopic.appleBackup.label == "Time Machine",
                "the row is named what it is called on the person's own Mac")
    }

    @Test("A row about where files live cannot be a problem")
    func notCoveredIsClamped() {
        let noGaps = BackupRow(topic: .notCovered,
                               headline: "Everything on this Mac is covered.",
                               severity: .problem,
                               coverage: [Coverage(name: "Media", lives: .onlyInTheCloud,
                                                   included: .no, why: "Not on the disk.")])
        #expect(noGaps.severity == .information,
                "a row whose only findings are where files live is describing an arrangement, not a fault")

        let withGap = BackupRow(topic: .notCovered,
                                headline: "Two things are in no backup.",
                                severity: .problem,
                                coverage: [Coverage(name: "Scans", lives: .onlyOnThisMac,
                                                    included: .no, why: "Only here.")])
        #expect(withGap.severity == .problem)
        #expect(withGap.gaps.count == 1)
    }

    @Test("An unprinted Recovery Plan is never a problem")
    func recoveryPlanIsClamped() {
        let row = BackupRow(topic: .recoveryPlan,
                            headline: "You have not printed one.",
                            severity: .problem)
        #expect(row.severity == .attention)
    }

    @Test("A row we could not read reports nothing and is never a fault")
    func unreadableRowsAreQuiet() {
        let row = BackupRow.unreadable(.notCovered, .notPermitted)
        #expect(row.severity == .information)
        #expect(row.status == .notChecked)
        #expect(row.measure == nil)
        #expect(row.coverage.isEmpty)
        #expect(row.complete == false, "a refusal a person could lift makes the run incomplete")

        let cannotBeGranted = BackupRow.unreadable(.notCovered, .notGrantable)
        #expect(cannotBeGranted.complete, "a refusal nobody can lift does not put a permanent caveat on Overview")
    }
}

@Suite("What the whole section says")
struct BackupReportTests {

    private func switchedOffMac(now: Date) -> TimeMachineState {
        TimeMachineState(isConfigured: true,
                         automaticBackupsOn: false,
                         destination: BackupDestination(name: "JDS Backup", kind: .localDrive, isConnected: false),
                         lastSuccess: now.addingTimeInterval(-4 * 86_400))
    }

    @Test("The one row Overview gets is about a backup that is not happening")
    func overviewHearsAboutTheSwitch() {
        let now = Date()
        let report = BackupReport(timeMachine: switchedOffMac(now: now),
                                  rows: [BackupRow(topic: .appleBackup, headline: "x")],
                                  ranAt: now)
        let finding = try? #require(report.overviewFinding)
        #expect(finding?.severity == .problem)
        #expect(finding?.section == .backup)
        #expect(finding?.title == "Time Machine is switched off")
    }

    @Test("Overview never hears that somebody keeps files in iCloud")
    func overviewNeverHearsAboutTheCloud() {
        let now = Date()
        let healthy = TimeMachineState(isConfigured: true,
                                       automaticBackupsOn: true,
                                       destination: BackupDestination(name: "Backup", kind: .localDrive, isConnected: true),
                                       lastSuccess: now.addingTimeInterval(-3600))
        let report = BackupReport(
            timeMachine: healthy,
            rows: [BackupRow(topic: .notCovered,
                             headline: "Where your files live.",
                             coverage: [Coverage(name: "Media", lives: .onlyInTheCloud, included: .no, why: "Not here."),
                                        Coverage(name: "Photos", lives: .inTheCloudAndHere, included: .yes, why: "Copied.")])],
            ranAt: now)
        #expect(report.overviewFinding == nil)
        #expect(report.gaps.isEmpty)
    }

    @Test("Rows come back in topic order however they arrived")
    func rowsSortThemselves() {
        let now = Date()
        let report = BackupReport(
            timeMachine: switchedOffMac(now: now),
            rows: [BackupRow(topic: .recoveryPlan, headline: "c"),
                   BackupRow(topic: .appleBackup, headline: "a"),
                   BackupRow(topic: .appleBackup, headline: "duplicate"),
                   BackupRow(topic: .notCovered, headline: "b")],
            ranAt: now)
        #expect(report.rows.map(\.topic) == [.appleBackup, .notCovered, .recoveryPlan])
        #expect(report.rows.filter { $0.topic == .appleBackup }.count == 1, "first one wins")
        // ⚠️ Not "a". The Time Machine row's sentence is authored by the report from its own
        // `ranAt`, deliberately — see `OneReportOneClockTests` for the face that said 25 days in
        // one sentence and 26 in another. What this test still proves is the ordering and the
        // dropping of the duplicate; the headline is no longer the reader's to keep.
        #expect(report.row(.appleBackup)?.headline == report.summary)
        #expect(report.row(.recoveryPlan)?.headline == "c", "other rows are passed through untouched")
    }

    @Test("The face says the gate is shut, unprompted")
    func theGateAppearsOnTheFace() {
        let now = Date()
        let report = BackupReport(timeMachine: switchedOffMac(now: now),
                                  rows: [BackupRow(topic: .appleBackup, headline: "x")],
                                  ranAt: now)
        #expect(report.linesUnderTheHeadline.contains(RehearsalGate.faceLine) == !RehearsalGate.hasBeenRehearsed)
    }

    @Test("The record that reaches the audit trail")
    func theRecord() {
        let now = Date()
        let report = BackupReport(timeMachine: switchedOffMac(now: now),
                                  rows: [BackupRow(topic: .appleBackup, headline: "x", severity: .problem)],
                                  ranAt: now)
        #expect(report.record.section == .backup)
        #expect(report.status == .needsAttention)
        #expect(report.complete)
    }
}

// MARK: - ⛔ The gate

@Suite("The rehearsal gate, and what it refuses")
struct RehearsalGateTests {

    @Test("⛔ Nothing is offered until somebody has restored from a real drive")
    func theGateIsShutUntilItIsNot() {
        // ⚠️ This test does not assert the gate is shut. It asserts the gate and what it offers
        // agree with each other — so it keeps working on the day John opens it, and it catches a
        // half-flip where the constant moved and the offer did not.
        #expect(RehearsalGate.mayBeOffered == RehearsalGate.hasBeenRehearsed)
        if !RehearsalGate.hasBeenRehearsed {
            let decision = RehearsalGate.permissionToWrite(to: "a drive")
            #expect(decision.isGranted == false)
            #expect(decision.pass == nil)
            #expect(decision.refusal?.missing == [.rehearsal])
        }
    }

    @Test("A rehearsal with a blank in it does not open the gate")
    func placeholdersDoNotCount() {
        let blank = RehearsalGate.Rehearsal(performedOn: Date(timeIntervalSince1970: 1_700_000_000),
                                            hardware: "  ",
                                            macOS: "26.6.2",
                                            restoredWith: "Migration Assistant",
                                            notes: "Fine.")
        #expect(blank.isProperlyRecorded() == false)

        let future = RehearsalGate.Rehearsal(performedOn: Date().addingTimeInterval(86_400),
                                             hardware: "Mac mini",
                                             macOS: "26.6.2",
                                             restoredWith: "Migration Assistant",
                                             notes: "Fine.")
        #expect(future.isProperlyRecorded() == false, "a rehearsal cannot have happened tomorrow")

        let good = RehearsalGate.Rehearsal(performedOn: Date(timeIntervalSince1970: 1_700_000_000),
                                           hardware: "Mac mini (M3), Samsung T7 2 TB, APFS (Encrypted)",
                                           macOS: "26.6.2",
                                           restoredWith: "Migration Assistant after a clean install",
                                           notes: "Everything came back; Mail and Photos checked by hand.")
        #expect(good.isProperlyRecorded())
    }

    @Test("If the rehearsal is recorded, it is recorded properly")
    func whateverIsThereIsWellFormed() {
        if let performed = RehearsalGate.performed {
            #expect(performed.isProperlyRecorded(),
                    "the rehearsal constant is filled in but incomplete — that opens nothing and means nothing")
        }
    }

    @Test("⚠️ The background piece has to clear both proofs")
    func theAgentNeedsTwo() {
        let decision = RehearsalGate.permissionForTheBackgroundPiece(to: "a drive")
        if RehearsalGate.hasBeenRehearsed && RehearsalGate.agentIsProved {
            #expect(decision.isGranted)
        } else {
            #expect(decision.isGranted == false)
            var expected: [RehearsalGate.Missing] = []
            if !RehearsalGate.hasBeenRehearsed { expected.append(.rehearsal) }
            if !RehearsalGate.agentIsProved { expected.append(.agentFullDiskAccess) }
            #expect(decision.refusal?.missing == expected)
        }
    }

    @Test("The refusal says what has not happened, not that a feature is unavailable")
    func theRefusalIsPlain() {
        #expect(RehearsalGate.faceLine.contains("erasing a drive and restoring from it"))
        #expect(RehearsalGate.faceLine.lowercased().contains("unavailable") == false)
        #expect(RehearsalGate.backgroundPieceLine.contains("reports no error"))
    }

    @Test("⚠️ A pass made for a test admits to it")
    func theTestingDoorIsLabelled() {
        let pass = RehearsalGate.passForTesting("a temporary folder this test made")
        #expect(pass.isForTestingOnly)
        #expect(pass.rehearsal == nil)
        #expect(pass.description.contains("FOR TESTING ONLY"))
    }
}

// MARK: - The printed page

@Suite("The Recovery Plan is a page, and it knows what it cannot know")
struct RecoveryPlanTests {

    private func plan(fileVaultOn: Bool = true,
                      macOS: String = "26.6.2",
                      destination: String? = "JDS Backup") -> RecoveryPlan {
        RecoveryPlan.make(macOSVersion: macOS,
                          macDescription: "MacBook Pro (14-inch, M3, 2024)",
                          architecture: .appleSilicon,
                          destinationName: destination,
                          fileVaultOn: fileVaultOn,
                          writtenOn: Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test("⭐ There is nowhere in this page to put a secret")
    func aBlankHasNoValue() {
        let blank = RecoveryBlank(label: "FileVault recovery key", whereToFindIt: "Passwords app.")
        let names = Mirror(reflecting: blank).children.compactMap(\.label).sorted()
        #expect(names == ["label", "lineLength", "whereToFindIt"],
                "RecoveryBlank grew a field. If any of these can hold a value, Wellkept can print somebody's recovery key.")
    }

    @Test("⚠️ The FileVault key warning leads the page, and says the Apple ID route is gone")
    func theFileVaultWarningIsThere() {
        let warning = try? #require(plan().warningForToday)
        #expect(warning?.mustBeDoneWhileTheMacStillWorks == true)
        #expect(warning?.body.contains("no longer keeps that key with Apple") == true)
        #expect(warning?.body.contains("Apple ID does not work any more") == true)
        #expect(warning?.body.contains("Passwords") == true)
        #expect(plan().warnings.filter(\.mustBeDoneWhileTheMacStillWorks).count == 1,
                "exactly one thing on this page has to be done before anything goes wrong")
    }

    @Test("The page carries the macOS it was written for, and says when to reprint")
    func thePageHasALifetime() {
        let p = plan(macOS: "26.6.2")
        #expect(p.macOSVersion == "26.6.2")
        #expect(p.isStale(currentMacOS: "26.6.2") == false)
        #expect(p.isStale(currentMacOS: "26.6.3"), "Migration Assistant's rule is \"newer than\", so a point release counts")
        #expect(p.reprintLine(currentMacOS: "26.6.3")?.contains("26.6.2") == true)
        #expect(p.reprintLine(currentMacOS: "26.6.2") == nil)
        #expect(p.subtitle.contains("26.6.2"))
    }

    @Test("Do not erase anything is the first step, and leave it alone is the last")
    func theOrderIsTheWorstDay() {
        let steps = plan().steps
        #expect(steps.first?.title.contains("Do not erase") == true)
        #expect(steps.last?.title.contains("Leave the backup drive alone") == true)
        #expect(steps.count >= 8)
        #expect(steps.allSatisfy { !$0.why.isEmpty }, "every step says why")
    }

    @Test("⛔ No installer on the drive, and no step needs Wellkept")
    func whatIsDeliberatelyAbsent() {
        let p = plan()
        let everything = (p.steps.map { $0.title + $0.whatToDo + $0.why }
                          + p.warnings.map { $0.title + $0.body }).joined(separator: " ")
        #expect(everything.contains("would not be used"),
                "Apple silicon Recovery downloads its own installer — the page has to say so")
        #expect(everything.lowercased().contains("bootable") == false, "bootable backups are dead")
        #expect(p.warnings.contains { $0.title == "None of this needs Wellkept." })
    }

    @Test("A Mac with no backup is told so, rather than handed steps that assume one")
    func noBackupIsSaidOutLoud() {
        let p = plan(destination: nil)
        #expect(p.warnings.contains { $0.title.contains("no backup for this page to point at") })
        #expect(p.steps.first?.whatToDo.contains("your backup drive") == true)
    }

    @Test("FileVault off still warns about the day it is switched on")
    func fileVaultOffStillMentionsIt() {
        let p = plan(fileVaultOn: false)
        #expect(p.warningForToday == nil)
        #expect(p.warnings.contains { $0.title.contains("switch FileVault on") })
    }

    @Test("One Recovery instruction is printed, not two")
    func oneInstruction() {
        #expect(MacArchitecture.appleSilicon.howToReachRecovery.contains("Loading startup options"))
        #expect(MacArchitecture.appleSilicon.howToReachRecovery.contains("Command and R") == false)
        #expect(MacArchitecture.intel.howToReachRecovery.contains("Command and R"))
        #expect(MacArchitecture.howToReachRecoveryWhenWeDoNotKnow.contains("2021 or later"))
    }
}

// MARK: - One report, one clock

/// ⚠️ **The face said "25 days ago" in its summary and "26 days ago" on the row an inch below.**
///
/// Both sentences were right about their own instant and wrong about each other: the row is built
/// by the reader when it runs, and the summary is written when the report is stamped. A last
/// backup sitting near a 24-hour boundary needs only a moment between them. A person who reads two
/// different numbers for one fact stops believing both, and this section's whole value is being
/// believed about a backup.
///
/// `BackupReport.init` now rewrites the Time Machine row's sentences from its own `ranAt`. These
/// are the tests that keep it that way.
@Suite("One report never disagrees with itself about the day")
struct OneReportOneClockTests {

    private static func state(lastSuccess: Date) -> TimeMachineState {
        TimeMachineState(isConfigured: true,
                         automaticBackupsOn: false,
                         destination: nil,
                         lastSuccess: lastSuccess,
                         unreadable: nil)
    }

    @Test("A row built a moment earlier is re-stated from the report's own clock")
    func theRowIsNormalised() {
        // Exactly on the boundary, which is where the two instants disagree.
        let stamped = Date()
        let lastSuccess = stamped.addingTimeInterval(-26 * 86_400)
        let machine = Self.state(lastSuccess: lastSuccess)

        // The reader's instant: a second earlier, which floors to 25 rather than 26.
        let readerRow = BackupRow(topic: .appleBackup,
                                  headline: machine.headline(now: stamped.addingTimeInterval(-1)))

        let report = BackupReport(timeMachine: machine, rows: [readerRow], ranAt: stamped)
        let row = report.rows.first { $0.topic == .appleBackup }

        #expect(row?.headline == report.summary,
                "the row and the summary are describing the same backup with different numbers")
    }

    @Test("Whatever the reader said, the report says it once")
    func noTwoSentencesDisagree() {
        let stamped = Date()
        for daysBack in [0, 1, 9, 26, 88] {
            let machine = Self.state(lastSuccess: stamped.addingTimeInterval(-Double(daysBack) * 86_400))
            let stale = BackupRow(topic: .appleBackup,
                                  headline: "Time Machine last backed up 999 days ago.")
            let report = BackupReport(timeMachine: machine, rows: [stale], ranAt: stamped)
            let row = report.rows.first { $0.topic == .appleBackup }
            #expect(row?.headline != stale.headline, "the stale sentence survived into the report")
            #expect(row?.headline == report.summary)
        }
    }
}
