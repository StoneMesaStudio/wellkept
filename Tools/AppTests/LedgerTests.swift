// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  LedgerTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The record IS the undo.** A quarantined file whose record is gone is a file nobody can put
//  back, while every screen in the app cheerfully reports an empty quarantine.
//
//  Two of these tests are regressions on bugs that were found in the shipped file on 2026-08-28:
//
//  1. **The truncate-in-place write.** A crash mid-write left half a JSON array, which decodes to
//     nothing. Fixed to `.atomic`; `theLedgerSurvivesAHalfWrittenFile` is what stops it coming back.
//  2. **`records()` returned `[]` for a permissions failure, a corrupt ledger and a fresh install
//     alike** — the app's own "never report zero because we could not look" rule, broken in the one
//     place where zero means somebody's files are unaccounted for.

private func sampleRecord(_ sandbox: QuarantineSandbox,
                          name: String = "Old Installer.dmg",
                          id: UUID = UUID(),
                          on date: Date = Date()) -> QuarantineRecord {
    QuarantineRecord(
        id: id,
        originalPath: sandbox.home.appending(path: "Downloads/\(name)").path(percentEncoded: false),
        originalName: name,
        identity: FileIdentity(volumeUUID: "AAAA-BBBB", volumeDevice: "/dev/disk3s5", inode: 4_242),
        quarantinedPath: sandbox.store.appending(path: "\(id.uuidString)/\(name)")
            .path(percentEncoded: false),
        storeRoot: sandbox.store.path(percentEncoded: false),
        mode: 0o644, ownerID: 501, groupID: 20, flags: 0,
        createdOn: date, modifiedOn: date, bytes: 1_234,
        isDirectory: false, isSymbolicLink: false, parentMode: 0o755,
        section: .storage, reason: "An installer you already used",
        quarantinedOn: date, wasInICloud: false)
}

// MARK: - ⭐ Empty is not the same as could-not-look

@Suite struct LedgerReadingTests {

    @Test func aFreshInstallReadsAsFreshRatherThanEmpty() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let reading = Ledger.read(home: sandbox.home)
        if case .fresh = reading {} else { Issue.record("a missing ledger must read as .fresh") }
        #expect(reading.isTrustworthy, "nothing set aside yet is a trustworthy zero")
    }

    @Test func anEmptyLedgerIsATrustworthyZero() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try Ledger.write([], home: sandbox.home)
        let reading = Ledger.read(home: sandbox.home)
        #expect(reading.records.isEmpty)
        #expect(reading.isTrustworthy)
        #expect(reading.trouble == nil)
    }

    /// ⚠️ **The regression.** The old code returned `[]` here, indistinguishable from an empty
    /// quarantine — so the app told somebody their files were not set aside while they sat in a
    /// folder with no record of where they came from.
    @Test func aCorruptLedgerIsLoudAndIsNeverAZero() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try FileManager.default.createDirectory(at: sandbox.ledger.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Exactly the shape a truncate-in-place crash leaves behind: half a JSON array.
        try Data("[{\"id\":\"9F2C".utf8).write(to: sandbox.ledger)

        let reading = Ledger.read(home: sandbox.home)
        #expect(!reading.isTrustworthy, "a damaged ledger must never read as trustworthy")
        let trouble = try #require(reading.trouble)
        #expect(trouble.kind == .corrupt)
        #expect(trouble.isLoud)
        #expect(trouble.sentence.contains("damaged"))
        #expect(trouble.sentence.contains("Nothing has been deleted"),
                "the first thing a frightened person needs to be told")
    }

    /// ⚠️ **The damaged ledger is copied aside, never deleted and never overwritten.** It is the only
    /// surviving statement about where somebody's files came from, and a person with a text editor
    /// can still read a partial JSON array.
    @Test func aCorruptLedgerIsKeptRatherThanThrownAway() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try FileManager.default.createDirectory(at: sandbox.ledger.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: sandbox.ledger)

        let trouble = try #require(Ledger.read(home: sandbox.home).trouble)
        #expect(sandbox.exists(sandbox.ledger), "the original is still there")
        let kept = try #require(trouble.keptAt)
        #expect(FileManager.default.fileExists(atPath: kept))
        let keptBytes = try Data(contentsOf: URL(filePath: kept))
        #expect(String(decoding: keptBytes, as: UTF8.self) == "not json at all")
    }

    /// Appending to a ledger that failed to decode would replace it with the new records alone —
    /// the same loss as deleting it, arrived at politely.
    @Test func nothingIsAppendedOverADamagedLedger() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try FileManager.default.createDirectory(at: sandbox.ledger.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("[".utf8).write(to: sandbox.ledger)

        let trouble = Ledger.append([sampleRecord(sandbox)], home: sandbox.home)
        #expect(trouble != nil, "the append must refuse and say so")
        let stillThere = String(decoding: try Data(contentsOf: sandbox.ledger), as: UTF8.self)
        #expect(stillThere == "[",
                "the damaged ledger was overwritten — that is the loss this guard exists to stop")
    }

    @Test func nothingIsRemovedFromADamagedLedgerEither() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try FileManager.default.createDirectory(at: sandbox.ledger.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("{".utf8).write(to: sandbox.ledger)

        #expect(Ledger.remove(ids: [UUID()], home: sandbox.home) != nil)
        let stillThere = String(decoding: try Data(contentsOf: sandbox.ledger), as: UTF8.self)
        #expect(stillThere == "{")
    }
}

