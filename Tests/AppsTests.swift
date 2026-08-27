import Testing
import Foundation
import WellkeptCore

// Plain import, not `@testable`. Everything the Apps vocabulary promises is public — and a package
// module compiled for testing is not the module the app links, so a rule that only holds under
// `@testable` is a rule that does not hold.

//  AppsTests.swift
//  WellkeptTests
//
//  ⭐ **The promises the Apps vocabulary is built on, checked by a machine rather than remembered.**
//
//  Five readers are written against `Apps.swift` in parallel by people who will not read each
//  other's files. Every rule below is one somebody could undo in a single well-meaning line, and
//  every one of them is invisible from the outside when it breaks — a count with no denominator, an
//  app called outdated on a version nobody could compare, a section that went amber on a Mac where
//  nothing was wrong.
//
//   1. **The row order never changes**, and raw values are storage while labels are English.
//   2. **There is no "outdated"**, and `.newerAvailable` cannot exist without a version.
//   3. **A count never travels without its denominator.**
//   4. **Apps can never turn Overview amber**, by any route.
//   5. **We could not look is never a zero and never a Good.**
//   6. **One row goes up to Overview**, never one per app.
//
//  ⚠️ Nothing here reads this Mac. Every value is typed out, so the suite gives the same answer on
//  an M3, on an Intel Mac Pro, and on a build machine.

// MARK: - Fixtures

private enum Sample {

    static func app(_ name: String,
                    _ bundleID: String,
                    update: UpdateStanding = .notChecked,
                    origin: AppOrigin = .developerID,
                    architecture: AppArchitecture = .universal) -> InstalledApp {
        InstalledApp(name: name,
                     bundleID: bundleID,
                     version: "1.0",
                     build: "100",
                     bytes: 12_345_678,
                     architecture: architecture,
                     signedBy: .developer("Someone Ltd"),
                     origin: origin,
                     update: update)
    }

    /// Thirteen checked apps, four of them with a newer version, plus eleven that could not be
    /// checked — the shape this Mac actually produced on 2026-08-27.
    static var measuredMac: AppsInventory {
        var apps: [InstalledApp] = []
        for i in 0..<4 {
            apps.append(app("Behind \(i)", "test.behind.\(i)", update: .newerAvailable("2.0")))
        }
        for i in 0..<9 {
            apps.append(app("Current \(i)", "test.current.\(i)", update: .current))
        }
        for i in 0..<11 {
            apps.append(app("Unknown \(i)", "test.unknown.\(i)",
                            update: .couldNotTell(.noSourceToAsk)))
        }
        return AppsInventory(apps: apps, otherBundles: 391)
    }
}

// MARK: - 1. The rows, and what is storage versus what is English

@Suite struct AppsRowOrderTests {

