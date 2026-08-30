// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  CoverageReader.swift
//  Wellkept — App/Backup
//
//  ⭐ **What is NOT backed up — and, for each thing, whether that actually matters.**
//
//  This is probably the most valuable sentence the Backup section says, and it is also the easiest
//  one to get catastrophically wrong in either direction. Say too much and the app opens with a
//  72 GB alarm about an arrangement that is working exactly as designed. Say too little and
//  somebody finds out on the one day it counts.
//
//  So this file answers **two separate questions per place**, and never lets them blur:
//
//  1. **Is there a copy of this anywhere other than this disk?** — `WhereItLives`. Only
//     `.onlyOnThisMac` can ever be a gap.
//  2. **Is it in a backup?** — `Included`. Answered from Time Machine's state and from nothing
//     else, because we cannot see inside a backup (below).
//
//  `Coverage.isGap` is the `and` of those two, and it is computed in `WellkeptCore` where no reader
//  can reach it. Nothing in this file can hand a cloud file to the screen as a missing one.
//
//  ## ⛔ What this file will not do
//
//  - **It never materialises a cloud file.** `ScanPolicy.prepareThisThread()` is called on every
//    thread that looks at anything, and the judgement is made on the kernel's `SF_DATALESS` flag
//    rather than on a size. During the Storage research, reading without that policy pulled **524
//    files** down over somebody's internet and turned a 36-second scan into over nine minutes.
//  - ⛔ **It never descends into a third-party file provider.** `~/Library/CloudStorage/GoogleDrive-…`
//    is indistinguishable from an ordinary folder by every test this app uses — same filesystem,
//    same device as `~/Documents`. Reading it **timed out and killed a scan**, and had it succeeded
//    it would have started downloading the whole Drive. It is refused **by name**, which is exactly
//    the case `ScanPolicy` says a name list is right for: the list only ever subtracts.
//  - ⛔ **It never opens another app's private data**, and it never even tries. macOS raises
//    *"would like to access data from other apps"* on the **attempt**, so a speculative read to
//    find out whether we are allowed is itself the harm. Calendars, Reminders and Notes live there
//    on macOS 26, and all three are reported without ever being touched.
//  - **It never walks the whole home folder.** That is `Scanner`'s job and it takes 56.7 seconds.
//    This runs in well under a second on a Mac with no cloud storage, and the one walk it does make
//    is bounded to the two roots that can hold a placeholder.
//  - ⛔ **It never reads the Apple ID.** `MobileMeAccounts.plist` carries the person's email address,
//    display name, first name, last name and two directory identifiers, an arm's length from the
//    `Services` array this file wants. Only `Services` is parsed. A backup tool that quietly learnt
//    somebody's name has answered a question about itself.
//
//  ## ⚠️ The five measurements this file is built on
//
//  Taken by hand on this Mac, read-only, 2026-08-29. Nothing was written, moved or downloaded.
//
//  1. **`stat` works without Full Disk Access; listing does not.** `~/Library/Mail`,
//     `~/Library/Messages` and `~/Library/Application Support/AddressBook` all `stat` cleanly with
//     nothing granted and all three refuse `ls` with `Operation not permitted`. So this file can
//     always prove a place **exists** — it just cannot say how big it is. That is the difference
//     between a row that says "your mail is not in any backup" and a row that says nothing at all.
//  2. **`~/Documents` holds 10,925 dataless files claiming 65.4 GB, out of 31,200.** Desktop &
//     Documents syncing is on, so two thirds of that folder is not on the disk to copy. Time
//     Machine has the same hole and never mentions it.
//  3. ⭐ **`~/Desktop` and `~/Library/Mobile Documents/com~apple~CloudDocs/Desktop` are the same
//     files.** Different directory inodes, *identical* file inodes — `SetShot.app` is `71114060`
//     under both names. **A backup that copies both roots copies everything twice**, and this is
//     the one finding here that is about the copier rather than about the person's arrangement.
//     `desktopAndDocumentsAreMirrored(home:)` is what stops it.
//  4. **iCloud Drive proper is 258 files, 21.3 GB, and only 3 of them are placeholders.** So
//     "iCloud Drive" and "the 72 GB that is not here" are not the same fact and do not belong on
//     the same row.
//  5. ⚠️ **`MobileMeAccounts.plist` states `Enabled` for only 4 of 24 services** — iCloud Drive,
//     Notes, Keychain and Find My. Photos, Mail, Messages, Contacts, Calendars, Reminders and
//     Bookmarks are **listed without a verdict**. There is no honest way to read a missing key as
//     "off", so this file has a third answer (`ICloudService.Standing.notStated`) and says so on
//     the row rather than guessing. See `ICloudAccount`.
//
//  ## ⭐ Why `Included` is never read out of a backup
//
//  **We cannot see inside a Time Machine backup, and we are not going to try.** The drive is
//  usually not plugged in; mounting one is forbidden outright; and `StdExclusions.plist` — the
//  file that used to list what Time Machine skips — **no longer exists on macOS 26**, so we cannot
//  even read the rules. Every claim about what is in a backup therefore comes from one place: the
//  state Time Machine publishes about itself, which reads with no permission at all.
//
//  That gives exactly three honest verdicts, and the useful one is the first:
//
//  | Time Machine | Verdict | Why it is safe to say |
//  |---|---|---|
//  | Never set up, or nothing has ever succeeded | **Not in the backup** | There is no backup. This is the finding the section exists for. |
//  | A backup has succeeded at some point | **In the backup**, dated | It ran as root with everything visible to it. How *old* it is belongs to the Time Machine row, and this row does not repeat it. |
//  | We could not read Time Machine at all | **Not known** | Claiming either way would be inventing the answer. |

// MARK: - The reader

enum CoverageReader {

    // MARK: ── The places ────────────────────────────────────────────────────────────────────────

    /// **The eleven things a person would think to ask about**, in the order the row draws them.
    ///
    /// The home folder first, because it is the whole and everything else is a part of it; then the
    /// ten named things, ordered by how much of somebody's life is in them rather than
    /// alphabetically.
    ///
    /// ⚠️ **The Trash is deliberately not here**, and it is the one `ProtectedPlace` with no row.
    /// It is not somewhere a person keeps things — it is where they have already thrown them away —
    /// and a row saying "your Trash is not backed up" reads as a fault when it is the arrangement.
    /// It still travels into `BackupCompleteness.missingSentences` through `ProtectedPlace`, which
    /// is where it belongs: it is one of the six things a backup made without Full Disk Access
    /// silently holds none of. A test asserts the Trash is the only one missing, so a *second*
    /// omission cannot happen quietly.
    enum Place: String, CaseIterable, Sendable, Identifiable, Hashable {
        case homeFolder
        case photos
        case mail
        case messages
        case contacts
        case calendars
        case reminders
        case notes
        case iCloudDrive
        case safari
        case music

