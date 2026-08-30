// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  BackupSource.swift
//  Wellkept — App/Backup/Engine
//
//  ⭐ **What gets copied, what gets named and skipped, and what is refused outright.**
//
//  ## The source is the home folder, and that was measured rather than chosen
//
//  Inside the home folder, **586,642 of 586,643 files are the user's own** — so a copy there is
//  byte-and-metadata perfect and needs no privileges at all. Outside it, **320,465 of 361,714 files
//  are root-owned**, and an unprivileged program cannot set an owner: `lchown` returns `EPERM`. A
//  whole-Mac backup is therefore not a thing this app can make, at any effort, without a privileged
//  helper it does not ship.
//
//  ⚠️ **So the promise is "all your files" and it is never `Backup.promiseWeDoNotMake`.** Nothing
//  in this file, or anything reading it, may imply otherwise.
//
//  ## The three ways something does not get copied, and only two of them are gaps
//
//  1. **In iCloud and not on this disk.** 72.2 GB of one measured Mac's files are placeholders —
//     65.4 GB of a media folder under Desktop & Documents syncing, plus Google Drive. Copying them means
//     **downloading 72 GB onto a Mac with 95 GB free**, over somebody's own internet, to back up
//     files that already have a second copy in the cloud. They are **named and skipped**, never
//     downloaded by default. ⚠️ Time Machine has exactly the same hole and never mentions it; this
//     section says it every single run.
//  2. **A cloud provider's folder we refuse to walk at all.** ⛔
//     `~/Library/CloudStorage/GoogleDrive-…` is **indistinguishable from a local folder by every
//     test this app uses** — same filesystem, same device number as `~/Documents`, no ubiquity
//     flag, no dataless flag. Reading it during the research timed out and killed a scan, and had
//     it succeeded it would have pulled the whole Drive down. It is detected **by name** and
//     refused, which is the one place in this engine where a name is the evidence. See `whyANameIsTheEvidenceHere`.
//  3. **A thing a copy means nothing for** — a socket, a device node, a named pipe. Not a gap and
//     not a loss.
//
//  Only the first counts as something worth telling a person about, and none of the three counts
//  against completeness. `NotCopied.countsAgainstCompleteness` is where that is decided, and it is
//  decided in `WellkeptCore` so every screen gets the same answer.
//
//  ## ⚠️ The failure that is silent, and is neither of the above
//
//  **Without Full Disk Access a backup contains no mail, no messages, no photos, no contacts, no
//  Safari data and no Trash — not partial, nothing — and macOS refuses SILENTLY, with no error.**
//  Enumerating those folders comes back empty rather than refused. So this file does not try to
//  detect it by walking; it asks `FullDiskAccess.isGranted` before the run and refuses to call the
//  result complete without it. `BackupCompleteness` is the type that holds that line.
//
//  Nothing in this file writes. The writers are `CopyOne` and `BackupRun`, and both take a
//  `RehearsalGate.Pass`.

// MARK: - What one thing in the source is

/// One item found in the source, with everything needed to decide what to do with it — read once.
struct SourceItem: Sendable, Equatable, Hashable {

    /// The path as the filesystem spells it.
    let path: String

    /// Where it goes, relative to the backup folder. Always the path with the home folder's own
    /// prefix removed, so a backup is browsable in the Finder and looks like the home folder.
    let relativePath: String

    let isDirectory: Bool
    let isSymbolicLink: Bool

    /// ⚠️ `SF_DATALESS`. **The reading that decides whether a file is really here** — never the
    /// return code of copying it. See `Backup.whyTheReturnCodeIsNotEvidence`.
    let isCloudOnly: Bool

    /// `st_size` — what it claims to weigh.
    let apparentBytes: Int64

    /// `st_blocks * 512` — what it actually occupies. ⚠️ Smaller than `apparentBytes` means the
    /// file is **sparse**, and copying it the ordinary way inflates it to its apparent size. A
    /// 500 MB sparse file became 500 MB of real blocks when it was measured.
    let allocatedBytes: Int64

    /// How many names this inode has. ⚠️ **Greater than one means a hard link**, and `copyfile`
    /// ignores them — copying both names makes two files where there was one, doubling the space
    /// and breaking the "change one, change both" the person relied on.
    let linkCount: UInt16

