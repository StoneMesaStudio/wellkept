import Testing
import Foundation
// Plain import, not `@testable`. Everything Hardware promises is public — and a package module
// reached through an Xcode project is not always compiled for testing, which turns a missing
// `public` into a confusing build failure instead of a clear one.
import WellkeptCore

//  HardwareTests.swift
//  WellkeptTests
//
//  ⭐ **The six promises the Hardware section is built on, checked by a machine rather than
//  remembered.**
//
//  Each one is a rule somebody could undo in a single well-meaning line, and each one is invisible
//  from the outside when it breaks — a row in the wrong place, a zero where a shrug belongs, a
//  green chip above a sentence describing a failure. They are:
//
//   1. **The row order never changes.** `HardwareTopic.allCases` is the panel, top to bottom.
//   2. **A raw value is storage; a label is English.** The reading history is the one record in
//      this app that cannot be rebuilt, and the topic's raw value is its key.
//   3. **We could not look is never a zero, and never a "Good".**
//   4. **Worn but working is never a problem.** A battery in year four does not raise the section.
//   5. **A drive that declares a fault does.**
//   6. **The machine block can never carry a status.** A 2019 iMac is not broken for being one.
//
//  ⚠️ Nothing here reads this Mac. Every value below is typed out, so the suite gives the same
//  answer on an M3, on a 2019 Mac Pro, and on a build machine with no battery at all. The readers
//  that *do* touch hardware live in the app target and are exercised against fixtures there; this
//  file is about the vocabulary they all have to agree on.

// MARK: - 1. The five rows, in their fixed order

@Suite struct HardwareTopicOrderTests {

    /// ⚠️ **`allCases` IS the panel.** Drive · Battery · Memory · Restarts · Speed, and it never
    /// sorts — not by severity, not alphabetically, not "worst first". Worst-first is right for a
    /// list of findings and wrong for a fixed panel: somebody who learned that Battery is the
    /// second row should still find it there next week, on a week when the drive happens to have
    /// gone quiet.
    @Test func theFiveRowsAreInTheirFixedOrder() {
        #expect(HardwareTopic.allCases.map(\.rawValue) ==
                ["drive", "battery", "memory", "restarts", "speed"])
    }

    /// One at a time, so a failure names the row that moved instead of printing two arrays and
    /// leaving the diff to the reader.
    @Test func everyRowKeepsItsPlace() {
        #expect(HardwareTopic.drive.order    == 0)
        #expect(HardwareTopic.battery.order  == 1)
        #expect(HardwareTopic.memory.order   == 2)
        #expect(HardwareTopic.restarts.order == 3)
        #expect(HardwareTopic.speed.order    == 4)
    }

    @Test func thereAreFiveOfThem() {
        #expect(HardwareTopic.allCases.count == 5)
    }

    /// `order` is derived from `allCases`, so the two cannot disagree — but somebody could
    /// reasonably "optimise" `order` into a hand-written switch, and a hand-written switch is
    /// exactly the thing that gets one case wrong.
    @Test func orderAgreesWithTheListItIsDerivedFrom() {
        for (index, topic) in HardwareTopic.allCases.enumerated() {
            #expect(topic.order == index, "\(topic.rawValue) reports order \(topic.order), sits at \(index)")
        }
    }

    /// A reader can finish in any order it likes; the report puts the rows back. This is what lets
    /// the speed test take four seconds while the battery takes twelve milliseconds without the
    /// panel reshuffling on the slow days.
    @Test func aReportPutsTheRowsBackIntoTheFixedOrderWhateverOrderTheyArrivedIn() {
        let scrambled = [
            Reading(topic: .speed, headline: "Not measured."),
            Reading(topic: .drive, headline: "Apple's drive check says this drive is fine."),
            Reading(topic: .restarts, headline: "This Mac has not restarted on its own."),
            Reading(topic: .battery, headline: "This battery holds 95% of the charge it held when new."),
            Reading(topic: .memory, headline: "This Mac has enough memory for what you run on it."),
        ]
        let report = HardwareReport(facts: .unknown, readings: scrambled)
        #expect(report.readings.map(\.topic) == HardwareTopic.allCases)
    }

    /// Two readers reporting the same row is a wiring mistake, not a second opinion. The first one
    /// wins and the panel still has five rows — a duplicated Drive row would push Speed off the
    /// bottom of a face nobody scrolls.
    @Test func aDuplicatedRowIsDroppedRatherThanDrawnTwice() {
        let report = HardwareReport(facts: .unknown, readings: [
            Reading(topic: .drive, headline: "First."),
            Reading(topic: .drive, headline: "Second."),
            Reading(topic: .battery, headline: "Battery."),
        ])
        #expect(report.readings.count == 2)
        #expect(report.reading(.drive)?.headline == "First.")
    }

    /// Every row has its two pieces of English. A topic with an empty explanation ships a row with
    /// a blank line under it, and nothing else in the build would notice.
    @Test func everyRowHasItsWords() {
        for topic in HardwareTopic.allCases {
            #expect(!topic.label.isEmpty, "\(topic.rawValue) has no label")
            #expect(!topic.explanation.isEmpty, "\(topic.rawValue) has no explanation")
            // The explanation says what the reading MEANS. A one-word restatement of the label is
            // the shape that arrives when somebody fills the field in to make a compiler happy.
            #expect(topic.explanation.count > topic.label.count + 10,
                    "\(topic.rawValue): the explanation is barely longer than the label")
        }
    }

    @Test func noTwoRowsShareALabel() {
        #expect(Set(HardwareTopic.allCases.map(\.label)).count == 5)
    }
}

