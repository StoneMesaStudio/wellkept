// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import Observation
import WellkeptCore

//  BackupModel.swift
//  Wellkept — App/Sections/Backup
//
//  **The one place the Backup check is run**, and the one row it sends up to Overview.
//
//  Same shape as `SecurityModel`, `AppsModel` and `ChangesModel`: detached reads, one report, one
//  finding. The section is the sixth instance of a pattern rather than a new design.
//
//  ## ⭐ What is different here, and it is the reason this section leads with Apple's backup
//
//  **Time Machine's whole state reads with zero permissions and in 52 milliseconds** — on or off,
//  the destination, whether the drive is here, the last success, the days since, the error and its
//  cause. Nothing else in this app answers a question that useful that cheaply. So the first read
//  is the one that helps somebody today, and everything Wellkept might one day do about it comes
//  after.
//
//  On the machine this was written on, that read says: *"Time Machine is switched off. It is still
//  set up, and it last backed up 4 days ago."* Nobody had told him.
//
//  ## The three reads, and what each costs
//
//  | Step | What it does | Cost |
//  |---|---|---|
//  | Apple's backup | `TimeMachineReader.read()` — preferences, mounted volumes, and the log only on a Mac that actually failed | 52 ms, nothing granted |
//  | What is not covered | `CoverageReader.read()` — `lstat` on eleven places, the iCloud services list, and a bounded walk for cloud-only files | seconds |
//  | The rest | what this Mac is, whether FileVault is on, and the page on record | one `diskutil` call |
//
//  ⚠️ **This section does not run on launch, for the middle one.** The cloud walk is a walk, and a
//  section that spent it on every launch would make the app feel slow on a screen where nothing had
//  changed. It runs on a press, like the other five.
//
//  ## ⛔ What this model will never do
//
//  - **Switch Time Machine on, off, or start a backup.** The row's button opens Apple's own pane.
//    Nothing in Wellkept ever enables, disables or triggers a backup.
//  - **Write a single byte to any drive.** `BackupRun` takes a `RehearsalGate.Pass`, which cannot be
//    constructed outside `RehearsalGate`, and this file never asks for one.
//  - **Call `tmutil latestbackup`.** Its first act is to mount the destination — measured on this
//    Mac with the drive unplugged: `Failed to mount backup destination … Code=18`.

// MARK: - What one run produced

/// Everything one Backup check produced: the report the screen draws, and the raw readings the
/// **Options** block shows underneath it.
struct BackupAnswer: Sendable {

    /// The report. Everything the face says comes from here.
    let report: BackupReport

    /// Apple's own backup, in full — including the snapshot reference point and the recorded
    /// backup dates, which are facts about this Mac rather than conclusions.
    let timeMachine: TimeMachineReader.Result

    /// What is and is not covered. `nil` only where the reader was not run.
    let coverage: CoverageReader.Reading?

    /// ⭐ The page **as it would be written today**, from this Mac as it is now. Not the page on
    /// record — that is `report.recoveryPlan`, and the difference between the two is what makes
    /// "print it again" possible to say.
    let planForToday: RecoveryPlan
}

// MARK: - The model

@MainActor
@Observable
final class BackupModel {

    // MARK: What the screen draws

    /// The last answer. `nil` until the first check finishes — the ordinary state on every launch,
    /// because nothing starts this but a press.
    private(set) var answer: BackupAnswer?

    private(set) var isChecking = false

    /// What it is doing at this moment. `nil` when nothing is running.
    private(set) var stage: Stage?

    /// What the last press of a button on this screen did, in that action's own words. Held rather
    /// than flashed, for the same reason Storage holds its outcome line: it reports something a
    /// person then has to go and find.
    private(set) var lastWord: String?

    // MARK: - The stages

    /// Three honest steps, in the order they happen.
    enum Stage: String, CaseIterable, Sendable, Hashable {
        case appleBackup
        case whatIsNotCovered
        case theRecoveryPlan

        var sentence: String {
            switch self {
            case .appleBackup:
                "Reading what Time Machine is doing — this needs no permission…"
            case .whatIsNotCovered:
                "Looking at what is and is not in a backup, and what is in the cloud…"
            case .theRecoveryPlan:
                "Working out what your Recovery Plan would say about this Mac…"
            }
        }

        /// How far through the run this is, one-based, for the count beside the spinner.
        var step: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

        static var count: Int { allCases.count }
    }

    // MARK: - ⭐ Running it

    /// **Read Apple's backup, read what is not covered, and work out what the page would say.**
    ///
    /// Safe to call again; a second call while one is running is ignored rather than queued.
    ///
    /// Every read runs detached. They block — `cfprefsd`, mounted volumes, `lstat` on eleven places,
    /// a bounded walk and one `diskutil` — and none of that may happen where the window is waiting
    /// to draw.
    func check(now: Date = Date()) async {
        guard !isChecking else { return }
        isChecking = true
        defer {
            isChecking = false
            stage = nil
        }

        stage = .appleBackup
        let machine = await Task.detached(priority: .userInitiated) {
            TimeMachineReader.read(now: now)
        }.value

        // ⚠️ **Passed in, never assumed.** A reader handed `true` when it is false describes a
        // backup that silently holds no mail, and nothing in this app is allowed to hard-code it.
        stage = .whatIsNotCovered
        let held = await Task.detached(priority: .userInitiated) { FullDiskAccess.isGranted }.value
        let state = machine.state
        let coverage = await Task.detached(priority: .userInitiated) {
            CoverageReader.read(timeMachine: state, fullDiskAccessHeld: held, now: now)
        }.value

        stage = .theRecoveryPlan
        let planned = await Task.detached(priority: .userInitiated) {
            Self.planForToday(destinationName: state.destination?.name, writtenOn: now)
        }.value
        let onRecord = await Task.detached(priority: .userInitiated) { RecoveryPlanStore.read() }.value

        let agentIsOn = BackgroundPieceService.isOn

        answer = Self.assemble(machine: machine,
                               coverage: coverage,
                               planForToday: planned,
                               onRecord: onRecord,
                               destination: StorageManifest.backupDestination()?
                                   .lastPathComponent,
                               agentIsOn: agentIsOn,
                               now: now)
    }