    /// The identity of the file on its volume, which is how the two names of a hard link are
    /// recognised as one file.
    let device: Int32
    let inode: UInt64

    let mode: UInt16
    let createdOn: Date?
    let modifiedOn: Date?

    var name: String { (path as NSString).lastPathComponent }

    /// Whether the file is sparse — it claims more than it occupies, by more than one block.
    var isSparse: Bool { allocatedBytes + 4096 < apparentBytes }

    /// Whether it has a second name somewhere.
    var isHardLinked: Bool { linkCount > 1 && !isDirectory }

    /// The size worth reporting: what it occupies. ⚠️ Never the apparent size, which was wrong by
    /// 56% on this Mac.
    var onDisk: SizeOnDisk { SizeOnDisk(allocatedBytes) }
}

// MARK: - Why something was left out

/// Why one item in the source is not being copied, with the reason a person reads.
///
/// ⚠️ Every case maps to a `NotCopied`, which is where "does this count against completeness" is
/// decided — in `WellkeptCore`, once, so no screen can answer it differently.
enum SourceExclusion: Sendable, Equatable, Hashable {

    /// `SF_DATALESS`. In iCloud, not on this disk. Named, skipped, never downloaded.
    case inTheCloudOnly

    /// ⛔ A cloud provider's folder that looks exactly like a local one. Carries the provider.
    case aCloudProviderFolder(provider: String)

    /// The person excluded it.
    case excludedByYou(rule: String)

    /// A socket, a device node, a named pipe.
    case notACopyableThing(kind: String)

    /// The destination drive itself, reached through the source. The engine pointed at its own
    /// output.
    case theBackupItself

    /// A different volume from the home folder — another disk mounted inside it, a disk image.
    case anotherVolume(name: String)

    var whyItWasNotCopied: NotCopied {
        switch self {
        case .inTheCloudOnly, .aCloudProviderFolder: .inTheCloudOnly
        case .excludedByYou:                         .excludedByYou
        case .notACopyableThing:                     .notACopyableThing
        case .theBackupItself, .anotherVolume:       .excludedByYou
        }
    }

    var sentence: String {
        switch self {
        case .inTheCloudOnly:
            return "This is in iCloud and not on this disk. Copying it would mean downloading it "
                 + "first, so Wellkept names it and leaves it where it is."
        case .aCloudProviderFolder(let provider):
            return "\(provider) keeps files that look like they are on this Mac and are not. "
                 + "Reading that folder would download all of it, so Wellkept does not go in."
        case .excludedByYou(let rule):
            return "You left this out (\(rule))."
        case .notACopyableThing(let kind):
            return "This is \(kind), which a copy does not mean anything for."
        case .theBackupItself:
            return "That is the backup drive. Wellkept does not copy the backup into itself."
        case .anotherVolume(let name):
            return "\(name) is a different disk, mounted inside your home folder. Wellkept backs up "
                 + "one disk."
        }
    }

    /// ⭐ Whether a person should be told about this one on the face. Only the cloud cases: the
    /// others are either their own decision or not a loss at all, and a run that lists a socket it
    /// declined to copy has buried the one line that mattered.
    var worthSaying: Bool {
        switch self {
        case .inTheCloudOnly, .aCloudProviderFolder: true
        case .excludedByYou, .notACopyableThing, .theBackupItself, .anotherVolume: false
        }
    }
}

// MARK: - The rules

/// ⭐ **What the source is, and where a walk stops. Decided once, here.**
///
/// The shape is deliberately the same as `ScanPolicy`: one type answers "may I go in here", every
/// walk asks it, and nothing carries its own private idea of where to stop. Two policies means only
/// one of them gets reviewed.
struct SourceRules: Sendable, Equatable {

    /// The home folder. The whole source, and nothing above it.
    let home: URL

    /// Where the backup is being written, so the walk never descends into its own output. `nil`
    /// while nothing has been chosen.
    let destinationFolder: String?

    /// Paths, relative to the home folder, the person chose to leave out.
    let excludedByTheUser: [String]

    /// The volume the home folder is on, read once at the start rather than per entry.
    let volume: VolumeReading?

