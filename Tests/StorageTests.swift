// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
// Plain import, not `@testable` — everything the vocabulary promises is public.
import WellkeptCore

//  StorageTests.swift
//  WellkeptTests
//
//  ⭐ **The two numbers, and the law about whose files they are.**
//
//  Storage is the first section that offers to touch anything, so these tests hold the four things
//  a later, well-meaning change could quietly undo:
//
//  1. **A person's own files are never pre-ticked.** `Origin.yours` is the default, and a `Item`
//     built without an origin is a file nobody may sweep.
//  2. **Two numbers, never one.** Size on disk and what would come back are different types with no
//     operator between them, and on this Mac they are up to 150× apart.
//  3. **The recoverable figure follows the snapshot, and under-promises in every unknown.**
//  4. **The gap is not optional.** A `StorageReport` cannot be built without naming the difference
//     between what the scan accounted for and what macOS says is used.

// MARK: - ⭐ The row order

@Suite("The five rows keep their raw values and their order")
struct StorageTopicTests {

    /// A raw value is storage: it goes into the check history, which cannot be rebuilt. Renaming one
    /// is a migration, and renaming one to read better on a screen is the change somebody makes
    /// without noticing that.
    @Test func rawValuesArePermanent() {
        #expect(StorageTopic.allCases.map(\.rawValue) == [
            "whatIsUsingSpace", "machineJunk", "yourOwnFiles", "duplicates", "setAside",
        ])
    }

    /// ⭐ **The pre-selected batch comes before the list that needs judgement.** Reversing these two
    /// would put a person's own documents at the top of the screen beside a button.
    @Test func junkComesBeforeAPersonsOwnFiles() {
        #expect(StorageTopic.machineJunk.order < StorageTopic.yourOwnFiles.order)
    }

    /// ⭐ **Exactly one topic may arrive with anything ticked.**
    @Test func onlyMachineJunkMayArrivePreSelected() {
        let preSelectable = StorageTopic.allCases.filter(\.mayArrivePreSelected)
        #expect(preSelectable == [.machineJunk])
    }

    /// The two ceremonies, 2026-08-28: a batch for junk, one at a time for everything else.
    @Test func everyOtherTopicIsOneAtATime() {
        #expect(StorageTopic.machineJunk.ceremony == .batch)
        for topic in StorageTopic.allCases where topic != .machineJunk {
            #expect(topic.ceremony == .oneAtATime, "\(topic.rawValue) offers a batch sweep")
        }
    }

    @Test func labelsAreNotRawValues() {
        for topic in StorageTopic.allCases {
            #expect(topic.label != topic.rawValue)
            #expect(!topic.explanation.isEmpty)
        }
    }
}

// MARK: - ⭐ Junk versus content

@Suite("A person's own files are never chosen for them")
struct OriginTests {

    private func item(_ origin: Origin? = nil, handling: Handling = .canBeSetAside) -> Item {
        let identity = ItemIdentity(volumeUUID: "V", volumeDevice: "/dev/disk3s5", inode: 42)
        let bytes = Bytes.allOfIt(SizeOnDisk(1_000_000_000))
        if let origin {
            return Item(identity: identity, path: "/Users/x/big.mov", bytes: bytes,
                        kind: .file, origin: origin, handling: handling, reason: "large")
        }
        return Item(identity: identity, path: "/Users/x/big.mov", bytes: bytes,
                    kind: .file, handling: handling, reason: "large")
    }

    /// ⭐ **The default is the safe direction.** A classifier that is unsure, a fixture written in a
    /// hurry, and a future scanner that forgets the argument all produce a file nobody may sweep.
    @Test func anItemBuiltWithoutAnOriginBelongsToThePerson() {
        #expect(item().origin == .yours)
        #expect(item().mayBePreSelected == false)
        #expect(item().ceremony == .oneAtATime)
    }

    @Test func onlyMachineJunkMayBeSweptOrPreSelected() {
        #expect(Origin.machineJunk.maySweep)
        #expect(Origin.machineJunk.mayBePreSelected)
        #expect(Origin.yours.maySweep == false)
        #expect(Origin.yours.mayBePreSelected == false)
    }

    /// Both halves have to agree: junk the engine cannot hold still gets no tick, because a ticked
    /// box that refuses when pressed teaches a person that our buttons are decorative.
    @Test func junkTheEngineCannotHoldIsNotPreSelected() {
        let stuck = item(.machineJunk, handling: .cannot("These are read-only disk images."))
        #expect(stuck.mayBePreSelected == false)
        #expect(stuck.handling.mayOfferAButton == false)
    }

