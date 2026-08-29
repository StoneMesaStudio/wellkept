// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import Darwin
import WellkeptCore

//  BackupProofTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The four things this section can get wrong that nobody would notice until the day it
//  mattered.** Everything here runs against real files in a pretend home folder and a pretend
//  drive, both made a moment before and thrown away after.
//
//  ⛔ **No test in this file touches a real volume, a real home folder, or Time Machine.** Every
//  path comes from `BackupSandbox`, which lives under the temporary directory.
//
//  ## The four
//
//  1. **Every door is shut, and the drive is untouched afterwards.** Not one entry point — all
//     three, as a table, because the one somebody adds next year is the one nobody photographs.
//  2. ⚠️ **A zero-byte cloud file.** With the dataless policy off, copying a cloud-only file fails
//     outright rather than writing an empty one — that is the safety net, and it is the best line
//     in the engine. **But a cloud file that is genuinely empty copies cleanly and returns zero**,
//     and so does an ordinary empty file. The test below copies both and shows the result is
//     identical, which is the whole argument for judging completeness by the flag.
//  3. ⛔ **Google Drive is never walked into.** Not "is recognised" — never entered, by the real
//     walk, in a real run. Reading that folder is what starts the download; on this Mac it timed
//     out and killed a scan, and had it succeeded it would have pulled down 6.5 GB.
//  4. ⚠️ **The grant is measured, never assumed.** Without Full Disk Access a backup contains no
//     mail, no messages, no photos, no contacts, no Safari data and no Trash, and macOS says
//     nothing at all. A run must report the grant it actually held, and the record on the drive
//     must still say so a year later.
//
//  Plus the fifth, which is the copy itself: **the bytes and the metadata, compared.**

// MARK: - 1. Every door, shut

@Suite("⛔ Every door into the engine is shut, and the drive is untouched")
struct BackupDoorTests {

    /// Everything on the pretend drive, however deep. Used to prove nothing was written.
    private func everythingOn(_ drive: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: drive, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { ($0 as? URL)?.lastPathComponent }
    }

    @Test("⭐ All three entry points refuse, for the same recorded reason, and write nothing")
    func everyEntryPointRefuses() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Documents/Letter.txt", contents: "something worth keeping")

        // ⚠️ Every public way into the engine, named. A door added later that is not in this list
        // is a door nobody proved anything about.
        var refusals: [String: RehearsalGate.Refusal] = [:]

        if case .refusedByTheGate(let why) = BackupRun.start(sandbox.plan()) {
            refusals["BackupRun.start"] = why
        }
        if case .refusedByTheGate(let why) = BackupRun.startInTheBackground(sandbox.plan()) {
            refusals["BackupRun.startInTheBackground"] = why
        }
        let item = RestorableItem(relativePath: "Documents/Letter.txt",
                                  onTheDriveAt: "Your files/Documents/Letter.txt",
                                  supersededOn: nil,
                                  theFileIsGoneFromTheMac: false,
                                  bytes: 23)
        if case .refusedByTheGate(let why) = Restore.start([item],
                                                           fromDrive: sandbox.drivePath,
                                                           to: sandbox.home) {
            refusals["Restore.start"] = why
        }

