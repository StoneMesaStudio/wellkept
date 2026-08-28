// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  StorageRowView.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **One of the five rows, and the two figures every single offer on this screen carries.**
//
//  ## ⚠️ Two numbers, always, and they are two different true answers
//
//  `~/Documents/Media` on this Mac: **14.8 GB on disk**, **0.5 GB back today**. Thirty times apart,
//  and the worksheet has a 150× case. The difference is a stuck Time Machine snapshot: a file
//  changed after the oldest snapshot comes back whole, one changed before it comes back not at all.
//
//  There is no view here that can draw one figure. `Bytes` carries both and has no initialiser
//  that takes a single number, and `TwoNumbers` prints both or says why the second is nothing.
//
//  ## ⚠️ The severity tag never appears on these rows
//
//  `StorageRow.severity` is a computed constant `.information`, and `SeverityTag` draws nothing for
//  `.information`. Revealing somebody's own files is not a fault, and a large folder is not a
//  problem — it is large. The only thing in this section that may be worse is how full the disk is,
//  and that is drawn once, at the top, by `FreeSpaceBlock`.

// MARK: - The card one row sits in

/// The heading, the three facts, and whatever the topic wants underneath.
///
/// Every row has the same head so that a person scanning the screen learns the shape once: what it
/// is, how much, and why it says so.
struct StorageTopicCard<Content: View>: View {

