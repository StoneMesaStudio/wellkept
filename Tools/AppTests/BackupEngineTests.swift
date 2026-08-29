// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  BackupEngineTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The copier, exercised against real files — in a sandbox, never on this Mac.**
//
//  ⛔ **Nothing in this file touches a real drive, a real home folder, Time Machine, or any volume
//  this Mac owns.** Every test builds its own pretend home folder and its own pretend drive under
//  the temporary directory, and throws both away. The one exception is a handful of *read-only*
//  judgements about `/`, which run `statfs` and nothing else.
//
//  ⚠️ **The engine is not offered to anybody**, and the first suite below is the proof: with
//  `RehearsalGate.performed` still `nil`, every public entry point refuses. The rest of the tests
//  reach past that with the debug-only door, which is what it exists for — the engine has to be
//  exercised before the rehearsal is possible at all.

// MARK: - A pretend Mac and a pretend drive

/// A home folder and a drive, both made a moment ago and both thrown away at the end.
struct BackupSandbox {

    let home: URL
    let drive: URL

    private let fileManager = FileManager.default

    init() throws {
        // ⚠️ `realpath`, for the same reason `QuarantineSandbox` does it: `/var` is a symlink to
        // `/private/var`, and left unresolved every path here has a symbolic link in its parent
        // chain — which `AtomicMove`'s `RENAME_NOFOLLOW_ANY` refuses, correctly, proving nothing.
        let base = URL(filePath: Self.canonical(FileManager.default.temporaryDirectory
                                                    .path(percentEncoded: false)))
            .appending(path: "Wellkept-backup-tests")
            .appending(path: UUID().uuidString)
        home = base.appending(path: "home")
        drive = base.appending(path: "drive")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: drive, withIntermediateDirectories: true)
    }

    static func canonical(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return path }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func tearDown() {
        let base = home.deletingLastPathComponent()
        if let walker = fileManager.enumerator(at: base, includingPropertiesForKeys: nil) {
            for case let url as URL in walker { chflags(url.path(percentEncoded: false), 0) }
        }
        try? fileManager.removeItem(at: base)
    }

    @discardableResult
    func file(_ relative: String, contents: String = "the contents") throws -> URL {
        let url = home.appending(path: relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let url = home.appending(path: relative)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var drivePath: String { drive.path(percentEncoded: false) }
    var backupFiles: URL { BackupCatalogue.files(onDrive: drivePath) }

    /// A plan pointed at this sandbox.
    func plan(checkTo: VerificationLevel = .compared) -> BackupPlan {
        BackupPlan(home: home, driveMountPoint: drivePath, checkTo: checkTo)
    }

    /// ⚠️ A drive verdict that says yes, for the tests that need to get past the drive check.
    ///
    /// A temporary folder is not a volume of its own and is on the same disk as the home folder, so
    /// the real judgement refuses it — correctly, and it would refuse a real person's Desktop folder
    /// for the same two reasons. This stands in for a drive that passed.
    func judgedGood(_ plan: BackupPlan) -> DriveVerdict {
        DriveVerdict(path: plan.driveMountPoint,
                     refusals: [],
                     reading: DriveReading(name: "Pretend Drive",
                                           mountPoint: plan.driveMountPoint,
                                           device: "/dev/pretend",
                                           format: .apfs,
                                           isReadOnly: false,
                                           isNetwork: false,
                                           isTheSameDiskAsYourFiles: false,
                                           isTheStartupDisk: false,
                                           capacity: SizeOnDisk(1 << 40),
                                           free: SizeOnDisk(1 << 39),
                                           encryptedAtRest: true))
    }

    func reading(_ path: String) -> Darwin.stat? {
        var status = Darwin.stat()
        guard lstat(path, &status) == 0 else { return nil }
        return status
    }
}

// MARK: - ⛔ 1. The gate is shut, and it is shut on every door

@Suite("⛔ Nothing in the backup engine is offered until the rehearsal is walked")
struct BackupGateTests {

    @Test("⭐ The rehearsal has not been performed, so nothing may be offered")
    func theGateIsShut() {
        #expect(RehearsalGate.performed == nil)
        #expect(RehearsalGate.hasBeenRehearsed == false)
        #expect(RehearsalGate.mayBeOffered == false)
        #expect(RehearsalGate.agentIsProved == false)
    }

    @Test("⭐ Starting a backup refuses, and nothing is written")
    func startingABackupRefuses() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Documents/a.txt")

        let result = BackupRun.start(sandbox.plan())
        guard case .refusedByTheGate(let refusal) = result else {
            Issue.record("the gate let a backup start")
            return
        }
        #expect(refusal.missing == [.rehearsal])
        #expect(refusal.sentence.contains("erasing a drive and restoring from it"))

        // ⛔ And nothing at all was written to the pretend drive.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: sandbox.drivePath)) ?? []
        #expect(contents.isEmpty, "the refused run wrote \(contents) to the drive")
    }

    @Test("⭐ The background piece is refused twice over")
    func theBackgroundPieceIsRefusedForBothReasons() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        guard case .refusedByTheGate(let refusal) = BackupRun.startInTheBackground(sandbox.plan()) else {
            Issue.record("the gate let the background piece start")
            return
        }
        #expect(refusal.missing.contains(.rehearsal))
        #expect(refusal.missing.contains(.agentFullDiskAccess))
    }

    @Test("⭐ Restoring refuses too — a restore nobody has tested is not a restore")
    func restoringRefuses() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let answer = Restore.start([], fromDrive: sandbox.drivePath, to: sandbox.home)
        guard case .refusedByTheGate = answer else {
            Issue.record("the gate let a restore start")
            return
        }
    }

    @Test("⛔ A testing pass cannot write to a real drive")
    func theTestingDoorCannotReachARealDrive() {
        #expect(BackupCatalogue.isARealDrive("/"))
        #expect(BackupCatalogue.isARealDrive("/Volumes/Anything"))
        #expect(BackupCatalogue.isARealDrive("/private/tmp/x") == false)

        let pass = RehearsalGate.passForTesting("this test")
        let opened = BackupCatalogue.open(onDrive: "/Volumes/Not A Real Drive At All",
                                          permittedBy: pass)
        guard case .failure(.aTestingPassOnARealDrive) = opened else {
            Issue.record("a testing pass was allowed to write to /Volumes")
            return
        }
    }

    @Test("⛔ A testing pass cannot remove anything from a real drive either")
    func theTestingDoorCannotForgetOnARealDrive() {
        let version = KeptVersion(id: UUID(), relativePath: "a.txt",
                                  keptAt: "Previous versions/x/a.txt",
                                  supersededOn: Date(), runID: UUID(), bytes: 1,
                                  theFileIsGoneFromTheMac: false)
        let gone = BackupCatalogue.forget([version],
                                          onDrive: "/Volumes/Not A Real Drive At All",
                                          permittedBy: RehearsalGate.passForTesting("this test"))
        #expect(gone.isEmpty)
    }
}

