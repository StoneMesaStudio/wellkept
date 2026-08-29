// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  BackupRun.swift
//  Wellkept — App/Backup/Engine
//
//  ⭐ **The whole copy, start to finish — and the one door the gate stands in.**
//
//  ## ⛔ Nothing here is offered to anybody until the rehearsal has been walked
//
//  `start(_:)` asks `RehearsalGate.permissionToWrite(to:)` and returns the refusal when the answer
//  is no. `RehearsalGate.performed` is `nil` today, so **the answer is no today**, on every Mac,
//  including this one. That is not a bug and it is not a placeholder: a backup is proven by erasing
//  a drive and restoring from it, nobody has done that with this code, and John's condition was that
//  the gate be a shipped, visible thing rather than a note in a document.
//
//  Opening it is one edit in one place — the four facts in `RehearsalGate.performed`. Nothing in
//  this file changes.
//
//  ## The order of operations, and why each step is where it is
//
//  1. **Ask the gate.** Before anything is read, let alone written.
//  2. **Judge the drive again.** It was judged when the person chose it; drives get unplugged,
//     remounted read-only, and filled up by something else in between.
//  3. **Read Full Disk Access before the copy, not after.** ⚠️ Without it a backup contains no mail,
//     messages, photos, contacts, Safari data or Trash — *nothing*, not partial — and macOS refuses
//     **silently, with no error at all**. There is no failure to detect afterwards, because there is
//     no failure: the folders simply enumerate empty. So the grant is read up front and carried into
//     `BackupCompleteness`, which refuses to call the run complete without it.
//  4. **Take the journal mark before the walk**, never after. Anything that changes while the copy
//     runs then lands in the next run rather than falling into the gap between the two.
//  5. **Walk, or replay.** The journal replays in about five seconds; the fallback walk is about
//     thirty-four. Any doubt at all about the journal and it is the walk — see `JournalDoubt`.
//  6. **Move the old copy aside before writing the new one.** `AtomicMove` — the app's one safe move
//     — on the drive's own volume. ⛔ Never an overwrite: the thing being overwritten is the only
//     other copy of somebody's file.
//  7. **Copy**, with the four repairs. `CopyOne`.
//  8. **Check**, at the level asked for, and say which level ran.
//  9. **Write the record**, on the drive, appended.
//
//  ## ⚠️ Two things this run will never do
//
//  - **It never deletes anything from the drive to make room.** If the drive is full, the run stops
//    and says so, with both figures. Retention is a proposal a person presses; see `Retention`.
//  - **It never downloads a file from iCloud in order to back it up.** 72.2 GB of this Mac's files
//    are placeholders, and copying them would mean pulling 72 GB onto a Mac with 95 GB free, over
//    somebody's own internet, to make a second copy of files that already have one. They are named
//    and skipped, every run, out loud. Time Machine has the same hole and never mentions it.

// MARK: - What to do

/// Everything one run needs, decided before it starts.
struct BackupPlan: Sendable {

    /// The home folder. ⚠️ The source is the home folder and nothing above it — 586,642 of 586,643
    /// files there are the user's own, and outside it 320,465 of 361,714 are root-owned and cannot
    /// have their ownership restored by an unprivileged program at all.
    let home: URL

    /// The drive's mount point, as the person chose it.
    let driveMountPoint: String

    let rules: SourceRules

    /// Where the last run got to. `nil` means walk everything.
    let sinceMark: JournalMark?

    /// How hard to check afterwards. ⚠️ `.readBack` is the only level that earns the word
    /// "verified"; see `VerificationLevel`.
    let checkTo: VerificationLevel

    /// How many files to check. `nil` checks all of them.
    let checkSample: Int?

    init(home: URL = StorageManifest.home(),
         driveMountPoint: String,
         rules: SourceRules? = nil,
         sinceMark: JournalMark? = nil,
         checkTo: VerificationLevel = .compared,
         checkSample: Int? = nil) {
        self.home = home
        self.driveMountPoint = driveMountPoint
        self.rules = rules ?? SourceRules(
            home: home,
            destinationFolder: BackupCatalogue.root(onDrive: driveMountPoint).path(percentEncoded: false))
        self.sinceMark = sinceMark
        self.checkTo = checkTo
        self.checkSample = checkSample
    }
}

// MARK: - What happened

/// What one run produced. ⚠️ Every way it can end is a case here, including the two ways it can end
/// before it starts.
enum BackupResult: Sendable {

