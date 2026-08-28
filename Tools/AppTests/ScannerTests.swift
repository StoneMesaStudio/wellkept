// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import Darwin
import WellkeptCore

//  ScannerTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The walk everything else in Storage depends on, proved against real files.**
//
//  Every fixture here is made inside a `ProvingGround`, a temporary directory that throws rather
//  than hand out a path outside itself. Nothing in this file touches, reads or changes anything on
//  this Mac that it did not create thirty milliseconds earlier — with one deliberate exception,
//  `theRootsAreTheDataVolumeAndNeverTheSystemOne`, which reads the volume layout and nothing else.
//
//  ## The four claims worth proving, and why they are these four
//
//  1. **The total is the size on disk.** Apparent size was wrong by 56% on this Mac and unstable
//     between runs. A test that only checked "it added up to something" would pass on either.
//  2. **A file that is not here is told apart from a file that is here and sparse.** They have the
//     same size, the same block count and the same everything except one flag. Getting this wrong
//     puts somebody's sparse disk image on a list headed "using no space here".
//  3. **A hard link is one file with two names.** 460 MB of difference inside `~/Sites` alone.
//  4. **A folder we were refused is named, never counted as empty.** Without Full Disk Access, 54
//     folders in this home directory cannot be read, and the two biggest wins on most Macs — the
//     Trash and the Photos library — are usually among them.

// MARK: - What it measures

@Suite("The scan measures what is on the disk")
struct ScannerMeasurementTests {

    /// ⭐ The total is `st_blocks × 512` — what the disk actually holds — and not what the files
    /// claim. Proved against the filesystem's own reading rather than against a number typed here,
    /// because a hand-typed expectation is a second guess at the same question.
    @Test func theTotalIsTheSizeOnDiskAndNotTheApparentSize() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let one = try ground.file("papers/first.txt", String(repeating: "a", count: 40_000))
        let two = try ground.file("papers/second.txt", String(repeating: "b", count: 9_000))
        try ground.folder("papers/empty")

        let survey = Scanner.walk(plan(ground))

        #expect(survey.files == 2)
        #expect(survey.measured.bytes == blocks(one) + blocks(two))
        // The apparent total is smaller here — 49,000 bytes of text in 56 KB of blocks — which is
        // the whole reason the two are different types.
        #expect(survey.measured.bytes > 49_000)
    }

    /// Every folder's total is the sum of everything beneath it, and the root's total is the whole
    /// walk. The rolling-up happens once per folder as it closes; a mistake there shows up as a
    /// parent smaller than its child.
    @Test func folderTotalsRollUpIntoTheirParents() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        try ground.file("work/deep/one.bin", String(repeating: "x", count: 30_000))
        try ground.file("work/deep/two.bin", String(repeating: "x", count: 30_000))
        try ground.file("work/loose.bin", String(repeating: "x", count: 10_000))

        let survey = Scanner.walk(plan(ground))

        let work = try #require(survey.folderTotals.first { $0.name == "work" })
        let deep = try #require(survey.folderTotals.first { $0.name == "deep" })

        #expect(deep.files == 2)
        #expect(work.files == 3)
        #expect(work.bytes.onDisk > deep.bytes.onDisk)
        #expect(work.bytes.onDisk.bytes == survey.measured.bytes)
    }

    /// ⚠️ Foundation hands back a folder's path with a trailing slash and a file's without one. Two
    /// spellings of one folder would show up as two rows on the same screen, and as two keys
    /// anywhere a path is used as one.
    @Test func aFolderIsSpelledTheSameWayAsEverythingElse() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        try ground.file("work/deep/one.bin", "x")

        var entries: [Scanner.Entry] = []
        let survey = Scanner.walk(plan(ground), onEntry: { entries.append($0) })

        for entry in entries {
            #expect(entry.path.hasSuffix("/") == false, "\(entry.path) is spelled with a trailing slash")
        }
        for folder in survey.folderTotals {
            #expect(folder.path.hasSuffix("/") == false, "\(folder.path) is spelled with a trailing slash")
        }
    }

    /// ⭐ **Both numbers, and they are not the same number.** With a snapshot from after everything
    /// was written, nothing comes back today — which is exactly the state this Mac is in, and the
    /// reason its figures look pessimistic beside every other tool's.
    @Test func aStuckSnapshotMeansNothingComesBackToday() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        try ground.file("papers/first.txt", String(repeating: "a", count: 40_000))

        let held = SnapshotStanding(snapshots: [
            LocalSnapshot(name: "com.apple.TimeMachine.2099-01-01-000000.local",
                          takenOn: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365))
        ])
        let heldSurvey = Scanner.walk(plan(ground, snapshots: held))
        #expect(heldSurvey.measured.bytes > 0)
        #expect(heldSurvey.bytes.recoverableToday.isZero)
        #expect(heldSurvey.bytes.agree == false)

        // With no snapshots at all, a delete returns the whole file.
        let free = Scanner.walk(plan(ground, snapshots: .none))
        #expect(free.bytes.recoverableToday.bytes == free.measured.bytes)
        #expect(free.bytes.agree)
    }

    /// ⚠️ A walk handed no snapshot reading promises **nothing**. Under-promising is recoverable;
    /// over-promising is the app caught lying.
    @Test func aWalkWithNoSnapshotReadingPromisesNothing() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        try ground.file("papers/first.txt", String(repeating: "a", count: 40_000))

        let survey = Scanner.walk(Scanner.Plan(roots: [ground.home], home: ground.home))
        #expect(survey.measured.bytes > 0)
        #expect(survey.bytes.recoverableToday.isZero)
    }
}

