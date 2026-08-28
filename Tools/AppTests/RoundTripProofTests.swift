// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  RoundTripProofTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The promise, proved: set a file aside, put it back, and nothing about it has changed.**
//
//  This is the test that decides whether quarantine is a real feature or a nicely-worded way of
//  damaging people's files. Everything else in the engine is in service of it.
//
//  ## Why a table of awkward files, and not one plain text file
//
//  A plain file survives almost anything, including a copy. That is exactly what makes it useless
//  as proof. **Every hazard the research measured shows up only on an awkward file:**
//
//  | The file | What a copy would lose |
//  |---|---|
//  | sparse | 200 MB of nothing becomes 200 MB of zeroes — measured at 6,000× |
//  | resource fork | the second stream, silently |
//  | Finder tags | the colour and the label the person set |
//  | an ACL | `clonefile` drops it |
//  | BSD flags | hidden, locked, no-dump — all of it |
//  | compressed | decompressed on the way through, and much larger afterwards |
//  | hard-linked | the two names become two files |
//  | a package | nothing, but it is the shape most junk actually has |
//  | a symbolic link | copied as its target, which is the catastrophe on the list |
//  | a folded name | recreated under a spelling the person never chose |
//  | a 255-byte name | truncated |
//  | an emoji name | mangled, on a bad day |
//
//  Each case is quarantined and restored, and the **whole** `FileFacts` reading is compared before
//  and after. Not a chosen list of fields — the whole struct, so a field added to `FileFacts`
//  tomorrow is covered from that moment without anybody remembering to add an assertion.
//
//  ## What is deliberately NOT claimed here
//
//  These files are made in a temporary directory on this Mac's own APFS Data volume, which is the
//  only volume quarantine is supported on. **Nothing here proves anything about a cross-volume
//  move, because the engine refuses to make one** — that refusal is proved in `RefusalProofTests`,
//  and it is the reason none of the copy hazards above can arise in shipping code.

// MARK: - The table

/// One awkward file, and what makes it awkward.
enum AwkwardFile: String, CaseIterable, Sendable {

    /// The control. If this one ever fails, nothing else in the table means anything.
    case ordinary

    /// 200 MB of logical size behind 16 KiB of blocks. A copy inflates it thousands of times over.
    case sparse

    /// A real second stream at `…/..namedfork/rsrc`, not an extended attribute pretending to be one.
    case resourceFork

    /// The colour and the label a person set in Finder, which live in one binary-plist attribute.
    case finderTags

    /// Several attributes at once, including an empty one and one with bytes that are not text.
    case manyExtendedAttributes

    /// `UF_HIDDEN | UF_NODUMP`. Deliberately not `UF_IMMUTABLE`, which is a refusal and is proved
    /// as one elsewhere — this case is about flags a movable file is allowed to carry.
    case bsdFlags

    /// An access control entry added with `chmod +a`. This is the one `clonefile` drops.
    case accessControlList

    /// A file macOS itself has compressed, made with `ditto --hfsCompression`. Compression is a BSD
    /// flag plus `com.apple.decmpfs` plus the resource fork, and all three are read back here.
    case compressed

    /// A `.app`-shaped folder. Most of what this app will ever set aside has this shape.
    case package

    /// The link itself, moved as a link. Copying one as its target is on the catastrophe list.
    case symbolicLink

    /// Two names, one inode. A copy splits them and the person ends up with two files that used to
    /// be one.
    case hardLinked

    /// `Café.txt` in NFC. The filesystem folds normalisation, so this file answers to a spelling it
    /// does not have — and a restore under the wrong spelling is a file the person cannot find.
    case foldedName

    /// 255 bytes, which is the limit.
    case nameAtTheLimit

    /// Because people name files this way and software keeps being surprised by it.
    case emojiName

    /// Read-only to its owner and nobody else. The permissions have to come back exactly.
    case unusualPermissions