// MARK: - 2. A raw value is storage, a label is English

@Suite struct HardwareStorageKeyTests {

    /// ⚠️ **These five strings are written into `Readings.jsonl`, which cannot be rebuilt.**
    ///
    /// macOS keeps days of history; Wellkept keeps for ever, but only from the first launch. A
    /// released build that reads `battery` back as an unknown string does not lose a preference,
    /// it loses years of the only battery record that exists. Renaming one is a migration, and
    /// this is the line that makes somebody notice they are about to write one.
    @Test func everyTopicRawValueIsItsPermanentStorageKey() {
        #expect(HardwareTopic.drive.rawValue    == "drive")
        #expect(HardwareTopic.battery.rawValue  == "battery")
        #expect(HardwareTopic.memory.rawValue   == "memory")
        #expect(HardwareTopic.restarts.rawValue == "restarts")
        #expect(HardwareTopic.speed.rawValue    == "speed")
    }

    /// The label is what a person reads and John edits. Making a word better must stay a one-line
    /// change; deriving the label from the raw value would make it a schema change.
    @Test func labelsAreEnglishAndAreAllowedToDriftFromTheKeys() {
        #expect(HardwareTopic.drive.label    == "Drive")
        #expect(HardwareTopic.battery.label  == "Battery")
        #expect(HardwareTopic.memory.label   == "Memory")
        #expect(HardwareTopic.restarts.label == "Restarts")
        #expect(HardwareTopic.speed.label    == "Speed")

        // Capitalised for display, lower case in storage. Same word today; they are not the same
        // field, and nothing may start assuming they are.
        for topic in HardwareTopic.allCases {
            #expect(topic.label != topic.rawValue,
                    "\(topic.rawValue): label and storage key are byte-identical — deriving one from the other is one refactor away")
        }
    }

    /// What actually reaches the file. Encoding the whole `Reading` is the honest check: it is the
    /// shape `ReadingSample` stores, and it proves the key is the raw value rather than a case
    /// index that would renumber itself the day a sixth row is added.
    @Test func aReadingRoundTripsThroughJSONWithItsKeysIntact() throws {
        let reading = Reading(topic: .battery,
                              headline: "This battery holds 95% of the charge it held when it was new.",
                              measure: "95%",
                              number: ReadingNumber(95, ReadingNumber.percent),
                              severity: .information,
                              reason: "282 charge cycles of the roughly 1,000 this battery is rated for.",
                              details: [DetailPair("Cycle count", "282")])

        let data = try JSONEncoder().encode(reading)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"battery\""), "the topic was not stored as its raw value: \(text)")
        #expect(text.contains("\"information\""), "the severity was not stored as its raw value")

        let back = try JSONDecoder().decode(Reading.self, from: data)
        #expect(back == reading)
        #expect(back.number?.value == 95)
        #expect(back.number?.unit == ReadingNumber.percent)
    }

    /// Two readers spelling the same unit two ways makes the history uncomparable — "MB/s" against
    /// "MBps" is two lines on a chart that should be one. The constants exist so nobody types the
    /// string, and they have to stay distinct from each other.
    @Test func theUnitsAreNamedRatherThanTypedAndAreAllDifferent() {
        let units = [ReadingNumber.percent, ReadingNumber.megabytesPerSecond, ReadingNumber.cycles,
                     ReadingNumber.gigabytes, ReadingNumber.count, ReadingNumber.days]
        #expect(Set(units).count == units.count)
        #expect(ReadingNumber.percent == "%")
        #expect(ReadingNumber.megabytesPerSecond == "MB/s")
        // ⚠️ There is no degree unit, and there must not be one. The route to a die temperature is
        // undocumented, moved 62 → 79 → 58 °C in three minutes on an idle Mac, and nobody — Apple
        // included — publishes what is too hot. See HARDWARE-QUESTIONS.md.
        #expect(!units.contains { $0.contains("°") },
                "a temperature unit has appeared. The section reports thermal STATE, never degrees.")
    }
}