        var id: String { rawValue }

        /// What a person calls it.
        var label: String {
            switch self {
            case .homeFolder:  "Your home folder"
            case .photos:      "Your Photos library"
            case .mail:        "Your Mail"
            case .messages:    "Your Messages"
            case .contacts:    "Your Contacts"
            case .calendars:   "Your Calendars"
            case .reminders:   "Your Reminders"
            case .notes:       "Your Notes"
            case .iCloudDrive: "iCloud Drive"
            case .safari:      "Safari's bookmarks and history"
            case .music:       "Your Music"
            }
        }

        /// ⭐ **The tie to `ProtectedPlace`, so the two lists cannot drift.**
        ///
        /// A place with one of these is a place a backup made **without Full Disk Access contains
        /// nothing of** — not a partial copy, nothing — and macOS refuses silently, with no error.
        /// The mapping is here rather than duplicated, so the wording of what is lost has one home.
        var protected: ProtectedPlace? {
            switch self {
            case .photos:   .photos
            case .mail:     .mail
            case .messages: .messages
            case .contacts: .contacts
            case .safari:   .safari
            case .homeFolder, .calendars, .reminders, .notes, .iCloudDrive, .music: nil
            }
        }

        /// Where the data actually sits, which decides how — and whether — we look.
        var keeping: Keeping {
            switch self {
            case .homeFolder:
                return .theWholeHomeFolder
            case .photos:
                return .atHome("Pictures/Photos Library.photoslibrary")
            case .mail:
                return .atHome("Library/Mail")
            case .messages:
                return .atHome("Library/Messages")
            case .contacts:
                return .atHome("Library/Application Support/AddressBook")
            case .safari:
                return .atHome("Library/Safari")
            case .iCloudDrive:
                return .atHome("Library/Mobile Documents/com~apple~CloudDocs")
            case .music:
                return .atHome("Music")
            // ⛔ macOS 26 keeps all three inside the folder class it gates behind "would like to
            // access data from other apps". `~/Library/Calendars` does not even exist on this Mac
            // any more — verified 2026-08-29, `stat` returns ENOENT. We do not look, we do not
            // probe, and we say so on the row.
            case .calendars, .reminders, .notes:
                return .inAPlaceMacOSKeepsToItself
            }
        }

        /// ⚠️ **Matched on `ServiceID`, never on `Name`.** Apple's own names are historical and two
        /// of them are actively misleading: Photos is listed as `PHOTO_STREAM` and Mail as
        /// `MAIL_AND_NOTES`, which is a different service from `NOTES`. The reverse-DNS identifiers
        /// say what they mean and have not moved.
        var iCloudServiceID: String? {
            switch self {
            case .photos:      "com.apple.Dataclass.Photos"
            case .mail:        "com.apple.Dataclass.Mail"
            case .messages:    "com.apple.Dataclass.Messages"
            case .contacts:    "com.apple.Dataclass.Contacts"
            case .calendars:   "com.apple.Dataclass.Calendars"
            case .reminders:   "com.apple.Dataclass.Reminders"
            case .notes:       "com.apple.Dataclass.Notes"
            case .safari:      "com.apple.Dataclass.Bookmarks"
            case .iCloudDrive: "com.apple.Dataclass.Ubiquity"
            // ⚠️ **Music is not an iCloud service in the sense that matters here.** Apple Music
            // downloads come back on demand; a track somebody ripped or bought outright does not,
            // and nothing distinguishes them from outside. So no service is claimed, and the row
            // treats the folder as the person's own files.
            case .music:       nil
            case .homeFolder:  nil
            }
        }

        /// The one line that says what this is and why it is being mentioned at all. Always shown,
        /// never behind a disclosure — a row with no reason is an accusation.
        var whatItIs: String {
            switch self {
            case .homeFolder:
                return "Everything under your account: documents, pictures, music, mail, messages "
                     + "and the settings every app keeps for you."
            case .photos:
                return "One package that Photos manages. If it is not copied, every picture and "
                     + "video in it goes with the disk."
            case .mail:
                return "On an account that does not keep a copy on the server, this is the only "
                     + "copy of your mail there is."
            case .messages:
                return "The whole history of every conversation, and its attachments."
            case .contacts:
                return "Everybody in your address book."
            case .calendars:
                return "Your appointments, and anything you have been invited to."
            case .reminders:
                return "Your lists and everything still on them."
            case .notes:
                return "Everything you have written in Notes."
            case .iCloudDrive:
                return "The folder Apple syncs between your devices. What is on this disk is "
                     + "whatever iCloud has brought down so far."
            case .safari:
                return "Bookmarks, reading list and history."
            case .music:
                return "Anything you ripped, bought outright or dragged in yourself. Apple Music "
                     + "downloads come back on their own; these do not."
            }
        }
    }

    /// Where a place's data sits, which decides how it may be looked at.
    enum Keeping: Sendable, Hashable {
        /// A folder under the home directory, at this relative path.
        case atHome(String)
        /// The home directory itself.
        case theWholeHomeFolder
        /// ⛔ Inside the folder class macOS gates behind the other-apps privacy dialog. **Never
        /// touched, never probed** — the dialog is raised on the attempt, so finding out whether we
        /// are allowed is itself the harm.
        case inAPlaceMacOSKeepsToItself
    }

    // MARK: ── ⚠️ What we found when we looked, or why we did not ─────────────────────────────────

    /// The result of looking for one place. Three answers, and the third is not the second.
    enum Presence: Sendable, Hashable {
        /// It is here. The size is present only where it could be had cheaply and honestly.
        case here(SizeOnDisk?)
        /// It is genuinely not on this Mac — `stat` returned `ENOENT`. Nothing to back up and
        /// nothing to say beyond that.
        case notHere
        /// We could not establish it, and this is why.
        case couldNotLook(Unreadable)

        var exists: Bool { if case .notHere = self { return false }; return true }

        var unreadable: Unreadable? {
            if case .couldNotLook(let why) = self { return why }
            return nil
        }