    let row: StorageRow
    /// The ceremony line, said once per card, so it is never a mystery which one you are in.
    var ceremonyNote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {

            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                Text(row.topic.label)
                    .font(.appTitle3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                if let measure = row.measure {
                    TwoNumbers(bytes: measure, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(row.headline)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isSummaryElement)

                // The row's own plain sentence, from `WellkeptCore`, so two screens cannot describe
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

                // ⚠️ Never swallowed. A row that read most of the disk and was refused the Trash is
                // not a row that failed — but it is not a row that saw everything either.
                // ⚠️ The SHORT form. The free-space card above has already named the folders;
                // printing them again an inch below is the same paragraph twice on one screen.
                if let refusal = row.refused.sentenceWithoutNames {
                    Text(refusal)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let ceremonyNote {
                    Text(ceremonyNote)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

// MARK: - ⭐ The two figures

/// **How much room it takes, and what would actually come back today.**
///
/// The second is not a smaller version of the first. It is the answer to a different question, and
/// on a Mac with a stuck snapshot it is routinely zero while the first is gigabytes. Printing only
/// the first would be the promise this section exists not to make.
struct TwoNumbers: View {
    let bytes: Bytes
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Figure(bytes.onDisk.text, size: 17, weight: .semibold)
                .accessibilityHidden(true)
            Text(bytes.recoverableToday.phrase)
                .font(.appCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        // Both, in one phrase. `Bytes.sentence` is where the pair is worded, and it is the same
        // sentence a `BigFiles.Place` uses.
        .accessibilityLabel(bytes.sentence)
    }
}

// MARK: - Where the weight sits

/// ⚠️ **A picture, not a proposal.** `BigFiles.Place` has no field a button could live in, and this
/// view draws none. It is the one row on this screen with nothing to press.
struct PlacesList: View {
    let places: [BigFiles.Place]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                    Text(place.name)
                        .font(.appBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TwoNumbers(bytes: place.bytes, alignment: .trailing)
                }
                .appRow(index)
            }
        }
    }
}

// MARK: - One thing, in the one-at-a-time ceremony

/// **A person's own file: named, sized, and never ticked.**
///
/// The verb sits on the row and opens a sheet. It is not a checkbox, there is no "select all", and
/// there is no batch entry point anywhere that could act on a list of these — see
/// `StorageModel.perform`.
struct OwnItemRow: View {
    let item: Item
    let index: Int
    var home: URL = StorageManifest.home()
    var busy = false
    /// Why the last attempt on this row did not work.
    var trouble: String?
    /// `nil` on a row we will never offer to touch — the size is still shown, and the reason is on
    /// the row where a button would have been.
    var onSetAside: (() -> Void)?

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

                // Why it is on the list. For a person's own file that is always and only "it is
                // large" — never "unused", never "old".
                Text(item.reason)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // ⚠️ Facts, in a line. "Last opened" is among them and is never a finding: it is
                // blank for 61% of the large files on this Mac, and one batch job stamped 123 of
                // them with the same date.
                Text(item.lineFacts.joined(separator: " · "))
                    .font(.appCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let trouble {
                    Text(trouble)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // ⚠️ Claims the width, and there is no `Spacer` beside it — an `HStack` holding both
            // splits the leftover between them, and every row ends up a third narrower than the
            // column it sits in.
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: Space.row) {
                TwoNumbers(bytes: item.bytes, alignment: .trailing)
                if let onSetAside, item.handling.mayOfferAButton {
                    Button(StorageWords.quarantine, action: onSetAside)
                        .buttonStyle(.app)
                        .controlSize(.small)
                        .disabled(busy)
                }
            }
        }
        .appRow(index)
    }
}

// MARK: - One thing, in the batch ceremony

/// **Machine junk, with a checkbox.** The only ticks on this screen.
///
/// The box is hand-rolled rather than a `Toggle` for the same reason every control in this app is:
/// native controls render in the system font and ignore the chosen typeface. The state is carried
/// by the mark **and** by the row's selection plate, so it never rests on one channel alone.
struct JunkTickRow: View {
    let item: Item
    let index: Int
    var home: URL = StorageManifest.home()
    /// The classifier's note when it decided not to tick something it could have. `nil` otherwise.
    var notTickedBecause: String?
    var trouble: String?
    let isTicked: Bool
    var busy = false
    let onToggle: (Bool) -> Void

    /// ⭐ Anything the engine cannot hold has no box at all. A tick that cannot be acted on is a
    /// promise the press would break.
    private var tickable: Bool { item.mayBePreSelected }

    var body: some View {
        Button { if tickable, !busy { onToggle(!isTicked) } } label: {
            HStack(alignment: .top, spacing: Space.gutter) {
                Image(systemName: mark)
                    .font(.appBody)
                    .foregroundStyle(tickable ? Color.primary : Theme.textTertiary)
                    .accessibilityHidden(true)

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
                        .help(item.path)

                    // ⭐ What it is and what writes it again. That second half is what makes a tick
                    // defensible, and `JunkClassifier.Category.reason` is where it is welded on.
                    Text(item.reason)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    if let notTickedBecause {
                        Text(notTickedBecause)
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
                .frame(maxWidth: .infinity, alignment: .leading)

                TwoNumbers(bytes: item.bytes, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .appRow(index, selected: isTicked)
        }
        .buttonStyle(.plain)
        .disabled(!tickable || busy)
        .accessibilityAddTraits(isTicked ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(item.name)
        .accessibilityValue(tickable
                            ? (isTicked ? "Ticked" : "Not ticked")
                            : (item.handling.why ?? "Cannot be set aside"))
    }

    private var mark: String {
        guard tickable else { return "minus.square" }
        return isTicked ? "checkmark.square.fill" : "square"
    }
}

// MARK: - Duplicates

/// **One set of identical files — and no nomination of an original.**
///
/// ⚠️ `Duplicates.Group` has no `keep`, no `original`, no `suggested`, and no sort that implies one.
/// Four real pairs on this Mac each defeat a different rule for picking, including a photo whose
/// dates a past copy destroyed, so "keep the oldest" picks the wrong one. Every copy gets the same
/// row and the same button, and the person chooses.
struct DuplicateGroupView: View {
    let group: Duplicates.Group
    let index: Int
    var home: URL = StorageManifest.home()
    var busy = false
    var trouble: (Item) -> String?
    let onSetAside: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                Text(group.headline)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TwoNumbers(bytes: group.extra, alignment: .trailing)
            }

            Text(Duplicates.Group.weNeverChoose)
                .font(.appCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // A pair the disk would not answer about. Listed, because the files really are
            // identical; not counted, because a number nobody verified does not go in a total.
            if let unsure = group.sharing.sentence {
                Text(unsure)
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(group.copies.enumerated()), id: \.element.id) { copyIndex, copy in
                    OwnItemRow(item: copy,
                               index: copyIndex,
                               home: home,
                               busy: busy,
                               trouble: trouble(copy),
                               onSetAside: { onSetAside(copy) })
                }
            }
        }
        .appRow(index)
    }
}
