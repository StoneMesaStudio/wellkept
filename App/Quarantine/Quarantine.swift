// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  Quarantine.swift
//  Wellkept — App/Quarantine
//
//  ⭐ **The four verbs, and the only place in Wellkept where a file moves.**
//
//  Quarantine · Restore · Delete · Ignore. The words are fixed app-wide and no screen invents a
//  synonym for them.
//
//  ## What quarantine actually is — John, 2026-08-28
//
//  He asked the question that reframed the whole feature: *"why would I do that? What is the
//  context?"*
//
//  **Quarantine is not "free up space". It moves no bytes off the disk at all.** Measured: setting
//  aside 391 MB across 100,000 files moved free space by **−8 KiB**. A same-volume rename re-points
//  an inode; the bytes never leave. It is the first half of deleting something, with a month to
//  change your mind: set it aside → nothing on the Mac changes size → empty the quarantine → the
//  space comes back.
//
//  ⚠️ **So nothing in this file, and nothing that reads it, may ever say a quarantine "freed"
//  anything.** A person checks About This Mac within a minute and is right to distrust everything
//  else the app says afterwards. `QuarantineWords` holds the sentences John approved; use them.
//
//  ## The one safe move
//
//  Every verb below is `renameatx_np` on the same volume, with two flags that are not optional:
//
//  - **`RENAME_EXCL`** — plain `rename(2)` *silently destroys* whatever occupies the destination. A
//    collision, a re-run batch, or a restore into a re-used name would otherwise destroy the exact
//    file this engine exists to protect. `RENAME_EXCL` returns `EEXIST` instead.
//  - **`RENAME_NOFOLLOW_ANY`** — a symlinked parent component is the failure class that ends a
//    product: acting through `Caches → RealAppSupport` destroys the real thing. This returns `ELOOP`
//    instead of following. `Movable` says so in words first; this is the syscall that guarantees it
//    even if somebody replaces a folder with a link between the check and the move.
//
//  There is no copy path anywhere in this file and there must never be one. See the header of
//  `QuarantineStore.swift` for what a copy loses.
//
//  ## Restore is held to a higher standard than quarantine
//
//  ⚠️ **An occupied original path is a refusal, never an overwrite.** Between setting something
//  aside and putting it back, the person may have re-downloaded the installer or saved the document
//  again. Moving over it destroys the newer one — and they asked for the opposite of that.
//
//  A missing parent folder is recreated with the permissions it had, which is why those are in the
//  record. An unmounted volume gets "plug it back in", not "the file is gone".
//
//  ## Malware containment, for Security's found items
//
//  Not everything malicious should be moved: moving it can break the very thing that is watching it.
//  **Containment is remove the execute bit and mark the file untrusted** — reversible, recorded, and
//  it leaves the file where macOS's own scanner can still see it.
//
//  ⚠️ **Zipping the store was rejected, 2026-08-28.** An archive drops the metadata a rename
//  preserves, and for a malicious file it *hides* it from XProtect rather than defusing it.

// MARK: - The words

/// The sentences John settled on, in one place so no screen can drift from them.
///
/// ⚠️ **The word "freed" is banned app-wide**, and `QuarantineWordsTests` fails the build if it, or
/// "reclaimed", turns up in a string anywhere under `App/`.
enum QuarantineWords {

    /// Before the button. John's words, 2026-08-28.
    static func beforeSettingAside(_ bytes: Int64) -> String {
        "Set aside \(StorageManifest.readable(bytes)). Nothing is deleted and no space comes back "
        + "until you empty the quarantine."
    }

    /// ⚠️ The consequence John drew out: **if the disk is full today, quarantine is the wrong
    /// button.** Wanting the space back now means quarantine and then empty, deliberately, in one
    /// sitting. Storage has to say this rather than let somebody set aside 40 GB and watch nothing
    /// happen.
    static let whenTheDiskIsAlreadyFull =
        "If you need the space back today, setting files aside will not do it. Set them aside and "
        + "then empty the quarantine, in one sitting."

    /// The one line for an iCloud-synced file. Allowed, with the warning — never refused.
    static let iCloud = Movable.iCloudWarning

    /// What the person is really being told by that line: for those thirty days the file is off
    /// their other devices while still taking up the same room here.
    static let iCloudGap =
        "It stays on this Mac, taking up the same room, until you empty the quarantine."
}

// MARK: - Asking for something to be set aside

extension Quarantine {

    /// One thing a section wants set aside, and why.
    struct Request: Sendable, Equatable {
        let url: URL
        let section: SectionID
        /// Why, in the user's words. Shown on the row for as long as the item is in quarantine.
        let reason: String

        init(_ url: URL, section: SectionID, reason: String) {
            self.url = url
            self.section = section
            self.reason = reason
        }
    }

    /// What happened to one item.
    struct Outcome: Sendable, Equatable, Identifiable {
        let path: String
        let name: String
        /// The record, when it moved. `nil` when it did not.
        let record: QuarantineRecord?
        /// The sentence a person reads, when it did not move.
        let refusal: String?

        var id: String { path }
        var moved: Bool { record != nil }
    }

    /// What happened to a batch.
    struct Report: Sendable {
        let outcomes: [Outcome]
        /// ⚠️ Loud when set: the files moved and the record of them did not save.
        let trouble: LedgerTrouble?

