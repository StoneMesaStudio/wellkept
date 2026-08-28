// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  Movable.swift
//  Wellkept — App/Quarantine
//
//  ⭐ **The refusal list. Every reason a file must not be touched, decided BEFORE anything moves.**
//
//  This is the first half of the engine and the more important half. `Quarantine.swift` performs
//  one syscall; this file decides whether that syscall is allowed to happen, and it decides it from
//  the file itself.
//
//  ## The rule the whole file is built on
//
//  ⚠️ **Identity, never name.** Every documented catastrophe in this field chose its target by
//  something other than identity. Adobe's updater deleted the alphabetically-first hidden folder at
//  the disk root. Pearcleaner's orphan detector matched vendor names and flagged live data. Apple
//  Music deleted 122 GB of local originals because a cloud copy was *inferred*. None of those was a
//  bug in a move; each was a bug in choosing.
//
//  So there is **no path blocklist here**, and there must never be one. A list of forbidden paths
//  goes stale every macOS release, silently — the release that renames a directory turns a guarded
//  path into an unguarded one and nothing fails until somebody's files are gone. The flags travel
//  with the file. `lstat().st_flags` and `statfs().f_flags` are the same two readings on Sonoma, on
//  Sequoia, and on whatever comes next.
//
//  ## The eight refusals, and what each one is actually preventing
//
//  1. **`.missing`** — nothing is there. Reported rather than silently skipped: a batch that
//     quietly drops what it cannot find is a batch whose count is a lie.
//  2. **`.notWhatWasAsked`** — the path resolves to a file spelled differently. **This filesystem
//     folds case AND Unicode normalisation**: `CaseTest.txt` is found at `casetest.TXT`, and an NFD
//     spelling opens the NFC file. Moving it would work; *restoring* it would recreate the file
//     under the caller's misspelling, which is a quiet corruption of somebody's folder. Callers that
//     got the path by enumerating the disk never see this refusal. `trueSpelling(of:)` is the way
//     forward for one that did not.
//  3. **`.protectedBySystem` / `.locked` / `.inADataVault` / `.notDownloaded`** — the BSD flags.
//     `SF_RESTRICTED` is System Integrity Protection expressed on the file; `UF_IMMUTABLE` is the
//     Finder's Locked checkbox; `SF_NOUNLINK` forbids the unlink half of a rename; `UF_DATAVAULT` is
//     the class macOS guards with a privacy dialog; `SF_DATALESS` means the bytes are not on this
//     Mac yet.
//  4. **`.onAReadOnlyVolume`** — `MNT_RDONLY` from `statfs`. A DMG, a locked disk, a snapshot mount.
//  5. **`.onTheSealedSystemVolume`** — ⚠️ **the trap.** `st_dev` is IDENTICAL for the sealed System
//     volume and the writable Data volume, and Foundation calls both "Macintosh HD" — even for
//     `/System/Library`. Anything that separates them by device number or display name will happily
//     conclude that `/System/Library/CoreServices` is on the same volume as your Desktop. Only
//     `statfs()` separates them: the System volume is the one mounted at `/`, and `f_mntfromname`
//     names a sealed snapshot device (`/dev/disk3s1s1`) rather than the Data device (`/dev/disk3s5`).
//  6. **`.throughASymlink`** — ⚠️ **the failure class that ends a product.** A cache folder that is
//     really a symlink to a live Application Support folder means "delete the cache" destroys the
//     real thing. The syscall backstop is `RENAME_NOFOLLOW_ANY`, which returns `ELOOP`; this check
//     is what lets the row say so in words before the button is pressed.
//  7. **`.outOfReach`** — without a privileged helper, quarantine reaches the home folder and
//     `/Applications` (root:admin, group-writable, which is why the ordinary uninstall case works)
//     and essentially nothing else. `/Library` and its LaunchDaemons are out of reach this round,
//     and the row says so instead of failing at the syscall with `EACCES`.
//  8. **`.openBy`** — ⚠️ **moving a file a running program holds open succeeds silently**, and the
//     program keeps writing into the quarantined copy. Nothing errors. It breaks hours later, on the
//     program's next open-by-path, in a way nobody connects back to Wellkept.
//
//  Plus `.inWellkeptsOwnStore`, which stops the engine being pointed at itself.
//
//  ## What this file does NOT do
//
//  It does not decide whether something *deserves* to be set aside. That is the section's judgement
//  and it is made somewhere else. This file answers one question — *can this be moved without
//  costing somebody something they cannot get back* — and answers it in words a person can read.

