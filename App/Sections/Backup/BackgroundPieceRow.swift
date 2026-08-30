// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  BackgroundPieceRow.swift
//  Wellkept — App/Sections/Backup
//
//  ⭐ **The one switch in this app that lets a piece of Wellkept keep running after the window
//  closes** — the answer, 2026-08-29.
//
//  ## Why it is switchable today, when the copying is not
//
//  This looks like a contradiction and it is the resolution of one. `RehearsalGate` will not let
//  the background piece copy anything until somebody has watched it read mail with the window shut
//  — and **the only way to get that evidence is to run it**. So registering is allowed, because
//  registering moves no bytes: the agent starts, probes what it can see, writes down the answer, and
//  copies nothing. That record is what a person reads before the proof is recorded.
//
//  ⚠️ Nothing the agent writes can open the gate. A perfect verdict in `AgentRecord` still leaves
//  `RehearsalGate.agentIsProved` false; a human has to look at it and write the proof down.
//
//  ## ⭐ Of its three jobs, two write to a drive and one does not
//
//  *Automatic means looking. Manual means touching.* Noticing that a backup has gone quiet is
//  looking, so it happens today whatever the gate says. Backing up hourly and backing up on connect
//  are touching, and they wait. That is not a workaround — it is the house rule applied to three
//  jobs that turn out not to be the same kind of thing.
//
//  ## ⚠️ `whenItIsOff` is not optional decoration
//
//  It appears beside the offer, every time. An app that describes its optional background piece as
//  though the app were crippled without it has made the switch compulsory in everything but name.

struct BackgroundPieceRow: View {

    /// The switch as something a view can hold, so this face and Settings cannot show two different
    /// answers about one login item.
    @State private var model = BackgroundPieceModel()

    /// Demo mode is a picture of a Mac, not this Mac. Registering a real login item from it would
    /// be the one thing on that screen that reached the machine.
    var live = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Toggle(BackgroundPiece.switchTitle, isOn: Binding(
                get: { model.isOn },
                set: { model.set($0) }))
                .font(.appHeadline)
                .disabled(!live)

            Text(BackgroundPiece.switchExplanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // ⚠️ Said beside the offer, always. See the header.
            Text(BackgroundPiece.whenItIsOff)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // ⛔ What it will and will not do while the gate is shut. The gate's own sentence, not a
            // paraphrase written on a screen.
            if let why = model.whyItWillNotCopyYet {
                WithheldNote(sentence: why)
                Text(jobsItStillDoes)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.needsApproval {
                Text(model.statusSentence)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let outcome = model.lastOutcome {
                Text(outcome.sentence)
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Open Login Items…") { model.showTheirLoginItems() }
                .buttonStyle(.app)
                .controlSize(.small)
                .disabled(!live)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The status is read from macOS rather than stored, so it can go stale the moment somebody
        // switches the row off in System Settings — which is the thing this design promises they
        // can do. Re-read whenever the row is drawn.
        .onAppear { if live { model.refresh() } }
    }

    /// ⭐ The half that works today, named rather than left as an absence.
    private var jobsItStillDoes: String {
        let looking = BackgroundPiece.Job.allCases.filter { !$0.copiesFiles }
        let names = looking.map(\.label).joined(separator: ", ")
        return "It will still do this much, because looking is not touching: \(names)."
    }
}
