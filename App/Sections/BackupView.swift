// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  BackupView.swift
//  Wellkept — App/Sections
//
//  **"Is my stuff safe?"** — what Apple's own backup is doing, what is in no backup at all, what
//  Wellkept could do about it, and the one page to print for the day the Mac will not start.
//
//  ## ⭐ It leads with Time Machine, and that is the whole design of this screen
//
//  **Time Machine's entire state reads with zero permissions, in 52 milliseconds**: on or off, the
//  destination, whether the drive is here, the last success, the days since, the error and its
//  cause. It is the only thing in this section that helps somebody today, so it is first, and
//  everything Wellkept might one day do about it comes after.
//
//  ⚠️ **"Switched off" is worded differently from "failing", and the difference is the point.** On
//  the machine this was built on, the honest headline is *"Your backup is switched off. The last
//  one finished on 25 August."* The earlier draft of this section said "Time Machine cannot reach
//  the drive", which was misleading: the destination is configured, the drive is simply in a
//  drawer, and automatic backups are off. **"Your backup is off and nobody told you" is both truer
//  and more useful than "your backup is broken."**
//
//  ## The shape, top to bottom
//
//  1. The heading, its status, and when it last ran.
//  2. The sentence and the one button, plus what it is doing while it runs.
//  3. ⭐ **The section's headline** — Time Machine's own, from `BackupReport.summary` — and the
//     lines under it, from `linesUnderTheHeadline`, in that order and never rewritten here.
//  4. **The four rows, in fixed order and never sorted**: Time Machine · What is not covered ·
//     Wellkept's own backup · Your Recovery Plan.
//  5. **Options** — the disaster table, every row's detail, and what this check actually did.
//
//  ## ⛔ Four things this screen may never do
//
//  - **Switch Time Machine on, off, or start a backup.** Every button here opens Apple's own pane.
//  - **Promise to rebuild the Mac.** A whole-Mac copy is impossible unprivileged — 320,465 of the
//    361,714 files outside the home folder are root-owned — and Migration Assistant accepting a
//    data-only volume is unverified, with Apple's own string arguing against it. The promise is
//    "all your files". `RehearsalGateGuardTests` fails the build on the other one.
//  - **Offer Wellkept's own backup.** Not until somebody has erased a drive and restored from it on
//    real hardware. The row still draws and still says why, in `RehearsalGate`'s own words.
//  - **Count the cloud as missing.** 72.2 GB of one measured Mac's files are in the cloud and not
//    on the disk. That is an arrangement, not a gap, and only `Coverage.isGap` may say otherwise.
//
//  ## ⚠️ This section does not run on launch
//
//  The Time Machine half would be free. The coverage half is a bounded walk, and a section that
//  spent it on every launch would make the app feel slow on a screen where nothing had changed. So
//  Backup runs on a press, like the other five.

struct BackupView: View {

    @Environment(AppState.self) private var app

    private var model: BackupModel { app.backup }

    /// What is drawn. In demo mode this is an invented Mac and **nothing has been read from this
    /// one** — the promise the bar across the top of the window makes on every screen.
    private var answer: BackupAnswer? {
        app.demoMode ? DemoData.backup(app.demoMachine) : model.answer
    }

    private var record: CheckRecord? { answer?.report.record ?? app.records[.backup] }

    /// Demo mode is a picture of a Mac, not this Mac, so nothing on it may start a real check,
    /// open a real settings pane, or print a page about a machine nobody is looking at.
    private var live: Bool { !app.demoMode }

    private var checking: Bool { live && model.isChecking }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                SectionHeader(section: .backup, record: record)

                // ⚠️ Time Machine's state needs nothing granted, and this line does not claim
                // otherwise. What the grant actually costs here is what a Wellkept backup would
                // contain — see `FullDiskAccess.shortfall(for:)`. It draws nothing once the grant
                // is on.
                PermissionNoticeLine(section: .backup)

                checkControl