// MARK: - The reasons

/// Why one thing cannot be moved, in the sentence the row shows.
///
/// Every case carries the evidence that produced it, so a support conversation can be about a
/// reading rather than about a guess.
enum MoveRefusal: Sendable, Equatable, Hashable {

    /// Nothing is at that path.
    case missing

    /// The path opens a file the filesystem spells differently. Carries the true spelling.
    case notWhatWasAsked(actual: String)

    /// `SF_RESTRICTED` — System Integrity Protection, expressed on the file itself.
    case protectedBySystem

    /// `UF_IMMUTABLE`, `SF_IMMUTABLE` or `SF_NOUNLINK`. Carries which.
    case locked(flag: String)

    /// `UF_DATAVAULT` — the class macOS guards behind a privacy dialog.
    case inADataVault

    /// `SF_DATALESS` — the file is a placeholder; its bytes are not on this Mac.
    case notDownloaded

    /// `MNT_RDONLY`. Carries the volume's mount point.
    case onAReadOnlyVolume(volume: String)

    /// The sealed System volume, separated by `statfs` and nothing else. Carries the device.
    case onTheSealedSystemVolume(device: String)

    /// A parent component is a symbolic link. Carries the component.
    case throughASymlink(component: String)

    /// Outside the home folder and `/Applications`, where no helper can reach.
    case outOfReach(place: String)

    /// Inside Wellkept's own quarantine store.
    case inWellkeptsOwnStore

    /// Held open by running programs. Carries their names, already de-duplicated.
    case openBy(programs: [String])

    /// The reading itself failed. Carries the system's own words.
    case couldNotBeRead(why: String)

    /// The one line the row shows. Plain words, no jargon, no path unless the path is the point.
    var sentence: String {
        switch self {
        case .missing:
            return "There is nothing there any more."
        case .notWhatWasAsked(let actual):
            return "This Mac spells that file differently: \(actual). Wellkept will not act on a "
                 + "name that is not the file's own."
        case .protectedBySystem:
            return "macOS protects this file. Nothing that runs without your password can move it."
        case .locked(let flag):
            return "This file is locked (\(flag)). Unlock it in Finder's Get Info and try again."
        case .inADataVault:
            return "macOS keeps this in a protected area that apps are not allowed to touch."
        case .notDownloaded:
            return "This file is not really on this Mac yet — only a placeholder is. Download it "
                 + "first."
        case .onAReadOnlyVolume(let volume):
            return "\(volume) is read-only. Nothing on it can be moved."
        case .onTheSealedSystemVolume:
            return "This is part of macOS itself, on the sealed system volume. It cannot be moved, "
                 + "and it should not be."
        case .throughASymlink(let component):
            return "The folder \(component) is a shortcut to somewhere else. Acting through it "
                 + "would change the real file, which is not what anyone asked for."
        case .outOfReach(let place):
            return "Wellkept cannot reach \(place). It can act on your home folder and on "
                 + "Applications, and it asks for no password to go further."
        case .inWellkeptsOwnStore:
            return "That is already in Wellkept's quarantine."
        case .openBy(let programs):
            let list = programs.formatted(.list(type: .and))
            return programs.count == 1
                ? "\(list) has this file open. Moving it now would leave \(list) writing into a "
                  + "file that is no longer where it thinks it is. Quit it first."
                : "\(list) have this file open. Moving it now would leave them writing into a file "
                  + "that is no longer where they think it is. Quit them first."
        case .couldNotBeRead(let why):
            return "Wellkept could not read this file well enough to be sure it is safe to move: "
                 + "\(why)."
        }
    }

    /// A short tag for the ledger and for logs. **Never shown to a person** — `sentence` is.
    var code: String {
        switch self {
        case .missing:                  "missing"
        case .notWhatWasAsked:          "notWhatWasAsked"
        case .protectedBySystem:        "protectedBySystem"
        case .locked:                   "locked"
        case .inADataVault:             "inADataVault"
        case .notDownloaded:            "notDownloaded"
        case .onAReadOnlyVolume:        "onAReadOnlyVolume"
        case .onTheSealedSystemVolume:  "onTheSealedSystemVolume"
        case .throughASymlink:          "throughASymlink"
        case .outOfReach:               "outOfReach"
        case .inWellkeptsOwnStore:      "inWellkeptsOwnStore"
        case .openBy:                   "openBy"
        case .couldNotBeRead:           "couldNotBeRead"
        }
    }

