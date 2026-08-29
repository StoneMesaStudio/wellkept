// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  Destination.swift
//  Wellkept — App/Backup/Engine
//
//  ⭐ **The drive a person chose, read and judged. Wellkept never makes one.**
//
//  ## What this file is allowed to do to a drive: nothing
//
//  ⛔ It does not erase, format, partition, repartition, mount, unmount, eject, rename or create a
//  volume. It runs `statfs` and, when it needs to know about encryption, `diskutil info` — which
//  reads and prints. There is no code path here that changes a drive's shape, and there must never
//  be one: the moment an app that is allowed to erase disks has a bug in *choosing*, somebody's
//  other drive is gone. See `whatWellkeptNeverDoes`, which is on the screen and not just here.
//
//  **The person prepares the drive in Disk Utility.** That is one instruction, it is Apple's own
//  tool, and it hands us the entire encryption story for free: erasing as **APFS (Encrypted)** asks
//  for a password and encrypts everything written to that drive from then on, with no code from us,
//  no key for us to lose, and nothing for us to get wrong. An encryption feature we did not write
//  is the best encryption feature available to this app.
//
//  ## Why the format is checked and said out loud
//
//  A backup on the wrong format is the quiet failure this section exists to prevent. Copy a home
//  folder onto an exFAT drive — the format every drive arrives from the shop with — and it lands
//  looking complete: right names, right sizes, right dates. What it does **not** have is ownership,
//  permissions, symbolic links, extended attributes, resource forks or the tag that records where a
//  file came from. Nothing errors. It is discovered on restore.
//
//  So the format is a `FormatVerdict` and not a boolean, because the three answers are genuinely
//  different: APFS is right, HFS+ works and is old, and everything else loses things a restore
//  needs. A person handed "unsupported" learns nothing; a person told *what is lost* can decide.
//
//  ## The refusals that are about the drive rather than the format
//
//  - **The startup disk.** A backup of your files onto the disk holding your files is not a backup
//    of anything. It is refused before the format is even considered.
//  - **A network share.** SMB and NFS hand back whatever the server feels like about ownership and
//    extended attributes, and the copy cannot be checked against the source in any way we would
//    stand behind. `MNT_LOCAL` clear is the reading, the same one `ScanPolicy` uses.
//  - **Read-only.** `MNT_RDONLY`. A disk image, a locked drive, a snapshot mount.
//
//  ⚠️ **Nothing in this file is a promise that a restore works.** `RehearsalGate` holds that, and
//  every writer in this engine takes a `RehearsalGate.Pass`. A drive that passes every check here
//  is a drive that is *shaped* right — it is not evidence that anybody has ever restored from one.

// MARK: - The format

/// What a drive is formatted as, and what that costs.
///
/// Read from `statfs().f_fstypename`, which is the kernel's own name for the filesystem and is not
/// localised, not guessed, and not derived from the drive's label.
enum DriveFormat: Sendable, Equatable, Hashable {

    /// Apple's current format. Everything a copy needs, plus clones, plus encryption at rest when
    /// the person erased it as **APFS (Encrypted)**.
    case apfs

    /// The old Mac format. It holds ownership, permissions, extended attributes, resource forks and
    /// creation dates — everything a restore needs. It is simply not what Disk Utility offers first
    /// any more.
    case hfsPlus

    /// The format nearly every drive is sold with. ⚠️ **Loses the most.**
    case exFAT

    /// Older Windows formats, and the 4 GB per-file ceiling that comes with them.
    case fat

    /// A server, not a drive. Carries the kernel's name for it.
    case networkShare(String)

    /// Something else. Carries the kernel's own name rather than pretending to recognise it.
    case other(String)

    /// The kernel's `f_fstypename`, turned into one of the above.
    ///
    /// ⚠️ The network case is decided by `MNT_LOCAL` being clear and **not** by the type name: a
    /// share can be mounted with a type name we have never heard of, and the flag is the reading
    /// that is true for all of them.
    static func read(typeName: String, isNetwork: Bool) -> DriveFormat {
        if isNetwork { return .networkShare(typeName) }
        switch typeName.lowercased() {
        case "apfs":            return .apfs
        case "hfs":             return .hfsPlus
        case "exfat":           return .exFAT
        case "msdos", "vfat":   return .fat
        default:                return .other(typeName)
        }
    }

