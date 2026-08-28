// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  QuarantinePage.swift
//  Wellkept — App/SetAside
//
//  ⭐ **Everything Wellkept has set aside, on one screen, with the two verbs on every row.**
//
//  ## Why this is a window and not a section
//
//  Quarantine belongs to Storage, and Storage is not built. Parking the screen until then would
//  mean shipping a quarantine nobody can look at — files moved out of somebody's home folder with
//  no page that lists them. So it lives in its own window, reachable from **Help ▸ Quarantine…**
//  and from **Settings ▸ Quarantine**, and it moves into the Storage face the day that face exists.
//  Nothing here assumes a window: the list, the row and the summary are views a section can drop in.
//
//  ## The order, and why it is not worst-first
//
//  Every other list in this app is worst first. This one is **oldest first, with anything past
//  thirty days risen to the top and marked ready to remove** — `Expiry.sortedForTheScreen`. There
//  is no "worst" in a quarantine: a file is not a problem, it is a decision somebody deferred, and
//  the only thing that ranks them is how long they have been waiting.
//
//  ## ⚠️ What this screen may never say
//
//  - **"Freed."** Setting things aside returns no space at all: measured 2026-08-28, 391 MB across
//    100,000 files moved free space by −8 KiB. Every figure on this page comes from the engine's own
//    sentences, and the only one that reports space coming back is `DeleteReport.sentence`, which
//    measures it after the fact.
//  - **A count, when the ledger could not be read.** `QuarantineSummaryRow` shows the trouble
//    instead, and the list stays empty rather than reporting zero. Zero is the one number that
//    means somebody's files are unaccounted for.

// MARK: - The window

enum QuarantineWindowID {
    /// The scene id. `openWindow(id:)` takes this string, so it lives in one place.
    static let value = "wellkept-quarantine"
}

/// The Quarantine window scene. `WellkeptApp` mounts this alongside the main window and Help.
struct QuarantineScene: Scene {
    var body: some Scene {
        Window("Quarantine", id: QuarantineWindowID.value) {
            QuarantinePage()
        }
        .defaultSize(width: 860, height: 640)
        .defaultPosition(.center)
    }
}

// MARK: - The page

struct QuarantinePage: View {

    /// ⚠️ **Above `AppearanceHost`.** The host re-identifies everything inside it whenever the
    /// typeface or the text size changes, and a model held below would be rebuilt — and re-read the
    /// disk — every time somebody pressed ⌘+.
    @State private var model: QuarantineModel

    /// The expiry setting, read live rather than snapshotted, so changing it in Settings while this
    /// window is open changes what every row says about what happens next.
    ///
    /// ⚠️ **Absent means manual.** A missing key must never read as automatic removal.
    @AppStorage(StorageManifest.Keys.quarantineExpiry) private var expiryRaw = ExpiryMode.manual.rawValue

    private var mode: ExpiryMode { ExpiryMode(rawValue: expiryRaw) ?? .manual }

    /// The sandbox door. The app passes nothing; the view-shot harness and the tests pass a home
    /// folder they made themselves, so nothing here is ever pointed at a real one by accident.
    @MainActor
    init(model: QuarantineModel = QuarantineModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        AppearanceHost {
            StableScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    heading

                    // ⚠️ **Hidden when there is nothing set aside**, because the empty state below
                    // already says so — and DESIGN §8's rule is that a screen never says the same
                    // thing twice. `isEmpty` is false when the ledger could not be read, so the
                    // trouble sentence still gets its row.
                    if let summary = model.summary, !summary.isEmpty {
                        QuarantineSummaryRow(summary: summary,
                                             onEmpty: { Task { await model.empty() } })
                    }

                    if let word = model.lastWord { outcome(word) }

                    list

                    whatHappensAtThirtyDays
                }
                .padding(Space.page)
                .readableColumn()
            }
            .fillsPane()
            .pageGround()
        }
        .frame(minWidth: SheetMetrics.width(640), minHeight: SheetMetrics.height(420))
        .task { await model.load() }
    }

    // MARK: The top

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("Quarantine").sectionHeading()
            Text(QuarantineText.whatThisIs)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the last action did, in the engine's words, where the person is already looking.
    ///
    /// It stays until it is dismissed or replaced. A note that vanished on a timer would be the one
    /// sentence in the app somebody is most likely to want to re-read — it is the only report of an
    /// action that cannot be undone.
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

    // MARK: The list

    @ViewBuilder private var list: some View {
        if model.summary?.trouble != nil {
            // The trouble sentence is already on the summary row above. Repeating it here would be
            // the same bad news twice; what belongs here is why the list is empty.
            InlineEmptyNote(symbol: "exclamationmark.triangle",
                            text: "Wellkept will not list items it could not read the record of. "
                                + "Nothing has been deleted.")
        } else if !model.hasRead {
            InlineEmptyNote(symbol: "clock", text: "Reading what is set aside…")
        } else if model.records.isEmpty {
            EmptyStateView(symbol: "tray",
                           title: QuarantineText.nothingIsSetAside,
                           message: QuarantineText.nothingIsSetAsideWhy,
                           greedy: false)
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
                                      onRestore: { Task { await model.restore(record) } },
                                      onDelete: { Task { await model.delete(record) } })
                }
            }
        }
    }

    // MARK: The foot

    /// What thirty days actually does, in the mode that is set, with the way to change it.
    ///
    /// It is at the foot rather than the top because it is the answer to a question the list raises
    /// — every row says "ready to remove in 27 days" and this is what that means.
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

