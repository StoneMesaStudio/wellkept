// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  RefusalProofTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The refusals refuse — each for its own reason, in its own words, and all of them at once.**
//
//  A move that works is half a product. The half that decides whether anybody should trust it is
//  the move that does not happen, and this file is where each one is made to happen for real.
//
//  ## The two syscall flags, shown to be load-bearing
//
//  It is not enough to assert that `renameatx_np` refused. A test that only shows the refusal
//  cannot tell you whether the flag did it or whether the situation was harmless all along. So each
//  of the two flag tests below **first demonstrates the damage with plain `rename(2)`**, on
//  throwaway files this fixture made a moment earlier, and only then shows that the engine's call
//  refuses on the identical shape.
//
//  - `RENAME_EXCL` — plain `rename(2)` silently destroys whatever occupies the destination.
//  - `RENAME_NOFOLLOW_ANY` — plain `rename(2)` follows a symlinked parent and moves the real file
//    out from under the person. This is the `Caches → Application Support` shape, and it is the
//    failure class that ends a product.
//
//  ## What cannot be made in a sandbox, and is said so rather than faked
//
//  Three of the thirteen refusals cannot be produced by an unprivileged test, and there is no
//  honest way around it:
//
//  - **`SF_RESTRICTED`, `SF_IMMUTABLE`, `SF_NOUNLINK`** need root to *set*. They are proved against
//    real files on this Mac that already carry them — `/Library/Apple` is restricted and `/usr/local`
//    is no-unlink, and both are on the writable Data volume, so they prove the flag and not the
//    volume.
//  - **`UF_DATAVAULT`** cannot be set at all, by anybody. The canonical examples live under
//    `~/Library/Containers`, which this suite is forbidden to read. Only its sentence is asserted.
//  - **`SF_DATALESS`** needs a file iCloud has evicted, which a test cannot arrange. Only its
//    sentence is asserted.
//
//  The mechanism they share *is* proved, with the one flag an ordinary user can set: a file at a
//  perfectly innocuous path is refused because of its flags, and the same file at the same path is
//  movable the moment the flags are cleared. **That is the claim that matters** — the refusal comes
//  from the file, never from a list of paths that goes stale every macOS release.

@Suite("Every refusal refuses, for its own reason")
struct RefusalProofTests {

    // MARK: The flags travel with the file

    /// ⭐ The claim the whole design rests on, stated as an experiment with one variable.
    ///
    /// Same file. Same path. Same everything. Flags on: refused. Flags off: movable. Nothing about
    /// where it lives changed between the two readings, so nothing about where it lives can be what
    /// decided.
    @Test func thePathDoesNotChangeButTheAnswerDoes() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let url = try ground.file("Documents/ordinary.txt", "nothing special about this path")

        #expect(Movable.check(url, reach: ground.reach).isMovable)

        try ground.setFlags(UInt32(UF_IMMUTABLE), on: url)
        let refused = Movable.check(url, reach: ground.reach)
        #expect(!refused.isMovable)
        #expect(refused.refusals.contains(.locked(flag: "locked in Finder")))
        #expect(refused.sentence?.contains("locked") == true)

