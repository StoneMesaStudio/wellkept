// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  Ledger.swift
//  Wellkept — App/Quarantine
//
//  ⭐ **The record. It IS the undo — a quarantined file with no record is a file nobody can put
//  back, and every screen in the app would say the quarantine was empty while it sat there.**
//
//  There is **one** ledger, at `StorageManifest.quarantineLedger()`. Nothing else may keep a second
//  copy of where a file came from. A file whose origin was written down in two formats is a file
//  that cannot be restored, because the two will disagree and neither will be obviously wrong.
//
//  ## What a record has to hold, and why each field is there
//
//  A path is not an identity on this filesystem. It folds case AND Unicode normalisation:
//  `CaseTest.txt` is found at `casetest.TXT`, and an NFD spelling opens the NFC file. So every
//  record carries **both** — the path, spelled the way the filesystem spells it, and a
//  `FileIdentity` that is not a path at all: the volume's UUID, the volume's device, and the inode.
//
//  ⚠️ **The inode is the durable half, and it survives precisely because of how the file was
//  moved.** A same-volume rename re-points a directory entry; the inode does not change. So the
//  identity written down before the move is still true of the file sitting in the store, and a
//  restore can prove it is putting back the thing it took rather than something that has since
//  moved into the same name.
//
//  Everything else in the record exists so that "put it back" means *exactly* back: mode, owner,
//  group, BSD flags, creation date, modification date, size, and whether it was a folder or a
//  symbolic link.
//
//  ## Atomic writes, and the bug that was already found here
//
//  ⚠️ `StorageManifest.write` used a plain `write(to:)` — a truncate-in-place. A badly timed crash
//  left half a JSON array, which decodes to nothing: every quarantined file orphaned, no record of
//  where any of them came from, and every screen in the app reporting an empty quarantine. Fixed to
//  `.atomic` on 2026-08-28, before anything was built on it. **Do not regress it, anywhere in this
//  file.** `.atomic` writes a temporary beside the target and renames it into place, which is the
//  same one safe move the rest of this engine is built on.
//
//  ## ⚠️ Empty is not the same as could-not-look
//
//  The old `records()` returned `[]` for a permissions failure, a corrupt ledger, and a fresh
//  install alike. That breaks the app's own rule — *never report zero because we could not look* —
//  in the one place where zero means somebody's files are unaccounted for. `LedgerReading` has three
//  cases and no way to collapse them by accident: `.fresh`, `.items`, `.unreadable`. A corrupt
//  ledger is **never deleted and never rewritten**; it is copied aside under a dated name, and the
//  trouble is carried in the reading so the screen can say so.
//
//  ## The crash states, all of them
//
//  A move is atomic, so there is no half-moved file. What can be interrupted is the *bookkeeping*
//  between the move and the ledger. The intent journal closes that window: the full record for every
//  item in a batch is written to `Quarantine-intent.json` **before the first move**, and the file is
//  removed after the ledger is updated. `reconcile()` runs at launch and can therefore see exactly
//  five states, and no others:
//
//  | On disk | What happened | What reconcile does |
//  |---|---|---|
//  | No intent file | Nothing was in flight | Nothing |
//  | Intent, item still at its original path | The move never ran | Drops it; nothing changed |
//  | Intent, item in the store, no ledger record | Moved, crash before the ledger | Adds the record |
//  | Intent, item in the store, ledger record present | Moved and recorded, crash before cleanup | Drops the intent |
//  | Intent, item at neither path | Something outside Wellkept took it | Reports it, loudly |
//
//  The last row is the only one that loses information, and it is the only one that cannot be caused
//  by this app.

// MARK: - Identity that is not a path

/// What a file is, as opposed to what it is called.
///
/// ⚠️ **This is the field that separates Wellkept from every catastrophe on the list.** Adobe's
/// updater chose by alphabetical position. Pearcleaner's orphan detector chose by vendor name. Apple
/// Music chose by inference. All three had a name and no identity.
struct FileIdentity: Codable, Sendable, Equatable, Hashable {

    /// The volume's own UUID, when it has one. Survives unmounting, remounting and renaming.
    let volumeUUID: String?

    /// `f_mntfromname`. ⚠️ The only reading that separates the sealed System volume from the Data
    /// volume — they share a device number and a display name.
    let volumeDevice: String

