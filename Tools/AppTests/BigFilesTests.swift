// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import Testing
import WellkeptCore

//  BigFilesTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The law: a person's own files are revealed, sized and sorted, and NEVER pre-selected.**
//
//  Everything here runs inside a throwaway home folder made thirty milliseconds earlier. Nothing
//  touches a real one, nothing is moved, and nothing is deleted — the only writing these tests do
//  is making their own fixtures.

@Suite("A person's own files are revealed and never chosen for them")
struct BigFilesTests {

    /// A file of `bytes` real bytes, made without holding it all in memory.
    @discardableResult
    static func realFile(_ url: URL, bytes: Int, byte: UInt8 = 0x41) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: byte, count: bytes).write(to: url)
        return url
    }

    /// ⚠️ **A sparse file: enormous by name, nothing on the disk.** It stands in for the 15,593
    /// iCloud placeholders on this Mac that look like 72 GB and occupy zero bytes — the same trap,
    /// reachable without an iCloud account.
    @discardableResult
    static func sparseFile(_ url: URL, claiming bytes: Int64) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let descriptor = open(url.path(percentEncoded: false), O_CREAT | O_WRONLY, 0o644)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        try #require(ftruncate(descriptor, off_t(bytes)) == 0)
        return url
    }

    static func read(_ sandbox: QuarantineSandbox,
                     snapshots: SnapshotStanding = .none,
                     smallest: SizeOnDisk = SizeOnDisk(1),
                     listing: Int = 40) -> BigFiles.Answer? {
        // ⚠️ `elsewhere: []`. The default reaches for the iOS simulator runtimes, which is 30 GB of
        // real disk on the machine running the suite — correct in the product, absurd in a test.
        BigFiles.read(roots: [sandbox.home], home: sandbox.home, elsewhere: [],
                      snapshots: snapshots, listing: listing, smallest: smallest)
    }

    // MARK: - ⭐ The law

    /// **Nothing a person owns arrives ticked.** Three independent mechanisms have to agree, and
    /// this asserts all three: the item's own origin, the item's own answer, and the row's.
    @Test func nothingOfAPersonsIsEverPreSelected() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "Movies/holiday.mov"), bytes: 2_000_000)
        try Self.realFile(sandbox.home.appending(path: "Documents/report.pdf"), bytes: 600_000)

        let answer = try #require(Self.read(sandbox))

        #expect(!answer.items.isEmpty)
        for item in answer.items {
            #expect(item.origin == .yours, "\(item.name) was not filed as the person's own")
            #expect(item.mayBePreSelected == false)
            #expect(item.ceremony == .oneAtATime)
        }
        #expect(answer.row.preSelected.isEmpty)
        #expect(answer.row.topic.mayArrivePreSelected == false)
        #expect(Origin.yours.maySweep == false)
    }

    /// ⚠️ **A large folder is not a problem, it is large.** There is no argument anywhere on
    /// `StorageRow` that could make this row anything else.
    @Test func revealingSomebodysFilesIsNeverAFault() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "huge.bin"), bytes: 5_000_000)

        let answer = try #require(Self.read(sandbox))
        #expect(answer.row.severity == .information)
        #expect(answer.row.status == .good)
        #expect(answer.row.topic == .yourOwnFiles)
    }

    /// Every listed thing carries the reason it is listed, and the reason is that it is large.
    @Test func everyRowSaysWhyItIsThere() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "a.bin"), bytes: 1_500_000)

        let answer = try #require(Self.read(sandbox))
        for item in answer.items { #expect(!item.reason.isEmpty) }
        #expect(answer.row.reason?.isEmpty == false)
    }

    // MARK: - ⚠️ Size on disk, never the size it claims

    /// ⭐ **The measurement this file exists for.** 15,593 files in the real home folder look like
    /// 72 GB and occupy nothing. Sorted the obvious way, they fill the top of the screen.
    ///
    /// The sparse file here claims 500 MB and occupies nothing. It must not outrank a real 3 MB
    /// file, and it must not be counted in the total.
    @Test func aFileThatClaims500MBAndOccupiesNothingDoesNotComeFirst() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.sparseFile(sandbox.home.appending(path: "looks-enormous.bin"), claiming: 500_000_000)
        try Self.realFile(sandbox.home.appending(path: "actually-here.bin"), bytes: 3_000_000)

        let answer = try #require(Self.read(sandbox))
        let first = try #require(answer.items.first)
        #expect(first.name == "actually-here.bin",
                "the list is sorted on the size a file claims, not on what it occupies")
        #expect(answer.total.onDisk.bytes < 100_000_000,
                "a file occupying nothing was added to the total")
    }

    /// Largest first, and the order is on `bytes.onDisk`.
    @Test func theListIsLargestFirst() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        for (name, size) in [("small.bin", 400_000), ("middle.bin", 1_200_000), ("big.bin", 4_000_000)] {
            try Self.realFile(sandbox.home.appending(path: name), bytes: size)
        }
        let answer = try #require(Self.read(sandbox))
        #expect(answer.items.map(\.name).prefix(3) == ["big.bin", "middle.bin", "small.bin"])
        #expect(zip(answer.items, answer.items.dropFirst())
            .allSatisfy { $0.bytes.onDisk >= $1.bytes.onDisk })
    }

    /// Nothing trivial reaches the screen. A "largest files" list whose smallest entry is 300 KB has
    /// said nothing useful and has put a person's own note beside a button.
    @Test func thereIsAFloorAndItIsRespected() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "tiny.txt"), bytes: 20)
        try Self.realFile(sandbox.home.appending(path: "big.bin"), bytes: 3_000_000)

        let answer = try #require(Self.read(sandbox, smallest: SizeOnDisk(1_000_000)))
        #expect(answer.items.map(\.name) == ["big.bin"])
    }

    // MARK: - ⭐ Two numbers, never one

    /// **A stuck snapshot means deleting an old file returns nothing**, and the row has to say so.
    /// Measured on this Mac: `~/Documents/Media` is 14.8 GB on disk and 0.5 GB back today.
    @Test func aStuckSnapshotTakesTheSecondNumberToZero() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "old.bin"), bytes: 2_000_000)

        // A snapshot taken after everything in the sandbox was written.
        let held = SnapshotStanding(snapshots: [LocalSnapshot(name: "com.apple.TimeMachine.test",
                                                              takenOn: Date().addingTimeInterval(60))])
        let answer = try #require(Self.read(sandbox, snapshots: held))

        #expect(answer.total.onDisk.bytes > 0)
        #expect(answer.total.recoverableToday.isZero,
                "the snapshot is holding these blocks and the row promised them anyway")
        for item in answer.items { #expect(item.bytes.recoverableToday.isZero) }
    }

    /// With no snapshot at all, everything comes back — the other end of the same arithmetic.
    @Test func withNoSnapshotEverythingComesBack() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "new.bin"), bytes: 2_000_000)

        let answer = try #require(Self.read(sandbox, snapshots: SnapshotStanding.none))
        let item = try #require(answer.items.first)
        #expect(item.bytes.recoverableToday.bytes == item.bytes.onDisk.bytes)
        #expect(item.bytes.agree)
    }

    /// ⚠️ **A listing we could not read is not "there are none".** `couldNotBeRead` promises
    /// nothing at all, which is deliberately the smaller of the two possible answers.
    @Test func anUnreadSnapshotListPromisesNothing() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "new.bin"), bytes: 2_000_000)

        let answer = try #require(Self.read(sandbox, snapshots: .couldNotBeRead))
        #expect(answer.total.recoverableToday.isZero)
    }

    // MARK: - ⚠️ What the walk refuses to open

    /// A package is one thing to a person, so it is one row here — never the 200,000 files inside
    /// `Xcode.app`.
    @Test func aPackageIsTakenWholeAndNotOpened() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "Thing.app/Contents/MacOS/Thing"),
                          bytes: 2_000_000)
        try Self.realFile(sandbox.home.appending(path: "Thing.app/Contents/Resources/big.data"),
                          bytes: 1_000_000)

        let answer = try #require(Self.read(sandbox))
        #expect(answer.items.map(\.name) == ["Thing.app"])
        let bundle = try #require(answer.items.first)
        #expect(bundle.kind == .bundle)
        #expect(bundle.bytes.onDisk.bytes >= 3_000_000, "the package was not weighed whole")
    }

    /// ⭐ **Measured and never offered.** The Trash is on `ScanPolicy.neverOffered`: worth a size,
    /// never a button, and its contents are not listed one by one.
    @Test func aRefusedPlaceIsSizedAndCarriesNoButton() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: ".Trash/thrown-away.bin"), bytes: 3_000_000)

        let answer = try #require(Self.read(sandbox))
        let trash = try #require(answer.items.first { $0.path.hasSuffix("/.Trash") })

        #expect(trash.name == "your Trash")
        #expect(trash.handling.mayOfferAButton == false)
        #expect(trash.handling.why?.isEmpty == false)
        #expect(trash.bytes.onDisk.bytes >= 3_000_000)
        #expect(answer.items.contains { $0.name == "thrown-away.bin" } == false,
                "the contents of a refused place were listed one by one")
    }

    /// A symbolic link is never followed and never counted. Following one is how a walk leaves the
    /// volume, loops, or counts the same folder twice under a second name.
    @Test func aSymbolicLinkIsNeverFollowed() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let real = try Self.realFile(sandbox.home.appending(path: "real/big.bin"), bytes: 3_000_000)
        try sandbox.link("shortcut.bin", to: real)
        try sandbox.link("shortcut-folder", to: real.deletingLastPathComponent())

        let answer = try #require(Self.read(sandbox))
        #expect(answer.items.map(\.name) == ["big.bin"])
        #expect(answer.filesSeen == 1, "a link was counted as a second copy of its target")
    }

    // MARK: - Where the weight sits

    /// The folder roll-up and the file list are separate, because merging them counts the same
    /// bytes twice.
    @Test func placesAndItemsAreTwoListsNotOne() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "Documents/Media/film.mov"), bytes: 4_000_000)
        try Self.realFile(sandbox.home.appending(path: "Documents/note.txt"), bytes: 1_000)

        let answer = try #require(Self.read(sandbox))
        #expect(answer.places.contains { $0.name == "Documents" })
        #expect(answer.places.contains { $0.name == "Documents/Media" })
        // ⚠️ A `Place` is a picture and has no field that could carry a button.
        #expect(answer.places.allSatisfy { !$0.sentence.isEmpty })
        // The file list holds no plain folders, so the two columns can each be added up.
        #expect(answer.items.allSatisfy { $0.kind != .folder })
    }

    /// The total is the walk's, not the listed items' — and the two are never printed as the same
    /// number.
    @Test func theTotalAndTheListedTotalAreDifferentNumbers() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "big.bin"), bytes: 4_000_000)
        try Self.realFile(sandbox.home.appending(path: "small.bin"), bytes: 500_000)

        let answer = try #require(Self.read(sandbox, smallest: SizeOnDisk(1_000_000)))
        #expect(answer.items.count == 1)
        #expect(answer.total.onDisk > answer.listed.onDisk,
                "the row's measure is the listed items rather than everything walked")
    }

    // MARK: - Cancelling

    /// ⚠️ **A cancelled run returns nothing at all.** A partial total is not a shorter answer, it is
    /// a wrong one, and the first thing anybody would do with it is put it on a screen.
    @Test func aCancelledRunReturnsNothing() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "a.bin"), bytes: 100_000)

        let answer = BigFiles.read(roots: [sandbox.home], home: sandbox.home, elsewhere: [],
                                   snapshots: SnapshotStanding.none, smallest: SizeOnDisk(1),
                                   isCancelled: { true })
        #expect(answer == nil)
    }

    // MARK: - The thread I/O policy

    /// ⭐ The walk sets it itself, because it is per thread and "somebody remembered" is not a
    /// guarantee. Without it a read pulls a file down from iCloud.
    @Test func theWalkSetsTheIOPolicyItself() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.realFile(sandbox.home.appending(path: "a.bin"), bytes: 1_000)

        _ = Self.read(sandbox)
        #expect(ScanPolicy.thisThreadHoldsCloudFilesWhereTheyAre)
    }

    // MARK: - The words

    /// ⚠️ **Never "you have not opened this in seven years".** Blank for 61% of large files here,
    /// and 123 files in one sample share one date a batch job stamped on them.
    @Test func lastOpenedIsAFactAndNeverAnElapsedTime() {
        let words = [BigFiles.Says.whyLastOpenedIsOnlyAFact,
                     BigFiles.Says.whyTheseAreListed,
                     BigFiles.Says.because(SizeOnDisk(1_000_000)),
                     BigFiles.Says.howThisIsSorted]
        for line in words {
            let lower = line.lowercased()
            #expect(!lower.contains("years ago"))
            #expect(!lower.contains("haven't opened"))
            #expect(!lower.contains("have not opened this"))
            #expect(!lower.contains("unused"))
        }
    }

    /// A large file is described, never accused.
    @Test func theReasonIsADescriptionAndNotAnAccusation() {
        let reason = BigFiles.Says.because(SizeOnDisk(4_000_000_000)).lowercased()
        #expect(reason.contains("because it is large"))
        #expect(!reason.contains("should"))
        #expect(!reason.contains("waste"))
    }
}