    /// ⚠️ **`allCases` IS the panel, top to bottom, and it never sorts.** A person who learns that
    /// updates are the third row should still find them there next week, on a Mac where nothing
    /// happens to have an update.
    @Test func theRowOrderIsFixed() {
        #expect(AppsTopic.allCases == [
            .installed, .macOS, .updates, .stoppedWorking, .removedLeftovers,
        ])
        #expect(AppsTopic.allCases.map(\.order) == Array(0..<AppsTopic.allCases.count))
    }

    /// Raw values are written into the check history, which cannot be rebuilt. Renaming one is a
    /// migration; renaming a label is a one-line edit John may make whenever he likes.
    @Test func rawValuesArePermanentAndLabelsAreSeparate() {
        #expect(AppsTopic.installed.rawValue == "installed")
        #expect(AppsTopic.macOS.rawValue == "macOS")
        #expect(AppsTopic.updates.rawValue == "updates")
        #expect(AppsTopic.stoppedWorking.rawValue == "stoppedWorking")
        #expect(AppsTopic.removedLeftovers.rawValue == "removedLeftovers")

        // Every label is English, and none of them is the raw value.
        for topic in AppsTopic.allCases {
            #expect(!topic.label.isEmpty)
            #expect(!topic.explanation.isEmpty)
            #expect(topic.label != topic.rawValue || topic == .macOS)
        }
    }

    /// A report built out of order comes back in order. The inventory call alone takes 7–8 seconds
    /// and the update check is slower still; the panel must not depend on who won the race.
    @Test func aReportPutsRowsBackIntoTheFixedOrder() {
        let report = AppsReport(inventory: .notCheckedYet, rows: [
            AppsRow(topic: .removedLeftovers, headline: "Nothing was left behind."),
            AppsRow(topic: .installed, headline: "31 apps."),
            AppsRow(topic: .updates, headline: "Nothing to do."),
        ])
        #expect(report.rows.map(\.topic) == [.installed, .updates, .removedLeftovers])
    }

    @Test func aDuplicateRowIsDropped() {
        let report = AppsReport(inventory: .notCheckedYet, rows: [
            AppsRow(topic: .installed, headline: "First."),
            AppsRow(topic: .installed, headline: "Second."),
        ])
        #expect(report.rows.count == 1)
        #expect(report.row(.installed)?.headline == "First.")
    }

    /// Duplicate apps are dropped by identifier, first one wins. Safari is added by hand and an
    /// inventory that also found it would otherwise list it twice.
    @Test func aDuplicateAppIsDropped() {
        let inventory = AppsInventory(apps: [
            Sample.app("Safari", "com.apple.Safari"),
            Sample.app("Safari (again)", "com.apple.Safari"),
        ])
        #expect(inventory.apps.count == 1)
        #expect(inventory.apps.first?.name == "Safari")
    }
}

// MARK: - 2. There is no "outdated"

@Suite struct UpdateStandingTests {

    /// ⚠️ **The guard that stops Pages 15.3.1 being reported as behind Pages 15.3.** The only way to
    /// claim a newer version exists is to name it, so a reader that could not name one is left with
    /// `.current` or `.couldNotTell` — and neither of those is an accusation.
    @Test func claimingANewerVersionRequiresNamingIt() {
        let standing = UpdateStanding.newerAvailable("2.1")
        #expect(standing.newerVersion == "2.1")
        #expect(standing.hasNewerVersion)
        #expect(standing.label.contains("2.1"))

        // Nothing else in the set can claim it.
        for other: UpdateStanding in [.current, .keepsItselfUpToDate, .notChecked,
                                      .couldNotTell(.askFailed)] {
            #expect(other.newerVersion == nil)
            #expect(!other.hasNewerVersion)
        }
    }

    /// "We did not look" and "we looked and could not tell" are different sentences, and only the
    /// first one has a switch behind it. Merging them is how a switched-off feature ends up
    /// reported as a limitation of the app.
    @Test func notCheckedIsNotTheSameAsCouldNotTell() {
        #expect(UpdateStanding.notChecked != UpdateStanding.couldNotTell(.askFailed))
        #expect(!UpdateStanding.notChecked.isInScope)
        #expect(UpdateStanding.couldNotTell(.askFailed).isInScope)
    }

    /// ⚠️ Only two standings count as checked. Folding `.keepsItselfUpToDate` in would inflate the
    /// denominator of the Overview sentence with apps nobody compared anything for.
    @Test func onlyARealComparisonCountsAsChecked() {
        #expect(UpdateStanding.current.wasChecked)
        #expect(UpdateStanding.newerAvailable("9").wasChecked)
        #expect(!UpdateStanding.keepsItselfUpToDate.wasChecked)
        #expect(!UpdateStanding.notChecked.wasChecked)
        #expect(!UpdateStanding.couldNotTell(.versionsNotComparable).wasChecked)
    }

