// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI
import WellkeptCore

//  RecoveryPlanView.swift
//  Wellkept — App/Sections/Backup
//
//  ⭐ **The page, on screen, exactly as it will come out of the printer — and the two buttons that
//  make it real.**
//
//  ## Why the whole page is shown before anything is printed
//
//  Same rule as `RepairShopSheet`: **show what is about to leave, before it leaves.** There the
//  thing leaving is a paste; here it is a piece of paper somebody will keep for years, and one of
//  its jobs is to hold their FileVault recovery key in their own handwriting. Nobody should have to
//  print a page to find out what is on it.
//
//  Both renderings come from `RecoveryPlanDocument.blocks(for:)`. There is no second list of what
//  the page says: this file turns blocks into SwiftUI, and `RecoveryPlanDocument.attributed`
//  turns the same blocks into ink.
//
//  ## ⚠️ The sentence this sheet exists to deliver
//
//  **macOS 26 moved the FileVault recovery key out of Apple's escrow and into the Passwords app.**
//  *"I can get it back with my Apple ID"* is no longer true. Wellkept can never read that key —
//  nothing unprivileged can — but it can put somebody in front of the Passwords app **while the Mac
//  still works**, which is the only moment it is possible. That warning is lifted to the top of the
//  page by `blocks(for:)` and it is repeated as the sheet's own leading line, because it is the one
//  thing here that is useless if it is read at the moment of need.
//
//  ## ⛔ What this sheet cannot do
//
//  It cannot fill anything in. Every value on the page is a blank with a ruled line; there is no
//  field, no text box, and nowhere in `RecoveryBlank` to put a value if somebody wanted one.

struct RecoveryPlanView: View {

    /// The page as it would be printed **today**, from what this Mac is now.
    let plan: RecoveryPlan

    /// What was already on record, if anything — so a page written for an older macOS can say so
    /// rather than quietly being replaced.
    var onRecord: RecoveryPlan?

    /// Called when a page actually reached a printer or a file, with the page that did.
    var onPrinted: (RecoveryPlan) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    /// What the last press did. Held rather than flashed: it is the report of the one action on
    /// this sheet that produces something a person then has to go and find.
    @State private var word: String?

    private var blocks: [RecoveryPlanDocument.Block] { RecoveryPlanDocument.blocks(for: plan) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gutter) {
            header

            StableScrollView {
                VStack(alignment: .leading, spacing: Space.block) {
                    ForEach(blocks) { block in
                        BlockView(block: block)
                    }
                }
                .padding(Space.card)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor), in: Radius.shape(Radius.control))
            .overlay(Radius.shape(Radius.control)
                .strokeBorder(Theme.hairlineInk, lineWidth: Hairline.thin))

            if let word {
                Text(word)
                    .font(.appCallout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            buttons
        }
        .padding(Space.page)
        .frame(width: SheetMetrics.width(680), height: SheetMetrics.height(720))
        .pageGround()
    }

    // MARK: The heading

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("Your Recovery Plan").sectionHeading()

            // ⚠️ Said here as well as on the paper. Somebody who reads this sheet and never prints
            // it has still been told the one thing that has to be done while the Mac works.
            Text(RecoveryPlan.printIt)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            if let stale = onRecord?.reprintLine(currentMacOS: plan.macOSVersion) {
                Text(stale)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The buttons

    /// ⚠️ **Print is the prominent one, and Save is beside it rather than instead of it.** A PDF on
    /// the Mac that will not start is a PDF you cannot open; the sentence under Save says so, once,
    /// where the decision is being made.
    private var buttons: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack(spacing: Space.gutter) {
                Button("Close") { dismiss() }
                    .buttonStyle(.app)
                    .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                Button("Save as PDF…") { act(RecoveryPlanDocument.savePDF(plan)) }
                    .buttonStyle(.app)

                Button("Print…") { act(RecoveryPlanDocument.print(plan)) }
                    .buttonStyle(.appProminent)
                    .keyboardShortcut(.defaultAction)
            }

            Text("A saved file lives on this Mac, and on the day you need this page that is the Mac "
                 + "that will not start. Print one as well.")
                .font(.appCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ⚠️ **The page is recorded only when it actually went somewhere.** A cancelled print panel
    /// records nothing and says nothing — a person who changed their mind has not been told they
    /// have a Recovery Plan.
    private func act(_ outcome: RecoveryPlanDocument.Outcome) {
        if case .done = outcome { onPrinted(plan) }
        word = outcome.sentence
    }
}

// MARK: - One block of the page

/// A block of the document, on screen. The same list the printer is given, in the app's own type.
///
/// ⚠️ The screen and the paper are deliberately **not** pixel-identical: the page is set in fixed
/// points because it is paper, and this follows the app's text-size setting because it is a screen.
/// What has to match is the words and their order, and that is guaranteed by both reading the same
/// `[Block]`.
private struct BlockView: View {
    let block: RecoveryPlanDocument.Block

    var body: some View {
        switch block {
        case .title(let text):
            Text(text)
                .font(.appTitle3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

        case .subtitle(let text):
            Text(text)
                .font(.appCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let text):
            Text(text)
                .font(.appHeadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.row)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(text)
                .font(.appCallout)
                .fixedSize(horizontal: false, vertical: true)

        case .step(let number, let title, let whatToDo, let why):
            HStack(alignment: .firstTextBaseline, spacing: Space.block) {
                Figure("\(number)", size: 15, weight: .semibold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.hairline) {
                    Text(title)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(whatToDo)
                        .font(.appCallout)
                        .fixedSize(horizontal: false, vertical: true)
                    // Always present, never behind anything. A step somebody understands is a step
                    // they can adapt when the screen in front of them does not match the page.
                    Text("Why: \(why)")
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

        case .warning(let title, let body, let urgent):
            VStack(alignment: .leading, spacing: Space.hairline) {
                HStack(spacing: Space.row) {
                    // The one tag on this page, and only on the item that has to be done today.
                    if urgent { SeverityTag(severity: .attention) }
                    Text(title)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(body)
                    .font(.appCallout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

        case .blank(let label, let whereToFindIt, let lineLength):
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(label)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                // The ruled line, drawn rather than typed: a run of underscores in a proportional
                // font is a dotted line, and this one is meant to be written on.
                Rectangle()
                    .fill(Theme.hairlineInk)
                    .frame(width: AppFont.pt(CGFloat(lineLength) * 7), height: Hairline.thin)
                    .padding(.vertical, Space.hairline)
                    .accessibilityHidden(true)
                Text(whereToFindIt)
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label), a blank line to fill in by hand. \(whereToFindIt)")
        }
    }
}