// MARK: - ⭐ Atomic writing

@Suite struct LedgerWritingTests {

    /// ⚠️ **The bug that was already found here.** A plain `write(to:)` truncates in place: a badly
    /// timed crash leaves half a JSON array and orphans every quarantined file a person owns.
    /// `.atomic` writes a temporary beside the target and renames it into place, so the ledger on
    /// disk is only ever a whole one.
    @Test func theLedgerIsWrittenWholeOrNotAtAll() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let first = sampleRecord(sandbox, name: "one.dmg")
        try Ledger.write([first], home: sandbox.home)

        // A much larger write over the top. With a truncate-in-place there is a window where the
        // file on disk is neither of these; with `.atomic` there is not.
        let many = (0..<200).map { sampleRecord(sandbox, name: "file-\($0).dmg") }
        try Ledger.write(many, home: sandbox.home)

        let back = Ledger.read(home: sandbox.home)
        #expect(back.isTrustworthy)
        #expect(back.records.count == 200)
        #expect(!back.records.contains(first))
    }

    /// ⚠️ Dates come back to the **second**, not the microsecond: ISO-8601 without fractional
    /// seconds is what makes the file legible to a person with a text editor, and that is the trade
    /// deliberately made. Nothing in the engine needs finer than a second — the shortest interval it
    /// reasons about is thirty days.
    @Test func everyFieldSurvivesARoundTrip() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let whole = Date(timeIntervalSince1970: 1_780_000_000)   // no fractional part
        let record = sampleRecord(sandbox, on: whole)
        try Ledger.write([record], home: sandbox.home)
        let back = try #require(Ledger.read(home: sandbox.home).records.first)

        #expect(back == record, "a record that does not round-trip is a file that cannot go back")
        #expect(back.identity.inode == 4_242)
        #expect(back.parentMode == 0o755)
        #expect(back.section == .storage)
    }

    @Test func aDateComesBackToTheSecond() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let awkward = Date(timeIntervalSince1970: 1_780_000_000.987_654)
        try Ledger.write([sampleRecord(sandbox, on: awkward)], home: sandbox.home)
        let back = try #require(Ledger.read(home: sandbox.home).records.first)
        #expect(abs(back.quarantinedOn.timeIntervalSince(awkward)) < 1)
    }

    /// ⚠️ A ledger written by a later build, naming a section this one has never heard of, must still
    /// decode — otherwise one unknown word orphans every file in the list.
    @Test func anUnknownSectionDoesNotOrphanTheWholeLedger() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let record = sampleRecord(sandbox)
        try Ledger.write([record], home: sandbox.home)
        var text = String(decoding: try Data(contentsOf: sandbox.ledger), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"storage\"", with: "\"somethingNewer\"")
        try Data(text.utf8).write(to: sandbox.ledger)

        let back = Ledger.read(home: sandbox.home)
        #expect(back.isTrustworthy, "an unknown section must not make the ledger unreadable")
        #expect(back.records.count == 1)
        #expect(back.records.first?.section == nil, "and it must not be flattened into a wrong one")
        #expect(back.records.first?.originalName == "Old Installer.dmg")
    }

    /// A person with a text editor is the last line of defence, and they cannot read
    /// `775472043.19`.
    @Test func datesAreWrittenSoAPersonCanReadThem() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try Ledger.write([sampleRecord(sandbox)], home: sandbox.home)
        let text = String(decoding: try Data(contentsOf: sandbox.ledger), as: UTF8.self)
        #expect(text.contains("T") && text.contains("Z"), "ISO-8601, not a seconds count")
        #expect(text.contains("originalPath"), "and the keys say what they are")
    }

    @Test func appendingDoesNotDuplicateARecordThatIsAlreadyThere() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let record = sampleRecord(sandbox)
        #expect(Ledger.append([record], home: sandbox.home) == nil)
        #expect(Ledger.append([record], home: sandbox.home) == nil)
        #expect(Ledger.read(home: sandbox.home).records.count == 1)
    }

    /// A record whose file has gone is **kept**, not filtered out. It is the evidence that something
    /// took the file and the only thing that can say where it came from.
    @Test func aRecordWhoseFileIsGoneIsStillARecord() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try Ledger.write([sampleRecord(sandbox)], home: sandbox.home)
        #expect(Ledger.read(home: sandbox.home).records.count == 1,
                "dropping it would quietly shrink the list and tell nobody")
    }
}

