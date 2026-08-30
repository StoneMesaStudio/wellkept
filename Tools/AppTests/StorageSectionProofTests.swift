// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import Testing
import WellkeptCore

//  StorageSectionProofTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **One pretend Mac, and every reader in the section run across it at once.**
//
//  Each reader in Storage has its own suite, and each of those proves its own file behaves. This
//  proves the thing none of them can: that the **join** behaves. The scanner walks and decides
//  nothing; the classifier decides and walks nothing; the big-file reader and the duplicate finder
//  each answer a different question about the same bytes. The mistake that loses somebody's files
//  does not live inside any one of those. It lives in the two lines that put them together.
//
//  So `PretendMac` below builds a home folder containing every near-miss that was measured on the
//  real machine on 2026-08-28 — the audiobook filed under a store number inside `Caches`, the
//  a working PHP install with no app and no receipt and no activity for months, an APFS clone pair, a
//  duplicate pair inside a project, a folder that will not open, a file that claims half a gigabyte
//  and occupies nothing — and every test here runs the real code over all of it in one pass.
//
//  ## Why several tests share one fixture rather than each building its own
//
//  Because the near-misses have to survive **each other**. A rule that saves the audiobook when the
//  audiobook is the only thing on the disk is not the rule we need; it has to survive being on a
//  disk that also contains a folder we genuinely do tick. Every test below therefore asserts a
//  positive control in the same run: **Xcode's build folder arrives ticked**. A suite where nothing
//  is ever offered would pass with the classifier deleted.
//
//  ## ⚠️ Nothing here goes near a real home folder
//
//  Everything is made inside a `ProvingGround`, which throws rather than hand out a path outside
//  itself, and is removed in a `defer`. Every reader is given `home:` and `roots:` pointing at that
//  sandbox, and both readers are passed `elsewhere: []` so they do not reach for the 30 GB of
//  simulator runtimes on the machine running the suite.

// MARK: - The pretend Mac

/// A home folder containing the measured near-misses, and the join that reads it.
struct PretendMac {

    let ground: ProvingGround
    var home: URL { ground.home }

    /// Four and a half months back, which is the age of the real orphan folder — old enough that
    /// every heuristic built on inactivity fires.
    static let longAgo = Date(timeIntervalSinceNow: -60 * 60 * 24 * 135)

    // Paths, named once so a test never spells one twice.
    static let audiobookFolder = "Library/Caches/com.apple.bookassetd"
    static let audiobookStore = "Library/Caches/com.apple.bookassetd/1442759222"
    static let audiobook = "Library/Caches/com.apple.bookassetd/1442759222/Track 1.m4b"
    static let orphanFolder = "Library/Application Support/Herd"
    static let derivedData = "Library/Developer/Xcode/DerivedData/Wellkept-abcdefg"
    static let browserCache = "Library/Caches/com.example.browser/entries"
    static let bigMovie = "Movies/Holiday in Sardinia.mov"
    static let cloneOriginal = "Pictures/Raw/first.raw"
    static let clonePair = "Pictures/Raw/second.raw"
    static let realCopyA = "Documents/Contracts/lease.pdf"
    static let realCopyB = "Documents/Archive/lease.pdf"
    static let projectCopyA = "Code/site/node_modules/left-pad/index.js"
    static let projectCopyB = "Code/site/vendor/index.js"
    static let lockedFolder = "Library/Mail"