        var bytes: SizeOnDisk? {
            if case .here(let size) = self { return size }
            return nil
        }
    }

    /// ⭐ **Whether a place is on this Mac at all, by `stat` and never by trying to open it.**
    ///
    /// Measured 2026-08-29: `stat` on `~/Library/Mail`, `~/Library/Messages` and
    /// `~/Library/Application Support/AddressBook` all succeed with nothing granted, while `ls` on
    /// every one of them is refused. That asymmetry is the whole reason this section can be honest
    /// on a Mac that has given Wellkept nothing: existence is provable, size is not.
    ///
    /// ⚠️ `lstat`, not `stat`, so the answer is about the thing itself and not about whatever a
    /// symbolic link points at.
    static func presence(of place: Place, home: URL = StorageManifest.home()) -> Presence {
        switch place.keeping {
        case .inAPlaceMacOSKeepsToItself:
            // ⛔ We do not go and see. `.notReported` and not `.notPermitted`: there is no button we
            // could honestly draw, because the permission that would open it is one Wellkept has
            // decided never to ask for.
            return .couldNotLook(.notReported)

        case .theWholeHomeFolder:
            return directoryPresence(home)

        case .atHome(let relative):
            return directoryPresence(home.appending(path: relative))
        }
    }

    private static func directoryPresence(_ url: URL) -> Presence {
        let path = url.path(percentEncoded: false)
        var status = stat()
        guard lstat(path, &status) == 0 else {
            // ⚠️ Missing and refused are different sentences and always have been. A Mac where Mail
            // was never set up has no `~/Library/Mail`, and reporting that as a refusal would be
            // Wellkept inventing a permission problem out of somebody's arrangement.
            return errno == ENOENT ? .notHere : .couldNotLook(.notPermitted)
        }
        // ⚠️ **No size.** A folder's own `st_size` is its directory entry, not its contents, and
        // totalling the contents means a walk this reader has no business doing. `nil` here is a
        // fact; a wrong number would be worse than none.
        return .here(nil)
    }

    // MARK: ── ⚠️ What iCloud says about itself ──────────────────────────────────────────────────

    /// Whether one iCloud service is on.
    enum ICloudService {
        enum Standing: String, Sendable, Hashable, CaseIterable {
            /// macOS says it is on.
            case on
            /// macOS says it is off.
            case off
            /// ⚠️ **macOS lists the service and does not say.** The commonest answer by a wide
            /// margin, and the reason this enum has three cases: on this Mac, 20 of 24 services
            /// carry no `Enabled` key at all. Reading that absence as "off" would be an invention,
            /// and reading it as "on" would be a comfortable one.
            case notStated
        }
    }

    /// **What the iCloud account says about which services are switched on.**
    ///
    /// ⛔ Only the `Services` array is parsed. The same file carries the person's email address,
    /// display name, first and last name and two directory identifiers; none of them is read, none
    /// is stored, and there is no property on this type that could hold one.
    struct ICloudAccount: Sendable, Hashable {

        /// Whether an iCloud account is configured at all.
        let signedIn: Bool

        /// Service identifier to standing, for the services this file asks about.
        let standings: [String: ICloudService.Standing]

        /// Set when the file could not be read. ⚠️ Then `signedIn` is `false` because it is unknown,
        /// and nothing downstream may treat that `false` as evidence.
        let unreadable: Unreadable?

        static let notSignedIn = ICloudAccount(signedIn: false, standings: [:], unreadable: nil)

        static func couldNotRead(_ why: Unreadable) -> ICloudAccount {
            ICloudAccount(signedIn: false, standings: [:], unreadable: why)
        }

        func standing(of serviceID: String?) -> ICloudService.Standing {
            guard signedIn, let serviceID else { return .off }
            return standings[serviceID] ?? .notStated
        }

        /// The Options lines. One per service we asked about, in `Place` order, so a person who
        /// wants to know why a row says what it says can see the evidence.
        var detailPairs: [DetailPair] {
            if let unreadable { return [DetailPair("iCloud", unreadable: unreadable)] }
            guard signedIn else { return [DetailPair("iCloud", "Not signed in on this Mac")] }
            var pairs = [DetailPair("iCloud", "Signed in")]
            for place in Place.allCases {
                guard let id = place.iCloudServiceID else { continue }
                let word: String
                switch standing(of: id) {
                case .on:        word = "On"
                case .off:       word = "Off"
                case .notStated: word = "macOS does not say"
                }
                pairs.append(DetailPair("\(place.label) in iCloud", word))
            }
            return pairs
        }
    }

    /// Where the account file lives. `~/Library/Preferences`, which reads with no permission.
    static func iCloudAccountFile(home: URL = StorageManifest.home()) -> URL {
        home.appending(path: "Library/Preferences/MobileMeAccounts.plist")
    }

    /// ⭐ **Reads which iCloud services are on, and nothing else about the account.**
    ///
    /// The shape, verified on one real Mac: a top-level `Accounts` array, each with a `Services` array,
    /// each service carrying a `ServiceID` and — for 4 of 24 — an `Enabled` boolean. Desktop &
    /// Documents is the odd one: it states `status = "active"` and no `Enabled` at all.
    static func readICloud(from file: URL? = nil, home: URL = StorageManifest.home()) -> ICloudAccount {
        let url = file ?? iCloudAccountFile(home: home)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            // No file at all is the ordinary shape of a Mac with no iCloud account. It is an
            // absence we can stand behind, not a refusal.
            return .notSignedIn
        }
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let top = root as? [String: Any],
              let accounts = top["Accounts"] as? [[String: Any]]
        else {
            // ⚠️ The file exists and did not parse. Apple has reshaped it before, and a reader that
            // treated a changed shape as "no iCloud" would tell somebody their photos are only on
            // this Mac on the strength of a schema change.
            return .couldNotRead(.notReported)
        }

