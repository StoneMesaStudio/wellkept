// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
// Plain import, not `@testable` — everything the report promises is public.
import WellkeptCore

//  HealthReportTests.swift
//  WellkeptTests
//
//  ⭐ **The page somebody hands to their repair shop, and the four laws it cannot break.**
//
//  This is the one artefact in Wellkept that is read away from the app. Nobody reading it can see
//  the screen it came from, ask what "Not checked" meant, or notice that a permission was off. So
//  every qualification the screen puts *around* the answer has to travel *inside* the page, and
//  these tests are what stops a later, well-meaning edit dropping one.
//
//  The four:
//
//  1. **The clean sentence appears if and only if the report is entitled to it.** Asserted over the
//     whole state — every combination of findings, unchecked sections, partial sections, permissions
//     and demo mode — rather than by looking at one screen. This is the rule the whole app is built
//     on, and it is the one a page can break most quietly.
//  2. **The audit trail lists all seven, always**, including the checks that never ran. It was asked
//     for by name: *"an audit trail for reassurance of what was checked please."* A list that
//     silently omitted the checks that did not happen would be reassurance about nothing.
//  3. **The caveats cannot be left off.** There is no initialiser that takes them.
//  4. **Never a score.** There is nowhere in the type to put one, and no sentence it produces
//     contains a grade.

// MARK: - Fixtures

private enum Mac {

    static let facts = MachineFacts(
        name: "Ada's MacBook Air",
        modelName: "MacBook Air (15-inch, M3, 2024)",
        modelIdentifier: "Mac15,13",
        chip: "Apple M3",
        memory: "16 GB",
        driveSize: "460 GB",
        systemVersion: "macOS 26.1",
        systemMajorVersion: 26,
        serialNumber: "C02XY1234567")

    /// A Mac with no serial number to report. Rare, and the case where offering a switch would be
    /// offering a control that changes nothing.
    static let factsWithoutSerial = MachineFacts(
        name: "The spare mini",
        modelName: "Mac mini (2024)",
        modelIdentifier: "Mac16,10",
        chip: "Apple M4",
        memory: "16 GB",
        driveSize: "245 GB",
        systemVersion: "macOS 26.1",
        systemMajorVersion: 26)

    static let ran = Date(timeIntervalSince1970: 1_787_000_000)

    /// Every checkable section ran, saw everything, and found nothing.
    static func allGood(at date: Date = ran) -> [SectionID: CheckRecord] {
        var out: [SectionID: CheckRecord] = [:]
        for section in SectionID.checkable {
            out[section] = CheckRecord(section: section, ranAt: date, status: .good, complete: true)
        }
        return out
    }

    static func problem(_ section: SectionID) -> Finding {
        Finding(section: section,
                title: "The firewall is off",
                reason: "Nothing is filtering what reaches this Mac from the network.",
                severity: .problem)
    }

    static let fullDiskOff = PermissionShortfall(
        permission: "Full Disk Access",
        sentences: ["Full Disk Access is off, so this cannot see everything using your space."])
}

// MARK: - ⭐ 1. The clean sentence, and the four things that forbid it

@Suite("The report may never say a Mac looks fine after a partial look")
struct HealthReportCleanStateTests {

