// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  ChangesView.swift
//  Wellkept — App/Sections
//
//  **"What changed, and who changed it?"** — this Mac's settings against the last time Wellkept
//  looked.
//
//  ## The shape, top to bottom
//
//  1. The heading, its status, and when it last ran.
//  2. The sentence and the one button, plus what it is doing while it runs.
//  3. ⭐ **What this section actually compares**, in a sentence, on the face — not buried in
//     Options. Changes watches the few dozen things Wellkept already understands, and a screen
//     that let somebody believe it watched every preference on the Mac would be claiming a look it
//     never took.
//  4. The section's own summary line, from `ChangesReport.summary`, never rewritten here.
//  5. The one Full Disk Access line, where privacy permissions moved while we could not see them.
//  6. **The five rows, in fixed order and never sorted**: Protections · What can reach this Mac ·
//     What starts on its own · Who can watch you · macOS itself. Every row every time.
//  7. **The undescribed count — one line, never rows.**
//  8. **Options** — what this check actually did, and the whole list of what is watched.
//
//  ## ⛔ Three things this screen may never do
//
//  - **Change a setting.** John, 2026-08-28: Wellkept writes no setting, ever, not even the default
//    browser. Every button here opens Apple's own pane and says which one. There is no fifth verb.
//  - **Name an app as the cause.** Nothing an unprivileged app can read records which process wrote
//    a setting. `Cause` has no case for it and `ChangesCauseGuardTests` fails the build on one.
//  - **List what it cannot explain.** A difference nothing describes is one number in one sentence.
//    41 rows of raw preference keys is what makes a journal nobody opens twice.
//
//  ## ⚠️ This section does not run on launch, and nothing here may start it
//
//  The read is Security's read — about eight seconds. The *snapshot* is the cheap half and belongs
//  on every launch; the comparison happens on a press. See `ChangesModel`.

struct ChangesView: View {

    @Environment(AppState.self) private var app

    private var model: ChangesModel { app.changes }

    /// What is drawn. In demo mode this is an invented Mac and **nothing has been read from this
    /// one** — the promise the bar across the top of the window makes on every screen.
    private var report: ChangesReport? {
        app.demoMode ? DemoData.changes(app.demoMachine) : model.report
    }

    private var record: CheckRecord? { report?.record ?? app.records[.changes] }

    /// Demo mode is a picture of a Mac, not this Mac, so nothing on it may start a real check.
    private var live: Bool { !app.demoMode }

    private var checking: Bool { live && model.isChecking }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                SectionHeader(section: .changes, record: record)

                // Without Full Disk Access some of what this compares is hidden. The line draws
                // nothing once the grant is on.
                PermissionNoticeLine(section: .changes)

                checkControl

