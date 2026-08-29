// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  AgentSchedule.swift
//  Wellkept — App/Backup/Agent
//
//  ⭐ **When the background piece acts, decided as arithmetic so it can be tested without a drive.**
//
//  Nothing in this file touches the disk, starts a timer, or knows what a backup is. It takes four
//  facts — the time, whether the drive is there, when a run last started, when a backup last
//  worked — and answers with one action and, separately, whether there is something to say.
//
//  ## ⭐ The line that decides everything here: *automatic means looking, manual means touching*
//
//  The house rule reads as one sentence and turns out to cover two different kinds of job. Of the
//  three things John asked the background piece to do, **two write to a drive and one does not**.
//  Noticing that a backup has gone quiet is looking. So:
//
//  - The **notice** is produced on every wake, gate or no gate. It costs nothing and it is the
//    single most useful thing this feature does — this Mac's own backup had been off for days with
//    nobody told, which is the finding the whole section exists to produce.
//  - The **two copying jobs** produce an action that is refused outright until `RehearsalGate`
//    grants a pass, which it will not do until a real erase-and-restore rehearsal has been walked
//    **and** the background piece has been shown to hold Full Disk Access.
//
//  ## Why the answer is a pair and not one enum
//
//  An earlier shape folded the stale notice into the action list, and it had a bug that was
//  invisible until it was written down: a Mac whose drive had been unplugged for a fortnight would
//  report "your backup has gone quiet" **instead of** "waiting for the drive", so plugging the
//  drive in would never start anything. The notice and the action are different questions about the
//  same moment, and they are answered separately.

enum AgentSchedule {

    /// Hourly, which is John's number.
    static let betweenRuns: TimeInterval = 60 * 60

    /// ⚠️ **How often the background piece looks up from what it is doing.** The drive-appeared
    /// notification is the fast path; this is the floor underneath it, because a notification that
    /// does not arrive in a login-item process is a class of failure nobody would notice for
    /// months. Sixty seconds is cheap — it is a `stat` on one path.
    static let betweenChecks: TimeInterval = 60

    /// Nine days, taken from Core rather than repeated, so the section and its background piece
    /// cannot disagree about when a backup has gone quiet.
    static var quietAfterDays: Int { BackupFreshness.staleAfterDays }

    // MARK: ── What it decides ───────────────────────────────────────────────────────────────────

    /// Why a backup is starting. Carried so the record says which of John's three jobs fired.
    enum Because: String, Sendable, Hashable, Codable {
        case theDriveWasPluggedIn
        case anHourHasPassed
        case nothingHasEverRun

        var sentence: String {
            switch self {
            case .theDriveWasPluggedIn: "the drive was plugged in"
            case .anHourHasPassed:      "an hour has passed"
            case .nothingHasEverRun:    "nothing has been backed up yet"
            }
        }
    }

    /// The one thing to do at this moment.
    enum Action: Sendable, Hashable {

        /// Copy now.
        case backUpNow(Because)

        /// The drive is not here. Nothing to do but keep looking.
        case waitForTheDrive

        /// The drive is here and the hour is not up.
        case waitUntil(Date)

        /// ⛔ **The state this build is actually in, on every Mac.** The gate has not been opened,
        /// so the two copying jobs do not run. The notice still does.
        case notAllowedToCopyYet([RehearsalGate.Missing])

        var isACopy: Bool { if case .backUpNow = self { return true }; return false }

        /// What to write in the record.
        var sentence: String {
            switch self {
            case .backUpNow(let because):
                "Started a backup because \(because.sentence)."
            case .waitForTheDrive:
                "Did nothing — the backup drive is not connected."
            case .waitUntil(let moment):
                "Did nothing — the next backup is due at "
                    + moment.formatted(date: .omitted, time: .shortened) + "."
            case .notAllowedToCopyYet(let missing):
                "Copied nothing. " + missing.map(\.sentence).joined(separator: " ")
            }
        }
    }

    /// One moment's answer: what to do, and what — if anything — to say.
    struct Decision: Sendable, Hashable {
        let action: Action
        /// ⭐ The third job. `nil` when there is nothing worth raising.
        let notice: String?

        var sentence: String {
            [action.sentence, notice].compactMap { $0 }.joined(separator: " ")
        }
    }

    // MARK: ── ⭐ The whole decision ──────────────────────────────────────────────────────────────

    /// - Parameters:
    ///   - driveIsConnected: whether the destination is mounted right now.
    ///   - lastRunStarted: when this background piece last began a run. `nil` if never.
    ///   - lastSuccess: when a backup — ours or Time Machine's — last actually worked.
    ///   - mayCopy: what `RehearsalGate.permissionForTheBackgroundPiece` said, reduced to a Bool by
    ///     the caller that holds the `Pass`. ⚠️ **This function never sees a `Pass` and must not**:
    ///     a decision made in arithmetic is not permission to write, and keeping the token out of
    ///     here is what stops somebody deciding their way into a copy.
    ///   - missing: what the gate said was missing, so the refusal can explain itself.
    static func decide(now: Date = Date(),
                       driveIsConnected: Bool,
                       lastRunStarted: Date?,
                       lastSuccess: Date?,
                       mayCopy: Bool,
                       missing: [RehearsalGate.Missing] = []) -> Decision {

        let notice = noticeAboutAQuietBackup(lastSuccess: lastSuccess, now: now)

        guard mayCopy else {
            return Decision(action: .notAllowedToCopyYet(missing), notice: notice)
        }
        guard driveIsConnected else {
            return Decision(action: .waitForTheDrive, notice: notice)
        }
        guard let lastRunStarted else {
            return Decision(action: .backUpNow(.nothingHasEverRun), notice: notice)
        }
        let due = lastRunStarted.addingTimeInterval(betweenRuns)
        return due <= now
            ? Decision(action: .backUpNow(.anHourHasPassed), notice: notice)
            : Decision(action: .waitUntil(due), notice: notice)
    }

    /// The same moment, when the drive has just appeared. Separate entry point rather than a flag,
    /// because "the drive was plugged in" is a different reason and the record says which.
    static func decideOnConnect(now: Date = Date(),
                                lastSuccess: Date?,
                                mayCopy: Bool,
                                missing: [RehearsalGate.Missing] = []) -> Decision {
        let notice = noticeAboutAQuietBackup(lastSuccess: lastSuccess, now: now)
        guard mayCopy else {
            return Decision(action: .notAllowedToCopyYet(missing), notice: notice)
        }
        return Decision(action: .backUpNow(.theDriveWasPluggedIn), notice: notice)
    }

    // MARK: ── The third job ─────────────────────────────────────────────────────────────────────

    /// ⭐ **"Notice when it has been too long."** Looking, not touching — so it happens whatever the
    /// gate says.
    ///
    /// ⚠️ It says the number of days rather than the word "stale". A person reading "your backup is
    /// stale" has to work out whether that is bad; a person reading "your last backup was 25 days
    /// ago" already knows.
    static func noticeAboutAQuietBackup(lastSuccess: Date?, now: Date = Date()) -> String? {
        let freshness = BackupFreshness.of(lastSuccess, now: now)
        guard freshness.worthRaising else { return nil }
        guard let lastSuccess else {
            return "No backup has ever finished on this Mac."
        }
        return "Your last backup was \(BackupFreshness.phrase(for: lastSuccess, now: now)). "
            + "Wellkept says something once it has been \(quietAfterDays) days."
    }
}
