import Foundation
import WellkeptCore

//  StorageManifest.swift
//  Wellkept — App/Storage
//
//  **Everything Wellkept writes outside its own app bundle is declared here, and nowhere else.**
//
//  ## Why this file exists
//
//  An uninstaller that keeps its own list of what to delete is a list that goes stale the first
//  time a section writes a new file — and it goes stale silently. Nothing fails; the app is in the
//  Trash and its 4 GB of cached scan results are still on the disk, in a folder nobody would think
//  to look in. Scout hit the general form of this: dragging it to the Trash left 349 MB of mail
//  index behind, which is why its inventory was moved out of the uninstaller and made testable.
//
//  So the rule for every owner adding storage to Wellkept:
//
//  1. Get the URL from this file. Never build a path to `Application Support` yourself.
//  2. If it is a new kind of file, add one `Entry` to `entries` and say what it is in the user's
//     words and how uninstall should treat it. That is the whole cost.
//
//  ## What the dispositions mean
//
//  `Disposition` is the load-bearing part. It is what stops the uninstaller from having a policy
//  of its own — the policy travels with the file, so a section that adds a folder full of the
//  user's own recovered documents cannot have it swept up by a later change to the uninstaller.

enum StorageManifest {

    // MARK: - Preference keys

    /// Every `UserDefaults` key Wellkept writes.
    ///
    /// The five appearance keys live on `AppearancePrefs` (they are read by views through
    /// `@AppStorage`); the rest are here. Both halves are listed in `all`, because the uninstaller
    /// and any future "reset everything" need the whole set and neither should have to know that
    /// it is kept in two places.
    ///
    /// ⚠️ **Raw strings are permanent.** They are already on disk in a user's plist; renaming one
    /// is a migration, and a build that reads back an unknown key silently forgets the setting.
    enum Keys {
        /// Set once the welcome + permissions flow has been through to the end, whether the user
        /// granted anything or pressed Finish later.
        ///
        /// **The uninstaller removes it, which is the whole mechanism behind "setup runs again
        /// after a reinstall but not after an update"** — an update leaves the plist alone.
        static let setupFinished = "setupFinished"

        /// Fills the seven sections with invented results, for looking at the app without a real
        /// scan. Never on by default, and never a state a real check can leave the app in.
        static let demoMode = "demoMode"

        /// Which invented Mac demo mode shows — `healthy` or `problems`. See `DemoMachine`.
        ///
        /// Kept separately from `demoMode` so that turning the demo off and on again does not
        /// silently move somebody back to a machine they did not pick.
        static let demoMachine = "demoMachine"

        /// Whether the setup flow has already asked for Full Disk Access once.
        ///
        /// Wellkept never raises a refused permission again on its own, so this exists to make
        /// *not* asking possible. It is not a record of the answer — the answer is read from the
        /// system, which is the only honest source.
        static let fullDiskAccessAsked = "fullDiskAccessAsked"

        /// Where the user pointed Backup. Read by the uninstaller for one reason only: to say
        /// where the backups are while leaving them exactly where they are.
        static let backupDestination = "backupDestination"

        /// Whether Wellkept may ask anybody whether your apps are current.
        ///
        /// ⚠️ **Taken from `Privacy.Departure`, never typed.** The key is a fact about a departure
        /// from this Mac, and a second copy of the literal is a second thing to keep in step. Stored
        /// as an optional Bool: absent means nobody has been asked yet, which is a real third state
        /// and the reason the Apps section puts the question up on its first run.
        static let checkAppUpdates = Privacy.Departure.appUpdateCheck.settingsKey

        /// Whether Wellkept may check for a newer Wellkept. Same shape, same register.
        static let checkWellkeptUpdates = Privacy.Departure.wellkeptUpdateCheck.settingsKey

        /// Every key the app writes, appearance included.
        static let all: [String] = [
            AppearancePrefs.modeKey,
            AppearancePrefs.colorLevelKey,
            AppearancePrefs.identityKey,
            AppearancePrefs.fontFamilyKey,
            AppearancePrefs.textScaleKey,
            setupFinished,
            demoMode,
            demoMachine,
            fullDiskAccessAsked,
            backupDestination,
            checkAppUpdates,
            checkWellkeptUpdates,
        ]
    }

