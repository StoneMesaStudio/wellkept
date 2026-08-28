// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  QuarantineSettingsPage.swift
//  Wellkept — App/SetAside
//
//  ⭐ **The Quarantine page in Settings: what happens at thirty days, and what you told Wellkept to
//  ignore.**
//
//  Two things live here and nothing else, and both earn the space by the rule in DESIGN §1.2: a
//  preference gets a field only when the app must act without being asked.
//
//  1. **The thirty-day choice.** John, 2026-08-28: *remove them at thirty days* or *tell me at
//     thirty days*, and **manual is the default**. It has to be a setting because the alternative is
//     asking the same question every time somebody sets something aside.
//  2. **The ignore list.** The fourth verb finally gets a home. Ignoring something is the one action
//     in Wellkept with no visible consequence — the finding simply stops appearing — so without this
//     page it is the only decision a person cannot take back.
//
//  ⚠️ **The Settings screen's own rule, from its header: every setting read app-wide must have a
//  control on this screen.** `Expiry.mode` is read by `sweepOnOpening` at every launch and by every
//  row on the quarantine page. Before this page existed it was a stored key with no control, which
//  is exactly the bug Waypoint shipped and this house wrote the rule about.

struct QuarantineSettings: View {

    /// Held by `SettingsView`, above `AppearanceHost`, so a ⌘+ press does not throw away a reading
    /// of the ledger.
    let model: QuarantineModel

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.card) {
                Text(QuarantineText.whatThisIs)
                    .font(.appBody)
                    .fixedSize(horizontal: false, vertical: true)

                // ⚠️ **The list itself is not here any more.** It lived in Settings only because
                // Storage did not exist to hold it, and a quarantine with no page listing it would
                // have meant moving files out of somebody's home folder with nowhere to see them.
                // Storage exists now, and a list in two places is two lists as far as anybody
                // reading is concerned.
                Text(Says.theListLivesInStorage)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ExpiryModeControl()

                IgnoredItemsPanel(model: model)
            }
            .padding(Space.page)
            .readableColumn(Layout.readableColumn)
        }
        .pageGround()
        .task {
            await model.loadIgnored()
        }
    }

    enum Says {
        static let theListLivesInStorage =
            "Everything Wellkept has set aside is listed on the Storage screen, with Restore and "
            + "Delete on each row and one button that empties the whole thing."
    }
}

// MARK: - The thirty days

/// **What happens at thirty days, and it is the person's choice.**
///
/// ⚠️ The explanation under the control is not a hint that never retires — it changes with the
/// selection, and it states the limitation rather than hiding it. Wellkept ships no background
/// piece, so *automatic* can only act the next time the app is opened, and it says what it removed
/// when it does. An app that implied it was watching the clock while closed would be lying about
/// what it is.
struct ExpiryModeControl: View {

    /// ⚠️ **Absent means manual**, which is what John chose. A missing key must never read as
    /// automatic removal of somebody's files.
    @AppStorage(StorageManifest.Keys.quarantineExpiry) private var raw = ExpiryMode.manual.rawValue

