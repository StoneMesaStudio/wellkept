// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  QuarantineTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The four verbs, exercised on real files in a sandbox that is thrown away afterwards.**
//
//  The tests that matter most are the ones that prove something did **not** happen: that a rename
//  cannot write over a file, that a restore refuses an occupied path rather than destroying
//  whatever is there now, and that no sentence anywhere claims a quarantine returned space it did not return.

// MARK: - ⭐ The one safe move

@Suite struct AtomicMoveTests {

    /// ⚠️ **Plain `rename(2)` silently destroys whatever occupies the destination.** A collision, a
    /// re-run batch, or a restore into a re-used name would otherwise destroy the exact file this
    /// engine exists to protect. `RENAME_EXCL` refuses instead.
    @Test func aMoveCanNeverWriteOverSomethingThatIsAlreadyThere() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let source = try sandbox.file("a.txt", contents: "the one being moved")
        let occupied = try sandbox.file("b.txt", contents: "somebody's newer work")

        let result = AtomicMove.perform(from: source.path(percentEncoded: false),
                                        to: occupied.path(percentEncoded: false))

        guard case .failed(let code, _) = result else {
            Issue.record("the move succeeded — RENAME_EXCL is missing and a file was just destroyed")
            return
        }
        #expect(code == EEXIST)
        #expect(sandbox.contents(of: occupied) == "somebody's newer work")
        #expect(sandbox.exists(source), "and the source is untouched")
        #expect(AtomicMove.sentence(for: EEXIST, fallback: "")
                    .contains("will not write over it"))
    }

    /// ⚠️ **The failure class that ends a product.** `RENAME_NOFOLLOW_ANY` returns `ELOOP` rather
    /// than acting on the real file at the other end of the link.
    @Test func aMoveThroughASymlinkedParentIsRefusedBySyscall() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let real = try sandbox.folder("real")
        try sandbox.file("real/live.db", contents: "somebody's actual data")
        try sandbox.link("shortcut", to: real)

        let result = AtomicMove.perform(
            from: sandbox.home.appending(path: "shortcut/live.db").path(percentEncoded: false),
            to: sandbox.home.appending(path: "taken.db").path(percentEncoded: false))

        guard case .failed(let code, _) = result else {
            Issue.record("the move followed a symlink — RENAME_NOFOLLOW_ANY is missing")
            return
        }
        #expect(code == ELOOP)
        #expect(sandbox.contents(of: real.appending(path: "live.db")) == "somebody's actual data")
    }

    /// The whole reason a rename is the only move: it re-points a directory entry and the file is
    /// otherwise untouched, inode included.
    @Test func aRenamePreservesTheInodeAndThePermissions() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let source = try sandbox.file("Documents/keep.txt")
        chmod(source.path(percentEncoded: false), 0o640)
        let before = sandbox.inode(of: source)
        let destination = sandbox.home.appending(path: "moved.txt")

        #expect(AtomicMove.perform(from: source.path(percentEncoded: false),
                                   to: destination.path(percentEncoded: false)) == .moved)
        #expect(sandbox.inode(of: destination) == before)
        #expect(sandbox.mode(of: destination) == 0o640)
    }

    @Test func everyFailureThatMattersHasItsOwnSentence() {
        for code in [EEXIST, ELOOP, EXDEV, EACCES, ENOENT] {
            let sentence = AtomicMove.sentence(for: code, fallback: "FALLBACK")
            #expect(sentence != "FALLBACK", "errno \(code) needs a sentence a person can read")
            #expect(sentence.hasSuffix("."))
        }
        #expect(AtomicMove.sentence(for: EIO, fallback: "FALLBACK") == "FALLBACK")
    }
}

// MARK: - ⭐ Verb 1: Quarantine

@Suite struct QuarantineVerbTests {

    @Test func settingSomethingAsideMovesItAndRecordsWhereItCameFrom() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/Old Installer.dmg", contents: "installer bytes")
        let inodeBefore = sandbox.inode(of: file)

        let report = Quarantine.quarantine(
            [.init(file, section: .storage, reason: "An installer you already used")],
            home: sandbox.home)

