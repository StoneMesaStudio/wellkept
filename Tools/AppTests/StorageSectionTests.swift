// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import Testing
import WellkeptCore

//  StorageSectionTests.swift
//  ViewShots (the bundle that compiles `App`)
//
//  ⭐ **The law this section exists to keep, asserted rather than remembered.**
//
//  Machine junk regenerates and may be pre-selected. A person's own files are revealed, sized and
//  sorted, and are **never** pre-selected and never swept. Four separate mechanisms enforce it —
//  `Origin.mayBePreSelected`, `Item.mayBePreSelected`, `StorageRow.preSelected` and
//  `StorageModel.setTicked` — and the point of these tests is that defeating any one of them still
//  produces the safe answer.
//
//  The rest of the file is about the two ceremonies, the two numbers, and the demo Macs: nothing
//  either of them shows may be something the real readers could not produce.

@Suite("⭐ Nothing of yours is ever ticked")
@MainActor
struct StorageLawTests {

    private var bothMacs: [StorageAnswer] { [DemoData.storage(.healthy), DemoData.storage(.problems)] }

    /// The topic-level rule, on every row of both demo Macs.
    @Test func onlyMachineJunkEverArrivesTicked() {
        for answer in bothMacs {
            for row in answer.report.rows where row.topic != .machineJunk {
                #expect(row.preSelected.isEmpty,
                        "\(row.topic.label) arrived with something ticked")
            }
        }
    }

    /// And everything that *is* ticked is the machine's and can actually be moved.
    @Test func everythingTickedIsTheMachinesAndCanBeMoved() {
        for answer in bothMacs {
            for item in answer.preSelected {
                #expect(item.origin == .machineJunk)
                #expect(item.handling.mayOfferAButton)
                #expect(item.cloudStanding.occupiesSpaceHere)
            }
        }
    }

    /// ⭐ **The mechanism, not the intention.** Hand the row a person's own file, claim it may be
    /// pre-selected, and it still comes back with nothing ticked — because `preSelected` asks the
    /// topic first and `Item.mayBePreSelected` asks `Origin` underneath that.
    @Test func aPersonsFileInTheJunkRowIsStillNotTicked() {
        let mine = Item(identity: ItemIdentity(volumeUUID: nil, volumeDevice: "/dev/disk1s1", inode: 7),
                        path: "/Users/sample/Documents/Taxes 2024.pdf",
                        bytes: Bytes.allOfIt(SizeOnDisk(4_000_000)),
                        kind: .file,
                        reason: "It is large.")
        let row = StorageRow(topic: .machineJunk, headline: "…", items: [mine])
        #expect(row.preSelected.isEmpty)
        #expect(!mine.mayBePreSelected)
    }

    /// The same file, ticked by hand in the model. `setTicked` refuses to record it, and even a
    /// forced id cannot become an item to act on.
    @Test func nothingOfYoursCanBeSweptEvenWhenTicked() async {
        let model = StorageModel(home: URL(filePath: NSTemporaryDirectory()))
        let mine = Item(identity: ItemIdentity(volumeUUID: nil, volumeDevice: "/dev/disk1s1", inode: 9),
                        path: "/Users/sample/Movies/Wedding.mov",
                        bytes: Bytes.allOfIt(SizeOnDisk(9_000_000_000)),
                        kind: .file,
                        reason: "It is large.")
        let row = StorageRow(topic: .machineJunk, headline: "…", items: [mine])
        let everything = Set([mine.id])

        model.setTicked(mine, true)
        #expect(!model.isTicked(mine, arrivesTicked: true))
        #expect(model.tickedItems(in: row, arriving: everything).isEmpty)
        #expect(model.tickedBytes(in: row, arriving: everything).isZero)

        // And the sweep-everything control cannot reach it either.
        model.setAllTicked(true, in: row)
        #expect(model.tickedItems(in: row, arriving: everything).isEmpty)
    }


    /// ⭐ **Machine junk arrives ticked with no scan behind it**, which is the state demo mode and
    /// every view-shot are in. The first version of the model stored the ticked ids and seeded them
    /// when a scan landed, so this case drew an empty batch and a button that said "Set Aside 0
    /// Things"; the picture caught it. Pre-selection is now the absence of a record.
    @Test func junkArrivesTickedWithNoScanBehindIt() {
        let model = StorageModel(home: URL(filePath: NSTemporaryDirectory()))
        let junk = Item(identity: ItemIdentity(volumeUUID: nil, volumeDevice: "/dev/disk1s1", inode: 11),
                        path: "/Users/sample/Library/Caches/whatever",
                        bytes: Bytes.allOfIt(SizeOnDisk(600_000_000)),
                        kind: .folder,
                        origin: .machineJunk,
                        handling: .canBeSetAside,
                        reason: "A store where every file is named after a checksum.")
        let row = StorageRow(topic: .machineJunk, headline: "…", items: [junk])
        let arriving = Set([junk.id])
        #expect(model.isTicked(junk, arrivesTicked: true))
        #expect(model.tickedItems(in: row, arriving: arriving).count == 1)

        model.setTicked(junk, false)
        #expect(!model.isTicked(junk, arrivesTicked: true))
        #expect(model.tickedItems(in: row, arriving: arriving).isEmpty)
    }

    /// ⚠️ **The annoyance filter survives all the way to the checkbox.** The classifier unticked the
    /// half-finished download that was used this month; nothing in the model puts that tick back,
    /// and the whole rest of the batch is still ticked around it.
    @Test func theClassifiersDecisionIsTheDefault() {
        let model = StorageModel(home: URL(filePath: NSTemporaryDirectory()))
        let answer = DemoData.storage(.problems)
        guard let row = answer.report.row(.machineJunk) else {
            Issue.record("the unwell demo Mac has no machine-junk row")
            return
        }
        let arriving = Set(JunkClassifier.arrivingTicked(answer.junk).map(\.id))
        let ticked = model.tickedItems(in: row, arriving: arriving)

        #expect(!ticked.isEmpty)
        #expect(ticked.count == arriving.count)
        for declined in answer.junk where !declined.arrivesTicked {
            #expect(!ticked.contains { $0.id == declined.item.id })
        }

        // And "Tick All" is a person overriding it, which is what that control means.
        model.setAllTicked(true, in: row)
        #expect(model.tickedItems(in: row, arriving: arriving).count == row.preSelected.count)
    }

    /// A person's own row has no batch anywhere: `Origin.yours` refuses a sweep, and its ceremony is
    /// the one-at-a-time one.
    @Test func yoursIsNeverSwept() {
        #expect(!Origin.yours.maySweep)
        #expect(Origin.yours.ceremony == .oneAtATime)
        #expect(Origin.machineJunk.maySweep)
        #expect(Origin.machineJunk.ceremony == .batch)
    }

    /// ⭐ Exactly one of the five rows has ticks on it, and the screen says which.
    @Test func exactlyOneRowIsABatch() {
        let batches = StorageTopic.allCases.filter { $0.ceremony == .batch }
        #expect(batches == [.machineJunk])
        #expect(StorageTopic.allCases.filter(\.mayArrivePreSelected) == [.machineJunk])
    }
}