    /// `st_ino`. Unchanged by a same-volume rename, which is the whole reason that is the only move
    /// this engine makes.
    let inode: UInt64

    init(volumeUUID: String?, volumeDevice: String, inode: UInt64) {
        self.volumeUUID = volumeUUID
        self.volumeDevice = volumeDevice
        self.inode = inode
    }

    init(_ reading: FileReading) {
        self.init(volumeUUID: reading.volume.uuid,
                  volumeDevice: reading.volume.device,
                  inode: reading.inode)
    }

    /// Whether the thing at `path` right now is this same file.
    ///
    /// Used before a restore and before a delete: between the two moments somebody may have replaced
    /// the file in the store by hand, and acting on the wrong inode is the failure this exists to
    /// catch.
    ///
    /// ⚠️ **An inode number alone is not an identity.** Inode numbers are handed out per volume and
    /// they start small, so a freshly made file on a plugged-in drive routinely carries the same
    /// number as one in the home folder. The volume has to be part of the comparison or this
    /// function says yes to the wrong file on the wrong disk — which is the exact shape of every
    /// catastrophe on the list, arrived at by arithmetic instead of by name.
    func stillDescribes(_ path: String) -> Bool {
        var status = stat()
        guard lstat(path, &status) == 0 else { return false }
        guard UInt64(status.st_ino) == inode else { return false }
        return isOnTheSameVolume(as: Movable.volume(of: path))
    }

    /// The volume half of the comparison, separated so a scan can read the volume once for a path
    /// and test it against a whole list without a `statfs` per entry.
    ///
    /// ⚠️ **The UUID is preferred and the device is only the fallback, because devices renumber.**
    /// `/dev/disk3s5` can come back as `/dev/disk4s5` after a reboot with a drive plugged in, and a
    /// strict device comparison would then refuse to restore somebody's files with "that is not the
    /// same file" — stranding them for a reason that has nothing to do with the file. The UUID does
    /// not move. An unreadable volume is treated as a match: the inode has already agreed, and
    /// refusing on a reading we could not take would strand the restore for the same bad reason.
    func isOnTheSameVolume(as volume: VolumeReading?) -> Bool {
        guard let volume else { return true }
        if let mine = volumeUUID, let theirs = volume.uuid { return mine == theirs }
        return volumeDevice == volume.device
    }
}

// MARK: - Containment, for a malware find

/// What was done to a file to make it harmless without moving it, and everything needed to undo it.
///
/// ⚠️ **Zipping the store was rejected, 2026-08-28, and must not come back.** An archive drops the
/// metadata a rename preserves, and for a malicious file it does the opposite of what it looks like
/// it does: it *hides* the file from macOS's own scanner rather than defusing it.
///
/// Containment is two reversible, recorded changes: **remove the execute bit**, so nothing can run
/// it, and **mark it untrusted**, so macOS treats it as something that came off the internet and was
/// never approved. Both are undone exactly by `Quarantine.release`.
struct Containment: Codable, Sendable, Equatable, Hashable {

    /// The permissions before the execute bits were cleared.
    let modeBefore: UInt16

    /// The download-provenance attribute as it was, or `nil` if the file had none. Restored byte for
    /// byte, including its absence.
    let untrustedMarkBefore: String?

    /// What Wellkept wrote in its place.
    let untrustedMarkNow: String

    let containedOn: Date
}

// MARK: - One record

/// One item Wellkept set aside, and everything needed to put it back exactly.
///
/// ⚠️ **`sectionRaw` is a string and not a `SectionID` on purpose.** A ledger written by a later
/// build, naming a section this one has never heard of, must still decode — otherwise one unknown
/// word orphans every file in the list. A record whose section is unrecognised is still a record of
/// where somebody's file came from, which is the only thing this type exists to protect.
struct QuarantineRecord: Codable, Sendable, Identifiable, Equatable, Hashable {

    let id: UUID

    // MARK: Where it came from

    /// The path it had, spelled the way the filesystem spells it.
    let originalPath: String

    /// Its own name, kept separately because it is what the row shows and what the store folder
    /// holds. Splitting the path at restore time would re-derive it, and re-deriving something that
    /// was already known is how spellings drift.
    let originalName: String

    /// ⚠️ The identity. See `FileIdentity`.
    let identity: FileIdentity

