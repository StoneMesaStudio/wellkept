// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  ScanPolicy.swift
//  Wellkept — App/Storage
//
//  ⭐ **Where a scan may go, what it may read, and what it will never offer to touch — decided once,
//  here, and nowhere else.**
//
//  Five scanners are written against this file. If any of them contains its own idea of where to
//  stop, the section has two policies and only one of them gets reviewed.
//
//  ## The four measurements that wrote this file
//
//  1. **Never scan from `/`.** Started at the root, a walk counts the disk twice and reports
//     501 GB used on a 494 GB drive — the Data volume is reachable directly *and* through the
//     firmlinks the sealed System volume publishes at `/Users`, `/Applications` and a dozen other
//     names. See `root(home:)`.
//  2. **A read can pull a file down from iCloud.** Comparing files during the research pulled
//     **524 of them** over the owner's internet and turned a 36-second scan into over nine minutes —
//     using his bandwidth to fill the disk we were there to empty. One flag makes such a read fail
//     instantly instead. It is **per thread**, so it has to be set on every scanning thread.
//     See `prepareThisThread()`.
//  3. **Our own scan rewrote 2,012 "last accessed" dates.** Reading a file's contents updates its
//     access time, so that field can never be evidence of anything here — our own looking poisons
//     it. The resource key is absent from `resourceKeys` so nobody can reach for it by habit.
//     See `whyLastAccessedIsNotHere`.
//  4. **A full scan of this home folder takes about 12 seconds.** Not minutes. So the section says
//     what it is doing and does not promise how long — the first scan after a restart has never
//     been measured, and a progress bar that lies twice is worse than no progress bar.
//     See `Running`.
//
//  ## ⚠️ Why a list of names is right HERE and wrong everywhere else
//
//  The engine's rule is **identity, never name**: every documented catastrophe in this field chose
//  its victim by something other than identity. That rule governs *choosing what to act on*, and
//  `Movable` keeps it — nothing is moved on the strength of its path.
//
//  `neverOffered` below runs in the opposite direction. It only ever **subtracts** from what is
//  offered. A stale entry costs somebody a folder we no longer mention; a stale entry in a
//  *blocklist that permits* costs somebody their files. The two are not symmetrical, and refusing
//  by name is safe precisely because the failure mode is "we were too careful".

// MARK: - Policy

enum ScanPolicy {

    // MARK: ── Where a scan starts ────────────────────────────────────────────────────────────────

    /// ⚠️ **The Data volume, never `/`.** See measurement 1 in the file note.
    ///
    /// Taken from the home folder's own `statfs` rather than assumed to be `/System/Volumes/Data`,
    /// because a Mac whose home folder is on an external disk has a different answer and it is the
    /// one that matters.
    static func root(home: URL = StorageManifest.home()) -> URL {
        FreeSpace.dataVolume(home: home)
    }

    /// The reason, in one sentence, for whoever finds `root()` and wonders why it is not `"/"`.
    static let whyNotTheRoot =
        "A walk from / counts the disk twice, because the Data volume is reachable both directly "
        + "and through the firmlinks the System volume publishes."

    // MARK: ── ⚠️ The thread I/O policy ───────────────────────────────────────────────────────────

    /// ⭐ **Call this first on EVERY thread that reads the disk. It is per thread, not per process.**
    ///
    /// Without it, touching a file that lives in iCloud and is not on this Mac makes macOS
    /// *download it*. Measured during the research: 524 files pulled down, a 36-second scan turned
    /// into over nine minutes, and the owner's bandwidth spent filling the disk we were there to
    /// help him empty.
    ///
    /// `IOPOL_MATERIALIZE_DATALESS_FILES_OFF` makes such a read fail immediately with `EPERM`
    /// instead, which is exactly what a scanner wants: a dataless file occupies no space here, so
    /// there is nothing to measure and nothing to offer.
    ///
    /// It is cheap, it cannot fail in a way that matters, and calling it twice is harmless — so it
    /// is safe to call at the top of every task rather than tracked.
    @discardableResult
    static func prepareThisThread() -> Bool {
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES,
                       IOPOL_SCOPE_THREAD,
                       IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0
    }