    /// Whether the person can do something about it themselves. Drives whether the row offers a
    /// next step or simply states the fact.
    var theUserCanFixThis: Bool {
        switch self {
        case .locked, .openBy, .notDownloaded, .notWhatWasAsked: true
        default: false
        }
    }
}

// MARK: - What was read

/// Everything `Movable` learned about one thing, kept so that nothing downstream has to read the
/// disk a second time and get a different answer.
///
/// ⚠️ **`Ledger` builds its record from this**, which is why the identity fields are here rather
/// than gathered again at move time. A file read twice is a file that can change in between.
struct FileReading: Sendable, Equatable, Hashable {
    let path: String
    /// The path as the filesystem itself spells it, when that could be established.
    let truePath: String?
    let inode: UInt64
    let mode: UInt16
    let ownerID: UInt32
    let groupID: UInt32
    let flags: UInt32
    let bytes: Int64
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let createdOn: Date?
    let modifiedOn: Date?

    let volume: VolumeReading

    /// Whether the file lives somewhere iCloud syncs. Drives John's one-line warning, and nothing
    /// else — an iCloud file is allowed, with the warning. It is never refused.
    let isInICloud: Bool

    var url: URL { URL(filePath: path) }
    var name: String { (path as NSString).lastPathComponent }
}

/// The volume a file is on, read with `statfs` because nothing else can tell the two halves of a
/// modern boot disk apart.
struct VolumeReading: Sendable, Equatable, Hashable {
    /// `f_mntonname` — where the volume is mounted. `/System/Volumes/Data` for anything of yours.
    let mountPoint: String
    /// `f_mntfromname` — the device. ⚠️ **The only thing that separates the sealed System volume
    /// from the Data volume.** They share a device number and a display name.
    let device: String
    /// `f_flags`.
    let flags: UInt32
    /// The volume's own UUID, when it has one. Half of a file's durable identity.
    let uuid: String?

    var isReadOnly: Bool { flags & UInt32(bitPattern: MNT_RDONLY) != 0 }

    /// ⚠️ The sealed System volume is the one mounted at `/`. The Data volume never is — it is
    /// mounted at `/System/Volumes/Data` and reached through firmlinks, which is why `/Users` and
    /// `/Applications` both report `/System/Volumes/Data` here and `/System/Library` reports `/`.
    var isSealedSystem: Bool { mountPoint == "/" }

    /// Two readings are the same volume when the device matches. Mount points move; a device does
    /// not, for as long as it is mounted.
    func isSameVolume(as other: VolumeReading) -> Bool { device == other.device }
}

// MARK: - Where the engine may act

/// The places quarantine may act, and the places it may never act, as URLs rather than as a list of
/// forbidden strings.
///
/// ⚠️ **`allowed` is small on purpose and it is not an oversight.** Wellkept ships no privileged
/// helper. `/Library` is root-owned and not group-writable, so a move there fails with `EACCES` —
/// and the honest thing is to say so on the row rather than to raise an authorization dialog for a
/// tidy-up. Widening this is a conversation about shipping a helper, not a constant to edit.
struct Reach: Sendable, Equatable {
    let allowed: [String]
    let forbidden: [String]

    static func standard(home: URL = StorageManifest.home()) -> Reach {
        Reach(allowed: [home.path(percentEncoded: false), "/Applications"],
              forbidden: [StorageManifest.quarantineDirectory(home: home).path(percentEncoded: false),
                          StorageManifest.supportDirectory(home: home).path(percentEncoded: false)])
    }

    /// The plain-English name of the place a path is in, for `.outOfReach`.
    static func place(of path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return "that place" }
        switch first {
        case "System":  return "macOS itself"
        case "Library": return "the system Library folder"
        case "private", "etc", "var", "usr", "bin", "sbin", "opt", "cores":
            return "the system folders"
        case "Volumes": return parts.count > 1 ? parts[1] : "that disk"
        default:        return "/\(first)"
        }
    }
}

// MARK: - The verdict

/// The answer, and everything that went into it.
struct MovableVerdict: Sendable, Equatable {
    let path: String
    /// Empty means it can be moved. Never one refusal when several are true — a person who unlocks
    /// a file only to be told it is also on a read-only volume has been sent on an errand.
    let refusals: [MoveRefusal]
    /// `nil` only when the file could not be read at all.
    let reading: FileReading?

