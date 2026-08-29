// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import CoreServices
import Darwin
import Foundation
import WellkeptCore

//  ChangeJournal.swift
//  Wellkept — App/Backup/Engine
//
//  ⭐ **What changed since last time, replayed out of the journal macOS already keeps.**
//
//  ## The measurement
//
//  **120,426 changes replayed in 5.2 seconds, none dropped.** The full-walk fallback took
//  **34 seconds for 991,153 files.** Neither is slow, which is the useful finding: change detection
//  is not the hard part of this section and it does not need to be clever. What it needs to be is
//  **honest about when it does not know**, and that is what most of this file is.
//
//  ## What this is, in one line
//
//  macOS keeps a per-volume log of every directory that changed, with an ever-increasing event
//  number. Ask it for everything since number N and it replays the log. `FSEvents` is the public
//  reading of it, it needs no permissions, and it is the same mechanism Spotlight and Time Machine
//  use.
//
//  ## ⚠️ The four ways it lies, and the one answer to all of them
//
//  1. **`kFSEventStreamEventFlagMustScanSubDirs`** — "too much changed here to list it". The log
//     coalesced. It is telling you to go and look.
//  2. **`UserDropped` / `KernelDropped`** — events were thrown away because something could not keep
//     up. What was thrown away is not recoverable and is not named.
//  3. **`EventIdsWrapped`** — the numbering restarted. Every mark taken before it is meaningless.
//  4. **The volume's UUID changed** — the drive was reformatted, or it is a different drive with the
//     same name. Event numbers from the old one address nothing.
//
//  ⛔ **In every one of those cases the answer is the same: throw the replay away and walk the whole
//  folder.** There is no partial credit here. A backup built from a journal that quietly dropped
//  events is a backup missing files nobody can name, and it will report success. Thirty-four
//  seconds is the entire cost of never having that happen.
//
//  ⚠️ **A timeout is also a lie.** If `HistoryDone` never arrives, we do not know whether we saw the
//  whole log or half of it, so a timeout is `.notTrustworthy` too — never "here is what we got".
//
//  ## What the journal gives, and what it does not
//
//  It names **directories**, not files, unless the stream asks for file-level events — and even
//  with `kFSEventStreamCreateFlagFileEvents` a coalesced batch degrades to the containing folder. So
//  a replay produces **places to look**, and the copier stats each one. That is the honest shape:
//  the journal narrows the walk, it never replaces the reading of a file.
//
//  ⛔ **The recorded-snapshot fallback is dead twice over** and must not be proposed again: mounting
//  a snapshot needs root, and `tmutil localsnapshot` only works on a volume already in a Time
//  Machine set, so on a Mac with no destination it produces nothing at all. The sentence lives in
//  `Backup.whySnapshotsAreNotAFallback`.
//
//  Nothing here writes anything. The writers take a `RehearsalGate.Pass`; this file reads a log.

// MARK: - Where we were up to

/// ⭐ **A place in the journal**, kept between runs so the next one knows where to start.
///
/// The volume's UUID is stored with the event number and is **not decoration**: event numbers are
/// per-volume, so a mark taken on one drive addresses nothing on another, and a drive that was
/// reformatted starts numbering again. Comparing them is the difference between an incremental
/// backup and a confident copy of the wrong changes.
struct JournalMark: Sendable, Equatable, Hashable, Codable {

    /// The event number this run finished at.
    let eventID: UInt64

    /// The volume the number belongs to. `nil` when macOS would not give one, which makes the mark
    /// unusable — recorded honestly rather than assumed to match.
    let volumeUUID: String?

    let takenOn: Date

    init(eventID: UInt64, volumeUUID: String?, takenOn: Date = Date()) {
        self.eventID = eventID
        self.volumeUUID = volumeUUID
        self.takenOn = takenOn
    }

    /// Whether this mark can be used against the volume in front of us now.
    func addresses(volumeUUID current: String?) -> Bool {
        guard let volumeUUID, let current else { return false }
        return volumeUUID == current
    }
}

// MARK: - Why a replay could not be trusted

/// ⚠️ **Why the journal was thrown away.** Every case means the same thing to the caller — walk
/// everything — and they are separate so the record can say which one happened.
enum JournalDoubt: String, Sendable, Equatable, CaseIterable, Codable {

    /// No mark from a previous run, or the first backup. Not a fault.
    case thereIsNoEarlierRun

