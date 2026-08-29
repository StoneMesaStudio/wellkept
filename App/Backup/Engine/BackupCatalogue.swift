// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  BackupCatalogue.swift
//  Wellkept — App/Backup/Engine
//
//  ⭐ **What is on the drive, what used to be on it, and what falls off — written on the drive
//  itself, in a form that is readable without this app.**
//
//  ## The shape on the drive, and why it is this shape
//
//      /Volumes/Your Drive/Wellkept Backup/
//        Your files/              ← the home folder as it is now. Open it in the Finder.
//        Previous versions/
//          2026-09-06 14-02/      ← what was replaced or removed on that run, and nothing else
//        Wellkept Backup Record.jsonl
//        What this is.txt
//
//  **`Your files` is a plain folder of plain files.** That is the whole design: a person can plug
//  the drive into any Mac, open it, and drag their documents back with the Finder, with Wellkept
//  uninstalled, deleted, or never installed on that machine. Nothing is packed, nothing is
//  compressed, nothing needs us. ⚠️ A backup that can only be read by the tool that made it is a
//  second dependency at the exact moment a person has run out of dependencies to spare.
//
//  **`Previous versions` holds only what changed.** A file that is replaced is moved there first —
//  with `AtomicMove`, the one safe move, on the drive's own volume — and then the new one is
//  written. So the current state is always complete and the history costs only the differences.
//
//  ⚠️ **The record is JSON Lines, appended, never rewritten.** The quarantine ledger shipped with a
//  truncate-in-place and it had to be fixed; the same mistake here would lose the index of
//  somebody's backup at the moment a run was interrupted. Every line stands alone, a torn last line
//  is dropped on read, and nothing before it is affected.
//
//  ## ⛔ Nothing is ever deleted by surprise. Not here, not on a schedule, not to make room.
//
//  This is the app-wide rule, and this file is where it would be easiest to break: a backup drive
//  fills up, and every other backup tool on earth solves that by quietly deleting the oldest thing.
//  **Wellkept does not.** `Retention` produces a **proposal** — what is older than the rule, what it
//  occupies, and what removing it would give back — and a person presses the button. The removal
//  itself is `forget(_:permittedBy:)`, it takes an explicit list of versions and a
//  `RehearsalGate.Pass`, and it will not take "everything older than X" as an argument.
//
//  If the drive fills, the run stops and says so. **A backup that deleted last month's copy of
//  something to make room for this month's is not a service anybody asked for.**

// MARK: - What one run did

/// One backup run, as the drive records it.
struct BackupRunRecord: Sendable, Equatable, Hashable, Codable, Identifiable {

    let id: UUID
    let startedOn: Date
    let finishedOn: Date

    /// How many things were copied, and what they occupy. ⚠️ Size on disk, never apparent size.
    let filesCopied: Int
    let bytesCopied: Int64

    /// Named and skipped because they are in the cloud. **Not a failure.**
    let cloudOnlySkipped: Int

    /// Genuinely failed.
    let failed: Int

    /// ⭐ Whether the run held Full Disk Access. **The single fact that decides whether this run may
    /// be called a complete backup**, and it is written down per run because a person restoring in
    /// a year needs to know which of their backups was made blind.
    let fullDiskAccessHeld: Bool

    /// Which level of checking actually ran. ⚠️ Never the word "verified" unless it was level three.
    let checkedTo: String

    /// Where the journal had got to when this run started, so the next one can replay from here.
    let mark: JournalMark?

    /// Why the journal was not used, when it was not. `nil` means it was.
    let lookedAtEverythingBecause: JournalDoubt?

    /// The macOS this backup was made on.
    ///
    /// ⚠️ **Migration Assistant refuses a backup made on a newer macOS than the machine being
    /// restored to.** That is the reason this is recorded rather than a nicety, and it is the same
    /// reason the printed Recovery Plan carries the version and is reprinted when it changes.
    let macOSVersion: String?

    /// The drive's name at the time, for a person reading the record on a different machine.
    let driveName: String