    var isMovable: Bool { refusals.isEmpty && reading != nil }

    /// What the row says. The refusals in order, one sentence each.
    var sentence: String? {
        refusals.isEmpty ? nil : refusals.map(\.sentence).joined(separator: " ")
    }

    var firstRefusal: MoveRefusal? { refusals.first }
}

// MARK: - The check

enum Movable {

    // ⚠️ **Taken from `sys/stat.h`, never typed out as hex.**
    //
    // They were typed out once, and one of them was wrong: `SF_NOUNLINK` is `0x00100000` and the
    // number written here was `0x00010000`, which is `SF_ARCHIVED` — one nibble apart in a column
    // of six. The effect was quiet in both directions. A file macOS genuinely refuses to unlink was
    // *not* refused, so the row promised a move that would come back `EPERM`; and a file merely
    // marked archived *was* refused, for a reason that is not a reason. Found 2026-08-28 by a test
    // against a real `SF_NOUNLINK` folder on this Mac.
    //
    // Naming the constants costs nothing and removes the whole class of mistake.
    static let restrictedFlag: UInt32   = UInt32(SF_RESTRICTED)   // SIP, expressed on the file
    static let userImmutable: UInt32    = UInt32(UF_IMMUTABLE)    // Finder's "Locked"
    static let systemImmutable: UInt32  = UInt32(SF_IMMUTABLE)
    static let noUnlink: UInt32         = UInt32(SF_NOUNLINK)
    static let dataVault: UInt32        = UInt32(UF_DATAVAULT)
    static let dataless: UInt32         = UInt32(SF_DATALESS)

    // MARK: The one call everything else makes

    /// Can this be moved, and if not, why — in words.
    ///
    /// - Parameters:
    ///   - url: the thing to check.
    ///   - reach: where the engine is allowed to act. Defaults to the home folder and
    ///     `/Applications`.
    ///   - census: a pre-taken census of open files, for a batch. ⚠️ **Pass one when checking more
    ///     than a handful of paths.** Without it every call runs `lsof` once, and a hundred thousand
    ///     junk files is a hundred thousand subprocesses. See `OpenFileCensus.take(of:)`.
    ///   - checkOpenFiles: pass `false` only for triage that will be re-checked before the move.
    ///     The move itself must never skip it.
    static func check(_ url: URL,
                      reach: Reach = .standard(),
                      census: OpenFileCensus? = nil,
                      checkOpenFiles: Bool = true) -> MovableVerdict {
        let path = url.path(percentEncoded: false)

        guard let reading = read(url) else {
            // `lstat` failing with ENOENT is "there is nothing there"; anything else is a reading we
            // could not take, and those are two different sentences.
            let why = String(cString: strerror(errno))
            return MovableVerdict(path: path,
                                  refusals: [errno == ENOENT ? .missing : .couldNotBeRead(why: why)],
                                  reading: nil)
        }

        var refusals: [MoveRefusal] = []

        // 1. Is this the file the caller means? Cheapest correctness check in the file, and the one
        //    that stops a restore recreating somebody's document under a misspelt name.
        //
        //    ⚠️ **Differing only by Unicode normalisation is not a misspelling here, and treating
        //    it as one refused ordinary files.** `URL.path` hands back NFD whatever went in, while
        //    APFS keeps whichever form it was given — so any file whose real name is NFC (anything
        //    unzipped, downloaded, or copied off a Windows or Linux share) arrived as an NFD string
        //    and was refused with "this Mac spells that file differently". The record already
        //    stores `truePath`, so the restore uses the file's own spelling either way; the refusal
        //    was costing the ordinary case and buying nothing. A difference in **case** is a real
        //    difference and is still refused — precomposing both sides leaves that one visible.
        if let truePath = reading.truePath, truePath != path,
           truePath.precomposedStringWithCanonicalMapping
               != path.precomposedStringWithCanonicalMapping {
            refusals.append(.notWhatWasAsked(actual: truePath))
        }

        // 2. The flags. All four are read from one `lstat`, so this costs nothing extra.
        if reading.flags & restrictedFlag != 0 { refusals.append(.protectedBySystem) }
        if reading.flags & userImmutable != 0 { refusals.append(.locked(flag: "locked in Finder")) }
        if reading.flags & systemImmutable != 0 { refusals.append(.locked(flag: "system immutable")) }
        if reading.flags & noUnlink != 0 { refusals.append(.locked(flag: "cannot be unlinked")) }
        if reading.flags & dataVault != 0 { refusals.append(.inADataVault) }
        if reading.flags & dataless != 0 { refusals.append(.notDownloaded) }

        // 3. The volume. ⚠️ Never `st_dev`, never the display name — see the header.
        if reading.volume.isSealedSystem {
            refusals.append(.onTheSealedSystemVolume(device: reading.volume.device))
        } else if reading.volume.isReadOnly {
            refusals.append(.onAReadOnlyVolume(volume: friendlyVolumeName(reading.volume)))
        }

        // 4. The parent chain. A symlinked component is the failure class that ends a product.
        if let crossed = symlinkInParentChain(of: path) {
            refusals.append(.throughASymlink(component: crossed))
        }

        // 5. Reach, and Wellkept's own store.
        if isInside(path, any: reach.forbidden) {
            refusals.append(.inWellkeptsOwnStore)
        } else if !isInside(path, any: reach.allowed) {
            refusals.append(.outOfReach(place: Reach.place(of: path)))
        }

        // 6. Who has it open. Last because it is the only expensive one.
        if checkOpenFiles {
            let holders = (census ?? OpenFileCensus.take(of: [url])).holders(of: path)
            if !holders.isEmpty { refusals.append(.openBy(programs: holders)) }
        }

        return MovableVerdict(path: path, refusals: refusals, reading: reading)
    }