        var moved: [QuarantineRecord] { outcomes.compactMap(\.record) }
        var refused: [Outcome] { outcomes.filter { !$0.moved } }
        var bytesSetAside: Int64 { moved.reduce(0) { $0 + $1.bytes } }
        /// Whether John's one line has to appear.
        var anyWasInICloud: Bool { moved.contains(where: \.wasInICloud) }

        /// What the screen says afterwards. **Never a figure that came back** — nothing came back.
        var sentence: String {
            if let trouble { return trouble.sentence }
            let count = moved.count
            guard count > 0 else {
                return refused.count == 1
                    ? (refused[0].refusal ?? "Nothing was set aside.")
                    : "Nothing was set aside."
            }
            let items = count == 1 ? "1 item" : "\(count) items"
            var line = "Set aside \(items), \(StorageManifest.readable(bytesSetAside)). "
                     + "Nothing is deleted and no space comes back until you empty the quarantine."
            if !refused.isEmpty {
                line += " \(refused.count) could not be moved."
            }
            return line
        }
    }
}

// MARK: - Putting things back

extension Quarantine {

    /// Why one item could not go back.
    enum RestoreRefusal: Sendable, Equatable {
        /// ⚠️ Something is at the original path. **Never overwritten.**
        case somethingIsAlreadyThere(path: String)
        /// The quarantined file is not in the store any more.
        case itemIsGone(path: String)
        /// The store is on a disk that is not plugged in.
        case volumeIsNotMounted(store: String)
        /// The thing in the store is not the thing that was put there.
        case notTheSameFile
        /// The folder it came out of could not be made again.
        case parentCouldNotBeMade(why: String)
        /// The move itself failed. Carries the system's own words.
        case couldNotBeMoved(why: String)
        /// The ledger could not be updated, so the record was left alone.
        case theRecordCouldNotBeUpdated(why: String)

        var sentence: String {
            switch self {
            case .somethingIsAlreadyThere(let path):
                "There is already something at \(path). Wellkept will not write over it — move or "
                + "rename that first, then try again."
            case .itemIsGone(let path):
                "The file is no longer at \(path). Something outside Wellkept moved or removed it."
            case .volumeIsNotMounted(let store):
                "This was set aside on a disk that is not connected. Plug \(store) back in and try "
                + "again."
            case .notTheSameFile:
                "What is in quarantine under that name is not the file Wellkept put there. It has "
                + "been left alone."
            case .parentCouldNotBeMade(let why):
                "The folder it came from no longer exists and could not be made again: \(why)."
            case .couldNotBeMoved(let why):
                "It could not be put back: \(why)."
            case .theRecordCouldNotBeUpdated(let why):
                "It was put back, but Wellkept could not update its own record: \(why)."
            }
        }
    }

    struct RestoreOutcome: Sendable, Equatable, Identifiable {
        let record: QuarantineRecord
        let refusal: RestoreRefusal?
        var id: UUID { record.id }
        var restored: Bool { refusal == nil }
    }

    struct RestoreReport: Sendable {
        let outcomes: [RestoreOutcome]
        let trouble: LedgerTrouble?

        var restored: [QuarantineRecord] { outcomes.filter(\.restored).map(\.record) }
        var stuck: [RestoreOutcome] { outcomes.filter { !$0.restored } }

        var sentence: String {
            if let trouble { return trouble.sentence }
            let back = restored.count
            if stuck.isEmpty {
                return back == 1
                    ? "It is back where it came from."
                    : "All \(back) are back where they came from."
            }
            if back == 0 {
                return stuck.count == 1
                    ? stuck[0].refusal?.sentence ?? "It could not be put back."
                    : "None of the \(stuck.count) could be put back."
            }
            return "\(back) went back. \(stuck.count) could not — "
                 + "\(stuck[0].refusal?.sentence ?? "the reason is on the row.")"
        }
    }
}

// MARK: - Removing for good

extension Quarantine {

    struct DeleteRefusal: Sendable, Equatable, Identifiable {
        let record: QuarantineRecord
        let sentence: String
        var id: UUID { record.id }
    }

    /// What emptying the quarantine actually did.
    ///
    /// ⚠️ **`cameBack` is measured, never predicted.** Free space is an estimate even after a real
    /// delete: a local Time Machine snapshot keeps the blocks allocated until macOS lets them go, in
    /// its own time. Promising a figure before the fact, or reporting the sum of the file sizes as
    /// though it were space returned, is a number a person can disprove in About This Mac.
    struct DeleteReport: Sendable {
        let deleted: [QuarantineRecord]
        let refused: [DeleteRefusal]
        let trouble: LedgerTrouble?
        /// Free bytes on the store's volume before, from `statfs`. `nil` when it could not be read.
        let freeBefore: Int64?
        /// Free bytes after.
        let freeAfter: Int64?

        var bytesOfFilesRemoved: Int64 { deleted.reduce(0) { $0 + $1.bytes } }

        /// What actually came back, as measured. Never negative — other things write to the disk
        /// while this runs, and a negative figure would be an artefact rather than a fact.
        var cameBack: Int64? {
            guard let freeBefore, let freeAfter else { return nil }
            return max(0, freeAfter - freeBefore)
        }