    /// A file in iCloud that is not on this Mac occupies nothing, so there is nothing to sweep.
    @Test func aFileThatIsNotHereIsNotPreSelected() {
        let identity = ItemIdentity(volumeUUID: "V", volumeDevice: "/dev/disk3s5", inode: 7)
        let cloud = Item(identity: identity, path: "/Users/x/film.mov",
                         bytes: .zero, kind: .file, origin: .machineJunk,
                         cloudStanding: .inTheCloudOnly, handling: .canBeSetAside,
                         reason: "in iCloud")
        #expect(cloud.mayBePreSelected == false)
    }

    /// ⭐ Only a row of machine junk hands anything back pre-ticked, whatever the items say.
    @Test func onlyTheJunkRowHandsBackPreSelectedItems() {
        let junk = item(.machineJunk)
        let mine = item(.yours)

        let junkRow = StorageRow(topic: .machineJunk, headline: "x", items: [junk, mine])
        #expect(junkRow.preSelected.map(\.origin) == [.machineJunk])

        let mineRow = StorageRow(topic: .yourOwnFiles, headline: "x", items: [junk, mine])
        #expect(mineRow.preSelected.isEmpty)
    }

    /// The settled line, 2026-08-28. Shown for a file that is here **and** synced, because that is the
    /// case where the thirty days cost something on another device.
    @Test func theICloudWarningAppearsOnlyWhereItIsTrue() {
        #expect(CloudStanding.bothPlaces.warning == CloudStanding.alsoRemovesItFromYourDevices)
        #expect(CloudStanding.onThisMac.warning == nil)
        #expect(CloudStanding.inTheCloudOnly.warning == nil)
    }
}

// MARK: - ⭐ The two numbers

@Suite("How big it is and what would come back are different numbers")
struct BytesTests {

    /// The real case from one media folder on a real Mac: 14.8 GB on disk, 0.5 GB back today.
    private let media = Bytes(onDisk: SizeOnDisk(14_800_000_000),
                              recoverableToday: .all(of: SizeOnDisk(500_000_000)))

    @Test func theRowCarriesBothWhereTheyDiffer() {
        #expect(media.agree == false)
        #expect(media.text.contains(media.onDisk.text))
        #expect(media.text.contains(media.recoverableToday.text))
    }

    @Test func oneFigureIsShownOnlyWhereBothAreTheSame() {
        let simple = Bytes.allOfIt(SizeOnDisk(4_200_000_000))
        #expect(simple.agree)
        #expect(simple.text == simple.onDisk.text)
    }

    /// ⚠️ Clamped toward the smaller promise. A scanner that summed a folder one way and the
    /// snapshot arithmetic another should print a conservative number, not a nonsense one.
    @Test func nothingComesBackThatIsNotThere() {
        let silly = Bytes(onDisk: SizeOnDisk(100), recoverableToday: .all(of: SizeOnDisk(999)))
        #expect(silly.recoverableToday.bytes == 100)
    }

    @Test func negativeSizesAreNotAThing() {
        #expect((SizeOnDisk(10) - SizeOnDisk(40)).bytes == 0)
        #expect(SizeOnDisk(-5).bytes == 0)
    }

    @Test func summingKeepsTheTwoNumbersApart() {
        let total = Bytes.sum([media, .allOfIt(SizeOnDisk(1_000_000_000))])
        #expect(total.onDisk.bytes == 15_800_000_000)
        #expect(total.recoverableToday.bytes == 1_500_000_000)
    }

    @Test func zeroSaysSoInWords() {
        #expect(Recoverable.nothing.phrase.contains("nothing"))
    }
}

// MARK: - ⚠️ Finder's number

@Suite("Finder's free-space figure cannot be used in arithmetic")
struct FinderFigureTests {

    /// The two readings taken on this Mac in the same second, 2026-08-28.
    private let actuallyFree = SizeOnDisk(109_754_851_328)
    private let finder = FinderFigure(177_859_575_022)

    /// The one permitted subtraction. 68.1 GB of Finder's number is a promise rather than room.
    @Test func theOnePermittedSubtraction() {
        #expect(finder.promiseBeyond(actuallyFree).bytes == 68_104_723_694)
        #expect(finder.differsFrom(actuallyFree))
    }

