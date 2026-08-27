import Testing
import Foundation
@testable import WellkeptCore

//  MacModelsTests.swift
//  WellkeptCoreTests
//
//  ⭐ **The shipped table of Macs is the thing in this app most likely to rot, and it rots
//  silently.**
//
//  Nothing on a Mac knows when the model was released or which macOS is the last one it will get.
//  Apple publishes all of it in prose, on support pages, so it is typed out by hand in
//  `MacModels.swift` and updated once a year — in September, by whoever ships the next release.
//
//  A missed September is not a crash and not a wrong answer: an unknown identifier returns `nil`,
//  the view shows the raw identifier, and `standing` says plainly that Wellkept does not know this
//  model. **A missing entry is honest. A wrong entry is not** — a typed marketing name on a screen
//  a person may paste into an email to a repair shop is a lie with somebody's afternoon attached to
//  it. So this suite guards the shape of every row rather than the contents of any one of them:
//
//   - every entry has all four of its fields, and none of them is a placeholder;
//   - identifiers are unique, so a lookup cannot silently pick one of two answers;
//   - **"among the oldest supported" and "no longer patched" stay different states** — the first is
//     a fact about a working Mac, the second is the only one of the six that is a problem;
//   - `lastUpdated` is present, well-formed, and not in the future.
//
//  ⚠️ Nothing here reads this Mac. `hw.model` is never consulted, so the suite gives the same
//  answer on an M3, on a 2019 Mac Pro, and on a build machine.

// MARK: - Every row of the table

@Suite struct MacModelTableTests {