// MARK: - ⭐ 2. The four things copyfile loses, put back

@Suite("⭐ The four repairs")
struct CopyRepairTests {

    private func pass() -> RehearsalGate.Pass {
        RehearsalGate.passForTesting("exercising the copier before the rehearsal")
    }

    @Test("⭐ Repair 1 — the creation date survives the copy")
    func theCreationDateSurvives() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let source = try sandbox.file("Documents/old.txt", contents: "hello")
        let longAgo = Date(timeIntervalSince1970: 1_000_000_000)   // 2001-09-09
        #expect(CopyOne.setCreationDate(longAgo, at: source.path(percentEncoded: false)))

        let rules = SourceRules(home: sandbox.home)
        let item = try #require(SourceReader.read(source.path(percentEncoded: false), rules: rules))
        let destination = sandbox.drive.appending(path: "out")
        try FileManager.default.createDirectory(at: destination.appending(path: "Documents"),
                                                withIntermediateDirectories: true)

        let outcome = CopyOne.run(item, into: destination, links: HardLinkLedger(), permittedBy: pass())
        let file = try #require(outcome.copiedFile)
        #expect(file.repairs.contains(.creationDate))

        let landed = destination.appending(path: "Documents/old.txt").path(percentEncoded: false)
        let born = try #require(CopyOne.creationDate(at: landed))
        #expect(abs(born.timeIntervalSince(longAgo)) < 2,
                "the copy claims to have been created on \(born) rather than \(longAgo)")
    }

    @Test("⭐ Repair 2 — where the file came from is carried, not laundered")
    func provenanceIsCarried() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let source = try sandbox.file("Downloads/installer.dmg", contents: "not really a disk image")
        let sourcePath = source.path(percentEncoded: false)

        // The attribute macOS writes when something comes off the internet.
        let tag = Data("0083;68b0c0de;Safari;".utf8)
        _ = tag.withUnsafeBytes {
            setxattr(sourcePath, "com.apple.quarantine", $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW)
        }
        try #require(CopyOne.attribute("com.apple.quarantine", of: sourcePath) != nil)

        let rules = SourceRules(home: sandbox.home)
        let item = try #require(SourceReader.read(sourcePath, rules: rules))
        let destination = sandbox.drive.appending(path: "out")
        try FileManager.default.createDirectory(at: destination.appending(path: "Downloads"),
                                                withIntermediateDirectories: true)

        let outcome = CopyOne.run(item, into: destination, links: HardLinkLedger(), permittedBy: pass())
        let file = try #require(outcome.copiedFile)
        #expect(file.repairs.contains(.whereItCameFrom))

        let landed = destination.appending(path: "Downloads/installer.dmg").path(percentEncoded: false)
        let carried = try #require(CopyOne.attribute("com.apple.quarantine", of: landed))
        #expect(carried == tag, "the download-provenance tag was laundered by the copy")
    }

    @Test("⭐ Repair 3 — a sparse file is not inflated")
    func sparsenessSurvives() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        // 64 MB that claims 64 MB and occupies almost nothing.
        let source = sandbox.home.appending(path: "sparse.bin")
        let path = source.path(percentEncoded: false)
        let descriptor = Darwin.open(path, O_CREAT | O_WRONLY, 0o644)
        try #require(descriptor >= 0)
        #expect(ftruncate(descriptor, 64 * 1024 * 1024) == 0)
        close(descriptor)

        let rules = SourceRules(home: sandbox.home)
        let item = try #require(SourceReader.read(path, rules: rules))
        try #require(item.isSparse, "the filesystem under the test did not make a sparse file")

        let destination = sandbox.drive.appending(path: "out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let outcome = CopyOne.run(item, into: destination, links: HardLinkLedger(), permittedBy: pass())
        let file = try #require(outcome.copiedFile)
        #expect(file.repairs.contains(.sparseness))

        let landed = try #require(sandbox.reading(destination.appending(path: "sparse.bin")
                                                      .path(percentEncoded: false)))
        // ⚠️ The measured failure was a 500 MB sparse file arriving as 500 MB of real blocks. A
        // copy that stayed sparse occupies a tiny fraction of what it claims.
        #expect(Int64(landed.st_blocks) * 512 < 8 * 1024 * 1024,
                "the copy inflated the sparse file to \(Int64(landed.st_blocks) * 512) bytes")
    }

    @Test("⭐ Repair 4 — two names for one file stay one file")
    func hardLinksSurvive() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let first = try sandbox.file("Projects/original.txt", contents: "shared contents")
        let second = sandbox.home.appending(path: "Projects/other name.txt")
        try FileManager.default.linkItem(at: first, to: second)

        let rules = SourceRules(home: sandbox.home)
        let destination = sandbox.drive.appending(path: "out")
        try FileManager.default.createDirectory(at: destination.appending(path: "Projects"),
                                                withIntermediateDirectories: true)
        let links = HardLinkLedger()

        let a = try #require(SourceReader.read(first.path(percentEncoded: false), rules: rules))
        let b = try #require(SourceReader.read(second.path(percentEncoded: false), rules: rules))
        #expect(a.isHardLinked && b.isHardLinked)

        let outA = CopyOne.run(a, into: destination, links: links, permittedBy: pass())
        let outB = CopyOne.run(b, into: destination, links: links, permittedBy: pass())

        let fileA = try #require(outA.copiedFile)
        let fileB = try #require(outB.copiedFile)
        #expect(fileA.wasLinked == false)
        #expect(fileB.wasLinked, "the second name was copied again instead of linked")
        #expect(fileB.repairs == [.hardLink])
        // ⚠️ Counted once. Counting both would report a backup larger than the drive it fits on.
        #expect(fileB.bytes == .zero)

        let landedA = try #require(sandbox.reading(destination.appending(path: "Projects/original.txt")
                                                       .path(percentEncoded: false)))
        let landedB = try #require(sandbox.reading(destination.appending(path: "Projects/other name.txt")
                                                       .path(percentEncoded: false)))
        #expect(landedA.st_ino == landedB.st_ino, "the two names arrived as two separate files")
    }

    @Test("⛔ A copy never writes over something already there")
    func aCopyNeverOverwrites() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let source = try sandbox.file("a.txt", contents: "the new one")
        let destination = sandbox.drive.appending(path: "out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("the older one, which must survive".utf8)
            .write(to: destination.appending(path: "a.txt"))

        let rules = SourceRules(home: sandbox.home)
        let item = try #require(SourceReader.read(source.path(percentEncoded: false), rules: rules))
        let outcome = CopyOne.run(item, into: destination, links: HardLinkLedger(), permittedBy: pass())

        guard case .failed(let failure) = outcome else {
            Issue.record("the copy wrote over an existing file")
            return
        }
        #expect(failure.code == EEXIST)
        let survived = try String(contentsOf: destination.appending(path: "a.txt"), encoding: .utf8)
        #expect(survived == "the older one, which must survive")
    }
}