    /// ⛔ The gate said no. Nothing was read and nothing was written.
    case refusedByTheGate(RehearsalGate.Refusal)

    /// The drive was not usable. Nothing was written.
    case theDriveWasNotUsable([DestinationRefusal])

    /// The record on the drive could not be written. ⚠️ Loud: files may be on the drive and the
    /// index of them may not be.
    case theRecordFailed(CatalogueTrouble)

    /// It ran.
    case finished(BackupOutcome)

    var outcome: BackupOutcome? { if case .finished(let outcome) = self { return outcome }; return nil }

    /// The sentence for the face.
    var sentence: String {
        switch self {
        case .refusedByTheGate(let refusal):     refusal.sentence
        case .theDriveWasNotUsable(let reasons): reasons.map(\.sentence).joined(separator: " ")
        case .theRecordFailed(let trouble):      trouble.sentence
        case .finished(let outcome):             outcome.sentence
        }
    }
}

/// What a completed run copied, skipped and failed on.
struct BackupOutcome: Sendable {

    let record: BackupRunRecord

    /// ⭐ Whether this may be called a complete backup. Built in `WellkeptCore` so the answer is the
    /// same on the face, on the record, and a year later.
    let completeness: BackupCompleteness

    /// What the check found, at the level that ran.
    let check: VerificationReport?

    /// The older copies this run put aside.
    let keptVersions: [KeptVersion]

    /// Everything that failed, so a person can see which files rather than a count.
    let failures: [CopyFailure]

    /// What was skipped, counted by kind. ⚠️ Cloud-only is here and is **not** a failure.
    let skipped: [String: Int]

    /// ⭐ The headline. **Never says "complete" unless it is.**
    var sentence: String {
        var line = completeness.headline
        if let check { line += " " + check.sentence }
        return line
    }

    var linesUnderneath: [String] {
        completeness.missingSentences + (check?.linesUnderneath ?? [])
    }
}

// MARK: - The run

enum BackupRun {

    // MARK: ── ⭐ The door ─────────────────────────────────────────────────────────────────────────