    init() throws {
        ground = try ProvingGround()

        // ⭐ The audiobook. 1.3 GB on the real Mac; the shape is what the classifier reads, and the
        // shape is exact — a ten-digit store number under a genuine Apple bundle identifier, inside
        // the one folder every commercial cleaner sells as the prize.
        try ground.file(Self.audiobook, bytes: Self.noise(300_000, seed: 11))
        try ground.file("\(Self.audiobookStore)/cover.jpg", bytes: Self.noise(9_000, seed: 12))

        // ⚠️ The trap that is live on the real Mac: no app, no receipt, no Spotlight entry,
        // untouched for four and a half months — and it is a working PHP install.
        try ground.file("\(Self.orphanFolder)/bin/php", bytes: Self.noise(120_000, seed: 21))
        try ground.file("\(Self.orphanFolder)/config/php.ini", "memory_limit = 512M")
        try ground.file("\(Self.orphanFolder)/composer.phar", bytes: Self.noise(80_000, seed: 22))

        // ✅ The positive control: Xcode's build output, which really is the machine's and really
        // does arrive ticked. 13 GB on the real Mac and the largest honest win in the section.
        try ground.file("\(Self.derivedData)/info.plist", "<plist/>")
        try ground.folder("\(Self.derivedData)/Build")
        try ground.folder("\(Self.derivedData)/Index.noindex")
        try ground.file("\(Self.derivedData)/Build/Products/thing.o",
                        bytes: Self.noise(200_000, seed: 31))

        // A real content-addressed cache: every name is a checksum, so the name itself is the
        // regeneration story.
        for seed in 0..<40 {
            try ground.file("\(Self.browserCache)/\(Self.checksum(seed))",
                            bytes: Self.noise(2_000, seed: UInt64(seed) &+ 41))
        }

        // A person's own large file, which is revealed and never chosen for them.
        try ground.file(Self.bigMovie, bytes: Self.noise(400_000, seed: 51))

        // ⚠️ An APFS clone pair. Two names, one set of blocks: deleting one gives back nothing.
        let original = try ground.file(Self.cloneOriginal, bytes: Self.noise(250_000, seed: 61))
        try Self.clone(original, to: try ground.inside(Self.clonePair))

        // Two genuinely separate copies of one document — the duplicate finder's real answer.
        let lease = Self.noise(180_000, seed: 71)
        try ground.file(Self.realCopyA, bytes: lease)
        try ground.file(Self.realCopyB, bytes: lease)

        // The same thing inside a project, where deleting one breaks a build. 94% of the 12,021
        // groups on the real Mac look like this.
        let bundled = Self.noise(150_000, seed: 81)
        try ground.file(Self.projectCopyA, bytes: bundled)
        try ground.file(Self.projectCopyB, bytes: bundled)
        try ground.file("Code/site/package.json", "{}")

        // A file that claims half a gigabyte and occupies nothing — the sparse stand-in for the
        // 15,593 iCloud placeholders that look like 72 GB and are not on the Mac at all.
        try ground.sparseFile("Downloads/looks-enormous.iso", logicalBytes: 500_000_000)

        // A folder that will not open, standing in for the 54 the real Mac refuses without Full
        // Disk Access. Something big is inside it, so a reader that reports zero is caught.
        try ground.file("\(Self.lockedFolder)/messages.db", bytes: Self.noise(220_000, seed: 91))
        try ground.setMode(0o000, on: try ground.inside(Self.lockedFolder))

        // Backdated last, so the writes above do not undo it.
        try Self.age(ground.home.appending(path: Self.orphanFolder), to: Self.longAgo)
    }

    func tearDown() {
        try? ground.setMode(0o755, on: home.appending(path: Self.lockedFolder))
        ground.tearDown()
    }

    // MARK: Making the fixtures