    /// A TestFlight build and an app macOS updates are not gaps in our coverage — they are
    /// questions that do not apply. Counting them as failures makes the figure worse than the truth.
    @Test func theTwoDoesNotApplyReasonsAreOutOfScope() {
        #expect(!UpdateUnknown.testFlightBuild.isInScope)
        #expect(!UpdateUnknown.shipsWithMacOS.isInScope)
        #expect(UpdateUnknown.noSourceToAsk.isInScope)
        #expect(UpdateUnknown.versionsNotComparable.isInScope)
        #expect(UpdateUnknown.askFailed.isInScope)
    }

    /// Every "could not tell" carries a reason. A bare shrug is a row a person cannot disagree with.
    @Test func everyCouldNotTellCarriesAReason() {
        for why in UpdateUnknown.allCases {
            #expect(!why.label.isEmpty)
            #expect(UpdateStanding.couldNotTell(why).label == why.label)
        }
    }

    /// Round-trips as JSON. The check history is written to disk and cannot be rebuilt.
    @Test func standingsSurviveARoundTrip() throws {
        let all: [UpdateStanding] = [.current, .newerAvailable("3.4.1"), .keepsItselfUpToDate,
                                     .couldNotTell(.versionsNotComparable), .notChecked]
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode([UpdateStanding].self, from: data) == all)
    }
}

// MARK: - 3. ⭐ A count never travels without its denominator

@Suite struct UpdateCoverageTests {

    /// ⚠️ **The rule John asked for on 2026-08-27.** A bare "4 apps are out of date" hides the
    /// eleven we could not check, in the direction that makes the app look more capable than it is.
    /// The sentence has to name both numbers.
    @Test func theOverviewSentenceCarriesItsDenominator() {
        let tally = UpdateTally.measuring(Sample.measuredMac.apps)
        #expect(tally.newerAvailable == 4)
        #expect(tally.coverage.checked == 13)
        #expect(tally.coverage.checkable == 24)
        #expect(tally.sentence == "4 of the 13 apps we could check have a newer version.")
        #expect(tally.sentenceWithCoverage.contains("11 more apps could not be checked."))
    }

    /// The numerator can never exceed the number of apps it is a fraction of. A figure larger than
    /// its own denominator is arithmetic nobody can read.
    @Test func theCountIsClampedToWhatWasChecked() {
        let tally = UpdateTally(newerAvailable: 99, coverage: UpdateCoverage(checked: 3, checkable: 8))
        #expect(tally.newerAvailable == 3)

        let coverage = UpdateCoverage(checked: 40, checkable: 10)
        #expect(coverage.checked == 10)
        #expect(coverage.checkable == 10)
        #expect(coverage.unchecked == 0)
    }

    /// Negative anything is a bug upstream, and it must not reach a screen.
    @Test func negativesAreClampedToZero() {
        let coverage = UpdateCoverage(checked: -5, checkable: -9)
        #expect(coverage.checked == 0)
        #expect(coverage.checkable == 0)
        #expect(coverage.isEmpty)
    }

    /// ⚠️ **Never report zero because we could not look.** With nothing checked, the sentence says
    /// so — it does not say "none of your apps has an update", which is the confident wrong answer.
    @Test func nothingCheckedNeverReadsAsNothingFound() {
        let tally = UpdateTally(newerAvailable: 0, coverage: UpdateCoverage(checked: 0, checkable: 9))
        #expect(!tally.sentence.contains("None of"))
        #expect(tally.sentence.contains("could not"))
        #expect(tally.sentence.contains("9"))
    }

    /// The clean answer still carries the scope, and it still counts.
    @Test func fullCoverageStillSaysHowMany() {
        let coverage = UpdateCoverage(checked: 6, checkable: 6)
        #expect(coverage.unchecked == 0)
        let tally = UpdateTally(newerAvailable: 0, coverage: coverage)
        #expect(tally.sentence == "None of the 6 apps we could check has a newer version.")
        // Nothing to caveat, so nothing is padded on.
        #expect(tally.sentenceWithCoverage == tally.sentence)
    }