// MARK: - 3. "We could not look" is never a zero and never a Good

@Suite struct UnreadableIsNeverAZeroTests {

    /// ⚠️ **The rule the whole file exists for.** A drive with no readable wear counter is not a
    /// drive at 0% wear, and a Mac whose panic log we cannot open has not had zero panics. The
    /// initialiser drops the measure rather than trusting five readers to remember.
    @Test func anUnreadableRowCannotCarryAFigureEvenIfOneIsHandedIn() {
        let sneaky = Reading(topic: .drive,
                             headline: "Drive wear — this Mac does not report it.",
                             measure: "0%",
                             number: ReadingNumber(0, ReadingNumber.percent),
                             unreadable: .notReported)
        #expect(sneaky.measure == nil, "an unreadable row kept a measure — it will print as 0%")
        #expect(sneaky.number == nil, "an unreadable row kept a number — the history will record a zero we never measured")
    }

    /// A row we did not read says **Not checked**, never Good. Saying Good about something we
    /// never looked at is the single cheapest way for this app to lose the right to be believed.
    @Test func anUnreadableRowIsNotCheckedRatherThanGood() {
        for why in Unreadable.allCases {
            let row = Reading.unreadable(.restarts, why)
            #expect(row.status == .notChecked, "\(why.rawValue) reported \(row.status.label)")
            #expect(row.status != .good)
        }
    }