        #expect(report.trouble == nil)
        let record = try #require(report.moved.first)
        #expect(!sandbox.exists(file), "the original is gone from where it was")
        #expect(sandbox.exists(record.quarantinedURL))
        #expect(sandbox.contents(of: record.quarantinedURL) == "installer bytes")
        #expect(sandbox.inode(of: record.quarantinedURL) == inodeBefore,
                "a rename keeps the inode — a copy would not, and a copy loses metadata")
        #expect(record.originalName == "Old Installer.dmg",
                "the file keeps its exact name inside its own folder")
        #expect(record.reason == "An installer you already used")
        #expect(Ledger.read(home: sandbox.home).records.map(\.id) == [record.id])
        #expect(!sandbox.exists(sandbox.intent), "the intent is cleared when the ledger is right")
    }

    /// ⚠️ **Nothing anywhere may say a quarantine freed space.** It frees nothing: 391 MB across
    /// 100,000 files moved free space by −8 KiB.
    @Test func theSentenceAfterwardsPromisesNoSpaceBack() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/big.dmg", contents: String(repeating: "x", count: 900))
        let report = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                           home: sandbox.home)

        let sentence = report.sentence.lowercased()
        #expect(!sentence.contains("freed"))
        #expect(!sentence.contains("reclaim"))
        #expect(report.sentence.contains("no space comes back until you empty the quarantine"))
    }

    @Test func aRefusedItemIsReportedWithItsReasonAndNothingMoves() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Documents/locked.txt")
        let path = file.path(percentEncoded: false)
        #expect(chflags(path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(path, 0) }

        let report = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                           home: sandbox.home)
        #expect(report.moved.isEmpty)
        #expect(report.refused.count == 1)
        #expect(report.refused[0].refusal?.contains("locked") == true)
        #expect(sandbox.exists(file))
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)
    }

    /// One item refused does not stop the rest. A batch that gives up at the first obstacle makes
    /// somebody run it four times.
    @Test func oneRefusalDoesNotStopTheBatch() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let good = try sandbox.file("Downloads/one.dmg")
        let missing = sandbox.home.appending(path: "Downloads/never-existed.dmg")
        let alsoGood = try sandbox.file("Downloads/two.dmg")

        let report = Quarantine.quarantine([
            .init(good, section: .storage, reason: "unused"),
            .init(missing, section: .storage, reason: "unused"),
            .init(alsoGood, section: .storage, reason: "unused"),
        ], home: sandbox.home)

        #expect(report.moved.count == 2)
        #expect(report.refused.count == 1)
        #expect(Ledger.read(home: sandbox.home).records.count == 2)
    }

    /// An iCloud file is allowed. The report says the warning applies; it never refuses.
    @Test func anICloudFileIsSetAsideWithTheWarningRatherThanRefused() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox
            .file("Library/Mobile Documents/com~apple~CloudDocs/Desktop/notes.txt")
        let report = Quarantine.quarantine([.init(file, section: .storage, reason: "large")],
                                           home: sandbox.home)

        #expect(report.moved.count == 1, "iCloud is never a refusal")
        #expect(report.anyWasInICloud)
        #expect(report.moved[0].wasInICloud)
    }

    @Test func aFolderCanBeSetAsideWhole() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let folder = try sandbox.folder("Downloads/Old Project")
        try sandbox.file("Downloads/Old Project/inside.txt", contents: "inner")

        let report = Quarantine.quarantine([.init(folder, section: .storage, reason: "finished")],
                                           home: sandbox.home)
        let record = try #require(report.moved.first)
        #expect(record.isDirectory)
        #expect(sandbox.contents(of: record.quarantinedURL.appending(path: "inside.txt")) == "inner")
    }
}

// MARK: - ⭐ Verb 2: Restore

@Suite struct RestoreVerbTests {