    init(home: URL = StorageManifest.home(),
         destinationFolder: String? = nil,
         excludedByTheUser: [String] = [],
         volume: VolumeReading? = nil) {
        self.home = home
        self.destinationFolder = destinationFolder
        self.excludedByTheUser = excludedByTheUser
        self.volume = volume ?? Movable.volume(of: home.path(percentEncoded: false))
    }

    // MARK: ── ⛔ The one place a name is the evidence ────────────────────────────────────────────

    /// ⛔ **Cloud providers whose folders are indistinguishable from local ones.**
    ///
    /// Matched as a **prefix of the folder's own name** inside `~/Library/CloudStorage`, which is
    /// where macOS's File Provider extensions put themselves. `GoogleDrive-someone@example.com` and
    /// `Dropbox` are folder names, not paths, so the match survives somebody having two accounts.
    static let cloudProviderFolders: [(prefix: String, provider: String)] = [
        ("GoogleDrive", "Google Drive"),
        ("Dropbox", "Dropbox"),
        ("OneDrive", "OneDrive"),
        ("Box", "Box"),
        ("pCloud", "pCloud"),
    ]

    /// ⚠️ **Why a name is the right evidence here and nowhere else in this app.**
    ///
    /// `Movable`'s rule is identity, never name, and it is right: a blocklist that *permits* goes
    /// stale silently and costs somebody their files. This list runs the other way. It only ever
    /// **subtracts** from what is copied, so a stale entry costs somebody a folder that had a
    /// second copy in the cloud anyway. The two failures are not symmetrical.
    ///
    /// And there is no other reading available. Measured 2026-08-29: the Google Drive folder is on
    /// the same filesystem and the same device as `~/Documents`, carries no ubiquity flag and no
    /// dataless flag, and reading it timed out and killed the scan. Every test this app has says it
    /// is an ordinary local folder. Its name is the only thing that is not a lie.
    static let whyANameIsTheEvidenceHere = """
        Google Drive's folder looks exactly like an ordinary folder on your Mac by every reading \
        Wellkept can take. The only way to know it is not is its name, so that is what Wellkept \
        uses — and it uses it only to leave the folder alone, never to act on it.
        """

    /// The provider whose folder this is, if it is one.
    func cloudProvider(of url: URL) -> String? {
        let cloudStorage = home.appending(path: "Library/CloudStorage").path(percentEncoded: false)
        let path = url.path(percentEncoded: false)
        guard Movable.isInside(path, any: [cloudStorage]) else { return nil }

        // The folder directly inside CloudStorage is the provider's; anything deeper is inside it.
        let parts = path.split(separator: "/").map(String.init)
        let base = cloudStorage.split(separator: "/").count
        guard parts.count > base else { return nil }
        let folder = parts[base]
        for entry in Self.cloudProviderFolders
        where folder.lowercased().hasPrefix(entry.prefix.lowercased()) {
            return entry.provider
        }
        return nil
    }

    // MARK: ── ⭐ The one question every walk asks ────────────────────────────────────────────────

    /// **May the walk go into this folder, and if not, why.**
    ///
    /// Returns `nil` when it may. The order is deliberate: the cloud provider first, because for
    /// that one the *touch* is the harm — reading the folder is what starts the download.
    func mayDescend(into url: URL) -> SourceExclusion? {
        let path = url.path(percentEncoded: false)

        if let provider = cloudProvider(of: url) { return .aCloudProviderFolder(provider: provider) }

        if let destinationFolder, Movable.isInside(path, any: [destinationFolder]) {
            return .theBackupItself
        }

        if let rule = exclusionRule(for: path) { return .excludedByYou(rule: rule) }

        // A different volume mounted inside the home folder. One backup is one disk.
        if let volume, let here = Movable.volume(of: path), !here.isSameVolume(as: volume) {
            return .anotherVolume(name: Movable.friendlyVolumeName(here))
        }

        return nil
    }

