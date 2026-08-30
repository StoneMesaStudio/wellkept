// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  StorageLawGuardTests.swift
//  WellkeptTests
//
//  ⭐ **The law of this section, proved over its whole state space and over its own source.**
//
//  `StorageTests` proves the types behave, case by case. This file asks two different questions,
//  and both of them are about the failure that ends the product rather than about a value:
//
//  1. **Is there ANY combination of states in which one of a person's own files arrives with its
//     box ticked?** Not "does this example behave" — every combination. `Origin` × `Handling` ×
//     `CloudStanding` × `ItemKind` × `StorageTopic` is 2 × 3 × 3 × 5 × 5 = 450 states, which is
//     small enough to enumerate and far too large to spot-check. A sampled test passes on the day
//     somebody adds a fourth `Handling` case that says yes.
//
//  2. **Can a later file undo it without anybody noticing?** The guards below read the repository's
//     own Swift and fail the build on the shape of the mistake — the same instrument, and the same
//     reasoning, as `ContainerGuardTests` and `QuarantineWordsTests`. The harm these prevent is a
//     sentence or a ticked box on somebody's screen, and by the time a behaviour test could observe
//     it, it has already happened.
//
//  ⚠️ **Nothing here touches the disk except to read this repository's own text.**

// MARK: - ⭐ 1. Every state, and none of them ticks a person's own file

/// The exhaustive version of the one rule this section exists to keep.
///
/// The ruling, 2026-08-28: **machine junk regenerates and may be pre-selected; a person's own
/// files are revealed, sized and sorted, and never pre-selected or swept.** Everything below walks
/// the whole product of the states an item can be in and asserts that no path through them puts a
/// tick on something whose `Origin` is `.yours`.
@Suite("Every state a row can be in, and none of them ticks a person's own file")
struct PreSelectionStateSpaceTests {

    /// One item in a named state. Deliberately built through the **public** initialiser a screen
    /// or a reader would use, so the test walks the same road the app does.
    private func item(origin: Origin,
                      handling: Handling,
                      cloud: CloudStanding,
                      kind: ItemKind,
                      inode: UInt64) -> Item {
        Item(identity: ItemIdentity(volumeUUID: "3F2A", volumeDevice: "/dev/disk3s5", inode: inode),
             path: "/Users/somebody/Movies/thing",
             bytes: Bytes.allOfIt(SizeOnDisk(4_000_000_000)),
             kind: kind,
             origin: origin,
             cloudStanding: cloud,
             handling: handling,
             reason: "It is one of the largest things in this folder.")
    }

    /// Every `Handling` there is, reached through the constructors the app has.
    private var everyHandling: [Handling] {
        [.canBeSetAside, .notCheckedYet, .cannot("These are read-only disk images.")]
    }

