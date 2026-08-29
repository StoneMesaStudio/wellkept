// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  ChangesRowView.swift
//  Wellkept — App/Sections/Changes
//
//  **One of the five rows, and one thing that moved inside it.**
//
//  The same shape as `SecurityRowView` and `ReadingRow`, deliberately: topic, status, the answer,
//  then whatever was found, named, underneath. A person who has learned the Security panel has
//  learned this one.
//
//  ## ⚠️ What every change block is required to say
//
//  Four things, in this order, and none of them is optional:
//
//  1. **What changed** — the watched thing's own title, and for a privacy grant the app's name too.
//  2. **From what to what** — both values, in the words the reader printed them in.
//  3. **When** — the window, with the asleep-or-off clause where it applies, and the cause clause,
//     which is where the macOS update sentence lands when the evidence supports one.
//  4. **What it costs** — our three sentences: what the setting does, what turning it off actually
//     costs you, and why it might have changed. This is the part John asked us to do better than
//     the prior art, and it is the reason the section is worth opening twice.
//
//  ## ⛔ The button changes nothing, and its words say so
//
//  Wellkept writes no setting, ever — John, 2026-08-28. Every button here opens Apple's own pane
//  and names the pane it opens, borrowed from `ConcernView.words(for:)` so Security and Changes
//  cannot drift into two different labels for the same destination. There is no fifth verb;
//  "Open Settings" is a destination, not something the app does to the Mac.

// MARK: - One of the five rows

struct ChangesTopicRow: View {