    @Test func somethingPutBackIsExactlyWhereAndWhatItWas() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/Old Installer.dmg", contents: "installer bytes")
        chmod(file.path(percentEncoded: false), 0o640)
        let inodeBefore = sandbox.inode(of: file)

        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        let report = Quarantine.restore([record], home: sandbox.home)
        #expect(report.stuck.isEmpty, "something would not go back: \(report.sentence)")
        #expect(sandbox.exists(file))
        #expect(sandbox.contents(of: file) == "installer bytes")
        #expect(sandbox.inode(of: file) == inodeBefore)
        #expect(sandbox.mode(of: file) == 0o640)
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)
        #expect(!sandbox.exists(record.holderURL), "the empty holder folder goes with it")
    }

    /// ⚠️ **The refusal that makes restore safe.** Between the quarantine and the restore the
    /// person may have re-downloaded the installer or saved the document again. Moving over it
    /// destroys the newer one — the opposite of what they asked for.
    @Test func anOccupiedOriginalPathIsARefusalAndNeverAnOverwrite() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/report.pdf", contents: "the old one")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        // They saved it again in the meantime.
        try sandbox.file("Downloads/report.pdf", contents: "THE NEW ONE, WRITTEN SINCE")

        let report = Quarantine.restore([record], home: sandbox.home)
        #expect(report.restored.isEmpty)
        #expect(report.stuck.count == 1)
        #expect(sandbox.contents(of: file) == "THE NEW ONE, WRITTEN SINCE",
                "the newer file was written over — this is the whole reason restore refuses")
        #expect(sandbox.exists(record.quarantinedURL), "and the old one is still safely in the store")
        #expect(report.sentence.contains("will not write over it"))
        #expect(Ledger.read(home: sandbox.home).records.count == 1,
                "a refused restore keeps its record")
    }

    /// A missing parent folder is made again, with the permissions it had.
    @Test func aMissingParentFolderIsRecreatedWithItsOwnPermissions() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let folder = try sandbox.folder("Downloads/Archive")
        chmod(folder.path(percentEncoded: false), 0o700)
        let file = try sandbox.file("Downloads/Archive/thing.zip")

        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)
        #expect(record.parentMode == 0o700)

        try FileManager.default.removeItem(at: folder)
        let report = Quarantine.restore([record], home: sandbox.home)

        #expect(report.stuck.isEmpty, "something would not go back: \(report.sentence)")
        #expect(sandbox.exists(file))
        #expect(sandbox.mode(of: folder) == 0o700,
                "a folder made with the default mask is not the folder that was there")
    }

    /// ⚠️ Identity, not name. Somebody may have put a different file in that folder by hand.
    @Test func aSubstitutedFileInTheStoreIsNotPutBack() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg", contents: "the real one")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        try FileManager.default.removeItem(at: record.quarantinedURL)
        try Data("something else entirely".utf8).write(to: record.quarantinedURL)

        let report = Quarantine.restore([record], home: sandbox.home)
        #expect(report.restored.isEmpty)
        #expect(report.stuck.first?.refusal == .notTheSameFile)
        #expect(!sandbox.exists(file))
    }

    /// A store on a disk that is not plugged in is "plug it back in", never "the file is gone".
    @Test func anUnmountedStoreSaysPlugItBackIn() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        try FileManager.default.removeItem(at: URL(filePath: record.storeRoot))

        let report = Quarantine.restore([record], home: sandbox.home)
        guard case .volumeIsNotMounted = try #require(report.stuck.first?.refusal) else {
            Issue.record("an absent store must read as a disconnected disk")
            return
        }
        #expect(report.sentence.contains("Plug"))
    }
}

// MARK: - ⭐ Verb 3: Delete

@Suite struct DeleteVerbTests {