    /// ⭐ **The headline.** Across all 450 states, an item that belongs to the person is never
    /// pre-selectable, is never handed back by a row's `preSelected`, and always draws the sheet
    /// rather than the batch.
    @Test func nothingOfAPersonsIsEverTickedInAnyState() {
        var states = 0
        var offenders: [String] = []
        var inode: UInt64 = 1

        for handling in everyHandling {
            for cloud in CloudStanding.allCases {
                for kind in ItemKind.allCases {
                    for topic in StorageTopic.allCases {
                        inode += 1
                        states += 1
                        let mine = item(origin: .yours, handling: handling, cloud: cloud,
                                        kind: kind, inode: inode)
                        let row = StorageRow(topic: topic, headline: topic.label, items: [mine])

                        if mine.mayBePreSelected {
                            offenders.append("item \(topic.rawValue)/\(handling.standing.rawValue)/\(cloud.rawValue)/\(kind.rawValue)")
                        }
                        if row.preSelected.isEmpty == false {
                            offenders.append("row \(topic.rawValue)/\(handling.standing.rawValue)/\(cloud.rawValue)/\(kind.rawValue)")
                        }
                        if mine.ceremony != .oneAtATime {
                            offenders.append("ceremony \(topic.rawValue)/\(kind.rawValue)")
                        }
                    }
                }
            }
        }

        #expect(states == everyHandling.count * CloudStanding.allCases.count
                        * ItemKind.allCases.count * StorageTopic.allCases.count)
        #expect(states >= 200, "the state space shrank — a case was removed, or a loop is empty")
        #expect(offenders.isEmpty, """
            A person's own file arrived pre-selected in \(offenders.count) states: \
            \(offenders.prefix(6).joined(separator: ", ")).
            Machine junk regenerates and may be pre-selected. A person's own files are revealed, \
            sized and sorted, and never pre-selected or swept. There is no third answer.
            """)
    }

    /// The other half, and the reason the first half is not vacuous: **machine junk that the engine
    /// can hold, on its own row, really does arrive ticked.** A law nothing can satisfy is a law
    /// nobody notices being deleted.
    @Test func theOneCaseThatDoesArriveTickedStillDoes() {
        let junk = item(origin: .machineJunk, handling: .canBeSetAside, cloud: .onThisMac,
                        kind: .folder, inode: 900)
        #expect(junk.mayBePreSelected)

        let row = StorageRow(topic: .machineJunk, headline: "Machine junk", items: [junk])
        #expect(row.preSelected.count == 1)
        #expect(row.ceremony == .batch)
    }

    /// ⚠️ **Junk on somebody else's row is still not ticked.** The row decides, not the item — so a
    /// reader that mislabels one thing cannot put a tick on a screen where no batch press exists.
    @Test func junkListedOnAnotherRowIsNotTickedEither() {
        let junk = item(origin: .machineJunk, handling: .canBeSetAside, cloud: .onThisMac,
                        kind: .folder, inode: 901)
        for topic in StorageTopic.allCases where topic != .machineJunk {
            let row = StorageRow(topic: topic, headline: topic.label, items: [junk])
            #expect(row.preSelected.isEmpty, "\(topic.rawValue) handed back a ticked box")
        }
    }

    /// ⚠️ **Two cases, and a third would be a decision.** `Origin` is what decides pre-selection,
    /// sweeping, ceremony and which sheet appears. Adding a case is adding a fourth answer to four
    /// questions at once, which is a conversation and not a commit.
    @Test func thereAreTwoOriginsAndNoRoomForAThird() {
        #expect(Origin.allCases.count == 2)
        #expect(Ceremony.allCases.count == 2)
        #expect(Origin.allCases.filter(\.mayBePreSelected) == [.machineJunk])
        #expect(Origin.allCases.filter(\.maySweep) == [.machineJunk])
        #expect(StorageTopic.allCases.filter(\.mayArrivePreSelected) == [.machineJunk])
    }

    /// The batch ceremony and the sheet ceremony are not the same act, and the difference is
    /// mechanical rather than a matter of which screen was written first.
    @Test func theTwoCeremoniesDisagreeAboutEverythingThatMatters() {
        #expect(Ceremony.batch.allowsMultipleSelection)
        #expect(Ceremony.batch.statesTheArithmeticFirst == false)
        #expect(Ceremony.oneAtATime.allowsMultipleSelection == false)
        #expect(Ceremony.oneAtATime.statesTheArithmeticFirst)
    }
}

// MARK: - ⭐ 2. The two numbers cannot be swapped

/// **`SizeOnDisk` and `Recoverable` are two types precisely so that a swap is a compile error.**
///
/// Measured on one real Mac: one media folder was 14.8 GB on disk and 0.5 GB back today — 30×
/// apart, and the worksheet carries a 150× case. Printing the first where the second belongs is the
/// single most misleading thing this section could do.
///
/// A test cannot assert that something does not compile. What it can assert is that the guardrails
/// which make the swap impossible are still standing: no literal turns into either type by
/// accident, and `Recoverable` has no public initialiser anywhere for a caller to reach for.
@Suite("The two numbers cannot be swapped, and a bare number is not either of them")
struct TwoNumbersTests {

    /// ⭐ Neither is `ExpressibleByIntegerLiteral`, so `SizeOnDisk` and `Recoverable` can never be
    /// produced by writing a number — a figure has to be given a meaning before it becomes a value.
    @Test func aBareNumberIsNeitherOfThem() {
        #expect(StorageSource.acceptsABareNumber(SizeOnDisk.self) == false,
                "SizeOnDisk gained a literal conformance — `let size: SizeOnDisk = 12` now compiles")
        #expect(StorageSource.acceptsABareNumber(Recoverable.self) == false,
                "Recoverable gained a literal conformance, so any number is now a conclusion")
        // The control: `Int` does, so a check that finds nothing is finding nothing for a reason.
        #expect(StorageSource.acceptsABareNumber(Int.self))
    }

    /// ⭐ **A `Recoverable` is a conclusion, and it is reached in one place.** The memberwise
    /// initialiser is deliberately internal to `WellkeptCore`; the two named constructors each
    /// state their assumption in their own name. This reads the source, because "no public init" is
    /// a property of the text and not of any value the test could hold.
    @Test func recoverableHasNoPublicInitialiserForAnybodyToReachFor() {
        let text = StorageSource.core
        let struckRegion = StorageSource.region(of: "public struct Recoverable", in: text)
        #expect(struckRegion.isEmpty == false, "the Recoverable declaration moved — this scan is blind")
        #expect(struckRegion.contains("public init") == false, """
            Recoverable gained a public initialiser. It is a conclusion drawn from the snapshot \
            list and the file's date, not a number a caller may assert. The only makers are \
            `.all(of:)`, `.nothing`, and `SnapshotStanding.recoverable(onDisk:modifiedOn:)`.
            """)
        // The internal one is still there, and still named so that a reader has to say `unchecked`.
        #expect(struckRegion.contains("init(unchecked bytes: Int64)"))
    }

    /// **`Bytes` has exactly one initialiser and it takes both figures.** A convenience that took
    /// one is how a row ends up printing 14.8 GB beside a button that returns half a gigabyte.
    @Test func aRowsMeasureCannotBeBuiltFromOneFigure() {
        let region = StorageSource.region(of: "public struct Bytes", in: StorageSource.core)
        #expect(region.isEmpty == false)
        let inits = region.components(separatedBy: "public init").count - 1
        #expect(inits == 1, "Bytes has \(inits) public initialisers — one of them takes a single figure")
        #expect(region.contains("public init(onDisk: SizeOnDisk, recoverableToday: Recoverable)"))
        // The two named shortcuts both say in their names what they are assuming.
        #expect(region.contains("static func allOfIt"))
        #expect(region.contains("static func heldBackBySnapshot"))
    }

    /// The pair clamps toward the smaller promise in both directions, whichever way a caller got
    /// it wrong. Asserted over a spread rather than one example.
    @Test func theSmallerPromiseAlwaysWins() {
        for onDisk in [Int64(0), 1, 1_000, 14_800_000_000] {
            for claimed in [Int64(0), 1, 999, 200_000_000_000] {
                let pair = Bytes(onDisk: SizeOnDisk(onDisk),
                                 recoverableToday: .all(of: SizeOnDisk(claimed)))
                #expect(pair.recoverableToday.bytes <= pair.onDisk.bytes,
                        "\(claimed) came back out of \(onDisk)")
            }
        }
    }

    /// ⚠️ **Finder's figure has no way out except one named subtraction.** It is not a number
    /// arithmetic works on — free 12 GB and it does not move by 12, because the purgeable pool
    /// shifts underneath. The type is what makes that true rather than a comment about it.
    @Test func findersFigureHasExactlyOneDoor() {
        let region = StorageSource.region(of: "public struct FinderFigure", in: StorageSource.core)
        #expect(region.isEmpty == false)
        #expect(region.contains("private let bytes: Int64"),
                "FinderFigure's byte count stopped being private — it can be used in arithmetic now")
        for operator_ in ["static func +", "static func -", "static func <", "public var bytes"] {
            #expect(region.contains(operator_) == false,
                    "FinderFigure gained `\(operator_)`, which makes it a quantity again")
        }
        #expect(region.contains("func promiseBeyond"))
    }

    /// The measured pair from this Mac, kept as a regression: 68.1 GB of Finder's figure is a
    /// promise rather than room, and the difference is explained rather than hidden.
    @Test func theMeasuredDifferenceIsStillTheOneWeExplain() {
        let real = SizeOnDisk(109_754_851_328)
        let finder = FinderFigure(177_859_575_022)
        let picture = FreeSpacePicture(capacity: SizeOnDisk(494_384_795_648),
                                       actuallyFree: real,
                                       finderShows: finder,
                                       snapshots: .none,
                                       volumeName: "Macintosh HD")
        #expect(picture.headline.contains(real.text), "the real number does not lead")
        #expect(picture.headline.contains(finder.text) == false, "Finder's number is in the headline")
        #expect(picture.finderLine?.contains(finder.text) == true, "Finder's figure is not printed underneath")
        #expect(picture.differenceLine?.contains("68.1 GB") == true,
                "the one line that explains the difference no longer names it")
    }
}

// MARK: - ⭐ 3. Nothing but the classifier may call something the machine's

/// **One file in the whole repository decides that something belongs to the machine.**
///
/// `BigFilesOriginGuardTests` watches two readers. This watches everything, because the mistake is
/// not confined to a reader: a view, a model, a demo fixture or a future section could each write
/// `origin: .machineJunk` and mean well doing it. Pre-selection and sweeping hang off that one
/// argument, so it belongs in the one file whose whole job is to justify it — with a category, a
/// story about what writes the thing again, and a stated cost of being wrong.
@Suite("Only the classifier may say something belongs to the machine")
struct MachineJunkAuthorityTests {

    /// The classifier itself, and the type's own declaration. Nowhere else.
    static let permitted: Set<String> = [
        "App/Storage/JunkClassifier.swift",
        "Core/Sources/WellkeptCore/Storage.swift",
    ]

    @Test func theScanCanSeeTheClassifier() {
        let files = StorageSource.swiftFiles()
        #expect(files.count > 40, "the source scan found almost nothing — it is looking in the wrong place")
        #expect(files.contains("App/Storage/JunkClassifier.swift"),
                "the classifier is not where the guard thinks it is")
    }

    /// ⭐ The guard. A **construction** — `origin: .machineJunk`, or `Origin.machineJunk` — outside
    /// those two files fails the build.
    ///
    /// ⚠️ A **comparison** is a different act and is allowed everywhere: a view has to be able to
    /// ask what it is drawing. `StorageTopic.machineJunk` is a different symbol entirely and is not
    /// matched, because a row named "machine junk" is not a claim about anybody's file.
    @Test func nobodyElseFilesAnythingAsTheMachines() {
        var offenders: [String] = []
        for relative in StorageSource.swiftFiles() where !Self.permitted.contains(relative) {
            for (number, line) in StorageSource.codeLines(of: relative) {
                let claims = line.contains("origin: .machineJunk")
                           || line.contains("Origin.machineJunk")
                guard claims, !line.contains("=="), !line.contains("!=") else { continue }
                offenders.append("\(relative):\(number)")
            }
        }
        #expect(offenders.isEmpty, """
            These decide on their own that something belongs to the machine: \
            \(offenders.joined(separator: ", ")).
            That one argument turns on pre-selection and batch sweeping. It belongs in \
            JunkClassifier, where a category has to name what writes the thing again and what \
            being wrong costs — not in a reader, a view or a fixture.
            """)
    }

    /// The negative control: the classifier really does write it, so a guard that finds nothing is
    /// finding nothing for the right reason.
    @Test func theClassifierStillWritesIt() {
        let text = StorageSource.text("App/Storage/JunkClassifier.swift")
        #expect(text.contains(".machineJunk"), """
            The classifier no longer files anything as the machine's — either it moved, or the             junk row is now empty on every Mac and the guard above is finding nothing because             there is nothing to find.
            """)
    }

    /// ⚠️ **No rule anywhere may conclude junk from an absence.** The Herd trap is live on this
    /// Mac: 90 MB in Application Support, no app, no receipt, no Spotlight entry, untouched four
    /// and a half months — and it is a working PHP install. Every orphan heuristic fires at once
    /// and every one of them is wrong.
    ///
    /// The defence is that no such rule exists, so this looks for the shape of one arriving.
    @Test func nothingConcludesJunkFromAnAbsence() {
        let phrases = ["noAppClaimsIt", "isOrphaned", "hasNoReceipt", "notInSpotlight",
                       "nobodyOpenedIt", "unclaimed", "hasNoOwnerApp"]
        var offenders: [String] = []
        for relative in StorageSource.swiftFiles() where relative.hasPrefix("App/Storage/") {
            for (number, line) in StorageSource.codeLines(of: relative) {
                for phrase in phrases where line.contains(phrase) {
                    offenders.append("\(relative):\(number) — \(phrase)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            These reason from an absence of evidence: \(offenders.joined(separator: ", ")).
            The 90 MB folder in Application Support with no app, no receipt, no Spotlight entry \
            and no activity for four and a half months is a working PHP install. Identity, never absence.
            """)
    }
}