    // MARK: Where it is now

    let quarantinedPath: String

    /// The store's root, so an item on a disk that is no longer plugged in can be named as such
    /// rather than reported missing.
    let storeRoot: String

    // MARK: Everything needed to put it back exactly

    let mode: UInt16
    let ownerID: UInt32
    let groupID: UInt32
    let flags: UInt32
    let createdOn: Date?
    let modifiedOn: Date?
    let bytes: Int64
    let isDirectory: Bool
    let isSymbolicLink: Bool

    /// The permissions of the folder it came out of.
    ///
    /// ⚠️ **Restoring into a folder that no longer exists means making that folder**, and a folder
    /// made with the default mask is not the folder that was there. Recorded at quarantine time
    /// because it cannot be recovered afterwards. `nil` only for a record written before this was
    /// kept, or where the parent could not be read.
    ///
    /// Ownership is deliberately not restored: `chown` to another user needs root, and Wellkept
    /// ships no privileged helper. The file's own ownership needs no restoring — a rename does not
    /// touch it.
    let parentMode: UInt16?

    // MARK: Who asked, why, and when

    /// The section that asked. Stored raw — see the note on the type.
    let sectionRaw: String

    /// Why it was set aside, in the user's words. Shown on the row.
    let reason: String

    let quarantinedOn: Date

    /// Whether it was somewhere iCloud syncs. Drives John's one line — *"This also removes it from
    /// your iPhone and iPad."* — and nothing else. An iCloud file is allowed, never refused.
    let wasInICloud: Bool

    /// Set only for a malware find that was defused in place rather than moved.
    let containment: Containment?

    var section: SectionID? { SectionID(rawValue: sectionRaw) }
    var originalURL: URL { URL(filePath: originalPath) }
    var quarantinedURL: URL { URL(filePath: quarantinedPath) }
    var storeURL: URL { URL(filePath: storeRoot) }

    /// The folder in the store that holds this one item. Removed once the item is out of it.
    var holderURL: URL { URL(filePath: storeRoot).appending(path: id.uuidString) }

    /// Was it defused in place rather than moved aside?
    var wasContainedInPlace: Bool { containment != nil && quarantinedPath == originalPath }

    init(id: UUID = UUID(),
         originalPath: String,
         originalName: String,
         identity: FileIdentity,
         quarantinedPath: String,
         storeRoot: String,
         mode: UInt16,
         ownerID: UInt32,
         groupID: UInt32,
         flags: UInt32,
         createdOn: Date?,
         modifiedOn: Date?,
         bytes: Int64,
         isDirectory: Bool,
         isSymbolicLink: Bool,
         parentMode: UInt16?,
         section: SectionID,
         reason: String,
         quarantinedOn: Date = Date(),
         wasInICloud: Bool,
         containment: Containment? = nil) {
        self.init(id: id, originalPath: originalPath, originalName: originalName,
                  identity: identity, quarantinedPath: quarantinedPath, storeRoot: storeRoot,
                  mode: mode, ownerID: ownerID, groupID: groupID, flags: flags,
                  createdOn: createdOn, modifiedOn: modifiedOn, bytes: bytes,
                  isDirectory: isDirectory, isSymbolicLink: isSymbolicLink,
                  parentMode: parentMode, sectionRaw: section.rawValue, reason: reason,
                  quarantinedOn: quarantinedOn, wasInICloud: wasInICloud,
                  containment: containment)
    }

    /// The same thing, taking the section as the raw string.
    ///
    /// ⚠️ **Only for rebuilding a record that already exists** — decoding one, or rewriting one with
    /// containment on it. A section that was written by a build this one has never heard of keeps its
    /// own word instead of being flattened into whichever case seemed closest.
    init(id: UUID,
         originalPath: String,
         originalName: String,
         identity: FileIdentity,
         quarantinedPath: String,
         storeRoot: String,
         mode: UInt16,
         ownerID: UInt32,
         groupID: UInt32,
         flags: UInt32,
         createdOn: Date?,
         modifiedOn: Date?,
         bytes: Int64,
         isDirectory: Bool,
         isSymbolicLink: Bool,
         parentMode: UInt16?,
         sectionRaw: String,
         reason: String,
         quarantinedOn: Date,
         wasInICloud: Bool,
         containment: Containment?) {
        self.id = id
        self.originalPath = originalPath
        self.originalName = originalName
        self.identity = identity
        self.quarantinedPath = quarantinedPath
        self.storeRoot = storeRoot
        self.mode = mode
        self.ownerID = ownerID
        self.groupID = groupID
        self.flags = flags
        self.createdOn = createdOn
        self.modifiedOn = modifiedOn
        self.bytes = bytes
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.parentMode = parentMode
        self.sectionRaw = sectionRaw
        self.reason = reason
        self.quarantinedOn = quarantinedOn
        self.wasInICloud = wasInICloud
        self.containment = containment
    }