    /// What a person would call it.
    var name: String {
        switch self {
        case .apfs:                  "APFS"
        case .hfsPlus:               "Mac OS Extended"
        case .exFAT:                 "exFAT"
        case .fat:                   "MS-DOS (FAT)"
        case .networkShare(let raw): "a network share (\(raw))"
        case .other(let raw):        raw
        }
    }

    /// ⭐ The three-way answer. Not a boolean, because "workable but old" is a real state and
    /// telling somebody their perfectly good HFS+ drive is unsupported would be false.
    var verdict: FormatVerdict {
        switch self {
        case .apfs:                        .right
        case .hfsPlus:                     .workable
        case .exFAT, .fat, .other:         .wrong
        case .networkShare:                .wrong
        }
    }

    /// **What is lost on this format, in losses rather than in filesystem vocabulary.** `nil` where
    /// nothing is lost.
    var whatIsLost: String? {
        switch self {
        case .apfs:
            return nil
        case .hfsPlus:
            return nil
        case .exFAT, .fat:
            return "This format cannot hold who owns a file, what it is allowed to do, shortcuts, "
                 + "or the tag that records where a file was downloaded from. A copy onto it looks "
                 + "finished and comes back missing all of that."
        case .networkShare:
            return "A drive on the network decides for itself what it keeps of a file, so nothing "
                 + "here can promise that what comes back is what went in."
        case .other(let raw):
            return "Wellkept does not know what \(raw) keeps of a file, so it will not tell you a "
                 + "copy onto it is safe."
        }
    }
}

/// Whether the drive is formatted the way this engine needs.
enum FormatVerdict: String, Sendable, Equatable, CaseIterable {

    /// APFS. What Disk Utility offers first, and what the instruction says to choose.
    case right

    /// It will hold everything, it is just not the current format.
    case workable

    /// Something a restore needs does not survive on it.
    case wrong

    var label: String {
        switch self {
        case .right:    "APFS — the right format"
        case .workable: "Older, and it will work"
        case .wrong:    "The wrong format for a backup"
        }
    }

    var mayBeUsed: Bool { self != .wrong }
}

// MARK: - What was read about a drive

/// Everything read about one drive, taken once so nothing downstream reads the disk again and gets
/// a different answer.
struct DriveReading: Sendable, Equatable, Hashable {

    /// The name a person sees in the Finder — the last part of the mount point.
    let name: String

    /// `f_mntonname`.
    let mountPoint: String

    /// `f_mntfromname`. ⚠️ The only thing that separates two volumes that share a device number.
    let device: String

    let format: DriveFormat

    let isReadOnly: Bool

    let isNetwork: Bool

    /// Whether this is the disk the home folder is on. A copy of your files onto the disk holding
    /// your files is not a backup.
    let isTheSameDiskAsYourFiles: Bool

    /// Whether it is the volume mounted at `/` — macOS itself.
    let isTheStartupDisk: Bool

    let capacity: SizeOnDisk
    let free: SizeOnDisk

    /// ⚠️ **Whether the drive is encrypted at rest**, from `diskutil info`. `nil` means we did not
    /// establish it, which is reported as not established and never as "no". The whole encryption
    /// story is the person choosing **APFS (Encrypted)** in Disk Utility; this reading is how the
    /// screen can tell them whether they did.
    let encryptedAtRest: Bool?

    var volumeReading: VolumeReading {
        VolumeReading(mountPoint: mountPoint,
                      device: device,
                      flags: isReadOnly ? UInt32(bitPattern: MNT_RDONLY) : 0,
                      uuid: nil)
    }

    /// The details for the Options block.
    var detailPairs: [DetailPair] {
        var pairs = [DetailPair("Drive", name),
                     DetailPair("Format", format.name),
                     DetailPair("Room on it", "\(free.text) free of \(capacity.text)")]
        switch encryptedAtRest {
        case .some(true):  pairs.append(DetailPair("Encrypted", "Yes — it was erased as APFS (Encrypted)"))
        case .some(false): pairs.append(DetailPair("Encrypted", "No. Erasing it as APFS (Encrypted) would encrypt it, and Wellkept plays no part in that."))
        case .none:        pairs.append(DetailPair("Encrypted", "Not established"))
        }
        return pairs
    }
}

// MARK: - Why a drive was refused

/// Why this drive cannot be backed up to, in the sentence the screen shows.
enum DestinationRefusal: Sendable, Equatable, Hashable {