    /// Where they agree there is nothing to explain, and a second identical number is clutter.
    @Test func nothingIsPrintedWhereTheyAgree() {
        let same = FinderFigure(actuallyFree.bytes)
        #expect(same.differsFrom(actuallyFree) == false)

        let picture = FreeSpacePicture(capacity: SizeOnDisk(494_384_795_648),
                                       actuallyFree: actuallyFree,
                                       finderShows: same)
        #expect(picture.finderLine == nil)
        #expect(picture.differenceLine == nil)
    }

    /// ⭐ The ruling: the real number leads, Finder's is underneath, one line explains it.
    @Test func theRealNumberLeadsAndTheDifferenceIsExplained() {
        let picture = FreeSpacePicture(capacity: SizeOnDisk(494_384_795_648),
                                       actuallyFree: actuallyFree,
                                       finderShows: finder)
        #expect(picture.headline.hasPrefix(actuallyFree.text))
        #expect(picture.finderLine?.contains(finder.text) == true)
        #expect(picture.differenceLine != nil)
        // The explanation carries the size of the promise, not a vague adjective.
        #expect(picture.differenceLine?.contains(finder.promiseBeyond(actuallyFree).text) == true)
    }
}

// MARK: - ⭐ The snapshot arithmetic

@Suite("What comes back today depends on the oldest snapshot")
struct SnapshotArithmeticTests {

    private let stuck = SnapshotStanding(snapshots: [
        LocalSnapshot(name: "com.apple.TimeMachine.2026-08-25-062503.local",
                      takenOn: Date(timeIntervalSince1970: 1_787_660_703)),
    ])

    private var beforeIt: Date { stuck.oldest!.takenOn.addingTimeInterval(-86_400) }
    private var afterIt: Date { stuck.oldest!.takenOn.addingTimeInterval(86_400) }

    private let gigabyte = SizeOnDisk(1_000_000_000)

    /// ⭐ **The whole model.** A file written after the snapshot is not referenced by it.
    @Test func aFileNewerThanTheSnapshotComesBackWhole() {
        #expect(stuck.recoverable(onDisk: gigabyte, modifiedOn: afterIt).bytes == gigabyte.bytes)
    }

    /// ⭐ And a file older than it comes back not at all — which is why deleting things on this Mac
    /// makes no room.
    @Test func aFileOlderThanTheSnapshotComesBackNotAtAll() {
        #expect(stuck.recoverable(onDisk: gigabyte, modifiedOn: beforeIt).isZero)
    }

    /// The four measured folder percentages — today 98%, yesterday 74%, May 12%, a July folder
    /// 3.6% — are this per-file rule summed over a mixture. Nothing needs a curve.
    @Test func aMixedFolderProducesAPercentage() {
        let files = (0..<10).map { index in
            stuck.bytes(onDisk: gigabyte, modifiedOn: index < 3 ? afterIt : beforeIt)
        }
        let total = Bytes.sum(files)
        #expect(total.onDisk.bytes == 10_000_000_000)
        #expect(total.recoverableToday.bytes == 3_000_000_000)
    }

    @Test func withNoSnapshotEverythingComesBack() {
        #expect(SnapshotStanding.none.recoverable(onDisk: gigabyte, modifiedOn: beforeIt).bytes
                == gigabyte.bytes)
    }

    /// ⚠️ Under-promise in every unknown. A figure that turns out larger is a pleasant surprise; one
    /// that turns out smaller is the app caught lying.
    @Test func everyUnknownPromisesNothing() {
        #expect(stuck.recoverable(onDisk: gigabyte, modifiedOn: nil).isZero)
        #expect(SnapshotStanding.couldNotBeRead.recoverable(onDisk: gigabyte, modifiedOn: afterIt).isZero)
        #expect(SnapshotStanding.couldNotBeRead.recoverable(onDisk: gigabyte, modifiedOn: nil).isZero)
    }

    /// ⭐ The ruling: one flat line on the face, no button — and only where it is true.
    @Test func theLineAppearsOnlyForAStuckSnapshot() {
        let now = stuck.oldest!.takenOn.addingTimeInterval(30 * 86_400)
        #expect(stuck.isStuck(now: now))
        #expect(stuck.line(now: now)?.isEmpty == false)

        let fresh = stuck.oldest!.takenOn.addingTimeInterval(3_600)
        #expect(stuck.isStuck(now: fresh) == false)
        #expect(stuck.line(now: fresh) == nil)

        #expect(SnapshotStanding.none.line() == nil)
        #expect(SnapshotStanding.couldNotBeRead.line() != nil)
    }
}