// MARK: - One item

/// **What it was, where it came from, who set it aside and why, how big, and how long it has.**
///
/// The two verbs sit on the row, because the row is the only place they mean anything. `Restore` is
/// the ordinary one and comes first; `Delete` carries its own confirmation naming the file.
struct QuarantineItemRow: View {
    let record: QuarantineRecord
    let index: Int
    let mode: ExpiryMode
    /// The home folder, so the path can be written the way a person thinks of it.
    var home: URL = StorageManifest.home()
    /// The file is not where the ledger says it is.
    var isMissing = false
    /// Why the last attempt on this row did not work.
    var trouble: String?
    var busy = false
    var now: Date = Date()
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var isReady: Bool { Expiry.isReady(record, now: now) }

    var body: some View {
        HStack(alignment: .top, spacing: Space.gutter) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                HStack(spacing: Space.row) {
                    if isReady { ReadyTag() }
                    Text(record.originalName)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                // Where it came from. Two files called `Cache.db` are told apart by nothing else,
                // and a person deciding whether to put something back needs to see where it would
                // go — so the path is always there, written with `~` and capped at two lines. The
                // whole thing is in the tooltip, and the text is selectable.
                Text(QuarantineText.shortPath(record.originalPath, home: home))
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .help(record.originalPath)

                // Who set it aside, and why, in the words the section used at the time.
                Text(QuarantineText.origin(record))
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Text(QuarantineText.life(record, mode: mode, now: now))
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // John's one line, on the row it is true of. Never a dialog and never a refusal.
                if record.wasInICloud { ICloudLine(showsTheGap: false) }

                if isMissing {
                    Text(QuarantineText.noLongerThere)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let trouble {
                    Text(trouble)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // ⚠️ **Claims the width, and there is no `Spacer` beside it.** A `Spacer` is
            // flexible and so is wrapping text, so an `HStack` holding both splits the leftover
            // between them — the sentences wrapped two words early beside a hand's width of empty
            // row, and every row on the page was a third narrower than the column it sat in.
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: Space.row) {
                Figure(StorageManifest.readable(record.bytes), size: 15, weight: .semibold)

                Button(QuarantineText.restore, action: onRestore)
                    .buttonStyle(.app)
                    .controlSize(.small)
                    // Nothing to put back, so the verb would be a promise the engine refuses.
                    .disabled(busy || isMissing)

                DeleteItemButton(record: record, busy: busy, onDelete: onDelete)
            }
        }
        .appRow(index)
    }
}

/// Past thirty days, and waiting. The word is the signal, not the colour.
private struct ReadyTag: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        let colour = palette.color(for: .attention)
        Text("READY")
            .font(.appCaption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(colour)
            .lineLimit(1)
            .padding(.horizontal, AppFont.pt(6))
            .padding(.vertical, AppFont.pt(2))
            .background(colour.opacity(0.10), in: Radius.shape(AppFont.pt(Radius.small)))
            .overlay(differentiate
                     ? Radius.shape(AppFont.pt(Radius.small))
                        .strokeBorder(colour.opacity(0.7), lineWidth: Hairline.thin)
                     : nil)
            .accessibilityLabel("Ready to remove")
    }
}

/// Delete one item, with the confirmation that names it.
///
/// Its own alert rather than the page's, for the same reason as `EmptyQuarantineButton`: a row is a
/// view a section can reuse, and one that needs a piece of the host's state to be wired up is one
/// that will be dropped in with the wire missing.
private struct DeleteItemButton: View {
    let record: QuarantineRecord
    var busy = false
    let onDelete: () -> Void

    @State private var asking = false

    private var words: (title: String, message: String) {
        QuarantineText.deleteConfirmation(record)
    }

    var body: some View {
        Button(QuarantineText.delete, role: .destructive) { asking = true }
            .buttonStyle(.app)
            .controlSize(.small)
            .disabled(busy)
            .alert(words.title, isPresented: $asking) {
                Button(QuarantineText.delete, role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(words.message)
            }
    }
}