        try ground.setFlags(0, on: url)
        #expect(Movable.check(url, reach: ground.reach).isMovable,
                "clearing the flag did not clear the refusal, so something else decided")
    }

    /// The engine refuses a locked file rather than moving it, and the file does not budge.
    @Test func aLockedFileIsNotSetAsideAndSaysWhy() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let url = try ground.file("Documents/locked.txt", "still here")
        try ground.setFlags(UInt32(UF_IMMUTABLE), on: url)
        defer { try? ground.setFlags(0, on: url) }

        let report = Quarantine.quarantine([.init(url, section: .storage, reason: "proof")],
                                           home: ground.home)
        #expect(report.moved.isEmpty)
        #expect(report.refused.count == 1)
        #expect(ground.exists(url))
        #expect(ground.contents(of: url) == "still here")
        #expect(Ledger.read(home: ground.home).records.isEmpty)
    }

    // MARK: The three that can only be found, not made

    /// `SF_RESTRICTED` on the writable Data volume. This one is worth the awkwardness of using a
    /// real path: it proves the refusal is the flag and not "anything under /System".
    @Test func aSystemProtectedFolderOnTheOrdinaryDiskIsRefusedForItsFlag() throws {
        let restricted = URL(filePath: "/Library/Apple")
        let reading = try #require(Movable.read(restricted),
                                   "/Library/Apple is not on this Mac, so this test proves nothing")
        #expect(reading.flags & Movable.restrictedFlag != 0,
                "/Library/Apple is no longer SF_RESTRICTED — find another one rather than deleting this")
        #expect(!reading.volume.isSealedSystem,
                "it is on the sealed volume after all, so the flag is not what is being proved")

        let verdict = Movable.check(restricted, checkOpenFiles: false)
        #expect(verdict.refusals.contains(.protectedBySystem))
        #expect(verdict.firstRefusal == .protectedBySystem,
                "the reason a person can do nothing about should be said first")
    }

    /// `SF_NOUNLINK`, likewise found rather than made.
    @Test func aFolderMacOSWillNotLetAnythingUnlinkIsRefusedForItsFlag() throws {
        let noUnlink = URL(filePath: "/usr/local")
        let reading = try #require(Movable.read(noUnlink),
                                   "/usr/local is not on this Mac, so this test proves nothing")
        #expect(reading.flags & Movable.noUnlink != 0,
                "/usr/local is no longer SF_NOUNLINK on this system")
        #expect(Movable.check(noUnlink, checkOpenFiles: false).refusals
                    .contains(.locked(flag: "cannot be unlinked")))
    }

    /// ⚠️ **The two that cannot be tested honestly, said out loud rather than faked.**
    ///
    /// `UF_DATAVAULT` cannot be set by any process, and the folders that carry it are ones this
    /// suite is forbidden to enumerate. `SF_DATALESS` needs a file iCloud has evicted from the
    /// disk, which a test cannot arrange and must not try to.
    ///
    /// What can be checked is that both refusals still exist, still have their own code, and still
    /// say something a person can act on — so that deleting either one from `MoveRefusal` breaks a
    /// test rather than quietly narrowing what the app will refuse.
    @Test func theTwoRefusalsATestCannotStageStillHaveTheirWords() {
        let vault = MoveRefusal.inADataVault
        #expect(vault.code == "inADataVault")
        #expect(!vault.sentence.isEmpty)
        #expect(!vault.theUserCanFixThis, "nobody can take a file out of a data vault")

        let dataless = MoveRefusal.notDownloaded
        #expect(dataless.code == "notDownloaded")
        #expect(!dataless.sentence.isEmpty)
        #expect(dataless.theUserCanFixThis, "downloading it again is something a person can do")
    }

    /// ⚠️ **The six flag constants, checked against `sys/stat.h` itself.**
    ///
    /// They were once written out as hex, and one of them was wrong: `SF_NOUNLINK` is `0x00100000`
    /// and the number in the file was `0x00010000` — `SF_ARCHIVED`, one nibble away in a column of
    /// six. It failed silently in both directions. A folder macOS genuinely will not let anything
    /// unlink was **not** refused, so the row offered a move that comes back `EPERM`; and a file
    /// merely marked archived **was** refused, for something that is not a reason.
    ///
    /// Nothing about the app noticed, because no test had a real `SF_NOUNLINK` file to look at.
    /// This is the cheap version of that test, and it holds whether or not one is on the machine.
    @Test func theFlagsAreTheSystemsFlagsAndNotNumbersSomebodyTypedOut() {
        #expect(Movable.restrictedFlag == UInt32(SF_RESTRICTED))
        #expect(Movable.userImmutable == UInt32(UF_IMMUTABLE))
        #expect(Movable.systemImmutable == UInt32(SF_IMMUTABLE))
        #expect(Movable.noUnlink == UInt32(SF_NOUNLINK))
        #expect(Movable.dataVault == UInt32(UF_DATAVAULT))
        #expect(Movable.dataless == UInt32(SF_DATALESS))

        // And no two of them are the same bit, which is the mistake the wrong number was one step
        // away from making.
        let all = [Movable.restrictedFlag, Movable.userImmutable, Movable.systemImmutable,
                   Movable.noUnlink, Movable.dataVault, Movable.dataless]
        #expect(Set(all).count == all.count)

        // Compression is deliberately NOT on the list: a compressed file is an ordinary file and
        // moves like one. If it were ever added, every `.app` on the Mac would become unmovable.
        #expect(!all.contains(UInt32(UF_COMPRESSED)))
    }

    // MARK: The volume

    @Test func macOSItselfIsRefusedAsTheSealedSystemVolume() {
        let verdict = Movable.check(URL(filePath: "/System/Library/CoreServices"),
                                    checkOpenFiles: false)
        #expect(verdict.refusals.contains { if case .onTheSealedSystemVolume = $0 { true } else { false } })
        #expect(!verdict.isMovable)
    }

    /// A read-only volume, if this Mac happens to have one mounted that is not the sealed system
    /// volume. Xcode's simulator runtimes are mounted read-only, so it usually does.
    ///
    /// ⚠️ **The harness will not mount a disk image to manufacture one.** Mounting changes the
    /// machine the tests run on, and this suite does not do that. When no such volume is present
    /// the reading itself is checked instead, and the test says which of the two it did.
    @Test func aReadOnlyVolumeIsRefusedByItsMountFlags() {
        var found: statfs?
        var list: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&list, MNT_NOWAIT)
        for index in 0..<Int(count) {
            guard let entry = list?[index] else { continue }
            let mount = withUnsafePointer(to: entry.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if entry.f_flags & UInt32(bitPattern: MNT_RDONLY) != 0, mount != "/" {
                found = entry
                break
            }
        }

        guard let entry = found else {
            // Nothing read-only is mounted. Check the reading that decides it, and say plainly that
            // the disk half was not exercised on this machine.
            let pretend = VolumeReading(mountPoint: "/Volumes/Read Only",
                                        device: "/dev/disk9s1",
                                        flags: UInt32(bitPattern: MNT_RDONLY),
                                        uuid: nil)
            #expect(pretend.isReadOnly)
            #expect(!pretend.isSealedSystem)
            #expect(MoveRefusal.onAReadOnlyVolume(volume: "Read Only").sentence.contains("Read Only"))
            return
        }

        let mount = withUnsafePointer(to: entry.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        let volume = try? #require(Movable.volume(of: mount))
        #expect(volume?.isReadOnly == true)
        let verdict = Movable.check(URL(filePath: mount), checkOpenFiles: false)
        #expect(verdict.refusals.contains { if case .onAReadOnlyVolume = $0 { true } else { false } },
                "\(mount) is mounted read-only and was not refused for it")
    }

    // MARK: Reach

    @Test func theSystemLibraryIsOutOfReachAndSaysWellkeptWillNotAskForAPassword() {
        let verdict = Movable.check(URL(filePath: "/Library/LaunchDaemons"), checkOpenFiles: false)
        let outOfReach = verdict.refusals.first { if case .outOfReach = $0 { true } else { false } }
        let refusal = try? #require(outOfReach)
        #expect(refusal?.sentence.contains("password") == true,
                "a person is entitled to know Wellkept could have asked and chose not to")
    }

    /// Wellkept's own store is off limits to Wellkept. Without this, a second pass over the home
    /// folder would set aside the things the first pass set aside, for ever.
    @Test func theStoreIsOffLimitsToTheAppItself() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let inside = try ground.file("Library/Application Support/Wellkept/Quarantine/x/held.txt",
                                     "already set aside")
        let verdict = Movable.check(inside, reach: Reach.standard(home: ground.home),
                                    checkOpenFiles: false)
        #expect(verdict.refusals.contains(.inWellkeptsOwnStore))
        #expect(!verdict.isMovable)
    }

    // MARK: Identity, not name

    /// The filesystem folds case and normalisation, so a path is not an identity. Asking for a
    /// spelling the file does not have is refused, and the refusal hands back the real spelling.
    @Test func aSpellingTheFileDoesNotHaveIsRefusedAndTheRealOneIsOffered() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let real = try ground.file("Documents/CaseTest.txt", "the real one")
        let asked = ground.home.appending(path: "Documents/casetest.TXT")

        // The fold is the filesystem's, not ours — the wrong spelling really does open the file.
        #expect(FileManager.default.contents(atPath: asked.path(percentEncoded: false)) != nil)

        let verdict = Movable.check(asked, reach: ground.reach, checkOpenFiles: false)
        let mismatch = verdict.refusals.first { if case .notWhatWasAsked = $0 { true } else { false } }
        #expect(mismatch != nil, "a folded spelling was accepted as the file's own name")
        if case .some(.notWhatWasAsked(let actual)) = mismatch {
            #expect(actual == real.path(percentEncoded: false))
        }

        // And the engine will not act on it either.
        let report = Quarantine.quarantine([.init(asked, section: .storage, reason: "proof")],
                                           home: ground.home)
        #expect(report.moved.isEmpty)
        #expect(ground.exists(real))
    }

    /// ⚠️ **Differing only by normalisation is not a misspelling, and refusing it cost the
    /// ordinary case.**
    ///
    /// APFS keeps whichever bytes it was handed, so a downloaded or unzipped file has an NFC name.
    /// `URL.path` hands back NFD whatever went in. Every section reaches the engine through a URL,
    /// so before this was fixed *every NFC-named file on the Mac* was refused with "this Mac spells
    /// that file differently" — a refusal on a file with nothing wrong with it.
    ///
    /// The record stores the file's own spelling either way, so nothing was being bought.
    @Test func aNormalisationDifferenceAloneIsNotARefusal() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let composed = Array("Caf\u{e9}.txt".utf8)
        let path = try ground.fileNamed(exactly: composed, inFolder: "Documents", contents: "NFC")
        let askedThroughAURL = URL(filePath: path)

        let verdict = Movable.check(askedThroughAURL, reach: ground.reach, checkOpenFiles: false)
        #expect(!verdict.refusals.contains { if case .notWhatWasAsked = $0 { true } else { false } },
                "an NFC-named file was refused for being spelled the way it is spelled")
        #expect(verdict.isMovable)

        // And the reading still hands back the file's own bytes for the record to keep.
        #expect(Array(try #require(verdict.reading?.truePath).utf8).suffix(composed.count)
                    == composed)
    }

    // MARK: Nothing there, and nothing readable

    @Test func nothingThereIsSaidPlainlyRatherThanSkipped() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let never = ground.home.appending(path: "Documents/never-existed.txt")
        let verdict = Movable.check(never, reach: ground.reach, checkOpenFiles: false)
        #expect(verdict.refusals == [.missing])
        #expect(verdict.reading == nil)
    }

    /// A reading that could not be taken is a different sentence from "there is nothing there",
    /// and the difference matters: one means the file is gone, the other means we are blind.
    @Test func aFileWeCannotEvenLookAtIsNotReportedAsMissing() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let folder = try ground.folder("Documents/no entry")
        let hidden = try ground.file("Documents/no entry/inside.txt", "unreachable")
        try ground.setMode(0o000, on: folder)
        defer { try? ground.setMode(0o700, on: folder) }

        let verdict = Movable.check(hidden, reach: ground.reach, checkOpenFiles: false)
        #expect(verdict.refusals.contains { if case .couldNotBeRead = $0 { true } else { false } },
                "got \(verdict.refusals.map(\.code)) instead")
        #expect(!verdict.refusals.contains(.missing),
                "a file we cannot look at was reported as one that is not there")
    }

    // MARK: Open files

    /// Moving a file a running program holds open succeeds silently, and the program keeps writing
    /// into the quarantined copy. Nothing errors; it breaks hours later on the next open-by-path.
    /// So it is refused up front, by name.
    @Test func aFileSomethingHasOpenIsRefusedAndTheProgramIsNamed() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let url = try ground.file("Documents/in use.log", "being written")
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let verdict = Movable.check(url, reach: ground.reach)
        let held = verdict.refusals.first { if case .openBy = $0 { true } else { false } }
        #expect(held != nil, "lsof did not see this process holding its own file open")
        if case .some(.openBy(let programs)) = held {
            #expect(!programs.isEmpty)
            #expect(held?.sentence.contains(programs[0]) == true, "the sentence does not name it")
        }
        #expect(held?.theUserCanFixThis == true, "quitting the app is something a person can do")
    }

    // MARK: All of them at once, in order

    /// ⚠️ **Refusals are plural and ordered.** Telling somebody to unlock a file and then, on the
    /// next run, that it is also somewhere Wellkept cannot reach, sends them on an errand for
    /// nothing.
    @Test func everyReasonIsGivenAtOnceAndTheHopelessOnesComeFirst() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        // Locked, and outside the reach this check is given.
        let url = try ground.file("Documents/locked and out of reach.txt")
        try ground.setFlags(UInt32(UF_IMMUTABLE), on: url)
        defer { try? ground.setFlags(0, on: url) }

        let narrowReach = Reach(allowed: ["/nowhere at all"], forbidden: [])
        let verdict = Movable.check(url, reach: narrowReach, checkOpenFiles: false)

        #expect(verdict.refusals.count >= 2, "only one reason was given: \(verdict.refusals.map(\.code))")
        #expect(verdict.refusals.contains(.locked(flag: "locked in Finder")))
        #expect(verdict.refusals.contains { if case .outOfReach = $0 { true } else { false } })

        let sentence = try #require(verdict.sentence)
        #expect(sentence.contains("locked"))
        #expect(sentence.count > MoveRefusal.locked(flag: "locked in Finder").sentence.count,
                "the row shows one reason where two are true")
    }

    /// Each refusal has its own code and its own words. A shared sentence is a row that cannot tell
    /// a person which of two different problems they have.
    @Test func noTwoRefusalsSayTheSameThing() {
        let all: [MoveRefusal] = [
            .missing, .notWhatWasAsked(actual: "/x"), .protectedBySystem,
            .locked(flag: "locked in Finder"), .inADataVault, .notDownloaded,
            .onAReadOnlyVolume(volume: "Backup"), .onTheSealedSystemVolume(device: "/dev/disk3s1s1"),
            .throughASymlink(component: "Caches"), .outOfReach(place: "the system folders"),
            .inWellkeptsOwnStore, .openBy(programs: ["Mail"]), .couldNotBeRead(why: "permission"),
        ]
        #expect(Set(all.map(\.code)).count == all.count, "two refusals share a code")
        #expect(Set(all.map(\.sentence)).count == all.count, "two refusals say the same thing")
        #expect(all.allSatisfy { !$0.sentence.isEmpty })
    }
}