// MARK: - ⭐ The gap, and never a zero

@Suite("The section names what it could not account for")
struct StorageReportTests {

    private let picture = FreeSpacePicture(
        capacity: SizeOnDisk(494_000_000_000),
        actuallyFree: SizeOnDisk(137_000_000_000),
        finderShows: FinderFigure(177_859_575_022),
        snapshots: SnapshotStanding(snapshots: [
            LocalSnapshot(name: "com.apple.TimeMachine.2026-08-25-062503.local",
                          takenOn: Date(timeIntervalSince1970: 1_787_660_703)),
        ]))

    private func report(measured: Int64 = 244_000_000_000,
                        refused: UnreadablePlaces = UnreadablePlaces(count: 54,
                                                                     notable: ["your Trash",
                                                                               "your Photos library"]))
    -> StorageReport {
        StorageReport(freeSpace: picture,
                      rows: [StorageRow(topic: .whatIsUsingSpace, headline: "Largest first")],
                      measured: SizeOnDisk(measured),
                      refused: refused)
    }

    /// ⭐ **There is no initialiser that produces a report without the gap.** The measured case:
    /// 244 GB accounted for against 357 GB used.
    @Test func theGapIsComputedNotPassedIn() {
        let made = report()
        #expect(made.gap.used.bytes == 357_000_000_000)
        #expect(made.gap.measured.bytes == 244_000_000_000)
        #expect(made.gap.difference.bytes == 113_000_000_000)
    }

    /// ⚠️ Every competitor invents an "Other" slice. We name what is in it.
    @Test func theGapIsExplainedRatherThanLabelledOther() {
        let sentence = report().gap.sentence
        #expect(sentence.lowercased().contains("other than") == false)
        #expect(sentence.contains("snapshot"))
        #expect(sentence.contains("54"))
        #expect(sentence.contains("bookkeeping"))
    }

    /// ⭐ The gap sentence is in the lines under the headline whenever it is worth explaining, so
    /// there is no draw of this section that shows totals without saying what they do not cover.
    @Test func theFaceAlwaysCarriesTheGap() {
        let lines = report().linesUnderTheHeadline
        #expect(lines.contains(report().gap.sentence))
    }

    /// A gap of a few hundred megabytes is bookkeeping, and saying so is clutter.
    @Test func aTinyGapIsNotExplained() {
        let tight = report(measured: 356_900_000_000, refused: .sawEverything)
        #expect(tight.gap.worthExplaining == false)
        #expect(tight.linesUnderTheHeadline.contains(tight.gap.sentence) == false)
    }

    /// ⭐ **Never a zero because we could not look.** Say "I was not allowed to look".
    @Test func refusedPlacesAreSaidOutLoud() {
        let made = report()
        #expect(made.refused.sentence?.contains("54") == true)
        #expect(made.refused.sentence?.contains("Photos") == true)
        #expect(made.complete == false)
        #expect(made.refused.remedy?.settingsPane == "fullDiskAccess")

        #expect(UnreadablePlaces.sawEverything.sentence == nil)
        #expect(UnreadablePlaces.sawEverything.stillComplete)
    }

    /// The files that look enormous and are not here. The verb is "look like".
    @Test func iCloudPlaceholdersAreNamedAndNeverCountedAsSpace() {
        let holding = CloudHolding(files: 15_593, apparentBytes: 72_000_000_000)
        #expect(holding.sentence.contains("look like"))
        #expect(holding.sentence.contains("using no space here"))
    }
}

// MARK: - What a row may and may not say

@Suite("A large folder is not a problem")
struct StorageRowTests {

    /// ⭐ Revealing a person's files is never a fault. There is no argument on the type that could
    /// carry a colour.
    @Test func noRowCanBeWorseThanInformation() {
        #expect(StorageRow.severityCeiling == .information)
        let row = StorageRow(topic: .yourOwnFiles, headline: "Your biggest folders",
                             measure: .allOfIt(SizeOnDisk(80_000_000_000)))
        #expect(row.severity == .information)
        #expect(row.status == .good)
    }

    /// A row we could not read carries no figure and no items. A zero here is the one number a
    /// person would act on and the one we have no right to.
    @Test func anUnreadableRowDropsItsNumbers() {
        let row = StorageRow.unreadable(.machineJunk, .notPermitted)
        #expect(row.measure == nil)
        #expect(row.count == nil)
        #expect(row.items.isEmpty)
        #expect(row.status == .notChecked)
        #expect(row.complete == false)
        #expect(row.headline.contains("not allowed"))
    }

