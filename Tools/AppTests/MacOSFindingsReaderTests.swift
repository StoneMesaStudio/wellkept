import Testing
import Foundation
import WellkeptCore

//  MacOSFindingsReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **Three promises, and all three are invisible from the outside when they break.**
//
//  1. **The window is measured, never assumed.** "macOS found nothing" is a claim about a fortnight
//     that macOS sized itself, and a Mac asleep for a month has a window that says nothing at all.
//  2. **A standard account gets `.notGrantable`** — no button, and the check still complete.
//     `.notPermitted` here would put a caveat on Overview that nobody could ever clear.
//  3. **"Some scanners did not finish" is ordinary**, and the copy has to read as ordinary, because
//     it is true on most Macs most days.
//
//  Nothing here reads this Mac's log. Every value is typed out, from real events captured on
//  2026-08-27.

@Suite struct MacOSFindingsStatusTests {

    /// The three words this Mac actually produced today, across 34 events: 31 `NoThreatDetected`,
    /// 2 `Success`, 1 `PluginCanceled`.
    @Test func theWordsThisMacActuallyProduces() {
        #expect(MacOSFindingsReader.outcome(of: "NoThreatDetected") == .clean)
        #expect(MacOSFindingsReader.outcome(of: "Success") == .clean)
        #expect(MacOSFindingsReader.outcome(of: "PluginCanceled") == .didNotFinish)
    }

    /// ⚠️ **"NoThreatDetected" contains "ThreatDetected".** A reader that checked for the alarming
    /// substring first would report a clean Mac as an infected one, every time, on every Mac.
    @Test func theCleanWordIsNotReadAsTheAlarmingOneInsideIt() {
        #expect(MacOSFindingsReader.outcome(of: "NoThreatDetected") == .clean)
        #expect(MacOSFindingsReader.outcome(of: "ThreatDetected") == .dealtWith)
    }

    /// ⚠️ **A word we do not know is reported as a word we do not know.** Apple adds to this
    /// vocabulary without announcing it; filing an unknown under "found nothing" would turn a new
    /// kind of finding into silence, and filing it under "found something" would invent an alarm.
    @Test func anUnknownWordIsCarriedVerbatim() {
        #expect(MacOSFindingsReader.outcome(of: "SomethingApplePublishedInMarch")
                == .unrecognised("SomethingApplePublishedInMarch"))
    }

    /// The plugin's name, without Apple's prefix, and anything else left alone.
    @Test func theScannerKeepsItsOwnName() {
        #expect(MacOSFindingsReader.scannerName(fromProcess: "XProtectRemediatorKeySteal")
                == "KeySteal")
        #expect(MacOSFindingsReader.scannerName(fromProcess: "XProtect") == "XProtect")
    }

    /// One real event from this Mac, byte for byte.
    @Test func aRealEventParses() {
        let message = #"{"execution_duration":0.00055,"status_message":"NoThreatDetected","status_code":20,"caused_by":[]}"#
        let result = MacOSFindingsReader.result(fromMessage: message,
                                                process: "XProtectRemediatorAdload",
                                                at: Date(timeIntervalSince1970: 1_000))
        #expect(result?.scanner == "Adload")
        #expect(result?.outcome == .clean)
        #expect(result?.statusCode == 20)
    }

    /// The progress chatter under the same subsystem is not JSON. It is skipped rather than
    /// half-read: 5,076 of the 5,700 entries on this Mac are path-scanning lines.
    @Test func chatterIsSkipped() {
        #expect(MacOSFindingsReader.result(fromMessage: "Initialized libYARA version 4.1",
                                           process: "XProtectRemediatorAdload",
                                           at: Date()) == nil)
    }
}

@Suite struct MacOSFindingsWindowTests {