    /// The house sentence, in both flavours, about a named thing. One wording, so five sections
    /// cannot invent five ways of saying nothing.
    @Test func thereIsOneHouseSentenceForSomethingWeCouldNotRead() {
        #expect(Unreadable.notReported.sentence  == "This Mac does not report it.")
        #expect(Unreadable.notPermitted.sentence == "We were not allowed to look.")
        #expect(Unreadable.notReported.sentence(about: "Drive wear") == "Drive wear — this Mac does not report it.")

        // The default headline names the row, so a row never reads as a bare shrug.
        #expect(Reading.unreadable(.battery, .notReported).headline == "Battery — this Mac does not report it.")
        #expect(Reading.unreadable(.drive, .notReported, about: "Drive wear").headline
                == "Drive wear — this Mac does not report it.")
    }

    /// A detail we could not read is the same sentence, not a dash and not a "0".
    @Test func anUnreadableDetailIsASentenceRatherThanADash() {
        let pair = DetailPair("Cycle count", unreadable: .notReported)
        #expect(pair.value == "This Mac does not report it.")
        #expect(pair.value != "—")
        #expect(pair.value != "0")
        #expect(pair.sensitive == false)
    }

    /// ⚠️ **`.notReported` must never mark a check incomplete.** Drive wear is unreadable on every
    /// Apple silicon Mac ever made. If that counted as "could not see everything", Overview would
    /// carry a caveat on every modern Mac, for ever, that no button could clear — and a warning
    /// nothing can clear is how an app teaches people to ignore it.
    @Test func theMachineNotHavingSomethingToGiveKeepsTheCheckComplete() {
        let report = HardwareReport(facts: .unknown, readings: [
            Reading.unreadable(.drive, .notReported, about: "Drive wear"),
            Reading(topic: .battery, headline: "Fine."),
        ])
        #expect(report.complete, "an Apple silicon Mac is now permanently 'incomplete' over a counter no Mac has")
        #expect(report.status == .good)
        #expect(report.record.complete)
        #expect(report.record.section == .hardware)
    }

    /// Being refused is different, and it is the one that has to travel. Kernel panics are readable
    /// only by an administrator account — by account type, not by any privacy setting — so the row
    /// says so and the check honestly reports that it did not see everything.
    @Test func beingRefusedIsWhatMakesACheckIncomplete() {
        let report = HardwareReport(facts: .unknown, readings: [
            Reading.unreadable(.restarts, .notPermitted, about: "Kernel panics"),
            Reading(topic: .battery, headline: "Fine."),
        ])
        #expect(!report.complete)
        #expect(!report.record.complete)
        // Still Good: nothing we could see is wrong. Overview's job is to say both halves, not to
        // pick one.
        #expect(report.status == .good)
    }

    /// ⚠️ **Only the refused row gets a button**, and it is enforced in the initialiser rather than
    /// trusted to five call sites. A "Fix this" button under "this Mac does not report it" is a
    /// button that cannot work, on a row nothing can change.
    @Test func onlyARefusedRowMayCarryAButton() {
        let offered = Remedy(title: "Open Settings", settingsPane: "privacy")

        let notReported = Reading.unreadable(.drive, .notReported, remedy: offered)
        #expect(notReported.remedy == nil, "a row nothing can fix is offering a fix")

        let refused = Reading.unreadable(.restarts, .notPermitted, remedy: offered)
        #expect(refused.remedy == offered)

        // And a row that read fine cannot carry one either — there is nothing to remedy.
        let fine = Reading(topic: .battery, headline: "Fine.", remedy: offered)
        #expect(fine.remedy == nil)

        #expect(Unreadable.notReported.mayOfferRemedy == false)
        #expect(Unreadable.notPermitted.mayOfferRemedy == true)
        #expect(Unreadable.notReported.stillComplete == true)
        #expect(Unreadable.notPermitted.stillComplete == false)
    }

    /// A refused row is allowed to carry no button at all, and usually should. There is nothing
    /// honest to offer somebody whose account type is the obstacle.
    @Test func aRefusedRowWithNothingToOfferOffersNothing() {
        let row = Reading.unreadable(.restarts, .notPermitted, about: "Kernel panics",
                                     reason: "Only an administrator account can read these reports. No permission setting changes that.")
        #expect(row.remedy == nil)
        #expect(row.reason?.isEmpty == false)
    }

    /// A section that read nothing at all is Not checked. A section that read four rows and found
    /// that this Mac does not report the fifth **was** checked.
    @Test func anEmptyReportIsNotCheckedButAPartlyUnreadableOneIsNot() {
        #expect(HardwareReport(facts: .unknown, readings: []).status == .notChecked)
        #expect(HardwareReport(facts: .unknown, readings: [
            Reading.unreadable(.speed, .notReported),
        ]).status == .good)
    }

    /// What the section states once instead of five times.
    @Test func theReportListsWhatItCouldNotRead() {
        let report = HardwareReport(facts: .unknown, readings: [
            Reading.unreadable(.drive, .notReported, about: "Drive wear"),
            Reading(topic: .battery, headline: "Fine."),
            Reading.unreadable(.restarts, .notPermitted, about: "Kernel panics"),
        ])
        let unreadable = report.unreadableTopics
        #expect(unreadable.count == 2)
        #expect(unreadable.map(\.topic) == [.drive, .restarts])
        #expect(unreadable.map(\.why) == [.notReported, .notPermitted])
    }
}

// MARK: - 4. Worn but working is never a problem

@Suite struct WornButWorkingTests {