        /// ⚠️ The sentence, and the reason this type exists.
        var sentence: String {
            guard !deleted.isEmpty else {
                if let trouble { return trouble.sentence }
                return refused.count == 1 ? refused[0].sentence : "Nothing was removed."
            }
            let items = deleted.count == 1 ? "1 item" : "\(deleted.count) items"
            let size = StorageManifest.readable(bytesOfFilesRemoved)

            guard let cameBack else {
                return "Removed \(items), \(size). Wellkept could not measure the free space on this "
                     + "disk, so it will not tell you a number it did not read."
            }
            if cameBack == 0 {
                return "Removed \(items), \(size). Free space has not moved yet — macOS is still "
                     + "holding those blocks in a local snapshot, and lets them go in its own time."
            }
            if cameBack < bytesOfFilesRemoved * 9 / 10 {
                return "Removed \(items), \(size). \(StorageManifest.readable(cameBack)) has come "
                     + "back so far — macOS is still holding the rest in a local snapshot, and lets "
                     + "it go in its own time."
            }
            return "Removed \(items), \(size). \(StorageManifest.readable(cameBack)) has come back."
        }
    }
}

// MARK: - What is in there right now

extension Quarantine {

    /// The permanent row on the Storage face. John's shape, 2026-08-28: *"40 GB set aside — oldest
    /// is 12 days old"*, with the Empty button on it.
    struct Summary: Sendable {
        let count: Int
        let bytes: Int64
        let oldest: Date?
        /// Past thirty days, waiting to be removed.
        let readyCount: Int
        /// Records whose file is not where the ledger says it is. ⚠️ Counted rather than dropped:
        /// silently shrinking the list is how a person stops being told something went wrong.
        let unaccountedFor: Int
        /// ⚠️ Loud when set. **Shown instead of a count**, never alongside one.
        let trouble: LedgerTrouble?

        var isEmpty: Bool { count == 0 && trouble == nil }

        /// The row. Never the word "freed".
        func rowSentence(now: Date = Date()) -> String {
            if let trouble { return trouble.sentence }
            guard count > 0 else { return "Nothing is set aside." }
            let size = StorageManifest.readable(bytes)
            guard let oldest else { return "\(size) set aside." }
            let days = Expiry.calendarDays(from: oldest, to: now)
            let age = days == 0 ? "the oldest went in today"
                    : days == 1 ? "the oldest is 1 day old"
                    : "the oldest is \(days) days old"
            return "\(size) set aside — \(age)."
        }

        /// The second line, when anything is past thirty days.
        var readySentence: String? {
            guard readyCount > 0 else { return nil }
            return readyCount == 1
                ? "1 item has been here \(Expiry.days) days and is ready to remove."
                : "\(readyCount) items have been here \(Expiry.days) days and are ready to remove."
        }

        /// The third line, when the ledger names something that is not there.
        var unaccountedSentence: String? {
            guard unaccountedFor > 0 else { return nil }
            return unaccountedFor == 1
                ? "1 item Wellkept set aside is no longer where it put it."
                : "\(unaccountedFor) items Wellkept set aside are no longer where it put them."
        }
    }
}

// MARK: - The engine

/// The four verbs.
///
/// Every function is free and reads the ledger fresh. There is no cached list, because a cached list
/// is a list that can disagree with the disk — and the disk is the one holding the files.
enum Quarantine {

    // MARK: ── Reading ────────────────────────────────────────────────────────────────────────

    /// What is in quarantine, with "empty" and "could not look" kept apart.
    ///
    /// Reconciles first: an interrupted batch must be finished before anybody is told a number.
    static func reading(home: URL = StorageManifest.home()) -> LedgerReading {
        Ledger.reconcile(home: home)
        return Ledger.read(home: home)
    }

    /// The list. ⚠️ **Check `reading().trouble` too** — this cannot tell you it could not look.
    static func records(home: URL = StorageManifest.home()) -> [QuarantineRecord] {
        reading(home: home).records
    }

    /// Finish anything a crash interrupted, and hand back what could not be accounted for.
    ///
    /// ⚠️ **Call this once at launch and show `sentence` when it is not `nil`.** `reading()` and the
    /// three verbs all reconcile too, but they throw the results away — which is right for them and
    /// wrong for the app as a whole. The state where an item is at neither its own path nor the
    /// store is the one thing reconciling can discover that nothing else in the app can: the record
    /// is not in the ledger, so `Summary.unaccountedFor` will never count it, and without this it
    /// would be found and then silently forgotten.
    @discardableResult
    static func reconcileOnOpening(home: URL = StorageManifest.home(),
                                   fileManager: FileManager = .default) -> ReconcileReport {
        ReconcileReport(results: Ledger.reconcile(home: home, fileManager: fileManager))
    }

    /// What an interrupted batch turned out to have done.
    struct ReconcileReport: Sendable {
        let results: [Ledger.Reconciliation]

        /// Items that were at neither path. Something outside Wellkept took them.
        var unaccountedFor: [Ledger.Reconciliation] { results.filter(\.isTrouble) }

        /// Items whose bookkeeping this reconciliation finished.
        var finished: [Ledger.Reconciliation] { results.filter { $0.result == .finished } }