    /// Build the record a move would produce, without moving anything.
    ///
    /// ⚠️ **Everything is decided here, before a single byte changes** — the id, the destination,
    /// the identity, all the metadata. That is what makes the intent journal possible: the record is
    /// already complete when it is written down, so a crash between the move and the ledger costs
    /// nothing but a reconciliation.
    static func planned(from reading: FileReading,
                        store: QuarantineStore,
                        section: SectionID,
                        reason: String,
                        id: UUID = UUID(),
                        now: Date = Date()) -> QuarantineRecord {
        let name = reading.name
        return QuarantineRecord(
            id: id,
            originalPath: reading.truePath ?? reading.path,
            originalName: name,
            identity: FileIdentity(reading),
            quarantinedPath: store.destination(for: name, id: id).path(percentEncoded: false),
            storeRoot: store.path,
            mode: reading.mode,
            ownerID: reading.ownerID,
            groupID: reading.groupID,
            flags: reading.flags,
            createdOn: reading.createdOn,
            modifiedOn: reading.modifiedOn,
            bytes: reading.bytes,
            isDirectory: reading.isDirectory,
            isSymbolicLink: reading.isSymbolicLink,
            parentMode: Movable.read(reading.url.deletingLastPathComponent())?.mode,
            section: section,
            reason: reason,
            quarantinedOn: now,
            wasInICloud: reading.isInICloud)
    }

}

// MARK: - What happened when the ledger was read

/// The three answers, kept apart so nothing can collapse them into a zero.
enum LedgerReading: Sendable {

    /// There is no ledger. A fresh install, or one where nothing has ever been set aside.
    case fresh

    /// The ledger was read. May legitimately be empty — everything was restored or removed.
    case items([QuarantineRecord])

    /// ⚠️ The ledger exists and could not be trusted. **Never reported as empty.**
    case unreadable(LedgerTrouble)

    /// Best effort, for a caller that genuinely only needs a list. ⚠️ **Check `trouble` too.** A
    /// caller that reads this and nothing else is the bug this type was written to fix.
    var records: [QuarantineRecord] {
        if case .items(let records) = self { return records }
        return []
    }

    /// `nil` when the reading can be believed.
    var trouble: LedgerTrouble? {
        if case .unreadable(let trouble) = self { return trouble }
        return nil
    }

    /// Whether "there is nothing in quarantine" is a thing the app is entitled to say.
    var isTrustworthy: Bool { trouble == nil }

    var count: Int { records.count }
}

/// The ledger could not be read, and what was done about it.
struct LedgerTrouble: Sendable, Equatable, Error {

    enum Kind: String, Sendable {
        /// The file is there and macOS would not hand it over.
        case couldNotBeOpened
        /// The file is there and is not the record it should be.
        case corrupt
        /// The ledger could not be written. The files are fine; the record of them is at risk.
        case couldNotBeWritten
    }

    let kind: Kind
    let path: String
    /// The system's own words, kept for a support conversation rather than for the screen.
    let underlying: String
    /// Where the unreadable original was copied to, when it could be.
    let keptAt: String?

    /// ⚠️ **The loud sentence.** It says what is unknown, not how many there are — because how many
    /// there are is exactly what is not known.
    var sentence: String {
        switch kind {
        case .couldNotBeOpened:
            return "Wellkept cannot read its own record of what it set aside, so it cannot tell you "
                 + "what is in quarantine. It has not deleted anything. The files are still in "
                 + "\((path as NSString).deletingLastPathComponent)."
        case .corrupt:
            let kept = keptAt.map { " The damaged record was kept at \($0)." } ?? ""
            return "Wellkept's record of what it set aside is damaged, so it cannot tell you what is "
                 + "in quarantine. Nothing has been deleted, and the files are still in "
                 + "\((path as NSString).deletingLastPathComponent).\(kept)"
        case .couldNotBeWritten:
            return "Wellkept could not save its record of what it set aside. Your files are where "
                 + "they were, but Wellkept may not be able to put them back on its own."
        }
    }