    /// The mark belongs to a different volume, or the volume was reformatted.
    case theMarkIsForADifferentDrive

    /// macOS said too much changed to list it.
    case tooMuchChangedToList

    /// Events were thrown away by macOS.
    case macOSDroppedEvents

    /// The numbering restarted.
    case theNumberingRestarted

    /// The replay did not finish in the time allowed.
    case itDidNotFinish

    /// The stream could not be created at all.
    case theJournalCouldNotBeRead

    /// What the record says. ⚠️ Plain, and never alarming: the first case is the ordinary first run,
    /// and the rest cost thirty-four seconds rather than costing anything a person notices.
    var sentence: String {
        switch self {
        case .thereIsNoEarlierRun:
            "This is the first backup to this drive, so Wellkept looked at everything."
        case .theMarkIsForADifferentDrive:
            "The record of what changed belongs to a different drive, so Wellkept looked at everything."
        case .tooMuchChangedToList:
            "Too much changed for macOS to list it, so Wellkept looked at everything."
        case .macOSDroppedEvents:
            "macOS lost track of some changes, so Wellkept looked at everything rather than guess."
        case .theNumberingRestarted:
            "macOS restarted its record of changes, so Wellkept looked at everything."
        case .itDidNotFinish:
            "Reading the list of changes did not finish, so Wellkept looked at everything."
        case .theJournalCouldNotBeRead:
            "Wellkept could not read the list of changes, so it looked at everything."
        }
    }

    /// ⚠️ **None of these is a problem.** The fallback is 34 seconds and the result is identical.
    /// Reporting them as faults would teach a person to worry about the safe path.
    var isAProblem: Bool { false }
}

// MARK: - The answer

/// What a replay produced.
enum JournalReplay: Sendable, Equatable {

    /// The places that changed, as folder paths. ⚠️ **Places to look, not files to copy** — the
    /// copier stats each one, because the journal coalesces to the containing folder.
    case placesThatChanged([String], upTo: JournalMark)

    /// ⛔ Walk everything. Carries which of the four lies happened.
    case lookAtEverything(JournalDoubt, upTo: JournalMark)

    var doubt: JournalDoubt? {
        if case .lookAtEverything(let doubt, _) = self { return doubt }
        return nil
    }

    var places: [String]? {
        if case .placesThatChanged(let places, _) = self { return places }
        return nil
    }

    /// Where the next run should start from, whichever way this one went.
    var mark: JournalMark {
        switch self {
        case .placesThatChanged(_, let mark), .lookAtEverything(_, let mark): mark
        }
    }
}

// MARK: - Reading the journal

enum ChangeJournal {

    /// How long a replay is allowed to take before it is thrown away.
    ///
    /// The measured replay was 5.2 seconds for 120,426 changes. Sixty is roughly ten times that,
    /// which leaves room for a machine far busier than this one and still fails long before a
    /// person would wonder whether the app had hung.
    static let patience: TimeInterval = 60

    /// The volume's own UUID, as `FSEvents` numbers it. `nil` on a volume that has no journal.
    static func journalUUID(ofVolumeAt path: String) -> String? {
        var status = stat()
        guard stat(path, &status) == 0 else { return nil }
        guard let uuid = FSEventsCopyUUIDForDevice(status.st_dev) else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// ⭐ **A mark for right now**, to be stored at the end of a successful run.
    ///
    /// ⚠️ Taken **before** the copy starts, never after. Anything that changes while the copy runs
    /// then lands in the next run rather than falling in the gap between the two.
    static func markHere(volumeAt path: String) -> JournalMark {
        JournalMark(eventID: FSEventsGetCurrentEventId(),
                    volumeUUID: journalUUID(ofVolumeAt: path))
    }

    /// ⭐ **Everything that changed under `root` since `mark`.**
    ///
    /// - Parameters:
    ///   - mark: where the last run finished. `nil` is the ordinary first run.
    ///   - root: the folder to ask about — the home folder.
    ///   - patience: how long to wait for the replay to finish.
    static func changes(since mark: JournalMark?,
                        under root: URL,
                        patience: TimeInterval = ChangeJournal.patience) -> JournalReplay {

        let rootPath = root.path(percentEncoded: false)
        let now = markHere(volumeAt: rootPath)

        guard let mark else { return .lookAtEverything(.thereIsNoEarlierRun, upTo: now) }
        guard mark.addresses(volumeUUID: now.volumeUUID) else {
            return .lookAtEverything(.theMarkIsForADifferentDrive, upTo: now)
        }

        let collector = JournalCollector()
        guard let stream = makeStream(root: rootPath, since: mark.eventID, collector: collector) else {
            return .lookAtEverything(.theJournalCouldNotBeRead, upTo: now)
        }

        let queue = DispatchQueue(label: "studio.stonemesa.wellkept.journal")
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return .lookAtEverything(.theJournalCouldNotBeRead, upTo: now)
        }

        let finished = collector.waitForHistory(patience)

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        // ⚠️ The order matters. A run that both dropped events AND finished is still untrustworthy,
        // so the doubts are tested before the timeout is.
        if let doubt = collector.doubt { return .lookAtEverything(doubt, upTo: now) }
        guard finished else { return .lookAtEverything(.itDidNotFinish, upTo: now) }

        return .placesThatChanged(collector.places, upTo: now)
    }

