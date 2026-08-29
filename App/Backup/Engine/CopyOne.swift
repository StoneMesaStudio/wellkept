// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  CopyOne.swift
//  Wellkept — App/Backup/Engine
//
//  ⭐ **One file, copied onto the backup drive, with the four things `copyfile` loses put back.**
//
//  ## ⛔ This is a copy, and it is the only copy in the app
//
//  `App/Quarantine` has the one **move** — `renameatx_np` on the same volume — and its header says a
//  copy fallback would be the most damaging line anybody could add there. That is still true, and it
//  is about quarantine: setting a file aside must never silently become a copy, because a copy loses
//  things and the person asked for the file to come back exactly as it was.
//
//  **A backup is a different act.** The destination is a different drive by definition, so a rename
//  is not available at any price — `renameatx_np` returns `EXDEV` across volumes. So this file
//  copies, deliberately, and the whole of it is about paying back what a copy costs. Nothing here
//  moves, deletes or modifies anything in the source: **every syscall in this file writes only to
//  the destination.**
//
//  ⭐ `run` takes a `RehearsalGate.Pass`, and only `RehearsalGate` can make one. A caller that has
//  not asked the gate cannot call this function at all — that is a compile error, not a convention.
//
//  ## What `copyfile` keeps, measured
//
//  Extended attributes, ACLs, resource forks, BSD flags and compression all survive `COPYFILE_ALL`.
//  Those were checked rather than assumed, and they are the reason this is `copyfile` and not a
//  read-and-write loop.
//
//  ## ⚠️ The four things it loses, and the one extra unprivileged call that repairs each
//
//  1. **The creation date.** `COPYFILE_STAT` carries the modification and access times and not the
//     birth time. Repaired with `setattrlist(ATTR_CMN_CRTIME)`. Left alone, every file in a restored
//     home folder claims to have been created on the day of the restore, and every "sort by date
//     created" a person has ever set up is wrong for the rest of the machine's life.
//  2. **The download-provenance tag.** `com.apple.quarantine` is the attribute that records that a
//     file came off the internet, and it is what makes macOS say *"this was downloaded on…"* before
//     it opens something. `copyfile` **launders** it — it does not error, it just arrives clean.
//     Repaired by reading it off the source and writing it onto the copy, along with
//     `kMDItemWhereFroms`. A backup that silently strips provenance is a backup that hands back a
//     folder of files macOS now trusts more than it should.
//  3. **Sparse-file inflation.** A file that claims 500 MB and occupies almost nothing came back as
//     500 MB of real blocks. Repaired by asking for `COPYFILE_DATA_SPARSE` — which is free, and is
//     used only where the source is genuinely sparse, because on an ordinary file it buys nothing.
//  4. **Hard links.** `copyfile` does not know about them, so two names for one file arrive as two
//     files: twice the space, and "change one, change both" quietly stops being true. Repaired with
//     `link(2)` on the destination the second time an inode is seen. `HardLinkLedger` is the memory
//     that makes that possible, and it is per run.
//
//  ## ⚠️ The rule that outranks all four
//
//  **Completeness is judged by the file flag, never by the return code.**
//
//  With the dataless-materialise policy off — which `ScanPolicy.prepareThisThread()` sets, per
//  thread, on every thread that touches the disk — reading a cloud-only file **fails outright**
//  rather than writing an empty one. That is the safety net, and it is the single most valuable line
//  in this engine. **But a genuinely zero-byte cloud file copies cleanly**, and the result is a file
//  in the backup with the right name, the right date and no contents. So `SF_DATALESS` is read off
//  the source *before* the copy, and a return of zero is never treated as evidence of anything. See
//  `Backup.whyTheReturnCodeIsNotEvidence`.
//
//  ## Never over the top of something
//
//  `COPYFILE_EXCL`, for the same reason `AtomicMove` insists on `RENAME_EXCL`: without it a copy
//  **silently destroys** whatever is at the destination. In this engine the thing at the destination
//  is somebody's previous backup, so an overwrite is not a tidy-up, it is the loss of the older
//  copy. Replacing a changed file is `BackupCatalogue`'s job and it moves the old one aside first,
//  with the one safe move, before anything new is written.

// MARK: - What happened to one file

/// What one file's copy produced.
enum CopyOutcome: Sendable, Equatable {

    /// It is on the drive, with everything repaired that needed repairing.
    case copied(CopiedFile)

    /// It was deliberately left out. Not a failure. `SourceExclusion` says which kind.
    case skipped(SourceExclusion)

    /// It genuinely failed.
    case failed(CopyFailure)

    var copiedFile: CopiedFile? { if case .copied(let file) = self { return file }; return nil }
    var isFailure: Bool { if case .failed = self { return true }; return false }