    /// Never quiet. Every screen that can show a quarantine count must show this instead of a zero.
    var isLoud: Bool { true }
}

// MARK: - The ledger

/// Reading and writing the one record.
///
/// Every function here is free — there is no instance and no cached state. A cached ledger is a
/// ledger that can disagree with the disk, and the disk is the one that has the files.
enum Ledger {

    // MARK: Reading

    /// What the ledger says, with "empty" and "could not look" kept apart.
    ///
    /// Records whose file is no longer where the ledger says are **kept, not dropped** — that is a
    /// change from the first version, which filtered them out. A record with a missing file is not a
    /// record of nothing; it is the evidence that something took the file, and the only thing that
    /// can say where it came from. `Quarantine.summary` counts it separately so the screen can say
    /// so instead of quietly shrinking the list.
    static func read(home: URL = StorageManifest.home(),
                     fileManager: FileManager = .default) -> LedgerReading {
        let ledger = StorageManifest.quarantineLedger(home: home)
        let path = ledger.path(percentEncoded: false)

        guard fileManager.fileExists(atPath: path) else { return .fresh }

        let data: Data
        do {
            data = try Data(contentsOf: ledger)
        } catch {
            return .unreadable(LedgerTrouble(kind: .couldNotBeOpened, path: path,
                                             underlying: error.localizedDescription, keptAt: nil))
        }

        // An empty file is a fresh ledger that nothing has been written to yet, not a corruption.
        if data.isEmpty { return .items([]) }

        do {
            return .items(try decoder().decode([QuarantineRecord].self, from: data))
        } catch {
            // ⚠️ **The damaged ledger is copied aside, never deleted and never overwritten.** It is
            // the only surviving statement about where somebody's files came from, and a partial
            // JSON array can still be read by a person with a text editor.
            let kept = keepACopy(of: ledger, fileManager: fileManager)
            return .unreadable(LedgerTrouble(kind: .corrupt, path: path,
                                             underlying: "\(error)", keptAt: kept))
        }
    }

    /// The list, for a caller that has already dealt with the trouble.
    static func records(home: URL = StorageManifest.home()) -> [QuarantineRecord] {
        read(home: home).records
    }

    // MARK: Writing

    /// Replace the ledger.
    ///
    /// ⚠️ **`.atomic`, always.** See the header: the plain form truncates in place, and a crash in
    /// that window orphans every quarantined file a person owns while the app reports an empty
    /// quarantine.
    static func write(_ records: [QuarantineRecord],
                      home: URL = StorageManifest.home(),
                      fileManager: FileManager = .default) throws {
        let support = StorageManifest.supportDirectory(home: home)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let data = try encoder().encode(records)
        try data.write(to: StorageManifest.quarantineLedger(home: home), options: .atomic)
    }

    /// Add records, keeping whatever is already there.
    ///
    /// ⚠️ **Refuses to write when the existing ledger could not be read.** Appending to a ledger that
    /// failed to decode would replace it with the new records alone — which is the same loss as
    /// deleting it, arrived at politely.
    @discardableResult
    static func append(_ records: [QuarantineRecord],
                       home: URL = StorageManifest.home()) -> LedgerTrouble? {
        guard !records.isEmpty else { return nil }
        let reading = read(home: home)
        if let trouble = reading.trouble { return trouble }

        var all = reading.records
        let known = Set(all.map(\.id))
        all.append(contentsOf: records.filter { !known.contains($0.id) })

        do {
            try write(all, home: home)
            return nil
        } catch {
            return LedgerTrouble(kind: .couldNotBeWritten,
                                 path: StorageManifest.quarantineLedger(home: home)
                                     .path(percentEncoded: false),
                                 underlying: error.localizedDescription, keptAt: nil)
        }
    }