    /// Check a batch, taking the census once.
    ///
    /// This is the entry point every section should use. One `lsof` for the whole list rather than
    /// one per file is the difference between a scan that finishes and a scan that does not.
    static func check(_ urls: [URL], reach: Reach = .standard()) -> [MovableVerdict] {
        guard !urls.isEmpty else { return [] }
        let census = OpenFileCensus.take(of: urls)
        return urls.map { check($0, reach: reach, census: census) }
    }

    // MARK: Reading one file

    /// Every reading `Movable` and `Ledger` need, taken once.
    ///
    /// `lstat` and not `stat`: a symlink is a thing in its own right, and following it here would
    /// report the flags and the volume of whatever it points at — which is exactly the confusion
    /// `RENAME_NOFOLLOW_ANY` exists to prevent.
    static func read(_ url: URL) -> FileReading? {
        let path = url.path(percentEncoded: false)
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }

        // ⚠️ **`statfs` follows a symbolic link, and there is no `lstatfs`.** A link pointing at
        // nothing therefore has no readable volume, and without this fallback `read` returned nil
        // for it — which `check` reported as `.missing`, "There is nothing there any more", about a
        // link sitting right there on the disk. Broken shortcuts are among the commonest leftovers
        // an uninstalled app leaves behind, so that was a refusal on the ordinary case.
        //
        // The parent is always the right answer: a symbolic link is an entry in its own directory,
        // so it is on that directory's volume by definition.
        guard let volume = volume(of: path)
                ?? volume(of: (path as NSString).deletingLastPathComponent)
        else { return nil }

        let isDirectory = (status.st_mode & S_IFMT) == S_IFDIR
        let isLink = (status.st_mode & S_IFMT) == S_IFLNK