        var standings: [String: ICloudService.Standing] = [:]
        for account in accounts {
            guard let services = account["Services"] as? [[String: Any]] else { continue }
            for service in services {
                guard let id = service["ServiceID"] as? String else { continue }
                standings[id] = standing(of: service)
            }
        }
        return ICloudAccount(signedIn: !accounts.isEmpty, standings: standings, unreadable: nil)
    }

    /// The three-way read of one service entry. Hoisted so the precedence is in one place and a
    /// test can hold it.
    static func standing(of service: [String: Any]) -> ICloudService.Standing {
        if let enabled = service["Enabled"] as? Bool { return enabled ? .on : .off }
        // Desktop & Documents states itself this way and nothing else on this Mac does. Treated as
        // corroboration rather than as a second rule: it agrees with the 10,925 placeholder files
        // in `~/Documents`, which is what actually proves the sync is on.
        if let status = service["status"] as? String, status.lowercased() == "active" { return .on }
        return .notStated
    }

    // MARK: ── ⛔ The file providers ─────────────────────────────────────────────────────────────

    /// `~/Library/CloudStorage` — where macOS mounts every third-party sync service.
    static func fileProviderRoot(home: URL = StorageManifest.home()) -> URL {
        home.appending(path: "Library/CloudStorage")
    }

    /// ⛔ **A folder here is never entered, never measured and never copied.**
    ///
    /// `~/Library/CloudStorage/GoogleDrive-…` reports the same filesystem and the same device as
    /// `~/Documents`. It is not a folder: it is a mount that fetches from a server as things are
    /// opened. Reading it once **timed out and stopped a scan**, and had it not, walking it would
    /// have begun downloading the entire Drive onto a Mac with 95 GB free.
    ///
    /// This is refusal by **name**, which `ScanPolicy` explains is safe in exactly this direction:
    /// the list only subtracts. A stale entry costs somebody a folder we no longer mention; the
    /// mistake in the other direction costs them a scan and their bandwidth.
    /// ⚠️ **Compared component by component, never by trimming a prefix off a string** — the same
    /// folding `Movable.isInside` does, and for the same reasons. Two of them bite here: the
    /// filesystem folds case and Unicode normalisation, so two spellings of one folder have
    /// different character counts; and Foundation hands back a directory's path with a trailing
    /// slash and a file's without one, so `…/CloudStorage` and `…/CloudStorage/` are two spellings
    /// of the same folder. A string comparison read the second pair as different and let a walk
    /// straight into Google Drive — caught by the test, 2026-08-29.
    static func isAFileProviderMount(_ url: URL, home: URL = StorageManifest.home()) -> Bool {
        let root = components(fileProviderRoot(home: home).path(percentEncoded: false))
        let subject = components(url.path(percentEncoded: false))
        // Exactly one level down: the mount itself, never the container and never something deeper.
        guard subject.count == root.count + 1 else { return false }
        return Array(subject.prefix(root.count)) == root
    }

    /// ⛔ **Anywhere under `~/Library/CloudStorage`**, mount or deeper. The walk uses this rather
    /// than `isAFileProviderMount` so that a folder reached by some route that skipped the mount is
    /// still refused. None of this reader's roots contains that folder, so this is a second lock on
    /// a door that is already shut — which is the correct number of locks for the one mistake that
    /// would spend somebody's bandwidth downloading their entire Drive.
    static func isInsideAFileProvider(_ url: URL, home: URL = StorageManifest.home()) -> Bool {
        let root = components(fileProviderRoot(home: home).path(percentEncoded: false))
        let subject = components(url.path(percentEncoded: false))
        guard subject.count > root.count else { return false }
        return Array(subject.prefix(root.count)) == root
    }

    private static func components(_ path: String) -> [String] {
        path.precomposedStringWithCanonicalMapping
            .split(separator: "/")
            .map { $0.lowercased() }
    }

    /// ⚠️ **The provider's name, with the account stripped off.**
    ///
    /// The folder is named `GoogleDrive-someone@gmail.com` — the person's Google address, in a
    /// path, ready to be printed on a row or copied to a repair shop. Everything after the first
    /// hyphen is dropped. `Dropbox` has no hyphen and survives whole.
    static func providerName(_ folder: String) -> String {
        guard let hyphen = folder.firstIndex(of: "-") else { return folder }
        let name = String(folder[folder.startIndex..<hyphen])
        return name.isEmpty ? folder : name
    }

    /// Every third-party sync service mounted on this Mac, by provider, sorted, without accounts.
    static func fileProviders(home: URL = StorageManifest.home()) -> [String] {
        let root = fileProviderRoot(home: home)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath:
                root.path(percentEncoded: false)) else { return [] }
        var found: Set<String> = []
        for name in names where !name.hasPrefix(".") {
            found.insert(providerName(name))
        }
        return found.sorted()
    }

    // MARK: ── ⭐ The double-count trap ──────────────────────────────────────────────────────────

    /// ⭐ **Whether `~/Desktop` and `~/Documents` are a second view of the iCloud folders.**
    ///
    /// Measured 2026-08-29: with Desktop & Documents syncing on, `~/Desktop/SetShot.app` and
    /// `~/Library/Mobile Documents/com~apple~CloudDocs/Desktop/SetShot.app` are inode `71114060`
    /// on device `16777234` — **the same file under two names**. The directories themselves have
    /// different inodes, so a check on the folders alone says no.
    ///
    /// ⚠️ **A copier that walks both roots copies everything twice**, and a size that counts both
    /// reports a home folder about 65 GB larger than it is. Compared on a real file rather than on
    /// the folders, because the folders lie.
    static func desktopAndDocumentsAreMirrored(home: URL = StorageManifest.home()) -> Bool {
        let pairs = [("Desktop", "Library/Mobile Documents/com~apple~CloudDocs/Desktop"),
                     ("Documents", "Library/Mobile Documents/com~apple~CloudDocs/Documents")]
        for (plain, cloud) in pairs {
            guard let sample = firstFileIdentity(in: home.appending(path: plain)),
                  let mirror = firstNamedIdentity(sample.name, in: home.appending(path: cloud))
            else { continue }
            if sample.device == mirror.device && sample.inode == mirror.inode { return true }
        }
        return false
    }

    private struct Identity { let name: String; let device: Int32; let inode: UInt64 }

    private static func firstFileIdentity(in directory: URL) -> Identity? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath:
                directory.path(percentEncoded: false)) else { return nil }
        for name in names.sorted() where !name.hasPrefix(".") {
            if let id = identity(of: directory.appending(path: name), named: name) { return id }
        }
        return nil
    }

    private static func firstNamedIdentity(_ name: String, in directory: URL) -> Identity? {
        identity(of: directory.appending(path: name), named: name)
    }

    private static func identity(of url: URL, named name: String) -> Identity? {
        var status = stat()
        guard lstat(url.path(percentEncoded: false), &status) == 0 else { return nil }
        return Identity(name: name, device: status.st_dev, inode: UInt64(status.st_ino))
    }

    // MARK: ── ⚠️ The files that are not on the disk at all ──────────────────────────────────────

    /// **What is in the cloud and not here.** On one measured Mac: 72.2 GB across roughly 11,000 files.
    ///
    /// ⚠️ **`apparent` is what the placeholders claim, and it is never a size we stand behind** —
    /// there is nothing on the disk to measure. It is stated anyway, because "72 GB of your files
    /// are not on this Mac and would have to be downloaded before anything could copy them" is
    /// something no other backup tool says out loud.
    struct CloudHolding: Sendable, Hashable {
        let files: Int
        let apparent: SizeOnDisk
        /// Whether a measurement was actually taken. `false` is not "none found".
        let measured: Bool

        static let notMeasured = CloudHolding(files: 0, apparent: .zero, measured: false)

        var isEmpty: Bool { files == 0 }

        /// The row's sentence, or `nil` where there is nothing to say.
        var sentence: String? {
            guard measured, files > 0 else { return nil }
            return "\(files.formatted()) files are in the cloud and not on this disk. They claim "
                 + "\(apparent.text). Copying them would mean downloading them first, so Wellkept "
                 + "names them and leaves them where they are."
        }
    }

    /// ⭐ **Counts placeholder files without touching one.**
    ///
    /// The thread policy is set first, so that even a mistake here fails instantly instead of
    /// starting a 72 GB download. The judgement is `Scanner.cloudStanding(datalessFlags:…)` — the
    /// kernel's `SF_DATALESS` flag — and never the size: a sparse disk image reads
    /// `blocks=0, size=100 MB` exactly like an iCloud photo and is very much here.
    ///
    /// The walk is bounded to the three roots that can hold a placeholder, and it dedupes by inode
    /// because `~/Desktop` and the iCloud Desktop are the same files under two names — without that
    /// set, this Mac's figure comes back at twice the truth. Everything `ScanPolicy` refuses is
    /// refused here, plus everything under `~/Library/CloudStorage`.
    ///
    /// ⚠️ **So this figure is smaller than "everything of yours that is not on the disk", on
    /// purpose.** Of the 72.2 GB measured on one Mac, 65.4 GB is `~/Documents` and is counted here;
    /// the other 6.5 GB is Google Drive, which gets its own row precisely because measuring it would
    /// mean walking into it.
    ///
    /// - Returns: the holding, and the places we were not allowed to read.
    static func measureCloudOnly(home: URL = StorageManifest.home(),
                                 desktopAndDocumentsSynced: Bool)
    -> (holding: CloudHolding, refused: UnreadablePlaces) {
        ScanPolicy.prepareThisThread()

        var roots = [home.appending(path: "Library/Mobile Documents")]
        if desktopAndDocumentsSynced {
            roots += [home.appending(path: "Desktop"), home.appending(path: "Documents")]
        }

        let volume = Movable.volume(of: ScanPolicy.root(home: home).path(percentEncoded: false))
        var seen: Set<UInt64> = []
        var files = 0
        var apparent: Int64 = 0

        // ⚠️ A reference type, held by `let`, exactly as `Scanner` does it. The enumerator's error
        // handler is the only way this walk learns it was refused a folder, and a handler that
        // mutated a local would be a mutable capture in an escaping closure.
        let refusals = Refusals()

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else { continue }
            guard let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(ScanPolicy.resourceKeys),
                options: ScanPolicy.walkOptions,
                errorHandler: { url, error in
                    refusals.note(url, error: error)
                    return true
                })
            else { continue }

            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: ScanPolicy.resourceKeys)

                if values?.isDirectory == true {
                    if isInsideAFileProvider(url, home: home)
                        || !ScanPolicy.descend(into: url, stayingOn: volume, home: home).isAllowed {
                        walker.skipDescendants()
                    }
                    continue
                }

                // ⚠️ The cheap candidate test first: a file with a size and no blocks *might* not be
                // here. Everything else is skipped without an `lstat`, which is what keeps this
                // walk to a fraction of a second on a Mac with nothing in the cloud.
                let onDisk = Int64(values?.totalFileAllocatedSize ?? 0)
                let claimed = Int64(values?.fileSize ?? 0)
                guard onDisk == 0, claimed > 0 else { continue }

                var status = stat()
                guard lstat(url.path(percentEncoded: false), &status) == 0 else { continue }
                guard Scanner.cloudStanding(datalessFlags: status.st_flags,
                                            mightNotBeHere: true) == .inTheCloudOnly else { continue }

                // ⭐ The mirror. `~/Desktop` and the iCloud Desktop hand back the same inodes, and
                // counting both doubles the figure on every Mac with Desktop & Documents syncing.
                guard seen.insert(UInt64(status.st_ino)).inserted else { continue }

                files += 1
                apparent += claimed
            }
        }

        return (CloudHolding(files: files, apparent: SizeOnDisk(apparent), measured: true),
                refusals.places)
    }

    /// What the walk was not allowed to read, collected by reference so the enumerator's escaping
    /// error handler has somewhere to put it.
    ///
    /// ⚠️ **A file listed and then gone is not a refusal.** A build finishing mid-walk removes
    /// hundreds of files a second, and counting those as places we were kept out of would put a
    /// permanent "this total is smaller than the truth" caveat on the screen of anybody who
    /// compiles anything.
    final class Refusals {
        private(set) var count = 0
        private(set) var notable: [String] = []

        func note(_ url: URL, error: Error) {
            let error = error as NSError
            let vanished = (error.domain == NSCocoaErrorDomain
                            && error.code == NSFileReadNoSuchFileError)
                        || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
            guard !vanished else { return }
            count += 1
            if notable.count < 5 { notable.append(url.lastPathComponent) }
        }

        var places: UnreadablePlaces {
            count == 0
                ? .sawEverything
                : UnreadablePlaces(count: count, notable: notable, why: .notPermitted)
        }
    }

    // MARK: ── ⭐ One run ────────────────────────────────────────────────────────────────────────

    /// Everything one pass of this reader produced.
    struct Reading: Sendable {

        /// The coverage rows, in `Place` order, followed by the cloud and file-provider rows.
        let coverage: [Coverage]

        /// What is in the cloud and not on the disk.
        let cloudOnly: CloudHolding

        /// Third-party sync services mounted here, by provider, with no account names.
        let providers: [String]

        /// ⭐ Whether `~/Desktop` and `~/Documents` are a second view of the iCloud folders.
        let desktopAndDocumentsMirrored: Bool

        /// What iCloud says about itself.
        let iCloud: ICloudAccount

        /// Whether Wellkept held Full Disk Access when this ran.
        let fullDiskAccessHeld: Bool

        /// Places we were refused.
        let refused: UnreadablePlaces

        let ranAt: Date

        /// ⭐ Every real gap. Never a cloud file — `Coverage.isGap` will not allow it.
        var gaps: [Coverage] { coverage.filter(\.isGap) }

        /// Things we could not establish either way.
        var unknowns: [Coverage] { coverage.filter(\.isUnknown) }

        /// The row's own sentence.
        var headline: String {
            if !gaps.isEmpty {
                return gaps.count == 1
                    ? "\(gaps[0].name) is in no backup, and it is only on this Mac."
                    : "\(gaps.count.formatted()) things are only on this Mac and in no backup."
            }
            if !unknowns.isEmpty {
                return "Everything Wellkept could check is covered. \(unknowns.count.formatted()) "
                     + "things it could not check."
            }
            return "Everything Wellkept can see is in a backup."
        }

        /// Why it says that.
        ///
        /// ⚠️ **The cloud sentence is deliberately not here.** It is the measure on this row and it
        /// is the `why` on the cloud row underneath, and DESIGN §8 is explicit: the container is the
        /// answer, and what sits inside it does not repeat it. Storage shipped that exact bug — the
        /// free-space card and the row beneath it printed the same folder names an inch apart, and
        /// it was caught in a screenshot rather than by a test.
        var reason: String? {
            var parts: [String] = []
            if desktopAndDocumentsMirrored { parts.append(Coverage.desktopIsTwoNamesForOneFolder) }
            // ⚠️ Never a zero. A folder the walk was refused makes the cloud figure smaller than
            // the truth, and the caveat travels with the figure rather than being dropped.
            if let refusal = refused.sentence { parts.append(refusal) }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }

        /// The Options block: the iCloud evidence, the providers, and the grant.
        var detailPairs: [DetailPair] {
            var pairs = iCloud.detailPairs
            pairs.append(DetailPair("Full Disk Access",
                                    fullDiskAccessHeld ? "Granted" : "Not granted"))
            if !fullDiskAccessHeld {
                pairs.append(DetailPair("Without it a backup holds none of",
                                        ProtectedPlace.listSentence))
            }
            if cloudOnly.measured {
                pairs.append(DetailPair("Files in the cloud and not on this disk",
                                        cloudOnly.files.formatted()))
                pairs.append(DetailPair("What those files claim to weigh", cloudOnly.apparent.text))
            }
            if !providers.isEmpty {
                pairs.append(DetailPair("Other sync services mounted here",
                                        providers.joined(separator: ", ")))
            }
            pairs.append(DetailPair("Desktop and Documents",
                                    desktopAndDocumentsMirrored
                                        ? "Also reachable through iCloud Drive, as the same files"
                                        : "Ordinary folders on this disk"))
            return pairs
        }

        /// ⭐ **The section row.**
        ///
        /// Severity is `.attention` at most, never `.problem`: a file that lives in one place is a
        /// person's arrangement, not a malfunction. `BackupRow` clamps `.notCovered` to
        /// `.information` on its own when there is no real gap, so the two agree by construction.
        var row: BackupRow {
            BackupRow(topic: .notCovered,
                      headline: headline,
                      measure: cloudOnly.measured && !cloudOnly.isEmpty
                          ? "\(cloudOnly.apparent.text) not on this disk"
                          : nil,
                      reason: reason,
                      severity: gaps.isEmpty ? .information : .attention,
                      coverage: coverage,
                      details: detailPairs,
                      remedy: fullDiskAccessHeld
                          ? nil
                          : Remedy(title: "Open Full Disk Access", settingsPane: "fullDiskAccess"))
        }
    }

    /// ⭐ **One pass. Reads, never writes, never downloads, never opens another app's data.**
    ///
    /// - Parameters:
    ///   - timeMachine: the only evidence there is about what is in a backup. See the file header.
    ///   - home: the home folder. Injectable so the tests can point at a fixture.
    ///   - fullDiskAccessHeld: ⚠️ **passed in, never assumed.** A caller that hands in `true` when
    ///     it is false makes a backup that silently holds no mail, and `ContainerGuardTests` is the
    ///     reason nothing anywhere is allowed to hard-code it.
    ///   - countCloudFiles: the bounded walk. Off for a quick pass or a test.
    static func read(timeMachine: TimeMachineState,
                     home: URL = StorageManifest.home(),
                     fullDiskAccessHeld: Bool,
                     countCloudFiles: Bool = true,
                     now: Date = Date()) -> Reading {

        let iCloud = readICloud(home: home)
        let synced = iCloud.standing(of: "com.apple.Dataclass.CloudDesktop") == .on
        let mirrored = desktopAndDocumentsAreMirrored(home: home)

        var holding = CloudHolding.notMeasured
        var refused = UnreadablePlaces.sawEverything
        if countCloudFiles {
            let measurement = measureCloudOnly(home: home, desktopAndDocumentsSynced: synced || mirrored)
            holding = measurement.holding
            refused = measurement.refused
        }

        var rows: [Coverage] = []
        for place in Place.allCases {
            guard let row = coverage(of: place,
                                     presence: presence(of: place, home: home),
                                     iCloud: iCloud,
                                     timeMachine: timeMachine,
                                     now: now) else { continue }
            rows.append(row)
        }

        // The cloud holding is its own row rather than a note on iCloud Drive's. They are different
        // facts: iCloud Drive on this Mac is 258 files and 21.3 GB, of which 3 are placeholders,
        // while the 72 GB is almost entirely `~/Documents`.
        if let cloudSentence = holding.sentence {
            rows.append(Coverage(name: "Files that are in the cloud and not on this disk",
                                 lives: .onlyInTheCloud,
                                 included: .no,
                                 why: cloudSentence,
                                 bytes: holding.apparent))
        }

        let providers = fileProviders(home: home)
        for provider in providers {
            rows.append(Coverage(name: provider,
                                 lives: .onAnotherDrive,
                                 included: .no,
                                 why: whyAFileProviderIsNeverOpened(provider)))
        }

        return Reading(coverage: rows,
                       cloudOnly: holding,
                       providers: providers,
                       desktopAndDocumentsMirrored: mirrored,
                       iCloud: iCloud,
                       fullDiskAccessHeld: fullDiskAccessHeld,
                       refused: refused,
                       ranAt: now)
    }

    // MARK: ── ⭐ The two questions, answered separately ─────────────────────────────────────────

    /// ⭐ **Where a place's data lives.**
    ///
    /// ⚠️ `WhereItLives` has no "we do not know" case, and that is correct — it is the field that
    /// decides whether something can be a gap, and a fourth case would be a fourth thing for a
    /// screen to get wrong. So the doubt is carried in `why`, on the row, in words: **"macOS does
    /// not say whether this is in iCloud."** The conservative half is what is asserted — the data
    /// *is* on this Mac, which is measured — and the row says plainly that the other half is not
    /// known rather than filling it in.
    static func whereItLives(_ place: Place, iCloud: ICloudAccount) -> WhereItLives {
        switch place {
        case .homeFolder:
            // Parts of it are in the cloud, and those parts have their own rows. The folder as a
            // whole is on this disk.
            return .onlyOnThisMac
        default:
            return iCloud.standing(of: place.iCloudServiceID) == .on
                ? .inTheCloudAndHere
                : .onlyOnThisMac
        }
    }

    /// ⭐ **Whether it is in a backup**, from Time Machine's own published state and nothing else.
    ///
    /// See the table in the file header. The valuable answer is the first one: **a Mac with no
    /// backup has everything in no backup, and that is provable with no permission at all.**
    static func included(_ place: Place,
                         presence: Presence,
                         timeMachine: TimeMachineState,
                         now: Date) -> Included {
        if let why = presence.unreadable { return .notKnown(why) }

        switch timeMachine.standing(now: now) {
        case .notReadable:
            return .notKnown(.notReported)
        case .neverSetUp:
            // ⭐ Proven, and the finding this section exists to produce.
            return .no
        case .switchedOff, .waitingForTheDrive, .failing, .overdue, .working:
            // ⚠️ A backup that exists but is old is still a backup. **How old belongs to the Time
            // Machine row and is not repeated here** — DESIGN §8: the container is the answer.
            return timeMachine.lastSuccess == nil ? .no : .yes
        }
    }

    /// One place's row, or `nil` where there is nothing of it on this Mac.
    ///
    /// ⭐ **A place that is not here gets no row at all.** A Mac where Mail was never set up has no
    /// `~/Library/Mail`, and a row reading "Your Mail — in the backup" would be Wellkept reporting
    /// on something that does not exist. Verified 2026-08-29: `~/Library/Calendars` is exactly this
    /// case on this Mac — Calendar's store moved, and `stat` returns `ENOENT`.
    static func coverage(of place: Place,
                         presence: Presence,
                         iCloud: ICloudAccount,
                         timeMachine: TimeMachineState,
                         now: Date) -> Coverage? {
        guard presence.exists else { return nil }

        let lives = whereItLives(place, iCloud: iCloud)
        let verdict = included(place, presence: presence, timeMachine: timeMachine, now: now)

        var why = place.whatItIs
        if case .inAPlaceMacOSKeepsToItself = place.keeping {
            why += " " + whyAnotherAppsDataIsNeverOpened
        }
        if lives == .onlyOnThisMac, iCloud.standing(of: place.iCloudServiceID) == .notStated {
            why += " " + macOSDoesNotSayWhetherThisIsInICloud
        }
        if place.protected != nil {
            why += " " + whatFullDiskAccessCosts
        }

        return Coverage(name: place.label,
                        lives: lives,
                        included: verdict,
                        why: why,
                        bytes: presence.bytes,
                        needsFullDiskAccess: place.protected != nil)
    }

    // MARK: ── The sentences this file owns ──────────────────────────────────────────────────────

    /// ⚠️ Said on every row whose cloud standing macOS declines to state — 7 of the 10 named places
    /// on this Mac. It is the alternative to guessing, and guessing here is how a backup tool tells
    /// somebody their photos are safe.
    static let macOSDoesNotSayWhetherThisIsInICloud =
        "macOS does not say whether iCloud also has a copy, so Wellkept does not claim either way."

    /// ⚠️ Said on every row that Full Disk Access gates. **Not partial — nothing.**
    static let whatFullDiskAccessCosts =
        "Without Full Disk Access a backup contains none of this — not part of it, none — and macOS "
        + "gives no error when that happens."

    /// ⛔ Why Calendars, Reminders and Notes are reported without ever being opened.
    static let whyAnotherAppsDataIsNeverOpened =
        "macOS keeps this where it keeps every app's private data, and asking to look would put a "
        + "privacy question on your screen about an app you did not start. Wellkept never asks."

    /// ⛔ Why a third-party sync folder is named and left alone.
    static func whyAFileProviderIsNeverOpened(_ provider: String) -> String {
        "\(provider) appears in the Finder as a folder and is not one — its files live on \(provider)'s "
        + "servers and arrive as they are opened. Wellkept never looks inside it. Reading one of "
        + "these once timed out and stopped a scan, and had it not, it would have begun downloading "
        + "the whole account onto this disk."
    }
}