// MARK: - ⭐ Files that are not here

@Suite("A file in iCloud and a sparse file are told apart")
struct ScannerCloudTests {

    /// ⭐ **The measurement this test exists for.** An iCloud placeholder reads `blocks=0`,
    /// `size=2.9 MB`, `flags=0x40000060`. A sparse file reads `blocks=0`, `size=104857600`,
    /// `flags=0x0`. Every number is the same shape; only the flag differs.
    ///
    /// Deciding on the numbers would put somebody's sparse disk image under "in iCloud, using no
    /// space here" — and then offer to set aside a file that is very much here.
    @Test func aSparseFileIsNotMistakenForAFileThatLivesInTheCloud() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let sparse = try ground.sparseFile("images/disk.sparseimage", logicalBytes: 100_000_000)
        var status = stat()
        #expect(lstat(sparse.path(percentEncoded: false), &status) == 0)
        #expect(status.st_flags & Movable.dataless == 0, "the fixture is not what this test needs")

        let survey = Scanner.walk(plan(ground))

        #expect(survey.cloudHolding.isEmpty, "a sparse file was reported as living in iCloud")
        let entry = try #require(survey.largest.first { $0.name == "disk.sparseimage" })
        #expect(entry.cloudStanding == .onThisMac)
        #expect(entry.apparentBytes == 100_000_000)
        // A disk image by extension, whatever it is filled with.
        #expect(entry.kind == .diskImage)
    }

    /// The classification itself, both ways round, without needing an iCloud account to test it.
    @Test func onlyTheKernelFlagSaysAFileIsNotHere() {
        #expect(Scanner.cloudStanding(datalessFlags: Movable.dataless,
                                      mightNotBeHere: true) == .inTheCloudOnly)
        // The flag alone is not enough: a file with blocks behind it is here whatever it is marked.
        #expect(Scanner.cloudStanding(datalessFlags: Movable.dataless,
                                      mightNotBeHere: false) == .onThisMac)
        // Nor are the numbers alone — this is the sparse file.
        #expect(Scanner.cloudStanding(datalessFlags: 0, mightNotBeHere: true) == .onThisMac)
    }

    /// ⚠️ **The two keys that are not asked for.** Either one takes the walk from 6.0 s to 24.8 s on
    /// 200,886 files, and `st_flags` answers the same question for nothing. `.contentAccessDateKey`
    /// is absent for a different reason and must stay absent: our own scan rewrote 2,012 of them.
    @Test func theWalkNeverAsksForTheExpensiveOrThePoisonedKeys() {
        #expect(Scanner.keys.contains(.isUbiquitousItemKey) == false)
        #expect(Scanner.keys.contains(.ubiquitousItemDownloadingStatusKey) == false)
        #expect(Scanner.keys.contains(.contentAccessDateKey) == false)

        // And the ones it cannot do without.
        #expect(Scanner.keys.contains(.totalFileAllocatedSizeKey))
        #expect(Scanner.keys.contains(.fileIdentifierKey))
        #expect(Scanner.keys.contains(.linkCountKey))

        // It is the section's own set, narrowed — never a second idea of what to ask for.
        #expect(Scanner.keys.isSuperset(of: ScanPolicy.resourceKeys
            .subtracting([.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])))
    }
}