    /// Random bytes, so two files of the same length are never accidentally identical.
    static func noise(_ count: Int, seed: UInt64) -> Data {
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

    static func checksum(_ seed: Int) -> String { String(format: "%064x", seed &* 2_654_435_761) }

    /// An APFS clone, the way the Finder makes one when it copies within a volume.
    static func clone(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let made = source.path(percentEncoded: false).withCString { from in
            destination.path(percentEncoded: false).withCString { to in clonefile(from, to, 0) }
        }
        try #require(made == 0, "this filesystem does not clone, so the check cannot be exercised")
    }

    /// Backdate a folder. `utimes` sets both timestamps, which is unavoidable — and harmless here,
    /// because nothing in this app reads the access time and a test that set only one would be
    /// asserting against a date the product does not use.
    static func age(_ url: URL, to date: Date) throws {
        let seconds = time_t(date.timeIntervalSince1970)
        var times = [timeval(tv_sec: seconds, tv_usec: 0), timeval(tv_sec: seconds, tv_usec: 0)]
        _ = url.path(percentEncoded: false).withCString { utimes($0, &times) }
    }

    // MARK: - ⭐ The join

    /// One classified thing: what the walk saw, and what the classifier concluded about it.
    struct Judged {
        let path: String
        let classified: JunkClassifier.Classified
        var item: Item { classified.item }
        var ticked: Bool { classified.arrivesTicked }
    }

    /// ⭐ **The two lines from the classifier's own header, run over a real walk.**
    ///
    /// This is the seam the Storage rows will be built on, and it is written here because nothing
    /// in the app has written it yet. Every folder and every file the scanner reports is offered to
    /// the classifier, and a folder that comes back `stopHere` takes everything beneath it with it
    /// — a junk folder is junk whole, and counting it at four depths offers it to a person four
    /// times.
    func classifyEverything(snapshots: SnapshotStanding = .none) -> [Judged] {
        let plan = Scanner.Plan(roots: [home], home: home, snapshots: snapshots,
                                folderDepth: 8, largestKept: 400)
        var files: [Scanner.Entry] = []
        let survey = Scanner.walk(plan, onEntry: { entry in
            if !entry.isFolder { files.append(entry) }
        })

        var judged: [Judged] = []
        var stopped: [String] = []

        // Folders shallowest first, so a `stopHere` folder is known before its children are looked
        // at.
        for folder in survey.folderTotals.sorted(by: { $0.depth < $1.depth }) {
            if stopped.contains(where: { folder.path.hasPrefix($0 + "/") }) { continue }
            guard let subject = JunkClassifier.Subject.onDisk(URL(filePath: folder.path))
            else { continue }
            let classified = JunkClassifier.classify(subject,
                                                     identity: folder.identity,
                                                     bytes: folder.bytes,
                                                     kind: folder.isPackage ? .bundle : .folder,
                                                     home: home)
            judged.append(Judged(path: folder.path, classified: classified))
            if classified.stopHere { stopped.append(folder.path) }
        }

        for entry in files {
            if stopped.contains(where: { entry.path.hasPrefix($0 + "/") }) { continue }
            guard let subject = JunkClassifier.Subject.onDisk(URL(filePath: entry.path))
            else { continue }
            let classified = JunkClassifier.classify(subject,
                                                     identity: entry.identity,
                                                     bytes: entry.bytes,
                                                     kind: entry.kind,
                                                     cloudStanding: entry.cloudStanding,
                                                     home: home)
            judged.append(Judged(path: entry.path, classified: classified))
        }
        return judged
    }

    /// Everything judged whose path is at or under a relative place in the sandbox.
    func everythingUnder(_ relative: String, in judged: [Judged]) -> [Judged] {
        let prefix = home.appending(path: relative).path(percentEncoded: false)
        return judged.filter { $0.path == prefix || $0.path.hasPrefix(prefix + "/") }
    }
}

// MARK: - ⭐ The near-misses, on one disk, in one run

@Suite("A whole pretend Mac, and nothing of the person's own is ever ticked", .serialized)
struct StorageSectionProofTests {

