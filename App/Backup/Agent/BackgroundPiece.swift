// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  BackgroundPiece.swift
//  Wellkept — App/Backup/Agent
//
//  ⭐ **The one place that names the Login Item.** Its label, the plist it is declared in, the flag
//  that tells the executable it is the background piece rather than the app, and the three things
//  it is allowed to do. Everything else in this folder reads those from here.
//
//  ## What John agreed to, on 2026-08-29, in his words
//
//  A small part of Wellkept that keeps running quietly — **`SMAppService.agent`, no password, no
//  root**, listed in **System Settings ▸ Login Items** where it can be switched off, **and off is
//  still a complete app.** It does three things and there is no fourth: back up hourly while the
//  drive is connected, start a backup the moment the drive is plugged in, and notice when a backup
//  has not worked in a while.
//
//  ## ⚠️ This is the sentence that changed
//
//  Until this file existed, "Wellkept quits when its window closes and has no background piece" was
//  true, and it was written into the Help page, three source files and `docs/CONTRACTS.md`. It is
//  half true now, and half-true is the worst state for a promise. The replacement keeps **both**
//  halves — the app still quits unless the person switches this on — and it is written once, in
//  `Backup.whatHappensWhenTheWindowCloses`, so the five copies cannot drift again.
//
//  `sentencesThatAreNoLongerTrue` records the old wording so a test can hunt for it. Copying an old
//  claim back in from another file is exactly how this sort of thing returns.
//
//  ## ⚠️ Why the background piece is the app's own executable, and not a separate helper
//
//  A LaunchAgent normally ships as its own little tool inside `Contents/MacOS`. This one is
//  `Contents/MacOS/Wellkept` with a flag, and the reason is the whole risk of this feature.
//
//  **macOS decides Full Disk Access from the code signature of the thing asking.** A separate
//  helper is a different program with a different identity, so it would almost certainly be handed
//  its own empty entry in the privacy list — and a backup made without the grant contains **no
//  mail, no messages and no photos, and macOS reports no error at all.** The same executable, at
//  the same path, with the same signature, is the arrangement with the best chance of inheriting
//  what the app was granted.
//
//  ⛔ **"Best chance" is not evidence, and this app does not ship on a guess.** `AgentSight` is the
//  check the background piece runs on itself, in its own process, before it copies anything, and
//  `RehearsalGate.agentHoldsFullDiskAccess` is where a human writes down what it found. Until
//  somebody has actually watched it, the background piece looks and refuses to copy.

enum BackgroundPiece {

    // MARK: ── ⭐ Identity, in one place ─────────────────────────────────────────────────────────

    /// The launchd label. ⚠️ **A literal, not built from `Bundle.main`**, because it has to match
    /// the plist inside the bundle byte for byte and a bundle identifier that came back `nil` would
    /// register a job under a name that unregisters nothing. `BackgroundPieceTests` reads the plist
    /// off the disk and asserts the two agree.
    static let label = "studio.stonemesa.wellkept.agent"

    /// The file in `Contents/Library/LaunchAgents/`. `SMAppService.agent(plistName:)` takes exactly
    /// this string.
    static let plistName = "studio.stonemesa.wellkept.agent.plist"

    /// ⭐ What launchd puts on the command line to say "you are the background piece, not the app".
    static let launchArgument = "--background-piece"

    /// Whether this process was started as the background piece.
    ///
    /// Read from the arguments rather than from anything stored: a process cannot be wrong about
    /// how it was started, and there is no state to get out of step.
    static func isTheBackgroundPiece(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.dropFirst().contains(launchArgument)
    }

    // MARK: ── The three things it does, and there is no fourth ───────────────────────────────────

    /// ⭐ **The whole list.** A background piece whose job list can grow is a background piece
    /// nobody can describe, and the sentence in Help says "three things" out loud.
    enum Job: String, CaseIterable, Identifiable, Sendable {

        /// Back up once an hour, for as long as the drive is there.
        case hourlyWhileTheDriveIsConnected

        /// Start a backup when the drive appears.
        case whenTheDriveIsPluggedIn

        /// Say so when a backup has not worked in `BackupFreshness.staleAfterDays` days.
        case noticeABackupThatHasGoneQuiet

        var id: String { rawValue }

        var label: String {
            switch self {
            case .hourlyWhileTheDriveIsConnected: "Backs up every hour while your drive is connected"
            case .whenTheDriveIsPluggedIn:        "Starts a backup when you plug the drive in"
            case .noticeABackupThatHasGoneQuiet:  "Tells you when a backup has not worked in \(BackupFreshness.staleAfterDays) days"
            }
        }

        /// ⭐ **Whether this job writes to a drive.**
        ///
        /// The line matters more than it looks. *Automatic means looking. Manual means touching* —
        /// the house rule — and noticing that a backup has gone quiet is looking. So the third job
        /// runs today, before the rehearsal, and the first two do not. That is not a workaround;
        /// it is the rule applied to three jobs that turn out not to be the same kind of thing.
        var copiesFiles: Bool { self != .noticeABackupThatHasGoneQuiet }
    }

    // MARK: ── The words ─────────────────────────────────────────────────────────────────────────

    /// The switch, wherever it is drawn. **Owned here so the Backup face and Settings cannot
    /// describe the same switch differently.**
    static let switchTitle = "Back up in the background"

    /// What switching it on actually gets, and what it costs. No hedging: it names the three jobs
    /// and says where the row appears in System Settings, because somebody who finds an unfamiliar
    /// login item and cannot place it will switch it off, and they will be right to.
    static let switchExplanation = """
        A small part of Wellkept keeps running after you close the window, and does three things: \
        backs up every hour while your drive is connected, starts a backup when you plug the drive \
        in, and tells you when a backup has not worked in \(BackupFreshness.staleAfterDays) days. \
        It needs no password and no administrator. It is listed as Wellkept in System Settings ▸ \
        General ▸ Login Items, where you can switch it off without asking us.
        """

    /// ⚠️ **Off is a complete app, and that has to be said in the same breath.** An app that
    /// describes its optional background piece as though the app were crippled without it has made
    /// the switch compulsory in everything but name.
    static let whenItIsOff = """
        With it off, Wellkept quits when you close its window and backs up only when you press the \
        button. Nothing else changes: every section still works, and every check still runs.
        """

    /// The replacement for the old claim, taken from Core rather than written again here.
    static var whatHappensWhenTheWindowCloses: String { Backup.whatHappensWhenTheWindowCloses }

    /// What has to be proved before it copies anything, taken from Core for the same reason.
    static var mustProveFirst: String { Backup.whatTheBackgroundPieceMustProveFirst }

    // MARK: ── ⚠️ The claims that stopped being true on 2026-08-29 ───────────────────────────────

    /// ⛔ **Recorded so a test can hunt for them.** Each was true, was written in several places, and
    /// is now wrong. They are listed rather than merely deleted because the failure mode is somebody
    /// copying a familiar sentence forward from a file that was not updated.
    ///
    /// ⚠️ The exempt file is this one — it is the only place they may appear.
    static let sentencesThatAreNoLongerTrue = [
        "has no background piece",
        "no part that runs in the background",
        "ships no background piece",
        "nothing runs while the app is closed",
        "no background scanning",
    ]
}