// MARK: - ⭐ Crash states

@Suite struct LedgerReconcileTests {

    @Test func nothingInFlightMeansNothingToDo() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        #expect(Ledger.reconcile(home: sandbox.home).isEmpty)
    }

    /// The move ran and the crash came before the ledger. The record is added; the file is
    /// accounted for.
    @Test func aMoveThatFinishedButWasNotRecordedIsRecorded() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let id = UUID()
        let record = sampleRecord(sandbox, id: id)
        try sandbox.file("Library/Application Support/Wellkept/Quarantine/\(id.uuidString)/Old Installer.dmg")
        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        let results = Ledger.reconcile(home: sandbox.home)
        #expect(results.map(\.result) == [.finished])
        #expect(Ledger.read(home: sandbox.home).records.map(\.id) == [id])
        #expect(!sandbox.exists(sandbox.intent), "the intent is cleared once the ledger is right")
    }

    /// The crash came before the move. Nothing on the disk changed, so nothing is recorded.
    @Test func aMoveThatNeverRanLeavesNoRecordBehind() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let record = sampleRecord(sandbox)
        try sandbox.file("Downloads/Old Installer.dmg")
        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        #expect(Ledger.reconcile(home: sandbox.home).map(\.result) == [.nothingHappened])
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)
        #expect(!sandbox.exists(sandbox.intent))
    }

    /// ⚠️ The only state that loses information, and the only one Wellkept cannot cause. It is
    /// reported rather than swallowed.
    @Test func anItemAtNeitherPlaceIsReportedRatherThanForgotten() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(),
                                     records: [sampleRecord(sandbox)]),
                               home: sandbox.home)

        let results = Ledger.reconcile(home: sandbox.home)
        #expect(results.map(\.result) == [.unaccountedFor])
        let allTrouble = results.allSatisfy { $0.isTrouble }
        #expect(allTrouble)
    }

    /// A restore that finished takes the record out of the ledger.
    @Test func aRestoreThatFinishedRemovesTheRecord() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let record = sampleRecord(sandbox)
        try Ledger.write([record], home: sandbox.home)
        try sandbox.file("Downloads/Old Installer.dmg")
        try Ledger.writeIntent(.init(verb: .restore, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        #expect(Ledger.reconcile(home: sandbox.home).map(\.result) == [.finished])
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)
    }

    /// A restore that never ran leaves the record exactly where it was.
    @Test func aRestoreThatNeverRanKeepsTheRecord() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let id = UUID()
        let record = sampleRecord(sandbox, id: id)
        try Ledger.write([record], home: sandbox.home)
        try sandbox.file("Library/Application Support/Wellkept/Quarantine/\(id.uuidString)/Old Installer.dmg")
        try Ledger.writeIntent(.init(verb: .restore, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        #expect(Ledger.reconcile(home: sandbox.home).map(\.result) == [.nothingHappened])
        #expect(Ledger.read(home: sandbox.home).records.map(\.id) == [id])
    }
}