// MARK: - ⚠️ 3. The flag, never the return code

@Suite("⚠️ Completeness is judged by the file flag, never the return code")
struct CloudOnlyTests {

    @Test("An ordinary file is not a cloud placeholder")
    func anOrdinaryFileIsHere() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let file = try sandbox.file("a.txt")
        #expect(SourceReader.isCloudOnly(file.path(percentEncoded: false)) == false)
    }

    @Test("⭐ A cloud-only item is skipped before it is ever touched")
    func aCloudOnlyItemIsSkipped() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        // ⚠️ `SF_DATALESS` cannot be set without root, and this suite will never ask for a password.
        // So the decision is exercised directly: an item carrying the flag is refused by the rules
        // and by the copier, and neither of them has to try the copy to find out.
        let placeholder = SourceItem(path: sandbox.home.appending(path: "big.mov")
                                        .path(percentEncoded: false),
                                     relativePath: "big.mov",
                                     isDirectory: false, isSymbolicLink: false,
                                     isCloudOnly: true,
                                     apparentBytes: 65_000_000_000, allocatedBytes: 0,
                                     linkCount: 1, device: 1, inode: 1, mode: 0o100644,
                                     createdOn: nil, modifiedOn: nil)

        let rules = SourceRules(home: sandbox.home)
        #expect(rules.mayCopy(placeholder) == .inTheCloudOnly)

        let outcome = CopyOne.run(placeholder,
                                  into: sandbox.drive,
                                  links: HardLinkLedger(),
                                  permittedBy: RehearsalGate.passForTesting("cloud-only"))
        #expect(outcome == .skipped(.inTheCloudOnly))
        #expect(Movable.exists(sandbox.drive.appending(path: "big.mov").path(percentEncoded: false)) == false)
    }

    @Test("⭐ Skipping a cloud file is not a failure, and it does not make a backup incomplete")
    func cloudOnlyIsNotAFailure() {
        #expect(NotCopied.inTheCloudOnly.countsAgainstCompleteness == false)
        #expect(NotCopied.failed.countsAgainstCompleteness)
        #expect(NotCopied.refusedSilently.countsAgainstCompleteness)

        let run = BackupCompleteness(fullDiskAccessHeld: true, cloudOnlySkipped: 15_593)
        #expect(run.mayBeCalledComplete)
        // ⚠️ And it is still said out loud, every run. Time Machine has the same hole and never
        // mentions it.
        #expect(run.missingSentences.contains { $0.contains("iCloud") })
    }

    @Test("⚠️ Without Full Disk Access a backup may not be called complete")
    func withoutTheGrantNothingIsComplete() {
        let blind = BackupCompleteness(fullDiskAccessHeld: false)
        #expect(blind.mayBeCalledComplete == false)
        #expect(blind.headline == "This is not a complete backup.")
        #expect(blind.missingSentences.first?.contains("Mail") == true)
        #expect(blind.remedy != nil)
    }
}

// MARK: - ⛔ 4. Google Drive, by name, because nothing else tells it apart

@Suite("⛔ A cloud provider's folder is refused by name")
struct CloudProviderTests {

    @Test("Google Drive's folder is recognised and refused")
    func googleDriveIsRefused() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let drive = try sandbox.folder("Library/CloudStorage/GoogleDrive-someone@example.com/My Drive")
        let rules = SourceRules(home: sandbox.home)

        #expect(rules.cloudProvider(of: drive) == "Google Drive")
        #expect(rules.mayDescend(into: drive) == .aCloudProviderFolder(provider: "Google Drive"))
    }

    @Test("The other providers are recognised too, and an ordinary folder is not")
    func theOtherProviders() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let rules = SourceRules(home: sandbox.home)

        for (folder, provider) in [("Dropbox", "Dropbox"), ("OneDrive-Personal", "OneDrive")] {
            let url = try sandbox.folder("Library/CloudStorage/\(folder)")
            #expect(rules.cloudProvider(of: url) == provider)
        }

        // ⚠️ A folder of the same name somewhere else is the person's own and is none of this
        // rule's business.
        let mine = try sandbox.folder("Documents/Dropbox")
        #expect(rules.cloudProvider(of: mine) == nil)
        #expect(rules.mayDescend(into: mine) == nil)
    }

    @Test("The reason a name is the evidence is written down where somebody will find it")
    func theReasonIsRecorded() {
        #expect(SourceRules.whyANameIsTheEvidenceHere.contains("only way to know"))
    }
}

// MARK: - 5. The drive, judged

@Suite("The drive is read and judged, and never written to")
struct DestinationTests {

    @Test("⭐ The startup disk is refused")
    func theStartupDiskIsRefused() {
        // Read-only: `statfs` on `/`, nothing else.
        let verdict = Destination.judge("/")
        #expect(verdict.mayBeUsed == false)
        #expect(verdict.refusals.contains(.theStartupDisk))
    }