// MARK: - ⭐ What do I actually lose, and in which disaster

/// **The table that is the section's argument.**
///
/// Every backup tool tells a person whether a backup ran. Almost none tells them what a backup is
/// *for* — which of the five things that actually go wrong it covers, and which of them nothing
/// covers. This is that table, and two of its five rows are the reason it exists:
///
/// - ⭐ **Ransomware is the disaster the cloud makes worse, not better.** iCloud syncs the
///   encryption to every device within minutes. A backup drive that lives permanently plugged in
///   is reachable by the same software that reached the disk.
/// - ⭐ **Nothing covers a bad macOS update, and no product sells you the thing that does.** On
///   Apple silicon a system restore does not put the old macOS back — Recovery downloads its own
///   installer, and Migration Assistant then brings your files to whatever it installed. The only
///   protection is not being first.
///
/// ⚠️ **Sync is not a backup.** It is the single sentence this table exists to make unavoidable,
/// and `DisasterGuardTests` fails the build if the cloud is ever recorded as covering a mistaken
/// deletion or ransomware.
struct Disaster: Sendable, Hashable, Identifiable {

    /// The five things that actually happen to people's Macs.
    enum Kind: String, Sendable, Hashable, CaseIterable, Identifiable {
        case theDriveDies
        case theMacIsStolen
        case ransomware
        case aFileDeletedByMistake
        case aBadMacOSUpdate