    /// ⚠️ **A battery past its rated cycle count, still holding 78%, is a battery doing its job in
    /// year four.** It says so plainly and stays `.information`, and the section stays Good.
    ///
    /// Marking it a problem produces a warning the user cannot clear by any action, on a machine
    /// that works — and every one of those teaches a person that this app's warnings can be
    /// ignored, which costs us the one warning that matters.
    ///
    /// ⚠️ `Vocabulary.swift`'s doc comment on `Severity` still offers "a battery at 78% health" as
    /// an example of `.attention`. That predates the 27 Aug decision and this test is the record of
    /// which one won: `Hardware.swift` and the section decision. The stale example is words in a
    /// comment; this is the behaviour.
    @Test func aWornBatteryDoesNotRaiseTheSection() {
        let worn = Reading(topic: .battery,
                           headline: "This battery holds 78% of the charge it held when it was new.",
                           measure: "78%",
                           number: ReadingNumber(78, ReadingNumber.percent),
                           severity: .information,
                           reason: "1,240 charge cycles of the roughly 1,000 it is rated for. It is working; it holds less than it did.",
                           details: [DetailPair("Cycle count", "1,240")])

        #expect(worn.status == .good)

        let report = HardwareReport(facts: .unknown, readings: [
            Reading(topic: .drive, headline: "Apple's drive check says this drive is fine."),
            worn,
        ])
        #expect(report.status == .good)
        // And nothing reaches Overview. A worn battery is not a thing that needs a person.
        #expect(report.overviewFinding == nil)
    }

    /// The same shape, one step further along: a drive that has written everything its maker rated
    /// it for and is still working. 118% worn is information, not a fault.
    @Test func aDriveAtMoreThanItsRatedWearIsStillNotAProblem() {
        let report = HardwareReport(facts: .unknown, readings: [
            Reading(topic: .drive,
                    headline: "Apple's drive check says this drive is fine.",
                    measure: "118% worn",
                    number: ReadingNumber(118, ReadingNumber.percent),
                    severity: .information),
        ])
        #expect(report.status == .good)
        #expect(report.overviewFinding == nil)
    }

    /// `.attention` is the middle case and it does raise the section — it is "not wrong yet,
    /// heading there", and it is the level a reader reaches for when it wants a person to look
    /// without claiming something has failed.
    @Test func attentionRaisesTheSectionAndProblemRaisesItToo() {
        for severity in [Severity.attention, .problem] {
            let report = HardwareReport(facts: .unknown, readings: [
                Reading(topic: .drive, headline: "Something.", severity: severity,
                        reason: "Because of a thing."),
            ])
            #expect(report.status == .needsAttention, "\(severity.rawValue) did not raise the section")
            #expect(report.overviewFinding?.severity == severity)
        }
    }
}

// MARK: - 5. A drive that declares a fault does raise it

@Suite struct FailingDriveTests {

    /// The one row this whole section exists to be able to print. Apple's own word, a `.problem`,
    /// the section flipped to Needs attention, and exactly one row sent to Overview.
    @Test func aDriveDeclaringAFaultRaisesTheSectionAndReachesOverview() {
        let failing = Reading(topic: .drive,
                              headline: "This drive says it is failing.",
                              severity: .problem,
                              reason: "The drive's own health check reports “Failing”. Copy anything you care about off it today.",
                              details: [DetailPair("Serial number", "0000000000000000", sensitive: true)])

        #expect(failing.status == .needsAttention)

        let report = HardwareReport(facts: .unknown, readings: [
            failing,
            Reading(topic: .battery, headline: "This battery holds 95% of the charge it held when new.",
                    measure: "95%", severity: .information),
        ])
        #expect(report.status == .needsAttention)
        #expect(report.overviewFinding?.severity == .problem)
        #expect(report.overviewFinding?.section == .hardware)
        #expect(report.overviewFinding?.title == "This drive says it is failing.")
        #expect(report.overviewFinding?.reason.isEmpty == false)
    }