// MARK: - The ignore list

@Suite struct IgnoreListTests {

    @Test func aFreshInstallHasNothingIgnoredAndSaysSoHonestly() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let reading = IgnoreList.read(home: sandbox.home)
        #expect(reading.items.isEmpty)
        #expect(reading.isTrustworthy)
    }

    @Test func aDamagedIgnoreListIsLoudRatherThanEmpty() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try FileManager.default.createDirectory(
            at: StorageManifest.supportDirectory(home: sandbox.home),
            withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: StorageManifest.ignoreList(home: sandbox.home))

        #expect(!IgnoreList.read(home: sandbox.home).isTrustworthy)
    }

    /// Ignore is reversible. An irreversible "never mention this again" is a decision somebody makes
    /// once and regrets for the life of the machine.
    @Test func ignoringIsARoundTrip() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/noisy.pkg")
        #expect(Quarantine.ignore(file, section: .apps, finding: "No app claims it",
                                  home: sandbox.home) == nil)

        let items = IgnoreList.items(home: sandbox.home)
        #expect(items.count == 1)
        #expect(items[0].finding == "No app claims it")
        #expect(items[0].section == .apps)
        #expect(items[0].identity != nil, "the identity, not just the name")
        #expect(IgnoreList.isIgnored(file, home: sandbox.home))

        #expect(Quarantine.stopIgnoring(items[0].id, home: sandbox.home) == nil)
        #expect(!IgnoreList.isIgnored(file, home: sandbox.home))
    }

    /// Ignoring a folder ignores what is in it. Being shown its contents one at a time afterwards is
    /// not what anybody meant.
    @Test func ignoringAFolderCoversWhatIsInside() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let folder = try sandbox.folder("Projects")
        let inside = try sandbox.file("Projects/big.psd")
        #expect(Quarantine.ignore(folder, section: .storage, finding: "12 GB",
                                  home: sandbox.home) == nil)
        #expect(IgnoreList.isIgnored(inside, home: sandbox.home))
    }

    @Test func ignoringTheSameThingTwiceMakesOneEntry() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/noisy.pkg")
        _ = Quarantine.ignore(file, section: .apps, finding: "first", home: sandbox.home)
        _ = Quarantine.ignore(file, section: .apps, finding: "second", home: sandbox.home)
        #expect(IgnoreList.items(home: sandbox.home).count == 1)
    }
}

// MARK: - ⭐ An inode on its own is not an identity

//  Regression, 2026-08-28. `FileIdentity` compared the inode and nothing else, and `IgnoreList`
//  did the same. **Inode numbers are handed out per volume and they start small**, so a file made
//  a moment ago on a plugged-in drive routinely carries the same number as one in the home folder.
//  A bare inode comparison therefore says yes to the wrong file on the wrong disk — which is the
//  shape of every catastrophe on the list, reached by arithmetic rather than by name.
//
//  The fix has a second half that matters as much as the first: it prefers the volume **UUID** and
//  falls back to the device. Devices renumber across a reboot — `/dev/disk3s5` becomes
//  `/dev/disk4s5` when a drive is plugged in — and a strict device comparison would refuse to
//  restore somebody's files with "that is not the same file", stranding them for a reason that has
//  nothing to do with their file.