    var duration: TimeInterval { finishedOn.timeIntervalSince(startedOn) }

    /// ⭐ Whether this run may be described as a complete backup. Built from the same type the whole
    /// app uses, so a record read back a year later answers the question exactly as the face did on
    /// the day.
    var completeness: BackupCompleteness {
        BackupCompleteness(fullDiskAccessHeld: fullDiskAccessHeld,
                           cloudOnlySkipped: cloudOnlySkipped,
                           failed: failed)
    }
}

/// One older copy of a file, kept because a newer one replaced it or because it is gone from the
/// Mac.
struct KeptVersion: Sendable, Equatable, Hashable, Codable, Identifiable {

    let id: UUID

    /// Where the file lives in the home folder, so a search can find it by the name a person knows.
    let relativePath: String

    /// Where the old copy is now, relative to the backup folder.
    let keptAt: String

    /// When it stopped being the current copy.
    let supersededOn: Date

    /// The run that superseded it.
    let runID: UUID

    let bytes: Int64

    /// Whether the file is gone from the Mac entirely, as opposed to having simply changed.
    ///
    /// ⚠️ This distinction is the whole reason a person keeps a backup: "I changed it and want the
    /// old one" and "I deleted it and want it back" are different requests, and a list that does not
    /// separate them makes the second one a hunt.
    let theFileIsGoneFromTheMac: Bool

    var name: String { (relativePath as NSString).lastPathComponent }
}

// MARK: - The lines on the drive

/// One line of the record. Every line stands alone; a torn last line costs that line and nothing
/// else.
enum CatalogueLine: Sendable, Equatable, Codable {
    case run(BackupRunRecord)
    case version(KeptVersion)

    private enum Kind: String, Codable { case run, version }
    private enum CodingKeys: String, CodingKey { case kind, run, version }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        switch try box.decode(Kind.self, forKey: .kind) {
        case .run:     self = .run(try box.decode(BackupRunRecord.self, forKey: .run))
        case .version: self = .version(try box.decode(KeptVersion.self, forKey: .version))
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .run(let record):
            try box.encode(Kind.run, forKey: .kind)
            try box.encode(record, forKey: .run)
        case .version(let version):
            try box.encode(Kind.version, forKey: .kind)
            try box.encode(version, forKey: .version)
        }
    }
}

// MARK: - The catalogue

/// ⭐ **The record on the drive.** Reads are free; every write takes a `RehearsalGate.Pass`.
enum BackupCatalogue {

    /// The mirror of the home folder. Plain files, plain folders, openable in the Finder.
    static let filesFolderName = "Your files"

    /// Where a replaced or removed file's old copy goes.
    static let versionsFolderName = "Previous versions"

    static let recordFileName = "Wellkept Backup Record.jsonl"

    static let readMeFileName = "What this is.txt"

    static func root(onDrive mountPoint: String) -> URL { Destination.folder(on: mountPoint) }
    static func files(onDrive mountPoint: String) -> URL {
        root(onDrive: mountPoint).appending(path: filesFolderName)
    }
    static func versions(onDrive mountPoint: String) -> URL {
        root(onDrive: mountPoint).appending(path: versionsFolderName)
    }
    static func record(onDrive mountPoint: String) -> URL {
        root(onDrive: mountPoint).appending(path: recordFileName)
    }

    /// ⭐ **The note that makes the drive readable without us.** Written once, rewritten whenever it
    /// changes, and deliberately says what Wellkept does *not* promise.
    static let readMe = """
        Wellkept Backup

        The folder "\(filesFolderName)" is a copy of your home folder. It is ordinary files in \
        ordinary folders. You can open it in the Finder on any Mac and drag anything you want back, \
        with or without Wellkept installed.

        "\(versionsFolderName)" holds older copies of files that changed or were deleted, filed by \
        the date they stopped being current.

        \(Backup.whatItPromises)

        Wellkept never erases, formats or partitions a drive, and it never deletes anything from \
        this one without being asked.
        """

    // MARK: ── Opening the folder on the drive ────────────────────────────────────────────────────

