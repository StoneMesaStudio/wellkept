// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  SetAsideNotice.swift
//  Wellkept — App/SetAside
//
//  ⭐ **The two sentences that stop the app looking broken, as views, in one place.**
//
//  Decided 2026-08-28. **Before** the button: *"Set aside 40 GB. Nothing is deleted and no space
//  comes back until you empty the quarantine."* **After**, permanently: *"40 GB set aside — the
//  oldest is 12 days old"*, with the Empty button on it.
//
//  ## Why these are views rather than a note in a design document
//
//  Storage will be the first section to offer quarantine, and Apps and Security will follow. If
//  each writes its own version of the before-sentence, one of them eventually writes "Free up
//  40 GB" — which is false, and falsifiable by the person in About This Mac within a minute. A
//  section that drops `SetAsideNotice` into its page cannot get it wrong, and a section that does
//  not drop it in is visibly missing something rather than quietly saying the wrong thing.
//
//  ⚠️ **Nothing here composes a sentence about bytes on its own.** The figures come from
//  `QuarantineWords.beforeSettingAside` and `Quarantine.Summary.rowSentence` — the two settled
//  sentences, and the only place in the app allowed to put a number in front of a person here.
//
//  ## The three pieces
//
//  - `SetAsideNotice` — before. What the button will do, and what will *not* happen afterwards.
//  - `ICloudLine` — the one line, where the person is already looking. Not a dialog, not a
//    refusal.
//  - `QuarantineSummaryRow` — after, and permanently. The row with Empty on it.

// MARK: - Before

/// **Shown next to any button that offers to set files aside, before it is pressed.**
///
/// The whole point is the second half of the sentence: nothing is deleted, and the disk does not
/// get any emptier. A person who presses a cleanup button, watches 40 GB "disappear", and then sees
/// About This Mac report the same free space has been lied to — and is right to distrust everything
/// else the app tells them.
struct SetAsideNotice: View {

    /// What the chosen items add up to.
    let bytes: Int64

    /// Whether anything chosen is somewhere iCloud syncs. Drives the one line.
    var anyInICloud = false

    /// Whether this Mac is short of space *today*. The consequence drawn out: if the disk is
    /// already full, quarantine is the wrong button — the person wants quarantine and then empty,
    /// deliberately, in one sitting.
    var diskIsAlreadyFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(QuarantineWords.beforeSettingAside(bytes))
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            if diskIsAlreadyFull {
                Text(QuarantineWords.whenTheDiskIsAlreadyFull)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if anyInICloud { ICloudLine() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether any of these is somewhere iCloud syncs — iCloud Drive, or a Desktop and Documents
    /// with sync switched on.
    ///
    /// A helper rather than something each section works out for itself: "is this file in iCloud"
    /// has a right answer and two plausible wrong ones, and `Movable` already holds it.
    static func anyInICloud(_ urls: [URL]) -> Bool {
        urls.contains(where: Movable.isInICloud)
    }
}

/// **The one line, verbatim, plus the fact it is really about.**
///
/// 2026-08-28: iCloud files are *allowed, with a warning* — never refused. Refusing would block the
/// most ordinary finding in the product on any Mac with Desktop and Documents sync switched on.
///
/// The second sentence is the part that is easy to miss: for those thirty days the file is off the
/// person's other devices **while still taking up the same room here**. That is the trade being
/// made, and it is the only reason the line is worth showing at all.
struct ICloudLine: View {
    /// The gap sentence is worth saying before the button and repetitive on a list of forty rows.
    var showsTheGap = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.row) {
            Image(systemName: "icloud")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                // The symbol restates the sentence beside it; spoken aloud it is noise.
                .accessibilityHidden(true)
            Text(showsTheGap
                 ? "\(QuarantineWords.iCloud) \(QuarantineWords.iCloudGap)"
                 : QuarantineWords.iCloud)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - After, and permanently

/// **The row asked for: "40 GB set aside — the oldest is 12 days old", with Empty on it.**
///
/// ⚠️ **When the ledger could not be read, this shows `trouble.sentence` INSTEAD of a count.**
/// Never a zero beside it and never a zero without it. Zero is the one number that means somebody's
/// files are unaccounted for, and the app's rule is that it never reports zero because it could not
/// look. `Summary.rowSentence` already does the right thing; the buttons are what have to be
/// withheld, because emptying a quarantine nobody can read is not an offer to make.
struct QuarantineSummaryRow: View {
    let summary: Quarantine.Summary
    var now: Date = Date()

    /// Opens the full list. `nil` on the screen that already *is* the full list.
    var onOpen: (() -> Void)?
    /// Empties it. `nil` where the caller has nothing to run afterwards — the button is left out
    /// rather than shown and disabled, since a disabled destructive button explains nothing.
    var onEmpty: (() -> Void)?

    private var trustworthy: Bool { summary.trouble == nil }

    var body: some View {
        // ⚠️ **The sentence gets the whole width and the buttons sit under it.** Side by side, a
        // two-button column takes nearly half the readable column away from a sentence that is
        // already long — it wrapped to four lines beside an inch of empty card, which is the
        // §7.2 moving-target problem arriving through the layout instead of through animation.
        VStack(alignment: .leading, spacing: Space.block) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                // The sentence. Never "freed", never a figure that came back — nothing came back,
                // and nothing will until the quarantine is emptied.
                Text(summary.rowSentence(now: now))
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isSummaryElement)

                if let ready = summary.readySentence {
                    Text(ready)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // ⚠️ Counted rather than dropped. Silently shrinking the list is how a person stops
                // being told that something went wrong.
                if let unaccounted = summary.unaccountedSentence {
                    Text(unaccounted)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if trustworthy, onOpen != nil || (onEmpty != nil && summary.count > 0) {
                HStack(spacing: Space.gutter) {
                    if let onOpen {
                        // The same words as the window's title and the launch bar's button. Three
                        // names for one screen is three screens as far as anybody reading is
                        // concerned.
                        Button("Show Quarantine", action: onOpen)
                            .buttonStyle(.app)
                            .controlSize(.small)
                    }
                    if let onEmpty, summary.count > 0 {
                        EmptyQuarantineButton(count: summary.count,
                                              bytes: summary.bytes,
                                              onEmpty: onEmpty)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

// MARK: - The one destructive button

/// **Empty the quarantine — and say exactly what that removes before it happens.**
///
/// It carries its own confirmation rather than borrowing the window's alert slot, so a section can
/// drop it into a page without also inheriting a piece of state it has to route. The trio in
/// DESIGN §10 is satisfied and then some: uncommon, irreversible, and sitting next to a button
/// people press often.
///
/// ⚠️ The confirmation is `@State`, so a ⌘+ while it is open dismisses it. That is the safe
/// direction — the alert closes and nothing is removed — and it is why nothing further is kept
/// here.
struct EmptyQuarantineButton: View {
    let count: Int
    let bytes: Int64
    let onEmpty: () -> Void

    @State private var asking = false

    private var words: (title: String, message: String) {
        QuarantineText.emptyConfirmation(count: count, bytes: bytes)
    }

    var body: some View {
        Button(QuarantineText.empty, role: .destructive) { asking = true }
            .buttonStyle(.app)
            .controlSize(.small)
            .alert(words.title, isPresented: $asking) {
                Button(QuarantineText.empty, role: .destructive, action: onEmpty)
                // Cancel is what Return does. The last dialog that should answer itself with the
                // destructive verb is the one with no undo behind it.
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(words.message)
            }
    }
}