// MARK: - ⭐ One file, two names

@Suite("A hard link is one file with two names")
struct ScannerHardLinkTests {

    /// ⭐ 460 MB of difference inside `~/Sites` alone: 13.11 GB counting every name against
    /// 12.65 GB counting every inode. Both names are still shown; only the bytes are counted once.
    @Test func aHardLinkIsCountedOnceAndBothNamesAreStillSeen() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let original = try ground.file("build/product.bin", String(repeating: "z", count: 60_000))
        try ground.hardLink("build/alias.bin", to: original)

        var entries: [Scanner.Entry] = []
        let survey = Scanner.walk(plan(ground), onEntry: { entries.append($0) })

        #expect(survey.files == 2, "both names should be walked")
        #expect(survey.namesSharingBlocks == 1)
        #expect(survey.measured.bytes == blocks(original), "the blocks were counted twice")

        let counted = entries.filter { $0.countsTowardTheTotal && !$0.isFolder }
        #expect(counted.count == 1)
        #expect(entries.filter { $0.linkCount > 1 }.count == 2)

        // The same inode under two names, which is what makes it one file.
        let inodes = Set(entries.filter { !$0.isFolder }.map(\.identity.inode))
        #expect(inodes.count == 1)
    }

    /// A symbolic link is a thing in its own right and its target is never followed. Following one
    /// is how a walk leaves the volume, loops, or counts the same folder under two names.
    @Test func aSymbolicLinkIsNotFollowed() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let real = try ground.folder("real")
        try ground.file("real/inside.bin", String(repeating: "q", count: 50_000))
        try ground.link("shortcut", to: real.path(percentEncoded: false))

        var entries: [Scanner.Entry] = []
        let survey = Scanner.walk(plan(ground), onEntry: { entries.append($0) })

        // Two things that are not folders: the real file, and the link itself — which is a thing in
        // its own right and is worth showing. What must not happen is the target being walked
        // twice, once under each name.
        #expect(survey.files == 2)
        #expect(entries.filter { $0.name == "inside.bin" }.count == 1,
                "the link's target was walked a second time")
        let link = try #require(entries.first { $0.name == "shortcut" })
        #expect(link.kind == .link)
        #expect(link.bytes.onDisk.bytes < 4_096, "a link was sized as its target")
    }
}

// MARK: - ⭐ What we were not allowed to see

@Suite("A folder we cannot read is named, never counted as empty")
struct ScannerRefusalTests {

    /// ⭐ **Never a zero.** A folder that will not open is reported by name, the run is marked
    /// incomplete, and the remedy is the one permission Wellkept ever asks for.
    @Test func aFolderThatWillNotOpenIsReportedByNameAndMakesTheRunIncomplete() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        try ground.file("open/visible.bin", String(repeating: "v", count: 20_000))
        let shut = try ground.folder("locked")
        try ground.file("locked/hidden.bin", String(repeating: "h", count: 90_000))
        try ground.setMode(0o000, on: shut)
        defer { try? ground.setMode(0o755, on: shut) }

        let survey = Scanner.walk(plan(ground))

        #expect(survey.unreadable.isEmpty == false, "a refused folder was silently skipped")
        #expect(survey.unreadable.count >= 1)
        #expect(survey.unreadable.why == .notPermitted)
        #expect(survey.unreadable.stillComplete == false)
        #expect(survey.complete == false)
        #expect(survey.unreadable.remedy != nil, "the one refusal a person can lift has no button")

