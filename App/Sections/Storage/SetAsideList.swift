// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  SetAsideList.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **The quarantine, on the screen it belongs to.**
//
//  It was parked in its own window and in Settings because Storage did not exist: shipping a
//  quarantine with no page listing it would have meant moving files out of somebody's home folder
//  with nowhere to see them. Storage exists now, so this is where it lives — the last of the five
//  rows, because it is the only one where room actually comes back, and it comes back at the second
//  press.
//
//  ## The order, and why it is not worst-first
//
//  Every other list in this app is worst first. This one is **oldest first, with anything past
//  thirty days risen to the top and marked ready to remove** — `Expiry.sortedForTheScreen`. There
//  is no "worst" in a quarantine: a file here is not a problem, it is a decision somebody deferred,
//  and the only thing that ranks them is how long they have been waiting.
//
//  ## ⚠️ Nothing here is new
//
//  `QuarantineSummaryRow`, `QuarantineItemRow` and `EmptyQuarantineButton` are the views the
//  quarantine window already used, reused verbatim. They were written to be dropped into a section
//  — see the header of `QuarantinePage` — and re-writing them here would be the fastest way to end
//  up with two screens describing one quarantine differently.

struct SetAsideList: View {

    let model: QuarantineModel
    var now: Date = Date()

    /// The expiry setting, read live rather than snapshotted, so changing it in Settings while this
    /// screen is open changes what every row says about what happens next.
    ///
    /// ⚠️ **Absent means manual.** A missing key must never read as automatic removal.
    @AppStorage(StorageManifest.Keys.quarantineExpiry) private var expiryRaw = ExpiryMode.manual.rawValue

    private var mode: ExpiryMode { ExpiryMode(rawValue: expiryRaw) ?? .manual }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {

            Text(QuarantineText.whatThisIs)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // ⚠️ Hidden when there is nothing set aside: the empty state below already says so, and
            // a screen never says the same thing twice. `isEmpty` is false when the ledger could
            // not be read, so the trouble sentence still gets its row.
            if let summary = model.summary, !summary.isEmpty {
                QuarantineSummaryRow(summary: summary,
                                     now: now,
                                     onEmpty: { Task { await model.empty() } })
            }

            list

            whatHappensAtThirtyDays
        }
    }

    @ViewBuilder private var list: some View {
        if model.summary?.trouble != nil {
            // The trouble sentence is already on the summary row above. What belongs here is why
            // the list is empty — never a zero, which is the one number that would mean somebody's
            // files are unaccounted for.
            InlineEmptyNote(symbol: "exclamationmark.triangle",
                            text: "Wellkept will not list items it could not read the record of. "
                                + "Nothing has been deleted.")
        } else if !model.hasRead {
            InlineEmptyNote(symbol: "clock", text: "Reading what is set aside…")
        } else if model.records.isEmpty {
            InlineEmptyNote(symbol: "tray", text: QuarantineText.nothingIsSetAsideWhy)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.records.enumerated()), id: \.element.id) { index, record in
                    QuarantineItemRow(record: record,
                                      index: index,
                                      mode: mode,
                                      home: model.home,
                                      isMissing: model.missing.contains(record.id),
                                      trouble: model.rowWord[record.id],
                                      busy: model.isWorking,
                                      now: now,
                                      onRestore: { Task { await model.restore(record) } },
                                      onDelete: { Task { await model.delete(record) } })
                }
            }
        }
    }

    /// What thirty days actually does, in the mode that is set, with the way to change it.
    ///
    /// At the foot rather than the top because it is the answer to a question the list raises —
    /// every row says "ready to remove in 27 days", and this is what that means.
    private var whatHappensAtThirtyDays: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("After \(Expiry.days) days")
                .font(.appHeadline)
            Text(mode.explanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            OpenSettingsButton {
                Text("Change this in Settings")
                    .font(.appCallout)
                    .underline()
            }
            .accessibilityAddTraits(.isButton)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}