        var isQuiet: Bool { unaccountedFor.isEmpty }

        /// `nil` on the ordinary Mac, where there is never anything in flight. Says only what is
        /// known — never a count of what was lost, because what was lost is what is not known.
        var sentence: String? {
            guard !unaccountedFor.isEmpty else { return nil }
            let names = unaccountedFor.map(\.name).sorted().formatted(.list(type: .and))
            return unaccountedFor.count == 1
                ? "Wellkept was interrupted while setting \(names) aside, and it is now at neither "
                  + "the place it came from nor the place Wellkept was putting it. Something other "
                  + "than Wellkept moved it. Nothing was deleted."
                : "Wellkept was interrupted part way through, and \(unaccountedFor.count) items "
                  + "(\(names)) are at neither the place they came from nor the place Wellkept was "
                  + "putting them. Something other than Wellkept moved them. Nothing was deleted."
        }
    }

    /// The permanent row.
    static func summary(home: URL = StorageManifest.home(),
                        now: Date = Date(),
                        fileManager: FileManager = .default) -> Summary {
        let reading = reading(home: home)
        if let trouble = reading.trouble {
            return Summary(count: 0, bytes: 0, oldest: nil, readyCount: 0,
                           unaccountedFor: 0, trouble: trouble)
        }
        let records = reading.records
        let missing = records.filter { !Movable.exists($0.quarantinedPath) }
        return Summary(count: records.count,
                       bytes: records.reduce(0) { $0 + $1.bytes },
                       oldest: records.map(\.quarantinedOn).min(),
                       readyCount: Expiry.ready(among: records, now: now).count,
                       unaccountedFor: missing.count,
                       trouble: nil)
    }

    // MARK: ── Verb 1: Quarantine ─────────────────────────────────────────────────────────────

    /// Set one thing aside.
    static func quarantine(_ url: URL,
                           section: SectionID,
                           reason: String,
                           home: URL = StorageManifest.home()) -> Outcome {
        quarantine([Request(url, section: section, reason: reason)], home: home)
            .outcomes.first
            ?? Outcome(path: url.path(percentEncoded: false),
                       name: url.lastPathComponent, record: nil,
                       refusal: MoveRefusal.missing.sentence)
    }