    /// The stream itself.
    ///
    /// `kFSEventStreamCreateFlagFileEvents` asks for individual files rather than only folders, and
    /// `NoDefer` makes the first batch arrive immediately rather than after the latency window.
    /// `UseCFTypes` is what lets the paths come back as strings instead of a C array.
    private static func makeStream(root: String,
                                   since eventID: UInt64,
                                   collector: JournalCollector) -> FSEventStreamRef? {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(collector).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil)

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagFileEvents
                           | kFSEventStreamCreateFlagNoDefer)

        return FSEventStreamCreate(kCFAllocatorDefault,
                                   journalCallback,
                                   &context,
                                   [root] as CFArray,
                                   eventID,
                                   0,
                                   flags)
    }
}

// MARK: - What the callback writes into

/// Collects a replay from the FSEvents callback, which arrives on a dispatch queue while the caller
/// waits on a semaphore.
///
/// `@unchecked Sendable` with a lock, because the callback is a C function pointer: it cannot be a
/// closure that captures, so the shared state has to be reached through the context pointer and
/// guarded here.
private final class JournalCollector: @unchecked Sendable {

    private let lock = NSLock()
    private var collected: [String] = []
    private var found: JournalDoubt?
    private let historyDone = DispatchSemaphore(value: 0)

    /// The four flags that mean the replay cannot be trusted, in the order they are checked.
    ///
    /// ⚠️ `RootChanged` is deliberately absent: it means the folder we asked about was moved or
    /// removed, which the copier discovers for itself when it stats the source and reports far
    /// better than a journal flag would.
    func note(flags: FSEventStreamEventFlags, path: String) {
        lock.lock()
        defer { lock.unlock() }

        if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
            // ⚠️ The two "dropped" flags accompany MustScanSubDirs and say who dropped them. Named
            // separately because "macOS lost track" and "too much changed at once" read differently
            // to a person, even though the answer to both is the same walk.
            if flags & UInt32(kFSEventStreamEventFlagUserDropped) != 0
                || flags & UInt32(kFSEventStreamEventFlagKernelDropped) != 0 {
                found = found ?? .macOSDroppedEvents
            } else {
                found = found ?? .tooMuchChangedToList
            }
        }
        if flags & UInt32(kFSEventStreamEventFlagEventIdsWrapped) != 0 {
            found = found ?? .theNumberingRestarted
        }
        if flags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 {
            historyDone.signal()
            return
        }
        if !path.isEmpty { collected.append(path) }
    }

    /// Wait for the replay to say it has reached the present. `false` means it never did.
    func waitForHistory(_ patience: TimeInterval) -> Bool {
        historyDone.wait(timeout: .now() + patience) == .success
    }

    var doubt: JournalDoubt? { lock.lock(); defer { lock.unlock() }; return found }

    /// The places, de-duplicated and sorted. A journal replay names the same folder many times.
    var places: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(Set(collected)).sorted()
    }
}

/// The C callback. It can capture nothing, so everything it needs arrives through `info`.
private let journalCallback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
    guard let info else { return }
    let collector = Unmanaged<JournalCollector>.fromOpaque(info).takeUnretainedValue()
    let list = unsafeBitCast(paths, to: NSArray.self)
    for index in 0..<count {
        let path = (index < list.count ? list[index] as? String : nil) ?? ""
        collector.note(flags: flags[index], path: path)
    }
}