// MARK: - ⭐ 4. The claims this section is not allowed to make

/// **`QuarantineWordsTests` bans "freed" and "reclaim" everywhere. This bans the four claims
/// Storage specifically invites**, and it is scoped to Storage's own files so that it never cries
/// wolf about a sentence Hardware or Security earned.
///
/// Each one is here because a measurement said so, and each cost is a person catching the app in a
/// claim they can disprove:
///
/// 1. **A countdown.** Measured end to end: 56.7 seconds for 983,868 files, and slower with Full
///    Disk Access, because the 68 folders it was refused are folders it would then walk. The first
///    scan after a restart has never been measured at all, so any figure attached to *progress*
///    would be a guess with a clock face on it.
///
///    ⚠️ The line drawn here is **a figure attached to progress**, not the word "minute". One
///    honest sentence before the press — `StorageWords.howLongItTakes`, "about a minute on a full
///    disk" — is calibration, and it is grounded in the measurement. A bar that says how much
///    longer is a promise the code cannot keep, and that is what is banned.
/// 2. **An accusation built on "last opened".** Blank for 61% of large files here, and 123 files in
///    one sample share a timestamp a batch job stamped on them.
/// 3. **An "Other" slice.** 244 GB of live files against 357 GB used. Every competitor hides that
///    gap behind a label; we name what is in it.
/// 4. **"Safe to delete", or a nomination of which duplicate to keep.** Four real pairs on this Mac
///    each defeat a different rule for picking the original. We never choose, and we never certify.
@Suite("The four claims Storage is not allowed to make")
struct StorageClaimTests {