// MARK: - ⭐ The structural guard

/// **A source scan, for the same reason as `ContainerGuardTests`.**
///
/// The realistic version of this mistake is not a deliberate one. It is a later owner adding
/// `origin: .machineJunk` to a scanner that reveals somebody's own files, because a batch sweep is
/// so much nicer to use — and every behaviour test still passes, because the classifier is where
/// everyone looks. By the time a test could observe the harm, a person's documents have arrived
/// on screen with their boxes ticked.
@Suite("Neither reader may file a person's own file as machine junk")
struct BigFilesOriginGuardTests {

    static let watched = ["App/Storage/BigFiles.swift", "App/Storage/Duplicates.swift"]

    static var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // Tools/AppTests
            .deletingLastPathComponent()   // Tools
            .deletingLastPathComponent()   // the repository
    }

    @Test func theGuardIsLookingAtRealFiles() {
        for relative in Self.watched {
            let text = try? String(contentsOf: Self.repoRoot.appending(path: relative),
                                   encoding: .utf8)
            #expect((text?.count ?? 0) > 2_000, "\(relative) was not found — the scan is looking in the wrong place")
        }
    }

    @Test func neitherReaderEverWritesMachineJunk() {
        var offenders: [String] = []
        for relative in Self.watched {
            guard let text = try? String(contentsOf: Self.repoRoot.appending(path: relative),
                                         encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Prose in a comment is how the reason gets recorded; only code counts.
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                if line.contains(".machineJunk") { offenders.append("\(relative):\(number + 1)") }
            }
        }
        #expect(offenders.isEmpty, """
            These file a person's own files as machine junk: \(offenders.joined(separator: ", ")).
            Machine junk may arrive pre-selected and may be swept in a batch. A person's own files
            may not, ever. Both readers pass `origin: .yours` and nothing else.
            """)
    }
}