    /// ⭐ **The audiobook.** `~/Library/Caches/com.apple.bookassetd/1442759222/Track 1.m4b`, 1.3 GB,
    /// put there by Apple Books. Every layer of it — the identifier folder, the store folder, the
    /// track — has to come back as the person's, in a run where the same disk also holds a folder we
    /// genuinely do tick.
    ///
    /// ⚠️ Note what makes this hard: `com.apple.bookassetd` is a real Apple bundle identifier, so
    /// the obvious refinement — "only sweep folders filed under an installed app's identifier" —
    /// convicts it. And that folder is where every commercial cleaner starts.
    @Test func theAudiobookInTheCacheFolderIsNeverOffered() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let judged = mac.classifyEverything()
        let book = mac.everythingUnder(PretendMac.audiobookFolder, in: judged)

        #expect(book.count >= 2, "the audiobook fixture was not walked at all — this proves nothing")
        for layer in book {
            #expect(layer.item.origin == .yours, "\(layer.item.name) was called the machine's")
            #expect(layer.ticked == false, "\(layer.item.name) arrived with its box ticked")
            #expect(layer.item.mayBePreSelected == false)
            #expect(layer.classified.judgement.category == nil)
        }

        // And it is absent from what a batch press would take.
        let ticked = JunkClassifier.arrivingTicked(judged.map(\.classified))
        #expect(ticked.contains { $0.path.contains("bookassetd") } == false,
                "the batch would have swept somebody's audiobook")