    /// Set a batch aside.
    ///
    /// The order is fixed and every step of it is load-bearing:
    ///
    ///  1. **Check everything first**, with one open-file census for the whole batch. Nothing moves
    ///     while anything is still being decided.
    ///  2. **Write the intent**, with the complete record for every item that is going to move. This
    ///     is the durable statement that closes the crash window — see `Ledger.reconcile`.
    ///  3. **Move them**, one atomic rename each.
    ///  4. **Write the ledger**, once.
    ///  5. **Clear the intent.**
    static func quarantine(_ requests: [Request],
                           home: URL = StorageManifest.home(),
                           fileManager: FileManager = .default) -> Report {
        guard !requests.isEmpty else { return Report(outcomes: [], trouble: nil) }

        Ledger.reconcile(home: home, fileManager: fileManager)

        let reach = Reach.standard(home: home)
        let census = OpenFileCensus.take(of: requests.map(\.url))

        // 1 — decide everything before touching anything.
        var planned: [(Request, QuarantineRecord)] = []
        var outcomes: [Outcome] = []

        for request in requests {
            let path = request.url.path(percentEncoded: false)
            let name = request.url.lastPathComponent

            let verdict = Movable.check(request.url, reach: reach, census: census)
            guard verdict.isMovable, let file = verdict.reading else {
                outcomes.append(Outcome(path: path, name: name, record: nil,
                                        refusal: verdict.sentence ?? MoveRefusal.missing.sentence))
                continue
            }

            switch QuarantineStore.forItem(on: file.volume, home: home, fileManager: fileManager) {
            case .failure(let refusal):
                outcomes.append(Outcome(path: path, name: name, record: nil,
                                        refusal: refusal.sentence))
            case .success(let store):
                planned.append((request, QuarantineRecord.planned(from: file, store: store,
                                                                  section: request.section,
                                                                  reason: request.reason)))
            }
        }

        guard !planned.isEmpty else { return Report(outcomes: outcomes, trouble: nil) }

        // 2 — say what is about to happen, durably.
        do {
            try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(),
                                         records: planned.map(\.1)),
                                   home: home, fileManager: fileManager)
        } catch {
            // ⚠️ No intent means no way to recover from a crash mid-batch, so nothing moves. A file
            // set aside with no record is the one outcome this engine exists to prevent.
            let why = "Wellkept could not write down what it was about to do, so it did nothing: "
                    + "\(error.localizedDescription)"
            return Report(outcomes: outcomes + planned.map {
                Outcome(path: $0.1.originalPath, name: $0.1.originalName, record: nil, refusal: why)
            }, trouble: nil)
        }

        // 3 — move them.
        var moved: [QuarantineRecord] = []
        for (_, record) in planned {
            do {
                try fileManager.createDirectory(at: record.holderURL,
                                                withIntermediateDirectories: true)
            } catch {
                outcomes.append(Outcome(path: record.originalPath, name: record.originalName,
                                        record: nil,
                                        refusal: "Wellkept could not make a place to put it: "
                                               + "\(error.localizedDescription)."))
                continue
            }

            switch AtomicMove.perform(from: record.originalPath, to: record.quarantinedPath) {
            case .moved:
                moved.append(record)
                outcomes.append(Outcome(path: record.originalPath, name: record.originalName,
                                        record: record, refusal: nil))
            case .failed(let code, let why):
                try? fileManager.removeItem(at: record.holderURL)
                outcomes.append(Outcome(path: record.originalPath, name: record.originalName,
                                        record: nil,
                                        refusal: AtomicMove.sentence(for: code, fallback: why)))
            }
        }

        // 4 and 5 — record it, then forget the intent.
        let trouble = Ledger.append(moved, home: home)
        if trouble == nil { Ledger.clearIntent(home: home, fileManager: fileManager) }

        return Report(outcomes: outcomes, trouble: trouble)
    }

    // MARK: ── Verb 2: Restore ────────────────────────────────────────────────────────────────

    /// Put things back exactly where they came from.
    ///
    /// ⚠️ **Restore is held to a higher standard than quarantine**, because a restore that goes
    /// wrong destroys something the person made *after* the quarantine — a file they have never had
    /// a chance to protect.
    @discardableResult
    static func restore(_ records: [QuarantineRecord],
                        home: URL = StorageManifest.home(),
                        fileManager: FileManager = .default) -> RestoreReport {
        guard !records.isEmpty else { return RestoreReport(outcomes: [], trouble: nil) }

        Ledger.reconcile(home: home, fileManager: fileManager)

        do {
            try Ledger.writeIntent(.init(verb: .restore, startedAt: Date(), records: records),
                                   home: home, fileManager: fileManager)
        } catch {
            let why = RestoreRefusal.couldNotBeMoved(
                why: "Wellkept could not write down what it was about to do "
                   + "(\(error.localizedDescription)), so it did nothing")
            return RestoreReport(outcomes: records.map { RestoreOutcome(record: $0, refusal: why) },
                                 trouble: nil)
        }

        var outcomes: [RestoreOutcome] = []
        var done: Set<UUID> = []

        for record in records {
            let refusal = putBack(record, fileManager: fileManager)
            outcomes.append(RestoreOutcome(record: record, refusal: refusal))
            if refusal == nil { done.insert(record.id) }
        }

        let trouble = Ledger.remove(ids: done, home: home)
        if trouble == nil { Ledger.clearIntent(home: home, fileManager: fileManager) }

        return RestoreReport(outcomes: outcomes, trouble: trouble)
    }

    /// One item, back. `nil` means it went.
    private static func putBack(_ record: QuarantineRecord,
                                fileManager: FileManager) -> RestoreRefusal? {

        // A file that was contained in place never moved. Undoing containment IS the restore.
        if record.wasContainedInPlace {
            return release(record, fileManager: fileManager)
        }

        guard Movable.exists(record.storeRoot) else {
            return .volumeIsNotMounted(store: (record.storeRoot as NSString).lastPathComponent)
        }
        guard Movable.exists(record.quarantinedPath) else {
            return .itemIsGone(path: record.quarantinedPath)
        }
        // ⚠️ Identity, not name. Somebody may have put a different file in that folder by hand.
        guard record.identity.stillDescribes(record.quarantinedPath) else {
            return .notTheSameFile
        }
        // ⚠️ The refusal that makes restore safe. Never an overwrite.
        guard !Movable.exists(record.originalPath) else {
            return .somethingIsAlreadyThere(path: record.originalPath)
        }

        let parent = record.originalURL.deletingLastPathComponent()
        if !Movable.exists(parent.path(percentEncoded: false)) {
            do {
                // The permissions the folder had, recorded when the file was taken. Without them a
                // recreated folder gets whatever the umask says, which is not what was there.
                let attributes: [FileAttributeKey: Any]? = record.parentMode
                    .map { [.posixPermissions: NSNumber(value: $0)] }
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: attributes)
            } catch {
                return .parentCouldNotBeMade(why: error.localizedDescription)
            }
        }

        switch AtomicMove.perform(from: record.quarantinedPath, to: record.originalPath) {
        case .moved:
            // The now-empty holder folder. Removed only while it is empty — never recursively.
            let holder = record.holderURL.path(percentEncoded: false)
            if ((try? fileManager.contentsOfDirectory(atPath: holder))?.isEmpty ?? false) {
                try? fileManager.removeItem(at: record.holderURL)
            }
            return nil
        case .failed(let code, let why):
            return .couldNotBeMoved(why: AtomicMove.sentence(for: code, fallback: why))
        }
    }

    // MARK: ── Verb 3: Delete ─────────────────────────────────────────────────────────────────

    /// Remove items from the quarantine for good.
    ///
    /// ⚠️ **`expecting` is not ceremony.** The classic way software deletes the wrong thing is a call
    /// site that hands over the whole list where it meant to hand over the selection. The count comes
    /// from what the person was actually shown; a mismatch is refused rather than resolved.
    ///
    /// Nothing goes to the Trash. Quarantine already *is* the holding pen — a second one would give
    /// somebody two places to look and no idea which held their file.
    @discardableResult
    static func delete(_ records: [QuarantineRecord],
                       expecting: Int,
                       home: URL = StorageManifest.home(),
                       fileManager: FileManager = .default) -> DeleteReport {
        guard !records.isEmpty else {
            return DeleteReport(deleted: [], refused: [], trouble: nil,
                                freeBefore: nil, freeAfter: nil)
        }
        guard records.count == expecting else {
            let why = "Wellkept was asked to remove \(expecting) items and handed \(records.count). "
                    + "It removed nothing."
            return DeleteReport(deleted: [],
                                refused: records.map { DeleteRefusal(record: $0, sentence: why) },
                                trouble: nil, freeBefore: nil, freeAfter: nil)
        }

        Ledger.reconcile(home: home, fileManager: fileManager)

        // ⚠️ Every volume the batch touches, not just the first record's. A selection can span the
        // boot disk and a plugged-in drive, and measuring one of them would report that most of the
        // space did not come back — a wrong number that reads exactly like the snapshot effect this
        // measurement exists to reveal honestly.
        let volumes = storeVolumes(of: records, home: home)
        let before = freeBytes(across: volumes)

        do {
            try Ledger.writeIntent(.init(verb: .delete, startedAt: Date(), records: records),
                                   home: home, fileManager: fileManager)
        } catch {
            let why = "Wellkept could not write down what it was about to do, so it removed nothing: "
                    + "\(error.localizedDescription)"
            return DeleteReport(deleted: [],
                                refused: records.map { DeleteRefusal(record: $0, sentence: why) },
                                trouble: nil, freeBefore: before, freeAfter: before)
        }

        var deleted: [QuarantineRecord] = []
        var refused: [DeleteRefusal] = []

        for record in records {
            // A contained-in-place item is deleted where it stands, and only if it is still the same
            // file. Everything else is deleted with its holder folder.
            let target = record.wasContainedInPlace ? record.originalPath : record.quarantinedPath

            guard Movable.exists(target) else {
                // Already gone. The record goes with it — a record of nothing helps nobody.
                deleted.append(record)
                continue
            }
            guard record.identity.stillDescribes(target) else {
                refused.append(DeleteRefusal(record: record,
                                             sentence: "What is there now is not the file Wellkept "
                                                     + "set aside. It has been left alone."))
                continue
            }
            do {
                if record.wasContainedInPlace {
                    try fileManager.removeItem(atPath: target)
                } else {
                    try fileManager.removeItem(at: record.holderURL)
                }
                deleted.append(record)
            } catch {
                refused.append(DeleteRefusal(record: record,
                                             sentence: "It could not be removed: "
                                                     + "\(error.localizedDescription)."))
            }
        }

        let trouble = Ledger.remove(ids: Set(deleted.map(\.id)), home: home)
        if trouble == nil { Ledger.clearIntent(home: home, fileManager: fileManager) }

        // ⚠️ Measured after, not predicted before. A local snapshot can hold the blocks.
        let after = freeBytes(across: volumes)

        return DeleteReport(deleted: deleted, refused: refused, trouble: trouble,
                            freeBefore: before, freeAfter: after)
    }

    /// Free bytes on the volume a path is on, from `statfs`.
    ///
    /// `f_bavail`, the blocks available to this user — the same figure the kernel gives `df`. Not
    /// Foundation's "important usage" capacity, which nets off what macOS *believes* it could purge
    /// and would therefore hide the very snapshot effect this measurement exists to reveal.
    static func freeBytes(onVolumeAt path: String) -> Int64? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        return Int64(fs.f_bavail) * Int64(fs.f_bsize)
    }

    /// One readable path per distinct volume the batch is stored on.
    ///
    /// De-duplicated by mount point rather than by store root: two stores on the same volume would
    /// otherwise have that volume's free space counted twice, and the total would appear to double
    /// for no reason anybody could explain. A record whose store is on a disk that is no longer
    /// connected simply drops out — its volume has no free space to measure from here.
    static func storeVolumes(of records: [QuarantineRecord],
                             home: URL = StorageManifest.home()) -> [String] {
        var byMountPoint: [String: String] = [:]
        for record in records {
            let path = record.wasContainedInPlace ? record.originalPath : record.storeRoot
            guard let volume = Movable.volume(of: path) else { continue }
            byMountPoint[volume.mountPoint] = path
        }
        if byMountPoint.isEmpty, let fallback = Movable.volume(of: home.path(percentEncoded: false)) {
            byMountPoint[fallback.mountPoint] = home.path(percentEncoded: false)
        }
        return byMountPoint.values.sorted()
    }

    /// Free bytes across several volumes, summed.
    ///
    /// ⚠️ **`nil` when nothing could be read, never zero.** Zero free bytes is a full disk, and the
    /// sentence for "the disk is full" is nothing like the sentence for "Wellkept could not take the
    /// reading" — see `DeleteReport.sentence`, which refuses to state a figure it did not measure.
    static func freeBytes(across volumes: [String]) -> Int64? {
        var total: Int64 = 0
        var readAny = false
        for path in volumes {
            guard let free = freeBytes(onVolumeAt: path) else { continue }
            total += free
            readAny = true
        }
        return readAny ? total : nil
    }

    // MARK: ── Verb 4: Ignore ─────────────────────────────────────────────────────────────────

    /// Never raise this again.
    ///
    /// ⚠️ **It has been parked twice; this is its home.** A list in Settings, every entry restorable,
    /// each with its own record of what was ignored and what the finding said at the time. Nothing on
    /// the disk is touched — ignoring is a statement about Wellkept's future behaviour, not about the
    /// file.
    @discardableResult
    static func ignore(_ url: URL,
                       section: SectionID,
                       finding: String,
                       home: URL = StorageManifest.home()) -> LedgerTrouble? {
        let reading = IgnoreList.read(home: home)
        if let trouble = reading.trouble { return trouble }

        let path = Movable.trueSpelling(of: url.path(percentEncoded: false))
            ?? url.path(percentEncoded: false)
        var items = reading.items
        guard !items.contains(where: { $0.path == path }) else { return nil }

        items.append(IgnoredItem(path: path,
                                 identity: Movable.read(url).map(FileIdentity.init),
                                 section: section,
                                 finding: finding))
        do {
            try IgnoreList.write(items, home: home)
            return nil
        } catch {
            return LedgerTrouble(kind: .couldNotBeWritten,
                                 path: StorageManifest.ignoreList(home: home)
                                     .path(percentEncoded: false),
                                 underlying: error.localizedDescription, keptAt: nil)
        }
    }

    /// Take one entry off the ignore list, so the section can raise it again.
    @discardableResult
    static func stopIgnoring(_ id: UUID, home: URL = StorageManifest.home()) -> LedgerTrouble? {
        let reading = IgnoreList.read(home: home)
        if let trouble = reading.trouble { return trouble }
        do {
            try IgnoreList.write(reading.items.filter { $0.id != id }, home: home)
            return nil
        } catch {
            return LedgerTrouble(kind: .couldNotBeWritten,
                                 path: StorageManifest.ignoreList(home: home)
                                     .path(percentEncoded: false),
                                 underlying: error.localizedDescription, keptAt: nil)
        }
    }

    /// Everything on the ignore list, for Settings.
    static func ignored(home: URL = StorageManifest.home()) -> IgnoreList.Reading {
        IgnoreList.read(home: home)
    }

    // MARK: ── Containment, for Security's found items ────────────────────────────────────────

    /// The attribute macOS itself uses to mark a file as untrusted. Setting it is what makes
    /// Gatekeeper treat something as never-approved.
    static let untrustedAttribute = "com.apple.quarantine"

    /// Make a malicious file harmless without moving it.
    ///
    /// Two changes, both reversible and both recorded: the execute bits come off, and the file gets
    /// macOS's own untrusted mark. It stays where it is, which is deliberate — moving something
    /// XProtect is watching can break the watching, and an archive would hide it from the scanner
    /// altogether.
    static func contain(_ url: URL,
                        reason: String,
                        home: URL = StorageManifest.home(),
                        now: Date = Date(),
                        fileManager: FileManager = .default) -> Outcome {
        let path = url.path(percentEncoded: false)
        let name = url.lastPathComponent

        let verdict = Movable.check(url, reach: Reach.standard(home: home), checkOpenFiles: false)
        guard let file = verdict.reading else {
            return Outcome(path: path, name: name, record: nil,
                           refusal: verdict.sentence ?? MoveRefusal.missing.sentence)
        }
        // Containment writes to the file, so the flag and volume refusals still apply — but not the
        // open-file one: a malicious thing that is running is exactly what wants defusing.
        let blocking = verdict.refusals.filter {
            if case .openBy = $0 { return false }
            return true
        }
        guard blocking.isEmpty else {
            return Outcome(path: path, name: name, record: nil,
                           refusal: blocking.map(\.sentence).joined(separator: " "))
        }

        let markBefore = readAttribute(untrustedAttribute, at: path)
        let markNow = "0083;\(String(UInt32(now.timeIntervalSince1970), radix: 16));Wellkept;"
                    + UUID().uuidString

        let strippedOfExecute = file.mode & ~UInt16(S_IXUSR | S_IXGRP | S_IXOTH)
        guard chmod(path, mode_t(strippedOfExecute)) == 0 else {
            return Outcome(path: path, name: name, record: nil,
                           refusal: "Wellkept could not take away this file's permission to run: "
                                  + "\(String(cString: strerror(errno))).")
        }
        writeAttribute(untrustedAttribute, value: markNow, at: path)

        let containment = Containment(modeBefore: file.mode,
                                      untrustedMarkBefore: markBefore,
                                      untrustedMarkNow: markNow,
                                      containedOn: now)

        let record = QuarantineRecord(
            originalPath: file.truePath ?? path, originalName: name,
            identity: FileIdentity(file), quarantinedPath: file.truePath ?? path,
            storeRoot: ((file.truePath ?? path) as NSString).deletingLastPathComponent,
            mode: file.mode, ownerID: file.ownerID, groupID: file.groupID, flags: file.flags,
            createdOn: file.createdOn, modifiedOn: file.modifiedOn, bytes: file.bytes,
            isDirectory: file.isDirectory, isSymbolicLink: file.isSymbolicLink,
            parentMode: Movable.read(url.deletingLastPathComponent())?.mode,
            section: .security, reason: reason, quarantinedOn: now,
            wasInICloud: file.isInICloud, containment: containment)

        if let trouble = Ledger.append([record], home: home) {
            return Outcome(path: path, name: name, record: record, refusal: trouble.sentence)
        }
        return Outcome(path: path, name: name, record: record, refusal: nil)
    }

    /// Undo containment exactly. The permissions go back, and so does the untrusted mark — including
    /// its absence, if the file did not have one.
    static func release(_ record: QuarantineRecord,
                        fileManager: FileManager = .default) -> RestoreRefusal? {
        guard let containment = record.containment else { return nil }
        let path = record.originalPath

        guard Movable.exists(path) else { return .itemIsGone(path: path) }
        guard record.identity.stillDescribes(path) else { return .notTheSameFile }

        guard chmod(path, mode_t(containment.modeBefore)) == 0 else {
            return .couldNotBeMoved(why: String(cString: strerror(errno)))
        }
        if let before = containment.untrustedMarkBefore {
            writeAttribute(untrustedAttribute, value: before, at: path)
        } else {
            removeAttribute(untrustedAttribute, at: path)
        }
        return nil
    }

    // MARK: Extended attributes

    static func readAttribute(_ name: String, at path: String) -> String? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW) == size else { return nil }
        return String(decoding: buffer, as: UTF8.self)
    }

    @discardableResult
    static func writeAttribute(_ name: String, value: String, at path: String) -> Bool {
        let bytes = Array(value.utf8)
        return setxattr(path, name, bytes, bytes.count, 0, XATTR_NOFOLLOW) == 0
    }

    @discardableResult
    static func removeAttribute(_ name: String, at path: String) -> Bool {
        removexattr(path, name, XATTR_NOFOLLOW) == 0
    }

    // MARK: ── Handing the whole store over ───────────────────────────────────────────────────

    /// Move every quarantined item into a folder the user picked, and report what would not move.
    ///
    /// The uninstaller's second option. ⚠️ **This one is allowed to cross volumes**, because the
    /// person has chosen a destination and the alternative is leaving their files in a folder
    /// belonging to an app that is about to be deleted. `FileManager.moveItem` copies-and-removes
    /// when it has to; the metadata cost is real and it is the lesser harm here.
    @discardableResult
    static func handOver(_ records: [QuarantineRecord], to folder: URL,
                         fileManager: FileManager = .default) -> [QuarantineRecord] {
        records.filter { record in
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let source = record.wasContainedInPlace ? record.originalURL : record.quarantinedURL
                guard Movable.exists(source.path(percentEncoded: false)) else {
                    return true
                }
                try fileManager.moveItem(at: source,
                                         to: freeName(in: folder, for: record.originalName,
                                                      fileManager: fileManager))
                if !record.wasContainedInPlace {
                    try? fileManager.removeItem(at: record.holderURL)
                }
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
        guard Movable.exists(candidate.path(percentEncoded: false)) else {
            return candidate
        }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for n in 2...999 {
            let tried = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let url = folder.appending(path: tried)
            if !Movable.exists(url.path(percentEncoded: false)) { return url }
        }
        // A thousand collisions on one name is not a real folder, but returning a colliding URL
        // would hand `moveItem` a destination it will refuse — a caught failure, not a lost file.
        return folder.appending(path: "\(base) \(UUID().uuidString)")
    }
}