@Suite("The two ceremonies say which one you are in")
@MainActor
struct StorageCeremonyTests {

    /// The sheet quotes **what comes back**, not the size on disk. On a Mac with a stuck
    /// snapshot the two are up to 150× apart.
    @Test func theSheetQuotesTheSecondNumber() {
        let held = Bytes(onDisk: SizeOnDisk(12_000_000_000), recoverableToday: .nothing)
        let free = Bytes.allOfIt(SizeOnDisk(12_000_000_000))
        #expect(FreeSpace.Says.arithmetic(for: free).contains(free.recoverableToday.text))
        #expect(!FreeSpace.Says.arithmetic(for: held).contains("12"))
    }

    /// Both routes are on the sheet, and the second is the one for somebody who needs the room now.
    @Test func bothRoutesExist() {
        #expect(!FreeSpace.Says.setAsideOnly.isEmpty)
        #expect(FreeSpace.Says.setAsideAndEmpty.lowercased().contains("empty"))
        #expect(FreeSpace.Says.setAsideOnly != FreeSpace.Says.setAsideAndEmpty)
    }

    /// ⚠️ The second route removes what is already waiting too, and the sheet says so before it is
    /// pressed rather than after.
    @Test func theSheetSaysWhatElseEmptyingRemoves() {
        let summary = Quarantine.Summary(count: 3, bytes: 12_600_000_000, oldest: Date(),
                                         readyCount: 1, unaccountedFor: 0, trouble: nil)
        let line = StorageWords.emptyingAlsoRemoves(summary)
        #expect(line.contains("3 other items"))
        #expect(line.contains(StorageManifest.readable(12_600_000_000)))
    }