    /// Build it, and hand back the thing to set aside.
    func build(in ground: ProvingGround) throws -> URL {
        switch self {
        case .ordinary:
            return try ground.file("Downloads/Old Installer.dmg", "installer bytes")

        case .sparse:
            return try ground.sparseFile("Downloads/disk image.sparsebundle-data",
                                         logicalBytes: 200 * 1024 * 1024)

        case .resourceFork:
            let url = try ground.file("Documents/With A Fork.txt", "the data fork")
            try ground.setResourceFork(Data(String(repeating: "RESOURCE", count: 64).utf8), on: url)
            return url

        case .finderTags:
            let url = try ground.file("Documents/Tagged.txt", "tagged")
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["Red\n6", "Work"], format: .binary, options: 0)
            try ground.setExtendedAttribute("com.apple.metadata:_kMDItemUserTags",
                                            to: plist, on: url)
            return url

        case .manyExtendedAttributes:
            let url = try ground.file("Documents/Attributed.txt", "attributed")
            try ground.setExtendedAttribute("com.apple.quarantine",
                                            to: Data("0081;68000000;Safari;".utf8), on: url)
            try ground.setExtendedAttribute("studio.stonemesa.empty", to: Data(), on: url)
            try ground.setExtendedAttribute("studio.stonemesa.binary",
                                            to: Data([0x00, 0xFF, 0x10, 0x00, 0x7F]), on: url)
            try ground.setExtendedAttribute("studio.stonemesa.large",
                                            to: Data(repeating: 0xAB, count: 4096), on: url)
            return url

        case .bsdFlags:
            let url = try ground.file("Documents/Hidden.txt", "hidden and not dumped")
            try ground.setFlags(UInt32(UF_HIDDEN) | UInt32(UF_NODUMP), on: url)
            return url

        case .accessControlList:
            let url = try ground.file("Documents/Shared.txt", "shared")
            try ground.addAccessControlEntry("user:\(NSUserName()) allow read,write", on: url)
            return url

        case .compressed:
            let plain = try ground.file("Documents/plain.txt",
                                        String(repeating: "compress me ", count: 5_000))
            return try ground.compressedCopy(of: plain, at: "Documents/Compressed.txt")

        case .package:
            try ground.folder("Applications/Old Thing.app/Contents/MacOS")
            try ground.file("Applications/Old Thing.app/Contents/Info.plist", "<plist/>")
            try ground.file("Applications/Old Thing.app/Contents/MacOS/Old Thing", "#!/bin/sh\n")
            try ground.file("Applications/Old Thing.app/Contents/Resources/icon.icns", "icns")
            return try ground.inside("Applications/Old Thing.app")

        case .symbolicLink:
            let target = try ground.file("Documents/the real one.txt", "the real bytes")
            return try ground.link("Documents/a shortcut",
                                   to: target.path(percentEncoded: false))

        case .hardLinked:
            let first = try ground.file("Documents/Original.txt", "one inode, two names")
            try ground.hardLink("Documents/The Other Name.txt", to: first)
            return first

        case .foldedName:
            // Explicit scalars rather than a typed character: which normalisation a source file is
            // saved in is not something a test should be at the mercy of.
            return try ground.file("Documents/Caf\u{e9}.txt", "an accented name in NFC")

        case .nameAtTheLimit:
            return try ground.file("Documents/\(String(repeating: "n", count: 255))", "at the limit")

        case .emojiName:
            return try ground.file("Documents/\u{1F9FE} Re\u{301}sume\u{301} \u{1F5C2}.txt", "emoji")

        case .unusualPermissions:
            let url = try ground.file("Documents/Read Only.txt", "0400")
            try ground.setMode(0o400, on: url)
            return url
        }
    }
}

// MARK: - ⭐ The round trip

@Suite("Quarantine and restore lose nothing")
struct RoundTripProofTests {