                if let report, !checking {
                    summary(report)
                    if report.privacyChangedButUnreadable { privacyWentDark }
                    refusals(report)
                    rows(report)
                    undescribed(report)
                    options(report)
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
            Text(SectionID.changes.sentence)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.gutter) {
                Button(SectionID.changes.verb) {
                    Task { await app.runChangesCheck() }
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
                        Text("Step \(stage.step) of \(ChangesModel.Stage.count)")
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

    /// ⭐ **What this section compares, on the face, before any result.**
    ///
    /// Not in Options and not in a footnote. Everything below this line is about a few dozen
    /// settings; a person who assumed it was all of them would draw the wrong conclusion from a
    /// quiet screen, and that conclusion would be our fault rather than theirs.
    private var scope: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("Wellkept compares the things it already understands: this Mac's protections, "
                 + "what can reach it over a network, what starts on its own, which apps hold the "
                 + "camera, the microphone and the screen, and the version of macOS. "
                 + "It does not compare every preference on this Mac. "
                 + "Options, below, lists all \(Watched.all.count) of them by name.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Said once, on the screen it is true of — and it is the sentence that explains why
            // this screen is blank when the app opens.
            Text("Wellkept reads this only when you press the button. It records what your "
                 + "settings are, compares them with the last time, and changes nothing — not one "
                 + "setting on this Mac, ever. Where something moved, the row offers to open "
                 + "Apple's own settings so you can decide.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The summary sentence

    /// **The section's answer, in one line.**
    ///
    /// From `ChangesReport.summary`, which is where the count, the date, the undescribed number and
    /// the asleep-or-off caveat are welded together. Rewriting it here is how the two come apart.
    private func summary(_ report: ChangesReport) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(report.summary)
                .font(.appTitle3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isSummaryElement)

            // ⚠️ The first look is not an all-clear, and the chip above already says "Not checked".
            // This is the sentence that stops it reading as one.
            if report.isFirstLook {
                Text("Nothing here is a verdict yet. A record of what your settings are cannot be "
                     + "back-filled, so Wellkept starts keeping one now and can answer this "
                     + "question from the next time you open it.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: John's answer 4 — said once, never per permission

    /// **The one Full Disk Access line**, where the privacy permissions changed and we could not
    /// see what.
    ///
    /// John, 2026-08-28: show it, once, as a single line with the button that grants access, and
    /// never repeated per permission. Saying nothing would be reporting zero because we could not
    /// look, which this app has banned everywhere else.
    private var privacyWentDark: some View {
        ChangesNoticeLine(symbol: "eye.slash",
                          text: "Which apps can use your camera, your microphone and your screen "
                              + "changed between these two looks, and Wellkept could not see what "
                              + "moved. macOS keeps that list private without Full Disk Access.",
                          severity: .attention,
                          buttonTitle: "Open System Settings…") {
            PermissionCenter.shared.openFullDiskAccessSettings()
        }
    }

    /// Anything else this run was refused, one line per row rather than one per item.
    private func refusals(_ report: ChangesReport) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            ForEach(report.unreadable) { item in
                Text(item.why.sentence(about: Watched.of(item.key)?.title ?? item.key.topic.label))
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The five rows

    /// ⚠️ **`ChangesTopic.allCases` is the order, and it is never sorted and never filtered.** A row
    /// that found nothing still draws: it is how the screen says what it looked at, and a panel
    /// whose rows come and go with the findings is a panel nobody can learn.
    private func rows(_ report: ChangesReport) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(ChangesTopic.allCases.enumerated()), id: \.element) { index, topic in
                ChangesTopicRow(topic: topic,
                                changes: report.changes(in: topic),
                                index: index,
                                firstLook: report.isFirstLook,
                                now: report.ranAt)
            }
        }
    }

    // MARK: ⭐ The count, and never the rows

    /// **One line with a number.**
    ///
    /// Wellkept records every readable setting and describes a few dozen of them, so a run will
    /// often find differences it has nothing to say about. That number is worth stating — it is
    /// the honest shape of what was looked at — and listing it is not: a screen of raw preference
    /// keys nobody can explain is what makes a journal that gets opened once.
    @ViewBuilder private func undescribed(_ report: ChangesReport) -> some View {
        if report.undescribed > 0 {
            Text(report.undescribed == 1
                 ? "One other value on this Mac also changed. Wellkept recorded it and has no "
                   + "description for it, so it is not listed here."
                 : "\(report.undescribed) other values on this Mac also changed. Wellkept recorded "
                   + "them and has no description for them, so they are not listed here.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Options

    /// One disclosure, and it says what is behind it. Its open state lives in `AppState`, so a ⌘+
    /// press does not collapse a panel somebody had just opened.
    private func options(_ report: ChangesReport) -> some View {
        LabelledDisclosure("Options", isExpanded: app.optionsOpen(.changes)) {
            VStack(alignment: .leading, spacing: Space.section) {
                thisCheck(report)
                WhatIsWatchedList()
            }
            .padding(.top, Space.row)
        }
    }

    /// The section's own audit trail: when it ran, what it compared against, whether it saw
    /// everything, and what it changed.
    private func thisCheck(_ report: ChangesReport) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("This check")
                .font(.appHeadline)

            DetailPairGrid(pairs: auditPairs(report))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func auditPairs(_ report: ChangesReport) -> [DetailPair] {
        [
            DetailPair("Ran at", ShortDate.stamp(report.ranAt)),
            DetailPair("Compared against",
                       report.previous.map { ShortDate.stamp($0) }
                           ?? "Nothing yet — this is the first record on this Mac."),
            DetailPair("Things watched", "\(Watched.all.count)"),
            DetailPair("Things that changed", "\(report.changes.count)"),
            DetailPair("Changed and not described", "\(report.undescribed)"),
            DetailPair("Was this Mac asleep or off in between",
                       report.macWasOffOrAsleep
                           ? "Yes, for part of it."
                           : (report.outageUnreadable == nil
                              ? "No."
                              : "Could not be read on this account.")),
            DetailPair("Saw everything it looked for",
                       report.complete
                           ? "Yes"
                           : "No — something on this Mac refused to be read, and the lines above say which."),
            DetailPair("What it changed",
                       "Nothing. Wellkept never writes a setting; the buttons open Apple's own settings."),
        ]
    }

    // MARK: Nothing checked yet

    /// ⚠️ **The ordinary state, not an edge case.** Changes never runs by itself, so this is what
    /// the screen looks like on every launch until somebody presses the button.
    private var notCheckedYet: some View {
        EmptyStateView(
            symbol: "clock.arrow.circlepath",
            title: "Nothing has been compared yet",
            message: "Press \(SectionID.changes.verb) and Wellkept will read the settings it "
                   + "watches, write down what they are, and tell you what is different from the "
                   + "last time. It changes nothing.",
            greedy: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