    @Test("A folder that is not a drive of its own is refused, and says so")
    func aFolderIsNotADrive() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let verdict = Destination.judge(sandbox.drivePath, home: sandbox.home)
        #expect(verdict.mayBeUsed == false)
        #expect(verdict.refusals.contains { $0.code == "notADriveOfItsOwn" })
        #expect(verdict.refusals.contains { $0.code == "theSameDiskAsYourFiles" })
        // The drive was read and nothing was written to it.
        let contents = try FileManager.default.contentsOfDirectory(atPath: sandbox.drivePath)
        #expect(contents.isEmpty)
    }

    @Test("A drive that is not connected says so, rather than failing")
    func anUnpluggedDriveSaysSo() {
        let verdict = Destination.judge("/Volumes/A Drive That Is Not Plugged In")
        #expect(verdict.refusals == [.notConnected(name: "A Drive That Is Not Plugged In")])
        #expect(verdict.firstRefusal?.theUserCanFixThis == true)
    }

    @Test("⭐ The three format verdicts, and what each wrong one loses")
    func theFormatVerdicts() {
        #expect(DriveFormat.read(typeName: "apfs", isNetwork: false) == .apfs)
        #expect(DriveFormat.read(typeName: "hfs", isNetwork: false) == .hfsPlus)
        #expect(DriveFormat.read(typeName: "exfat", isNetwork: false) == .exFAT)
        #expect(DriveFormat.read(typeName: "smbfs", isNetwork: true) == .networkShare("smbfs"))
        // ⚠️ The network answer comes from the mount flag, not from the type name.
        #expect(DriveFormat.read(typeName: "apfs", isNetwork: true) == .networkShare("apfs"))

        #expect(DriveFormat.apfs.verdict == .right)
        #expect(DriveFormat.hfsPlus.verdict == .workable)
        #expect(DriveFormat.exFAT.verdict == .wrong)

        // ⚠️ A wrong format always says what is lost. "Unsupported" teaches a person nothing.
        for format in [DriveFormat.exFAT, .fat, .other("ntfs"), .networkShare("nfs")] {
            #expect(format.verdict.mayBeUsed == false)
            #expect(format.whatIsLost?.isEmpty == false, "\(format.name) does not say what it loses")
        }
        #expect(DriveFormat.apfs.whatIsLost == nil)
    }

    @Test("The one instruction carries the whole encryption story")
    func theInstructionIsTheEncryptionStory() {
        #expect(Destination.howToPrepareADrive.contains("APFS (Encrypted)"))
        #expect(Destination.howToPrepareADrive.contains("never sees the password"))
        #expect(Destination.whatWellkeptNeverDoes.contains("never erases"))
    }

    @Test("Encryption is read from diskutil's own output, and an unknown answer is not 'no'")
    func encryptionIsParsedNotGuessed() throws {
        func plist(_ pairs: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: pairs, format: .xml, options: 0)
        }
        #expect(EncryptionReading.encrypted(inPropertyList: try plist(["Encryption": true])) == true)
        #expect(EncryptionReading.encrypted(inPropertyList: try plist(["Encryption": false])) == false)
        #expect(EncryptionReading.encrypted(
            inPropertyList: try plist(["FilesystemUserVisibleName": "APFS (Encrypted)"])) == true)
        // ⚠️ Nothing to go on is `nil` — reported as not established, never as "no".
        #expect(EncryptionReading.encrypted(inPropertyList: try plist(["VolumeName": "Backup"])) == nil)
        #expect(EncryptionReading.encrypted(inPropertyList: Data("not a plist".utf8)) == nil)
    }
}

// MARK: - ⭐ 6. The three levels, and the one word

@Suite("⭐ The strongest word is never used without reading the bytes back")
struct VerificationTests {

    @Test("Each level uses its own word, and only one of them is the strong one")
    func theWords() {
        #expect(VerificationLevel.counted.word == "counted")
        #expect(VerificationLevel.compared.word == "checked")
        #expect(VerificationLevel.readBack.word == "verified")

        #expect(VerificationLevel.counted.mayUseTheWordVerified == false)
        #expect(VerificationLevel.compared.mayUseTheWordVerified == false)
        #expect(VerificationLevel.readBack.mayUseTheWordVerified)

        // ⚠️ And the two weaker levels say what they did not do.
        #expect(VerificationLevel.counted.whatItDoesNotProve != nil)
        #expect(VerificationLevel.compared.whatItDoesNotProve != nil)
        #expect(VerificationLevel.readBack.whatItDoesNotProve == nil)
    }

    @Test("⭐ A report below the top level never claims the strong word")
    func theWeakerLevelsNeverClaimIt() {
        let forbidden = VerificationLevel.readBack.word
        for level in [VerificationLevel.counted, .compared] {
            let report = VerificationReport(level: level, checked: 10, inTheBackup: 10,
                                            failures: [], cloudOnly: 0)
            #expect(report.sentence.lowercased().contains(forbidden) == false,
                    "a \(level.rawValue) report overclaimed: \(report.sentence)")
            for line in report.linesUnderneath {
                #expect(line.lowercased().contains(forbidden) == false)
            }
        }
    }

    @Test("⭐ A sample carries both numbers rather than the bare word")
    func aSampleCarriesBothNumbers() {
        let sample = VerificationReport(level: .readBack, checked: 500, inTheBackup: 586_642,
                                        failures: [], cloudOnly: 0)
        #expect(sample.wasASample)
        #expect(sample.sentence.contains("500"))
        #expect(sample.sentence.contains("586,642"))
        #expect(sample.sentence.contains("chosen at random"))

        let whole = VerificationReport(level: .readBack, checked: 12, inTheBackup: 12,
                                       failures: [], cloudOnly: 0)
        #expect(whole.wasASample == false)
        #expect(whole.sentence.contains("all 12 files"))
    }

    @Test("⭐ The levels are genuinely different: a corrupted copy passes the middle one and fails the top one")
    func theLevelsAreNotDecorative() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let source = try sandbox.file("a.txt", contents: "AAAAAAAAAA")
        let copy = sandbox.drive.appending(path: "a.txt")
        try Data("BBBBBBBBBB".utf8).write(to: copy)   // same length, different bytes

        let sourcePath = source.path(percentEncoded: false)
        let copyPath = copy.path(percentEncoded: false)

        // Make the metadata agree, which is exactly what a silently-corrupted copy looks like.
        var status = Darwin.stat()
        try #require(lstat(sourcePath, &status) == 0)
        var times = [timeval(tv_sec: status.st_mtimespec.tv_sec, tv_usec: 0),
                     timeval(tv_sec: status.st_mtimespec.tv_sec, tv_usec: 0)]
        #expect(utimes(copyPath, &times) == 0)
        #expect(CopyOne.setCreationDate(Date(timeIntervalSince1970:
            TimeInterval(status.st_birthtimespec.tv_sec)), at: copyPath))

        #expect(Verify.check(sourcePath: sourcePath, backupPath: copyPath,
                             relativePath: "a.txt", level: .counted).matched)
        #expect(Verify.check(sourcePath: sourcePath, backupPath: copyPath,
                             relativePath: "a.txt", level: .compared).matched,
                "the metadata was made to agree, so the middle level is supposed to pass — that is the point")

        let readBack = Verify.check(sourcePath: sourcePath, backupPath: copyPath,
                                    relativePath: "a.txt", level: .readBack)
        #expect(readBack.matched == false, "reading the bytes back did not catch a corrupted copy")
        #expect(readBack.why?.contains("contents") == true)
    }

    @Test("A missing copy fails at every level")
    func aMissingCopyFailsEverywhere() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let source = try sandbox.file("a.txt")

        for level in VerificationLevel.allCases {
            let result = Verify.check(sourcePath: source.path(percentEncoded: false),
                                      backupPath: sandbox.drive.appending(path: "nothing").path(percentEncoded: false),
                                      relativePath: "a.txt", level: level)
            #expect(result.isFailure)
            #expect(result.why == "it is not on the drive")
        }
    }

    @Test("A failure is stated before anything about how thorough the check was")
    func aFailureLeads() {
        let bad = FileCheck(relativePath: "a.txt", level: .readBack, matched: false,
                            why: "the contents differ", sourceIsInTheCloud: false)
        let report = VerificationReport(level: .readBack, checked: 100, inTheBackup: 100,
                                        failures: [bad], cloudOnly: 0)
        #expect(report.allMatched == false)
        #expect(report.sentence.hasPrefix("1 file"))
        #expect(report.sentence.contains("not a copy you can rely on"))
    }
}