    /// One is a word, not a digit, in both halves. English that reads "1 of the 1 apps" is English
    /// nobody wrote on purpose.
    @Test func theSingularReadsLikeEnglish() {
        let one = UpdateTally(newerAvailable: 1, coverage: UpdateCoverage(checked: 1, checkable: 4))
        #expect(one.sentence == "The one app we could check has a newer version.")
        #expect(one.sentenceWithCoverage.contains("3 more apps could not be checked."))

        let none = UpdateTally(newerAvailable: 0, coverage: UpdateCoverage(checked: 1, checkable: 1))
        #expect(none.sentence == "The one app we could check is current.")
    }

    /// Coverage is derived from the apps, so it can never disagree with the list it is about.
    @Test func coverageIsMeasuredFromTheApps() {
        let inventory = AppsInventory(apps: [
            Sample.app("A", "a", update: .current),
            Sample.app("B", "b", update: .newerAvailable("2")),
            Sample.app("C", "c", update: .keepsItselfUpToDate),
            Sample.app("D", "d", update: .couldNotTell(.shipsWithMacOS)),
            Sample.app("E", "e", update: .notChecked),
        ])
        #expect(inventory.coverage.checked == 2)
        #expect(inventory.coverage.checkable == 3)   // A, B, C — not D (does not apply), not E
        #expect(inventory.tally.newerAvailable == 1)
    }
}

// MARK: - 4. ⭐ Apps can never turn Overview amber

@Suite struct AppsNeverAmberTests {

    /// ⚠️ **The 2026-08-27 ruling, held in the type.** Without vulnerability data an old app is not
    /// dangerous, and a version behind is not something wrong. There is no argument on `AppsRow`
    /// that can carry a worse severity, and this test fails the moment somebody adds one.
    @Test func everyRowIsInformationWhateverItSays() {
        let rows = [
            AppsRow(topic: .installed, headline: "31 apps."),
            AppsRow(topic: .updates, headline: "4 have a newer version.", measure: "4 of 13"),
            AppsRow(topic: .stoppedWorking, headline: "Two apps crashed."),
            AppsRow.unreadable(.removedLeftovers, .notPermitted),
        ]
        for row in rows {
            #expect(row.severity == .information)
            #expect(row.severity == AppsRow.severityCeiling)
            #expect(row.status != .needsAttention)
        }
    }

    /// The section chip cannot say Needs attention either — not with four updates, not with crashes.
    @Test func theSectionNeverSaysNeedsAttention() {
        let report = AppsReport(inventory: Sample.measuredMac, rows: [
            AppsRow(topic: .installed, headline: "24 apps."),
            AppsRow(topic: .updates, headline: "Four have a newer version."),
        ])
        #expect(report.status == .good)
        #expect(report.record.status == .good)
    }

    /// And neither can the row it hands to Overview. `AppState.needsYou` lists `.attention` and
    /// above, so this row correctly never appears under "what needs you".
    @Test func theOverviewRowIsAlwaysInformation() throws {
        let report = AppsReport(inventory: Sample.measuredMac, rows: [
            AppsRow(topic: .updates, headline: "Four have a newer version."),
        ])
        let finding = try #require(report.overviewFinding)
        #expect(finding.severity == .information)
        #expect(finding.section == .apps)
    }
}

// MARK: - 5. We could not look is never a zero and never a Good

@Suite struct AppsUnreadableTests {

    /// A row we did not read cannot carry a figure, whatever a reader hands in.
    @Test func anUnreadableRowDropsItsMeasure() {
        let row = AppsRow(topic: .stoppedWorking,
                          headline: "Ignored.",
                          measure: "0 crashes",
                          unreadable: .notPermitted)
        #expect(row.measure == nil)
        #expect(row.status == .notChecked)
    }