    /// ⭐ How this outcome is filed on the report. Taken from `WellkeptCore` so that "does this
    /// count against completeness" has exactly one answer in the whole app.
    var notCopied: NotCopied? {
        switch self {
        case .copied:                    nil
        case .skipped(let exclusion):    exclusion.whyItWasNotCopied
        case .failed:                    .failed
        }
    }
}

/// One file that is now on the drive, and what had to be repaired to get it there.
struct CopiedFile: Sendable, Equatable, Hashable {

    /// Where it goes on the drive, relative to the backup folder.
    let relativePath: String

    /// What it occupies on this Mac. ⚠️ Size on disk, never the apparent size.
    let bytes: SizeOnDisk

    /// ⚠️ **Whether it is a folder.** Kept because a folder is not a thing verification can compare:
    /// `st_size` on a directory is the filesystem's own bookkeeping and differs legitimately between
    /// two copies of the same folder. Caught by the suite the first time the check ran.
    let isDirectory: Bool

    let modifiedOn: Date?
    let createdOn: Date?

    /// The identity of the source file, which is how the second name of a hard link is recognised.
    let device: Int32
    let inode: UInt64

    /// ⭐ **It was linked to a file already in this backup rather than copied again.** The second
    /// name of a hard link.
    let linkedToAnotherName: String?

    /// Which of the four repairs were actually needed. Kept so the record can say what was done
    /// rather than claiming a general competence.
    let repairs: [CopyRepair]

    var wasLinked: Bool { linkedToAnotherName != nil }
}

/// One of the four things `copyfile` loses, put back.
enum CopyRepair: String, Sendable, Equatable, CaseIterable, Codable {

    /// `setattrlist(ATTR_CMN_CRTIME)`.
    case creationDate

    /// `com.apple.quarantine` and `kMDItemWhereFroms`, read off the source and written on.
    case whereItCameFrom

    /// `COPYFILE_DATA_SPARSE`, so a file that claims more than it occupies stays that way.
    case sparseness

    /// `link(2)` — a second name for a file already in this backup.
    case hardLink

    var label: String {
        switch self {
        case .creationDate:     "Creation date"
        case .whereItCameFrom:  "Where the file came from"
        case .sparseness:       "Kept the file's real size"
        case .hardLink:         "Kept as one file with two names"
        }
    }
}

/// Why one file did not copy.
struct CopyFailure: Sendable, Equatable, Hashable {

    let relativePath: String

    /// `errno` from the failing call.
    let code: Int32

    /// The system's own words.
    let why: String

    /// Which step failed, so a support conversation can be about a step rather than a guess.
    let step: String

    /// The sentence a person reads.
    var sentence: String {
        switch code {
        case EEXIST:
            return "There is already something at \(relativePath) on the drive, and Wellkept will "
                 + "not write over it."
        case ENOSPC:
            return "The drive ran out of room while copying \(relativePath)."
        case EPERM, EACCES:
            return "macOS would not let Wellkept read \(relativePath), and Wellkept does not ask "
                 + "for a password to insist."
        case EROFS:
            return "The drive became read-only while copying \(relativePath)."
        case ENOENT:
            return "\(relativePath) was gone by the time Wellkept reached it."
        default:
            return "\(relativePath) could not be copied: \(why)."
        }
    }
}

// MARK: - ⚠️ The memory that makes hard links survive

/// **Which destination path each source inode landed at, for this run.**
///
/// ⚠️ `copyfile` has no idea two paths are one file. Without this, a home folder containing a
/// hard-linked file under two names arrives on the drive as two independent files — twice the space,
/// and a restore where editing one no longer changes the other. Measured as one of the four losses.
///
/// Keyed on device **and** inode, never inode alone: inode numbers are only unique within a volume,
/// and a home folder can have another disk mounted inside it.
final class HardLinkLedger: @unchecked Sendable {

    private let lock = NSLock()
    private var firstNameOf: [Key: String] = [:]

    struct Key: Hashable, Sendable {
        let device: Int32
        let inode: UInt64
    }

    init() {}

    /// The destination path this inode already landed at, or `nil` if this is its first name.
    func firstName(device: Int32, inode: UInt64) -> String? {
        lock.lock(); defer { lock.unlock() }
        return firstNameOf[Key(device: device, inode: inode)]
    }

    /// Remember where this inode landed.
    func remember(device: Int32, inode: UInt64, at destination: String) {
        lock.lock(); defer { lock.unlock() }
        firstNameOf[Key(device: device, inode: inode)] = destination
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return firstNameOf.count }
}

// MARK: - The copy

/// ⭐ **The one place a file is copied onto a backup drive.**
enum CopyOne {