    /// **Should this file be copied, and if not, why.** `nil` means copy it.
    ///
    /// ⚠️ **`isCloudOnly` is read from the file's own `SF_DATALESS` flag**, taken in the same
    /// `lstat` as everything else. It is never inferred from a size, a folder, or the result of trying.
    func mayCopy(_ item: SourceItem) -> SourceExclusion? {
        if item.isCloudOnly { return .inTheCloudOnly }
        if let provider = cloudProvider(of: URL(filePath: item.path)) {
            return .aCloudProviderFolder(provider: provider)
        }
        if let destinationFolder, Movable.isInside(item.path, any: [destinationFolder]) {
            return .theBackupItself
        }
        if let rule = exclusionRule(for: item.path) { return .excludedByYou(rule: rule) }
        if let kind = notACopyableThing(mode: item.mode, isDirectory: item.isDirectory,
                                        isSymbolicLink: item.isSymbolicLink) {
            return .notACopyableThing(kind: kind)
        }
        return nil
    }

    /// The person's own exclusion that caught this path, if any.
    func exclusionRule(for path: String) -> String? {
        for rule in excludedByTheUser {
            let full = rule.hasPrefix("/")
                ? rule
                : home.appending(path: rule).path(percentEncoded: false)
            if Movable.isInside(path, any: [full]) { return rule }
        }
        return nil
    }

    /// What a thing is, when it is not a file, a folder or a symbolic link.
    ///
    /// ⚠️ `mode` here is the **file type bits** from `st_mode`, not the permission bits — see
    /// `SourceReader.read`, which passes the whole thing for exactly this reason.
    func notACopyableThing(mode: UInt16, isDirectory: Bool, isSymbolicLink: Bool) -> String? {
        if isDirectory || isSymbolicLink { return nil }
        switch mode_t(mode) & S_IFMT {
        case S_IFREG:  return nil
        case S_IFSOCK: return "a socket"
        case S_IFIFO:  return "a named pipe"
        case S_IFCHR, S_IFBLK: return "a device"
        default:       return "not an ordinary file"
        }
    }

    /// Where this item goes on the backup drive, relative to the backup folder.
    func relativePath(of path: String) -> String? {
        let base = home.path(percentEncoded: false)
        guard Movable.isInside(path, any: [base]) else { return nil }
        // ⚠️ Component by component, never by trimming a prefix off a string: the filesystem folds
        // case and Unicode normalisation, so two spellings of the same folder have different
        // character counts and a length-based slice would cut in the wrong place.
        let baseCount = base.split(separator: "/").count
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > baseCount else { return "" }
        return parts.dropFirst(baseCount).joined(separator: "/")
    }
}

// MARK: - Reading one item

/// Reads one thing in the source, once, into a `SourceItem`.
///
/// ⚠️ **`lstat`, never `stat`.** A symbolic link is a thing in its own right and is copied as one;
/// following it here would report the target's flags, the target's size, and — for a link into a
/// cloud folder — would start the download this engine exists to avoid.
enum SourceReader {

    /// `nil` when there is nothing there, or nothing readable.
    static func read(_ path: String, rules: SourceRules) -> SourceItem? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }

        let type = status.st_mode & S_IFMT
        let isDirectory = type == S_IFDIR
        let isLink = type == S_IFLNK

        return SourceItem(
            path: path,
            relativePath: rules.relativePath(of: path) ?? (path as NSString).lastPathComponent,
            isDirectory: isDirectory,
            isSymbolicLink: isLink,
            // ⭐ The flag, and only the flag. Never the return code of a copy.
            isCloudOnly: status.st_flags & Movable.dataless != 0,
            apparentBytes: Int64(status.st_size),
            allocatedBytes: Int64(status.st_blocks) * 512,
            linkCount: UInt16(truncatingIfNeeded: status.st_nlink),
            device: status.st_dev,
            inode: UInt64(status.st_ino),
            mode: UInt16(truncatingIfNeeded: status.st_mode),
            createdOn: Date(timeIntervalSince1970: TimeInterval(status.st_birthtimespec.tv_sec)),
            modifiedOn: Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)))
    }

    /// Whether the file at this path is a placeholder for something in the cloud.
    ///
    /// ⭐ **The one reading completeness is judged by.** A copy that returns success can still have
    /// written nothing, because a cloud-only file that happens to be empty copies cleanly. This is
    /// the answer that does not depend on having tried.
    static func isCloudOnly(_ path: String) -> Bool {
        var status = stat()
        guard lstat(path, &status) == 0 else { return false }
        return status.st_flags & Movable.dataless != 0
    }
}