    /// The batch's button counts what it is about to move, and says so in the label.
    @Test func theBatchButtonCountsWhatItMoves() {
        #expect(StorageWords.batchButton(1).contains("1"))
        #expect(StorageWords.batchButton(7).contains("7"))
    }

    /// ⭐ The two ceremony lines are different sentences, so a person can tell the lists apart
    /// without counting checkboxes.
    @Test func theTwoCeremoniesAreNamedDifferently() {
        #expect(StorageWords.thisOneIsABatch != StorageWords.thisOneIsOneAtATime)
        #expect(StorageWords.thisOneIsOneAtATime.lowercased().contains("nothing here is ticked"))
    }
}

@Suite("⭐ Two numbers, and a section that adds up")
struct StorageArithmeticTests {

    /// Every measured row on both demo Macs carries **both** figures. There is no initialiser that
    /// could produce one.
    @Test func everyMeasureCarriesBothNumbers() {
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            for row in answer.report.rows {
                guard let measure = row.measure else { continue }
                #expect(measure.recoverableToday.bytes <= measure.onDisk.bytes)
                #expect(!measure.text.isEmpty)
            }
        }
    }

    /// ⭐ The unwell Mac's stuck snapshot really does take the second number away, and it does so by
    /// arithmetic rather than by assertion — the files are older than the snapshot.
    @Test func aStuckSnapshotTakesTheSecondNumberAway() {
        let answer = DemoData.storage(.problems)
        #expect(answer.report.freeSpace.snapshots.isStuck())
        let mine = answer.report.row(.yourOwnFiles)
        let older = mine?.items.filter { item in
            guard let changed = item.modifiedOn,
                  let oldest = answer.report.freeSpace.snapshots.oldest else { return false }
            return changed < oldest.takenOn
        } ?? []
        #expect(!older.isEmpty)
        for item in older { #expect(item.bytes.recoverableToday.isZero) }
    }

    /// The healthy Mac's snapshot is doing its job, so recent things really do come back.
    @Test func aWorkingSnapshotLetsRecentThingsComeBack() {
        let answer = DemoData.storage(.healthy)
        let junk = answer.report.row(.machineJunk)?.items ?? []
        #expect(junk.contains { !$0.bytes.recoverableToday.isZero })
    }

    /// ⭐ **The gap is named, never hidden in an "Other" slice.** It cannot be omitted: the report
    /// computes it from a required argument, and the sentence is in the lines under the headline.
    @Test func theGapIsNamedOnBothMacs() {
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            #expect(answer.report.gap.worthExplaining)
            #expect(answer.report.linesUnderTheHeadline.contains(answer.report.gap.sentence))
            // ⚠️ The sentence names what is in the gap. It never labels it — there is no wedge
            // called "Other" here and no category the difference gets filed under.
            #expect(answer.report.gap.sentence.contains(answer.report.gap.difference.text))
            #expect(answer.report.gap.sentence.contains(answer.report.measured.text))
        }
    }

    /// Finder's figure is printed, explained, and never added to anything.
    @Test func finderIsExplainedRatherThanContradicted() {
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            let picture = answer.report.freeSpace
            let finder = picture.finderLine
            #expect(finder?.contains("Finder") == true)
            #expect(picture.differenceLine != nil)
            #expect(answer.report.linesUnderTheHeadline.first == picture.finderLine)
        }
    }

    /// ⚠️ The ruling: the snapshot problem is said out loud, as one flat line, on the face.
    @Test func theSnapshotProblemIsSaidOutLoud() {
        let answer = DemoData.storage(.problems)
        let line = answer.report.snapshotLine
        #expect(line?.isEmpty == false)
        #expect(answer.report.linesUnderTheHeadline.contains(line ?? ""))
    }
}

@Suite("The five rows, in order, and never a fault")
struct StorageRowShapeTests {