        // ✅ The positive control, in the same run. Without this the test passes with the classifier
        // deleted.
        #expect(ticked.contains { $0.path.contains("DerivedData") },
                "nothing at all was offered — the run is vacuous")
    }

    /// ⚠️ **The orphan trap.** 90 MB in Application Support, no app that claims it, no receipt, no
    /// Spotlight entry, and untouched for four and a half months. Every heuristic built on an
    /// absence fires, and it is a working PHP install.
    ///
    /// This is safe because no rule in the classifier reasons from an absence — not because
    /// somebody wrote an exception for one vendor. The test names none either.
    @Test func nothingIsConcludedFromAnAbsenceOfEvidence() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let judged = mac.classifyEverything()
        let orphan = mac.everythingUnder(PretendMac.orphanFolder, in: judged)

        #expect(orphan.count >= 3, "the orphan-folder fixture was not walked")
        for thing in orphan {
            #expect(thing.item.origin == .yours, "\(thing.path) was called the machine's")
            #expect(thing.ticked == false)
        }

        // The folder really is old enough for every inactivity rule to fire — the fixture is doing
        // its job, and being old was still not a reason for anything.
        let folder = orphan.first { $0.path.hasSuffix("/Herd") }
        let modified = try #require(folder?.item.modifiedOn)
        #expect(Date().timeIntervalSince(modified) > 60 * 60 * 24 * 100,
                "the fixture is not actually old, so the heuristics were never tempted")
    }

    /// ⭐ **A clone pair is not a duplicate.** Two names, one set of blocks: deleting one gives back
    /// nothing, which is a claim a person disproves in sixty seconds.
    ///
    /// Asserted on a disk that also holds a **real** pair, so the finder is proved to be working
    /// while it declines the clone.
    @Test func aClonePairIsNeitherADuplicateNorInTheTotal() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let answer = try #require(Duplicates.find(roots: [mac.home], home: mac.home,
                                                  snapshots: .none, smallest: SizeOnDisk(1_000)))

        let cloned = answer.groups.filter { group in
            group.copies.contains { $0.path.contains("/Pictures/Raw/") }
        }
        #expect(cloned.isEmpty, "a clone pair was offered as a duplicate")
        #expect(answer.sharedBlocks >= 1, "the block check never fired — the pair was not compared")

        // ✅ The real pair is found, so the finder is not simply silent.
        let real = answer.groups.filter { group in
            group.copies.contains { $0.path.hasSuffix("/lease.pdf") }
        }
        #expect(real.count == 1, "two genuinely separate copies were not found")

        // The tidiness figure counts the real pair and nothing of the clone's.
        #expect(answer.tidiness.onDisk.bytes > 0)
        #expect(answer.tidiness.onDisk.bytes < 400_000,
                "the clone's blocks were counted into the tidiness figure")
    }

    /// ⚠️ **Nothing inside a project folder is offered, and nothing there is ever pre-selected.**
    /// 94% of the duplicate groups on the real Mac are inside one, and deleting one half breaks a
    /// build.
    @Test func nothingInsideAProjectIsOfferedOrPreSelected() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let answer = try #require(Duplicates.find(roots: [mac.home], home: mac.home,
                                                  snapshots: .none, smallest: SizeOnDisk(1_000)))
        let inProject = answer.groups.filter { group in
            group.copies.contains { $0.path.contains("/node_modules/") }
        }
        #expect(inProject.isEmpty, "a pair inside a project was put on the list")
        #expect(answer.insideProjects >= 1, "the project pair was never even seen")

        // And the same files, reached through the other reader, are still the person's.
        let judged = mac.classifyEverything()
        let code = mac.everythingUnder("Code", in: judged)
        #expect(code.isEmpty == false)
        for thing in code {
            #expect(thing.item.origin == .yours, "\(thing.path) was filed as the machine's")
            #expect(thing.ticked == false)
        }
    }

    /// ⭐ **We never choose which copy is the original**, and there is nowhere in the type for a
    /// choice to live. Four real pairs on the measured Mac each defeat a different rule — including
    /// a photo whose dates a past copy destroyed, so "keep the oldest" picks the wrong one.
    @Test func noGroupNominatesAnOriginal() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let answer = try #require(Duplicates.find(roots: [mac.home], home: mac.home,
                                                  snapshots: .none, smallest: SizeOnDisk(1_000)))
        let group = try #require(answer.groups.first)

        // Every copy carries the same standing: same origin, same ceremony, and none is ticked.
        #expect(Set(group.copies.map(\.origin)) == [Origin.yours])
        #expect(group.copies.allSatisfy { $0.mayBePreSelected == false })
        #expect(group.copies.count >= 2)
        #expect(group.headline.isEmpty == false)

        // And the sentence saying so is read from the one place it is written.
        #expect(Duplicates.Group.weNeverChoose
                == ScanPolicy.Shape.aDuplicateWeWouldHaveToChooseBetween.why)
    }

    /// ⭐ **A person's own file is never pre-ticked, whichever reader found it.** Asserted across
    /// both of them in one run rather than inside each — the failure this catches is a row assembled
    /// from two readers that individually behaved.
    @Test func noReaderHandsBackATickedFileOfThePersons() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let big = try #require(BigFiles.read(roots: [mac.home], home: mac.home, elsewhere: [],
                                             snapshots: .none, smallest: SizeOnDisk(1)))
        #expect(big.items.isEmpty == false, "the big-file reader found nothing — this proves nothing")
        #expect(big.items.allSatisfy { $0.origin == .yours })
        #expect(big.row.preSelected.isEmpty)

        let duplicates = try #require(Duplicates.find(roots: [mac.home], home: mac.home,
                                                      snapshots: .none, smallest: SizeOnDisk(1_000)))
        #expect(duplicates.row.preSelected.isEmpty)

        let judged = mac.classifyEverything()
        let mine = judged.filter { $0.item.origin == .yours }
        #expect(mine.isEmpty == false)
        #expect(mine.allSatisfy { $0.ticked == false && $0.item.mayBePreSelected == false })

        // Whatever did arrive ticked is the machine's, every one of it.
        let ticked = JunkClassifier.arrivingTicked(judged.map(\.classified))
        #expect(ticked.isEmpty == false, "the run is vacuous — nothing was offered at all")
        #expect(ticked.allSatisfy { $0.origin == .machineJunk })
    }

    /// ⭐ **A folder that will not open is named, never reported as empty and never as zero.**
    /// Without Full Disk Access, 54 folders in the measured home directory cannot be read — the
    /// Trash and the photo library among them, usually the two biggest wins on any Mac.
    @Test func aFolderWeCouldNotReadIsNamedAndNeverAZero() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let big = try #require(BigFiles.read(roots: [mac.home], home: mac.home, elsewhere: [],
                                             snapshots: .none, smallest: SizeOnDisk(1)))

        #expect(big.refused.isEmpty == false, "a folder that would not open was silently skipped")
        #expect(big.refused.stillComplete == false)
        #expect(big.row.complete == false)
        #expect(big.refused.remedy != nil, "the one refusal a person can lift carries no button")

        let sentence = try #require(big.refused.sentence)
        #expect(sentence.lowercased().contains("not allowed")
                || sentence.lowercased().contains("could not"),
                "the refusal does not say we were not allowed to look: \(sentence)")
        #expect(sentence.contains(" 0 ") == false, "a refusal was reported as a quantity")

        // What it could read is still reported. A refusal is not a reason to throw the rest away.
        #expect(big.total.onDisk.bytes > 0)
        #expect(big.items.contains { $0.path.contains("messages.db") } == false,
                "something inside the folder we were refused was listed anyway")
    }

    /// ⚠️ **A file that claims half a gigabyte and occupies nothing does not go to the top**, and it
    /// is never opened to find out. The sparse file is the stand-in for the 15,593 iCloud
    /// placeholders on the measured Mac that look like 72 GB.
    @Test func somethingThatIsNotReallyThereDoesNotOutrankSomethingThatIs() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let big = try #require(BigFiles.read(roots: [mac.home], home: mac.home, elsewhere: [],
                                             snapshots: .none, smallest: SizeOnDisk(1)))
        let first = try #require(big.items.first)
        #expect(first.path.contains("looks-enormous") == false,
                "a file that claims 500 MB and occupies nothing was put at the top")
        #expect(first.bytes.onDisk.bytes > 100_000)

        // The duplicate finder never reads anything like that much, because it never opens it.
        let duplicates = try #require(Duplicates.find(roots: [mac.home], home: mac.home,
                                                      snapshots: .none, smallest: SizeOnDisk(1_000)))
        #expect(duplicates.bytesRead < 10_000_000,
                "the comparison read \(duplicates.bytesRead) bytes — something enormous was opened")
        #expect(duplicates.stoppedEarly == false)
    }
}