    /// Whether this thread is currently holding cloud files where they are. For a test, and for a
    /// scanner that wants to assert its own setup rather than assume it.
    static var thisThreadHoldsCloudFilesWhereTheyAre: Bool {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
            == IOPOL_MATERIALIZE_DATALESS_FILES_OFF
    }

    // MARK: ── What every enumerator asks for ─────────────────────────────────────────────────────

    /// ⭐ **The one resource-key set. Every walk in the section uses it.**
    ///
    /// `.totalFileAllocatedSizeKey` is the size on disk — allocated blocks, after compression, after
    /// sparseness, after clones. `.fileSizeKey` is the apparent size, which was wrong by 56% on this
    /// Mac and swung 11% between two runs minutes apart. Both are here because the difference is
    /// itself a finding: a 72 GB apparent total against a zero on-disk total is how the section
    /// knows to say "these are in iCloud".
    static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .isRegularFileKey,
        .fileResourceIdentifierKey,
        .volumeIdentifierKey,
        // ⭐ Size on disk. The number the section shows.
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        // The apparent size, kept only to detect the gap. Never printed as a size we stand behind.
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
        .nameKey,
    ]

    /// ⚠️ **`.contentAccessDateKey` is deliberately absent, and this is why.**
    ///
    /// Our own research scan rewrote 2,012 of them by reading the files. The field records who
    /// looked last, and we are who looked last — so on any Mac where Wellkept has run once, "not
    /// opened in years" is a statement about Wellkept. There is no threshold at which it becomes
    /// evidence, and there is no version of this that is fixable by being more careful.
    ///
    /// `Item.lastOpenedOn` is Spotlight's `kMDItemLastUsedDate`, which is a different reading that
    /// nothing here writes. It is blank for 61% of large files on this Mac, and it is a fact on a
    /// row rather than a finding.
    static let whyLastAccessedIsNotHere =
        "Reading a file updates its last-accessed date, so our own scan would be the thing it "
        + "recorded."

    /// The enumerator options every walk uses.
    ///
    /// ⚠️ `.skipsPackageDescendants` is **off**: a Photos library is a package and its size is the
    /// single most useful number in this section. What we must not do is offer to reach *inside* it,
    /// and that is `neverOffered`'s job, not the enumerator's.
    static let walkOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

    /// The same, for the walks that must see dot-files — the ones totalling a folder's size, where
    /// skipping `.git` would under-report a project by most of its weight.
    static let walkOptionsIncludingHidden: FileManager.DirectoryEnumerationOptions = []

    // MARK: ── Where a scan may not go ────────────────────────────────────────────────────────────

    /// Why a walk stopped at a folder.
    enum SkipReason: Sendable, Equatable, Hashable {

        /// The sealed System volume. ⚠️ It shares a device number and a display name with the Data
        /// volume — only `statfs` tells them apart — and everything on it is macOS, is measured by
        /// macOS, and is not ours to count.
        case sealedSystemVolume

        /// A different volume from the one being scanned: another disk, a mounted image, a
        /// snapshot mount. Counting it would attribute somebody else's disk to this one.
        case anotherVolume(name: String)

        /// A Time Machine snapshot mount. The files in it are the same blocks as the live ones, so
        /// walking it counts everything twice.
        case snapshot

        /// A network mount — `MNT_LOCAL` is clear. Walking it is somebody's server, over somebody's
        /// network, and none of it is space on this Mac.
        case networkVolume(name: String)

        /// A symbolic link. ⚠️ Following one is how a walk leaves the volume, loops forever, or
        /// counts the same folder under two names — and following one on the *acting* side is how a
        /// "delete this cache" destroys the real folder it points at.
        case symbolicLink

        /// Another app's sandboxed data. ⛔ **Banned outright.** macOS gates it behind *"would like
        /// to access data from other apps"*, which it raises on the **attempt**, not on the failure.
        /// A speculative read to find out whether we are allowed IS the harm: it puts an
        /// unexplained dialog on somebody's screen. Storage never goes there at all.
        case anotherAppsData

        /// Wellkept's own quarantine store. The engine pointed at itself.
        case wellkeptsOwnStore

        /// We were refused. Counted, named, and never reported as a zero.
        case notPermitted

        /// The words on the "we did not look everywhere" line, where there are any.
        var sentence: String {
            switch self {
            case .sealedSystemVolume:
                "macOS itself, which macOS measures and we do not."
            case let .anotherVolume(name):
                "\(name) is a different disk."
            case .snapshot:
                "A Time Machine snapshot, which is the same blocks over again."
            case let .networkVolume(name):
                "\(name) is on the network, not on this Mac."
            case .symbolicLink:
                "A shortcut to somewhere else."
            case .anotherAppsData:
                "Another app's private data, which macOS keeps to itself."
            case .wellkeptsOwnStore:
                "Wellkept's own quarantine."
            case .notPermitted:
                Unreadable.notPermitted.sentence
            }
        }

        /// ⭐ Whether this skip means the run saw less than it should have. Only a refusal a person
        /// could lift counts — everywhere else, not going there IS the correct answer, and telling
        /// somebody the scan was incomplete because it declined to count macOS twice is noise.
        var makesTheRunIncomplete: Bool { self == .notPermitted }
    }

    enum Descent: Sendable, Equatable {
        case yes
        case no(SkipReason)

        var isAllowed: Bool { self == .yes }
        var reason: SkipReason? {
            if case let .no(why) = self { return why }
            return nil
        }
    }

    /// ⭐ **The one question every walk asks before it steps into a folder.**
    ///
    /// - Parameters:
    ///   - url: the folder about to be entered.
    ///   - stayingOn: the volume the scan belongs to, read once at the start rather than per entry.
    ///   - home: the home folder, for the two Wellkept-owned places and the gated Library folders.
    static func descend(into url: URL,
                        stayingOn scanVolume: VolumeReading?,
                        home: URL = StorageManifest.home()) -> Descent {
        let path = url.path(percentEncoded: false)

        // Wellkept's own store first: it is cheap, it is certain, and an engine that walks its own
        // quarantine will offer to quarantine the quarantine.
        let ours = [StorageManifest.quarantineDirectory(home: home).path(percentEncoded: false),
                    StorageManifest.supportDirectory(home: home).path(percentEncoded: false)]
        if Movable.isInside(path, any: ours) { return .no(.wellkeptsOwnStore) }

        // ⛔ Another app's sandboxed data. Tested BEFORE anything that touches the folder, because
        // for these the touch is the harm.
        if isAnotherAppsData(path, home: home) { return .no(.anotherAppsData) }

        // A symbolic link, by `lstat`, so the answer is about the link and not its target.
        var status = stat()
        guard lstat(path, &status) == 0 else { return .no(.notPermitted) }
        if (status.st_mode & S_IFMT) == S_IFLNK { return .no(.symbolicLink) }

        // ⚠️ A symlink anywhere in the chain above is the same hazard arriving by a different door.
        if Movable.symlinkInParentChain(of: path) != nil { return .no(.symbolicLink) }

        guard let volume = Movable.volume(of: path) else { return .no(.notPermitted) }

        if volume.isSealedSystem { return .no(.sealedSystemVolume) }
        if isNetwork(volume) { return .no(.networkVolume(name: Movable.friendlyVolumeName(volume))) }
        if isSnapshotMount(volume) { return .no(.snapshot) }

        if let scanVolume, !volume.isSameVolume(as: scanVolume) {
            return .no(.anotherVolume(name: Movable.friendlyVolumeName(volume)))
        }

        return .yes
    }

    /// ⛔ **The folders under `~/Library` that macOS gates behind the app-data privacy dialog.**
    ///
    /// The name is taken from `LeftoverReader.Place`, which is the one file in this repository
    /// permitted to write it — `Tests/ContainerGuardTests.swift` fails the build on any other file
    /// that does. Taking it from there rather than retyping it also means there is one spelling, so
    /// this rule and the Apps section's gate can never disagree.
    ///
    /// It is matched as a **suffix** rather than as a list of two names, so the group variant is
    /// covered by the same line, and so a future macOS that adds a third one is covered before we
    /// have heard of it. Only folders sitting directly inside `~/Library` qualify: a folder of the
    /// same name inside somebody's project is their own file and is none of this rule's business.
    static func isAnotherAppsData(_ path: String, home: URL = StorageManifest.home()) -> Bool {
        // ⚠️ Compared component by component, never by trimming a prefix off a string. The
        // filesystem folds case and Unicode normalisation, so two spellings of the same folder have
        // different character counts — and a rule that slices by length would then read the wrong
        // component and let a walk into the one place it must never go.
        let libraryParts = components(home.appending(path: "Library").path(percentEncoded: false))
        let parts = components(path)
        guard parts.count > libraryParts.count,
              Array(parts.prefix(libraryParts.count)) == libraryParts
        else { return false }

        let gated = LeftoverReader.Place.containers.directory.lowercased()
        return parts[libraryParts.count].hasSuffix(gated)
    }

    /// Path components, case-folded and canonically composed — the same folding `Movable.isInside`
    /// does, and for the same reason.
    private static func components(_ path: String) -> [String] {
        path.precomposedStringWithCanonicalMapping
            .split(separator: "/")
            .map { $0.lowercased() }
    }

    /// `MNT_LOCAL` clear means the volume is served over a network.
    static func isNetwork(_ volume: VolumeReading) -> Bool {
        volume.flags & UInt32(bitPattern: MNT_LOCAL) == 0
    }

    /// A mounted APFS snapshot. Its blocks are the live volume's blocks, so walking it double-counts
    /// the whole disk.
    static func isSnapshotMount(_ volume: VolumeReading) -> Bool {
        volume.mountPoint.hasPrefix("/Volumes/.timemachine")
            || volume.mountPoint.hasPrefix("/System/Volumes/Update/mnt")
            || volume.device.contains("@")
    }

    // MARK: ── ⭐ The refusal list ────────────────────────────────────────────────────────────────

    /// One thing Storage will never offer to touch, and why.
    struct Refusal: Sendable, Equatable, Hashable, Identifiable {
        /// The path, relative to the home folder, or absolute when it starts with `/`.
        let place: String
        /// What a person would call it.
        let name: String
        /// **Why.** Shown wherever the refusal is explained, and the reason it is a sentence rather
        /// than a comment is that a person who wonders why their Photos library is not on the list
        /// deserves the answer on the screen.
        let why: String
        /// Whether it is still worth reporting the size, with no button. `false` means we do not
        /// even measure it.
        let stillMeasured: Bool

        var id: String { place }

        init(_ place: String, _ name: String, why: String, stillMeasured: Bool = true) {
            self.place = place
            self.name = name
            self.why = why
            self.stillMeasured = stillMeasured
        }
    }

    /// ⭐ **What Storage will never offer to touch, at any age, in any category.**
    ///
    /// Not "unless it is old". Not "unless the user turns on advanced mode". Never. Age is an
    /// annoyance filter and nothing more — measured, "older than 30 days" picks a 1.3 GB audiobook
    /// out of `~/Library/Caches` first and protects only 4% of Xcode's build output.
    /// Hoisted so the named entry and the extension rule below give the same answer.
    static let whyAPhotoLibraryIsNeverTouched =
        "Photos keeps one package and manages what is inside it. Changing it from outside is how a "
        + "library gets corrupted, and Photos already has its own duplicate finder that merges "
        + "rather than deletes."

    static let neverOffered: [Refusal] = [

        Refusal("Pictures/Photos Library.photoslibrary", "your Photos library",
                why: whyAPhotoLibraryIsNeverTouched),

        Refusal("Library/Mail", "your mail",
                why: "On an account that does not keep a copy on the server, this is the only copy "
                   + "there is."),

        Refusal("Library/Messages", "your messages",
                why: "The whole history of every conversation, and there is no second copy unless "
                   + "you back up."),

        Refusal("Library/Keychains", "your passwords",
                why: "Losing one of these loses accounts, not files."),

        Refusal("Library/Preferences", "every app's settings",
                why: "A 2 KB file here can be a window position or a licence key, and nothing on "
                   + "the outside tells them apart."),

        Refusal("Library/Application Support/MobileSync", "your iPhone and iPad backups",
                why: "Large, and the only copy of a phone that is not backed up anywhere else. "
                   + "It is worth showing you the size; it is not ours to remove."),

        Refusal(".Trash", "your Trash",
                why: "It is already a holding pen with an undo. Moving things from one holding pen "
                   + "to another is not tidying, and the Finder's Empty Trash is one click away."),

        Refusal("/Library/Developer/CoreSimulator/Profiles/Runtimes", "the iOS simulator runtimes",
                why: "30 GB on this Mac, and they are root-owned read-only disk images: they "
                   + "cannot be set aside, so there would be no thirty-day undo. Xcode removes "
                   + "them from its own Settings."),

        Refusal("/System", "macOS itself",
                why: "It is on a sealed volume that nothing can write to, ours included.",
                stillMeasured: false),

        Refusal("/private/var/db", "the system's own bookkeeping",
                why: "Receipts, caches and databases macOS uses to know what is installed. "
                   + "Removing them breaks updates in ways that surface weeks later.",
                stillMeasured: false),

        Refusal("/Volumes", "anything on another disk",
                why: "Quarantine only works within one volume, so there would be no undo. Another "
                   + "disk is also somebody's backup more often than not."),

        Refusal("Library/Mobile Documents", "iCloud Drive's own folder",
                why: "The individual files in here can be set aside, with the warning. The folder "
                   + "itself is iCloud's, and moving it takes the sync with it."),
    ]

    /// Things that are never offered by shape rather than by place, because they can be anywhere.
    ///
    /// The last two are the duplicate finder's two hard rules, kept here so they are next to
    /// everything else that says no.
    enum Shape: Sendable, Equatable, CaseIterable {

        /// Anything inside an app. Removing part of an app breaks the app and breaks its signature,
        /// and a "cache" folder inside a bundle is the developer's, not the machine's.
        case insideAnAppBundle

        /// A `.git` folder. It is usually most of a project's weight and it is the entire history.
        case versionControlHistory

        /// One half of an APFS clone pair. ⚠️ Two "copies" that share their blocks are one file:
        /// deleting one returns nothing, and the pair is not a duplicate.
        case oneHalfOfAClone

        /// Any member of a duplicate group. ⚠️ **There is no honest way to pick the original.** Four
        /// real pairs on this Mac each defeat a different rule, including a photo whose dates a past
        /// copy destroyed, so "keep the oldest" picks the wrong one. And 94% of the 12,021 groups in
        /// this home folder are inside project folders, where deleting one breaks a build. We show
        /// the group. **We never choose.**
        case aDuplicateWeWouldHaveToChooseBetween

        var why: String {
            switch self {
            case .insideAnAppBundle:
                "Taking a file out of an app breaks the app, and breaks the signature macOS checks."
            case .versionControlHistory:
                "That folder is the project's entire history, and it is usually most of its size."
            case .oneHalfOfAClone:
                "These two share the same blocks on the disk. They look like two files and they are "
                + "one, so deleting either makes no room."
            case .aDuplicateWeWouldHaveToChooseBetween:
                "We can tell you these are identical. We cannot tell you which one something else "
                + "depends on, so the choice is yours."
            }
        }
    }

    /// Whether a path is on the refusal list, and which entry caught it.
    ///
    /// The named places first, then the three shapes that can be anywhere. A Photos library is
    /// matched by its extension rather than by where it usually sits, because a person is perfectly
    /// entitled to keep one on an external drive and calling that one fair game would be the
    /// difference between a rule and a coincidence.
    static func refusal(for path: String, home: URL = StorageManifest.home()) -> Refusal? {
        for refusal in neverOffered {
            let full = refusal.place.hasPrefix("/")
                ? refusal.place
                : home.appending(path: refusal.place).path(percentEncoded: false)
            if Movable.isInside(path, any: [full]) { return refusal }
        }

        let parts = components(path)
        for (index, component) in parts.enumerated() {
            if component == ".git" {
                return Refusal(path, "a project's history", why: Shape.versionControlHistory.why)
            }
            if component.hasSuffix(".photoslibrary") || component.hasSuffix(".aplibrary") {
                return Refusal(path, "a photo library", why: whyAPhotoLibraryIsNeverTouched)
            }
            // ⚠️ **Inside an app, not the app itself.** Removing an app is the Apps section's
            // business and it takes the whole bundle; reaching into one breaks the app and breaks
            // the signature macOS checks at launch.
            if component.hasSuffix(".app") && index < parts.count - 1 {
                return Refusal(path, "part of an app", why: Shape.insideAnAppBundle.why)
            }
        }
        return nil
    }

    /// ⭐ **Whether Storage may draw a button on this at all.** One call, so no screen has to
    /// remember the list.
    static func mayOfferToActOn(_ path: String, home: URL = StorageManifest.home()) -> Bool {
        refusal(for: path, home: home) == nil
    }

    // MARK: ── Age ───────────────────────────────────────────────────────────────────────────────

    /// ⚠️ **"Older than 30 days" is not a safety net, and it is never the reason anything is
    /// ticked.**
    ///
    /// Measured: it picks the 1.3 GB audiobook in `~/Library/Caches` first, and it protects only 4%
    /// of Xcode's build output. What it is genuinely good for is one thing — *do not make me
    /// re-download something I used this week* — so it survives as an annoyance filter on top of a
    /// decision that has already been made on other grounds.
    static let annoyanceFilterDays = 30

    static func isRecentlyUsed(_ modifiedOn: Date?, now: Date = Date()) -> Bool {
        guard let modifiedOn else { return false }
        let days = Calendar.current.dateComponents([.day], from: modifiedOn, to: now).day ?? 0
        return days < annoyanceFilterDays
    }

    // MARK: ── Reading a file's contents ─────────────────────────────────────────────────────────

    /// ⚠️ **Whether a scanner may open this file at all.**
    ///
    /// Opening is the expensive, side-effectful act in this section: it rewrites the access date,
    /// and without `prepareThisThread()` it can pull the file down from iCloud. So it happens only
    /// where there is no other way to answer the question — comparing two files that are already
    /// known to be the same size — and never on a file that is not here.
    static func mayReadContents(ofSize onDisk: SizeOnDisk,
                                cloudStanding: CloudStanding,
                                forDuplicateComparison: Bool) -> Bool {
        guard forDuplicateComparison else { return false }
        guard cloudStanding.occupiesSpaceHere else { return false }
        guard !onDisk.isZero else { return false }
        return thisThreadHoldsCloudFilesWhereTheyAre
    }

    // MARK: ── What the screen says while it runs ────────────────────────────────────────────────

    /// ⚠️ **Honest, not theatrical, and never a time.**
    ///
    /// The whole home folder took about 12 seconds when it was measured. That is fast enough that a
    /// staged progress theatre would be a lie told for a quarter of a minute — and the first scan
    /// after a restart has never been measured, so any figure we printed would be a guess dressed
    /// as a countdown.
    ///
    /// The button says what it is doing, in its own label, and says where it has got to by naming
    /// the place rather than a percentage. See DESIGN §9.
    enum Running {
        /// The verb in the button's own label while it runs.
        static let verb = "Scanning"
        /// What it says underneath: where it is, not how far along.
        static func at(_ place: String) -> String { "Looking in \(place)" }
        /// ⛔ There is deliberately no `estimatedTimeRemaining`. Do not add one.
        static let whyThereIsNoEstimate =
            "The first scan after a restart has never been measured, so any figure would be a guess."
    }
}