    /// Nothing is mounted there. The ordinary case: the drive is unplugged.
    case notConnected(name: String)

    /// The path is not a mount point of its own — a folder on some other disk.
    ///
    /// ⚠️ Migration Assistant refuses a backup that sits in a folder rather than being a volume of
    /// its own. That is not the reason for this refusal, but it is the reason the sentence says
    /// "the drive itself" rather than "somewhere on a drive".
    case notADriveOfItsOwn(path: String)

    /// The startup disk.
    case theStartupDisk

    /// The same disk the home folder is on.
    case theSameDiskAsYourFiles(name: String)

    /// On the network.
    case onTheNetwork(name: String)

    /// `MNT_RDONLY`.
    case readOnly(name: String)

    /// The format loses something a restore needs. Carries the format so the sentence can say what.
    case wrongFormat(name: String, format: DriveFormat)

    /// Not enough room. Carries both figures, because "not enough room" without them is useless.
    case notEnoughRoom(needs: SizeOnDisk, free: SizeOnDisk)

    /// The reading failed. Carries the system's own words.
    case couldNotBeRead(path: String, why: String)

    var sentence: String {
        switch self {
        case .notConnected(let name):
            return "\(name) is not connected. Plug it in and Wellkept will pick it up."
        case .notADriveOfItsOwn(let path):
            return "\(path) is a folder on another disk, not the drive itself. Choose the drive."
        case .theStartupDisk:
            return "That is the disk macOS is running from. A copy of your files onto the disk your "
                 + "files are already on is not a backup of anything."
        case .theSameDiskAsYourFiles(let name):
            return "\(name) is the same disk your home folder is on. If that disk fails, both "
                 + "copies go with it."
        case .onTheNetwork(let name):
            return "\(name) is on the network rather than plugged into this Mac. "
                 + (DriveFormat.networkShare("").whatIsLost ?? "")
        case .readOnly(let name):
            return "\(name) is read-only. Nothing can be written to it."
        case .wrongFormat(let name, let format):
            return "\(name) is formatted as \(format.name). "
                 + (format.whatIsLost ?? "")
                 + " " + Destination.howToPrepareADrive
        case .notEnoughRoom(let needs, let free):
            return "This backup needs about \(needs.text) and \(free.text) is free on the drive. "
                 + "Wellkept will not start a copy it knows cannot finish."
        case .couldNotBeRead(let path, let why):
            return "Wellkept could not read \(path) well enough to be sure it is safe to write "
                 + "there: \(why)."
        }
    }

    /// A short tag for the record. **Never shown to a person** — `sentence` is.
    var code: String {
        switch self {
        case .notConnected:            "notConnected"
        case .notADriveOfItsOwn:       "notADriveOfItsOwn"
        case .theStartupDisk:          "theStartupDisk"
        case .theSameDiskAsYourFiles:  "theSameDiskAsYourFiles"
        case .onTheNetwork:            "onTheNetwork"
        case .readOnly:                "readOnly"
        case .wrongFormat:             "wrongFormat"
        case .notEnoughRoom:           "notEnoughRoom"
        case .couldNotBeRead:          "couldNotBeRead"
        }
    }

    /// Whether the person can put it right themselves, which decides whether the row offers a next
    /// step or simply states the fact.
    var theUserCanFixThis: Bool {
        switch self {
        case .notConnected, .wrongFormat, .notEnoughRoom, .theSameDiskAsYourFiles,
             .theStartupDisk, .onTheNetwork, .notADriveOfItsOwn:
            true
        case .readOnly, .couldNotBeRead:
            false
        }
    }
}

/// The answer about one drive.
struct DriveVerdict: Sendable, Equatable {
    let path: String
    /// Empty means it may be written to. Never one refusal when several are true.
    let refusals: [DestinationRefusal]
    /// `nil` only when the drive could not be read at all.
    let reading: DriveReading?

    var mayBeUsed: Bool { refusals.isEmpty && reading != nil }

    var sentence: String? {
        refusals.isEmpty ? nil : refusals.map(\.sentence).joined(separator: " ")
    }

    var firstRefusal: DestinationRefusal? { refusals.first }
}

// MARK: - Reading a drive

/// ⭐ **The one place a backup destination is judged.**
///
/// ⚠️ This enum reads. It never writes. The write side of this engine is `BackupRun`, and it takes a
/// `RehearsalGate.Pass` that only `RehearsalGate` can produce.
enum Destination {