// MARK: - 7. The journal, and the four ways it lies

@Suite("The change journal, and when it is thrown away")
struct ChangeJournalTests {

    @Test("No earlier run means look at everything, and it is not a problem")
    func aFirstRunLooksAtEverything() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let replay = ChangeJournal.changes(since: nil, under: sandbox.home)
        #expect(replay.doubt == .thereIsNoEarlierRun)
        #expect(replay.places == nil)
        #expect(replay.doubt?.isAProblem == false)
    }

    @Test("⭐ A mark from a different drive is thrown away rather than trusted")
    func aMarkFromAnotherDriveIsUseless() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let wrong = JournalMark(eventID: 42, volumeUUID: "00000000-0000-0000-0000-000000000000")
        let replay = ChangeJournal.changes(since: wrong, under: sandbox.home)
        #expect(replay.doubt == .theMarkIsForADifferentDrive)
    }

    @Test("A mark with no volume addresses nothing")
    func aMarkWithNoVolumeIsUnusable() {
        let mark = JournalMark(eventID: 7, volumeUUID: nil)
        #expect(mark.addresses(volumeUUID: "anything") == false)
        #expect(JournalMark(eventID: 7, volumeUUID: "A").addresses(volumeUUID: nil) == false)
        #expect(JournalMark(eventID: 7, volumeUUID: "A").addresses(volumeUUID: "A"))
    }

    @Test("Every doubt carries a plain sentence, and none of them is a problem")
    func everyDoubtSaysSomething() {
        for doubt in JournalDoubt.allCases {
            #expect(doubt.sentence.contains("looked at everything"))
            #expect(doubt.isAProblem == false)
        }
    }

    @Test("A replay always carries the mark the next run starts from")
    func theMarkIsAlwaysCarried() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let replay = ChangeJournal.changes(since: nil, under: sandbox.home)
        #expect(replay.mark.eventID > 0)
    }
}

// MARK: - 8. The record on the drive

@Suite("The record on the drive is appended, readable, and never rewritten")
struct BackupCatalogueTests {

    private func pass() -> RehearsalGate.Pass {
        RehearsalGate.passForTesting("exercising the catalogue before the rehearsal")
    }

    @Test("Opening makes the three folders and the note that explains them")
    func openingMakesTheFolders() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        guard case .success = BackupCatalogue.open(onDrive: sandbox.drivePath, permittedBy: pass()) else {
            Issue.record("the backup folder could not be made")
            return
        }
        #expect(Movable.exists(BackupCatalogue.files(onDrive: sandbox.drivePath).path(percentEncoded: false)))
        #expect(Movable.exists(BackupCatalogue.versions(onDrive: sandbox.drivePath).path(percentEncoded: false)))

        let note = BackupCatalogue.root(onDrive: sandbox.drivePath)
            .appending(path: BackupCatalogue.readMeFileName)
        let text = try String(contentsOf: note, encoding: .utf8)
        #expect(text.contains("ordinary files in ordinary folders"))
        // ⛔ The promise we do not make is not in it.
        #expect(text.lowercased().contains(Backup.promiseWeDoNotMake) == false)
    }

    @Test("⭐ Lines are appended, and an earlier line survives a torn later one")
    func appendingIsAppendOnly() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        _ = BackupCatalogue.open(onDrive: sandbox.drivePath, permittedBy: pass())

        let first = BackupRunRecord(id: UUID(), startedOn: Date(), finishedOn: Date(),
                                    filesCopied: 3, bytesCopied: 300, cloudOnlySkipped: 1,
                                    failed: 0, fullDiskAccessHeld: true, checkedTo: "compared",
                                    mark: nil, lookedAtEverythingBecause: nil,
                                    macOSVersion: "26.6.2", driveName: "Pretend")
        #expect(BackupCatalogue.append(.run(first), onDrive: sandbox.drivePath, permittedBy: pass()) == nil)
        #expect(BackupCatalogue.runs(onDrive: sandbox.drivePath).count == 1)

        // A torn line, exactly as an interrupted write would leave it.
        let record = BackupCatalogue.record(onDrive: sandbox.drivePath)
        let handle = try FileHandle(forWritingTo: record)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"kind\":\"ru".utf8))
        try handle.close()

        // ⚠️ The earlier line is untouched, which is the whole reason this is not a rewrite.
        #expect(BackupCatalogue.runs(onDrive: sandbox.drivePath).count == 1)
        #expect(BackupCatalogue.runs(onDrive: sandbox.drivePath).first?.filesCopied == 3)

        // And a later append still lands.
        let second = BackupRunRecord(id: UUID(), startedOn: Date(), finishedOn: Date().addingTimeInterval(60),
                                     filesCopied: 9, bytesCopied: 900, cloudOnlySkipped: 0,
                                     failed: 0, fullDiskAccessHeld: true, checkedTo: "readBack",
                                     mark: nil, lookedAtEverythingBecause: nil,
                                     macOSVersion: "26.6.2", driveName: "Pretend")
        #expect(BackupCatalogue.append(.run(second), onDrive: sandbox.drivePath, permittedBy: pass()) == nil)
        #expect(BackupCatalogue.runs(onDrive: sandbox.drivePath).count == 2)
        // Newest first.
        #expect(BackupCatalogue.runs(onDrive: sandbox.drivePath).first?.filesCopied == 9)
    }

    @Test("A run written without the grant may never be called complete, a year later")
    func theRecordRemembersTheGrant() {
        let blind = BackupRunRecord(id: UUID(), startedOn: Date(), finishedOn: Date(),
                                    filesCopied: 500_000, bytesCopied: 400_000_000_000,
                                    cloudOnlySkipped: 0, failed: 0,
                                    fullDiskAccessHeld: false, checkedTo: "readBack",
                                    mark: nil, lookedAtEverythingBecause: nil,
                                    macOSVersion: "26.6.2", driveName: "Pretend")
        #expect(blind.completeness.mayBeCalledComplete == false)
    }

    @Test("The dates in the record are readable by a person with a text editor")
    func theRecordIsReadableWithoutUs() throws {
        let line = CatalogueLine.version(KeptVersion(id: UUID(), relativePath: "a.txt",
                                                     keptAt: "Previous versions/x/a.txt",
                                                     supersededOn: Date(timeIntervalSince1970: 1_756_000_000),
                                                     runID: UUID(), bytes: 12,
                                                     theFileIsGoneFromTheMac: true))
        let data = try BackupCatalogue.encoder().encode(line)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("2025-"))
        #expect(text.contains("1756000000") == false, "the date was written as a raw number")
    }
}

