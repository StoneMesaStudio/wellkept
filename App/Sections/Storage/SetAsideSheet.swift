// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  SetAsideSheet.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **Ceremony two: one file, never pre-ticked, and the arithmetic stated before the press.**
//
//  John, 2026-08-28: *"A person's own file: one at a time, never pre-ticked, with a sheet stating
//  the arithmetic before the press — 'this will not make your Mac emptier today; to get the 12 GB
//  back you also have to empty the quarantine' — and both buttons on that sheet."*
//
//  ## The sentence is not written here
//
//  It is `FreeSpace.Says.arithmetic(for:)`, and the figure in it is **what would come back today**,
//  not the size on disk. On a Mac with a stuck Time Machine snapshot the two are up to 150× apart,
//  and quoting the larger one would be a promise the second press cannot keep. Where the snapshot
//  has taken the whole figure away, that function says so instead of naming a number.
//
//  ## ⚠️ The two buttons, and what the second one really is
//
//  - **Set aside** — the ordinary route. Nothing is deleted, nothing on the Mac gets smaller, and
//    there are thirty days to change your mind.
//  - **Set aside, then empty the quarantine** — the answer to the consequence John drew out on
//    2026-08-28: *if the disk is full today, quarantine is the wrong button.* Wanting the room now
//    means both halves, deliberately, in one sitting.
//
//  The second route is a real delete with no undo, so this sheet says what emptying takes with it
//  **before** it is pressed — including anything already waiting from an earlier day, which is the
//  one thing about that button a person could not otherwise know.
//
//  Cancel is the visible exit and is what Return does not do: the last dialog that should answer
//  itself with the irreversible verb is the one with nothing behind it.

struct SetAsideSheet: View {

    let item: Item
    /// What is already in quarantine, so the second route can say what else it removes. `nil` when
    /// the quarantine is empty or could not be read.
    var alreadyWaiting: Quarantine.Summary?
    /// Whether this Mac is short of room today.
    var diskIsAlreadyFull = false
    /// `(thenEmpty:)` — the route the person picked.
    let onConfirm: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gutter) {
            Text(StorageWords.sheetTitle(item)).sectionHeading()

            Text(QuarantineText.shortPath(item.path))
                .font(.appCaption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)

            StableScrollView {
                VStack(alignment: .leading, spacing: Space.gutter) {
                    numbers
                    arithmetic
                    if item.warning != nil { ICloudLine() }
                    if diskIsAlreadyFull { fullDisk }
                    if let alreadyWaiting { waiting(alreadyWaiting) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            buttons
        }
        .padding(Space.page)
        .frame(width: SheetMetrics.width(560), height: SheetMetrics.height(520))
        .pageGround()
    }

    // MARK: The two numbers

    /// ⭐ Both, side by side and labelled, because they answer different questions and the whole
    /// sheet is about the difference between them.
    private var numbers: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(StorageWords.sheetSizes)
                .font(.appHeadline)
            DetailPairGrid(pairs: [
                DetailPair("Size on disk", item.bytes.onDisk.text),
                DetailPair("Comes back today", item.bytes.recoverableToday.text),
            ])
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    /// ⭐ **John's sentence.** Never re-composed, never abbreviated.
    private var arithmetic: some View {
        Text(FreeSpace.Says.arithmetic(for: item.bytes))
            .font(.appBody)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullDisk: some View {
        Text(FreeSpace.Says.whenTheDiskIsAlreadyFull)
            .font(.appCallout)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// ⚠️ What the second button also removes. Said before the press, not discovered afterwards.
    private func waiting(_ summary: Quarantine.Summary) -> some View {
        Text(StorageWords.emptyingAlsoRemoves(summary))
            .font(.appCallout)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The two routes

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack(spacing: Space.gutter) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.app)
                    .keyboardShortcut(.cancelAction)
                Button(FreeSpace.Says.setAsideOnly) {
                    onConfirm(false)
                    dismiss()
                }
                .buttonStyle(.appProminent)
            }
            HStack(spacing: Space.gutter) {
                Spacer(minLength: 0)
                // Destructive, and it says so: this half has no undo at all.
                Button(FreeSpace.Says.setAsideAndEmpty, role: .destructive) {
                    onConfirm(true)
                    dismiss()
                }
                .buttonStyle(.app)
            }
        }
    }
}