    /// **Make the folders on the drive, if they are not there.**
    ///
    /// ⭐ Takes a `RehearsalGate.Pass`. Creating the destination folder is already writing to
    /// somebody's drive, which is why the guard in `Tests/RehearsalGateGuardTests.swift` covers
    /// every write primitive in this directory and not only the copy ones.
    ///
    /// ⚠️ Refuses a pass that admits to being for testing when the drive is a real one — the debug
    /// door exists so the engine can be exercised, never so it can write to somebody's disk.
    static func open(onDrive mountPoint: String,
                     permittedBy pass: RehearsalGate.Pass) -> Result<URL, CatalogueTrouble> {

        if pass.isForTestingOnly, isARealDrive(mountPoint) {
            return .failure(.aTestingPassOnARealDrive(path: mountPoint))
        }

        let base = root(onDrive: mountPoint)
        for folder in [base, files(onDrive: mountPoint), versions(onDrive: mountPoint)] {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                return .failure(.couldNotBeWritten(path: folder.path(percentEncoded: false),
                                                   why: error.localizedDescription))
            }
        }

        // The note is rewritten whenever its wording changes, and only then — a file rewritten on
        // every run is a file whose modification date tells a person nothing.
        let note = base.appending(path: readMeFileName)
        let existing = try? String(contentsOf: note, encoding: .utf8)
        if existing != readMe { try? Data(readMe.utf8).write(to: note) }