    /// The extended attributes that carry where a file came from.
    ///
    /// ⚠️ `com.apple.quarantine` is the one macOS reads before opening something downloaded, and it
    /// is the one `copyfile` launders. `kMDItemWhereFroms` is the URL Safari and Mail record, which
    /// is what a person sees in Get Info.
    static let provenanceAttributes = ["com.apple.quarantine",
                                       "com.apple.metadata:kMDItemWhereFroms"]

    /// ⭐ **Copy one thing.**
    ///
    /// - Parameters:
    ///   - item: the source, already read once. ⚠️ Never re-read here: a file read twice is a file
    ///     that can change in between, and the copy would then be checked against a different
    ///     reading from the one that chose it.
    ///   - destinationRoot: the backup folder on the drive.
    ///   - links: this run's hard-link memory.
    ///   - pass: ⭐ permission from `RehearsalGate`. Only the gate can make one.
    static func run(_ item: SourceItem,
                    into destinationRoot: URL,
                    links: HardLinkLedger,
                    permittedBy pass: RehearsalGate.Pass) -> CopyOutcome {

        // ⚠️ Per thread, not per process. Without it a read of a cloud-only file DOWNLOADS it —
        // measured at 524 files and nine minutes during the research. Cheap, idempotent, and set
        // here rather than trusted to have been set by whoever called us.
        ScanPolicy.prepareThisThread()

        let destination = destinationRoot.appending(path: item.relativePath)
        let destinationPath = destination.path(percentEncoded: false)

        // ⭐ **The flag, before the copy.** A cloud-only file is skipped rather than attempted: the
        // attempt is what would download it if the policy above ever failed to take.
        if item.isCloudOnly { return .skipped(.inTheCloudOnly) }

        if item.isDirectory {
            return makeFolder(item, at: destinationPath, permittedBy: pass)
        }

        // ⚠️ **Repair 4, and it comes first**, because a second name must not be copied at all.
        if item.isHardLinked,
           let first = links.firstName(device: item.device, inode: item.inode) {
            return linkAgain(item, from: first, to: destinationPath, permittedBy: pass)
        }

        // The copy itself.
        var flags = UInt32(COPYFILE_ALL) | UInt32(COPYFILE_NOFOLLOW) | UInt32(COPYFILE_EXCL)
        var repairs: [CopyRepair] = []

        // ⚠️ **Repair 3.** Only where the source is genuinely sparse — on an ordinary file this flag
        // buys nothing, and asking for it everywhere would be a claim we had not measured.
        if item.isSparse {
            flags |= UInt32(COPYFILE_DATA_SPARSE)
            repairs.append(.sparseness)
        }

        let code = copyfile(item.path, destinationPath, nil, copyfile_flags_t(flags))
        guard code == 0 else {
            let number = errno
            return .failed(CopyFailure(relativePath: item.relativePath,
                                       code: number,
                                       why: String(cString: strerror(number)),
                                       step: "copying the file"))
        }

        // ⚠️ **The return code is not evidence.** Read the source's flag again now that the copy is
        // done: a file that became a cloud placeholder while we were working would have copied
        // cleanly and be empty on the drive.
        if SourceReader.isCloudOnly(item.path) {
            unlink(destinationPath)
            return .skipped(.inTheCloudOnly)
        }

        // ⚠️ **Repair 1 and repair 2.** Both are one unprivileged call each, both are on the
        // destination only, and neither can fail in a way that costs the file — a copy with the
        // wrong creation date is still the file's contents, so a failed repair is recorded and does
        // not fail the copy.
        if let createdOn = item.createdOn, setCreationDate(createdOn, at: destinationPath) {
            repairs.append(.creationDate)
        }
        if carryProvenance(from: item.path, to: destinationPath) {
            repairs.append(.whereItCameFrom)
        }

        if item.isHardLinked {
            links.remember(device: item.device, inode: item.inode, at: destinationPath)
        }

        return .copied(CopiedFile(relativePath: item.relativePath,
                                  bytes: item.onDisk,
                                  isDirectory: false,
                                  modifiedOn: item.modifiedOn,
                                  createdOn: item.createdOn,
                                  device: item.device,
                                  inode: item.inode,
                                  linkedToAnotherName: nil,
                                  repairs: repairs))
    }

    // MARK: ── The pieces ─────────────────────────────────────────────────────────────────────────