    // MARK: ── The words ──────────────────────────────────────────────────────────────────────────

    /// ⭐ **The one instruction, and the whole encryption story with it.**
    static let howToPrepareADrive = """
        Open Disk Utility, select the drive, press Erase, and choose APFS. If you choose \
        APFS (Encrypted) it asks you for a password, and from then on everything on that drive is \
        encrypted — Wellkept has no part in that and never sees the password.
        """

    /// ⛔ **What this app will not do to a drive.** On the screen, not only in this comment.
    static let whatWellkeptNeverDoes = """
        Wellkept never erases, formats, partitions, mounts, unmounts or renames a drive. It writes \
        files into one folder on a drive you prepared yourself and chose yourself.
        """

    /// ⚠️ **The promise, and it is not the other one.**
    ///
    /// Taken from `Backup.whatItPromises` rather than written again here, so the destination screen
    /// and the section face cannot drift apart.
    static let whatArrivesOnTheDrive = Backup.whatItPromises

    /// ⚠️ Migration Assistant refuses a backup that sits inside a folder rather than being a volume
    /// of its own — which is why the destination is the drive and not a folder somebody picked.
    ///
    /// It is also **unverified** that Migration Assistant accepts a data-only volume at all, with
    /// Apple's own string arguing against it. This sentence therefore describes what Wellkept does,
    /// and claims nothing about what Migration Assistant will do with it.
    static let whyTheWholeDriveAndNotAFolder = """
        Wellkept uses the whole drive rather than a folder on one. A folder full of your files is \
        still readable in the Finder either way; a drive is the only shape anything else on macOS \
        has a chance of recognising.
        """

    /// The folder Wellkept writes into, at the root of the chosen drive.
    ///
    /// Named in plain words because a person browsing the drive in the Finder should be able to
    /// tell what it is without us. ⛔ Never a dot-folder: an unexplained hidden folder at a disk
    /// root is the exact shape of the accident that started the refusal list in `Movable`.
    static let folderName = "Wellkept Backup"

    /// Where the backup lives on a given drive.
    static func folder(on driveMountPoint: String) -> URL {
        URL(filePath: driveMountPoint).appending(path: folderName)
    }

    // MARK: ── ⭐ The one call ─────────────────────────────────────────────────────────────────────

    /// **Read a drive and judge it.** Reads only.
    ///
    /// - Parameters:
    ///   - path: the drive's mount point, as the person chose it.
    ///   - home: the home folder, so "the same disk as your files" can be answered.
    ///   - needs: how much the backup is expected to want, when that is known. `nil` skips the room
    ///     check — a first look at a drive happens before anything has been measured.
    ///   - encryption: how to find out whether the drive is encrypted. Injected so a test never
    ///     runs a subprocess.
    static func judge(_ path: String,
                      home: URL = StorageManifest.home(),
                      needs: SizeOnDisk? = nil,
                      encryption: (String) -> Bool? = { EncryptionReading.ofVolume(at: $0) })
    -> DriveVerdict {

        guard Movable.exists(path) else {
            return DriveVerdict(path: path,
                                refusals: [.notConnected(name: (path as NSString).lastPathComponent)],
                                reading: nil)
        }

        guard let volume = Movable.volume(of: path) else {
            let why = String(cString: strerror(errno))
            return DriveVerdict(path: path, refusals: [.couldNotBeRead(path: path, why: why)],
                                reading: nil)
        }

        let isNetwork = ScanPolicy.isNetwork(volume)
        let typeName = fileSystemTypeName(of: path) ?? "unknown"
        let format = DriveFormat.read(typeName: typeName, isNetwork: isNetwork)
        let name = Movable.friendlyVolumeName(volume)

        let homeVolume = Movable.volume(of: home.path(percentEncoded: false))
        let sameDisk = homeVolume.map { volume.isSameVolume(as: $0) } ?? false

        let space = roomOn(path)
        let reading = DriveReading(name: name,
                                   mountPoint: volume.mountPoint,
                                   device: volume.device,
                                   format: format,
                                   isReadOnly: volume.isReadOnly,
                                   isNetwork: isNetwork,
                                   isTheSameDiskAsYourFiles: sameDisk,
                                   isTheStartupDisk: volume.isSealedSystem,
                                   capacity: space.capacity,
                                   free: space.free,
                                   encryptedAtRest: isNetwork ? nil : encryption(path))

        var refusals: [DestinationRefusal] = []

        // ⚠️ The path has to be the drive itself. A folder somebody picked inside another disk is
        // not a destination, and the mount point is the reading that settles it.
        if volume.mountPoint != canonical(path) {
            refusals.append(.notADriveOfItsOwn(path: path))
        }

        if volume.isSealedSystem { refusals.append(.theStartupDisk) }
        else if sameDisk { refusals.append(.theSameDiskAsYourFiles(name: name)) }

        if isNetwork { refusals.append(.onTheNetwork(name: name)) }
        if volume.isReadOnly { refusals.append(.readOnly(name: name)) }

        if !format.verdict.mayBeUsed, !isNetwork {
            refusals.append(.wrongFormat(name: name, format: format))
        }

        if let needs, needs > space.free {
            refusals.append(.notEnoughRoom(needs: needs, free: space.free))
        }

        return DriveVerdict(path: path, refusals: refusals, reading: reading)
    }