    @Test func emptyingTheQuarantineRemovesTheFilesAndTheirRecords() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        let report = Quarantine.delete([record], expecting: 1, home: sandbox.home)
        #expect(report.deleted.count == 1)
        #expect(report.refused.isEmpty)
        #expect(!sandbox.exists(record.quarantinedURL))
        #expect(!sandbox.exists(record.holderURL))
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)
    }

    /// ⚠️ **The classic way software deletes the wrong thing** is a call site that hands over the
    /// whole list where it meant to hand over the selection.
    @Test func aCountThatDoesNotMatchWhatTheUserSawRemovesNothing() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let one = try sandbox.file("Downloads/one.dmg")
        let two = try sandbox.file("Downloads/two.dmg")
        let moved = Quarantine.quarantine([
            .init(one, section: .storage, reason: "unused"),
            .init(two, section: .storage, reason: "unused"),
        ], home: sandbox.home).moved

        // The screen showed one selected; the caller handed over both.
        let report = Quarantine.delete(moved, expecting: 1, home: sandbox.home)
        #expect(report.deleted.isEmpty)
        #expect(report.refused.count == 2)
        #expect(moved.allSatisfy { sandbox.exists($0.quarantinedURL) })
        #expect(Ledger.read(home: sandbox.home).records.count == 2)
    }

    /// ⚠️ **Free space is an estimate even after a real delete** — a local snapshot keeps the
    /// blocks allocated. The figure is measured before and after, never promised.
    @Test func whatCameBackIsMeasuredAndNeverCalledFreed() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg", contents: String(repeating: "x", count: 5_000))
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        let report = Quarantine.delete([record], expecting: 1, home: sandbox.home)
        #expect(report.freeBefore != nil, "the measurement is taken, not skipped")
        #expect(report.freeAfter != nil)
        #expect((report.cameBack ?? 0) >= 0, "a negative figure would be an artefact, not a fact")

        let sentence = report.sentence.lowercased()
        #expect(!sentence.contains("freed"))
        #expect(!sentence.contains("reclaim"))
        #expect(report.sentence.contains("Removed"))
    }

    /// When nothing comes back the sentence says why, rather than reporting the file sizes as
    /// though they were space returned.
    @Test func nothingComingBackIsExplainedRatherThanHidden() {
        let report = Quarantine.DeleteReport(
            deleted: [], refused: [], trouble: nil, freeBefore: 1_000, freeAfter: 1_000)
        #expect(report.sentence == "Nothing was removed.")

        let measured = Quarantine.DeleteReport(
            deleted: [], refused: [], trouble: nil, freeBefore: nil, freeAfter: nil)
        #expect(measured.cameBack == nil)
    }

    @Test func anItemThatIsAlreadyGoneTakesItsRecordWithIt() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)
        try FileManager.default.removeItem(at: record.holderURL)

        let report = Quarantine.delete([record], expecting: 1, home: sandbox.home)
        #expect(report.deleted.count == 1, "a record of nothing helps nobody")
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)
    }
}

// MARK: - ⭐ Malware containment

@Suite struct ContainmentTests {

    /// Containment is two reversible, recorded changes. **Zipping the store was rejected** — an
    /// archive drops the metadata a rename preserves, and for a malicious file it hides it from
    /// macOS's own scanner rather than defusing it.
    @Test func containingAFileTakesAwayItsRightToRunAndMarksItUntrusted() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing", contents: "#!/bin/sh\necho hello\n")
        let path = file.path(percentEncoded: false)
        chmod(path, 0o755)

        let outcome = Quarantine.contain(file, reason: "macOS found malware here",
                                         home: sandbox.home)
        #expect(outcome.refusal == nil, "containment was refused: \(outcome.refusal ?? "")")
        let record = try #require(outcome.record)

        #expect(sandbox.exists(file), "it stays where XProtect can still see it")
        #expect(sandbox.mode(of: file)! & 0o111 == 0, "nothing may run it")
        #expect(Quarantine.readAttribute(Quarantine.untrustedAttribute, at: path) != nil)
        #expect(record.containment?.modeBefore == 0o755)
        #expect(record.wasContainedInPlace)
        #expect(record.section == .security)
    }

    @Test func releasingPutsThePermissionsAndTheMarkBackExactly() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing")
        let path = file.path(percentEncoded: false)
        chmod(path, 0o755)

        let record = try #require(Quarantine.contain(file, reason: "found", home: sandbox.home).record)
        #expect(Quarantine.release(record) == nil)

        #expect(sandbox.mode(of: file) == 0o755)
        #expect(Quarantine.readAttribute(Quarantine.untrustedAttribute, at: path) == nil,
                "the file had no mark before, so it must have none after")
    }

    /// Restoring a contained record is the same act as releasing it, because nothing ever moved.
    @Test func restoringAContainedItemUndoesTheContainment() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing")
        chmod(file.path(percentEncoded: false), 0o755)
        let record = try #require(Quarantine.contain(file, reason: "found", home: sandbox.home).record)

        let report = Quarantine.restore([record], home: sandbox.home)
        #expect(report.stuck.isEmpty, "something would not go back: \(report.sentence)")
        #expect(sandbox.mode(of: file) == 0o755)
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)
    }

    /// A running malicious thing is exactly what wants defusing, so the open-file refusal does not
    /// apply here — but every other refusal still does.
    @Test func containmentStillRefusesWhatItCannotSafelyTouch() {
        let outcome = Quarantine.contain(URL(filePath: "/System/Library/CoreServices/Finder.app"),
                                         reason: "no")
        #expect(outcome.record == nil)
        #expect(outcome.refusal?.contains("sealed system volume") == true)
    }
}