    /// ⭐ **The app's entry point. Asks the gate, and hands back its refusal when it says no.**
    ///
    /// This is the calling convention every writer in this engine follows, in one place:
    ///
    /// ```swift
    /// guard case .granted(let pass) = RehearsalGate.permissionToWrite(to: name) else { … }
    /// ```
    static func start(_ plan: BackupPlan,
                      progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }) -> BackupResult {
        let name = (plan.driveMountPoint as NSString).lastPathComponent
        // ⭐ Two cases, and there is no way to get a `Pass` out of the refused one. That is the
        // enforcement: this switch is exhaustive, and the `.refused` arm has nothing to run with.
        switch RehearsalGate.permissionToWrite(to: name) {
        case .refused(let refusal):
            return .refusedByTheGate(refusal)
        case .granted(let pass):
            return run(plan, permittedBy: pass, progress: progress)
        }
    }

    /// ⚠️ **The background piece asks a harder question and has to clear both proofs.**
    ///
    /// A scheduled backup that silently contains no mail is worse than a manual one, because nobody
    /// is watching when it runs and nobody is told when it holds nothing. Until somebody has watched
    /// an `SMAppService.agent` read a Full-Disk-Access-protected folder with the app not running,
    /// this refuses. See `Backup.whatTheBackgroundPieceMustProveFirst`.
    static func startInTheBackground(_ plan: BackupPlan) -> BackupResult {
        let name = (plan.driveMountPoint as NSString).lastPathComponent
        switch RehearsalGate.permissionForTheBackgroundPiece(to: name) {
        case .refused(let refusal):
            return .refusedByTheGate(refusal)
        case .granted(let pass):
            return run(plan, permittedBy: pass)
        }
    }

    // MARK: ── The work ───────────────────────────────────────────────────────────────────────────

    /// ⭐ **Copy the home folder onto the drive.**
    ///
    /// - Parameters:
    ///   - pass: permission from `RehearsalGate`. Only the gate can make one, so a caller that has
    ///     not asked cannot call this at all.
    ///   - judge: how the drive is judged. **The default is the real judgement and nothing in the
    ///     app passes anything else** — it is a seam so the suite can exercise the copier against a
    ///     temporary folder, which the real judgement refuses (correctly: a folder is not a volume
    ///     of its own, and it is on the same disk as the home folder).
    static func run(_ plan: BackupPlan,
                    permittedBy pass: RehearsalGate.Pass,
                    now: Date = Date(),
                    judgingTheDriveWith judge: (BackupPlan) -> DriveVerdict = {
                        Destination.judge($0.driveMountPoint, home: $0.home)
                    },
                    progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }) -> BackupResult {

        // ⚠️ Per thread. Without it, reading a cloud-only file downloads it.
        ScanPolicy.prepareThisThread()

        let started = now

        // 2. The drive, judged again.
        let verdict = judge(plan)
        guard verdict.mayBeUsed, let drive = verdict.reading else {
            return .theDriveWasNotUsable(verdict.refusals)
        }

        // 3. ⭐ The grant, read before anything is copied. There is nothing to detect afterwards.
        let fullDiskAccessHeld = FullDiskAccess.isGranted

        // The folders on the drive.
        guard case .success = BackupCatalogue.open(onDrive: plan.driveMountPoint, permittedBy: pass) else {
            return .theRecordFailed(.couldNotBeWritten(path: plan.driveMountPoint,
                                                       why: "the backup folder could not be made"))
        }
        let filesRoot = BackupCatalogue.files(onDrive: plan.driveMountPoint)
        let versionsRoot = BackupCatalogue.versions(onDrive: plan.driveMountPoint)
            .appending(path: BackupCatalogue.versionFolderName(for: started))

        // 4–5. What to look at. ⚠️ `changes(since:)` takes its own mark **before** it replays, and
        // that mark is what gets stored — so anything that changes while this run copies lands in
        // the next run rather than falling into the gap between the two.
        let replay = ChangeJournal.changes(since: plan.sinceMark, under: plan.home)
        let paths: [String]
        if let places = replay.places {
            paths = everythingUnder(places, rules: plan.rules)
        } else {
            paths = everythingUnder(plan.home.path(percentEncoded: false), rules: plan.rules)
        }

        progress(BackupProgress(place: plan.home.lastPathComponent, done: 0, failed: 0))

        // 6–7. The copy.
        let links = HardLinkLedger()
        let runID = UUID()
        var copied: [CopiedFile] = []
        var failures: [CopyFailure] = []
        var skipped: [String: Int] = [:]
        var kept: [KeptVersion] = []
        var cloudOnly = 0
        var bytes: Int64 = 0

        // ⚠️ Labelled, because the ENOSPC arm below has to leave the LOOP and not merely the switch.
        // A bare `break` inside a `switch` inside a `for` breaks the switch, and the run would carry
        // on producing a backup missing everything that came after the drive filled up.
        eachFile: for path in paths {
            guard let item = SourceReader.read(path, rules: plan.rules) else { continue }

            if let exclusion = plan.rules.mayCopy(item) {
                let key = exclusion.whyItWasNotCopied.rawValue
                skipped[key, default: 0] += 1
                if exclusion == .inTheCloudOnly { cloudOnly += 1 }
                continue
            }

            let destination = filesRoot.appending(path: item.relativePath)
            let destinationPath = destination.path(percentEncoded: false)

            // ⛔ Never over the top of something. The old copy is moved aside first, with the app's
            // one safe move, on the drive's own volume.
            if Movable.exists(destinationPath) {
                if isUnchanged(item, comparedTo: destinationPath) { continue }
                if let version = putAside(destinationPath,
                                          relativePath: item.relativePath,
                                          into: versionsRoot,
                                          onDrive: plan.driveMountPoint,
                                          runID: runID,
                                          on: started,
                                          theFileIsGoneFromTheMac: false,
                                          permittedBy: pass) {
                    kept.append(version)
                } else {
                    failures.append(CopyFailure(relativePath: item.relativePath,
                                                code: EEXIST,
                                                why: "the older copy could not be put aside",
                                                step: "keeping the previous version"))
                    continue
                }
            } else if !item.isDirectory {
                // The folders above it, made in order, with the source folders' own permissions.
                makeFoldersFor(item.relativePath, under: filesRoot, home: plan.home,
                               rules: plan.rules, permittedBy: pass)
            }

            switch CopyOne.run(item, into: filesRoot, links: links, permittedBy: pass) {
            case .copied(let file):
                copied.append(file)
                bytes += file.bytes.bytes
            case .skipped(let exclusion):
                let key = exclusion.whyItWasNotCopied.rawValue
                skipped[key, default: 0] += 1
                if exclusion == .inTheCloudOnly { cloudOnly += 1 }
            case .failed(let failure):
                failures.append(failure)
                // ⚠️ The drive filling up stops the run. It does not silently continue producing a
                // backup that is missing whatever came after the disk was full — and it does not
                // delete anything to make room, which is what every other tool does here.
                if failure.code == ENOSPC { break eachFile }
            }

            progress(BackupProgress(place: (item.relativePath as NSString).deletingLastPathComponent,
                                    done: copied.count,
                                    failed: failures.count))
        }

        // 8. The check. ⚠️ It always runs — the question is never "was it checked" but "to what
        // level", and a run that reports no check at all is one a person has to interpret.
        //
        // Hard-linked second names are left out: they were not copied, they were linked, and reading
        // the same inode back twice would report a number larger than the number of files.
        //
        // ⚠️ **Folders are left out too**, and that was found by the suite rather than reasoned:
        // `st_size` on a directory is the filesystem's own bookkeeping about how many entries it
        // holds, and it differs legitimately between two copies of the same folder. Comparing it
        // reported every folder in the backup as a mismatch — a check that cries wolf on the
        // ordinary case is worse than no check, because it trains a person to ignore the one that
        // matters.
        let check = Verify.run(copied.filter { !$0.wasLinked && !$0.isDirectory }.map(\.relativePath),
                               home: plan.home,
                               backupFiles: filesRoot,
                               level: plan.checkTo,
                               sample: plan.checkSample)

        let completeness = BackupCompleteness(fullDiskAccessHeld: fullDiskAccessHeld,
                                              cloudOnlySkipped: cloudOnly,
                                              failed: failures.count)

        let record = BackupRunRecord(id: runID,
                                     startedOn: started,
                                     finishedOn: Date(),
                                     filesCopied: copied.count,
                                     bytesCopied: bytes,
                                     cloudOnlySkipped: cloudOnly,
                                     failed: failures.count,
                                     fullDiskAccessHeld: fullDiskAccessHeld,
                                     checkedTo: check.level.rawValue,
                                     mark: replay.mark,
                                     lookedAtEverythingBecause: replay.doubt,
                                     macOSVersion: macOSVersion(),
                                     driveName: drive.name)

        // 9. The record, appended.
        for version in kept {
            _ = BackupCatalogue.append(.version(version), onDrive: plan.driveMountPoint, permittedBy: pass)
        }
        if let trouble = BackupCatalogue.append(.run(record),
                                                onDrive: plan.driveMountPoint,
                                                permittedBy: pass) {
            return .theRecordFailed(trouble)
        }

        return .finished(BackupOutcome(record: record,
                                       completeness: completeness,
                                       check: check,
                                       keptVersions: kept,
                                       failures: failures,
                                       skipped: skipped))
    }

    // MARK: ── The pieces ─────────────────────────────────────────────────────────────────────────

    /// Every path under a root that the rules allow a walk into.
    ///
    /// ⚠️ Depth-first with the folder emitted **before** its contents, so a folder always exists on
    /// the drive before anything is written into it.
    static func everythingUnder(_ root: String, rules: SourceRules) -> [String] {
        ScanPolicy.prepareThisThread()

        var found: [String] = []
        var queue = [root]

        while let path = queue.popLast() {
            let url = URL(filePath: path)
            found.append(path)

            var status = stat()
            guard lstat(path, &status) == 0, (status.st_mode & S_IFMT) == S_IFDIR else { continue }
            if rules.mayDescend(into: url) != nil { continue }

            // ⚠️ `contentsOfDirectory`, not a deep enumerator: the rules have to be asked at every
            // level, and a deep enumerator that has already descended has already done the reading
            // we were trying to avoid.
            let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            for child in children.sorted().reversed() {
                queue.append(path + "/" + child)
            }
        }
        return found
    }

    /// Every path under each of several roots, de-duplicated.
    static func everythingUnder(_ roots: [String], rules: SourceRules) -> [String] {
        var seen = Set<String>()
        var found: [String] = []
        for root in roots {
            for path in everythingUnder(root, rules: rules) where seen.insert(path).inserted {
                found.append(path)
            }
        }
        return found
    }

    /// Whether the copy on the drive is already this file.
    ///
    /// ⚠️ Size **and** modification time to the second, which is what every incremental backup uses.
    /// It is not proof — a file changed in place, in the same second, to the same length, reads as
    /// unchanged — and that is why `.readBack` exists and why the word "verified" is reserved for it.
    static func isUnchanged(_ item: SourceItem, comparedTo destinationPath: String) -> Bool {
        var copy = stat()
        guard lstat(destinationPath, &copy) == 0 else { return false }
        guard !item.isDirectory else { return true }
        return Int64(copy.st_size) == item.apparentBytes
            && copy.st_mtimespec.tv_sec == Int(item.modifiedOn?.timeIntervalSince1970 ?? -1)
    }

    /// Move the copy on the drive into this run's `Previous versions` folder, and record it.
    ///
    /// ⭐ `AtomicMove` — the app's one safe move, on the drive's own volume. `RENAME_EXCL` so it can
    /// never write over something already there, `RENAME_NOFOLLOW_ANY` so it can never act through a
    /// symbolic link.
    static func putAside(_ destinationPath: String,
                         relativePath: String,
                         into versionsRoot: URL,
                         onDrive mountPoint: String,
                         runID: UUID,
                         on date: Date,
                         theFileIsGoneFromTheMac: Bool,
                         permittedBy pass: RehearsalGate.Pass) -> KeptVersion? {

        let target = versionsRoot.appending(path: relativePath)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        var status = stat()
        let bytes = lstat(destinationPath, &status) == 0 ? Int64(status.st_blocks) * 512 : 0

        guard case .moved = AtomicMove.perform(from: destinationPath,
                                               to: target.path(percentEncoded: false)) else {
            return nil
        }

        // ⚠️ **The backup root, asked for directly.** It was reached by deleting two path
        // components once, and `URL.deletingLastPathComponent()` leaves a trailing slash — so the
        // prefix never matched, `keptAt` came out as a full absolute path, and every restore looked
        // for the file at `<drive>/Wellkept Backup/<the whole absolute path again>`. Caught by the
        // suite the first time a second run put a file aside.
        let root = BackupCatalogue.root(onDrive: mountPoint).path(percentEncoded: false)
        let full = target.path(percentEncoded: false)
        let keptAt = full.hasPrefix(root + "/") ? String(full.dropFirst(root.count + 1)) : full

        return KeptVersion(id: UUID(),
                           relativePath: relativePath,
                           keptAt: keptAt,
                           supersededOn: date,
                           runID: runID,
                           bytes: bytes,
                           theFileIsGoneFromTheMac: theFileIsGoneFromTheMac)
    }

    /// Make the folders above a file, each with the source folder's own permissions.
    static func makeFoldersFor(_ relativePath: String,
                               under filesRoot: URL,
                               home: URL,
                               rules: SourceRules,
                               permittedBy pass: RehearsalGate.Pass) {
        let parts = relativePath.split(separator: "/").map(String.init).dropLast()
        var walked: [String] = []
        for part in parts {
            walked.append(part)
            let relative = walked.joined(separator: "/")
            let destination = filesRoot.appending(path: relative).path(percentEncoded: false)
            guard !Movable.exists(destination) else { continue }
            let source = home.appending(path: relative).path(percentEncoded: false)
            guard let item = SourceReader.read(source, rules: rules) else { continue }
            _ = CopyOne.run(item, into: filesRoot, links: HardLinkLedger(), permittedBy: pass)
        }
    }

    /// This Mac's macOS version, recorded per run.
    ///
    /// ⚠️ **Migration Assistant refuses a backup made on a newer macOS than the machine being
    /// restored to.** That is the reason it is written down.
    static func macOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

// MARK: - What the screen says while it runs

/// ⚠️ **Where it is, not how far along, and never a time.**
///
/// The same rule as `ScanPolicy.Running`, and for the same reason: nobody has measured a first
/// backup of a large home folder onto a slow drive, so any estimate would be a guess dressed as a
/// countdown. What is honest is the folder it is in and how many files are behind it.
struct BackupProgress: Sendable, Equatable, Hashable {

    /// The folder it is working through, in the person's own words.
    let place: String

    let done: Int
    let failed: Int

    var sentence: String { place.isEmpty ? "Copying your files" : "Copying \(place)" }

    /// ⛔ There is deliberately no `estimatedTimeRemaining` and no percentage. Do not add one.
    static let whyThereIsNoEstimate =
        "A first backup onto a drive nobody has measured would make any figure a guess, and a "
        + "progress bar that lies twice is worse than no progress bar."
}