        return FileReading(
            path: path,
            truePath: trueSpelling(of: path),
            inode: UInt64(status.st_ino),
            mode: UInt16(status.st_mode & 0o7777),
            ownerID: status.st_uid,
            groupID: status.st_gid,
            flags: status.st_flags,
            bytes: Int64(status.st_size),
            isDirectory: isDirectory,
            isSymbolicLink: isLink,
            createdOn: Date(timeIntervalSince1970: TimeInterval(status.st_birthtimespec.tv_sec)),
            modifiedOn: Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)),
            volume: volume,
            isInICloud: isInICloud(url))
    }

    // MARK: The volume

    /// The volume a path is on, read with `statfs`.
    ///
    /// ⚠️ **This function is the reason the engine is safe on a modern Mac.** `URLResourceKey`'s
    /// volume identifier and volume name both report the same thing for the sealed System volume and
    /// the writable Data volume — measured 2026-08-28, both "Macintosh HD", same `st_dev`, even for
    /// `/System/Library`. `f_mntonname` and `f_mntfromname` are the only readings that differ.
    static func volume(of path: String) -> VolumeReading? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }

        let mountPoint = withUnsafePointer(to: fs.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        let device = withUnsafePointer(to: fs.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }

        let uuid = (try? URL(filePath: mountPoint)
            .resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString

        return VolumeReading(mountPoint: mountPoint, device: device, flags: fs.f_flags, uuid: uuid)
    }

    /// What to call a volume in a sentence. The mount point, trimmed, because a person recognises
    /// "Backup Drive" and not `/dev/disk6s2`.
    static func friendlyVolumeName(_ volume: VolumeReading) -> String {
        if volume.mountPoint == "/" { return "the system volume" }
        if volume.mountPoint == "/System/Volumes/Data" { return "this Mac's disk" }
        return (volume.mountPoint as NSString).lastPathComponent
    }

    // MARK: Spelling

    /// The path as the filesystem itself spells it, or `nil` when that could not be established.
    ///
    /// ⚠️ **This is not pedantry.** The volume is case-insensitive and normalisation-insensitive, so
    /// `casetest.TXT` opens `CaseTest.txt` and an NFD spelling opens the NFC file. A record holding
    /// the caller's spelling is a record that restores the file under a name it never had.
    ///
    /// `F_GETPATH` on an open descriptor is the answer macOS itself uses. `O_SYMLINK` so a symlink
    /// reports its own path rather than its target's; `O_EVTONLY` as the fallback, because a file we
    /// are not allowed to read is still a file whose name we may need.
    static func trueSpelling(of path: String) -> String? {
        for flags in [O_RDONLY | O_SYMLINK | O_NONBLOCK, O_EVTONLY | O_SYMLINK, O_RDONLY] {
            let descriptor = open(path, flags)
            guard descriptor >= 0 else { continue }
            defer { close(descriptor) }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { continue }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                          as: UTF8.self)
        }
        return nil
    }

    // MARK: The parent chain

    /// The first parent component that is a symbolic link, or `nil` when the chain is clean.
    ///
    /// Walks from the root down, `lstat`-ing each prefix. The final component is deliberately NOT
    /// included: a symlink is a legitimate thing to set aside, and moving it moves the link and not
    /// its target. It is a symlink in the *middle* that turns "delete this cache" into "destroy the
    /// real folder it points at".
    static func symlinkInParentChain(of path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return nil }

        var prefix = ""
        for component in parts.dropLast() {
            prefix += "/" + component
            var status = stat()
            guard lstat(prefix, &status) == 0 else { continue }
            if (status.st_mode & S_IFMT) == S_IFLNK { return component }
        }
        return nil
    }

    // MARK: Containment

    /// Is `path` inside any of `roots`?
    ///
    /// Compared component by component, case-folded and canonically composed, because the filesystem
    /// folds both. A plain `hasPrefix` gets two things wrong at once: it folds nothing, and it says
    /// `/Users/jdsmith` is inside `/Users/jds`.
    static func isInside(_ path: String, any roots: [String]) -> Bool {
        let subject = fold(path)
        for root in roots {
            let base = fold(root)
            guard base.count <= subject.count else { continue }
            if Array(subject.prefix(base.count)) == base { return true }
        }
        return false
    }

    private static func fold(_ path: String) -> [String] {
        path.precomposedStringWithCanonicalMapping
            .split(separator: "/")
            .map { $0.lowercased() }
    }

    // MARK: iCloud

    /// Whether this lives somewhere iCloud syncs.
    ///
    /// John's answer, 2026-08-28: an iCloud file is **allowed, with a warning** — one line, *"This
    /// also removes it from your iPhone and iPad."* Refusing would block the most ordinary finding in
    /// the product on any Mac with Desktop & Documents sync switched on.
    ///
    /// ⚠️ The warning is really about the gap. For those thirty days the file is off the person's
    /// other devices while still taking up the same room on the Mac. That is the fact worth knowing
    /// before the button, and it is what the one line is for.
    static func isInICloud(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
           values.isUbiquitousItem == true {
            return true
        }
        // The resource key answers for a file iCloud is actively managing. A folder inside iCloud
        // Drive, and a file whose ubiquity has not been established, still live in the one place the
        // path can prove.
        return url.path(percentEncoded: false).contains("/Library/Mobile Documents/")
    }

    // MARK: Is there anything there

    /// Is there something at this path?
    ///
    /// ⚠️ **`lstat`, never `FileManager.fileExists`.** `fileExists` follows a symbolic link and
    /// answers about the target, so a link pointing at nothing reads as absent while it is sitting
    /// right there on the disk. Broken shortcuts are among the most ordinary leftovers an
    /// uninstalled app leaves behind — the engine has to be able to hold one, put it back, and
    /// really remove it, and every one of those needs this reading and not the other.
    static func exists(_ path: String) -> Bool {
        var status = stat()
        return lstat(path, &status) == 0
    }

    /// The one line John approved. **Used verbatim, everywhere, or not at all.**
    static let iCloudWarning = "This also removes it from your iPhone and iPad."
}