@Suite struct FileIdentityVolumeTests {

    private func realIdentity(of url: URL) throws -> FileIdentity {
        try #require(Movable.read(url).map(FileIdentity.init))
    }

    @Test func aFileIsItselfWhenTheInodeAndTheVolumeBothAgree() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg")
        let identity = try realIdentity(of: file)
        #expect(identity.stillDescribes(file.path(percentEncoded: false)))
    }

    /// ⚠️ The bug. Same inode number, different disk — and the old comparison said yes.
    @Test func aMatchingInodeOnAnotherVolumeIsNotTheSameFile() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg")
        let real = try realIdentity(of: file)
        let elsewhere = FileIdentity(volumeUUID: "FFFFFFFF-0000-0000-0000-000000000000",
                                     volumeDevice: "/dev/disk99s1",
                                     inode: real.inode)

        #expect(!elsewhere.stillDescribes(file.path(percentEncoded: false)),
                "the inode matched, so only the volume could tell these apart — and it must")
    }

    /// The same hole in the ignore list: one ignored download would have silenced a finding on a
    /// backup drive that happened to share its number.
    @Test func ignoringAFileDoesNotSilenceAnUnrelatedOneOnAnotherDisk() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/thing.dmg")
        let real = try realIdentity(of: file)

        let onAnotherDisk = IgnoredItem(
            path: "/Volumes/Backup/something else.dmg",
            identity: FileIdentity(volumeUUID: "FFFFFFFF-0000-0000-0000-000000000000",
                                   volumeDevice: "/dev/disk99s1", inode: real.inode),
            section: .storage, finding: "A big old file")

        #expect(!IgnoreList.contains(file, in: [onAnotherDisk]),
                "a shared inode number across two disks is a coincidence, not an identity")

        let itself = IgnoredItem(path: file.path(percentEncoded: false), identity: real,
                                 section: .storage, finding: "A big old file")
        #expect(IgnoreList.contains(file, in: [itself]), "and the real one still matches")
    }

    /// ⚠️ **Devices renumber; UUIDs do not.** A restore after a reboot must not be refused because
    /// the disk came back as a different `diskNsM`.
    @Test func theUUIDWinsOverTheDeviceBecauseDevicesRenumberAcrossAReboot() {
        let identity = FileIdentity(volumeUUID: "AAAA-BBBB", volumeDevice: "/dev/disk3s5",
                                    inode: 4_242)
        let afterAReboot = VolumeReading(mountPoint: "/System/Volumes/Data",
                                         device: "/dev/disk4s5", flags: 0, uuid: "AAAA-BBBB")
        #expect(identity.isOnTheSameVolume(as: afterAReboot))

        let genuinelyAnotherDisk = VolumeReading(mountPoint: "/Volumes/Backup",
                                                 device: "/dev/disk3s5", flags: 0, uuid: "CCCC-DDDD")
        #expect(!identity.isOnTheSameVolume(as: genuinelyAnotherDisk),
                "the device string matched by coincidence; the UUID is the one that counts")
    }

    /// A reading that could not be taken must not strand a restore. The inode has already agreed.
    @Test func aVolumeThatCouldNotBeReadIsNotTreatedAsADifferentDisk() {
        let identity = FileIdentity(volumeUUID: "AAAA-BBBB", volumeDevice: "/dev/disk3s5",
                                    inode: 4_242)
        #expect(identity.isOnTheSameVolume(as: nil))
    }

    /// Without a UUID on either side there is only the device, and it is better than nothing.
    @Test func theDeviceIsTheFallbackWhenNeitherSideHasAUUID() {
        let identity = FileIdentity(volumeUUID: nil, volumeDevice: "/dev/disk3s5", inode: 1)
        #expect(identity.isOnTheSameVolume(as: VolumeReading(mountPoint: "/", device: "/dev/disk3s5",
                                                             flags: 0, uuid: nil)))
        #expect(!identity.isOnTheSameVolume(as: VolumeReading(mountPoint: "/", device: "/dev/disk9s9",
                                                              flags: 0, uuid: nil)))
    }
}