    // MARK: - Where things live

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "studio.stonemesa.wellkept"
    }

    static func home(_ fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
    }

    /// `~/Library/Application Support/Wellkept` — everything the app writes for itself.
    static func supportDirectory(home: URL = home()) -> URL {
        home.appending(path: "Library/Application Support/Wellkept")
    }

    /// Where quarantined items are held for their thirty days.
    ///
    /// ⚠️ **This folder holds the user's own files, and it is the one place in the app where that
    /// is true.** Nothing may empty it on a schedule, on quit, or as a side effect of anything
    /// else. The uninstaller asks about it by name; see `Disposition.ask`.
    static func quarantineDirectory(home: URL = home()) -> URL {
        supportDirectory(home: home).appending(path: "Quarantine")
    }

    /// The record of what is in quarantine and where each item came from.
    ///
    /// Kept beside the files rather than inside them: an item's original path is the only thing
    /// that makes "Put Them Back" possible, and a folder of orphaned files with no record of where
    /// they belong is exactly the "buried" outcome John ruled out.
    static func quarantineLedger(home: URL = home()) -> URL {
        supportDirectory(home: home).appending(path: "Quarantine.json")
    }

    /// The dated history of every check Wellkept has run.
    static func historyStore(home: URL = home()) -> URL {
        supportDirectory(home: home).appending(path: "History.json")
    }

    /// Every individual reading Wellkept has ever taken — a battery percentage, a disk speed —
    /// one JSON object per line, appended from the first launch.
    ///
    /// Separate from `historyStore` because the two answer different questions and have different
    /// shapes. That one is the audit trail: which section ran, when, and what it concluded. This
    /// one is the numbers, kept so the app can eventually say "slower than it used to be" about a
    /// machine whose own records go back eight days. See `ReadingHistory`.
    static func readingHistory(home: URL = home()) -> URL {
        supportDirectory(home: home).appending(path: "Readings.jsonl")
    }

    /// Every thermal-pressure reading Wellkept has taken — one JSON object per line.
    ///
    /// Separate from `readingHistory` because thermal pressure is not one of the five Hardware
    /// rows, and `ReadingSample` is keyed by `HardwareTopic`. Filing it under a topic it does not
    /// belong to would make `ReadingHistory.latest(_:)` hand a thermal reading to whichever reader
    /// owns that topic. See `ThermalHistory`.
    static func thermalHistory(home: URL = home()) -> URL {
        supportDirectory(home: home).appending(path: "Thermal.jsonl")
    }

    /// Where the user pointed Backup, if they have. `nil` until they do.
    ///
    /// A path string rather than a security-scoped bookmark because Wellkept is unsandboxed and
    /// has no need of one; if that ever changes, this is the single place it changes.
    static func backupDestination(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: Keys.backupDestination), !path.isEmpty else {
            return nil
        }
        return URL(filePath: path)
    }

    // MARK: - The inventory

    /// How uninstall must treat one thing Wellkept has written.
    enum Disposition: Sendable {
        /// Wellkept's own bookkeeping. Deleted without a separate question — removing the app is
        /// the question.
        case delete
        /// The user's own files. **Never deleted, never decided for them.** The uninstaller stops
        /// and asks what should happen to these.
        case ask
        /// Not ours to touch under any circumstances. Named in the closing dialog so the user
        /// knows it survived, and then left alone.
        case leave
    }

    /// One thing Wellkept has put on the disk, named the way a person would name it rather than
    /// by its path.
    struct Entry: Identifiable, Sendable, Equatable {
        let title: String
        /// What it is, in the fewest plain words that carry it. Shown to a person who is about to
        /// agree to delete it.
        let detail: String
        let url: URL
        let bytes: Int64
        let disposition: Disposition

        var id: String { url.path }
    }

    /// Everything that actually exists on this Mac right now, largest concern first.
    ///
    /// ⚠️ **Add a line here when you add a file. That is the only thing you have to remember.**
    /// Nothing filters this list by hand afterwards — the uninstaller groups it by `disposition`,
    /// so a new entry gets the right treatment whether or not anybody edits the uninstaller.
    ///
    /// Paths that do not exist are dropped rather than listed at zero bytes: offering to delete
    /// files a person does not have reads as an app that has not looked.
    static func entries(
        home: URL = home(),
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> [Entry] {
        var found: [Entry] = []

        func add(_ title: String, _ detail: String, _ url: URL, _ disposition: Disposition) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            found.append(Entry(title: title, detail: detail, url: url,
                               bytes: size(of: url, fileManager: fileManager),
                               disposition: disposition))
        }

        add("Quarantine",
            "Items Wellkept set aside for you, and the record of where each one came from",
            quarantineDirectory(home: home), .ask)

        add("Check history",
            "The dated record of every check Wellkept has run on this Mac",
            historyStore(home: home), .delete)

        add("Readings",
            "The numbers Wellkept has read from this Mac over time — battery, drive speed and the rest",
            readingHistory(home: home), .delete)

        add("Thermal record",
            "How often macOS has said this Mac was running hot",
            thermalHistory(home: home), .delete)

        add("Settings",
            "Appearance, text size, and whether setup has run",
            home.appending(path: "Library/Preferences/\(bundleIdentifier).plist"), .delete)

        add("Saved window state",
            "Where the window was and how big",
            home.appending(path: "Library/Saved Application State/\(bundleIdentifier).savedState"),
            .delete)

        add("Caches",
            "Temporary files macOS keeps for every app",
            home.appending(path: "Library/Caches/\(bundleIdentifier)"), .delete)

        add("Stored web data",
            "Cookies and credentials macOS keeps per app — Wellkept writes none",
            home.appending(path: "Library/HTTPStorages/\(bundleIdentifier)"), .delete)

        // ⚠️ **There is deliberately no catch-all entry for `~/Library/Application Support/
        // Wellkept` itself, and there must never be one.** `removeItem` on a folder is recursive,
        // and that folder contains the quarantine — the one place in this app that holds the
        // user's own files. A tidy-looking "delete Wellkept's folder" line would destroy them
        // while doing exactly what it was told, and the person who lost them would have been shown
        // a dialog that never mentioned it.
        //
        // The folder is cleared up by `tidyEmptyFolders()` after the declared entries are gone,
        // and only while it is empty. Litter beats loss.
        //
        // The ledger is not a declared entry either: items that could not be handed back are still
        // in quarantine, and the ledger is the only record of where each of them came from.

        if let backups = backupDestination(defaults: defaults),
           fileManager.fileExists(atPath: backups.path) {
            found.append(Entry(title: "Your backups",
                               detail: "The copies of your files Wellkept made for you",
                               url: backups,
                               // Not measured. Walking an external backup volume to put a number
                               // in a dialog is minutes of disk I/O for a figure nobody acts on,
                               // and the sentence beside it is "left alone" either way.
                               bytes: 0,
                               disposition: .leave))
        }

        return found
    }

    /// What macOS will not let an app take back on its own.
    ///
    /// There is no API to revoke a privacy grant — by design, since an app that could revoke its
    /// own permissions could grant them too. Saying so is the only honest option; the alternative
    /// is a person believing Wellkept is gone while System Settings still lists it.
    static let permissionsOnlyTheUserCanRemove = ["Full Disk Access", "Files and Folders"]

    // MARK: - Measuring

    /// Bytes on disk, walking into a folder rather than reporting the folder's own 64 bytes.
    static func size(of url: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

        func bytes(_ item: URL) -> Int64 {
            guard let values = try? item.resourceValues(forKeys: keys) else { return 0 }
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return bytes(url) }

        guard let walk = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let child as URL in walk { total += bytes(child) }
        return total
    }

    /// "4.2 GB", for a sentence rather than a table.
    static func readable(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Deleting

    /// Delete the entries whose disposition says so, and report whatever survived rather than
    /// claiming a clean sweep.
    ///
    /// ⚠️ **Filters on `.delete` itself rather than trusting the caller to have filtered.** One
    /// mistaken call site is all it takes for this function to be handed the quarantine folder,
    /// and that folder holds the user's own files.
    ///
    /// One failure does not stop the rest: a locked cache file must not leave the check history
    /// on the disk.
    @discardableResult
    static func delete(_ entries: [Entry], fileManager: FileManager = .default) -> [Entry] {
        entries.filter { entry in
            guard entry.disposition == .delete else { return false }
            do {
                try fileManager.removeItem(at: entry.url)
                return false
            } catch {
                return fileManager.fileExists(atPath: entry.url.path)
            }
        }
    }

    /// Clear up Wellkept's own folders — **only while they are empty, and never recursively.**
    ///
    /// This is the whole of the catch-all, and its narrowness is the point. Anything still inside
    /// the quarantine is something a person asked to keep, or something that could not be handed
    /// back; either way it stays, along with the ledger that says where each item came from.
    static func tidyEmptyFolders(home: URL = home(), fileManager: FileManager = .default) {
        func isEmpty(_ url: URL) -> Bool {
            let contents = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? ["not-empty"]
            return contents.isEmpty
        }

        let quarantine = quarantineDirectory(home: home)
        if fileManager.fileExists(atPath: quarantine.path), isEmpty(quarantine) {
            try? fileManager.removeItem(at: quarantine)
            // Safe only now: with the folder gone there is nothing left whose origin the ledger
            // was the sole record of.
            try? fileManager.removeItem(at: quarantineLedger(home: home))
        }

        let support = supportDirectory(home: home)
        if fileManager.fileExists(atPath: support.path), isEmpty(support) {
            try? fileManager.removeItem(at: support)
        }
    }

    /// Forget every setting without touching a file — the in-process half of the same job.
    ///
    /// Deleting the preferences plist is not enough on its own while the app is running: macOS
    /// holds the defaults in memory and writes them back out on quit, resurrecting the file that
    /// was just deleted.
    static func forgetPreferences(defaults: UserDefaults = .standard) {
        for key in Keys.all { defaults.removeObject(forKey: key) }
    }
}