// MARK: - Who has it open

/// Which running programs hold which files open, taken once for a whole batch.
///
/// ⚠️ **The reason this exists at all**: moving a file a running program holds open **succeeds
/// silently**. The descriptor follows the inode, so the program keeps writing — into a file that is
/// now in quarantine. Nothing errors at the time. The program breaks hours later on its next
/// open-by-path, and nobody connects that to a tidy-up they ran before lunch.
///
/// ⚠️ **What this cannot see, said plainly.** `lsof` without root reports only the current user's
/// own processes. `sshd`, `mds`, and anything else running as root are invisible to it. So an empty
/// census is not proof that nothing has the file open — it is proof that nothing *of yours* does.
/// That is still the case that matters here, because everything in reach belongs to this user.
struct OpenFileCensus: Sendable, Equatable {

    /// Path, exactly as `lsof` reported it, to the programs holding it.
    private let byPath: [String: [String]]

    init(byPath: [String: [String]] = [:]) { self.byPath = byPath }

    /// The programs holding `path` open, de-duplicated and sorted. Empty when nothing of this
    /// user's does.
    func holders(of path: String) -> [String] {
        if let exact = byPath[path] { return exact }
        // `lsof` prints the filesystem's own spelling, which may not be the caller's.
        let folded = path.precomposedStringWithCanonicalMapping.lowercased()
        for (reported, programs) in byPath
        where reported.precomposedStringWithCanonicalMapping.lowercased() == folded {
            return programs
        }
        return []
    }

    var isEmpty: Bool { byPath.isEmpty }

    /// Ask `lsof` once about a whole list.
    ///
    /// Chunked at 200 paths per call so a large batch cannot overrun the argument list, and given a
    /// short deadline each time: `lsof` stats every mount, and a stalled network volume would
    /// otherwise hang a scan for as long as the mount takes to time out.
    static func take(of urls: [URL], timeout: TimeInterval = 10) -> OpenFileCensus {
        let tool = URL(filePath: "/usr/sbin/lsof")
        guard !urls.isEmpty, FileManager.default.isExecutableFile(atPath: tool.path) else {
            return OpenFileCensus()
        }

        var found: [String: Set<String>] = [:]
        for chunk in stride(from: 0, to: urls.count, by: 200).map({
            Array(urls[$0..<min($0 + 200, urls.count)])
        }) {
            // -n and -P: no DNS, no port-name lookups, both of which can block. -w: no warnings for
            // the paths nothing has open, which is nearly all of them. -F pcn: the machine-readable
            // form — one field per line, tagged.
            let arguments = ["-n", "-P", "-w", "-F", "pcn", "--"]
                + chunk.map { $0.path(percentEncoded: false) }
            guard let output = run(tool, arguments: arguments, timeout: timeout) else { continue }

            var command = ""
            for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
                let body = String(line.dropFirst())
                switch line.first {
                case "c": command = body
                case "n" where !command.isEmpty: found[body, default: []].insert(command)
                default: break
                }
            }
        }

        return OpenFileCensus(byPath: found.mapValues { $0.sorted() })
    }

    /// ⚠️ **`lsof` exits non-zero when it finds nothing**, which is the ordinary case. So this
    /// deliberately does not check the termination status — only whether there is output to read.
    /// The runner in `ReachableReader` requires status 0 and would report every clean file as a
    /// failed reading.
    private static func run(_ tool: URL, arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        let watchdog = ProcessWatchdog(process)
        let killer = DispatchWorkItem { watchdog.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        // Drained before `waitUntilExit`: a child filling the pipe while the parent waits for it to
        // exit is a deadlock, and it only appears on the machine with the most to say.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        return String(data: data, encoding: .utf8)
    }
}

/// One reference, read from two threads, and all either of them does is ask whether the process is
/// still running.
private final class ProcessWatchdog: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() { if process.isRunning { process.terminate() } }
}