// MARK: - ⭐ The snapshot, across every reader at once

/// **One stuck snapshot means deleting anything older than it gives back nothing**, and every
/// reader in this section has to say so in the same breath.
///
/// Measured on the real Mac: one local snapshot dated 25 August, and how much a delete returns
/// depends entirely on the file's age — written today 98%, yesterday 74%, May 12%, a July folder
/// 3.6%. The model is binary per file, which is why those four numbers fall out with no curve
/// anywhere.
@Suite("What comes back today is the same answer in every reader", .serialized)
struct SnapshotAgreementTests {

    /// A snapshot taken after everything in the fixture was written, so nothing comes back.
    private var stuck: SnapshotStanding {
        SnapshotStanding(snapshots: [
            LocalSnapshot(name: "com.apple.TimeMachine.2026-08-25-062503.local",
                          takenOn: Date().addingTimeInterval(60))])
    }

    /// ⭐ Every reader, one disk, one snapshot: **nothing comes back today, and each of them says
    /// so in words rather than printing the file's size where the answer belongs.**
    @Test func aSnapshotNewerThanEverythingTakesEveryPromiseToZero() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let big = try #require(BigFiles.read(roots: [mac.home], home: mac.home, elsewhere: [],
                                             snapshots: stuck, smallest: SizeOnDisk(1)))
        #expect(big.items.isEmpty == false)
        for item in big.items {
            #expect(item.bytes.onDisk.bytes > 0, "\(item.name) has no size at all")
            #expect(item.bytes.recoverableToday.isZero,
                    "\(item.name) promises \(item.bytes.recoverableToday.text) a snapshot is holding")
            #expect(item.bytes.agree == false)
            #expect(item.bytes.text.contains("nothing comes back today"),
                    "the row prints one number where two are true: \(item.bytes.text)")
        }

        let judged = mac.classifyEverything(snapshots: stuck)
        let sized = judged.filter { $0.item.bytes.onDisk.bytes > 0 }
        #expect(sized.isEmpty == false)
        for thing in sized {
            #expect(thing.item.bytes.recoverableToday.isZero,
                    "\(thing.path) promises space a snapshot is holding")
        }
    }

    /// The counterpart: with no snapshot at all, the two numbers agree and the row shows one
    /// figure. If this ever fails alongside the test above, the arithmetic is not being done.
    @Test func withNoSnapshotTheTwoNumbersAgreeAndOneFigureIsShown() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let big = try #require(BigFiles.read(roots: [mac.home], home: mac.home, elsewhere: [],
                                             snapshots: .none, smallest: SizeOnDisk(1)))
        let item = try #require(big.items.first)
        #expect(item.bytes.agree)
        #expect(item.bytes.text == item.bytes.onDisk.text)
    }

    /// ⚠️ **A snapshot list we could not read is a different answer from no snapshots at all.**
    /// Collapsing them would make a Mac we could not read look like the most generous case there
    /// is, and every figure on the screen would be a promise nobody checked.
    @Test func aListWeCouldNotReadPromisesNothing() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }

        let big = try #require(BigFiles.read(roots: [mac.home], home: mac.home, elsewhere: [],
                                             snapshots: .couldNotBeRead, smallest: SizeOnDisk(1)))
        #expect(big.items.isEmpty == false)
        #expect(big.items.allSatisfy { $0.bytes.recoverableToday.isZero },
                "an unread snapshot list was treated as no snapshots")
        #expect(SnapshotStanding.couldNotBeRead != SnapshotStanding.none)
    }

    /// Answer 4, 2026-08-28: **Storage says the Time Machine problem out loud** — one flat
    /// line on the face, no button. It appears only where the snapshot is genuinely stuck, so a Mac
    /// whose backups are working says nothing about them here.
    @Test func theStuckSnapshotGetsOneFlatLineAndNoButton() throws {
        let old = SnapshotStanding(snapshots: [
            LocalSnapshot(name: "com.apple.TimeMachine.2026-08-25-062503.local",
                          takenOn: Date().addingTimeInterval(-60 * 60 * 24 * 20))])
        #expect(old.isStuck())
        let line = try #require(old.line())
        #expect(line.isEmpty == false)

        let fresh = SnapshotStanding(snapshots: [
            LocalSnapshot(name: "com.apple.TimeMachine.2026-08-28-090000.local",
                          takenOn: Date().addingTimeInterval(-60 * 60 * 3))])
        #expect(fresh.isStuck() == false)
        #expect(fresh.line() == nil, "a working backup was reported as a problem")
    }
}