    @Test func theFiveRowsAreAlwaysInTopicOrder() {
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            #expect(answer.report.rows.map(\.topic) == StorageTopic.allCases)
        }
    }

    /// ⚠️ Revealing a person's files is never a fault. Nothing on these rows can carry a colour.
    @Test func noRowIsEverWorseThanInformation() {
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            for row in answer.report.rows {
                #expect(row.severity == .information)
                #expect(row.status != .needsAttention)
            }
        }
    }

    /// A ledger nobody could read is **not** an empty quarantine. It refuses to report a figure.
    @Test func anUnreadableLedgerIsNeverAZero() {
        let trouble = Quarantine.Summary(count: 0, bytes: 0, oldest: nil, readyCount: 0,
                                         unaccountedFor: 0,
                                         trouble: LedgerTrouble(kind: .couldNotBeOpened,
                                                                path: "/Users/sample/ledger.json",
                                                                underlying: "Operation not permitted",
                                                                keptAt: nil))
        let row = StorageScan.setAsideRow(trouble, snapshots: .none)
        #expect(row.unreadable != nil)
        #expect(row.measure == nil)
        #expect(row.count == nil)
        #expect(row.items.isEmpty)
    }

    /// And neither is a ledger that was never read at all.
    @Test func noSummaryIsNotAnEmptyQuarantine() {
        let row = StorageScan.setAsideRow(nil, snapshots: .none)
        #expect(row.unreadable != nil)
        #expect(row.measure == nil)
    }

    /// ⚠️ The set-aside row never promises a figure before the fact. What it says emptying would do
    /// is an estimate, and it says so.
    @Test func theSetAsideRowNeverPromisesAFigure() {
        let held = SnapshotStanding(snapshots: [
            LocalSnapshot(name: "stuck", takenOn: Date().addingTimeInterval(-30 * 86_400)),
        ])
        let summary = Quarantine.Summary(count: 2, bytes: 40_000_000_000,
                                         oldest: Date().addingTimeInterval(-40 * 86_400),
                                         readyCount: 1, unaccountedFor: 0, trouble: nil)
        let row = StorageScan.setAsideRow(summary, snapshots: held)
        #expect(row.measure?.recoverableToday.isZero == true)
        let estimate = row.details.first { $0.label == "What emptying it would do" }?.value
        #expect(estimate?.contains("snapshot") == true)
    }

    /// The picture row is a picture: no items, therefore nothing anywhere to press.
    @Test func thePictureRowHasNothingToPress() {
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            let row = answer.report.row(.whatIsUsingSpace)
            #expect(row?.items.isEmpty == true)
            #expect(row?.preSelected.isEmpty == true)
        }
    }

    /// ⚠️ We never nominate an original, and the sentence saying so travels with the row.
    @Test func duplicatesNeverNominateAnOriginal() {
        let answer = DemoData.storage(.problems)
        let row = answer.report.row(.duplicates)
        #expect(row?.reason?.contains(Duplicates.Group.weNeverChoose) == true)
        #expect(answer.groups.allSatisfy { !$0.insideAProject })
    }
}

@Suite("The two demo Macs show nothing the readers could not produce")
struct StorageDemoTests {