    /// Only a refusal a person could lift makes the check incomplete, and only that one gets a
    /// button. Nothing in Apps needs Full Disk Access, so in practice no row here carries either.
    @Test func onlyALiftableRefusalCostsCompleteness() {
        let notReported = AppsRow.unreadable(.macOS, .notReported,
                                             remedy: Remedy(title: "Open Settings"))
        let notGrantable = AppsRow.unreadable(.macOS, .notGrantable,
                                              remedy: Remedy(title: "Open Settings"))
        let notPermitted = AppsRow.unreadable(.macOS, .notPermitted,
                                              remedy: Remedy(title: "Open Settings"))

        #expect(notReported.complete)
        #expect(notGrantable.complete)
        #expect(!notPermitted.complete)

        #expect(notReported.remedy == nil)
        #expect(notGrantable.remedy == nil)
        #expect(notPermitted.remedy?.title == "Open Settings")
    }

    /// The house sentence, not a dash and not a zero.
    @Test func anUnreadableRowUsesTheHouseSentence() {
        let row = AppsRow.unreadable(.updates, .notReported, about: "A newer version")
        #expect(row.headline == "A newer version — this Mac does not report it.")
    }

    /// A bundle count nobody took is not a zero. `nil` prints the house sentence instead.
    @Test func anUncountedBundleTotalIsNotZero() {
        let inventory = AppsInventory(apps: [Sample.app("A", "a")], otherBundles: nil)
        let pair = inventory.detailPairs.first { $0.label.contains("Other bundles") }
        #expect(pair?.value == Unreadable.notReported.sentence)
        #expect(pair?.value.contains("0") == false)
    }

    /// An app whose size was never weighed has no size text — never "0 bytes".
    @Test func anUnweighedAppHasNoSize() {
        let app = InstalledApp(name: "Thing", bundleID: "thing", bytes: nil)
        #expect(app.sizeText == nil)
        #expect(app.versionText == Unreadable.notReported.sentence)
    }
}

// MARK: - 6. One row for Overview, and what an app's line says

@Suite struct AppsOverviewAndLineTests {

    /// ⚠️ **One row, not one per app.** Four apps with newer versions produce one finding, and its
    /// reason carries the denominator — because there is nothing else there to draw.
    @Test func fourUpdatesProduceOneRowCarryingItsDenominator() throws {
        let report = AppsReport(inventory: Sample.measuredMac, rows: [
            AppsRow(topic: .updates, headline: "Four."),
        ])
        let finding = try #require(report.overviewFinding)
        #expect(finding.title == "4 apps have a newer version")
        #expect(finding.reason.contains("4 of the 13 apps we could check"))
        #expect(finding.reason.contains("11 more apps could not be checked"))
    }

    /// Nothing to say, nothing sent. Overview lists what needs you, and an app section with no
    /// updates has nothing for it.
    @Test func nothingToSayMeansNoRow() {
        let inventory = AppsInventory(apps: [
            Sample.app("A", "a", update: .current),
            Sample.app("B", "b", update: .couldNotTell(.noSourceToAsk)),
        ])
        let report = AppsReport(inventory: inventory, rows: [
            AppsRow(topic: .updates, headline: "Nothing to do."),
        ])
        #expect(report.overviewFinding == nil)
    }

    /// The section's own sentence never states the count without the coverage beside it.
    @Test func theSectionSummaryCarriesTheCoverage() {
        let report = AppsReport(inventory: Sample.measuredMac, rows: [
            AppsRow(topic: .installed, headline: "24 apps."),
        ])
        #expect(report.summary.contains("24 apps are installed."))
        #expect(report.summary.contains("4 of the 13 apps we could check"))
        #expect(report.summary.contains("could not be checked"))
    }

    /// **Three facts on an app's line, and these three.** Everything more exact is behind Options.
    @Test func anAppsLineCarriesThreeFacts() {
        let app = Sample.app("Pages", "com.apple.iWork.Pages",
                             update: .newerAvailable("15.4"), origin: .appStore)
        #expect(app.lineFacts.count == 3)
        #expect(app.lineFacts == ["1.0", "Mac App Store", "Version 15.4 is available"])
        // The exact material is one layer down, and there is more of it than a line could hold.
        #expect(app.detailPairs.count > app.lineFacts.count)
    }

