// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import Testing
import WellkeptCore

//  DuplicatesTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The one that matters: an APFS clone is not a duplicate.**
//
//  Verified by hand on 2026-08-28 and asserted here. A `cp -c` clone and its original report the
//  same size, the same `st_blocks`, the same content and the same hash; `du` counts both at full
//  size. Every reading macOS offers says two files. The blocks say one. Without the check in
//  `Duplicates.blockClasses`, this row's headline is wrong by exactly one copy of every cloned file
//  on the disk — and it is wrong in the direction a person can disprove in a minute by deleting one
//  and watching nothing happen.
//
//  Every fixture is made inside a throwaway home folder. Nothing here touches a real one.

@Suite("Duplicates are tidiness, and a clone is not one")
struct DuplicatesTests {

    // MARK: Fixtures

    /// Random bytes, so two files of the same length are not accidentally identical.
    static func bytes(_ count: Int, seed: UInt64) -> Data {
        var state = seed &* 6_364_136_223_846_793_005 &+ 1
        var out = Data(count: count)
        out.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for index in 0..<count {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                base[index] = UInt8(truncatingIfNeeded: state >> 33)
            }
        }
        return out
    }

    @discardableResult
    static func write(_ url: URL, _ data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    /// ⚠️ **An APFS clone**, made the way the Finder makes one when it copies within a volume.
    @discardableResult
    static func clone(_ source: URL, to destination: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let made = source.path(percentEncoded: false).withCString { from in
            destination.path(percentEncoded: false).withCString { to in
                clonefile(from, to, 0)
            }
        }
        try #require(made == 0, "this filesystem does not clone, so the check cannot be exercised")
        return destination
    }

    @discardableResult
    static func hardLink(_ source: URL, to destination: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: source, to: destination)
        return destination
    }

    static func find(_ sandbox: QuarantineSandbox,
                     smallest: SizeOnDisk = SizeOnDisk(1_000)) -> Duplicates.Answer? {
        Duplicates.find(roots: [sandbox.home], home: sandbox.home, snapshots: SnapshotStanding.none,
                        smallest: smallest)
    }

    // MARK: - ⭐ The clone

    /// **The headline test.** Two names, one set of blocks: not a duplicate, not on the list, not in
    /// the total.
    @Test func aCloneIsNotADuplicate() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let original = try Self.write(sandbox.home.appending(path: "photos/original.raw"),
                                      Self.bytes(2_000_000, seed: 7))
        try Self.clone(original, to: sandbox.home.appending(path: "photos/clone.raw"))

        let answer = try #require(Self.find(sandbox))

        #expect(answer.groups.isEmpty, "a clone pair was offered as a duplicate")
        #expect(answer.sharedBlocks == 1)
        #expect(answer.tidiness.isZero)
    }

    /// The reading the whole check rests on, asserted on its own: a clone shares its first block
    /// with the original, and a real copy does not.
    @Test func theBlockCheckSeparatesACloneFromACopy() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let data = Self.bytes(3_000_000, seed: 11)
        let original = try Self.write(sandbox.home.appending(path: "a.bin"), data)
        let cloned = try Self.clone(original, to: sandbox.home.appending(path: "clone.bin"))
        let copied = try Self.write(sandbox.home.appending(path: "copy.bin"), data)

        let originalBlocks = try #require(Duplicates.physicalFingerprint(
            of: original.path(percentEncoded: false), length: 3_000_000))
        let cloneBlocks = try #require(Duplicates.physicalFingerprint(
            of: cloned.path(percentEncoded: false), length: 3_000_000))
        let copyBlocks = try #require(Duplicates.physicalFingerprint(
            of: copied.path(percentEncoded: false), length: 3_000_000))

        #expect(originalBlocks == cloneBlocks, "the clone did not report the original's blocks")
        #expect(Set(originalBlocks).isDisjoint(with: Set(copyBlocks)),
                "a real copy reported the original's blocks")
    }

    /// ⚠️ **`totalFileAllocatedSize` cannot tell them apart**, which is the reason the block check
    /// has to exist at all. If this ever starts failing, macOS has changed and the comment in
    /// `Duplicates.swift` needs rewriting — it does not mean the check is unnecessary.
    @Test func everySizeReadingReportsACloneAtFullSize() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let original = try Self.write(sandbox.home.appending(path: "a.bin"),
                                      Self.bytes(2_000_000, seed: 3))
        let cloned = try Self.clone(original, to: sandbox.home.appending(path: "clone.bin"))

        let one = try original.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        let two = try cloned.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        #expect(one.totalFileAllocatedSize == two.totalFileAllocatedSize)
        #expect((one.totalFileAllocatedSize ?? 0) >= 2_000_000)
    }

    // MARK: - ⚠️ Hard links

    /// Two names for one inode. Removing one returns nothing, and it is caught before anything is
    /// opened.
    @Test func aHardLinkIsNotASecondCopy() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let original = try Self.write(sandbox.home.appending(path: "a.bin"),
                                      Self.bytes(1_500_000, seed: 5))
        try Self.hardLink(original, to: sandbox.home.appending(path: "elsewhere/same.bin"))

        let answer = try #require(Self.find(sandbox))
        #expect(answer.groups.isEmpty, "a hard link was offered as a duplicate")
        #expect(answer.hardLinksFolded == 1)
    }

    // MARK: - What is actually a duplicate

    /// Two genuinely separate copies of the same bytes: one group, one decision.
    @Test func twoRealCopiesAreOneGroupAndOneDecision() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let data = Self.bytes(1_500_000, seed: 13)
        try Self.write(sandbox.home.appending(path: "Downloads/invoice.pdf"), data)
        try Self.write(sandbox.home.appending(path: "Documents/invoice.pdf"), data)

        let answer = try #require(Self.find(sandbox))
        let group = try #require(answer.groups.first)

        #expect(answer.groups.count == 1)
        #expect(group.copies.count == 2)
        #expect(group.judgementCalls == 1)
        #expect(answer.judgementCalls == 1)
        #expect(group.sharing == .separateCopies)
        #expect(group.extra.onDisk.bytes >= 1_500_000)
    }

    /// ⚠️ Two files of the same length that differ in the middle are not identical, and the cheap
    /// hash alone would not know — this is the case that proves the full compare runs.
    @Test func sameLengthIsNotSameContent() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        var first = Self.bytes(2_000_000, seed: 17)
        var second = first
        second[1_000_000] = first[1_000_000] &+ 1
        // The ends are identical, so only a full compare can separate them.
        #expect(first.prefix(65_536) == second.prefix(65_536))
        #expect(first.suffix(65_536) == second.suffix(65_536))
        try Self.write(sandbox.home.appending(path: "one.bin"), first)
        try Self.write(sandbox.home.appending(path: "two.bin"), second)
        first = Data(); second = Data()

        let answer = try #require(Self.find(sandbox))
        #expect(answer.groups.isEmpty, "two different files were called identical")
    }

    /// Below the floor nothing is compared. The whole `~/Documents` prize on this Mac is 387 MB
    /// across 633 decisions; going smaller buys nothing and costs a person their afternoon.
    @Test func smallFilesAreNotCompared() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let data = Self.bytes(50_000, seed: 19)
        try Self.write(sandbox.home.appending(path: "a.bin"), data)
        try Self.write(sandbox.home.appending(path: "b.bin"), data)

        let answer = try #require(Self.find(sandbox, smallest: SizeOnDisk(1_000_000)))
        #expect(answer.groups.isEmpty)
        #expect(Duplicates.smallestWorthComparing.bytes >= 1_000_000)
    }

    // MARK: - ⚠️ Project folders

    /// **94% of the identical files on this Mac are inside project folders**, where the second copy
    /// is a build system's output and removing it breaks the build. Those are not offered.
    @Test func aPairInsideAProjectIsLeftOutAndTheReasonIsSaid() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let data = Self.bytes(1_500_000, seed: 23)
        try Self.write(sandbox.home.appending(path: "project/Package.swift"), Data("// swift".utf8))
        try Self.write(sandbox.home.appending(path: "project/Sources/asset.bin"), data)
        try Self.write(sandbox.home.appending(path: "project/.build/asset.bin"), data)

        let answer = try #require(Self.find(sandbox))
        #expect(answer.groups.isEmpty)
        #expect(answer.insideProjects == 1)
        #expect(answer.row.details.contains { $0.value.contains("project folders") })
    }

    /// A folder name that only ever appears inside a project is enough on its own — no marker file
    /// needed, and no directory listing either.
    @Test func aBuildFolderIsRecognisedByNameAlone() {
        var memo = Duplicates.ProjectMemo(home: URL(filePath: "/Users/somebody"))
        // `isInsideAProject` is `mutating` — it remembers what it has already decided — and
        // `#expect` captures its operand immutably, so the answers are taken first.
        let insideNodeModules = memo.isInsideAProject("/Users/somebody/code/app/node_modules/x/y.js")
        let insideAProjectFile = memo.isInsideAProject("/Users/somebody/code/App.xcodeproj/xcuserdata/thing")
        let aFilmIsNotAProject = memo.isInsideAProject("/Users/somebody/Movies/holiday.mov")
        #expect(insideNodeModules)
        #expect(insideAProjectFile)
        #expect(aFilmIsNotAProject == false)
    }

    // MARK: - ⭐ We never choose

    /// **There is no honest way to pick the original**, so there is nothing on `Group` that could
    /// carry a choice and nothing on the row that could arrive ticked.
    @Test func nothingNominatesAnOriginal() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let data = Self.bytes(1_500_000, seed: 29)
        try Self.write(sandbox.home.appending(path: "a/file.bin"), data)
        try Self.write(sandbox.home.appending(path: "b/file.bin"), data)

        let answer = try #require(Self.find(sandbox))
        let group = try #require(answer.groups.first)

        #expect(answer.row.preSelected.isEmpty)
        #expect(answer.row.topic.mayArrivePreSelected == false)
        #expect(answer.row.ceremony == .oneAtATime)
        for copy in group.copies {
            #expect(copy.origin == .yours)
            #expect(copy.mayBePreSelected == false)
        }
        #expect(Duplicates.Group.weNeverChoose
            == ScanPolicy.Shape.aDuplicateWeWouldHaveToChooseBetween.why)
    }

    /// The row is a count of decisions before it is a number of bytes, and it never claims space.
    @Test func theRowIsSoldAsTidinessAndNeverAsSpace() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let data = Self.bytes(1_500_000, seed: 31)
        try Self.write(sandbox.home.appending(path: "a/file.bin"), data)
        try Self.write(sandbox.home.appending(path: "b/file.bin"), data)

        let answer = try #require(Self.find(sandbox))
        let reason = try #require(answer.row.reason).lowercased()

        #expect(answer.row.severity == .information)
        #expect(answer.row.topic == .duplicates)
        #expect(reason.contains("tidiness, not space"))
        #expect(answer.row.headline.contains("decision"))
    }

    // MARK: - The pieces

    /// The cheap hash separates different content and agrees with itself.
    @Test func theCheapHashIsAFilterAndNotAVerdict() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let one = try Self.write(sandbox.home.appending(path: "one.bin"),
                                 Self.bytes(200_000, seed: 37))
        let two = try Self.write(sandbox.home.appending(path: "two.bin"),
                                 Self.bytes(200_000, seed: 41))

        ScanPolicy.prepareThisThread()
        let first = try #require(Duplicates.cheapHash(of: one.path(percentEncoded: false),
                                                     length: 200_000))
        let again = try #require(Duplicates.cheapHash(of: one.path(percentEncoded: false),
                                                     length: 200_000))
        let other = try #require(Duplicates.cheapHash(of: two.path(percentEncoded: false),
                                                     length: 200_000))
        #expect(first == again)
        #expect(first != other)
    }

    /// The full compare, on its own, both ways round.
    @Test func theFullCompareIsByteForByte() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let data = Self.bytes(1_100_000, seed: 43)
        var changed = data
        changed[1_050_000] = data[1_050_000] &+ 1

        let a = try Self.write(sandbox.home.appending(path: "a.bin"), data)
        let b = try Self.write(sandbox.home.appending(path: "b.bin"), data)
        let c = try Self.write(sandbox.home.appending(path: "c.bin"), changed)

        var read: Int64 = 0
        #expect(Duplicates.identical(a.path(percentEncoded: false), b.path(percentEncoded: false),
                                     length: 1_100_000, bytesRead: &read))
        #expect(Duplicates.identical(a.path(percentEncoded: false), c.path(percentEncoded: false),
                                     length: 1_100_000, bytesRead: &read) == false)
        #expect(read > 0, "nothing was actually read")
    }

    /// ⭐ The search sets the thread I/O policy itself, so a comparison can never pull a file down
    /// from iCloud. 524 came down during the research; that is what this line prevents.
    @Test func theSearchSetsTheIOPolicyItself() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.write(sandbox.home.appending(path: "a.bin"), Self.bytes(2_000, seed: 47))

        _ = Self.find(sandbox)
        #expect(ScanPolicy.thisThreadHoldsCloudFilesWhereTheyAre)
    }

    /// A cancelled run returns nothing at all.
    @Test func aCancelledRunReturnsNothing() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try Self.write(sandbox.home.appending(path: "a.bin"), Self.bytes(2_000, seed: 53))

        #expect(Duplicates.find(roots: [sandbox.home], home: sandbox.home, snapshots: SnapshotStanding.none,
                                smallest: SizeOnDisk(1), isCancelled: { true }) == nil)
    }

    /// ⚠️ A group whose blocks could not be read is listed and **not counted**. A number nobody
    /// verified does not go into a headline.
    @Test func whatCouldNotBeVerifiedIsNotCounted() {
        #expect(BlockSharing.separateCopies.mayBeCounted)
        #expect(BlockSharing.couldNotTell.mayBeCounted == false)
        #expect(BlockSharing.sameBlocks.mayBeCounted == false)
        #expect(BlockSharing.couldNotTell.sentence?.isEmpty == false)
        #expect(BlockSharing.separateCopies.sentence == nil)
    }

    /// The under-promise: whichever copy is kept, at least this much is duplicated.
    @Test func theExtraFigureIsTheSmallestTrueAnswer() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let data = Self.bytes(1_500_000, seed: 59)
        try Self.write(sandbox.home.appending(path: "a/file.bin"), data)
        try Self.write(sandbox.home.appending(path: "b/file.bin"), data)
        try Self.write(sandbox.home.appending(path: "c/file.bin"), data)

        let answer = try #require(Self.find(sandbox))
        let group = try #require(answer.groups.first)
        #expect(group.copies.count == 3)
        #expect(group.judgementCalls == 2)
        // Two copies' worth, never three.
        #expect(group.extra.onDisk.bytes < group.copies.reduce(Int64(0)) { $0 + $1.bytes.onDisk.bytes })
    }
}