    /// ⚠️ **The failing row deliberately carries no figure.** "Failing" beside "118% worn" gives a
    /// person a percentage to puzzle over instead of files to copy, and 118% invites a question
    /// that costs the afternoon. The number is still kept for the history.
    @Test func theFailingRowGivesFilesToCopyRatherThanAPercentageToPuzzleOver() {
        let failing = Reading(topic: .drive,
                              headline: "This drive says it is failing.",
                              measure: nil,
                              number: ReadingNumber(118, ReadingNumber.percent),
                              severity: .problem,
                              reason: "The drive's own health check reports “Failing”.")
        #expect(failing.measure == nil)
        #expect(failing.number != nil, "the history still wants the number even when the row does not show it")
    }

    /// ⚠️ **One row goes up to Overview, not one per finding.** Overview lists what needs you; a
    /// section that posts five rows there has turned the summary into a second copy of itself, and
    /// the section a person should actually open gets lost among its own details.
    @Test func onlyOneRowReachesOverviewHoweverManyThingsAreWrong() {
        let report = HardwareReport(facts: .unknown, readings: [
            Reading(topic: .drive, headline: "This drive says it is failing.", severity: .problem,
                    reason: "The drive's own health check reports “Failing”."),
            Reading(topic: .memory, headline: "macOS closed 3 running programs to free memory.",
                    severity: .attention, reason: "Three in the last week."),
            Reading(topic: .restarts, headline: "This Mac restarted on its own twice.",
                    severity: .attention, reason: "Two kernel panics in 30 days."),
        ])
        let finding = try? #require(report.overviewFinding)
        #expect(finding?.severity == .problem, "Overview led with something other than the worst thing")
        // The others are counted, not listed. The count is what tells a person the section is
        // worth opening without reproducing it on the summary.
        #expect(finding?.reason.contains("2 more in Hardware") == true,
                "the other two findings vanished instead of being counted: \(finding?.reason ?? "")")
    }

    /// A clean Mac sends nothing. Overview is a list of what needs you, and "nothing needs you" is
    /// an empty list rather than a row saying so.
    @Test func aCleanMacSendsNothingToOverview() {
        let report = HardwareReport(facts: .unknown, readings: HardwareTopic.allCases.map {
            Reading(topic: $0, headline: "\($0.label) is fine.", severity: .information)
        })
        #expect(report.overviewFinding == nil)
        #expect(report.status == .good)
    }

    /// The finding's identity is stable across draws. A `Finding` recomputed on every redraw is a
    /// new `UUID` every redraw, which is how a list animates itself to pieces.
    @Test func theOverviewRowKeepsItsIdentityBetweenReads() {
        let report = HardwareReport(facts: .unknown, readings: [
            Reading(topic: .drive, headline: "This drive says it is failing.", severity: .problem,
                    reason: "It said so itself."),
        ])
        #expect(report.overviewFinding?.id == report.overviewFinding?.id)
    }
}

// MARK: - 6. The machine block is inventory, never a verdict

@Suite struct MachineBlockCarriesNoStatusTests {

    private static let m3 = MachineFacts(
        name: "John's MacBook Air",
        modelName: "MacBook Air (15-inch, M3, 2024)",
        modelIdentifier: "Mac15,13",
        chip: "Apple M3",
        memory: "8 GB",
        driveSize: "494 GB",
        systemVersion: "macOS 26.6.2",
        systemMajorVersion: 26,
        inUseSince: Date(timeIntervalSince1970: 1_764_460_800),
        serialNumber: "C02XY1Z2ABCD")

    /// ⚠️ **A 2019 iMac is not broken for being a 2019 iMac.** The block is name, model, chip,
    /// memory, drive, macOS — inventory. There is no arrangement of those fields that constitutes a
    /// fault, so the section's chip is computed from the readings and from nothing else.
    @Test func anOldMacWithFiveHealthyRowsIsStillGood() throws {
        let old = MachineFacts(name: "The iMac", modelName: "MacBook Air (Retina, 13-inch, 2018)",
                               modelIdentifier: "MacBookAir8,1", chip: "1.6 GHz Dual-Core Intel Core i5",
                               memory: "8 GB", driveSize: "121 GB", systemVersion: "macOS 14.7",
                               systemMajorVersion: 14)

        let inTheFuture = try #require(Calendar.current.date(from: DateComponents(year: 2028, month: 3, day: 1)))
        // This Mac really is out of security updates by then — the harshest state the table has.
        #expect(old.standing(asOf: inTheFuture).severity == .problem)

        let report = HardwareReport(facts: old,
                                    readings: HardwareTopic.allCases.map {
                                        Reading(topic: $0, headline: "\($0.label) is fine.")
                                    },
                                    ranAt: inTheFuture)
        // The chip above the rows still says Good, because every row is good. What is out of date
        // is Apple's support for the macOS it can run, and that is a sentence, not a fault light.
        #expect(report.status == .good)
        // It does reach Overview — John, 2026-08-27: say it plainly, as security rather than as a
        // reason to buy a machine.
        #expect(report.overviewFinding?.severity == .problem)
        #expect(report.overviewFinding?.title == "This Mac no longer gets security updates")
    }