// MARK: - Quarantine

/// One item Wellkept set aside, and where it came from.
///
/// Written by whichever section quarantines something; read by the uninstaller and by the
/// quarantine browser. Nothing else may define a second shape for this — the record IS the undo,
/// and a file whose origin was recorded in two formats is a file that cannot be put back.
struct QuarantineRecord: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    /// Where it was when Wellkept took it.
    let originalPath: String
    /// Where it is now, inside `StorageManifest.quarantineDirectory()`.
    let quarantinedPath: String
    let quarantinedOn: Date
    /// Why it was set aside, in the user's words. Shown on the row.
    let reason: String

    init(id: UUID = UUID(), originalPath: String, quarantinedPath: String,
         quarantinedOn: Date = Date(), reason: String) {
        self.id = id
        self.originalPath = originalPath
        self.quarantinedPath = quarantinedPath
        self.quarantinedOn = quarantinedOn
        self.reason = reason
    }

    var originalURL: URL { URL(filePath: originalPath) }
    var quarantinedURL: URL { URL(filePath: quarantinedPath) }
}

/// Reading, restoring and handing over the quarantine.
///
/// ⚠️ **Nothing in here deletes anything, and nothing in here overwrites anything.** Both are
/// deliberate and both are load-bearing. Quarantine exists so that a mistake costs thirty days of
/// patience instead of a file; a "restore" that clobbered whatever now sits at the original path
/// would turn the undo into a second, worse deletion.
enum Quarantine {