        let sentence = try #require(survey.unreadable.sentence)
        #expect(sentence.contains("locked"))
        // What it *could* read is still reported. A refusal is not a reason to throw away the rest.
        #expect(survey.measured.bytes > 0)
    }

    /// ⚠️ Not going somewhere is usually the **right** answer, and it must not leave Overview with
    /// a permanent caveat nobody can clear. Our own quarantine store is the clearest case: an engine
    /// that walked it would offer to quarantine the quarantine.
    @Test func wellkeptsOwnStoreIsSkippedWithoutMakingTheRunIncomplete() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        try ground.file("papers/real.txt", String(repeating: "r", count: 20_000))
        let store = StorageManifest.quarantineDirectory(home: ground.home)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try Data(String(repeating: "s", count: 80_000).utf8)
            .write(to: store.appending(path: "held.bin"))

        let survey = Scanner.walk(plan(ground))

        #expect(survey.skippedOnPurpose.contains { $0.why == .wellkeptsOwnStore })
        #expect(survey.unreadable.isEmpty, "a deliberate skip was reported as a refusal")
        #expect(survey.complete)
        #expect(survey.files == 1, "the quarantine store was counted as somebody's files")
    }

    /// The name on a refusal is the person's own word for the place where there is one. "your
    /// Trash" means something; "54 folders" means nothing.
    @Test func aRefusedPlaceIsNamedTheWayAPersonWouldNameIt() {
        let home = URL(filePath: "/Users/somebody")
        #expect(Scanner.friendlyName(for: "/Users/somebody/.Trash", home: home) == "your Trash")
        #expect(Scanner.friendlyName(for: "/Users/somebody/Library/Mail", home: home) == "your mail")
        // Anything not on the list still gets a name rather than a path.
        #expect(Scanner.friendlyName(for: "/Users/somebody/Odds", home: home) == "Odds")
    }
}

// MARK: - ⚠️ Where it goes, and how it stops

@Suite("The walk stays on the Data volume and can be stopped")
struct ScannerBoundaryTests {

    /// ⚠️ **Never `/`.** A walk from the root counts the disk twice and reports 501 GB used on a
    /// 494 GB drive. Reads the volume layout of this Mac and nothing else.
    @Test func theRootsAreTheDataVolumeAndNeverTheSystemOne() throws {
        let roots = Scanner.roots()
        #expect(roots.isEmpty == false)

        let scanVolume = try #require(
            Movable.volume(of: ScanPolicy.root().path(percentEncoded: false)))
        for root in roots {
            let path = root.path(percentEncoded: false)
            #expect(path != "/")
            let volume = try #require(Movable.volume(of: path))
            #expect(volume.isSealedSystem == false, "\(path) is on the sealed System volume")
            #expect(volume.isSameVolume(as: scanVolume), "\(path) is on another disk")
        }
        // /Users covers the home folder, /Users/Shared, and every other account.
        #expect(roots.contains { $0.path(percentEncoded: false) == "/Users" })
    }

    /// ⭐ Stopping is real. The totals a stopped walk hands back are a floor, and it says so.
    @Test func aStoppedWalkSaysSoRatherThanReportingAFullTotal() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        for index in 0..<3_000 {
            try ground.file("many/file-\(index).bin", "x")
        }

        var seen = 0
        let survey = Scanner.walk(plan(ground), stop: {
            seen += 1
            return seen > 2
        })

        #expect(survey.stoppedEarly)
        #expect(survey.complete == false)
        #expect(survey.files < 3_000)
    }

    /// ⭐ **The one line that stops a scan downloading somebody's photo library.** It is per thread,
    /// so the walk sets it itself rather than trusting a caller to have done it.
    @Test func theWalkingThreadHoldsCloudFilesWhereTheyAre() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        try ground.file("papers/one.txt", "hello")

        let survey = Scanner.walk(plan(ground))
        #expect(survey.heldCloudFilesWhereTheyAre)
        #expect(ScanPolicy.thisThreadHoldsCloudFilesWhereTheyAre)
    }

    /// The same walk through the async door, cancellable and off the main thread.
    @Test func theAsyncWalkReturnsTheSameAnswer() async throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        try ground.file("papers/one.txt", String(repeating: "o", count: 12_000))

        let survey = await Scanner.survey(plan(ground))
        #expect(survey.files == 1)
        #expect(survey.stoppedEarly == false)
        #expect(survey.heldCloudFilesWhereTheyAre)
    }
}

// MARK: - ⭐ What the walk refuses to decide

@Suite("The walk reveals and never classifies")
struct ScannerRestraintTests {