    /// A row that read most of the disk and was refused one folder is not a row that could not be
    /// read — reporting it as one would throw away everything it did find.
    @Test func aPartlyRefusedRowKeepsWhatItFound() {
        let row = StorageRow(topic: .machineJunk,
                             headline: "Caches and build output",
                             measure: .allOfIt(SizeOnDisk(13_000_000_000)),
                             count: 400,
                             refused: UnreadablePlaces(count: 2, notable: ["your Trash"]))
        #expect(row.measure != nil)
        #expect(row.complete == false)
        #expect(row.remedy?.title == "Open Full Disk Access")
    }
}

// MARK: - What reaches Overview

@Suite("Only a disk with no room left reaches Overview")
struct StorageOverviewTests {

    private func report(free: Int64, capacity: Int64 = 494_000_000_000) -> StorageReport {
        StorageReport(freeSpace: FreeSpacePicture(capacity: SizeOnDisk(capacity),
                                                  actuallyFree: SizeOnDisk(free)),
                      rows: [StorageRow(topic: .whatIsUsingSpace, headline: "x")],
                      measured: SizeOnDisk(capacity - free))
    }

    /// ⭐ A 40 GB folder is not something that needs you. Nothing about the size of somebody's own
    /// files may ever appear on Overview.
    @Test func aRoomyDiskSaysNothingAtAll() {
        let made = report(free: 137_000_000_000)
        #expect(made.freeSpace.pressure == .comfortable)
        #expect(made.overviewFinding == nil)
        #expect(made.status == .good)
    }

    @Test func aDiskGettingFullIsAttentionNotAProblem() {
        let made = report(free: 40_000_000_000)
        #expect(made.freeSpace.pressure == .gettingFull)
        #expect(made.overviewFinding?.severity == .attention)
        #expect(made.status == .needsAttention)
    }

    /// The one genuine problem this section has: macOS needs working room of its own.
    @Test func aDiskWithNoRoomLeftIsAProblem() {
        let made = report(free: 4_000_000_000)
        #expect(made.freeSpace.pressure == .nearlyFull)
        #expect(made.overviewFinding?.severity == .problem)
        #expect(made.overviewFinding?.measure?.contains("free") == true)
    }

    /// A 4 TB disk with 60 GB left is not comfortable just because 60 GB sounds like a lot, and a
    /// 256 GB disk with 30 GB left is not a problem just because 12% sounds small. Both halves of
    /// the threshold earn their place.
    @Test func theFloorIsBytesAsWellAsAPercentage() {
        #expect(report(free: 8_000_000_000, capacity: 4_000_000_000_000).freeSpace.pressure == .nearlyFull)
        #expect(report(free: 30_000_000_000, capacity: 256_000_000_000).freeSpace.pressure == .gettingFull)
    }

    @Test func aReportWithNoRowsHasNotBeenRun() {
        let empty = StorageReport(freeSpace: FreeSpacePicture(capacity: SizeOnDisk(1),
                                                              actuallyFree: SizeOnDisk(1)),
                                  rows: [],
                                  measured: .zero)
        #expect(empty.status == .notChecked)
        #expect(empty.summary.contains("Nothing has been scanned"))
    }
}

// MARK: - Identity

@Suite("A path is not an identity")
struct ItemIdentityTests {

    /// ⚠️ Inode numbers are handed out per volume and start small, so a fresh file on a plugged-in
    /// drive routinely carries the same number as one in the home folder.
    @Test func theVolumeIsPartOfEveryComparison() {
        let home = ItemIdentity(volumeUUID: "AAA", volumeDevice: "/dev/disk3s5", inode: 12)
        let drive = ItemIdentity(volumeUUID: "BBB", volumeDevice: "/dev/disk6s2", inode: 12)
        #expect(home.isTheSameThing(as: drive) == false)
        #expect(home.isTheSameThing(as: home))
    }

    /// Devices renumber across a reboot with a drive plugged in, so the UUID wins where both have
    /// one and the device is only the fallback.
    @Test func theUUIDBeatsARenumberedDevice() {
        let before = ItemIdentity(volumeUUID: "AAA", volumeDevice: "/dev/disk3s5", inode: 12)
        let after = ItemIdentity(volumeUUID: "AAA", volumeDevice: "/dev/disk4s5", inode: 12)
        #expect(before.isTheSameThing(as: after))
    }
}