    /// An app's row lists who signed it and **never claims to have verified it**. `spctl` calls 11
    /// of 31 apps here failures, 8 of them purely for carrying a Finder tag.
    @Test func theSignerIsNamedAndNothingIsVerified() {
        let app = Sample.app("Thing", "thing")
        let signer = app.detailPairs.first { $0.label == "Signed by" }
        #expect(signer?.value == "Someone Ltd")

        for word in ["verified", "valid", "trusted", "safe", "tampered"] {
            for pair in app.detailPairs {
                #expect(!pair.value.lowercased().contains(word))
                #expect(!pair.label.lowercased().contains(word))
            }
        }
    }

    /// Reading a signature can fail, and failing is a sentence rather than an accusation.
    @Test func anUnreadableSignatureSaysSoInTheHouseWords() {
        #expect(SignedBy.unreadable(.notReported).label == Unreadable.notReported.sentence)
        #expect(SignedBy.unreadable(.notReported).name == nil)
        #expect(!SignedBy.unreadable(.notReported).wasRead)
        #expect(SignedBy.apple.name == "Apple")
        #expect(SignedBy.notSigned.name == nil)
    }

    /// Intel-only is a labelled fact with an explanation, and there is no route from it to a
    /// severity — see the note on `AppArchitecture`.
    @Test func intelOnlyIsAFactNotAWarning() {
        #expect(AppArchitecture.intelOnly.label == "Intel only")
        #expect(AppArchitecture.intelOnly.explanation?.contains("Rosetta") == true)
        #expect(AppArchitecture.universal.explanation == nil)
        for word in ["stop working", "no longer", "soon", "must"] {
            #expect(AppArchitecture.intelOnly.explanation?.lowercased().contains(word) != true)
        }
    }

    /// The update reader hands standings back without rebuilding an inventory that took 7–8 seconds.
    @Test func standingsCanBeAppliedToAnExistingInventory() {
        let inventory = AppsInventory(apps: [
            Sample.app("A", "a"), Sample.app("B", "b"),
        ], otherBundles: 391)

        let updated = inventory.applying(["a": .current])
        #expect(updated.app("a")?.update == .current)
        #expect(updated.app("b")?.update == .notChecked)
        // Everything else survives.
        #expect(updated.otherBundles == 391)
        #expect(updated.apps.count == 2)
    }
}

// MARK: - 7. The two rows that are mostly about not overstating

@Suite struct CrashesAndLeftoversTests {

    /// A crash count is real crashes, never a file count. 108 files here are zero real crashes.
    @Test func aCrashRowCountsCrashesNotFiles() {
        let crashed = CrashedApp(appName: "Thing", bundleID: "thing", crashes: 1,
                                 lastCrash: Date(timeIntervalSince1970: 1_786_000_000))
        #expect(crashed.sentence.hasPrefix("Crashed once, on "))
        let twice = CrashedApp(appName: "Thing", bundleID: "thing", crashes: 3,
                               lastCrash: Date(timeIntervalSince1970: 1_786_000_000))
        #expect(twice.sentence.hasPrefix("Crashed 3 times, last on "))
    }

    /// ⚠️ **Every leftover carries the reason we believe its app is gone**, on the row. This is the
    /// section most likely to be wrong — `~/Library/Application Support/Herd` looks like dead weight
    /// and is somebody's PHP — so an item with no stated reason is an accusation.
    @Test func everyLeftoverCarriesItsReason() {
        let leftover = Leftover(appName: "Gone",
                                bundleID: "com.example.gone",
                                paths: ["~/Library/Application Support/Gone"],
                                bytes: 5_000_000,
                                reason: "No app with this identifier is installed.")
        #expect(!leftover.reason.isEmpty)
        #expect(leftover.detailPairs.first?.value == leftover.reason)
        #expect(leftover.sizeText != nil)

        // Unweighed is nil, not zero.
        let unweighed = Leftover(appName: "Gone", paths: ["/tmp/x"], reason: "Gone.")
        #expect(unweighed.sizeText == nil)
    }
}