    /// ⚠️ **The window is arithmetic on what the store actually held**, and `nil` is a real answer
    /// rather than a stand-in fortnight.
    @Test func theWindowIsMeasuredAndNeverAssumed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let twelveDays = now.addingTimeInterval(-12 * 86_400)
        #expect(MacOSFindingsReader.measuredDays(earliestRecord: twelveDays, now: now) == 12)
        #expect(MacOSFindingsReader.measuredDays(earliestRecord: nil, now: now) == nil)
        // A store whose first entry is minutes old is a real, very short window — not no window.
        #expect(MacOSFindingsReader.measuredDays(earliestRecord: now.addingTimeInterval(-600),
                                                 now: now) == 1)
    }

    /// ⚠️ **The row borrows the section's own sentence and never writes its own.** Two copies of a
    /// sentence about how far back "nothing" reaches is two chances for the row and the summary
    /// above it to disagree.
    @Test func theWindowClauseIsTheSectionsOwnWording() {
        for days in [nil, 1, 12] as [Int?] {
            #expect(MacOSFindingsReader.windowClause(days)
                    == SecurityReport(block: .unknown, rows: [], measuredDays: days).windowClause)
        }
    }

    /// The figure on the row is the window itself, and it is absent rather than invented when the
    /// window could not be measured.
    @Test func theMeasureIsTheWindowOrNothing() {
        #expect(MacOSFindingsReader.measure(14) == "14 days")
        #expect(MacOSFindingsReader.measure(1) == "1 day")
        #expect(MacOSFindingsReader.measure(nil) == nil)
    }
}

@Suite struct MacOSFindingsRowTests {