// MARK: - The store

@Suite struct QuarantineStoreTests {

    /// ⚠️ The store lives on the same volume as the file, always. Every hazard measured — split
    /// hard links, sparse files inflating six thousand times, partial copies, running out of space
    /// mid-batch — exists only on the cross-volume path.
    @Test func theStoreIsOnTheSameVolumeAsTheFile() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg")
        let reading = try #require(Movable.read(file))
        let store = try QuarantineStore.forItem(on: reading.volume, home: sandbox.home).get()

        #expect(store.volume.isSameVolume(as: reading.volume))
        #expect(store.root == StorageManifest.quarantineDirectory(home: sandbox.home))
    }

    /// Each item gets its own folder named by the record's id, so a collision is not merely
    /// unlikely — it is impossible, and the file keeps its exact name.
    @Test func namingCannotCollideAndTheNameIsKept() {
        let store = QuarantineStore(root: URL(filePath: "/tmp/store"),
                                    volume: VolumeReading(mountPoint: "/", device: "/dev/disk1",
                                                          flags: 0, uuid: nil))
        let first = UUID(), second = UUID()
        #expect(store.destination(for: "report.pdf", id: first)
                != store.destination(for: "report.pdf", id: second))
        #expect(store.destination(for: "report.pdf", id: first).lastPathComponent == "report.pdf")
    }

    @Test func aVolumeWithNoApplicationSupportGetsAStoreAtItsOwnRoot() {
        let elsewhere = VolumeReading(mountPoint: "/Volumes/Backup Drive",
                                      device: "/dev/disk6s2", flags: 0, uuid: nil)
        let location = QuarantineStore.location(for: elsewhere,
                                                home: URL(filePath: "/Users/example"))
        #expect(location.path(percentEncoded: false)
                == "/Volumes/Backup Drive/\(QuarantineStore.rootFolderName)")
    }

    @Test func everyStoreRefusalSaysWhyInPlainWords() {
        let refusals: [StoreRefusal] = [
            .volumeUnreadable(path: "/x"),
            .couldNotMakeAPlace(volume: "Backup Drive", why: "no permission"),
            .wouldCrossVolumes(from: "this Mac's disk", to: "Backup Drive"),
        ]
        for refusal in refusals {
            #expect(refusal.sentence.hasSuffix("."))
            #expect(!refusal.code.isEmpty)
        }
        #expect(refusals[2].sentence.contains("copies the file"),
                "the reason cross-volume is refused has to be in the sentence")
    }
}

// MARK: - The permanent row

@Suite struct QuarantineSummaryTests {

    @Test func anEmptyQuarantineSaysSoPlainly() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let summary = Quarantine.summary(home: sandbox.home)
        #expect(summary.isEmpty)
        #expect(summary.rowSentence() == "Nothing is set aside.")
    }

    /// The settled shape, 2026-08-28: *"40 GB set aside — oldest is 12 days old"*, with the Empty
    /// button on it.
    @Test func theRowIsSizeSetAsideAndTheAgeOfTheOldest() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let now = Date()
        let file = try sandbox.file("Downloads/thing.dmg", contents: String(repeating: "x", count: 4_000))
        _ = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                  home: sandbox.home)

        let twelveDaysOn = Calendar.current.date(byAdding: .day, value: 12, to: now)!
        let row = Quarantine.summary(home: sandbox.home, now: twelveDaysOn).rowSentence(now: twelveDaysOn)

        #expect(row.contains("set aside"))
        #expect(row.contains("the oldest is 12 days old"))
        #expect(!row.lowercased().contains("freed"))
    }

    /// ⚠️ An unreadable ledger is shown **instead of** a count, never alongside one.
    @Test func anUnreadableLedgerReplacesTheCountRatherThanReadingAsZero() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try FileManager.default.createDirectory(at: sandbox.ledger.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("[{".utf8).write(to: sandbox.ledger)

        let summary = Quarantine.summary(home: sandbox.home)
        #expect(summary.trouble != nil)
        #expect(!summary.isEmpty, "a summary that could not look must not read as empty")
        #expect(summary.rowSentence().contains("cannot tell you"))
    }

    @Test func aRecordWhoseFileIsGoneIsCountedAndSaidOutLoud() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)
        try FileManager.default.removeItem(at: record.holderURL)

        let summary = Quarantine.summary(home: sandbox.home)
        #expect(summary.unaccountedFor == 1)
        #expect(summary.unaccountedSentence?.contains("no longer where it put it") == true)
    }
}