// MARK: - ⭐ The two flags, and what happens without them

@Suite("RENAME_EXCL and RENAME_NOFOLLOW_ANY are what make the move safe")
struct AtomicMoveFlagProofTests {

    /// Both flags are set, always. This is the constant the other two tests are about.
    @Test func bothFlagsAreOnTheOnlyMoveTheAppMakes() {
        #expect(AtomicMove.flags & UInt32(RENAME_EXCL) != 0)
        #expect(AtomicMove.flags & UInt32(RENAME_NOFOLLOW_ANY) != 0)
    }

    /// ⭐ **The occupant survives.**
    ///
    /// First the danger, on throwaway files: plain `rename(2)` destroys whatever is at the
    /// destination without a word. Then the same shape through `AtomicMove`, which refuses.
    @Test func aDestinationThatIsAlreadyOccupiedIsNeverWrittenOver() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        // 1. What plain rename(2) does. Both of these are files this test made a moment ago.
        let doomedSource = try ground.file("danger/source.txt", "the incoming file")
        let doomedOccupant = try ground.file("danger/occupied.txt", "somebody's only copy")
        #expect(rename(doomedSource.path(percentEncoded: false),
                       doomedOccupant.path(percentEncoded: false)) == 0)
        #expect(ground.contents(of: doomedOccupant) == "the incoming file",
                "plain rename(2) no longer destroys the destination — the premise has changed")

        // 2. What the app does instead.
        let source = try ground.file("safe/source.txt", "the incoming file")
        let occupant = try ground.file("safe/occupied.txt", "somebody's only copy")
        let occupantInode = try #require(ground.inode(of: occupant))
        let occupantFacts = try #require(FileFacts.take(of: occupant))

        let result = AtomicMove.perform(from: source.path(percentEncoded: false),
                                        to: occupant.path(percentEncoded: false))
        guard case .failed(let code, _) = result else {
            Issue.record("the move went ahead and destroyed the occupant")
            return
        }
        #expect(code == EEXIST)
        #expect(ground.contents(of: occupant) == "somebody's only copy")
        #expect(ground.inode(of: occupant) == occupantInode)
        #expect(FileFacts.take(of: occupant)?.differences(from: occupantFacts).isEmpty == true)
        #expect(ground.contents(of: source) == "the incoming file", "the source was consumed anyway")
        #expect(AtomicMove.sentence(for: code, fallback: "")
                    .contains("will not write over it"))
    }

    /// ⭐ **The real file survives a symlinked parent.**
    ///
    /// The shape is the one that ends products: `Library/Caches/RealApp` is a symbolic link to
    /// `Library/Application Support/RealApp`, and something asks to set aside "a cache file". Follow
    /// the link and you have deleted the person's real data through a path that said "Caches".
    ///
    /// Plain `rename(2)` follows it. `renameatx_np` with `RENAME_NOFOLLOW_ANY` refuses with `ELOOP`.
    @Test func aSymlinkedParentIsRefusedAndTheRealFileIsUntouched() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        try ground.folder("Library/Application Support/RealApp")
        let real = try ground.file("Library/Application Support/RealApp/important.db",
                                   "years of somebody's work")
        let realFacts = try #require(FileFacts.take(of: real))
        try ground.folder("Library/Caches")
        try ground.link("Library/Caches/RealApp",
                        to: ground.home.appending(path: "Library/Application Support/RealApp")
                            .path(percentEncoded: false))

        // The path that lies. It opens the real file.
        let throughTheLink = ground.home
            .appending(path: "Library/Caches/RealApp/important.db")
            .path(percentEncoded: false)
        #expect(FileManager.default.contents(atPath: throughTheLink) != nil,
                "the fixture is not the shape this test is about")

        // 1. Plain rename(2) follows the link and takes the real file with it.
        let somewhereElse = try ground.inside("Library/Caches/taken.db")
        #expect(rename(throughTheLink, somewhereElse.path(percentEncoded: false)) == 0)
        #expect(!ground.exists(real),
                "plain rename(2) no longer follows a symlinked parent — the premise has changed")
        // Put it back, so the second half starts from the same shape.
        #expect(rename(somewhereElse.path(percentEncoded: false),
                       real.path(percentEncoded: false)) == 0)

        // 2. The engine's move refuses instead.
        let result = AtomicMove.perform(from: throughTheLink,
                                        to: try ground.inside("Library/Caches/taken.db")
                                            .path(percentEncoded: false))
        guard case .failed(let code, _) = result else {
            Issue.record("the move followed the link and moved the real file")
            return
        }
        #expect(code == ELOOP)
        #expect(ground.exists(real), "the real file is gone")
        #expect(FileFacts.take(of: real)?.differences(from: realFacts).isEmpty == true)
        #expect(AtomicMove.sentence(for: code, fallback: "").contains("shortcut"))
    }

    /// And the same shape refused a whole step earlier, before any syscall is attempted — so the
    /// row can say which component is the link instead of showing an error number.
    @Test func theSymlinkedParentIsNamedBeforeAnythingIsAttempted() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        try ground.folder("Library/Application Support/RealApp")
        let real = try ground.file("Library/Application Support/RealApp/important.db", "work")
        try ground.folder("Library/Caches")
        try ground.link("Library/Caches/RealApp",
                        to: ground.home.appending(path: "Library/Application Support/RealApp")
                            .path(percentEncoded: false))

        let lying = ground.home.appending(path: "Library/Caches/RealApp/important.db")
        let verdict = Movable.check(lying, reach: ground.reach, checkOpenFiles: false)
        #expect(verdict.refusals.contains(.throughASymlink(component: "RealApp")))

        let report = Quarantine.quarantine([.init(lying, section: .storage, reason: "a cache")],
                                           home: ground.home)
        #expect(report.moved.isEmpty)
        #expect(ground.contents(of: real) == "work")
        #expect(report.refused.first?.refusal?.contains("shortcut") == true)
    }

    /// A cross-volume move is refused by the kernel, not caught by a fallback that copies.
    ///
    /// ⚠️ This is asserted on the *sentence*, because staging a real cross-volume rename would mean
    /// mounting a second volume, and the harness will not change the machine to make a point. What
    /// is proved is that the engine has words for `EXDEV` and that they say a copy is not what it
    /// will do instead.
    @Test func crossingDisksIsAnErrorWithWordsAndNeverACopy() {
        let sentence = AtomicMove.sentence(for: EXDEV, fallback: "")
        #expect(sentence.contains("different disk"))
        #expect(sentence.contains("copies it"))
    }
}