    /// Storage's own files, and nowhere else. Security genuinely does take a few seconds, and a
    /// guard that fires on a true sentence somewhere else gets deleted rather than obeyed.
    static var watched: [String] {
        StorageSource.swiftFiles().filter {
            $0.hasPrefix("App/Storage/")
                || $0.hasPrefix("App/Sections/Storage")
                || $0 == "Core/Sources/WellkeptCore/Storage.swift"
        }
    }

    @Test func theScanIsLookingAtStoragesOwnFiles() {
        #expect(Self.watched.count >= 6, "Storage's files moved — this guard is scanning nothing")
        #expect(Self.watched.contains("Core/Sources/WellkeptCore/Storage.swift"))
    }

    static let timePromises = ["time remaining", "estimated time", "seconds remaining",
                               "minutes remaining", "time left", "almost done", "nearly finished",
                               "% complete", "this will take"]

    static let accusations = ["have not opened", "haven\'t opened", "has not been opened",
                              "hasn\'t been opened", "you last opened", "unused for",
                              "untouched for", "years ago", "never opened"]

    static let certifications = ["safe to delete", "safe to remove", "safely delete",
                                 "safely remove", "we recommend", "we suggest", "keep this one",
                                 "the original is", "suggested copy", "best copy"]

    /// 1. Never a countdown, and no symbol anywhere that could grow into one.
    @Test func nothingCountsDownWhileTheScanRuns() {
        let found = StorageSource.offenders(in: Self.watched, saying: Self.timePromises)
        #expect(found.isEmpty, """
            \(found.joined(separator: "; ")).
            The measured run is 56.7 seconds for 983,868 files and slower once Full Disk Access is \
            granted, because the folders it was refused are folders it would then walk. Progress \
            names a place: "Looking in Documents".
            """)

        // The symbol, not only the sentence. A property called `estimatedTimeRemaining` is a
        // countdown whether or not anything has printed it yet.
        var symbols: [String] = []
        for relative in Self.watched {
            for (number, line) in StorageSource.codeLines(of: relative) {
                // ⚠️ **Matched at an identifier boundary, not as a bare substring.** `eta` is
                // three letters that live inside `details`, `metadata` and `beta`, and the
                // substring version of this guard fired on 74 perfectly innocent lines across
                // seven files — including the `details.append(…)` that builds every Options panel
                // in the section. A guard that cries wolf gets deleted, which is the one outcome
                // that would actually let a countdown in.
                for name in ["estimatedTime", "timeRemaining", "secondsLeft", "eta"]
                where StorageSource.mentionsSymbol(name, in: line) {
                    symbols.append("\(relative):\(number) — \(name)")
                }
            }
        }
        #expect(symbols.isEmpty, "a countdown was added: \(symbols.joined(separator: ", "))")
    }

    /// 2. Never an accusation built on a date that is blank 61% of the time.
    @Test func nothingAccusesAPersonOfNotOpeningSomething() {
        let found = StorageSource.offenders(in: Self.watched, saying: Self.accusations)
        #expect(found.isEmpty, """
            \(found.joined(separator: "; ")).
            "Last opened" is blank for 61% of large files on this Mac, and 123 files in one sample \
            carry one timestamp a batch job stamped on them. It is a fact on a row and never a \
            finding.
            """)
    }

    /// 3. Never a slice called "Other". The gap is named and explained, or it is not shown.
    @Test func theGapIsNeverLabelledOther() {
        var offenders: [String] = []
        for relative in Self.watched {
            for (number, line) in StorageSource.codeLines(of: relative) {
                for literal in StorageSource.stringLiterals(in: line)
                where literal == "Other" || literal == "Other space" || literal == "Other files" {
                    offenders.append("\(relative):\(number)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            These label the gap: \(offenders.joined(separator: ", ")).
            The scan totals 244 GB of live files where macOS reports 357 GB used. The difference is \
            the snapshot, the folders we were refused, and filesystem bookkeeping — and naming \
            those three is the only thing this section does that no other tool on the Mac does.
            """)
        // ⭐ And the sentence that replaces the slice still names what is in the gap. The measured
        // pair from this Mac: 244 GB accounted for against 357 GB used.
        let gap = MeasuredGap(used: SizeOnDisk(357_000_000_000),
                              measured: SizeOnDisk(244_000_000_000),
                              placesRefused: 54,
                              hasSnapshot: true)
        #expect(gap.worthExplaining)
        #expect(gap.sentence.contains("snapshot"), "the snapshot is not named as a cause")
        #expect(gap.sentence.contains("54 folders we were not allowed to read"))
        #expect(gap.sentence.contains("bookkeeping"))
        #expect(gap.detailPairs.contains { $0.label == "Other" } == false,
                "the details grew a slice labelled Other")
    }

    /// 4. Never "safe to delete", and never a nomination of which copy to keep.
    @Test func nothingIsCertifiedSafeAndNoCopyIsNominated() {
        let found = StorageSource.offenders(in: Self.watched, saying: Self.certifications)
        #expect(found.isEmpty, """
            \(found.joined(separator: "; ")).
            Four real duplicate pairs on this Mac each defeat a different rule for picking the \
            original — including a photo whose dates a past copy destroyed, so "keep the oldest" \
            picks the wrong one. We never choose, and nothing is certified safe by us.
            """)
    }

    /// ⚠️ The lists are not a style rule with an exception queue. Removing a phrase is a
    /// conversation about a measurement, so the counts are asserted.
    @Test func theBansHaveNowhereToShrinkQuietly() {
        #expect(Self.timePromises.count == 9)
        #expect(Self.accusations.count == 9)
        #expect(Self.certifications.count == 10)
        #expect(StorageTopic.allCases.count == 5)
    }
}

// MARK: - ⭐ 5. A place we could not read is never a zero

/// **Without Full Disk Access, 54 folders in this home directory cannot be read** — the Trash and
/// the Photos library among them, usually the two biggest wins on any Mac. A row that answers "0
/// bytes" there is worse than no row: it is a number a person would act on and the one number we
/// have no right to.
@Suite("A place we could not read is named, and never reported as empty")
struct RefusedIsNeverZeroTests {

    /// Every topic, every kind of refusal: no measure, no count, no items, and a sentence that says
    /// what happened.
    @Test func noUnreadableRowInAnyTopicCarriesAFigure() {
        for topic in StorageTopic.allCases {
            for why in Unreadable.allCases where why != .notReported {
                let row = StorageRow.unreadable(topic, why, about: "your Trash",
                                                reason: "Wellkept was not allowed to look inside.")
                #expect(row.measure == nil, "\(topic.rawValue)/\(why.rawValue) reported a figure")
                #expect(row.count == nil)
                #expect(row.items.isEmpty)
                #expect(row.headline.contains("your Trash"))
                #expect(row.status == .notChecked)
            }
        }
    }

    /// ⚠️ A figure handed in is **dropped**, not trusted. The mistake this catches is a reader that
    /// walked half a folder, was refused the rest, and passed on what it had as if it were the
    /// answer.
    @Test func aFigureHandedToAnUnreadableRowIsThrownAway() {
        let row = StorageRow(topic: .yourOwnFiles,
                             headline: "We were not allowed to look.",
                             measure: .allOfIt(SizeOnDisk(12_000_000_000)),
                             count: 4_000,
                             items: [],
                             unreadable: .notPermitted)
        #expect(row.measure == nil)
        #expect(row.count == nil)
    }

    /// The refusal a person can lift carries a button; the one nobody can lift does not. Both say
    /// what happened, in words, and neither says zero.
    @Test func onlyTheRefusalAPersonCanLiftCarriesAButton() {
        let liftable = UnreadablePlaces(count: 54, notable: ["your Trash", "your photo library"],
                                        why: .notPermitted)
        #expect(liftable.remedy != nil)
        #expect(liftable.stillComplete == false)
        let sentence = liftable.sentence ?? ""
        #expect(sentence.contains("your Trash"))
        #expect(sentence.contains(" 0 ") == false, "a refusal was reported as a quantity")

        let fixed = UnreadablePlaces(count: 2, notable: ["the system volume"], why: .notGrantable)
        #expect(fixed.remedy == nil, "a door was offered with no room behind it")

        #expect(UnreadablePlaces.sawEverything.isEmpty)
        #expect(UnreadablePlaces.sawEverything.sentence == nil)
        #expect(UnreadablePlaces.sawEverything.stillComplete)
    }

    /// ⚠️ **An empty folder and a folder we were refused must not read the same.** This is the
    /// distinction the whole rule rests on, so it is asserted directly.
    @Test func nothingFoundAndNotAllowedToLookAreDifferentAnswers() {
        let empty = StorageRow(topic: .duplicates,
                               headline: "Nothing here has an identical twin.",
                               measure: .zero, count: 0)
        let refused = StorageRow.unreadable(.duplicates, .notPermitted, about: "your photo library")

        #expect(empty.status == .good)
        #expect(refused.status == .notChecked)
        #expect(empty.complete)
        #expect(refused.complete == false)
        #expect(empty.headline != refused.headline)
    }

    /// The remedy names a real pane, spelled the way the app's own settings opener spells it. Core
    /// cannot import the app layer, so this literal is unavoidable; the test is what stops it
    /// rotting.
    @Test func theRemedyStillNamesAPane() {
        let remedy = UnreadablePlaces(count: 3, notable: ["your Trash"], why: .notPermitted).remedy
        #expect(remedy?.settingsPane == "fullDiskAccess")
        #expect(remedy?.title.isEmpty == false)
    }
}

// MARK: - ⭐ 6. Nothing asks for the date our own scan poisons

/// **Our research read 2,012 files and their "last accessed" dates now all read as today.** That
/// date can never be used to find old files, because the act of looking rewrites it. The key is
/// absent from `ScanPolicy.resourceKeys`, which `StoragePolicyTests` asserts; this asserts the
/// stronger thing, which is that no file in the app asks for it at all.
@Suite("Nothing in the app asks for a date our own scan rewrites")
struct AccessDateTests {

    @Test func theAccessDateIsNamedNowhereInShippingCode() {
        var offenders: [String] = []
        for relative in StorageSource.swiftFiles() {
            for (number, line) in StorageSource.codeLines(of: relative)
            where line.contains("contentAccessDateKey") || line.contains("ATTR_CMN_ACCTIME") {
                offenders.append("\(relative):\(number)")
            }
        }
        #expect(offenders.isEmpty, """
            These ask for the last-accessed date: \(offenders.joined(separator: ", ")).
            Our own research scan rewrote 2,012 of them in a single afternoon, so the date says \
            when Wellkept looked and not when the person did. If it is ever wanted it has to be \
            captured in the first pass, before anything is opened.
            """)
    }
}

// MARK: - The scanner behind the guards

/// Reads this repository's own Swift. Shared by the suites above so there is one idea of what
/// counts as code and one idea of where the repository is.
enum StorageSource {

    static let roots = ["App", "Core/Sources"]

    /// Whether a type can be produced by writing a number. Wrapped in a generic function because
    /// the check has to happen where the concrete type is still known.
    static func acceptsABareNumber<T>(_ type: T.Type) -> Bool {
        type is any ExpressibleByIntegerLiteral.Type
    }

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the repository
    }

    static func swiftFiles() -> [String] {
        var found: [String] = []
        for directory in roots {
            let base = repoRoot.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: base,
                                                              includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append(String(url.path.dropFirst(repoRoot.path.count + 1)))
            }
        }
        return found.sorted()
    }

    static func text(_ relative: String) -> String {
        (try? String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)) ?? ""
    }

    static var core: String { text("Core/Sources/WellkeptCore/Storage.swift") }

    /// Every line that is not a comment, with its 1-based number. Prose in a comment is where the
    /// reason gets recorded, so comments are exempt from every guard here.
    static func codeLines(of relative: String) -> [(Int, String)] {
        text(relative)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { return nil }
                return (index + 1, String(line))
            }
    }

    /// The text of a declaration, from its opening line to the next one at the same indentation.
    /// Crude on purpose: it is looking for the presence or absence of a keyword inside one type,
    /// and the failure mode of getting the end wrong is a guard that over-reports.
    static func region(of declaration: String, in text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(declaration) }) else { return "" }
        var end = start + 1
        while end < lines.count && lines[end] != "}" { end += 1 }
        return lines[start...min(end, lines.count - 1)].joined(separator: "\n")
    }

    /// Every double-quoted run on a line. Same crude scanner as `QuarantineWordsTests`, and
    /// deliberately so — over-reporting is the safe direction for a guard.
    static func stringLiterals(in line: String) -> [String] {
        var literals: [String] = []
        var current = ""
        var inside = false
        var escaped = false
        for character in line {
            if escaped { if inside { current.append(character) }; escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "\"" {
                if inside { literals.append(current); current = "" }
                inside.toggle()
                continue
            }
            if inside { current.append(character) }
        }
        return literals
    }

    /// Whether a line names a symbol — the name at the start of an identifier, rather than buried
    /// inside a longer word.
    ///
    /// `estimatedTimeRemaining` and `etaSeconds` both match `eta`; `details` and `metadata` do not.
    /// The rule is only about the character **before** the name, because Swift identifiers are
    /// camelCase and a countdown called `etaForTheRun` is still a countdown.
    static func mentionsSymbol(_ name: String, in line: String) -> Bool {
        let characters = Array(line)
        let needle = Array(name)
        guard needle.count <= characters.count else { return false }
        for start in 0...(characters.count - needle.count) {
            guard Array(characters[start..<(start + needle.count)]) == needle else { continue }
            if start == 0 { return true }
            let before = characters[start - 1]
            if !(before.isLetter || before.isNumber || before == "_") { return true }
        }
        return false
    }

    /// Where any of these phrases appears inside a string literal in shipping code.
    static func offenders(in files: [String], saying phrases: [String]) -> [String] {
        var found: [String] = []
        for relative in files {
            for (number, line) in codeLines(of: relative) {
                for literal in stringLiterals(in: line) {
                    let lowered = literal.lowercased()
                    for phrase in phrases where lowered.contains(phrase) {
                        found.append("\(relative):\(number) — \"\(literal)\"")
                    }
                }
            }
        }
        return found
    }
}