                if let answer, !checking {
                    headline(answer.report)
                    if let word = model.lastWord, live { outcome(word) }
                    rows(answer)
                    options(answer)
                } else if !checking {
                    notCheckedYet
                }
            }
            .padding(Space.page)
            .readableColumn()
        }
        .fillsPane()
    }

    // MARK: The sentence and the button

    private var checkControl: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text(SectionID.backup.sentence)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.gutter) {
                Button(SectionID.backup.verb) {
                    Task { await app.runBackupCheck() }
                }
                .buttonStyle(.appProminent)
                .controlSize(.large)
                .disabled(!live || model.isChecking)

                if checking, let stage = model.stage {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stage.sentence)
                            .font(.appCallout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Step \(stage.step) of \(BackupModel.Stage.count)")
                            .font(.appCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .appAnimation(Motion.chrome, value: model.stage)

            scope
        }
    }

    /// **What this section reads, and what it will not touch**, on the face, before any result.
    ///
    /// Said here because this is the one section in the app whose subject is a drive, and a person
    /// looking at a screen about backups has every reason to wonder whether it is about to write to
    /// one. The answer is on the screen rather than in a document.
    private var scope: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("Wellkept reads what Time Machine says about itself — whether it is on, which "
                 + "drive it uses, and when it last finished — and then looks at what is on this "
                 + "Mac and nowhere else. It never switches Time Machine on or off, never starts a "
                 + "backup, and never erases, formats or renames a drive.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Said once, on the screen it is true of — and it is the sentence that explains why
            // this screen is blank when the app opens.
            Text("None of this happens on its own. Wellkept looks when you press the button.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: ⭐ The headline

    /// **The section's answer, in one line, and everything that qualifies it underneath.**
    ///
    /// Both come out of `BackupReport` — `summary` is Time Machine's own headline and
    /// `linesUnderTheHeadline` is the ordered list of caveats, including the gate's sentence. They
    /// are never re-composed here: welding them together on the screen is exactly how the face and
    /// the report come to say different things about the same Mac.
    private func headline(_ report: BackupReport) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(report.summary)
                .font(.appTitle3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isSummaryElement)

            ForEach(Array(report.linesUnderTheHeadline.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// What the last press did, in that action's own words, where the person is already looking.
    private func outcome(_ word: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
            Text(word)
                .font(.appCallout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: Space.row)
            Button("Dismiss") { model.clearLastWord() }
                .buttonStyle(.app)
                .controlSize(.small)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: Radius.control)
        .accessibilityElement(children: .combine)
    }

    // MARK: The four rows

    /// ⚠️ `report.rows` is already in `BackupTopic` order, put there by `BackupReport.init`. It is
    /// never sorted here and never filtered.
    private func rows(_ answer: BackupAnswer) -> some View {
        VStack(alignment: .leading, spacing: Space.gutter) {
            ForEach(answer.report.rows) { row in
                BackupTopicCard(row: row,
                                onRemedy: { press($0, on: row, answer: answer) },
                                canPress: live) {
                    content(row)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ row: BackupRow) -> some View {
        if let why = row.unreadable {
            Text(why.sentence(about: row.topic.label))
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !row.coverage.isEmpty {
            CoverageList(coverage: row.coverage)
        } else if row.topic == .wellkeptBackup {
            // ⭐ The one switch in the app that lets part of Wellkept keep running after the window
            // closes. It sits on this row rather than in Settings because it is a property of the
            // backup, not of the app's looks — and because the sentence explaining what it costs to
            // leave it off has to be beside the offer.
            BackgroundPieceRow(live: live)
        }
    }

    // MARK: What a button does

    /// **Two kinds of button, and neither of them changes a setting.**
    ///
    /// A remedy with a pane opens Apple's own settings. The Recovery Plan's opens the page — the
    /// one button in this section that produces something, and what it produces is paper.
    @MainActor private func press(_ remedy: Remedy, on row: BackupRow, answer: BackupAnswer) {
        guard live else { return }
        if let raw = remedy.settingsPane, let pane = SystemSettingsPane(rawValue: raw) {
            pane.open()
            return
        }
        guard row.topic == .recoveryPlan else { return }
        showTheRecoveryPlan(answer)
    }

    /// ⚠️ Through the window's **one** sheet slot. Two `.sheet` modifiers on one view make SwiftUI
    /// silently drop one, with no warning and no crash.
    @MainActor private func showTheRecoveryPlan(_ answer: BackupAnswer) {
        app.sheet = SheetRoute(id: "recovery-plan") {
            RecoveryPlanView(plan: answer.planForToday,
                             onRecord: answer.report.recoveryPlan) { printed in
                model.recordThePlanWasPrinted(printed)
            }
        }
    }

    // MARK: Options

    /// One disclosure, and it says what is behind it. It sits after the rows: everything in it is a
    /// more exact version of something above.
    private func options(_ answer: BackupAnswer) -> some View {
        LabelledDisclosure("Options", isExpanded: app.optionsOpen(.backup)) {
            VStack(alignment: .leading, spacing: Space.section) {
                DisasterTable()

                ForEach(answer.report.rows) { row in
                    if !row.details.isEmpty {
                        VStack(alignment: .leading, spacing: Space.row) {
                            Text(row.topic.label)
                                .font(.appHeadline)
                            DetailPairGrid(pairs: row.details)
                        }
                    }
                }

                thisCheck(answer)
            }
            .padding(.top, Space.row)
        }
    }

    /// The section's own audit trail: when it ran, what it read, what it could not see, and what it
    /// changed.
    private func thisCheck(_ answer: BackupAnswer) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("This check")
                .font(.appHeadline)

            DetailPairGrid(pairs: auditPairs(answer))

            ForEach(answer.report.unreadableTopics, id: \.topic) { item in
                Text(item.why.sentence(about: item.topic.label))
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func auditPairs(_ answer: BackupAnswer) -> [DetailPair] {
        let report = answer.report
        var pairs = [
            DetailPair("Ran at", ShortDate.stamp(report.ranAt)),
            DetailPair("Rows read", "\(report.rows.count) of \(BackupTopic.allCases.count)"),
            DetailPair("Things in no backup at all", "\(report.gaps.count)"),
            // ⛔ Recorded on the screen, not only in a comment. It is the one call whose obvious
            // use would have mounted somebody's drive to answer a question about a drive.
            DetailPair("How the last backup date was found",
                       "From Time Machine's own settings. Asking macOS for the latest backup would "
                     + "make it try to mount the drive."),
            DetailPair("Saw everything it looked for",
                       report.complete
                           ? "Yes"
                           : "No — something on this Mac refused to be read, and the lines above say which."),
            DetailPair("What this check changed",
                       "Nothing. It read settings and file dates; it wrote to no drive and started "
                     + "no backup."),
            DetailPair("What Wellkept never does to a drive", Destination.whatWellkeptNeverDoes),
            DetailPair("Getting a Mac working again", BackupRows.whatWellkeptIsNotPartOf),
        ]

        if let coverage = answer.coverage, !coverage.providers.isEmpty {
            // ⚠️ The provider, never the folder name. `~/Library/CloudStorage/GoogleDrive-…`
            // carries the account's email address one step from a screen.
            pairs.append(DetailPair("Other sync services mounted here",
                                    coverage.providers.joined(separator: ", ")))
        }
        if let line = answer.timeMachine.snapshotLine {
            pairs.append(DetailPair("Local snapshots", line))
        }
        return pairs
    }

    // MARK: Nothing checked yet

    /// ⚠️ **The ordinary state, not an edge case.** Backup never runs by itself, so this is what
    /// the screen looks like on every launch until somebody presses the button.
    private var notCheckedYet: some View {
        EmptyStateView(
            symbol: "externaldrive.badge.timemachine",
            title: "Nothing has been checked yet",
            message: "Press \(SectionID.backup.verb) and Wellkept will read what Time Machine is "
                   + "doing, work out what is on this Mac and nowhere else, and offer you one page "
                   + "to print for the day this Mac will not start. It changes nothing.",
            greedy: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