    /// ⭐ **The whole promise, once per awkward file.**
    ///
    /// Take every fact about the file. Set it aside. Put it back. Take every fact again. They have
    /// to be the same value — not similar, not equal on the fields somebody listed. The same value.
    @Test(arguments: AwkwardFile.allCases)
    func nothingAboutItChanges(_ awkward: AwkwardFile) throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let url = try awkward.build(in: ground)
        let before = try #require(FileFacts.take(of: url),
                                  "the fixture for \(awkward.rawValue) was not made")

        let report = Quarantine.quarantine([.init(url, section: .storage, reason: "proof")],
                                           home: ground.home)
        let record = try #require(report.moved.first,
                                  "\(awkward.rawValue) was refused: \(report.sentence)")
        #expect(report.trouble == nil)
        #expect(!ground.exists(url), "\(awkward.rawValue) is still where it was")

        let inStore = try #require(FileFacts.take(of: record.quarantinedURL),
                                   "\(awkward.rawValue) is not in the store")
        let lostInTheStore = inStore.differences(from: before).joined(separator: ", ")
        #expect(lostInTheStore.isEmpty,
                "while set aside, \(awkward.rawValue) lost: \(lostInTheStore)")

        let back = Quarantine.restore([record], home: ground.home)
        #expect(back.stuck.isEmpty, "\(awkward.rawValue) would not go back: \(back.sentence)")

        let after = try #require(FileFacts.take(of: url),
                                 "\(awkward.rawValue) did not come back")
        let lost = after.differences(from: before).joined(separator: ", ")
        #expect(lost.isEmpty, "the round trip changed \(awkward.rawValue): \(lost)")
        #expect(after == before)
    }

    /// The one reading that separates a move from a copy, stated on its own so a failure says so.
    ///
    /// Same inode, before, during and after. Nothing else in this file would catch a "helpful"
    /// `copyItem` fallback that got every other field right by hand.
    @Test(arguments: AwkwardFile.allCases)
    func itIsTheSameFileThroughout(_ awkward: AwkwardFile) throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let url = try awkward.build(in: ground)
        let inode = try #require(ground.inode(of: url))

        let record = try #require(Quarantine.quarantine(
            [.init(url, section: .storage, reason: "proof")], home: ground.home).moved.first)
        #expect(ground.inode(of: record.quarantinedURL) == inode,
                "\(awkward.rawValue) changed inode on the way in — that was a copy")

        Quarantine.restore([record], home: ground.home)
        #expect(ground.inode(of: url) == inode,
                "\(awkward.rawValue) changed inode on the way back — that was a copy")
    }

    // MARK: The cases worth saying out loud

    /// 200 MB of logical size, 16 KiB of blocks, and the blocks do not move.
    ///
    /// This is the fixture that would fail loudest under a copy: `copyfile` writes the holes out as
    /// real zeroes and a 16 KiB file becomes a 200 MB one.
    @Test func aSparseFileDoesNotInflate() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let url = try ground.sparseFile("Downloads/sparse.bin", logicalBytes: 200 * 1024 * 1024)
        let before = try #require(FileFacts.take(of: url))
        #expect(before.size == 200 * 1024 * 1024)
        #expect(before.allocatedBlocks * 512 < 1_048_576, """
            the fixture is not sparse, so this test proves nothing — it has \
            \(before.allocatedBlocks * 512) bytes behind \(before.size)
            """)

        let record = try #require(Quarantine.quarantine(
            [.init(url, section: .storage, reason: "proof")], home: ground.home).moved.first)
        let after = try #require(FileFacts.take(of: record.quarantinedURL))

        #expect(after.allocatedBlocks == before.allocatedBlocks)
        #expect(after.size == before.size)
    }

    /// macOS's own compression is a BSD flag, an extended attribute and a resource fork at once.
    /// All three come back, and the file still reads as its uncompressed self.
    @Test func aCompressedFileIsStillCompressedAndStillReadable() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let plain = try ground.file("Documents/plain.txt",
                                    String(repeating: "compress me ", count: 5_000))
        let url = try ground.compressedCopy(of: plain, at: "Documents/Compressed.txt")

        let before = try #require(FileFacts.take(of: url))
        // UF_COMPRESSED is 0x20. If `ditto` ever stops producing one on this filesystem, this
        // expectation fails and says so, rather than the test quietly proving nothing.
        #expect(before.flags & 0x20 != 0, """
            ditto --hfsCompression did not produce a compressed file on this volume, so there is \
            nothing here to preserve and this test is not proving what it claims
            """)
        #expect(before.extendedAttributes["com.apple.decmpfs"] != nil)

        let record = try #require(Quarantine.quarantine(
            [.init(url, section: .storage, reason: "proof")], home: ground.home).moved.first)
        let after = try #require(FileFacts.take(of: record.quarantinedURL))

        #expect(after.flags == before.flags)
        #expect(after.extendedAttributes["com.apple.decmpfs"]
                    == before.extendedAttributes["com.apple.decmpfs"])
        #expect(after.resourceFork == before.resourceFork)
        #expect((try? Data(contentsOf: record.quarantinedURL))?.count == 60_000,
                "the file no longer reads back as its uncompressed self")
    }

    /// Two names for one inode stay two names for one inode. A copy makes them two files, and the
    /// person who edits one is baffled that the other did not change.
    @Test func hardLinksAreNotSplit() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let first = try ground.file("Documents/Original.txt", "one inode, two names")
        let second = try ground.hardLink("Documents/The Other Name.txt", to: first)
        let inode = try #require(ground.inode(of: first))

        let record = try #require(Quarantine.quarantine(
            [.init(first, section: .storage, reason: "proof")], home: ground.home).moved.first)

        #expect(ground.inode(of: second) == inode, "the other name now points somewhere else")
        #expect(ground.inode(of: record.quarantinedURL) == inode)
        #expect(ground.contents(of: second) == "one inode, two names")
        var status = stat()
        lstat(second.path(percentEncoded: false), &status)
        #expect(status.st_nlink == 2, "the link count moved, so the file was copied")
    }

    /// ⚠️ **A symbolic link is set aside as a link.** Following it would set aside whatever it
    /// points at — which is Adobe's accident, in miniature, with our name on it.
    @Test func aSymbolicLinkMovesAsItselfAndItsTargetIsUntouched() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let target = try ground.file("Documents/the real one.txt", "the real bytes")
        let targetFacts = try #require(FileFacts.take(of: target))
        let link = try ground.link("Documents/a shortcut", to: target.path(percentEncoded: false))

        let record = try #require(Quarantine.quarantine(
            [.init(link, section: .storage, reason: "proof")], home: ground.home).moved.first)

        #expect(record.isSymbolicLink)
        #expect(ground.exists(target), "the target went with the link")
        #expect(FileFacts.take(of: target)?.differences(from: targetFacts).isEmpty == true,
                "the target was changed by moving a link to it")

        var status = stat()
        #expect(lstat(record.quarantinedURL.path(percentEncoded: false), &status) == 0)
        #expect((status.st_mode & S_IFMT) == S_IFLNK, "what is in the store is not a link any more")
    }

    /// ⭐ **The name comes back as its own bytes, not as a spelling that merely opens the same
    /// file.**
    ///
    /// Two things fold here at once and they pull in opposite directions. APFS keeps whichever
    /// bytes it was handed, so a file downloaded or unzipped keeps its NFC name. Foundation
    /// decomposes, so `URL.path` describes that file in NFD. The filesystem folds normalisation, so
    /// the NFD string opens the NFC file and nothing errors anywhere.
    ///
    /// The engine has to come out of that with the file's **own** spelling, or the restore leaves
    /// somebody with a document whose name is subtly not the one they gave it — openable by name,
    /// invisible to a search for it.
    ///
    /// ⚠️ This case is why the fixture writes the name with `open(2)`. Built the ordinary way, every
    /// fixture in this file is NFD, the asked-for path matches it exactly, and the whole problem is
    /// invisible.
    @Test func aNameThatIsNFCOnDiskSurvivesBeingAskedForInNFD() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let composed = Array("Caf\u{e9}.txt".utf8)
        let decomposed = Array("Cafe\u{301}.txt".utf8)
        #expect(composed != decomposed, "the two spellings must differ as bytes")

        let path = try ground.fileNamed(exactly: composed, inFolder: "Documents",
                                        contents: "an accented name in NFC")
        #expect(Array(path.utf8).suffix(composed.count) == composed,
                "the fixture did not put NFC on the disk after all")

        // What any section would actually hand the engine: a URL. Foundation decomposes it.
        let asked = URL(filePath: path)
        #expect(Array(asked.path(percentEncoded: false).utf8).suffix(decomposed.count) == decomposed,
                "Foundation no longer decomposes — this test's premise has changed")

        let report = Quarantine.quarantine([.init(asked, section: .storage, reason: "proof")],
                                           home: ground.home)
        let record = try #require(report.moved.first,
                                  "an ordinary NFC-named file was refused: \(report.sentence)")

        // ⭐ The record keeps the file's own spelling, not the caller's.
        #expect(Array(record.originalPath.utf8).suffix(composed.count) == composed,
                "the record kept a spelling the file does not have")

        let back = Quarantine.restore([record], home: ground.home)
        #expect(back.stuck.isEmpty, "\(back.sentence)")

        let names = try FileManager.default
            .contentsOfDirectory(atPath: ground.inside("Documents").path(percentEncoded: false))
        #expect(names.contains { Array($0.utf8) == composed },
                "the file came back under a different spelling: \(names.map { Array($0.utf8) })")
    }

    /// A package is a folder, and a folder moves whole and instantly. Everything inside it is
    /// exactly what it was, including the empty directories.
    @Test func aPackageGoesAndComesBackWhole() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let app = try AwkwardFile.package.build(in: ground)
        let before = try #require(FileFacts.take(of: app))

        let record = try #require(Quarantine.quarantine(
            [.init(app, section: .apps, reason: "proof")], home: ground.home).moved.first)
        #expect(record.isDirectory)
        #expect(ground.contents(of: record.quarantinedURL
                                    .appending(path: "Contents/Info.plist")) == "<plist/>")

        Quarantine.restore([record], home: ground.home)
        #expect(FileFacts.take(of: app)?.differences(from: before).isEmpty == true)
    }
}

// MARK: - The fixture has to be safe before it can prove anything

@Suite("The proving ground cannot be pointed outside itself")
struct ProvingGroundSafetyTests {

    @Test func anAbsolutePathIsRefused() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        #expect(throws: SandboxEscape.self) { try ground.inside("/Users/somebody/Documents") }
    }

    @Test func climbingOutWithDotDotIsRefused() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        #expect(throws: SandboxEscape.self) { try ground.inside("Documents/../../escape.txt") }
    }

    /// ⚠️ The one that matters. A test that makes a symbolic link and then writes "inside" it would
    /// be writing wherever the link points — which on a real Mac is how a fixture destroys the
    /// machine it is running on. The check is made on the resolved parent, not on the string.
    @Test func writingThroughASymbolicLinkOutOfTheSandboxIsRefused() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let elsewhere = try ProvingGround()
        defer { elsewhere.tearDown() }

        try ground.link("a way out", to: elsewhere.rootPath)
        #expect(throws: SandboxEscape.self) { try ground.inside("a way out/written.txt") }
        #expect(throws: SandboxEscape.self) {
            try ground.file("a way out/written.txt", "this must never be written")
        }
        #expect(!elsewhere.exists(URL(filePath: elsewhere.rootPath).appending(path: "written.txt")))
    }

    @Test func anOrdinaryRelativePathIsAllowedAndLandsInside() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }
        let url = try ground.file("Documents/fine.txt", "fine")
        #expect(Movable.isInside(url.path(percentEncoded: false), any: [ground.rootPath]))
    }

    /// It takes itself away again, including anything a failing test left flagged.
    @Test func itCleansUpAfterItself() throws {
        let ground = try ProvingGround()
        let url = try ground.file("Documents/locked.txt", "locked")
        try ground.setFlags(UInt32(UF_IMMUTABLE), on: url)
        ground.tearDown()
        #expect(!FileManager.default.fileExists(atPath: ground.rootPath))
    }
}