    /// Take records out, by id. Same refusal on an unreadable ledger, and for the same reason.
    @discardableResult
    static func remove(ids: Set<UUID>, home: URL = StorageManifest.home()) -> LedgerTrouble? {
        guard !ids.isEmpty else { return nil }
        let reading = read(home: home)
        if let trouble = reading.trouble { return trouble }

        do {
            try write(reading.records.filter { !ids.contains($0.id) }, home: home)
            return nil
        } catch {
            return LedgerTrouble(kind: .couldNotBeWritten,
                                 path: StorageManifest.quarantineLedger(home: home)
                                     .path(percentEncoded: false),
                                 underlying: error.localizedDescription, keptAt: nil)
        }
    }

    /// Replace one record in place, by id. Used when containment is applied or lifted.
    @discardableResult
    static func replace(_ record: QuarantineRecord,
                        home: URL = StorageManifest.home()) -> LedgerTrouble? {
        let reading = read(home: home)
        if let trouble = reading.trouble { return trouble }

        var all = reading.records
        if let index = all.firstIndex(where: { $0.id == record.id }) {
            all[index] = record
        } else {
            all.append(record)
        }

        do {
            try write(all, home: home)
            return nil
        } catch {
            return LedgerTrouble(kind: .couldNotBeWritten,
                                 path: StorageManifest.quarantineLedger(home: home)
                                     .path(percentEncoded: false),
                                 underlying: error.localizedDescription, keptAt: nil)
        }
    }

    // MARK: The intent journal

    /// What Wellkept was in the middle of doing when the lights went out.
    ///
    /// Written **before the first move of a batch**, with the complete record for every item, and
    /// removed once the ledger has been brought up to date. One slot: operations are sequential, so
    /// at most one batch is ever in flight.
    struct Intent: Codable, Sendable, Equatable {

        enum Verb: String, Codable, Sendable {
            /// Moving items into the store.
            case quarantine
            /// Moving items out of the store, back where they came from.
            case restore
            /// Removing items from the store for good.
            case delete
        }

        let verb: Verb
        let startedAt: Date
        let records: [QuarantineRecord]
    }

    static func writeIntent(_ intent: Intent,
                            home: URL = StorageManifest.home(),
                            fileManager: FileManager = .default) throws {
        let support = StorageManifest.supportDirectory(home: home)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try encoder().encode(intent).write(to: StorageManifest.quarantineIntent(home: home),
                                           options: .atomic)
    }

    static func readIntent(home: URL = StorageManifest.home()) -> Intent? {
        guard let data = try? Data(contentsOf: StorageManifest.quarantineIntent(home: home)),
              !data.isEmpty
        else { return nil }
        return try? decoder().decode(Intent.self, from: data)
    }