        return .success(base)
    }

    /// ⚠️ Whether this is a drive somebody actually owns, as opposed to a temporary folder a test
    /// made. Used for one thing: refusing a testing pass on a real drive.
    static func isARealDrive(_ mountPoint: String) -> Bool {
        let path = Destination.canonical(mountPoint)
        return path == "/" || path.hasPrefix("/Volumes/")
    }

    // MARK: ── Appending ──────────────────────────────────────────────────────────────────────────

    /// **Append one line to the record.**
    ///
    /// ⚠️ **`O_APPEND`, opened and closed per line, never a rewrite of the file.** The quarantine
    /// ledger shipped with a truncate-in-place and had to be fixed; here the same mistake would lose
    /// the index of an entire backup. An append either lands whole or does not land, and a torn last
    /// line costs one line.
    @discardableResult
    static func append(_ line: CatalogueLine,
                       onDrive mountPoint: String,
                       permittedBy pass: RehearsalGate.Pass) -> CatalogueTrouble? {

        if pass.isForTestingOnly, isARealDrive(mountPoint) {
            return .aTestingPassOnARealDrive(path: mountPoint)
        }

        guard let data = try? encoder().encode(line) else {
            return .couldNotBeWritten(path: recordFileName, why: "the line could not be written out")
        }
        var bytes = Data(data)
        bytes.append(0x0A)

        let path = record(onDrive: mountPoint).path(percentEncoded: false)
        // ⚠️ `O_RDWR` and not `O_WRONLY`: the torn-line check below has to *read* the last byte, and
        // a write-only descriptor refuses that with `EBADF` — silently, so the check would answer
        // "the file ends in a newline" about every file. `O_APPEND` is what makes the write atomic
        // and puts it at the end regardless; reading does not change that.
        let descriptor = Darwin.open(path, O_RDWR | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            return .couldNotBeWritten(path: path, why: String(cString: strerror(errno)))
        }
        defer { close(descriptor) }

        // ⚠️ **A torn last line must stay torn, and must not swallow the next one.**
        //
        // Caught by the suite, not by reasoning: an interrupted write leaves a partial line with no
        // newline after it, and appending straight onto the end glues the new record to the wreckage
        // — so the torn line takes the *next* record down with it, which is the one thing an
        // append-only record is supposed to make impossible. If the file does not end in a newline,
        // one is written first. The torn line is then dropped on read, alone.
        if endsWithoutANewline(descriptor) { bytes.insert(0x0A, at: 0) }

        let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard written == bytes.count else {
            return .couldNotBeWritten(path: path, why: String(cString: strerror(errno)))
        }
        return nil
    }

    /// Whether the file has something in it and does not end in a newline — the shape an
    /// interrupted append leaves behind.
    private static func endsWithoutANewline(_ descriptor: Int32) -> Bool {
        let size = lseek(descriptor, 0, SEEK_END)
        guard size > 0 else { return false }
        var last: UInt8 = 0
        // `pread` so the append offset the descriptor carries is not disturbed by the read.
        guard pread(descriptor, &last, 1, off_t(size - 1)) == 1 else { return false }
        return last != 0x0A
    }

    // MARK: ── Reading ────────────────────────────────────────────────────────────────────────────

    /// Every line on the drive. A line that will not decode is dropped rather than failing the read:
    /// one bad line must not hide the other four thousand.
    static func lines(onDrive mountPoint: String) -> [CatalogueLine] {
        let path = record(onDrive: mountPoint)
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        let decoder = decoder()
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap {
            try? decoder.decode(CatalogueLine.self, from: Data($0.utf8))
        }
    }

    /// Every run, newest first.
    static func runs(onDrive mountPoint: String) -> [BackupRunRecord] {
        lines(onDrive: mountPoint).compactMap {
            if case .run(let record) = $0 { return record }
            return nil
        }.sorted { $0.finishedOn > $1.finishedOn }
    }

    /// Every kept older copy, newest first.
    static func keptVersions(onDrive mountPoint: String) -> [KeptVersion] {
        lines(onDrive: mountPoint).compactMap {
            if case .version(let version) = $0 { return version }
            return nil
        }.sorted { $0.supersededOn > $1.supersededOn }
    }

    /// The most recent run, or `nil` on a drive nothing has been written to.
    static func lastRun(onDrive mountPoint: String) -> BackupRunRecord? { runs(onDrive: mountPoint).first }

    /// ISO-8601 dates and sorted keys, for the same reason as the quarantine ledger: the case where
    /// this file matters most is the one where Wellkept is not running, and a person with a text
    /// editor can read `2026-09-06T14:02:11Z` and cannot read `775472043.19`.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: ── ⛔ The only removal in this engine ────────────────────────────────────────────────

    /// ⛔ **Remove named older copies from the drive. The only thing in this engine that removes
    /// anything, and it takes a list rather than a rule.**
    ///
    /// ⚠️ **There is deliberately no `forgetEverythingOlderThan(_:)`.** A function that takes a rule
    /// is a function somebody can call on a timer, and the moment one exists, a full drive gets
    /// solved by deleting last year silently. This one takes the exact versions a person looked at
    /// and pressed a button about, and it names each one back in the result.
    ///
    /// ⚠️ It never touches `Your files`. Anything there is the current copy of something, and there
    /// is no arrangement under which removing the current copy is retention.
    ///
    /// - Returns: the versions that are genuinely gone. Anything that could not be removed is
    ///   absent from the result and still on the drive — reported, never assumed away.
    @discardableResult
    static func forget(_ versions: [KeptVersion],
                       onDrive mountPoint: String,
                       permittedBy pass: RehearsalGate.Pass) -> [KeptVersion] {

        if pass.isForTestingOnly, isARealDrive(mountPoint) { return [] }

        let versionsRoot = self.versions(onDrive: mountPoint).path(percentEncoded: false)
        var gone: [KeptVersion] = []

        for version in versions {
            let target = root(onDrive: mountPoint).appending(path: version.keptAt)
            let path = target.path(percentEncoded: false)

            // ⚠️ The last line of defence, and it is not decoration: a `keptAt` that has been
            // mangled, or a record from a different drive, must never let this reach into
            // "Your files" or out of the backup folder altogether.
            guard Movable.isInside(path, any: [versionsRoot]) else { continue }
            guard Movable.symlinkInParentChain(of: path) == nil else { continue }

            if (try? FileManager.default.removeItem(at: target)) != nil { gone.append(version) }
            else if !Movable.exists(path) { gone.append(version) }
        }
        return gone
    }

    /// The folder this run's superseded copies go in. Dated in a form that sorts and that a person
    /// reads without help.
    static func versionFolderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: date)
    }
}