    private var mode: Binding<ExpiryMode> {
        Binding(get: { ExpiryMode(rawValue: raw) ?? .manual },
                set: { raw = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("After \(Expiry.days) days")
                .font(.appHeadline)

            // ⚠️ **Not a segmented control, and that was tried first.** The two labels are
            // sentences — "Tell me when they reach 30 days" — and a two-segment control at the
            // Settings width truncated both of them to "Tell me when th…" and "Remove them…",
            // which is the one screen in the app where the difference between the options is the
            // entire content. A vertical choice has as much room as the words need.
            VStack(alignment: .leading, spacing: Space.row) {
                ForEach(ExpiryMode.allCases) { option in
                    ExpiryChoiceRow(option: option, selection: mode)
                }
            }

            Text(mode.wrappedValue.explanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // The one thing neither label says, and the thing that makes the choice safe to offer:
            // the count is calendar days, not days the app happened to be open.
            Text("Counted in calendar days from the day each item was set aside.")
                .font(.appCaption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

/// One of the two answers, with the mark that says which is chosen.
///
/// Hand-rolled rather than a `Picker(.radioGroup)` for the reason every control in this app is:
/// native controls render in the system font and ignore the chosen typeface. The mark is a filled
/// circle **and** a bolder label, so the choice is never carried by one channel alone.
private struct ExpiryChoiceRow: View {
    let option: ExpiryMode
    @Binding var selection: ExpiryMode

    private var chosen: Bool { selection == option }

    var body: some View {
        Button { selection = option } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                    .font(.appBody)
                    // Achromatic. Bronze appears in exactly three places in this app and this is
                    // not one of them, and `Color.accentColor` here would put a fourth colour on
                    // the screen — the asset is empty, so it resolves to the system blue.
                    .foregroundStyle(chosen ? Color.primary : Theme.textSecondary)
                    // The word beside it and the selected trait already say this.
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(.appBody.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - The ignore list

/// **What you told Wellkept to stop raising, and how to take it back.**
///
/// ⚠️ Nothing on this list was moved, changed or deleted. Ignoring is a statement about what
/// Wellkept will mention, not about the file — which is why the only verb here is *Stop Ignoring*
/// and why removing an entry cannot lose anybody anything.
///
/// ⚠️ **An unreadable list shows its trouble instead of a count.** A list that read as empty because
/// it could not be opened would put every suppressed finding back on somebody's screen — a smaller
/// harm than losing a file, and still the wrong answer.
struct IgnoredItemsPanel: View {
    let model: QuarantineModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(QuarantineText.ignoreListTitle)
                .font(.appHeadline)

            Text(QuarantineText.ignoreListBlurb)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let trouble = model.ignoreTrouble {
                Text(trouble.sentence)
                    .font(.appCallout)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.ignored.isEmpty {
                InlineEmptyNote(symbol: "eye", text: QuarantineText.ignoreListEmpty)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.ignored.enumerated()), id: \.element.id) { index, item in
                        IgnoredItemRow(item: item,
                                       index: index,
                                       home: model.home,
                                       busy: model.isWorking,
                                       onStop: { Task { await model.stopIgnoring(item) } })
                    }
                }
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

/// One ignored thing: what it was, what the finding said, which section said it, and when.
struct IgnoredItemRow: View {
    let item: IgnoredItem
    let index: Int
    /// The home folder, so the path reads as `~/Library/Logs/chatty.log`.
    var home: URL = StorageManifest.home()
    var busy = false
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.gutter) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(item.name)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Text(QuarantineText.shortPath(item.path, home: home))
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .help(item.path)

                // What the finding actually said, so the row is a decision a person can reconsider
                // rather than a path they have to recognise.
                Text(item.section.map { "\($0.title) · \(item.finding)" } ?? item.finding)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // ⚠️ `fixedSize` on the vertical axis, or the date truncates to "Aug 28, 2026 at
                // 8…" in a column this narrow instead of wrapping onto a second line.
                Text(QuarantineText.ignoredOn(item))
                    .font(.appCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // ⚠️ **Claims the width, and there is no `Spacer` beside it.** A `Spacer` is
            // flexible and so is wrapping text, so an `HStack` holding both splits the leftover
            // between them — the sentences wrapped two words early beside a hand's width of empty
            // row, and every row on the page was a third narrower than the column it sat in.
            .frame(maxWidth: .infinity, alignment: .leading)

            // No confirmation: nothing is destroyed and the person can ignore it again the moment
            // it reappears. A dialog here is how people learn to dismiss dialogs unread.
            Button(QuarantineText.stopIgnoring, action: onStop)
                .buttonStyle(.app)
                .controlSize(.small)
                .disabled(busy)
        }
        .appRow(index)
    }
}
