// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  BackupRows.swift
//  Wellkept — App/Sections/Backup
//
//  **The two rows nobody else builds: Wellkept's own backup, and the Recovery Plan.**
//
//  `TimeMachineReader` builds `.appleBackup` and `CoverageReader` builds `.notCovered`, because both
//  are measurements of this Mac. These two are not measurements. One reports the state of *this
//  app* — whether the engine may be offered at all — and the other reports whether a person has a
//  piece of paper. Neither has a reader, so they are built here, from the facts the section already
//  has.
//
//  ## ⛔ The rule the first of them exists to keep
//
//  **A backup is proven by erasing a drive and restoring from it. It is never proven by a passing
//  test suite, and no restore has ever been performed with this code.** So the engine is built,
//  tested and complete — and it is offered to nobody. `RehearsalGate.Pass` cannot be constructed
//  outside its own file, which makes calling a copier a compile error rather than a convention, and
//  this row is the visible half of that: it draws, it explains itself, and it has no button.
//
//  ⚠️ **Hiding the row instead would be a different lie.** An app that pretends a feature does not
//  exist has not been honest about why it is switched off; it has just stopped mentioning it.
//
//  ## Why the second one is `.attention` and never `.problem`
//
//  Not having printed a page is not a malfunction. `BackupRow` clamps `.recoveryPlan` to
//  `.attention` on its own, so the two agree by construction rather than by agreement.

enum BackupRows {

    // MARK: - ⭐ Wellkept's own backup

    /// **What Wellkept's own backup is, and why it is not on offer.**
    ///
    /// - Parameters:
    ///   - destination: the drive somebody has pointed Backup at, if they have. Named, never
    ///     measured — reading a drive that is not attached is how `tmutil latestbackup` ended up
    ///     trying to mount one.
    ///   - agentIsOn: whether the background piece is registered right now.
    static func wellkeptBackup(destination: String?, agentIsOn: Bool) -> BackupRow {
        let offered = RehearsalGate.mayBeOffered

        var details: [DetailPair] = [
            DetailPair("What it copies", Backup.whatItPromises),
            DetailPair("Why a copy that succeeded is not proof", Backup.whyTheReturnCodeIsNotEvidence),
            DetailPair("When the window closes", Backup.whatHappensWhenTheWindowCloses),
            DetailPair("The background piece", Backup.whatTheBackgroundPieceMustProveFirst),
            DetailPair("Our own snapshots", Backup.whySnapshotsAreNotAFallback),
            DetailPair("Where you pointed it", destination ?? "Nowhere yet"),
            DetailPair("Background piece", agentIsOn ? "On" : "Off"),
        ]
        details.append(contentsOf: RehearsalGate.detailPairs)

        return BackupRow(
            topic: .wellkeptBackup,
            headline: offered
                ? "Wellkept can copy your home folder to a drive you choose."
                : "Wellkept's own backup is built, and it is not being offered yet.",
            measure: nil,
            // ⚠️ The gate's own sentence, never a paraphrase. It says what has not happened rather
            // than that a feature is unavailable, and those read completely differently to somebody
            // deciding whether the app is broken.
            reason: offered ? Backup.whatItPromises : RehearsalGate.faceLine,
            // Never a fault. Nothing is wrong with the person's Mac because we have not finished
            // testing our own copier.
            severity: .information,
            details: details,
            withheld: offered ? nil : RehearsalGate.faceLine)
    }

    // MARK: - ⭐ The Recovery Plan

    /// **Whether there is a page, and whether it still describes this Mac.**
    ///
    /// - Parameters:
    ///   - onRecord: the page that was actually printed, or `nil` if nobody has printed one.
    ///   - today: the page as it would be written now — the source of the macOS version the record
    ///     is compared against.
    static func recoveryPlan(onRecord: RecoveryPlan?, today: RecoveryPlan) -> BackupRow {
        let verb = Remedy(title: onRecord == nil ? "Write the Recovery Plan" : "Open the Recovery Plan")

        guard let onRecord else {
            return BackupRow(
                topic: .recoveryPlan,
                headline: "You have not printed a Recovery Plan.",
                measure: nil,
                reason: "One page, printed and kept somewhere that is not this Mac, with what to do "
                      + "on the day it will not start. It needs no drive, no permission and no "
                      + "network — and instructions that live only on the Mac that has stopped "
                      + "working are worth nothing.",
                severity: .attention,
                details: today.detailPairs,
                remedy: verb)
        }

        let stale = onRecord.reprintLine(currentMacOS: today.macOSVersion)
        let written = onRecord.writtenOn.formatted(date: .abbreviated, time: .omitted)

        return BackupRow(
            topic: .recoveryPlan,
            headline: stale == nil
                ? "Your Recovery Plan is current."
                : "Your Recovery Plan was written for an older macOS.",
            measure: "Printed \(written)",
            // ⚠️ The page has a lifetime, and this is the sentence that says so. Migration
            // Assistant refuses a backup made on a newer macOS than the machine being restored to,
            // so a page naming the wrong version is describing a restore that will be refused.
            reason: stale ?? "Wellkept cannot see the page itself. It remembers that you made one, "
                           + "on \(written), for macOS \(onRecord.macOSVersion).",
            severity: stale == nil ? .information : .attention,
            details: onRecord.detailPairs,
            remedy: verb)
    }

    /// ⛔ **The one line that is true of both rows and of nothing else in this app.**
    ///
    /// Recovery is macOS's, Migration Assistant is macOS's, and the page is paper. Wellkept plays no
    /// part in getting a Mac working again — and a recovery page that required the app you cannot
    /// run would be a joke at somebody's expense.
    static let whatWellkeptIsNotPartOf = """
        Getting a Mac working again is done with macOS's own tools. Wellkept plays no part in it, \
        and you do not need to install it to use a backup it made.
        """
}