// MARK: - The settled words

@Suite struct QuarantineWordingTests {

    /// Before the button. **"Nothing is deleted and no space comes back until you empty the
    /// quarantine."**
    @Test func theWordsBeforeTheButtonPromiseNothing() {
        let words = QuarantineWords.beforeSettingAside(40_000_000_000)
        #expect(words.contains("Set aside"))
        #expect(words.contains("Nothing is deleted"))
        #expect(words.contains("no space comes back until you empty the quarantine"))
        #expect(!words.lowercased().contains("freed"))
    }

    /// ⚠️ **If the disk is full today, quarantine is the wrong button** — and Storage has to say so
    /// rather than let somebody set aside 40 GB and watch nothing happen.
    @Test func theDiskFullCaseIsNamedRatherThanLeftToBeDiscovered() {
        #expect(QuarantineWords.whenTheDiskIsAlreadyFull.contains("will not do it"))
        #expect(QuarantineWords.whenTheDiskIsAlreadyFull.contains("one sitting"))
    }

    /// The iCloud warning is really about the gap: the file is off the person's other devices while
    /// still taking up the same room here.
    @Test func theICloudGapIsExplained() {
        #expect(QuarantineWords.iCloudGap.contains("taking up the same room"))
    }
}

// MARK: - ⭐ Free space is measured, and measured on every disk the batch touched

//  ⚠️ **Never a promised figure.** Free space is an estimate even after a real delete — a local
//  Time Machine snapshot keeps the blocks allocated until macOS lets them go, in its own time. So
//  the delete measures before and after and reports what actually came back.
//
//  Regression, 2026-08-28: the measurement was taken on the first record's volume alone. A
//  selection spanning the boot disk and a plugged-in drive would have had most of its space
//  reported as not having come back — a wrong number that reads exactly like the snapshot effect
//  this measurement exists to reveal honestly.

@Suite struct FreeSpaceMeasurementTests {

    @Test func oneDiskIsCountedOnceHoweverManyItemsAreOnIt() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let store = sandbox.store.path(percentEncoded: false)
        try FileManager.default.createDirectory(at: sandbox.store, withIntermediateDirectories: true)

        let records = (1...3).map { n in
            QuarantineRecord(
                originalPath: sandbox.home.appending(path: "Downloads/\(n).dmg")
                    .path(percentEncoded: false),
                originalName: "\(n).dmg",
                identity: FileIdentity(volumeUUID: nil, volumeDevice: "/dev/disk3s5", inode: UInt64(n)),
                quarantinedPath: store + "/\(n)/\(n).dmg", storeRoot: store,
                mode: 0o644, ownerID: 501, groupID: 20, flags: 0,
                createdOn: Date(), modifiedOn: Date(), bytes: 10,
                isDirectory: false, isSymbolicLink: false, parentMode: 0o755,
                section: .storage, reason: "unused", wasInICloud: false)
        }

        let volumes = Quarantine.storeVolumes(of: records, home: sandbox.home)
        #expect(volumes.count == 1, "three items on one disk is one disk, not three")

        let single = try #require(Quarantine.freeBytes(onVolumeAt: store))
        let summed = try #require(Quarantine.freeBytes(across: volumes))