// MARK: - ⛔ 9. Retention proposes; it never deletes

@Suite("⛔ Nothing falls off the drive by surprise")
struct RetentionTests {

    private func version(daysAgo: Int, bytes: Int64 = 1_000_000) -> KeptVersion {
        KeptVersion(id: UUID(), relativePath: "Documents/a.txt",
                    keptAt: "Previous versions/x/Documents/a.txt",
                    supersededOn: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                    runID: UUID(), bytes: bytes, theFileIsGoneFromTheMac: false)
    }

    @Test("Anything younger than the rule is never offered for removal")
    func youngCopiesAreNeverOffered() {
        let proposal = Retention.standard.proposal([version(daysAgo: 10), version(daysAgo: 89)])
        #expect(proposal.isEmpty)
        #expect(proposal.sentence.contains("Nothing on the drive is older"))
    }

    @Test("⭐ What has aged out is a proposal, in the conditional, with the figure")
    func agedOutIsAProposal() {
        let proposal = Retention.standard.proposal([version(daysAgo: 200), version(daysAgo: 400),
                                                    version(daysAgo: 3)])
        #expect(proposal.versions.count == 2)
        #expect(proposal.wouldGiveBack.bytes == 2_000_000)
        #expect(proposal.sentence.contains("Removing"))
        #expect(proposal.sentence.contains("Nothing is removed until you say so"))
    }

    @Test("The rule says out loud that nothing is removed on its own")
    func theRuleSaysSo() {
        #expect(Retention.standard.keepEverythingForDays == 90)
        #expect(Retention.standard.sentence.contains("never removes anything from your drive on its own"))
    }

    @Test("⛔ Forgetting refuses anything that is not inside 'Previous versions'")
    func forgettingCannotReachTheCurrentCopy() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let pass = RehearsalGate.passForTesting("retention")
        _ = BackupCatalogue.open(onDrive: sandbox.drivePath, permittedBy: pass)

        // A current file, which must survive whatever a mangled record says.
        let current = BackupCatalogue.files(onDrive: sandbox.drivePath).appending(path: "a.txt")
        try Data("the only copy".utf8).write(to: current)

        let mangled = KeptVersion(id: UUID(), relativePath: "a.txt",
                                  keptAt: "\(BackupCatalogue.filesFolderName)/a.txt",
                                  supersededOn: Date(), runID: UUID(), bytes: 1,
                                  theFileIsGoneFromTheMac: false)
        let gone = BackupCatalogue.forget([mangled], onDrive: sandbox.drivePath, permittedBy: pass)
        #expect(gone.isEmpty)
        #expect(Movable.exists(current.path(percentEncoded: false)),
                "retention reached into the current copy of somebody's file")
    }

    @Test("Forgetting a real old copy removes it and says which")
    func forgettingWorksOnWhatItIsGiven() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let pass = RehearsalGate.passForTesting("retention")
        _ = BackupCatalogue.open(onDrive: sandbox.drivePath, permittedBy: pass)

        let old = BackupCatalogue.versions(onDrive: sandbox.drivePath)
            .appending(path: "2026-01-01 09-00/a.txt")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("last year's".utf8).write(to: old)

        let version = KeptVersion(id: UUID(), relativePath: "a.txt",
                                  keptAt: "\(BackupCatalogue.versionsFolderName)/2026-01-01 09-00/a.txt",
                                  supersededOn: Date(), runID: UUID(), bytes: 11,
                                  theFileIsGoneFromTheMac: false)
        let gone = BackupCatalogue.forget([version], onDrive: sandbox.drivePath, permittedBy: pass)
        #expect(gone.count == 1)
        #expect(Movable.exists(old.path(percentEncoded: false)) == false)
    }
}

// MARK: - ⭐ 10. A whole run, end to end

@Suite("⭐ A whole backup, into a pretend drive")
struct WholeRunTests {

    private func pass() -> RehearsalGate.Pass {
        RehearsalGate.passForTesting("exercising the engine before the rehearsal")
    }

    @Test("⭐ The files arrive, the record is written, and the check runs")
    func aRunCopiesEverything() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        try sandbox.file("Documents/one.txt", contents: "one")
        try sandbox.file("Documents/Notes/two.md", contents: "two")
        try sandbox.file("Pictures/three.jpg", contents: "three")

        let plan = sandbox.plan(checkTo: .readBack)
        let result = BackupRun.run(plan, permittedBy: pass(),
                                   judgingTheDriveWith: sandbox.judgedGood)
        let outcome = try #require(result.outcome, "the run did not finish: \(result.sentence)")

