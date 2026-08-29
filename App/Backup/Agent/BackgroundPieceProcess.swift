// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import Foundation
import WellkeptCore

//  BackgroundPieceProcess.swift
//  Wellkept — App/Backup/Agent
//
//  ⭐ **The background piece, from the inside.** This is what launchd starts.
//
//  It is the app's own executable with `--background-piece` on the command line, so nothing here
//  ever creates an `NSApplication`: `WellkeptEntry.main()` branches before SwiftUI is touched. The
//  process has no window, no menu bar and no Dock tile, and it appears in **System Settings ▸
//  General ▸ Login Items** as Wellkept.
//
//  ## What it does, in order, every time it starts
//
//  1. **Never materialise a cloud file.** `ScanPolicy.prepareThisThread()` first, before anything
//     reads anything. Without it a single read can pull a file down over somebody's internet — 524
//     of them, measured, during the research. It is a per-thread setting, so it is set here and on
//     any thread this process ever adds.
//  2. ⭐ **Look at itself.** `AgentSight` probes the six protected places and writes what it found
//     to `AgentRecord`. This is the answer to the question nobody had answered: whether a login item
//     inherits the app's Full Disk Access. It is settled by measurement, in this process, before
//     anything else happens.
//  3. **Ask the gate.** `RehearsalGate.permissionForTheBackgroundPiece` needs two proofs — a real
//     erase-and-restore rehearsal, and a human having written down that they watched step 2 come
//     out clean. Today it refuses on every Mac, and the refusal is recorded in words.
//  4. **Watch.** A drive-appeared notification for speed, and a sixty-second look at the
//     destination underneath it as the floor.
//
//  ## ⚠️ Why there is a poll under the notification
//
//  `NSWorkspace.didMountNotification` in a launchd agent is not something anybody here has proved.
//  If it never arrives, the fast path silently stops working and "starts a backup when you plug the
//  drive in" quietly becomes false — the exact shape of failure this whole section is built to
//  refuse. Sixty seconds is a `stat` on one path; it costs nothing and it cannot fail silently.
//
//  ## ⛔ It copies nothing on its own
//
//  There is no copy code in this file. When the gate opens, whoever owns the copier hands one to
//  `copier`, and it takes a `RehearsalGate.Pass` — a token whose initialiser is `fileprivate` to
//  `RehearsalGate`, so a copier cannot be called without asking. Until then, `.backUpNow` is
//  unreachable, because `mayCopy` is false on every Mac.

/// What actually copies files, when there is one. ⭐ **The `Pass` in the signature is the
/// enforcement**: nothing can implement a call to this without the gate having granted it.
@MainActor
protocol BackgroundCopier: AnyObject {
    /// - Returns: a plain sentence for the record.
    func backUp(to destination: URL, permittedBy pass: RehearsalGate.Pass) -> String
}

@MainActor
enum BackgroundPieceProcess {

    /// Set by whoever owns the engine. `nil` in every build shipped so far, which is honest rather
    /// than unfinished — see the gate.
    static var copier: (any BackgroundCopier)?

    /// Kept so a wake can tell "the drive has been here for an hour" from "the drive just arrived".
    private static var driveWasConnected = false

    /// What is holding the run loop open. Held so it is not deallocated the moment it is made.
    private static var heartbeat: Timer?

    // MARK: ── ⭐ Start ───────────────────────────────────────────────────────────────────────────

    /// Run until launchd or the person stops us. Never returns.
    static func runUntilKilled() {
        // 1. Cloud files stay in the cloud. Before anything reads anything.
        ScanPolicy.prepareThisThread()

        // 2. ⭐ The self-check. Written down whatever it says.
        var record = AgentRecord.recordSight(
            as: .theBackgroundPiece,
            saying: "The background piece started.")
        record.noted(record.verdict.sentence)
        record.write()

        watchForTheDrive()
        startHeartbeat()

        // 3. The first look, immediately, so a Mac whose drive is already plugged in does not wait
        //    a minute to find out.
        wake(.started)

        // A `Timer` on the main run loop is what keeps this call from returning — a run loop with
        // no sources exits immediately, and a background piece that quit two milliseconds after
        // launchd started it would look exactly like one that was working.
        RunLoop.main.run()
        exit(0)
    }

    // MARK: ── Waking ────────────────────────────────────────────────────────────────────────────

    /// Why we are looking. Recorded so the log says which of the three jobs fired.
    enum Wake: String, Sendable {
        case started
        case theDriveAppeared
        case theClock
    }

    /// ⭐ One moment: read the facts, ask `AgentSchedule`, do what it says, write it down.
    static func wake(_ reason: Wake) {
        var record = AgentRecord.read()
        let destination = StorageManifest.backupDestination()
        let connected = destination.map(isMounted) ?? false

        // ⛔ The gate, every single wake. Not cached, not remembered from start-up: a build whose
        // rehearsal was recorded is a different build, and a decision made once at launch is a
        // decision that outlives its evidence.
        let permission = RehearsalGate.permissionForTheBackgroundPiece(
            to: destination?.lastPathComponent ?? "the backup drive")

        let justArrived = connected && !driveWasConnected
        driveWasConnected = connected

        let decision: AgentSchedule.Decision =
            (reason == .theDriveAppeared || justArrived)
                ? AgentSchedule.decideOnConnect(lastSuccess: record.lastSuccessfulBackup,
                                                mayCopy: permission.isGranted,
                                                missing: permission.refusal?.missing ?? [])
                : AgentSchedule.decide(driveIsConnected: connected,
                                       lastRunStarted: record.lastRunStarted,
                                       lastSuccess: record.lastSuccessfulBackup,
                                       mayCopy: permission.isGranted,
                                       missing: permission.refusal?.missing ?? [])

        // ⚠️ Only the two copying jobs are gated. The notice is looking, not touching, so it is
        // produced and recorded whatever the gate said — and on a Mac whose backups stopped a
        // fortnight ago it is the single most useful thing this feature does.
        if case .backUpNow = decision.action, let pass = permission.pass, let destination {
            record.lastRunStarted = Date()
            if let copier {
                record.noted(decision.sentence + " " + copier.backUp(to: destination, permittedBy: pass))
            } else {
                // Reachable only in a build where the gate has been opened and no copier has been
                // handed over. Said out loud rather than passed over in silence.
                record.noted("A backup was due and this build carries no copier, so nothing was copied.")
            }
        } else {
            record.noted(decision.sentence)
        }
        record.write()
    }

    // MARK: ── Watching ──────────────────────────────────────────────────────────────────────────

    /// The fast path. ⚠️ Unproven in a login item, which is why it is not the only path.
    private static func watchForTheDrive() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { wake(.theDriveAppeared) }
        }
    }

    /// The floor: look at the destination every minute. Also what keeps the run loop alive.
    private static func startHeartbeat() {
        let timer = Timer(timeInterval: AgentSchedule.betweenChecks, repeats: true) { _ in
            // A timer added to the main run loop fires on the main thread, always.
            MainActor.assumeIsolated { wake(.theClock) }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    /// Whether the destination is actually there right now.
    ///
    /// ⚠️ Deliberately the plainest possible test. Anything cleverer — asking about volumes,
    /// matching names — is a way to be wrong about somebody's drive, and being wrong here means
    /// either a backup that never runs or a backup written into a folder on the startup disk with
    /// the drive's name on it.
    static func isMounted(_ destination: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let there = FileManager.default.fileExists(atPath: destination.path(percentEncoded: false),
                                                  isDirectory: &isDirectory)
        return there && isDirectory.boolValue
    }
}