    /// ⭐ **The law, held by the type system.** An `Entry` has no `origin`, and the `Item` it builds
    /// defaults to `.yours` — so a scanner that is unsure, a fixture written in a hurry and a future
    /// caller that forgets the argument all produce something nobody may pre-tick and nobody may
    /// sweep.
    @Test func anItemBuiltFromAnEntryIsTheirsUntilSomebodySaysOtherwise() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        try ground.file("papers/tax-return.pdf", String(repeating: "t", count: 30_000))

        let survey = Scanner.walk(plan(ground, snapshots: .none))
        let entry = try #require(survey.largest.first)

        let item = entry.item(reason: "It is the largest thing in this folder.")
        #expect(item.origin == .yours)
        #expect(item.mayBePreSelected == false)
        #expect(item.ceremony == .oneAtATime)
        #expect(item.bytes.onDisk == entry.bytes.onDisk)
        #expect(item.reason.isEmpty == false)
    }

    /// ⚠️ Largest is by **size on disk**. A list built on what files claim puts the 15,593 things
    /// that are not on this Mac at the top of the screen.
    @Test func theLargestListIsSortedBySizeOnDiskNotByWhatFilesClaim() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        try ground.sparseFile("looks-huge.bin", logicalBytes: 200_000_000)
        try ground.file("actually-big.bin", String(repeating: "b", count: 400_000))

        let survey = Scanner.walk(plan(ground))
        let first = try #require(survey.largest.first)
        #expect(first.name == "actually-big.bin",
                "a file that claims 200 MB and occupies almost none was put at the top")
        #expect(first.apparentBytes < 500_000)
    }

    /// Progress names a place. ⚠️ Never a percentage, and never a time — the first scan after a
    /// restart has never been measured, so any figure would be a guess with a clock face on it.
    @Test func progressNamesAPlaceAndNeverATime() {
        let progress = Scanner.Progress(place: "Documents",
                                        thingsSeen: 40_000,
                                        measured: SizeOnDisk(12_000_000))
        #expect(progress.sentence == ScanPolicy.Running.at("Documents"))
        #expect(progress.sentence.contains("%") == false)
        #expect(progress.sentence.lowercased().contains("remaining") == false)
        #expect(progress.sentence.lowercased().contains("second") == false)
    }

    /// ⭐ **The gap is named, not drawn as a slice called "Other".** A survey that accounted for
    /// less than macOS says is used can produce the sentence on its own, before any row exists.
    @Test func theSurveyCanNameTheGapBetweenItselfAndWhatMacOSReports() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        try ground.file("papers/one.txt", String(repeating: "o", count: 20_000))

        let survey = Scanner.walk(plan(ground))
        let picture = FreeSpacePicture(capacity: SizeOnDisk(500_000_000_000),
                                       actuallyFree: SizeOnDisk(100_000_000_000),
                                       finderShows: FinderFigure(170_000_000_000),
                                       snapshots: .none,
                                       volumeName: "this Mac's disk")

        let gap = survey.gap(against: picture)
        #expect(gap.measured == survey.measured)
        #expect(gap.worthExplaining)
        #expect(gap.sentence.lowercased().contains("other ") || gap.sentence.contains("The other"))
        #expect(gap.sentence.contains("bookkeeping"))
    }

    /// ⚠️ The survey says what its own total gets wrong, and in which direction. Every competitor
    /// puts the difference in a slice labelled "Other", which is a number with the explanation
    /// removed.
    @Test func theSurveySaysWhatItsOwnTotalGetsWrong() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        try ground.file("papers/one.txt", "hello")

        let survey = Scanner.walk(plan(ground))
        #expect(survey.honestyNotes.count >= 2)
        #expect(survey.honestyNotes.contains { $0.contains("clone") })
        for note in survey.honestyNotes {
            #expect(note.hasSuffix("."))
        }
    }
}

// MARK: - Shared helpers

/// The plan every fixture walk uses: this sandbox and nothing else.
private func plan(_ ground: ProvingGround,
                  snapshots: SnapshotStanding = .none) -> Scanner.Plan {
    Scanner.Plan(roots: [ground.home],
                 home: ground.home,
                 snapshots: snapshots,
                 folderDepth: 4,
                 largestKept: 50)
}

/// The filesystem's own reading of a file's size on disk, for comparing against the walk's.
private func blocks(_ url: URL) -> Int64 {
    var status = stat()
    guard lstat(url.path(percentEncoded: false), &status) == 0 else { return -1 }
    return Int64(status.st_blocks) * 512
}