        // ⚠️ **Not equality.** Both figures are live readings of a real disk taken microseconds
        // apart, and this Mac's free space genuinely moves between them — the run that caught this
        // differed by 4,096 bytes, which is one block, written by some daemon minding its own
        // business. The defect this test exists to catch is counting one volume three times, which
        // would make `summed` roughly triple, not one block larger. Asserting equality made a real
        // test intermittently red for a reason that has nothing to do with the thing it checks —
        // and an intermittently red gate is one nobody reads.
        let drift = abs(Int64(summed) - Int64(single))
        #expect(drift < 64 * 1_024 * 1_024,
                "free space moved by \(drift) bytes between two readings — that is not drift, that is the same volume counted more than once")
    }

    /// ⚠️ `nil`, never zero. Zero free bytes is a full disk; the sentence for that is nothing like
    /// the sentence for "Wellkept could not take the reading".
    @Test func aReadingThatCouldNotBeTakenIsNotReportedAsZero() {
        #expect(Quarantine.freeBytes(across: []) == nil)
        #expect(Quarantine.freeBytes(across: ["/no/such/place/at/all"]) == nil)
        #expect(Quarantine.freeBytes(onVolumeAt: "/no/such/place/at/all") == nil)
    }

    /// The whole point of the type: what came back is measured, and a delete that returns nothing
    /// says so plainly rather than claiming the sum of the file sizes.
    @Test func aDeleteReportsWhatCameBackAndNeverWhatWasPromised() {
        let stalled = Quarantine.DeleteReport(deleted: [], refused: [], trouble: nil,
                                              freeBefore: 1_000, freeAfter: 1_000)
        #expect(stalled.cameBack == 0)

        let unreadable = Quarantine.DeleteReport(deleted: [], refused: [], trouble: nil,
                                                 freeBefore: nil, freeAfter: nil)
        #expect(unreadable.cameBack == nil, "no reading is not a reading of zero")

        // Other things write to the disk while a delete runs, so free space can go down. A negative
        // figure would be an artefact of the timing rather than a fact about the delete.
        let noisy = Quarantine.DeleteReport(deleted: [], refused: [], trouble: nil,
                                            freeBefore: 2_000, freeAfter: 1_000)
        #expect(noisy.cameBack == 0)
    }
}

// MARK: - ⭐ What reconciling found, said out loud

//  Reconciling can discover one thing nothing else in the app can: an item that is at neither its
//  own path nor the store. Its record is not in the ledger, so `Summary.unaccountedFor` will never
//  count it — and before `reconcileOnOpening` existed, that finding was computed at launch and
//  thrown away.

@Suite struct ReconcileReportTests {

    @Test func anOrdinaryLaunchHasNothingToSay() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let report = Quarantine.reconcileOnOpening(home: sandbox.home)
        #expect(report.isQuiet)
        #expect(report.sentence == nil, "an app that reports on a quiet launch is an app nobody reads")
    }

    @Test func anItemAtNeitherPlaceIsNamedRatherThanCounted() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let id = UUID()
        let record = QuarantineRecord(
            id: id,
            originalPath: sandbox.home.appending(path: "Downloads/Old Installer.dmg")
                .path(percentEncoded: false),
            originalName: "Old Installer.dmg",
            identity: FileIdentity(volumeUUID: nil, volumeDevice: "/dev/disk3s5", inode: 9),
            quarantinedPath: sandbox.store.appending(path: "\(id.uuidString)/Old Installer.dmg")
                .path(percentEncoded: false),
            storeRoot: sandbox.store.path(percentEncoded: false),
            mode: 0o644, ownerID: 501, groupID: 20, flags: 0,
            createdOn: Date(), modifiedOn: Date(), bytes: 10,
            isDirectory: false, isSymbolicLink: false, parentMode: 0o755,
            section: .storage, reason: "unused", wasInICloud: false)

        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        let report = Quarantine.reconcileOnOpening(home: sandbox.home)
        #expect(!report.isQuiet)
        let sentence = try #require(report.sentence)
        #expect(sentence.contains("Old Installer.dmg"), "name it; a bare count helps nobody")
        #expect(sentence.contains("Nothing was deleted."))
        #expect(!sentence.lowercased().contains("freed"))
    }
}