    private static func result(_ scanner: String,
                               _ status: String,
                               daysAgo: Double,
                               now: Date) -> MacOSFindingsReader.ScanResult {
        MacOSFindingsReader.ScanResult(scanner: scanner,
                                       at: now.addingTimeInterval(-daysAgo * 86_400),
                                       outcome: MacOSFindingsReader.outcome(of: status),
                                       statusMessage: status,
                                       statusCode: nil)
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// **This Mac, this morning.** Nineteen scanners clean, one cancelled part-way. The row says
    /// nothing was found, says how far back that reaches, and treats the cancelled one as routine.
    @Test func aCleanMacSaysHowFarBackTheNothingReaches() {
        let survey = MacOSFindingsReader.Survey(
            results: [Self.result("Adload", "NoThreatDetected", daysAgo: 0, now: Self.now),
                      Self.result("KeySteal", "PluginCanceled", daysAgo: 0, now: Self.now)],
            earliestRecord: Self.now.addingTimeInterval(-14 * 86_400),
            lastActivity: Self.now
        )
        let answer = MacOSFindingsReader.answer(from: survey, now: Self.now)

        #expect(answer.measuredDays == 14)
        #expect(answer.row.headline == "macOS's own scanners found nothing in the last 14 days.")
        #expect(answer.row.measure == "14 days")
        #expect(answer.row.status == .good)
        #expect(answer.row.concerns.isEmpty)
    }

    /// ⚠️ **Routine, and worded as routine.** One of about twenty plugins stopping mid-flight is
    /// what a normal Tuesday looks like; a health check that raises an eyebrow at it raises one on
    /// most Macs most days.
    @Test func aScannerThatDidNotFinishReadsAsOrdinary() {
        let survey = MacOSFindingsReader.Survey(
            results: [Self.result("KeySteal", "PluginCanceled", daysAgo: 0, now: Self.now)],
            earliestRecord: Self.now.addingTimeInterval(-14 * 86_400),
            lastActivity: Self.now
        )
        let reason = MacOSFindingsReader.answer(from: survey, now: Self.now).row.reason ?? ""
        #expect(reason.contains("That is routine"))
        #expect(!reason.lowercased().contains("failed to"))
        #expect(!reason.lowercased().contains("warning"))
    }

    /// ⚠️ **A Mac that has been asleep says so**, rather than reporting a clean result nobody
    /// earned. Nothing found and nothing run look identical in the log; only this sentence
    /// separates them.
    @Test func aMacThatHasNotRunItsScannersSaysThatInstead() {
        let survey = MacOSFindingsReader.Survey(
            results: [],
            earliestRecord: Self.now.addingTimeInterval(-30 * 86_400),
            lastActivity: nil
        )
        let row = MacOSFindingsReader.answer(from: survey, now: Self.now).row
        #expect(row.headline == "macOS's own scanners have not run in the last 30 days.")
        #expect(row.reason?.contains("asleep or switched off") == true)
        #expect(!row.headline.contains("found nothing"))
    }

    /// A finding is stated plainly, and it stays a statement: the section has no red, and no
    /// concern in the closed list of nine is about an XProtect result, so this row cannot turn
    /// amber. What it reports has already been dealt with, by Apple, before Wellkept looked.
    @Test func aFindingIsStatedPlainlyAndIsNeverRed() {
        let survey = MacOSFindingsReader.Survey(
            results: [Self.result("Adload", "ThreatRemediated", daysAgo: 3, now: Self.now)],
            earliestRecord: Self.now.addingTimeInterval(-14 * 86_400),
            lastActivity: Self.now
        )
        let row = MacOSFindingsReader.answer(from: survey, now: Self.now).row
        #expect(row.headline == "macOS found something and dealt with it in the last 14 days.")
        #expect(row.reason?.contains("Nothing is left for you to do") == true)
        #expect(row.severity != .problem)
        #expect(row.concerns.isEmpty)
    }

    /// ⚠️ **A standard account: `.notGrantable`.** No button, and the check stays complete —
    /// because no permission this app could ask for would have shown it more. `.notPermitted` here
    /// is the bug that put an unclearable caveat on Overview.
    @Test func aStandardAccountGetsNoButtonAndStillCountsAsComplete() {
        let survey = MacOSFindingsReader.Survey(results: nil, isAdministrator: false)
        let answer = MacOSFindingsReader.answer(from: survey, now: Self.now)

        #expect(answer.row.unreadable == .notGrantable)
        #expect(answer.row.remedy == nil)
        #expect(answer.row.complete, "a refusal nobody can lift must not make the check incomplete")
        #expect(answer.row.status == .notChecked)
        #expect(answer.row.reason?.contains("administrator account") == true)
        #expect(answer.row.reason?.contains("nothing to switch on") == true)
    }

    /// An administrator who still cannot open the log is not told to become an administrator.
    @Test func anAdministratorWhoIsRefusedGetsADifferentSentence() {
        let survey = MacOSFindingsReader.Survey(results: nil, isAdministrator: true)
        let reason = MacOSFindingsReader.answer(from: survey, now: Self.now).row.reason ?? ""
        #expect(!reason.contains("Only an administrator"))
        #expect(reason.contains("no permission that would change that"))
    }

    /// ⚠️ A refused read is never a zero. The row carries no count and no measure — it did not find
    /// that nothing happened, it did not look.
    @Test func aRefusedReadCarriesNoFigure() {
        let row = MacOSFindingsReader.answer(from: .init(results: nil), now: Self.now).row
        #expect(row.measure == nil)
        #expect(!row.headline.contains("0"))
    }

    /// Everything not routine is kept, even where the same scanner ran clean afterwards — "macOS
    /// removed something last Tuesday" does not stop being true because Wednesday was quiet.
    /// Routine results collapse to the latest one per scanner.
    @Test func findingsSurviveAndRoutineResultsCollapse() {
        let condensed = MacOSFindingsReader.condense([
            Self.result("Adload", "ThreatRemediated", daysAgo: 5, now: Self.now),
            Self.result("Adload", "NoThreatDetected", daysAgo: 4, now: Self.now),
            Self.result("Adload", "NoThreatDetected", daysAgo: 0, now: Self.now),
            Self.result("KeySteal", "NoThreatDetected", daysAgo: 1, now: Self.now),
        ])
        #expect(condensed.count == 3)
        #expect(condensed.contains { $0.outcome == .dealtWith })
        #expect(condensed.filter { $0.scanner == "Adload" && $0.outcome == .clean }.count == 1)
        // Newest first, so the disclosure reads the way a person expects a log to read.
        #expect(condensed == condensed.sorted { $0.at > $1.at })
    }

    /// The Options panel always says how far back the records go and how we looked, because the row
    /// above it is a claim about exactly that.
    @Test func optionsAlwaysCarryTheWindowAndTheMethod() {
        let survey = MacOSFindingsReader.Survey(
            results: [Self.result("Adload", "NoThreatDetected", daysAgo: 0, now: Self.now)],
            earliestRecord: Self.now.addingTimeInterval(-9 * 86_400),
            lastActivity: Self.now
        )
        let details = MacOSFindingsReader.answer(from: survey, now: Self.now).row.details
        #expect(details.contains { $0.label == "Records go back to" })
        #expect(details.first { $0.label == "Window measured" }?.value == "9 days")
        #expect(details.first { $0.label == "How we looked" }?.value.contains("scanned nothing")
                == true)
    }
}