// MARK: - Trouble

/// What went wrong with the record. ⚠️ Loud when it happens: the files may be on the drive and the
/// index of them may not be.
enum CatalogueTrouble: Sendable, Equatable, Hashable, Error {

    case couldNotBeWritten(path: String, why: String)

    /// ⛔ A debug-only pass was handed to something writing to a real drive.
    case aTestingPassOnARealDrive(path: String)

    var sentence: String {
        switch self {
        case .couldNotBeWritten(let path, let why):
            "The backup's own record could not be written at \(path): \(why). The files may be on "
            + "the drive; the list of them is not."
        case .aTestingPassOnARealDrive(let path):
            "Wellkept refused to write to \(path) because the permission it was given is the "
            + "testing one. That is a fault in Wellkept, not in your drive, and nothing was written."
        }
    }

    var isLoud: Bool { true }
}

// MARK: - ⛔ Retention: a proposal, never an act

/// **How long older copies are kept before Wellkept offers to remove them.**
///
/// ⚠️ **This type proposes. It never deletes.** Every other backup tool solves a full drive by
/// quietly removing the oldest thing on it, and that is precisely the behaviour this app refuses
/// everywhere else — nothing is deleted, quarantine has a thirty-day undo, and the Storage section
/// never sweeps a person's own files. A backup drive is not an exception to that; it is the place
/// where breaking it would cost the most.
struct Retention: Sendable, Equatable, Hashable, Codable {

    /// Older copies younger than this are never offered for removal.
    ///
    /// Ninety days rather than thirty: quarantine's thirty days is about a file you *chose* to set
    /// aside this month, and this is about the version of a document you may not discover is wrong
    /// until the next quarter's figures come out.
    let keepEverythingForDays: Int

    /// The whole rule, for a person.
    var sentence: String {
        "Older copies are kept for at least \(keepEverythingForDays) days. After that Wellkept will "
        + "show you what has aged out and what removing it would give back. It never removes "
        + "anything from your drive on its own."
    }

    static let standard = Retention(keepEverythingForDays: 90)

    /// What has aged past the rule. **A list to show somebody, not a list to act on.**
    func agedOut(_ versions: [KeptVersion], now: Date = Date()) -> [KeptVersion] {
        versions.filter {
            let days = Calendar.current.dateComponents([.day], from: $0.supersededOn, to: now).day ?? 0
            return days >= keepEverythingForDays
        }
    }

    /// What the proposal says: how many, how old, and what it would give back.
    ///
    /// ⚠️ **"Would give back" is the honest figure and it is the sum of what those copies occupy on
    /// the backup drive** — not what they occupy on this Mac, and not what they claim to weigh.
    func proposal(_ versions: [KeptVersion], now: Date = Date()) -> RetentionProposal {
        let due = agedOut(versions, now: now)
        return RetentionProposal(versions: due,
                                 wouldGiveBack: SizeOnDisk(due.reduce(0) { $0 + $1.bytes }),
                                 rule: self)
    }
}

/// What Wellkept would remove if somebody asked it to. ⛔ Nothing happens because this exists.
struct RetentionProposal: Sendable, Equatable, Hashable {

    let versions: [KeptVersion]
    let wouldGiveBack: SizeOnDisk
    let rule: Retention

    var isEmpty: Bool { versions.isEmpty }

    /// The sentence on the screen. ⚠️ Says what would happen, in the conditional, because nothing
    /// has happened.
    var sentence: String {
        guard !isEmpty else {
            return "Nothing on the drive is older than the \(rule.keepEverythingForDays)-day rule."
        }
        let count = versions.count == 1 ? "1 older copy" : "\(versions.count.formatted()) older copies"
        return "\(count) on the drive are older than \(rule.keepEverythingForDays) days. Removing "
             + "them would give back \(wouldGiveBack.text). Nothing is removed until you say so."
    }

    /// The oldest thing in the proposal, which is the fact a person actually wants.
    var oldest: Date? { versions.map(\.supersededOn).min() }
}