    /// ⚠️ Every junk item's reason is the classifier's own — the sentence that names the program
    /// which writes the thing again. Nothing in the demo invents grounds for a tick.
    @Test func everyJunkReasonIsTheClassifiersOwn() {
        let known = Set(JunkClassifier.Category.allCases.map(\.reason))
            .union(JunkClassifier.Category.allCases.map {
                "\($0.whatItIs) \(JunkClassifier.whyARuntimeHasNoButton)"
            })
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            for classified in answer.junk {
                #expect(known.contains(classified.item.reason),
                        "invented reason: \(classified.item.reason)")
                #expect(classified.item.origin == .machineJunk)
            }
        }
    }

    /// Everything on the person's own row is `.yours`, which is the default and therefore also the
    /// answer when somebody forgets the argument.
    @Test func everythingOnTheOwnFilesRowIsYours() {
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            for item in answer.report.row(.yourOwnFiles)?.items ?? [] {
                #expect(item.origin == .yours)
                #expect(!item.mayBePreSelected)
            }
        }
    }

    /// ⛔ The simulator runtimes are on the unwell Mac, reported, with no button.
    @Test func theRuntimesAreReportedAndHaveNoButton() {
        let answer = DemoData.storage(.problems)
        let runtimes = answer.junk.filter { $0.judgement.category == .simulatorRuntime }
        #expect(runtimes.count == 2)
        for runtime in runtimes {
            #expect(!runtime.arrivesTicked)
            #expect(!runtime.item.handling.mayOfferAButton)
        }
    }

    /// The annoyance filter takes a tick away and says why. It never puts one on.
    @Test func theAnnoyanceFilterOnlyEverUnticks() {
        let answer = DemoData.storage(.problems)
        let recent = answer.junk.first { $0.judgement.category == .halfFinishedDownload }
        #expect(recent?.arrivesTicked == false)
        #expect(recent?.judgement.notTickedBecause == JunkClassifier.usedThisMonth)
    }

    /// ⚠️ **The healthy Mac raises nothing.** Storage's only Overview row is a disk with no room
    /// left; a large folder is never something that needs you.
    @Test func theHealthyMacRaisesNothing() {
        let answer = DemoData.storage(.healthy)
        #expect(answer.report.overviewFinding == nil)
        #expect(answer.report.freeSpace.pressure == .comfortable)
        #expect(answer.report.status == .good)
        #expect(answer.report.complete)
    }

    /// And the unwell one raises exactly one thing, about the disk and nothing else.
    @Test func theUnwellMacRaisesOnlyTheFullDisk() {
        let answer = DemoData.storage(.problems)
        let finding = answer.report.overviewFinding
        #expect(finding?.severity == .problem)
        #expect(finding?.section == .storage)
        #expect(DemoData.findings(.problems).filter { $0.section == .storage }.count == 1)
    }

    /// ⚠️ **The one state Overview must never get wrong.** 54 folders could not be read, so the
    /// unwell Mac's record is incomplete — and it comes out of the report rather than being asserted
    /// by the demo.
    @Test func theUnwellMacIsHonestlyIncomplete() {
        let answer = DemoData.storage(.problems)
        #expect(!answer.report.complete)
        #expect(answer.report.refused.count == 54)
        #expect(answer.report.refused.sentence != nil)
        #expect(DemoData.records(.problems)[.storage]?.complete == false)
        #expect(DemoData.records(.healthy)[.storage]?.complete == true)
    }

    /// The demo answer is built once, so its Overview row keeps a stable identity between draws.
    @Test func theDemoAnswerIsCachedRatherThanRebuilt() {
        #expect(DemoData.storage(.problems).report.overviewFinding?.id
                == DemoData.storage(.problems).report.overviewFinding?.id)
        #expect(DemoData.storage(.healthy).report.ranAt == DemoData.storage(.healthy).report.ranAt)
    }

    /// Nothing on either Mac is a real path on this one.
    @Test func nothingInTheDemoNamesThisMac() {
        let home = StorageManifest.home().path(percentEncoded: false)
        for answer in [DemoData.storage(.healthy), DemoData.storage(.problems)] {
            for row in answer.report.rows {
                for item in row.items {
                    #expect(!item.path.hasPrefix(home), "the demo names a real path: \(item.path)")
                }
            }
        }
    }
}

@Suite("What the junk sweep looks at, and what it never convicts for")
struct JunkSweepTests {

    /// ⚠️ **Location narrows where we look; it never convicts.** The sweep's starting points are all
    /// under the home folder, and each one is only a hint — every candidate is still judged by
    /// `JunkClassifier`, which is what keeps the 1.3 GB audiobook in `~/Library/Caches` safe.
    @Test func everyStartingPointIsUnderTheHomeFolder() {
        #expect(!JunkSweep.places.isEmpty)
        for place in JunkSweep.places {
            #expect(!place.relativePath.hasPrefix("/"))
            #expect(!place.name.isEmpty)
        }
    }

    /// The row names each category's regeneration story, which is the thing that makes a tick
    /// defensible in the first place.
    @Test func theRowNamesWhatWritesEachThingAgain() {
        let answer = DemoData.storage(.problems)
        let row = answer.report.row(.machineJunk)
        let details = row?.details ?? []
        #expect(details.contains { $0.label == JunkClassifier.Category.xcodeBuildOutput.label })
        #expect(details.contains {
            $0.value.contains(JunkClassifier.Category.xcodeBuildOutput.howItComesBack)
        })
    }

    /// An empty sweep says so rather than showing an empty list with no explanation.
    @Test func anEmptySweepSaysWhyItIsEmpty() {
        let row = JunkSweep.row(JunkSweep.Found(junk: [], refused: .sawEverything, considered: 12))
        #expect(row.measure == nil)
        #expect(row.items.isEmpty)
        #expect(row.headline == JunkSweep.Says.nothingFound)
    }

    /// A refusal is carried on the row rather than swallowed, and it makes the run incomplete only
    /// where a person could actually lift it.
    @Test func aRefusalIsCarriedRatherThanSwallowed() {
        let row = JunkSweep.row(JunkSweep.Found(
            junk: [],
            refused: UnreadablePlaces(count: 3, notable: ["your Trash"], why: .notPermitted),
            considered: 12))
        #expect(row.refused.count == 3)
        #expect(!row.complete)
    }
}