        var id: String { rawValue }

        /// Said the way a person would say it, in the present tense, without drama.
        var label: String {
            switch self {
            case .theDriveDies:          "The disk dies"
            case .theMacIsStolen:        "The Mac is stolen or lost"
            case .ransomware:            "Something encrypts your files and asks for money"
            case .aFileDeletedByMistake: "You delete something by mistake"
            case .aBadMacOSUpdate:       "A macOS update goes wrong"
            }
        }
    }

    /// Whether a thing covers a disaster. Three answers, and the middle one is the honest one most
    /// of the time.
    enum Cover: Sendable, Hashable {
        /// It covers this. The string is the condition it still depends on.
        case yes(String)
        /// It covers this only under a condition that is not automatic.
        case onlyIf(String)
        /// It does not cover this, and here is why not.
        case no(String)

        var label: String {
            switch self {
            case .yes:    "Covered"
            case .onlyIf: "Only if"
            case .no:     "Not covered"
            }
        }

        var detail: String {
            switch self {
            case .yes(let s), .onlyIf(let s), .no(let s): return s
            }
        }

        /// ⚠️ **`.onlyIf` is not covered.** A condition somebody has to have arranged in advance is
        /// not protection they have; it is protection they might have. Everywhere this feeds a
        /// count or a colour, it counts as no.
        var isCovered: Bool { if case .yes = self { return true }; return false }
    }