// MARK: - The move itself

/// ⭐ **The one syscall this whole app is built around.**
///
/// `renameatx_np` on the same volume: atomic, instant at any size, and it preserves creation date,
/// mode, ownership, ACLs, every extended attribute, the resource fork, BSD flags, compression,
/// sparseness and the inode. Measured 2026-08-28 against every alternative; every copy-based one
/// loses something.
enum AtomicMove {

    enum Result: Sendable, Equatable {
        case moved
        case failed(code: Int32, why: String)
    }

    /// ⚠️ **Both flags are mandatory and neither is a precaution.**
    ///
    /// `RENAME_EXCL` — without it, `rename(2)` *silently destroys* whatever is at the destination.
    /// `RENAME_NOFOLLOW_ANY` — without it, a symlinked parent component means the move acts on a
    /// file somewhere else entirely, which is how a cache cleaner deletes somebody's real data.
    static let flags = UInt32(RENAME_EXCL) | UInt32(RENAME_NOFOLLOW_ANY)

    static func perform(from source: String, to destination: String) -> Result {
        let code = renameatx_np(AT_FDCWD, source, AT_FDCWD, destination, flags)
        guard code != 0 else { return .moved }
        let number = errno
        return .failed(code: number, why: String(cString: strerror(number)))
    }

    /// What each failure means, in words. The three that matter get their own sentence because each
    /// is a different thing for a person to do next.
    static func sentence(for code: Int32, fallback: String) -> String {
        switch code {
        case EEXIST, ENOTEMPTY:
            "There is already something where this was going, and Wellkept will not write over it."
        case ELOOP:
            "The path to this file goes through a shortcut to somewhere else. Wellkept stopped "
            + "rather than change the real file at the other end."
        case EXDEV:
            "That would move the file to a different disk, which copies it. Wellkept only ever "
            + "moves a file on the disk it is already on."
        case EACCES, EPERM:
            "macOS would not let Wellkept move this file, and Wellkept does not ask for a password "
            + "to insist."
        case ENOENT:
            "There is nothing there any more."
        default:
            fallback
        }
    }
}