// MARK: - ⭐ Reconciling something that was contained rather than moved

//  Regression, 2026-08-28. Containment moves nothing, so a contained record has the same path in
//  both fields and the five-state table does not apply to it. The branch that handled it ignored
//  the intent's verb and re-added the record whatever had happened — so a malware file that had
//  just been deleted came back as a ledger row pointing at nothing, for ever, that nothing in the
//  app could clear.

private func containedRecord(_ sandbox: QuarantineSandbox,
                             at url: URL,
                             id: UUID = UUID()) -> QuarantineRecord {
    let path = url.path(percentEncoded: false)
    return QuarantineRecord(
        id: id,
        originalPath: path,
        originalName: url.lastPathComponent,
        identity: FileIdentity(volumeUUID: nil, volumeDevice: "/dev/disk3s5", inode: 7),
        quarantinedPath: path,
        storeRoot: (path as NSString).deletingLastPathComponent,
        mode: 0o644, ownerID: 501, groupID: 20, flags: 0,
        createdOn: Date(), modifiedOn: Date(), bytes: 12,
        isDirectory: false, isSymbolicLink: false, parentMode: 0o755,
        sectionRaw: "security", reason: "macOS found malware here",
        quarantinedOn: Date(), wasInICloud: false,
        containment: Containment(modeBefore: 0o755, untrustedMarkBefore: nil,
                                 untrustedMarkNow: "0083;0;Wellkept;x", containedOn: Date()))
}

@Suite struct ContainedReconcileTests {

    /// ⚠️ The bug: the record was resurrected for a file that had just been removed.
    @Test func aContainedFileThatWasDeletedIsNotBroughtBackAsAGhostRow() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let gone = sandbox.home.appending(path: "Downloads/malware")
        let record = containedRecord(sandbox, at: gone)
        try Ledger.write([record], home: sandbox.home)
        try Ledger.writeIntent(.init(verb: .delete, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        #expect(Ledger.reconcile(home: sandbox.home).map(\.result) == [.finished])
        #expect(Ledger.read(home: sandbox.home).records.isEmpty,
                "the file is gone, so the row that points at it must go too")
    }

    /// The delete never ran. The file is still there and so is the record.
    @Test func aContainedFileThatIsStillThereKeepsItsRecord() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/malware")
        let record = containedRecord(sandbox, at: file)
        try Ledger.write([record], home: sandbox.home)
        try Ledger.writeIntent(.init(verb: .delete, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        #expect(Ledger.reconcile(home: sandbox.home).map(\.result) == [.nothingHappened])
        #expect(Ledger.read(home: sandbox.home).records.count == 1)
    }

    /// Containment that finished but was not written down gets written down.
    @Test func aContainmentThatWasNotRecordedIsRecorded() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/malware")
        let record = containedRecord(sandbox, at: file)
        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        #expect(Ledger.reconcile(home: sandbox.home).map(\.result) == [.finished])
        #expect(Ledger.read(home: sandbox.home).records.map(\.id) == [record.id])
    }

    /// Something else took the file while a release was in flight. Reported, never guessed at.
    @Test func aContainedFileThatSomethingElseTookIsReported() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let gone = sandbox.home.appending(path: "Downloads/malware")
        let record = containedRecord(sandbox, at: gone)
        try Ledger.write([record], home: sandbox.home)
        try Ledger.writeIntent(.init(verb: .restore, startedAt: Date(), records: [record]),
                               home: sandbox.home)

        #expect(Ledger.reconcile(home: sandbox.home).map(\.result) == [.unaccountedFor])
    }
}