    /// Four fields, and every one of them filled in. The shape of mistake this catches is not a
    /// typo — it is a row pasted from the one above it and half-edited, which reads perfectly well
    /// in a diff of sixty-five near-identical lines.
    @Test func everyEntryHasAllFourOfItsFields() {
        for model in MacModels.all {
            #expect(!model.identifier.isEmpty, "a row has no identifier")
            #expect(!model.marketingName.isEmpty, "\(model.identifier) has no marketing name")
            #expect(!model.chipFamily.isEmpty, "\(model.identifier) has no chip family")
            #expect(model.releaseYear >= 2017,
                    "\(model.identifier): release year \(model.releaseYear) predates every Mac that can run macOS 14")
            #expect(model.releaseYear <= 2035,
                    "\(model.identifier): release year \(model.releaseYear) is a typo")
        }
    }

    /// An identifier is what `sysctl hw.model` returns — a name, a comma, a number. Anything else
    /// in that field will never match a real Mac, and a row that can never match is a row nobody
    /// will ever discover is wrong.
    @Test func everyIdentifierLooksLikeAnIdentifier() {
        for model in MacModels.all {
            #expect(model.identifier.contains(","),
                    "\(model.identifier) is not in `Name0,0` form — it cannot match `hw.model`")
            #expect(model.identifier.last?.isNumber == true, "\(model.identifier) does not end in a number")
            #expect(!model.identifier.contains(" "), "\(model.identifier) has a space in it")
        }
    }

    /// ⚠️ **Unique, or a lookup quietly picks one of two answers.** The table is folded into a
    /// dictionary with `uniquingKeysWith: { first, _ in first }`, which means a duplicate does not
    /// crash and does not warn — it just makes the second row unreachable for ever.
    @Test func noIdentifierAppearsTwice() {
        let identifiers = MacModels.all.map(\.identifier)
        let duplicates = Dictionary(grouping: identifiers, by: { $0 }).filter { $0.value.count > 1 }.keys
        #expect(duplicates.isEmpty, "duplicated identifiers, and the second row of each is dead: \(Array(duplicates))")
        #expect(Set(identifiers).count == identifiers.count)
    }

    /// A marketing name is Apple's own words, copied so a person matching their Mac against a
    /// support page sees the same string. A row whose "name" is just the identifier again is a row
    /// somebody added in a hurry, and it would print "Mac15,13" twice on the machine block.
    @Test func noMarketingNameIsJustTheIdentifierAgain() {
        for model in MacModels.all {
            #expect(model.marketingName != model.identifier,
                    "\(model.identifier) has no real name — the machine block would print the identifier twice")
        }
    }

    /// Duplicate marketing names are legitimate and expected: `iMac21,1` and `iMac21,2` are both
    /// "iMac (24-inch, M1, 2021)". Written down so nobody "fixes" it by inventing a distinguishing
    /// suffix Apple does not use.
    @Test func twoIdentifiersMaySharePublishedName() {
        let names = MacModels.all.map(\.marketingName)
        #expect(Set(names).count < names.count,
                "every name is now unique — if that is real it is fine, but Apple ships several identifiers per model")
    }

    /// The two halves of the table are the two halves of the audience, and each is internally
    /// consistent. Intel is where Hardware gets *more*, not less — real NVMe S.M.A.R.T. counters
    /// are readable there and are not readable on any Apple silicon Mac — so which half a row is in
    /// decides what the drive row can say.
    @Test func eachHalfOfTheTableAgreesWithItself() {
        for model in MacModels.appleSilicon {
            #expect(model.architecture == .appleSilicon, "\(model.identifier) is filed under Apple silicon")
            #expect(model.chipFamily != "Intel", "\(model.identifier) is an Apple silicon Mac with an Intel chip family")
        }
        for model in MacModels.intel {
            #expect(model.architecture == .intel, "\(model.identifier) is filed under Intel")
            #expect(model.chipFamily == "Intel", "\(model.identifier) is an Intel Mac with chip family \(model.chipFamily)")
            // Every Intel Mac Wellkept will ever see can run macOS 14, which means 2017 at the
            // earliest — the iMac Pro. Anything older cannot run this app at all.
            #expect(model.releaseYear >= 2017, "\(model.identifier) is older than any Mac that can run macOS 14")
        }
        #expect(MacModels.all.count == MacModels.appleSilicon.count + MacModels.intel.count)
    }

    /// The table is not thin. A count floor rather than an exact number: exact would have to be
    /// raised every September by the same edit that adds the models, which is a test that only ever
    /// fails for the right reason once and then gets edited to match.
    @Test func theTableCoversBothArchitecturesInEarnest() {
        #expect(MacModels.appleSilicon.count >= 40,
                "only \(MacModels.appleSilicon.count) Apple silicon models — M1 through M4 is around 47")
        #expect(MacModels.intel.count >= 18,
                "only \(MacModels.intel.count) Intel models — every Intel Mac that runs macOS 14 is 18")
    }

    /// `newestMacOS` is the field that turns "current" into "this is the last macOS this Mac can
    /// run". A value above the newest release this build has heard of is a typo, and it would
    /// silently make an old Mac report as current.
    @Test func noModelClaimsToRunAMacOSThisBuildHasNeverHeardOf() {
        for model in MacModels.all {
            guard let newest = model.newestMacOS else { continue }
            #expect(newest <= MacModels.newestKnownMacOS,
                    "\(model.identifier) claims macOS \(newest); this build knows up to \(MacModels.newestKnownMacOS)")
            #expect(newest >= 14, "\(model.identifier) claims macOS \(newest), below Wellkept's own floor of 14")
        }
    }

    /// Apple has dropped no Apple silicon Mac. Stated as a test because the day that changes is the
    /// September this file has to be edited, and a red line here is a better reminder than a note
    /// in a header nobody re-reads.
    @Test func appleHasDroppedNoAppleSiliconMacYet() {
        let dropped = MacModels.appleSilicon.filter { $0.newestMacOS != nil }
        #expect(dropped.isEmpty, """
            \(dropped.map(\.identifier)) now have an end-of-support macOS. If Apple really has \
            dropped them, this test is the reminder to check the rest of the September list too: \
            new models added, newestKnownMacOS bumped, securityUpdatesThrough extended, lastUpdated \
            bumped.
            """)
    }
}

// MARK: - The stamp on the table

@Suite struct TableFreshnessTests {

    /// ⚠️ **`lastUpdated` is how a future reader tells stale data from data that simply has not
    /// changed.** Without it, a table nobody has touched since 2026 and a table checked last week
    /// look identical.
    @Test func theTableSaysWhenItWasLastChecked() throws {
        #expect(!MacModels.lastUpdated.isEmpty)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let stamped = try #require(formatter.date(from: MacModels.lastUpdated),
                                   "lastUpdated is not an ISO date: “\(MacModels.lastUpdated)”")
        // A stamp in the future is a typo, and a typo here is the one kind of rot that reads as
        // freshness.
        #expect(stamped <= Date().addingTimeInterval(60 * 60 * 24),
                "lastUpdated is in the future: \(MacModels.lastUpdated)")

        let earliest = try #require(formatter.date(from: "2026-01-01"))
        #expect(stamped >= earliest, "lastUpdated predates the app: \(MacModels.lastUpdated)")
    }

    /// The security-update estimates. Every one of them is a guess and every sentence says "about";
    /// what a test can check is that they are ordered — a later macOS cannot stop being patched
    /// before an earlier one.
    @Test func aLaterMacOSIsPatchedForLongerThanAnEarlierOne() throws {
        let fourteen = try #require(MacModels.securityUpdatesThrough(forMacOS: 14))
        let fifteen = try #require(MacModels.securityUpdatesThrough(forMacOS: 15))
        let twentySix = try #require(MacModels.securityUpdatesThrough(forMacOS: 26))
        #expect(fourteen < fifteen)
        #expect(fifteen < twentySix)
        // 26 Tahoe is the terminal Intel release and its tail is deliberately generous: the
        // machines running it have nowhere to go, and overstating the tail is the safe direction to
        // be wrong in.
        #expect(twentySix >= 2029)
        // A release nobody has estimated returns nothing rather than a guess.
        #expect(MacModels.securityUpdatesThrough(forMacOS: 27) == nil)
    }

    /// Every macOS named by a `newestMacOS` has an estimate to go with it, or the sentence a person
    /// reads loses its date and becomes "it still gets security fixes" with no end in sight.
    @Test func everyEndOfLineMacOSHasAnEstimateBesideIt() {
        let claimed = Set(MacModels.all.compactMap(\.newestMacOS))
        for major in claimed.sorted() {
            #expect(MacModels.securityUpdatesThrough(forMacOS: major) != nil, """
                macOS \(major) is the last release for at least one model in the table, and \
                securityUpdatesThrough has no estimate for it — those Macs will be told only that \
                they “still get security fixes”, with no year.
                """)
        }
    }
}

// MARK: - The six states, and the two that must stay apart

@Suite struct SupportStandingTests {

    private func date(_ year: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: 6, day: 1)))
    }

    /// ⚠️ **"Among the oldest supported" and "no longer patched" are different states and must
    /// never be merged.** John, 2026-08-27: *"Not about fear, it is about security. Why not be
    /// honest? We are not selling them a new machine, we are protecting them."*
    ///
    /// The first is a fact about a Mac that is working and fully patched — first in line to be
    /// dropped, and nothing more. The second is the only state in this enum where something a
    /// person cares about has actually stopped.
    @Test func theOldestSupportedMacAndTheUnpatchedOneAreNotTheSameThing() {
        let oldest = SupportStanding.oldestSupported(macOS: 26)
        let unpatched = SupportStanding.noLongerUpdated(newestItCanRun: 14, since: 2026)

        #expect(oldest != unpatched)
        #expect(oldest.label != unpatched.label)
        #expect(oldest.sentence != unpatched.sentence)

        // The distinction that actually reaches the user: one is a badge, the other is a sentence.
        #expect(oldest.severity == .information)
        #expect(unpatched.severity == .problem)

        // And the words carry it. The supported Mac is told it still gets everything; the other is
        // told what stopped, in the language of security rather than of obsolescence.
        #expect(oldest.sentence.contains("still gets every update"))
        #expect(unpatched.sentence.contains("stay open"))
        #expect(!unpatched.sentence.lowercased().contains("upgrade"))
        #expect(!unpatched.sentence.lowercased().contains("buy"))
    }

    /// ⚠️ **Exactly one of the six is a problem.** A badge that sits on a working Mac for three
    /// years is a badge people learn to scroll past, and then the one that matters is scrolled past
    /// with it.
    @Test func onlyOneOfTheSixStatesIsAProblem() {
        let all: [SupportStanding] = [
            .current,
            .oldestSupported(macOS: 26),
            .lastRelease(macOS: 26, securityUpdatesThrough: 2029),
            .behind(newestItCanRun: 15, securityUpdatesThrough: 2027),
            .noLongerUpdated(newestItCanRun: 14, since: 2026),
            .unknown,
        ]
        let problems = all.filter { $0.severity == .problem }
        #expect(problems.count == 1)
        #expect(problems.first == .noLongerUpdated(newestItCanRun: 14, since: 2026))

        // Six states, six sentences, six labels. A shared sentence means two different situations
        // read identically to the person in one of them.
        #expect(Set(all.map(\.sentence)).count == 6)
        #expect(Set(all.map(\.label)).count == 6)
        for standing in all {
            #expect(!standing.sentence.isEmpty)
            #expect(!standing.label.isEmpty)
        }
    }

    /// Every year in these sentences is an estimate, and every sentence says so. Dropping the word
    /// "about" turns a guess into a promise, and the guess is deliberately generous — telling
    /// somebody their Mac is unprotected while it is still being patched is the scareware move this
    /// whole app exists to not be.
    @Test func everyDatedSentenceAdmitsItIsAnEstimate() {
        #expect(SupportStanding.lastRelease(macOS: 26, securityUpdatesThrough: 2029).sentence.contains("about 2029"))
        #expect(SupportStanding.behind(newestItCanRun: 15, securityUpdatesThrough: 2027).sentence.contains("about 2027"))
        // With no estimate the sentence loses the year rather than inventing one.
        #expect(!SupportStanding.lastRelease(macOS: 26, securityUpdatesThrough: nil).sentence.contains("about"))
    }

    /// A Mac newer than this build says so. This is the branch that makes a missed September
    /// harmless instead of wrong.
    @Test func anUnknownModelSaysItIsUnknownRatherThanGuessing() {
        #expect(MacModels.model(for: "Mac99,1") == nil)
        #expect(MacModels.marketingName(for: "Mac99,1") == nil)
        #expect(MacModels.standing(for: "Mac99,1", runningMacOS: 31) == .unknown)
        #expect(SupportStanding.unknown.sentence.contains("does not recognise"))
        #expect(SupportStanding.unknown.severity == .information)
    }

    /// The lookup that the machine block runs on every launch.
    @Test func theTableAnswersForARealMac() {
        #expect(MacModels.marketingName(for: "Mac15,13") == "MacBook Air (15-inch, M3, 2024)")
        #expect(MacModels.model(for: "Mac15,13")?.chipFamily == "M3")
        #expect(MacModels.model(for: "Mac15,13")?.architecture == .appleSilicon)
        #expect(MacModels.model(for: "MacPro7,1")?.architecture == .intel)
    }

    /// An Intel Mac that has run out of estimated security updates. The date is what moves it, so
    /// the same machine is `.behind` today and `.noLongerUpdated` two years from now — which is the
    /// whole reason `asOf:` exists rather than the function reading the clock itself.
    @Test func aMacGoesOutOfSupportOnTheCalendarRatherThanAllAtOnce() throws {
        // MacBookAir8,1 stops at macOS 14, whose fixes are estimated to end in 2026.
        #expect(MacModels.standing(for: "MacBookAir8,1", runningMacOS: 14, asOf: try date(2026))
                == .behind(newestItCanRun: 14, securityUpdatesThrough: 2026))
        #expect(MacModels.standing(for: "MacBookAir8,1", runningMacOS: 14, asOf: try date(2028))
                == .noLongerUpdated(newestItCanRun: 14, since: 2026))
    }

    /// A Mac on the last macOS it will ever run, still patched, is told exactly that — and it is
    /// not a warning. Four Intel Macs are in this state for about three more years, and they are a
    /// real part of the audience rather than an edge case.
    @Test func theLastMacOSForAMacIsAStatementNotAWarning() throws {
        let standing = MacModels.standing(for: "MacPro7,1", runningMacOS: 26, asOf: try date(2026))
        #expect(standing == .lastRelease(macOS: 26, securityUpdatesThrough: 2029))
        #expect(standing.severity == .information)
    }

    /// Apple silicon: nothing has been dropped, so the only distinction left is whether the model
    /// is first in line — and being first in line is a fact, never a warning.
    @Test func anUndroppedMacIsCurrentOrFirstInLineAndNeitherIsAFault() throws {
        let firstInLine = MacModels.standing(for: "MacBookAir10,1", runningMacOS: 26, asOf: try date(2026))
        let newer = MacModels.standing(for: "Mac16,13", runningMacOS: 26, asOf: try date(2026))

        #expect(firstInLine == .oldestSupported(macOS: 26))
        #expect(newer == .current)
        #expect(firstInLine.severity == .information)
        #expect(newer.severity == .information)
        #expect(firstInLine != newer)
    }

    /// Somebody who simply has not updated is not out of support. `runningMacOS` is what is booted;
    /// `newestMacOS` is what the machine could run. Conflating them would tell a person on macOS 14
    /// with an M3 that their Mac is finished.
    @Test func notHavingUpdatedIsNotTheSameAsNotBeingAbleTo() throws {
        let m3OnOldMacOS = MacModels.standing(for: "Mac15,13", runningMacOS: 14, asOf: try date(2028))
        #expect(m3OnOldMacOS.severity == .information)
        #expect(m3OnOldMacOS != .noLongerUpdated(newestItCanRun: 14, since: 2026))
    }
}