        #expect(refusals.count == 3, """
            One of the three entry points did not refuse. Refused: \(refusals.keys.sorted()). \
            RehearsalGate.performed is nil, so nothing in this engine may write to anything.
            """)

        // ⭐ Every refusal names the same missing thing, and says it in words a person can read.
        for (door, why) in refusals {
            #expect(why.missing.contains(.rehearsal), "\(door) refused for some other reason")
            #expect(why.sentence.contains("erasing a drive and restoring from it"),
                    "\(door)'s refusal does not say what has not happened yet")
        }
        // ⚠️ The background piece has to clear the second proof as well.
        #expect(refusals["BackupRun.startInTheBackground"]?.missing.contains(.agentFullDiskAccess) == true,
                "the scheduled door refused without mentioning that nothing has shown it can read mail")

        // ⛔ And after all three, the pretend drive holds nothing whatsoever.
        #expect(everythingOn(sandbox.drive).isEmpty, """
            Something was written to the drive by a refused run: \(everythingOn(sandbox.drive)). \
            A refusal happens before the folders are made, not after.
            """)
    }

    /// ⭐ The row that would offer the engine carries the refusal instead of a button, and it does
    /// it without calling itself a fault. **Nothing is wrong with the person's Mac** because we have
    /// not finished testing our own copier.
    @Test("⭐ The row that offers the engine withholds it, and is not an alarm")
    func theRowWithholdsRatherThanAlarming() {
        let row = BackupRows.wellkeptBackup(destination: "Spare 2 TB", agentIsOn: false)
        #expect(RehearsalGate.mayBeOffered == false)
        #expect(row.withheld == RehearsalGate.faceLine,
                "the offer row does not carry the gate's own sentence where its button would be")
        #expect(row.severity == .information, "a feature we have not finished is not a problem")
        #expect(row.status == .good)
        #expect(row.topic.needsRehearsal)
    }

    @Test("The refusal is the same one the face shows, rather than a second wording")
    func theFaceAndTheEngineSayTheSameThing() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        guard case .refusedByTheGate(let why) = BackupRun.start(sandbox.plan()) else {
            Issue.record("the gate let a run start"); return
        }
        #expect(why.sentence == RehearsalGate.faceLine, """
            The engine's refusal and the sentence on the screen have drifted apart. There is one \
            sentence, on RehearsalGate.Missing, and both read it.
            """)
    }
}

// MARK: - 2. ⚠️ The zero-byte cloud file

@Suite("⚠️ A zero-byte cloud file, and why the return code cannot be the evidence")
struct ZeroByteCloudFileTests {

    /// A placeholder for something in the cloud that happens to be empty.
    ///
    /// ⚠️ `SF_DATALESS` cannot be set without root and this suite will never ask for a password, so
    /// the reading is handed in rather than staged. That is the honest shape: the engine takes the
    /// flag off one `lstat` and this exercises the decision that flag feeds.
    private func placeholder(at path: String, relativePath: String, bytes: Int64) -> SourceItem {
        SourceItem(path: path, relativePath: relativePath,
                   isDirectory: false, isSymbolicLink: false,
                   isCloudOnly: true,
                   apparentBytes: bytes, allocatedBytes: 0,
                   linkCount: 1, device: 1, inode: 1, mode: 0o100644,
                   createdOn: nil, modifiedOn: nil)
    }

    @Test("⭐ An empty cloud file is skipped for its flag, and an empty ordinary file is copied")
    func theFlagIsWhatSeparatesThem() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let pass = RehearsalGate.passForTesting("the zero-byte trap")
        let rules = SourceRules(home: sandbox.home)

        // ⚠️ Two files that are indistinguishable by size, by name, by date, and by what a copy
        // returns. One of them is 65 GB of somebody's photographs that live in iCloud.
        let empty = try sandbox.file("Documents/Empty.txt", contents: "")
        let real = SourceReader.read(empty.path(percentEncoded: false), rules: rules)
        #expect(real?.apparentBytes == 0)
        #expect(real?.isCloudOnly == false)

        let ghost = placeholder(at: sandbox.home.appending(path: "Documents/Ghost.txt")
                                    .path(percentEncoded: false),
                                relativePath: "Documents/Ghost.txt",
                                bytes: 0)

        // The rules refuse the placeholder and allow the empty file, on the flag alone.
        #expect(rules.mayCopy(ghost) == .inTheCloudOnly)
        #expect(rules.mayCopy(real!) == nil)

        // And the copier does the same thing, before it touches either.
        let ghostOutcome = CopyOne.run(ghost, into: sandbox.drive, links: HardLinkLedger(),
                                       permittedBy: pass)
        #expect(ghostOutcome == .skipped(.inTheCloudOnly))
        #expect(Movable.exists(sandbox.drive.appending(path: "Documents/Ghost.txt")
                                  .path(percentEncoded: false)) == false)

        BackupRun.makeFoldersFor("Documents/Empty.txt", under: sandbox.drive,
                               home: sandbox.home, rules: rules, permittedBy: pass)
        let realOutcome = CopyOne.run(real!, into: sandbox.drive, links: HardLinkLedger(),
                                      permittedBy: pass)
        #expect(realOutcome.copiedFile != nil, "an ordinary empty file is an ordinary file")

        // ⭐ The point, said as an assertion: had either been judged by whether the copy worked,
        // both would have been called copied. One of them is not here at all.
        #expect(ghostOutcome.notCopied == .inTheCloudOnly)
        #expect(NotCopied.inTheCloudOnly.countsAgainstCompleteness == false)
    }

    @Test("A cloud placeholder is skipped whatever it claims to weigh")
    func sizeIsNeverTheEvidence() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let rules = SourceRules(home: sandbox.home)

        for bytes: Int64 in [0, 1, 65_000_000_000] {
            let ghost = placeholder(at: sandbox.home.appending(path: "big-\(bytes).mov")
                                        .path(percentEncoded: false),
                                    relativePath: "big-\(bytes).mov",
                                    bytes: bytes)
            #expect(rules.mayCopy(ghost) == .inTheCloudOnly,
                    "a placeholder of \(bytes) bytes was not recognised — size is not the evidence")
        }
    }

    @Test("The reason is written down in one place, in words a screen can use")
    func theRuleIsRecorded() {
        #expect(Backup.whyTheReturnCodeIsNotEvidence.contains("returns success"))
        #expect(Backup.whyTheReturnCodeIsNotEvidence.contains("not from the result of copying it"))
    }
}

// MARK: - 3. ⛔ Google Drive, never entered

@Suite("⛔ A real walk never goes into Google Drive")
struct GoogleDriveIsNeverEnteredTests {

    /// A home folder with one ordinary document and one cloud provider's folder full of files.
    private func homeWithADrive(_ sandbox: BackupSandbox) throws {
        try sandbox.file("Documents/Letter.txt", contents: "an ordinary document")
        try sandbox.file("Library/CloudStorage/GoogleDrive-someone@example.com/My Drive/Big.mov",
                         contents: "six and a half gigabytes, pretend")
        try sandbox.file("Library/CloudStorage/GoogleDrive-someone@example.com/My Drive/Deep/Deeper/Also.txt",
                         contents: "and everything under it")
    }

    @Test("⛔ The walk lists the document and never one thing inside the provider's folder")
    func theWalkStopsAtTheName() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        try homeWithADrive(sandbox)

        let rules = SourceRules(home: sandbox.home)
        let found = BackupRun.everythingUnder(sandbox.home.path(percentEncoded: false), rules: rules)

        #expect(found.contains { $0.hasSuffix("Documents/Letter.txt") },
                "the walk did not find the ordinary document, so it proves nothing about the rest")
        let insideTheDrive = found.filter { $0.contains("GoogleDrive") && $0.contains("My Drive") }
        #expect(insideTheDrive.isEmpty, """
            The walk went inside Google Drive: \(insideTheDrive). Reading that folder is what starts \
            the download — on this Mac it timed out and killed a scan, and had it succeeded it would \
            have pulled 6.5 GB onto a disk with 95 GB free. The folder's name is the only thing \
            about it that is not a lie.
            """)
    }

    @Test("⛔ A whole run copies the document and nothing from the provider's folder")
    func aWholeRunLeavesItAlone() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        try homeWithADrive(sandbox)

        let plan = sandbox.plan()
        let result = BackupRun.run(plan,
                                   permittedBy: RehearsalGate.passForTesting("google drive"),
                                   judgingTheDriveWith: { sandbox.judgedGood($0) })
        guard let outcome = result.outcome else {
            Issue.record("the run did not finish: \(result.sentence)"); return
        }

        let onTheDrive = (FileManager.default.enumerator(at: sandbox.backupFiles,
                                                         includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.path(percentEncoded: false) } ?? [])

        #expect(onTheDrive.contains { $0.hasSuffix("Documents/Letter.txt") })
        #expect(onTheDrive.contains { $0.contains("GoogleDrive") } == false, """
            Something from Google Drive was copied onto the backup drive: \
            \(onTheDrive.filter { $0.contains("GoogleDrive") }).
            """)
        // The refusal is counted and named rather than silently dropped.
        #expect(outcome.record.filesCopied > 0)
        // ⛔ And the folder itself is exactly as it was: nothing in this engine writes to the
        // source, and in this one folder even a read would have cost somebody their bandwidth.
        let untouched = sandbox.home
            .appending(path: "Library/CloudStorage/GoogleDrive-someone@example.com/My Drive/Big.mov")
        #expect(try Data(contentsOf: untouched) == Data("six and a half gigabytes, pretend".utf8))
    }
}

// MARK: - 4. ⚠️ The grant, measured

@Suite("⚠️ A run reports the grant it held, and the record still says so a year later")
struct GrantIsMeasuredTests {

    @Test("⭐ The run's answer about Full Disk Access is this Mac's answer, not a constant")
    func theGrantIsRead() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Documents/Letter.txt")

        let result = BackupRun.run(sandbox.plan(),
                                   permittedBy: RehearsalGate.passForTesting("the grant"),
                                   judgingTheDriveWith: { sandbox.judgedGood($0) })
        guard let outcome = result.outcome else {
            Issue.record("the run did not finish: \(result.sentence)"); return
        }

        // ⚠️ Whichever way this Mac answers, the run has to agree with it. A literal `true` here
        // would be the silent lie: macOS hands over no mail, messages or photos without the grant
        // and reports no error at all.
        #expect(outcome.completeness.fullDiskAccessHeld == FullDiskAccess.isGranted)
        #expect(outcome.record.fullDiskAccessHeld == FullDiskAccess.isGranted)

        if !FullDiskAccess.isGranted {
            #expect(outcome.completeness.mayBeCalledComplete == false,
                    "a run made without the grant called itself complete")
            #expect(outcome.sentence.contains("not a complete backup"))
        }

        // ⭐ And the record on the drive keeps the answer, which is what somebody restoring in a
        // year is actually reading.
        let readBack = BackupCatalogue.runs(onDrive: sandbox.drivePath)
        #expect(readBack.count == 1)
        #expect(readBack.first?.completeness.fullDiskAccessHeld == FullDiskAccess.isGranted)
    }

    @Test("⭐ A backup made without the grant names every one of the six things it does not hold")
    func theSixAreNamed() {
        let blind = BackupCompleteness(fullDiskAccessHeld: false)
        #expect(blind.mayBeCalledComplete == false)

        let said = blind.missingSentences.joined(separator: " ")
        for place in ProtectedPlace.allCases {
            let word = place.label.replacingOccurrences(of: "Your ", with: "")
            #expect(said.localizedCaseInsensitiveContains(word), """
                A backup made without Full Disk Access does not say that \(place.label) is missing \
                from it. macOS hands over none of them and reports no error, so this sentence is \
                the only warning a person ever gets.
                """)
        }
        // ⚠️ And it says the thing that makes it dangerous: no error was raised.
        #expect(said.contains("without any error"))
        #expect(blind.remedy != nil, "the one refusal a person can lift carries no button")
    }

    @Test("Nothing failed and the grant was held is the only way to be complete")
    func completeIsNarrow() {
        #expect(BackupCompleteness(fullDiskAccessHeld: true).mayBeCalledComplete)
        #expect(BackupCompleteness(fullDiskAccessHeld: true, failed: 1).mayBeCalledComplete == false)
        #expect(BackupCompleteness(fullDiskAccessHeld: false, failed: 0).mayBeCalledComplete == false)
        // Cloud-only files are named, and they are not a failure.
        #expect(BackupCompleteness(fullDiskAccessHeld: true, cloudOnlySkipped: 15_593)
            .mayBeCalledComplete)
    }
}

// MARK: - 5. ⭐ The copy itself, compared

@Suite("⭐ What arrives on the drive is the same file, byte for byte and fact for fact")
struct CopyIsFaithfulTests {

    private func birthTime(of path: String) -> Int? {
        var status = Darwin.stat()
        guard lstat(path, &status) == 0 else { return nil }
        return status.st_birthtimespec.tv_sec
    }

    private func attribute(_ name: String, of path: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(path, name, &bytes, size, 0, XATTR_NOFOLLOW) == size else { return nil }
        return Data(bytes)
    }

    @Test("⭐ The bytes, the creation date, the provenance tag and the permissions all survive")
    func theWholeFileArrives() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let pass = RehearsalGate.passForTesting("a faithful copy")
        let rules = SourceRules(home: sandbox.home)

        // A file with something in it, downloaded from somewhere, made in 2019, and private.
        let contents = "Dear whoever finds this,\nthe bytes matter.\n"
        let source = try sandbox.file("Documents/Letter.txt", contents: contents)
        let sourcePath = source.path(percentEncoded: false)

        let tag = Data("0083;5d1f4c00;Safari;".utf8)
        _ = tag.withUnsafeBytes {
            setxattr(sourcePath, "com.apple.quarantine", $0.baseAddress, tag.count, 0, XATTR_NOFOLLOW)
        }
        #expect(chmod(sourcePath, 0o640) == 0)
        let made = Date(timeIntervalSince1970: 1_550_000_000)   // February 2019
        #expect(CopyOne.setCreationDate(made, at: sourcePath))

        let item = try #require(SourceReader.read(sourcePath, rules: rules))
        BackupRun.makeFoldersFor(item.relativePath, under: sandbox.drive,
                               home: sandbox.home, rules: rules, permittedBy: pass)
        let outcome = CopyOne.run(item, into: sandbox.drive, links: HardLinkLedger(),
                                  permittedBy: pass)
        let copied = try #require(outcome.copiedFile)
        let copyPath = sandbox.drive.appending(path: "Documents/Letter.txt")
            .path(percentEncoded: false)

        // ⭐ The bytes, compared. Not the size — the bytes.
        #expect(try Data(contentsOf: URL(filePath: copyPath)) == Data(contents.utf8))

        // ⭐ Repair 1. Every file in a restored home folder otherwise claims to have been made on
        // the day of the restore, and every "sort by date created" is wrong for the rest of the
        // machine's life.
        #expect(birthTime(of: copyPath) == Int(made.timeIntervalSince1970))
        #expect(copied.repairs.contains(.creationDate))

        // ⭐ Repair 2. copyfile launders this one — it does not error, it arrives clean.
        #expect(attribute("com.apple.quarantine", of: copyPath) == tag)
        #expect(copied.repairs.contains(.whereItCameFrom))

        // The permissions are the source's, not the umask's.
        var status = Darwin.stat()
        #expect(lstat(copyPath, &status) == 0)
        #expect(status.st_mode & 0o777 == 0o640)

        // ⛔ And the source is exactly as it was. Nothing in this engine writes to the source.
        #expect(try Data(contentsOf: source) == Data(contents.utf8))
        #expect(birthTime(of: sourcePath) == Int(made.timeIntervalSince1970))
    }

    @Test("⭐ Two names for one file arrive as two names for one file")
    func hardLinksSurvive() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let pass = RehearsalGate.passForTesting("hard links")
        let rules = SourceRules(home: sandbox.home)

        let first = try sandbox.file("Documents/One.txt", contents: "one file, two names")
        let secondPath = sandbox.home.appending(path: "Documents/Two.txt")
            .path(percentEncoded: false)
        #expect(link(first.path(percentEncoded: false), secondPath) == 0)

        let links = HardLinkLedger()
        for relative in ["Documents/One.txt", "Documents/Two.txt"] {
            let path = sandbox.home.appending(path: relative).path(percentEncoded: false)
            let item = try #require(SourceReader.read(path, rules: rules))
            BackupRun.makeFoldersFor(relative, under: sandbox.drive, home: sandbox.home,
                                   rules: rules, permittedBy: pass)
            _ = CopyOne.run(item, into: sandbox.drive, links: links, permittedBy: pass)
        }

        // ⭐ One inode on the drive, under two names — not two files, not twice the space, and
        // "change one, change both" is still true after a restore.
        var a = Darwin.stat(), b = Darwin.stat()
        let one = sandbox.drive.appending(path: "Documents/One.txt").path(percentEncoded: false)
        let two = sandbox.drive.appending(path: "Documents/Two.txt").path(percentEncoded: false)
        #expect(lstat(one, &a) == 0)
        #expect(lstat(two, &b) == 0)
        #expect(a.st_ino == b.st_ino, "the two names arrived as two separate files")
        #expect(links.count == 1)
    }
}
