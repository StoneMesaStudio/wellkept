// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  BackupRowView.swift
//  Wellkept — App/Sections/Backup
//
//  **One of the four rows, and the coverage list underneath two of them.**
//
//  ## The head every row wears
//
//  What it is · how it stands · why it says so. The same three facts in the same three places on all
//  four rows, so a person learns the shape once. `BackupRow` already decided the severity and
//  clamped it per topic; nothing here may soften or sharpen a verdict on the way to the screen.
//
//  ## ⭐ The one thing this file does that no other row view does: it draws a refusal that is ours
//
//  `withheld` is set when a row exists and is **not being offered**, because nobody has erased a
//  drive and restored from it yet. It is not a permission we were refused and it is not a failure —
//  it is this app declining to offer something it has not proved. So it is drawn in place of the
//  button, in `RehearsalGate`'s own words, and the row keeps everything else it had.
//
//  ⚠️ **Never as an error, and never in red.** A person seeing an alarm here would conclude
//  something is wrong with their Mac; what is actually true is that something is unfinished in
//  ours.

// MARK: - The card

/// The heading, the three facts, the refusal or the button, and whatever the topic wants underneath.
struct BackupTopicCard<Content: View>: View {

    let row: BackupRow
    /// What the row's button does. `nil` draws no button even where the row carries a remedy.
    var onRemedy: ((Remedy) -> Void)?
    /// ⚠️ **Drawn and greyed rather than removed, in demo mode.** Demo mode is a picture of a Mac,
    /// not this Mac, so nothing on it may open a settings pane or print a page about a machine
    /// nobody is looking at — but a control that comes and goes with the mode is a control nobody
    /// can judge from the picture.
    var canPress = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {

            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                Text(row.topic.label)
                    .font(.appTitle3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                StatusChip(status: row.status)
            }

            VStack(alignment: .leading, spacing: Space.hairline) {
                HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                    SeverityTag(severity: row.severity)
                    Text(row.headline)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isSummaryElement)
                }

                // The row's own plain sentence, from `WellkeptCore`, so no two screens can describe
                // the same row differently.
                Text(row.topic.explanation)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let reason = row.reason {
                    Text(reason)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let measure = row.measure {
                    Text(measure)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content

            // ⛔ The refusal and the button are mutually exclusive, and the refusal wins. A row that
            // is not being offered may not also carry the offer.
            if let withheld = row.withheld {
                WithheldNote(sentence: withheld)
            } else if let remedy = row.remedy, let onRemedy {
                Button(remedy.title) { onRemedy(remedy) }
                    .buttonStyle(.app)
                    .controlSize(.regular)
                    .disabled(!canPress)
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

// MARK: - ⛔ The gate, on the screen

/// **The sentence that stands where the button would be.**
///
/// John's condition, 2026-08-29: the gate is a shipped, visible thing in the code, not a note in a
/// document. This is the visible half. It says what has not happened — nobody has erased a drive and
/// restored from it — rather than that a feature is unavailable, because those two sentences send a
/// person to completely different conclusions about whether the app is working.
struct WithheldNote: View {
    let sentence: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.row) {
            Image(systemName: "lock")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(sentence)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Achromatic. Not a warning colour, because this is not a warning about the person's Mac.
        .background(Theme.stripe, in: Radius.shape(Radius.control))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - What is and is not covered

/// **The coverage list: what is in a backup, what is not, and where each thing actually lives.**
///
/// ⚠️ **A row here is not an accusation.** 72.2 GB of this Mac's files are in the cloud and not on
/// the disk, and a tool that counted those as "missing from your backup" would open with a 72 GB
/// alarm about an arrangement working exactly as designed. `Coverage.isGap` is the only thing that
/// may say something is missing, and it is `true` only for something that lives **on this Mac and
/// nowhere else**. Everything else prints its own reason for not being a gap.
struct CoverageList: View {
    let coverage: [Coverage]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(coverage.enumerated()), id: \.element.id) { index, item in
                CoverageRow(item: item, index: index)
            }
        }
    }
}

/// One thing, where it lives, and whether it is in a backup.
struct CoverageRow: View {
    let item: Coverage
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: Space.gutter) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                    // Only a real gap is tagged. Tagging everything is how a tag stops meaning
                    // anything — and here it would also be untrue.
                    if item.isGap { SeverityTag(severity: .attention) }
                    Text(item.name)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Always present. A row with no reason is an accusation.
                Text(item.why)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // ⚠️ Two facts, not one: where it lives, and whether it is in a backup. They come
                // apart — something can be on this Mac only and still be backed up, and something
                // in iCloud can be in no backup and not be a gap.
                Text("\(item.lives.label) · \(item.included.label)")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.row)

            if let bytes = item.bytes {
                Figure(bytes.text, size: 15, weight: .semibold)
                    .accessibilityHidden(true)
            }
        }
        .appRow(index)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - What no backup covers

/// ⭐ **The five disasters, and what actually covers each one.**
///
/// This is the section's argument, and two rows are why it exists. **Ransomware is the one the
/// cloud makes worse** — sync copies the encryption to every device within minutes and calls it
/// success — and **nothing covers a bad macOS update**, because on Apple silicon Recovery downloads
/// its own installer, so a restore does not put the old macOS back.
///
/// It sits behind **Options** rather than on the face: it is the same five answers every time on
/// every Mac, and a permanent block of them above the rows would be a paragraph that never changes
/// sitting on top of the ones that do.
struct DisasterTable: View {

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text("What each kind of disaster is actually covered by")
                .font(.appHeadline)

            Text(Disaster.syncIsNotABackup)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(Disaster.table.enumerated()), id: \.element.kind) { index, disaster in
                    DisasterRow(disaster: disaster, index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DisasterRow: View {
    let disaster: Disaster
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                // ⚠️ `.onlyIf` does not count as covered, and a guard test fails the build if it
                // ever starts to. "Only if the drive was unplugged" is not protection somebody has.
                if !disaster.isCovered { SeverityTag(severity: .attention) }
                Text(disaster.kind.label)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(disaster.whatIsLost)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            DetailPairGrid(pairs: disaster.detailPairs)
        }
        .appRow(index)
    }
}