    /// A folder on the drive, with the source folder's own permissions and metadata.
    ///
    /// Made with `mkdir` and then given its metadata by `copyfile`, rather than by
    /// `FileManager.createDirectory`: the second one applies the process's umask and would quietly
    /// widen the permissions on somebody's private folder.
    private static func makeFolder(_ item: SourceItem,
                                   at destinationPath: String,
                                   permittedBy pass: RehearsalGate.Pass) -> CopyOutcome {
        let mode = mode_t(item.mode) & 0o7777
        if mkdir(destinationPath, mode) != 0, errno != EEXIST {
            let number = errno
            return .failed(CopyFailure(relativePath: item.relativePath,
                                       code: number,
                                       why: String(cString: strerror(number)),
                                       step: "making the folder"))
        }

        // Metadata only — a folder has no data to copy, and `COPYFILE_EXCL` is deliberately absent
        // because the folder was just made by the line above.
        let flags = UInt32(COPYFILE_METADATA) | UInt32(COPYFILE_NOFOLLOW)
        _ = copyfile(item.path, destinationPath, nil, copyfile_flags_t(flags))

        var repairs: [CopyRepair] = []
        if let createdOn = item.createdOn, setCreationDate(createdOn, at: destinationPath) {
            repairs.append(.creationDate)
        }

        return .copied(CopiedFile(relativePath: item.relativePath,
                                  bytes: .zero,
                                  isDirectory: true,
                                  modifiedOn: item.modifiedOn,
                                  createdOn: item.createdOn,
                                  device: item.device,
                                  inode: item.inode,
                                  linkedToAnotherName: nil,
                                  repairs: repairs))
    }

    /// ⚠️ **Repair 4.** The second name of a hard link becomes a second name on the drive too.
    ///
    /// ⭐ It takes the `Pass` even though `run` has already been given one, and even though it is
    /// private: `link(2)` creates a file on somebody's drive, and the rule this engine is built to
    /// is that **every function that writes holds the token**, not every file.
    /// `Tests/BackupEntryPointGuardTests.swift` checks it one function at a time.
    private static func linkAgain(_ item: SourceItem,
                                  from first: String,
                                  to destinationPath: String,
                                  permittedBy pass: RehearsalGate.Pass) -> CopyOutcome {
        guard link(first, destinationPath) == 0 else {
            let number = errno
            return .failed(CopyFailure(relativePath: item.relativePath,
                                       code: number,
                                       why: String(cString: strerror(number)),
                                       step: "linking the file to its other name"))
        }
        return .copied(CopiedFile(relativePath: item.relativePath,
                                  // ⚠️ Zero, on purpose. The bytes were counted under the first
                                  // name; counting them twice would report a backup larger than
                                  // the drive it fits on.
                                  bytes: .zero,
                                  isDirectory: false,
                                  modifiedOn: item.modifiedOn,
                                  createdOn: item.createdOn,
                                  device: item.device,
                                  inode: item.inode,
                                  linkedToAnotherName: first,
                                  repairs: [.hardLink]))
    }

    /// ⚠️ **Repair 1.** `setattrlist` with `ATTR_CMN_CRTIME`, which is the only way to write a birth
    /// time, and `FSOPT_NOFOLLOW` so a symbolic link gets its own rather than its target's.
    @discardableResult
    static func setCreationDate(_ date: Date, at path: String) -> Bool {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_CRTIME)

        let whole = floor(date.timeIntervalSince1970)
        var when = timespec(tv_sec: Int(whole),
                            tv_nsec: Int((date.timeIntervalSince1970 - whole) * 1_000_000_000))

        return setattrlist(path, &list, &when, MemoryLayout<timespec>.size,
                           UInt32(FSOPT_NOFOLLOW)) == 0
    }

    /// The creation date as the filesystem holds it. For the verifier, and for a test that wants to
    /// prove repair 1 rather than assume it.
    static func creationDate(at path: String) -> Date? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        let seconds = TimeInterval(status.st_birthtimespec.tv_sec)
        let nanos = TimeInterval(status.st_birthtimespec.tv_nsec) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds + nanos)
    }

    /// ⚠️ **Repair 2.** Read the provenance attributes off the source and write them onto the copy.
    ///
    /// Returns whether anything was actually carried — a file that was never downloaded has none of
    /// these, and reporting a repair that was not needed would be noise on the record.
    @discardableResult
    static func carryProvenance(from source: String, to destination: String) -> Bool {
        var carried = false
        for name in provenanceAttributes {
            guard let value = attribute(name, of: source) else { continue }
            let written = value.withUnsafeBytes { bytes -> Int32 in
                setxattr(destination, name, bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
            }
            if written == 0 { carried = true }
        }
        return carried
    }

    /// One extended attribute's bytes, or `nil` when it is not there.
    ///
    /// `XATTR_NOFOLLOW` so a symbolic link reports its own attributes rather than its target's.
    static func attribute(_ name: String, of path: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW)
        guard read > 0 else { return nil }
        return Data(buffer.prefix(read))
    }
}