        for relative in ["Documents/one.txt", "Documents/Notes/two.md", "Pictures/three.jpg"] {
            let landed = sandbox.backupFiles.appending(path: relative)
            #expect(Movable.exists(landed.path(percentEncoded: false)), "\(relative) is not on the drive")
            #expect(try String(contentsOf: landed, encoding: .utf8).isEmpty == false)
        }

        #expect(outcome.record.filesCopied >= 3)
        #expect(outcome.failures.isEmpty, "\(outcome.failures.map(\.sentence))")
        #expect(outcome.check?.allMatched == true)
        #expect(outcome.check?.level == .readBack)
        #expect(BackupCatalogue.runs(onDrive: sandbox.drivePath).count == 1)

        // ⭐ The grant is recorded as it actually was on the machine running this suite, never
        // assumed. That is the fact the whole completeness answer hangs on.
        #expect(outcome.record.fullDiskAccessHeld == FullDiskAccess.isGranted)
    }

    @Test("⭐ A second run over the same drive keeps the old copy rather than writing over it")
    func aSecondRunKeepsThePreviousVersion() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Documents/report.txt", contents: "the first draft")
        _ = BackupRun.run(sandbox.plan(), permittedBy: pass(), judgingTheDriveWith: sandbox.judgedGood)

        // Change it, and make sure the modification time really moved.
        try Data("the second draft, which is longer".utf8).write(to: file)
        var times = [timeval(tv_sec: Int(Date().timeIntervalSince1970) + 5, tv_usec: 0),
                     timeval(tv_sec: Int(Date().timeIntervalSince1970) + 5, tv_usec: 0)]
        #expect(utimes(file.path(percentEncoded: false), &times) == 0)

        let second = BackupRun.run(sandbox.plan(), permittedBy: pass(),
                                   judgingTheDriveWith: sandbox.judgedGood)
        let outcome = try #require(second.outcome, Comment(rawValue: second.sentence))

        // The current copy is the new one.
        let current = sandbox.backupFiles.appending(path: "Documents/report.txt")
        #expect(try String(contentsOf: current, encoding: .utf8) == "the second draft, which is longer")

        // ⭐ And the old one is on the drive, not gone.
        let kept = try #require(outcome.keptVersions.first { $0.relativePath == "Documents/report.txt" })
        let old = BackupCatalogue.root(onDrive: sandbox.drivePath).appending(path: kept.keptAt)
        #expect(try String(contentsOf: old, encoding: .utf8) == "the first draft")
    }

    @Test("An unchanged file is not copied a second time")
    func nothingIsCopiedTwice() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Documents/steady.txt", contents: "unchanged")

        _ = BackupRun.run(sandbox.plan(), permittedBy: pass(), judgingTheDriveWith: sandbox.judgedGood)
        let second = BackupRun.run(sandbox.plan(), permittedBy: pass(),
                                   judgingTheDriveWith: sandbox.judgedGood)
        let outcome = try #require(second.outcome, Comment(rawValue: second.sentence))
        #expect(outcome.keptVersions.isEmpty)
        #expect(outcome.record.filesCopied == 0)
    }

    @Test("A drive that is refused stops the run before anything is written")
    func aRefusedDriveWritesNothing() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("a.txt")

        let result = BackupRun.run(sandbox.plan(), permittedBy: pass())   // the real judgement
        guard case .theDriveWasNotUsable(let reasons) = result else {
            Issue.record("a folder that is not a drive was accepted")
            return
        }
        #expect(reasons.isEmpty == false)
        let contents = try FileManager.default.contentsOfDirectory(atPath: sandbox.drivePath)
        #expect(contents.isEmpty)
    }

    @Test("The walk stops where the rules say, and finds what they allow")
    func theWalkObeysTheRules() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }

        try sandbox.file("Documents/keep.txt")
        try sandbox.file("Library/CloudStorage/GoogleDrive-x@y.z/My Drive/huge.mov")
        try sandbox.file("Secret/leave.txt")

        let rules = SourceRules(home: sandbox.home, excludedByTheUser: ["Secret"])
        let found = BackupRun.everythingUnder(sandbox.home.path(percentEncoded: false), rules: rules)

        #expect(found.contains { $0.hasSuffix("Documents/keep.txt") })
        // ⛔ The walk never went inside Google Drive's folder.
        #expect(found.contains { $0.hasSuffix("huge.mov") } == false)
        // The person's own exclusion stopped the descent.
        #expect(found.contains { $0.hasSuffix("Secret/leave.txt") } == false)
    }

    @Test("Progress says where it is, never how long it will take")
    func progressSaysWhereNotWhen() {
        let progress = BackupProgress(place: "Documents", done: 12, failed: 0)
        #expect(progress.sentence == "Copying Documents")
        #expect(BackupProgress.whyThereIsNoEstimate.contains("guess"))
    }
}

// MARK: - ⭐ 11. Getting things back

@Suite("⭐ Restoring: by name, by day, and never over the top of something")
struct RestoreTests {

    private func pass() -> RehearsalGate.Pass {
        RehearsalGate.passForTesting("exercising the restore before the rehearsal")
    }

    /// A drive with one file backed up twice, so there is a current copy and an older one.
    private func driveWithTwoVersions(_ sandbox: BackupSandbox) throws -> BackupOutcome {
        let file = try sandbox.file("Documents/report.txt", contents: "the first draft")
        _ = BackupRun.run(sandbox.plan(), permittedBy: pass(), judgingTheDriveWith: sandbox.judgedGood)
        try Data("the second draft".utf8).write(to: file)
        var times = [timeval(tv_sec: Int(Date().timeIntervalSince1970) + 5, tv_usec: 0),
                     timeval(tv_sec: Int(Date().timeIntervalSince1970) + 5, tv_usec: 0)]
        _ = utimes(file.path(percentEncoded: false), &times)
        let second = BackupRun.run(sandbox.plan(), permittedBy: pass(),
                                   judgingTheDriveWith: sandbox.judgedGood)
        return try #require(second.outcome, Comment(rawValue: second.sentence))
    }

    @Test("Search finds both copies, current first, each with its date")
    func searchFindsEveryCopy() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        _ = try driveWithTwoVersions(sandbox)

        let everything = RestoreCatalogue.everything(onDrive: sandbox.drivePath)
        let found = RestoreCatalogue.search("report", in: everything)
        #expect(found.count == 2)
        #expect(found[0].isTheCurrentCopy)
        #expect(found[1].supersededOn != nil)
        #expect(found[1].sentence.contains("as it was until"))