    /// What is in quarantine right now. An unreadable or absent ledger reads as empty, which is
    /// the honest answer — it is also what a fresh install looks like.
    static func records(home: URL = StorageManifest.home()) -> [QuarantineRecord] {
        let ledger = StorageManifest.quarantineLedger(home: home)
        guard let data = try? Data(contentsOf: ledger),
              let records = try? JSONDecoder().decode([QuarantineRecord].self, from: data)
        else { return [] }
        // A record whose file is already gone is a record of nothing. Listing it would offer to
        // restore something that cannot be restored.
        return records.filter { FileManager.default.fileExists(atPath: $0.quarantinedPath) }
    }

    static func write(_ records: [QuarantineRecord], home: URL = StorageManifest.home()) throws {
        let support = StorageManifest.supportDirectory(home: home)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: StorageManifest.quarantineLedger(home: home))
    }

    /// Put each item back where it came from, and report the ones that could not go back.
    ///
    /// ⚠️ **An occupied original path is a refusal, not an overwrite.** Between quarantining and
    /// restoring, the user may have made a new file with the same name — re-downloaded the
    /// installer, saved the document again. Moving over it would destroy the newer one, and the
    /// person would have asked for the opposite of that.
    @discardableResult
    static func restore(_ records: [QuarantineRecord],
                        fileManager: FileManager = .default) -> [QuarantineRecord] {
        records.filter { record in
            let destination = record.originalURL
            guard !fileManager.fileExists(atPath: destination.path) else { return true }
            do {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try fileManager.moveItem(at: record.quarantinedURL, to: destination)
                return false
            } catch {
                return true
            }
        }
    }

    /// Move every quarantined item into a folder the user picked, and report what would not move.
    ///
    /// A name already taken in the destination gets a numbered suffix rather than replacing what
    /// is there — same reason as `restore`.
    @discardableResult
    static func handOver(_ records: [QuarantineRecord], to folder: URL,
                         fileManager: FileManager = .default) -> [QuarantineRecord] {
        records.filter { record in
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try fileManager.moveItem(at: record.quarantinedURL,
                                         to: freeName(in: folder,
                                                      for: record.quarantinedURL.lastPathComponent,
                                                      fileManager: fileManager))
                return false
            } catch {
                return true
            }
        }
    }

    /// A URL in `folder` that nothing occupies: "report.pdf", then "report 2.pdf", and so on.
    static func freeName(in folder: URL, for name: String,
                         fileManager: FileManager = .default) -> URL {
        let candidate = folder.appending(path: name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for n in 2...999 {
            let tried = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let url = folder.appending(path: tried)
            if !fileManager.fileExists(atPath: url.path) { return url }
        }
        // A thousand collisions on one name is not a real folder, but returning a colliding URL
        // would hand `moveItem` a destination it will refuse — a caught failure, not a lost file.
        return folder.appending(path: "\(base) \(UUID().uuidString)")
    }
}