    /// Put the four rows together into the one report.
    ///
    /// ⚠️ **Order is not decided here.** `BackupReport.init` sorts by `BackupTopic.order` and drops
    /// duplicates, so a row arriving late cannot rearrange the screen.
    nonisolated static func assemble(machine: TimeMachineReader.Result,
                                     coverage: CoverageReader.Reading?,
                                     planForToday: RecoveryPlan,
                                     onRecord: RecoveryPlan?,
                                     destination: String?,
                                     agentIsOn: Bool,
                                     now: Date = Date()) -> BackupAnswer {

        var rows: [BackupRow] = [machine.row]
        if let coverage { rows.append(coverage.row) }
        rows.append(BackupRows.wellkeptBackup(destination: destination, agentIsOn: agentIsOn))
        rows.append(BackupRows.recoveryPlan(onRecord: onRecord, today: planForToday))

        let report = BackupReport(timeMachine: machine.state,
                                  rows: rows,
                                  // ⚠️ `nil`, and it must stay `nil` until a Wellkept backup has
                                  // actually been made. `BackupCompleteness` describes a run that
                                  // happened; inventing one for a run that never started would put
                                  // "this backup is complete" on a Mac with no backup at all.
                                  completeness: nil,
                                  recoveryPlan: onRecord,
                                  currentMacOS: planForToday.macOSVersion,
                                  ranAt: now)

        return BackupAnswer(report: report,
                            timeMachine: machine,
                            coverage: coverage,
                            planForToday: planForToday)
    }

    // MARK: - ⭐ The page as it would be written today

    /// **What the Recovery Plan would say about this Mac, right now.**
    ///
    /// Rebuilt on every check rather than stored, because every fact in it can move: the macOS
    /// version, whether FileVault is on, which drive the backup is on. The stored copy is the page
    /// somebody actually printed, and comparing the two is the whole point.
    ///
    /// ⚠️ **The architecture is optional and stays optional.** A Mac whose model identifier is not
    /// in `MacModels` gets the instruction that covers both routes, described by the year somebody
    /// can read off the About screen rather than by the name of a processor. Guessing here would
    /// send somebody holding the wrong key at the worst possible moment.
    nonisolated static func planForToday(destinationName: String?, writtenOn: Date = Date()) -> RecoveryPlan {
        let facts = MachineReader.read()
        let model = MacModels.model(for: facts.modelIdentifier)

        return RecoveryPlan.make(macOSVersion: version(from: facts.systemVersion),
                                 macDescription: description(of: facts),
                                 architecture: model?.architecture,
                                 destinationName: destinationName,
                                 fileVaultOn: fileVaultIsOn(),
                                 writtenOn: writtenOn)
    }

    /// `"macOS 26.6.2"` → `"26.6.2"`.
    ///
    /// The page writes "macOS \(version)" itself, and a plan whose version read "macOS macOS 26.6.2"
    /// would also never match the current one, so the staleness check would fire forever.
    nonisolated static func version(from systemVersion: String) -> String {
        let trimmed = systemVersion.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("macOS ") else { return trimmed }
        return String(trimmed.dropFirst("macOS ".count))
    }

    /// What the page calls this Mac. **The name first**, because a household with two of these ends
    /// up with two pages and the model is what they have in common.
    nonisolated static func description(of facts: MachineFacts) -> String {
        facts.modelName.isEmpty || facts.modelName == facts.name
            ? facts.name
            : "\(facts.name) — \(facts.modelName)"
    }

    /// **Whether the disk is locked.**
    ///
    /// ⚠️ `false` here means two different things — off, or unreadable — and the page treats them
    /// the same on purpose. The FileVault-off page says "if you ever switch FileVault on, come back
    /// and reprint this", which is the right sentence for somebody we could not read as well as for
    /// somebody who has it off. The alternative was a third kind of page about a permission.
    nonisolated static func fileVaultIsOn() -> Bool {
        ProtectionReader.fileVault(volume: ProtectionReader.fileVaultVolume(timeout: 5)).state == .on
    }

    // MARK: - What a press did

    /// Record that a page reached a printer or a file, and say so where the person is looking.
    ///
    /// ⚠️ The row is rebuilt from the stored page rather than being patched in place, so the
    /// headline, the measure and the severity all move together. A screen that flipped one of the
    /// three by hand is how a row ends up saying "current" beside a date from last year.
    func recordThePlanWasPrinted(_ plan: RecoveryPlan, now: Date = Date()) {
        guard RecoveryPlanStore.record(plan) else {
            lastWord = "Wellkept could not write down that you printed the page. The page is fine — "
                     + "it just will not be able to tell you when it goes out of date."
            return
        }
        lastWord = "Your Recovery Plan is on record, written for macOS \(plan.macOSVersion). "
                 + "Wellkept will say when it needs printing again."

        guard let answer else { return }
        self.answer = Self.assemble(machine: answer.timeMachine,
                                    coverage: answer.coverage,
                                    planForToday: answer.planForToday,
                                    onRecord: plan,
                                    destination: StorageManifest.backupDestination()?.lastPathComponent,
                                    agentIsOn: BackgroundPieceService.isOn,
                                    now: now)
    }

    func clearLastWord() { lastWord = nil }
}