        #expect(RestoreCatalogue.search("nothing like this", in: everything).isEmpty)
        #expect(RestoreCatalogue.search("  ", in: everything).isEmpty)
    }

    @Test("⭐ Point in time picks the copy that was current on the day")
    func pointInTimePicksTheRightCopy() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let outcome = try driveWithTwoVersions(sandbox)
        let superseded = try #require(outcome.keptVersions.first).supersededOn

        let everything = RestoreCatalogue.everything(onDrive: sandbox.drivePath)
        let before = RestoreCatalogue.versionAsOf(superseded.addingTimeInterval(-60),
                                                  of: "Documents/report.txt", in: everything)
        #expect(before?.isTheCurrentCopy == false, "asking for yesterday returned today's copy")

        let after = RestoreCatalogue.versionAsOf(superseded.addingTimeInterval(60),
                                                 of: "Documents/report.txt", in: everything)
        #expect(after?.isTheCurrentCopy == true)
    }

    @Test("⭐ A restore puts the file back, with its bytes")
    func aRestorePutsTheFileBack() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        let outcome = try driveWithTwoVersions(sandbox)
        let older = try #require(outcome.keptVersions.first)

        let landing = sandbox.home.appending(path: "Restored")
        let item = RestorableItem(relativePath: older.relativePath,
                                  onTheDriveAt: older.keptAt,
                                  supersededOn: older.supersededOn,
                                  theFileIsGoneFromTheMac: false,
                                  bytes: older.bytes)

        let report = Restore.run([item], fromDrive: sandbox.drivePath, to: landing,
                                 permittedBy: pass())
        #expect(report.restored.count == 1, "\(report.refused.compactMap { $0.refusal?.sentence })")
        let back = landing.appending(path: "Documents/report.txt")
        #expect(try String(contentsOf: back, encoding: .utf8) == "the first draft")
    }

    @Test("⛔ A restore never writes over a file that is already there")
    func aRestoreNeverOverwrites() throws {
        let sandbox = try BackupSandbox()
        defer { sandbox.tearDown() }
        _ = try driveWithTwoVersions(sandbox)

        // The file on the Mac is the newer one. It must survive.
        let report = Restore.run([RestorableItem(relativePath: "Documents/report.txt",
                                                 onTheDriveAt: "\(BackupCatalogue.filesFolderName)/Documents/report.txt",
                                                 supersededOn: nil,
                                                 theFileIsGoneFromTheMac: false,
                                                 bytes: 0)],
                                 fromDrive: sandbox.drivePath,
                                 to: sandbox.home,
                                 permittedBy: pass())
        #expect(report.restored.isEmpty)
        guard case .somethingIsAlreadyThere = try #require(report.refused.first?.refusal) else {
            Issue.record("a restore over an existing file was not refused as such")
            return
        }
        #expect(try String(contentsOf: sandbox.home.appending(path: "Documents/report.txt"),
                           encoding: .utf8) == "the second draft")
    }

    @Test("A drive that is not plugged in says so rather than reporting nothing found")
    func anUnpluggedDriveIsNamed() throws {
        let item = RestorableItem(relativePath: "a.txt", onTheDriveAt: "Your files/a.txt",
                                  supersededOn: nil, theFileIsGoneFromTheMac: false, bytes: 1)
        let report = Restore.run([item], fromDrive: "/Volumes/Not Plugged In",
                                 to: FileManager.default.temporaryDirectory,
                                 permittedBy: RehearsalGate.passForTesting("unplugged"))
        #expect(report.restored.isEmpty)
        guard case .theDriveIsNotConnected = try #require(report.refused.first?.refusal) else {
            Issue.record("an unplugged drive was not named as such")
            return
        }
    }

    @Test("The safe landing place is a dated folder on the Desktop, and the reason is written down")
    func theSafeLandingPlace() {
        let landing = Restore.somewhereSafe(home: URL(filePath: "/Users/example"),
                                            on: Date(timeIntervalSince1970: 1_756_000_000))
        #expect(landing.path(percentEncoded: false).contains("/Desktop/Restored by Wellkept 2025-"))
        #expect(Restore.whyNotStraightBack.contains("may be the newer one"))
    }
}

// MARK: - The promise, in the engine's own words

@Suite("What the engine promises, and what it does not")
struct BackupPromiseTests {

    @Test("⛔ Nothing in the engine's own sentences promises to rebuild a Mac")
    func thePromiseIsAllYourFiles() {
        let sentences = [Destination.howToPrepareADrive,
                         Destination.whatWellkeptNeverDoes,
                         Destination.whatArrivesOnTheDrive,
                         Destination.whyTheWholeDriveAndNotAFolder,
                         BackupCatalogue.readMe,
                         Restore.whyNotStraightBack,
                         SourceRules.whyANameIsTheEvidenceHere]
        for sentence in sentences {
            #expect(sentence.lowercased().contains(Backup.promiseWeDoNotMake) == false,
                    "this promises too much: \(sentence)")
        }
        #expect(Backup.whatItPromises.contains("does not reinstall your Mac"))
    }

    @Test("Every refusal a person can read says what to do about it, or says plainly that they cannot")
    func everyRefusalSaysSomething() {
        let refusals: [DestinationRefusal] = [
            .notConnected(name: "Backup"), .notADriveOfItsOwn(path: "/x"), .theStartupDisk,
            .theSameDiskAsYourFiles(name: "Macintosh HD"), .onTheNetwork(name: "Server"),
            .readOnly(name: "Locked"), .wrongFormat(name: "Backup", format: .exFAT),
            .notEnoughRoom(needs: SizeOnDisk(100), free: SizeOnDisk(10)),
            .couldNotBeRead(path: "/x", why: "no"),
        ]
        for refusal in refusals {
            #expect(refusal.sentence.count > 20, "\(refusal.code) says almost nothing")
            #expect(refusal.code.isEmpty == false)
        }

        for exclusion: SourceExclusion in [.inTheCloudOnly, .aCloudProviderFolder(provider: "Google Drive"),
                                           .excludedByYou(rule: "Secret"),
                                           .notACopyableThing(kind: "a socket"),
                                           .theBackupItself, .anotherVolume(name: "Other")] {
            #expect(exclusion.sentence.count > 20)
        }
        // ⭐ Only the cloud cases are worth putting on the face.
        #expect(SourceExclusion.inTheCloudOnly.worthSaying)
        #expect(SourceExclusion.notACopyableThing(kind: "a socket").worthSaying == false)
    }
}