    // MARK: ── The readings ───────────────────────────────────────────────────────────────────────

    /// `f_fstypename` — the kernel's own name for the filesystem, not localised and not guessed.
    static func fileSystemTypeName(of path: String) -> String? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        return withUnsafePointer(to: fs.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
    }

    /// How big the drive is and how much is free.
    ///
    /// ⚠️ `f_bavail`, not `f_bfree`: the second counts blocks reserved for root, which an ordinary
    /// program cannot have. Promising space that only root can use is how a copy fills a disk and
    /// stops halfway.
    static func roomOn(_ path: String) -> (capacity: SizeOnDisk, free: SizeOnDisk) {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return (.zero, .zero) }
        let block = Int64(fs.f_bsize)
        return (SizeOnDisk(Int64(fs.f_blocks) * block), SizeOnDisk(Int64(fs.f_bavail) * block))
    }

    /// The path as the filesystem spells it, symlinks resolved. `/Volumes/Backup` handed in with a
    /// trailing slash must compare equal to the mount point.
    static func canonical(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else {
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

// MARK: - Is the drive encrypted

/// ⚠️ **Whether a volume is encrypted at rest, read from `diskutil info`.**
///
/// `diskutil` is the only unprivileged reading of this, and `info` prints — it changes nothing. ⛔
/// No other `diskutil` verb is used anywhere in this app, and none may be added: `eraseVolume`,
/// `apfs`, `mount` and `unmount` all change somebody's drive, which is the one thing this engine
/// promises never to do.
///
/// The parsing is separated from the running so a test can exercise it against a fixture rather
/// than against whatever is plugged into the machine running the suite.
enum EncryptionReading {

    /// `nil` means not established — reported as not established, **never as "no"**. A drive we
    /// could not ask about is not a drive we know to be unencrypted, and telling somebody their
    /// backup is unencrypted when it is not is a reason to distrust everything else on the screen.
    static func ofVolume(at path: String, timeout: TimeInterval = 10) -> Bool? {
        let tool = URL(filePath: "/usr/sbin/diskutil")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }
        guard let output = run(tool, arguments: ["info", "-plist", path], timeout: timeout) else {
            return nil
        }
        return encrypted(inPropertyList: output)
    }

    /// The parse, on its own so it can be tested.
    ///
    /// Two keys, because Apple has used both: `Encryption` on APFS volumes and `FilesystemUserVisible
    /// Name` carrying "(Encrypted)" on some. Either is enough; neither present is `nil`.
    static func encrypted(inPropertyList data: Data) -> Bool? {
        guard let plist = try? PropertyListSerialization
            .propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }

        if let flag = plist["Encryption"] as? Bool { return flag }
        if let flag = plist["FileVault"] as? Bool { return flag }
        if let visible = plist["FilesystemUserVisibleName"] as? String {
            return visible.localizedCaseInsensitiveContains("encrypted")
        }
        return nil
    }

    /// The same shape as every other subprocess in this app: no shell, a deadline, the pipe drained
    /// before the wait so a chatty child cannot deadlock the parent.
    private static func run(_ tool: URL, arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        let box = TerminationBox(process)
        let killer = DispatchWorkItem { box.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }
}

/// One reference read from two threads, and all either does is ask whether the process is running.
private final class TerminationBox: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() { if process.isRunning { process.terminate() } }
}