// MARK: - ⭐ The whole section's answer, assembled

/// **The report the face is drawn from, built out of the real readers over the pretend Mac.**
///
/// The failure this catches is the one that only appears at assembly: rows that each behaved, added
/// together into a screen that ticks something, hides a refusal, or quietly reports a gap it cannot
/// explain.
@Suite("The assembled report", .serialized)
struct StorageReportProofTests {

    private func report(_ mac: PretendMac, free: Int64 = 109_754_851_328) throws -> StorageReport {
        let judged = mac.classifyEverything()
        let ticked = JunkClassifier.arrivingTicked(judged.map(\.classified))
        let big = try #require(BigFiles.read(roots: [mac.home], home: mac.home, elsewhere: [],
                                             snapshots: .none, smallest: SizeOnDisk(1)))
        let duplicates = try #require(Duplicates.find(roots: [mac.home], home: mac.home,
                                                      snapshots: .none, smallest: SizeOnDisk(1_000)))

        let junkRow = StorageRow(topic: .machineJunk,
                                 headline: "Things the machine wrote and will write again",
                                 measure: .sum(ticked.map(\.bytes)),
                                 count: ticked.count,
                                 items: ticked)

        let picture = FreeSpacePicture(capacity: SizeOnDisk(494_384_795_648),
                                       actuallyFree: SizeOnDisk(free),
                                       finderShows: FinderFigure(177_859_575_022),
                                       snapshots: .none,
                                       volumeName: "Macintosh HD")

        return StorageReport(freeSpace: picture,
                             rows: [big.row, junkRow, duplicates.row],
                             measured: big.total.onDisk,
                             refused: big.refused,
                             cloudHolding: big.cloudHolding)
    }

    /// ⭐ Across the whole assembled report, everything pre-selected is the machine's.
    @Test func nothingThePersonOwnsSurvivesIntoThePreSelection() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }
        let report = try report(mac)

        let ticked = report.rows.flatMap(\.preSelected)
        #expect(ticked.isEmpty == false, "nothing at all was pre-selected — the report is vacuous")
        #expect(ticked.allSatisfy { $0.origin == .machineJunk })
        #expect(ticked.allSatisfy { $0.handling.mayOfferAButton })
        #expect(report.row(.yourOwnFiles)?.preSelected.isEmpty == true)
        #expect(report.row(.duplicates)?.preSelected.isEmpty == true)
    }

    /// ⚠️ **Revealing somebody's files is never a fault.** Every row is `.information`, and the only
    /// thing that can reach Overview is a disk with no room left.
    @Test func aLargeFolderIsNotAProblem() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }
        let report = try report(mac)

        #expect(report.rows.allSatisfy { $0.severity == .information })
        #expect(report.overviewFinding == nil, "a roomy disk raised something on Overview")
        #expect(report.status == .good)
    }

    /// The one thing that does reach Overview: no room left. 5% or 10 GB, whichever bites first —
    /// because 5% of a 4 TB disk and 5% of a 256 GB disk are different situations.
    @Test func aDiskWithNoRoomLeftIsTheOneThingRaised() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }
        let report = try report(mac, free: 2_000_000_000)

        let finding = try #require(report.overviewFinding)
        #expect(finding.severity == .problem)
        #expect(finding.section == .storage)
        #expect(report.status == .needsAttention)
    }

    /// ⭐ **The gap is named, never hidden.** There is no argument for it on the initialiser and no
    /// code path that produces a report without it, so this asserts the sentence reaches the face.
    @Test func theFaceAlwaysSaysWhatItCouldNotAccountFor() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }
        let report = try report(mac)

        #expect(report.gap.worthExplaining, "the pretend disk's gap is too small to exercise this")
        #expect(report.linesUnderTheHeadline.contains(report.gap.sentence))
        // ⚠️ Named causes, not a label. "The other 113 GB is …" is ordinary English; a slice called
        // "Other" is a number with the explanation taken off, which is what is banned.
        #expect(report.gap.sentence.contains("bookkeeping"))
        #expect(report.gap.detailPairs.contains { $0.label == "Other" } == false)

        // Finder's figure and the line explaining it are both under the headline, and the headline
        // itself is the real number.
        #expect(report.summary == report.freeSpace.headline)
        #expect(report.linesUnderTheHeadline.contains { $0.contains("Finder says") })
    }

    /// A run that could not see everything is never reported as complete, and the refusal survives
    /// assembly rather than being averaged away by two rows that were fine.
    @Test func oneRefusedFolderMakesTheWholeRunIncomplete() throws {
        let mac = try PretendMac()
        defer { mac.tearDown() }
        let report = try report(mac)

        #expect(report.complete == false)
        #expect(report.record.complete == false)
        #expect(report.linesUnderTheHeadline.contains { $0.lowercased().contains("not allowed") })
    }
}
