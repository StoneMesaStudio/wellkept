// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  JunkBatch.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **Ceremony one: tick a batch, one press, done, never asked again.**
//
//  John, 2026-08-28: *"Junk: tick a batch, one press, done, and the row afterwards says '13 GB set
//  aside'."*
//
//  ## Why this one gets ticks and nothing else on the screen does
//
//  There is nothing to decide. Every category here names the program that writes the thing again:
//  Xcode rewrites its build folder on the next build, a browser re-fetches a cached page, a
//  half-finished download starts over. Being wrong costs a rebuild or a page load. Asking somebody
//  to consider thirteen gigabytes of `DerivedData` one folder at a time would be asking them to
//  spend an afternoon on a decision that has one answer.
//
//  That is exactly not true of a person's own files, which is why they get the other ceremony and
//  why there is no code path from this view to one of them: `JunkTickRow` refuses to draw a box for
//  anything whose `Item.mayBePreSelected` is false, and `StorageModel.setTicked` refuses to record
//  one. Both would have to be defeated, and `StorageRow.preSelected` would still return `[]`.
//
//  ## ⚠️ What the press does not do
//
//  It moves files inside the disk. It returns **no room at all** — measured, 391 MB across 100,000
//  files moved free space by −8 KiB. `SetAsideNotice` says so above the button, in John's words,
//  and the sentence afterwards is `Quarantine.Report.sentence`, which says it again.

struct JunkBatch: View {

    let row: StorageRow
    /// The classifier's own notes, so a thing it declined to tick can say why on its row.
    let judgements: [JunkClassifier.Classified]
    let model: StorageModel
    /// Whether this Mac is short of room today. Drives John's "quarantine is the wrong button" line.
    let diskIsAlreadyFull: Bool

    /// ⭐ The classifier's own answer about what arrives ticked, read from the judgements rather
    /// than re-derived. `JunkClassifier.arrivingTicked` has already intersected what it decided
    /// with what `Item` permits, so the annoyance filter's decision survives all the way here.
    private var arriving: Set<String> {
        Set(JunkClassifier.arrivingTicked(judgements).map(\.id))
    }

    private var offered: [Item] { row.items.filter(\.mayBePreSelected) }
    private var reported: [Item] { row.items.filter { !$0.mayBePreSelected } }
    private var ticked: [Item] { model.tickedItems(in: row, arriving: arriving) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {

            if offered.isEmpty, reported.isEmpty {
                InlineEmptyNote(symbol: "sparkles", text: JunkSweep.Says.nothingFound)
            }

            if !offered.isEmpty {
                header
                VStack(spacing: 0) {
                    ForEach(Array(offered.enumerated()), id: \.element.id) { index, item in
                        JunkTickRow(item: item,
                                    index: index,
                                    home: model.home,
                                    notTickedBecause: note(for: item),
                                    trouble: model.rowWord[item.path],
                                    isTicked: model.isTicked(item, arrivesTicked: arriving.contains(item.id)),
                                    busy: model.isWorking,
                                    onToggle: { model.setTicked(item, $0) })
                    }
                }
                press
            }

            if !reported.isEmpty { reportedOnly }
        }
    }

    // MARK: The head

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                Text(StorageWords.batchHeading)
                    .font(.appHeadline)
                Spacer(minLength: Space.row)
                // Both directions, always, rather than one button whose word changes underneath the
                // pointer. A control that means the opposite of what it did a second ago is how
                // somebody unticks a list they had just finished ticking.
                Button("Tick All") { model.setAllTicked(true, in: row) }
                    .buttonStyle(.app)
                    .controlSize(.small)
                    .disabled(model.isWorking || ticked.count == offered.count)
                Button("Untick All") { model.setAllTicked(false, in: row) }
                    .buttonStyle(.app)
                    .controlSize(.small)
                    .disabled(model.isWorking || ticked.isEmpty)
            }

            Text(StorageWords.batchExplanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(JunkSweep.Says.whyTheseArriveTicked)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The one press

    private var press: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            if ticked.isEmpty {
                Text(StorageWords.nothingTicked)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // ⚠️ Both figures for the batch, before the press. The second is what a person
                // would actually see afterwards, and on a Mac with a stuck snapshot it is zero.
                HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                    Text(StorageWords.batchButton(ticked.count))
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Space.row)
                    TwoNumbers(bytes: model.tickedBytes(in: row, arriving: arriving), alignment: .trailing)
                }

                // John's sentences, verbatim, from the file that owns them.
                SetAsideNotice(bytes: model.tickedBytes(in: row, arriving: arriving).onDisk.bytes,
                               anyInICloud: model.tickedTouchICloud(in: row, arriving: arriving),
                               diskIsAlreadyFull: diskIsAlreadyFull)
            }

            HStack(spacing: Space.gutter) {
                Button(StorageWords.batchButton(ticked.count)) {
                    Task { await model.setAsideTicked(in: row, arriving: arriving) }
                }
                .buttonStyle(.app)
                .controlSize(.regular)
                .disabled(ticked.isEmpty || model.isWorking)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: What we can only report

    /// ⛔ **The simulator runtimes, and anything else nothing can move.** 11.6 GB of compressed disk
    /// images on this Mac, root-owned and read-only, mounted as sealed volumes. No thirty-day undo
    /// could exist for them, so there is no button — the size and the reason, and nothing else.
    private var reportedOnly: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("Reported, with nothing to press")
                .font(.appHeadline)
            VStack(spacing: 0) {
                ForEach(Array(reported.enumerated()), id: \.element.id) { index, item in
                    OwnItemRow(item: item,
                               index: index,
                               home: model.home,
                               busy: model.isWorking,
                               onSetAside: nil)
                }
            }
        }
    }

    private func note(for item: Item) -> String? {
        judgements.first { $0.item.id == item.id }?.judgement.notTickedBecause
    }
}