    let kind: Kind

    /// What is actually lost, in one sentence, if nothing covers it.
    let whatIsLost: String

    /// Time Machine's answer.
    let timeMachine: Cover

    /// iCloud's — or any sync service's — answer.
    let theCloud: Cover

    /// ⭐ What nothing covers. `nil` where something does.
    let coveredByNothing: String?

    var id: Kind { kind }

    /// Whether this disaster has an answer at all.
    var isCovered: Bool { timeMachine.isCovered || theCloud.isCovered }

    /// The Options lines for one disaster.
    var detailPairs: [DetailPair] {
        var pairs = [
            DetailPair("Time Machine", "\(timeMachine.label) — \(timeMachine.detail)"),
            DetailPair("iCloud and other sync services", "\(theCloud.label) — \(theCloud.detail)"),
        ]
        if let coveredByNothing {
            pairs.append(DetailPair("Nothing covers", coveredByNothing))
        }
        return pairs
    }

    /// ⭐ **The table.** Fixed order, most likely first.
    static let table: [Disaster] = [

        Disaster(kind: .theDriveDies,
                 whatIsLost: "Everything on the disk, at once, with no warning.",
                 timeMachine: .yes("everything up to its last successful backup is on the backup "
                                 + "drive. Anything changed since then is not."),
                 theCloud: .yes("whatever iCloud was syncing is on Apple's servers and comes back "
                              + "when you sign in on another Mac."),
                 coveredByNothing: "Anything changed since the last backup that iCloud was not "
                                 + "also syncing."),

        Disaster(kind: .theMacIsStolen,
                 whatIsLost: "The Mac, and every copy of your files that was in the same bag.",
                 timeMachine: .onlyIf("the backup drive was somewhere else. A drive that lives "
                                    + "plugged into the Mac is stolen with the Mac."),
                 theCloud: .yes("it is not in the building, which is the one thing that matters "
                              + "here."),
                 coveredByNothing: "Nothing, if the drive was elsewhere. Everything not in iCloud, "
                                 + "if it was not."),

        // ⭐ The row the section is for.
        Disaster(kind: .ransomware,
                 whatIsLost: "Every file it could reach, scrambled, including the ones it reached "
                           + "through iCloud.",
                 timeMachine: .onlyIf("the drive was unplugged, or the damage is noticed before an "
                                    + "encrypted backup runs over the good ones. A drive that is "
                                    + "always connected is reachable by the same software."),
                 theCloud: .no("sync is not a backup. It copies the encrypted files to every device "
                             + "you own, usually within minutes, and calls it success."),
                 coveredByNothing: "Anything whose only other copy was a drive that was plugged in "
                                 + "at the time."),

        Disaster(kind: .aFileDeletedByMistake,
                 whatIsLost: "One file, or one folder, and usually you notice weeks later.",
                 timeMachine: .yes("it keeps hourly versions, so you can go back to the day before "
                                 + "you deleted it — as far back as the drive has room for."),
                 theCloud: .no("deleting a file deletes it on every device. iCloud Drive and Photos "
                             + "each hold it for 30 days and then it is gone everywhere at once."),
                 coveredByNothing: "Anything deleted longer ago than your backup drive has room to "
                                 + "remember."),

        // ⛔ The row nobody sells you anything for.
        Disaster(kind: .aBadMacOSUpdate,
                 whatIsLost: "Not usually your files — the use of your Mac, for as long as it takes.",
                 timeMachine: .no("it restores your files, not the version of macOS you were on. On "
                                + "an Apple silicon Mac, Recovery downloads its own installer and "
                                + "never reads one from your drive."),
                 theCloud: .no("it holds files. It has nothing to say about which macOS you are on."),
                 coveredByNothing: "Going back to the macOS you were on. The only thing that helps "
                                 + "is not installing a new one the week it comes out."),
    ]