    /// ⭐ **The law, asserted over the state rather than over a screen.**
    ///
    /// Sixteen combinations of the four vetoes. In every one of them the clean sentence appears if
    /// and only if `isCleanBillOfHealth` — there is no arrangement of inputs that produces one
    /// without the other, which is what makes the property safe for another screen to read.
    @Test func theCleanSentenceAppearsExactlyWhenItIsEarned() {
        for hasFinding in [false, true] {
            for missedOne in [false, true] {
                for sawPart in [false, true] {
                    for demo in [false, true] {
                        var records = Mac.allGood()
                        if missedOne { records[.storage] = nil }
                        if sawPart {
                            records[.apps] = CheckRecord(section: .apps, ranAt: Mac.ran,
                                                         status: .good, complete: false)
                        }

                        let report = HealthReport(
                            machine: Mac.facts,
                            findings: hasFinding ? [Mac.problem(.security)] : [],
                            records: records,
                            sampleResults: demo)

                        let saysFine = report.headline == HealthReport.everythingLooksFine
                        #expect(saysFine == report.isCleanBillOfHealth, """
                            finding:\(hasFinding) missed:\(missedOne) partial:\(sawPart) \
                            demo:\(demo) — the page said "\(report.headline)" while \
                            isCleanBillOfHealth was \(report.isCleanBillOfHealth).
                            """)
                        if hasFinding || missedOne || sawPart || demo {
                            #expect(!saysFine)
                        }
                    }
                }
            }
        }
    }

    /// A permission that was off is the fifth veto, and it is separate from the four above: a
    /// section can be `complete: true` on its own terms while the grant it needed was never given.
    @Test func aPermissionThatWasOffAlsoForbidsTheCleanSentence() {
        let report = HealthReport(machine: Mac.facts,
                                  findings: [],
                                  records: Mac.allGood(),
                                  permissionsOff: [Mac.fullDiskOff])
        #expect(!report.isCleanBillOfHealth)
        #expect(!report.sawEverything)
        #expect(report.headline != HealthReport.everythingLooksFine)
    }

    /// The one arrangement that earns it: everything ran, everything was seen, nothing was found,
    /// and nothing was invented.
    @Test func aMacWithNothingWrongIsAllowedToSaySo() {
        let report = HealthReport(machine: Mac.facts, findings: [], records: Mac.allGood())
        #expect(report.isCleanBillOfHealth)
        #expect(report.headline == HealthReport.everythingLooksFine)
        // The clean state is the sentence AND the date. On a page read weeks later the date is
        // the more load-bearing half.
        #expect(report.subtitle.contains("Ada's MacBook Air"))
    }

    /// ⚠️ A page with nothing checked at all is the likeliest one to be mistaken for good news:
    /// there is nothing on it. It gets the strongest sentence available.
    @Test func aPageWithNothingCheckedSaysSoFirst() {
        let report = HealthReport(machine: nil, findings: [], records: [:])
        #expect(!report.isCleanBillOfHealth)
        #expect(report.headline != HealthReport.everythingLooksFine)
        #expect(!report.caveats.isEmpty)
    }

    @Test func theHeadlineCountsWhatNeedsYouInWords() {
        let two = HealthReport(findings: [Mac.problem(.security), Mac.problem(.backup)],
                               records: Mac.allGood())
        #expect(two.headline == "Two things need you.")

        let one = HealthReport(findings: [Mac.problem(.security)], records: Mac.allGood())
        #expect(one.headline == "One thing needs you.")
    }
}

// MARK: - ⭐ 2. The audit trail

@Suite("The audit trail lists all seven and says when each ran")
struct HealthReportAuditTests {

    /// ⭐ **All seven, on every page, whatever the records happen to contain.**
    @Test func allSevenAppearEvenWhenNothingHasRun() {
        let report = HealthReport(findings: [], records: [:])
        #expect(report.audit.count == SectionID.allCases.count)
        #expect(report.audit.map(\.section) == SectionID.allCases)
        for line in report.audit {
            #expect(line.ranAt == nil)
            #expect(line.status == .notChecked)
            #expect(line.whenSentence == "Not run")
        }
    }

    /// A section that ran carries its time; a section that did not says so in words. ⚠️ **Never a
    /// dash** — a dash on a page a stranger is reading is a shrug.
    @Test func theOnesThatRanCarryTheirTimeAndTheOthersSaySo() {
        var records = Mac.allGood()
        records[.storage] = nil

        let report = HealthReport(findings: [], records: records)
        let storage = report.audit.first { $0.section == .storage }
        let apps = report.audit.first { $0.section == .apps }

        #expect(storage?.ranAt == nil)
        #expect(storage?.whenSentence == "Not run")
        #expect(storage?.line.contains("Not checked") == true)
        #expect(apps?.ranAt == Mac.ran)
        #expect(apps?.whenSentence.isEmpty == false)
        #expect(apps?.whenSentence != "Not run")
    }

    /// A section that saw part of the Mac says so on its own row, not only in the caveats. The
    /// caveat is the reason; the row is the fact, and somebody scanning the list needs it there.
    @Test func aPartialCheckSaysSoOnItsOwnRow() {
        var records = Mac.allGood()
        records[.security] = CheckRecord(section: .security, ranAt: Mac.ran,
                                         status: .good, complete: false)
        let report = HealthReport(findings: [], records: records)
        let security = try? #require(report.audit.first { $0.section == .security })
        #expect(security?.sawEverything == false)
        #expect(security?.line.contains("saw part of this Mac") == true)
    }

    /// ⚠️ **A check that never ran saw nothing, not part.**
    ///
    /// The first printed page of this report said "Apps: Not checked — Not run (saw part of this
    /// Mac)", which claims a look that never happened. The row already says it did not run; the
    /// caveat about a short look belongs only to a check that actually looked.
    @Test func aCheckThatNeverRanDoesNotClaimAPartialLook() {
        let report = HealthReport(findings: [], records: [:])
        for line in report.audit {
            #expect(!line.sawOnlyPart)
            #expect(!line.line.contains("saw part of this Mac"))
        }

        // And the row that did run short still says so, so the fix did not silence the real case.
        var records = Mac.allGood()
        records[.storage] = CheckRecord(section: .storage, ranAt: Mac.ran,
                                        status: .good, complete: false)
        let mixed = HealthReport(findings: [], records: records)
        #expect(mixed.audit.first { $0.section == .storage }?.sawOnlyPart == true)
    }

    /// Overview's own line is on the page, because the sweep is itself a check and its record is
    /// what says whether the whole press completed.
    @Test func overviewsOwnLineIsOnThePage() {
        #expect(HealthReport(findings: [], records: [:]).audit.contains { $0.section == .overview })
    }
}

// MARK: - ⭐ 3. The caveats travel with the page

@Suite("Every qualification travels inside the report")
struct HealthReportCaveatTests {

    /// ⚠️ Checks that never ran are named, and the caveat says what that costs: the page says
    /// nothing about them. Without it, silence reads as approval.
    @Test func checksThatNeverRanAreNamedOnThePage() {
        var records = Mac.allGood()
        records[.storage] = nil
        records[.backup] = nil

        let report = HealthReport(findings: [], records: records)
        let text = report.caveats.map { "\($0.title) \($0.body)" }.joined(separator: " ")
        #expect(text.contains("Storage"))
        #expect(text.contains("Backup"))
        #expect(text.contains("Two checks were not run"))
    }

    @Test func aPartialCheckIsNamedOnThePage() {
        var records = Mac.allGood()
        records[.security] = CheckRecord(section: .security, ranAt: Mac.ran,
                                         status: .good, complete: false)
        let report = HealthReport(findings: [], records: records)
        let body = report.caveats.map(\.body).joined(separator: " ")
        #expect(body.contains("Security"))
        #expect(body.contains("not everything there is"))
    }

    /// ⚠️ **The permission's cost is quoted, never paraphrased.** The sentences are the app's own
    /// `FullDiskAccess.shortfall(for:)` strings, so the page and the section's own face say the
    /// same thing about the same refusal.
    @Test func aRefusedPermissionCarriesTheAppsOwnSentence() {
        let report = HealthReport(findings: [],
                                  records: Mac.allGood(),
                                  permissionsOff: [Mac.fullDiskOff])
        let caveat = report.caveats.first { $0.title.contains("Full Disk Access") }
        #expect(caveat != nil)
        #expect(caveat?.body == Mac.fullDiskOff.sentences.joined(separator: " "))
    }

    /// ⭐ **Three states, and the middle one is a real answer.** Declining is not the same as never
    /// having been asked, and a page that collapsed them would tell a repair shop the owner refused
    /// something they were never offered.
    @Test func theUpdateCheckHasThreeAnswersOnThePageToo() {
        let allowed = HealthReport(findings: [], records: Mac.allGood(), appUpdateChecking: true)
        #expect(!allowed.caveats.contains { $0.title.lowercased().contains("update") })

        let declined = HealthReport(findings: [], records: Mac.allGood(), appUpdateChecking: false)
        let declinedCaveat = declined.caveats.first { $0.title.lowercased().contains("update") }
        #expect(declinedCaveat?.title.contains("switched off") == true)
        // Quoted from the register rather than paraphrased — see the header of `Privacy.swift`.
        #expect(declinedCaveat?.body.contains(Privacy.Departure.appUpdateCheck.cost) == true)

        let notAsked = HealthReport(findings: [], records: Mac.allGood(), appUpdateChecking: nil)
        let notAskedCaveat = notAsked.caveats.first { $0.title.lowercased().contains("update") }
        #expect(notAskedCaveat?.title.contains("had not been asked") == true)
        #expect(notAskedCaveat?.body != declinedCaveat?.body)
    }

    /// Demo mode's caveat comes first, because it invalidates every other line on the page.
    @Test func aSamplePageSaysSoBeforeAnythingElse() {
        let report = HealthReport(machine: Mac.facts,
                                  findings: [],
                                  records: Mac.allGood(),
                                  appUpdateChecking: true,
                                  sampleResults: true)
        #expect(report.caveats.first?.body.contains("invented") == true)
        #expect(report.headline.contains("sample results"))
    }

    /// ⚠️ **There is no way to build a report with no caveats when there should be some.** The
    /// initialiser takes none, so a caller cannot suppress them — which is the failure this whole
    /// type exists to make impossible.
    @Test func onlyAFullyCheckedMacWithNoSerialGetsAPageWithNoCaveats() {
        let clean = HealthReport(machine: Mac.factsWithoutSerial,
                                 findings: [],
                                 records: Mac.allGood(),
                                 appUpdateChecking: true)
        // The machine block is still named, so there is still exactly one caveat about the page.
        #expect(clean.caveats.count == 1)
        #expect(clean.caveats[0].title.contains("names the Mac"))
    }
}

// MARK: - ⭐ The serial number

@Suite("The person's serial-number choice is honoured in one place")
struct HealthReportSerialTests {

    @Test func theSerialIsOnThePageWhenItIsAskedFor() {
        let report = HealthReport(machine: Mac.facts, includeSerial: true,
                                  findings: [], records: Mac.allGood())
        #expect(report.carriesSerialNumber)
        #expect(report.machine.contains { $0.value == "C02XY1234567" })
        #expect(report.caveats.contains { $0.title.contains("serial number") })
    }

    /// ⚠️ Off, it is **absent**, not blanked. A row reading "Serial number: —" is a row that tells
    /// the reader there was one.
    @Test func theSerialIsAbsentWhenItIsNot() {
        let report = HealthReport(machine: Mac.facts, includeSerial: false,
                                  findings: [], records: Mac.allGood())
        #expect(!report.carriesSerialNumber)
        #expect(!report.machine.contains { $0.value.contains("C02XY") })
        #expect(!report.machine.contains { $0.label.lowercased().contains("serial") })
        #expect(report.caveats.contains { $0.title.contains("names the Mac") })
    }

    /// A Mac that reports no serial number never claims to be carrying one — which is what stops a
    /// screen offering a switch that changes nothing.
    @Test func aMacWithNoSerialNumberNeverClaimsOne() {
        let report = HealthReport(machine: Mac.factsWithoutSerial, includeSerial: true,
                                  findings: [], records: Mac.allGood())
        #expect(!report.carriesSerialNumber)
    }

    @Test func aPageWithNoMachineBlockNamesNoMac() {
        let report = HealthReport(machine: nil, findings: [], records: Mac.allGood())
        #expect(report.machine.isEmpty)
        #expect(report.machineName == nil)
        #expect(!report.caveats.contains { $0.title.contains("serial") })
    }
}

// MARK: - ⛔ 4. Never a score

@Suite("Nothing the report produces is a grade")
struct HealthReportNeverAScoreTests {

    /// ⛔ No sentence this type can produce carries a number out of anything. The three vocabulary
    /// enums have three cases each and no rank, so there is nowhere for one to come from — this is
    /// the belt to that braces.
    @Test func noSentenceOnThePageIsAGrade() {
        var every: [String] = [HealthReport.everythingLooksFine,
                               HealthReport.auditIntro,
                               HealthReport.findingsIntro,
                               HealthReport.machineIntro,
                               HealthReport.nothingNeedsYou,
                               HealthReport.provenance]

        for demo in [false, true] {
            for count in [0, 1, 3] {
                let report = HealthReport(
                    machine: Mac.facts,
                    findings: (0..<count).map { _ in Mac.problem(.security) },
                    records: Mac.allGood(),
                    sampleResults: demo)
                every.append(report.headline)
                every.append(report.subtitle)
                every.append(report.title)
                every += report.caveats.flatMap { [$0.title, $0.body] }
                every += report.audit.map(\.line)
            }
        }

        let text = every.joined(separator: " ").lowercased()
        for grade in ["out of 100", "/100", "health score", "overall score", "score of", "score:"] {
            #expect(!text.contains(grade), "the report produced a grade: \(grade)")
        }
    }

    /// The status vocabulary has three words and no fourth, and none of them is a number. Restated
    /// here because the report is where a score would be most tempting to add.
    @Test func theStatusVocabularyIsStillThreeWords() {
        #expect(SectionStatus.allCases.count == 3)
        #expect(SectionStatus.allCases.map(\.label) == ["Good", "Needs attention", "Not checked"])
    }
}