    static func clearIntent(home: URL = StorageManifest.home(),
                            fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: StorageManifest.quarantineIntent(home: home))
    }

    // MARK: Reconciling

    /// What reconciling one interrupted item found.
    struct Reconciliation: Sendable, Equatable, Identifiable {

        enum Result: String, Sendable {
            /// The move never ran. Nothing on the disk changed.
            case nothingHappened
            /// The move ran; the ledger has now been brought up to date.
            case finished
            /// The move ran and the ledger already knew. Only the intent file was left over.
            case alreadyRecorded
            /// ⚠️ The item is at neither path. Something outside Wellkept took it.
            case unaccountedFor
        }

        let id: UUID
        let name: String
        let result: Result

        var isTrouble: Bool { result == .unaccountedFor }
    }

    /// Finish anything a crash interrupted. Called at launch, and again before the quarantine is
    /// read, because both are moments where being out of date costs something.
    ///
    /// Cheap when there is nothing to do: one `Data(contentsOf:)` on a file that is not there.
    @discardableResult
    static func reconcile(home: URL = StorageManifest.home(),
                          fileManager: FileManager = .default) -> [Reconciliation] {
        guard let intent = readIntent(home: home) else { return [] }

        var results: [Reconciliation] = []
        var toAdd: [QuarantineRecord] = []
        var toRemove: Set<UUID> = []
        let known = Set(read(home: home).records.map(\.id))

        for record in intent.records {
            let atOriginal = fileManager.fileExists(atPath: record.originalPath)
            let inStore = fileManager.fileExists(atPath: record.quarantinedPath)

            // ── Contained in place ────────────────────────────────────────────────────────────
            // Containment moves nothing, so both paths are the same file and the five-state table
            // above does not apply: there is no "in the store" to look in. The only thing the disk
            // can settle is whether the file is still there at all.
            //
            // ⚠️ This branch used to re-add the record whatever the intent said, which resurrected
            // the record for a malware file that had just been deleted — leaving a row pointing at
            // nothing, for ever, that nothing could clear.
            //
            // An interrupted *release* is the one case the disk cannot settle, because a released
            // file and a contained one sit at the same path. It is left recorded on purpose:
            // releasing is idempotent, so the person pressing Restore once more finishes the job,
            // and a row that is still there is a smaller harm than a file the app has forgotten.
            if record.wasContainedInPlace {
                guard fileManager.fileExists(atPath: record.originalPath) else {
                    if intent.verb == .delete {
                        toRemove.insert(record.id)
                        results.append(.init(id: record.id, name: record.originalName,
                                             result: .finished))
                    } else {
                        results.append(.init(id: record.id, name: record.originalName,
                                             result: .unaccountedFor))
                    }
                    continue
                }
                if !known.contains(record.id) {
                    toAdd.append(record)
                    results.append(.init(id: record.id, name: record.originalName,
                                         result: .finished))
                } else {
                    results.append(.init(id: record.id, name: record.originalName,
                                         result: intent.verb == .quarantine
                                             ? .alreadyRecorded : .nothingHappened))
                }
                continue
            }

            switch intent.verb {
            case .quarantine:
                if inStore, !known.contains(record.id) {
                    toAdd.append(record)
                    results.append(.init(id: record.id, name: record.originalName, result: .finished))
                } else if inStore {
                    results.append(.init(id: record.id, name: record.originalName, result: .alreadyRecorded))
                } else if atOriginal {
                    results.append(.init(id: record.id, name: record.originalName, result: .nothingHappened))
                } else {
                    results.append(.init(id: record.id, name: record.originalName, result: .unaccountedFor))
                }

            case .restore:
                if atOriginal, !inStore {
                    toRemove.insert(record.id)
                    results.append(.init(id: record.id, name: record.originalName, result: .finished))
                } else if inStore {
                    if !known.contains(record.id) { toAdd.append(record) }
                    results.append(.init(id: record.id, name: record.originalName, result: .nothingHappened))
                } else {
                    results.append(.init(id: record.id, name: record.originalName, result: .unaccountedFor))
                }

            case .delete:
                if inStore {
                    if !known.contains(record.id) { toAdd.append(record) }
                    results.append(.init(id: record.id, name: record.originalName, result: .nothingHappened))
                } else {
                    toRemove.insert(record.id)
                    results.append(.init(id: record.id, name: record.originalName, result: .finished))
                }
            }
        }

        // ⚠️ The intent file is cleared **last**, and only if the ledger accepted the corrections.
        // Clearing it first would turn a failed write into a permanent orphan.
        var ledgerHeld = true
        if !toAdd.isEmpty { ledgerHeld = append(toAdd, home: home) == nil }
        if ledgerHeld, !toRemove.isEmpty { ledgerHeld = remove(ids: toRemove, home: home) == nil }
        if ledgerHeld { clearIntent(home: home, fileManager: fileManager) }

        return results
    }

    // MARK: Coders

    /// ISO-8601 dates, sorted keys, pretty printed.
    ///
    /// Not tidiness: this file is somebody's only route back to their files, and the case where it
    /// matters most is the one where Wellkept is not running. A person with a text editor can read
    /// `2026-08-28T09:14:03Z` and cannot read `775472043.19`.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Copy an unreadable ledger aside under a dated name, and say where it went.
    private static func keepACopy(of ledger: URL, fileManager: FileManager) -> String? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let kept = ledger.deletingLastPathComponent()
            .appending(path: "Quarantine-unreadable-\(stamp).json")
        guard (try? fileManager.copyItem(at: ledger, to: kept)) != nil else { return nil }
        return kept.path(percentEncoded: false)
    }
}

// MARK: - The ignore list

/// One thing the user told Wellkept never to raise again.
///
/// ⚠️ **Ignore has been parked twice and this is its home.** It is a real record, not a hidden flag:
/// it says what was ignored, which section found it, what the finding said at the time, and when. It
/// is listed in Settings and every entry can be taken back, because an irreversible "never mention
/// this again" is a decision somebody makes once and regrets for the life of the machine.
struct IgnoredItem: Codable, Sendable, Identifiable, Equatable, Hashable {