    let topic: ChangesTopic
    let changes: [Change]
    let index: Int
    /// `true` on a first look, where "nothing changed" would be a claim rather than an answer.
    var firstLook = false
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(topic.label)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                StatusChip(status: status)
            }

            Text(headline)
                .font(.appBody)
                .foregroundStyle(firstLook ? Theme.textSecondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            // What a change in this row would mean. One sentence, on every row, every time — it is
            // what makes a row that found nothing worth having on the screen at all.
            Text(topic.explanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.top, 2)

            // ⚠️ Never behind a disclosure. A row that says something moved and hides what is an
            // alarm the person cannot examine.
            if !changes.isEmpty {
                VStack(alignment: .leading, spacing: Space.block) {
                    ForEach(changes) { change in
                        ChangeBlockView(change: change, now: now)
                    }
                }
                .padding(.top, Space.row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRow(index)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(topic.label), \(status.label)")
    }

    /// The row's own status.
    ///
    /// ⚠️ **A change is not by itself a fault.** A row where something moved back to the value that
    /// protects you, or where the macOS version went up, still reads Good — the amber comes from
    /// `Change.severity`, which needs a `Watched.safeValue` to reach `.attention` at all.
    private var status: SectionStatus {
        if firstLook { return .notChecked }
        if changes.contains(where: { $0.severity(Watched.of($0.key)) >= .attention }) {
            return .needsAttention
        }
        return .good
    }

    private var headline: String {
        if firstLook { return "Recorded for the first time — there is nothing yet to compare it with." }
        switch changes.count {
        case 0:  return "Nothing here has changed."
        case 1:  return "One thing here has changed."
        default: return "\(changes.count) things here have changed."
        }
    }
}

// MARK: - ⭐ One thing that moved

/// What changed, from what to what, when, and what it costs — with the pane that owns it.
struct ChangeBlockView: View {

    let change: Change
    var now = Date()

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    private var watched: Watched? { Watched.of(change.key) }
    private var severity: Severity { change.severity(watched) }

    var body: some View {
        let tint = palette.color(for: severity)

        VStack(alignment: .leading, spacing: Space.row) {
            // 1 — what changed. No severity tag on an ordinary change: `.information` is what most
            // of these are, and a tag on every one of them is how a tag stops meaning anything.
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(change.what)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if severity >= .attention { SeverityTag(severity: severity) }
                Spacer(minLength: 0)
            }

            // 2 — from what to what. The news, and the one line somebody's eye goes to.
            Text("\(change.from)  →  \(change.to)")
                .font(.appBody.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                // The arrow is decoration to a screen reader; the block's own label says it in
                // words, in the sentence the engine composed and the tests hold to.
                .accessibilityHidden(true)

            // 3 — when, and then how much of "why" the evidence supports.
            //
            // ⚠️ **Two lines, not one.** Joined, they read "between 22 Aug and now, and this Mac
            // was asleep or switched off for part of it — this changed while your Mac was off for
            // the macOS 26.6.2 update — it was off for about six minutes": two em-dashes and three
            // clauses in a sentence somebody reads once. Measured by eye on the 2026-08-28 shots.
            VStack(alignment: .leading, spacing: 2) {
                Text(sentence(change.window.sentence(now: now)))
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Text(sentence(change.cause.clause))
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 4 — ⭐ our three sentences.
            if let watched {
                WatchedSentences(description: watched.description)
                    .padding(.top, Space.hairline)
            }

            if let pane {
                Button(ConcernView.words(for: pane)) { pane.open() }
                    .buttonStyle(.app)
                    .controlSize(.small)
            }
        }
        .padding(Space.block)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(severity >= .attention ? 0.08 : 0.05),
                    in: Radius.shape(Radius.control))
        // The border is the second channel: under Differentiate Without Color the wash says
        // nothing, and this block has to keep reading as a finding rather than as a card.
        .overlay {
            Radius.shape(Radius.control)
                .strokeBorder(tint.opacity(differentiate ? 0.85 : 0.25),
                              lineWidth: differentiate ? Hairline.selection : Hairline.thin)
        }
        .accessibilityElement(children: .contain)
        // ⚠️ The canonical sentence, not a re-composition. The layout above spreads the same facts
        // across four lines because that reads better with eyes; a screen reader gets the one
        // sentence the engine owns and the tests hold to.
        .accessibilityLabel(change.sentence(now: now))
    }

    /// A clause the types own, stood up as a sentence of its own.
    ///
    /// ⚠️ **Only the capital and the full stop are this file's.** `Window.sentence` and
    /// `Cause.clause` are both written to sit mid-line, and both are held to their exact wording by
    /// tests — *"changed during"*, never *"the update changed it"*. Rewriting either here is how
    /// the screen and the tests come apart.
    private func sentence(_ clause: String) -> String {
        "\(clause.prefix(1).uppercased())\(clause.dropFirst())."
    }

    /// Where macOS lets a person change this back themselves. `nil` where macOS offers no pane.
    private var pane: SystemSettingsPane? {
        watched?.settingsPane.flatMap(SystemSettingsPane.init(rawValue:))
    }
}

// MARK: - ⭐ The three sentences

/// **What the setting does, what turning it off costs you, and why it might have changed.**
///
/// The prior art everybody points at is 787 one-line descriptions, 383 of them flagged
/// AI-generated, and not one attempts the second or the third. John, 2026-08-28: *"let's show him
/// up and do it better"*. This view is where "better" is actually visible — three labelled
/// sentences, on every change, written by us for the few dozen settings Wellkept already reads.
///
/// Stacked rather than in a grid. Adaptive columns would put three paragraphs side by side in
/// 210-point gutters at 100% text, which is a specification sheet; these are sentences a person
/// reads in order.
struct WatchedSentences: View {

    let description: Watched.Description

    private static let labels = ["What it does",
                                 "What turning it off costs you",
                                 "Why it might have changed"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            ForEach(Array(zip(Self.labels, description.sentences)), id: \.0) { label, sentence in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sentence)
                        .font(.appCallout)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        // Selectable, so a sentence can be pasted into an email without retyping.
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A single caveat line, with the one button that can lift it

/// **One line, one icon, one button** — the shape `PermissionNoticeLine` already uses on every
/// section face, borrowed rather than reinvented so the two read as the same kind of statement.
///
/// The button sits **under** the sentence rather than beside it. Beside it, the button claims a
/// column and the sentence wraps into a ribbon three words wide — measured on the Security face,
/// 2026-08-27, not guessed.
struct ChangesNoticeLine: View {

    let symbol: String
    let text: String
    var severity: Severity = .attention
    var buttonTitle: String?
    var action: (() -> Void)?

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.row) {
            Image(systemName: symbol)
                .font(.appCaption)
                .foregroundStyle(palette.color(for: severity))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.row) {
                Text(text)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let buttonTitle, let action {
                    // ⚠️ NOT `.buttonStyle(.link)`. That draws in the system accent — Apple's blue,
                    // since `AccentColor` ships empty — which would be the only blue in the app.
                    Button(buttonTitle) { action() }
                        .font(.appCallout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