    /// ⭐ The disasters nothing covers. On any Mac, this is never empty, and saying so is the point.
    static var coveredByNothing: [Disaster] { table.filter { !$0.isCovered } }

    /// The law, in one sentence, kept where a test can find it.
    static let syncIsNotABackup =
        "A sync service keeps every device the same. That is the opposite of a backup, which keeps "
        + "yesterday. Deleting a file, or encrypting one, is copied everywhere just as faithfully "
        + "as writing one."

    /// ⛔ Recorded so nobody proposes shipping a macOS installer on the backup drive again.
    static let whyThereIsNoInstallerOnTheDrive =
        "On an Apple silicon Mac, Recovery downloads its own copy of macOS and never reads one from "
        + "your drive. An 18.4 GB installer on the backup drive helps in one case only: another "
        + "working Mac, and bad internet."
}

// MARK: - The sentence that belongs to Coverage

extension Coverage {

    /// ⭐ **The double-count trap, in words**, kept beside the type it is about rather than in the
    /// reader, because the copier needs it too.
    ///
    /// Measured 2026-08-29: `~/Desktop/SetShot.app` and its iCloud Drive twin are inode `71114060`
    /// on the same device. One file, two names.
    static let desktopIsTwoNamesForOneFolder =
        "Your Desktop and Documents folders also appear inside iCloud Drive. They are not two "
        + "copies — they are the same files under two names, so anything counting both would count "
        + "your files twice."
}