    let id: UUID
    /// The path as the filesystem spells it.
    let path: String
    /// The identity, when it could be read. `nil` for something that had already gone.
    let identity: FileIdentity?
    let sectionRaw: String
    /// What the finding said, so Settings can show what is being suppressed rather than a bare path.
    let finding: String
    let ignoredOn: Date

    var section: SectionID? { SectionID(rawValue: sectionRaw) }
    var url: URL { URL(filePath: path) }
    var name: String { (path as NSString).lastPathComponent }

    init(id: UUID = UUID(), path: String, identity: FileIdentity?, section: SectionID,
         finding: String, ignoredOn: Date = Date()) {
        self.id = id
        self.path = path
        self.identity = identity
        self.sectionRaw = section.rawValue
        self.finding = finding
        self.ignoredOn = ignoredOn
    }
}

/// The list of things Wellkept has been told to leave alone.
///
/// Same three-case reading as the ledger, and for the same reason: an ignore list that reads as
/// empty because it could not be opened would put every suppressed finding back on somebody's
/// screen, which is a smaller harm than losing a file and still the wrong answer.
enum IgnoreList {

    enum Reading: Sendable {
        case fresh
        case items([IgnoredItem])
        case unreadable(LedgerTrouble)

        var items: [IgnoredItem] {
            if case .items(let items) = self { return items }
            return []
        }
        var trouble: LedgerTrouble? {
            if case .unreadable(let trouble) = self { return trouble }
            return nil
        }
        var isTrustworthy: Bool { trouble == nil }
    }

    static func read(home: URL = StorageManifest.home(),
                     fileManager: FileManager = .default) -> Reading {
        let file = StorageManifest.ignoreList(home: home)
        let path = file.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else { return .fresh }

        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            return .unreadable(LedgerTrouble(kind: .couldNotBeOpened, path: path,
                                             underlying: error.localizedDescription, keptAt: nil))
        }
        if data.isEmpty { return .items([]) }

        do {
            return .items(try Ledger.decoder().decode([IgnoredItem].self, from: data))
        } catch {
            return .unreadable(LedgerTrouble(kind: .corrupt, path: path,
                                             underlying: "\(error)", keptAt: nil))
        }
    }

    static func items(home: URL = StorageManifest.home()) -> [IgnoredItem] {
        read(home: home).items
    }

    static func write(_ items: [IgnoredItem],
                      home: URL = StorageManifest.home(),
                      fileManager: FileManager = .default) throws {
        let support = StorageManifest.supportDirectory(home: home)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try Ledger.encoder().encode(items).write(to: StorageManifest.ignoreList(home: home),
                                                 options: .atomic)
    }

    /// Whether this path is on the list.
    ///
    /// Matched on **identity first**, path second. A file that was ignored and has since been
    /// renamed is the same file; a new file that has taken the old name is not. The path fallback
    /// covers a list written before the identity could be read — and it matches **inside** an
    /// ignored folder too, deliberately: telling Wellkept to leave a folder alone and then being
    /// shown its contents one at a time is not what anybody meant by ignore.
    static func isIgnored(_ url: URL, home: URL = StorageManifest.home()) -> Bool {
        contains(url, in: items(home: home))
    }

    /// The same test against a list already in hand — for a scan checking thousands of paths, which
    /// must not re-read the file thousands of times.
    /// ⚠️ **The volume is read once, here, and not once per entry.** A scan asks this about
    /// thousands of paths; a `statfs` inside the loop would be thousands of syscalls multiplied by
    /// the length of the list. It matters for correctness as much as for speed — see
    /// `FileIdentity.isOnTheSameVolume`, without which an inode match alone would suppress a
    /// finding on a plugged-in drive because a file in the home folder happened to share its number.
    static func contains(_ url: URL, in items: [IgnoredItem]) -> Bool {
        let path = url.path(percentEncoded: false)
        guard !items.isEmpty else { return false }

        var status = stat()
        let readable = lstat(path, &status) == 0
        let inode = UInt64(status.st_ino)
        let volume = readable ? Movable.volume(of: path) : nil

        for item in items {
            if readable, let identity = item.identity,
               identity.inode == inode, identity.isOnTheSameVolume(as: volume) { return true }
            if Movable.isInside(path, any: [item.path]) { return true }
        }
        return false
    }
}