    /// Everything short of "the updates have actually stopped" is information, and reaches nobody.
    /// A Mac that will keep getting fixes for three more years does not need a badge for three
    /// years.
    @Test func stillPatchedIsNeverAWarning() throws {
        let today = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 27)))
        let stillPatched = MachineFacts(name: "The Mac Pro", modelName: "Mac Pro (2019)",
                                        modelIdentifier: "MacPro7,1", chip: "Intel Xeon W",
                                        memory: "96 GB", driveSize: "2 TB",
                                        systemVersion: "macOS 26.6", systemMajorVersion: 26)
        #expect(stillPatched.standing(asOf: today).severity == .information)

        let report = HardwareReport(facts: stillPatched,
                                    readings: [Reading(topic: .drive, headline: "Fine.")],
                                    ranAt: today)
        #expect(report.overviewFinding == nil)
        #expect(report.status == .good)
    }

    /// The block, as rows, in a fixed order — and the serial number is last and marked, so a
    /// screenshot taken from the top of the block does not carry it.
    @Test func theBlockIsAFixedListWithTheSerialLastAndFlagged() {
        let pairs = Self.m3.detailPairs
        #expect(pairs.map(\.label).prefix(7) ==
                ["Name", "Model", "Model identifier", "Chip", "Memory", "Drive", "macOS"])
        #expect(pairs.last?.label == "Serial number")
        #expect(pairs.last?.sensitive == true)
        #expect(pairs.filter(\.sensitive).count == 1)
        // Nothing in the block is a status word. If one ever appears here, the block has started
        // giving a verdict.
        let statusWords = SectionStatus.allCases.map(\.label)
        for pair in pairs {
            #expect(!statusWords.contains(pair.value), "the machine block is reporting a status: \(pair.label)")
        }
    }

    /// A Mac the shipped table has never heard of says so rather than guessing. A wrong marketing
    /// name is a lie on a screen a person might paste into an email to a repair shop.
    @Test func aMacNewerThanThisBuildSaysSo() {
        let future = MachineFacts(name: "New Mac", modelName: "Mac99,1", modelIdentifier: "Mac99,1",
                                  chip: "Apple M9", memory: "64 GB", driveSize: "4 TB",
                                  systemVersion: "macOS 31.0", systemMajorVersion: 31)
        #expect(future.model == nil)
        #expect(future.standing() == .unknown)
        #expect(future.standing().severity == .information)
    }

    /// The placeholder a face draws before anything has been read says so in every field. Nothing
    /// in it is a guess dressed as a fact.
    @Test func thePlaceholderIsHonestRatherThanPlausible() {
        #expect(MachineFacts.unknown.modelName == "Not checked yet")
        #expect(MachineFacts.unknown.chip == "Not checked yet")
        #expect(MachineFacts.unknown.serialNumber == nil)
        #expect(MachineFacts.unknown.systemMajorVersion == 0)
        #expect(MachineFacts.unknown.standing() == .unknown)
    }

    /// ⚠️ **A verdict taken inside a virtual machine is a verdict about a file on somebody's
    /// disk.** It outranks every reading, so a confident sentence about a battery that does not
    /// exist never reaches Overview.
    @Test func aVirtualMachineSaysSoAndOutranksEveryReading() {
        let vm = MachineFacts(name: "Test VM", modelName: "VirtualMac2,1", modelIdentifier: "VirtualMac2,1",
                              chip: "Apple Virtualization", memory: "8 GB", driveSize: "64 GB",
                              systemVersion: "macOS 26.0", systemMajorVersion: 26,
                              isVirtualMachine: true)
        let report = HardwareReport(facts: vm, readings: [
            Reading(topic: .drive, headline: "This drive says it is failing.", severity: .problem,
                    reason: "It said so itself."),
        ])
        #expect(report.overviewFinding?.title == "This is a virtual machine")
        #expect(vm.detailPairs.contains { $0.value == "A virtual machine, not real hardware" })
    }
}

// MARK: - The repair-shop copy

@Suite struct ClipboardTextTests {

    private static func report(ranAt: Date = Date(timeIntervalSince1970: 1_787_000_000)) -> HardwareReport {
        HardwareReport(
            facts: MachineFacts(name: "John's MacBook Air",
                                modelName: "MacBook Air (15-inch, M3, 2024)",
                                modelIdentifier: "Mac15,13", chip: "Apple M3", memory: "8 GB",
                                driveSize: "494 GB", systemVersion: "macOS 26.6.2",
                                systemMajorVersion: 26, serialNumber: "C02XY1Z2ABCD"),
            readings: [
                Reading(topic: .drive, headline: "This drive says it is failing.", severity: .problem,
                        reason: "The drive's own health check reports “Failing”.",
                        details: [DetailPair("Model", "APPLE SSD AP0512Z"),
                                  DetailPair("Serial number", "0000000000000000", sensitive: true)]),
            ],
            ranAt: ranAt)
    }

    /// ⚠️ **The caller must show this before it reaches the clipboard**, serial included. Something
    /// that quietly copies an identifying number is doing the thing this app exists to catch other
    /// software doing — so the text is one string, shown and pasted, and cannot drift.
    @Test func theTextCarriesTheMachineTheDateAndTheFinding() {
        let text = Self.report().clipboardText()
        #expect(text.contains("John's MacBook Air"))
        #expect(text.contains("MacBook Air (15-inch, M3, 2024)"))
        #expect(text.contains("Drive: This drive says it is failing."))
        #expect(text.contains("APPLE SSD AP0512Z"))
    }

    /// Leaving the serial out leaves out **every** identifying line, in the machine block and in
    /// the rows alike — one flag, filtered in one place, so the summary beside the preview cannot
    /// disagree with the preview.
    @Test func leavingTheSerialOutLeavesOutEveryIdentifyingLine() {
        let withIt = Self.report().clipboardText(includeSerial: true)
        let without = Self.report().clipboardText(includeSerial: false)
        #expect(withIt.contains("C02XY1Z2ABCD"))
        #expect(!without.contains("C02XY1Z2ABCD"))
        #expect(!without.contains("0000000000000000"), "a drive serial survived the exclusion")
        // Everything else is still there — this is a redaction, not a different report.
        #expect(without.contains("Drive: This drive says it is failing."))
    }

    /// A virtual machine says so at the top, before a repair shop reads a word of the readings.
    @Test func aVirtualMachineWarnsAtTheTopOfTheCopy() {
        let vm = HardwareReport(
            facts: MachineFacts(name: "Test VM", modelName: "VirtualMac2,1",
                                modelIdentifier: "VirtualMac2,1", chip: "Apple Virtualization",
                                memory: "8 GB", driveSize: "64 GB", systemVersion: "macOS 26.0",
                                systemMajorVersion: 26, isVirtualMachine: true),
            readings: [Reading(topic: .drive, headline: "Fine.")])
        let lines = vm.clipboardText().split(separator: "\n").map(String.init)
        #expect(lines.prefix(3).contains { $0.contains("Virtual machine") })
    }

    /// One date format for everything Core writes outside a view, so the clipboard and the reading
    /// history cannot each grow their own.
    @Test func thereIsOneDateFormatOutsideTheViews() {
        let stamp = ShortDate.stamp(Date(timeIntervalSince1970: 1_787_000_000))
        #expect(!stamp.isEmpty)
        #expect(Self.report().clipboardText().contains(stamp))
    }
}
