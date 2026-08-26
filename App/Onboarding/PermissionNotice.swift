// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  PermissionNotice.swift
//  Wellkept — App/Onboarding
//
//  The standing notice for a permission that is off.
//
//  ## The whole reminder story, in two views
//
//  Setup asks once. After that the app never raises a refused permission again on its own — no
//  dialog on launch, no badge, and **no permanent stripe across the top of every screen.** What is
//  left is these two: a row on Overview, and one line inside each section whose answer is
//  incomplete because of it.
//
//  Both disappear the moment the permission is granted, without being dismissed. That is what makes
//  them a statement of fact rather than a nag: there is nothing to close, because there is nothing
//  to close once it is true.
//
//  ## Why this is explanation and not clutter
//
//  DESIGN §12.4 draws the line at "say the thing the person does not already know." Someone looking
//  at Overview cannot know which parts of their Mac Wellkept was unable to see, or that a clean
//  result from a partial look is not a clean Mac. That is the sentence that turns a misleading
//  screen into an honest one, and it is worth the space every time it appears.

// MARK: - The Overview row

/// The notice as it appears on Overview: what is hidden, what that costs, and the way to change it.
///
/// **Renders nothing at all when the permission is on.** Place it at the top of Overview's list and
/// forget about it.
@MainActor
struct PermissionNoticeRow: View {

    private let center = PermissionCenter.shared

    /// Whether this person has ever been shown the Full Disk Access step. It decides one sentence
    /// below — never say the same thing twice, but do say it once to someone who left setup before
    /// reaching it.
    @AppStorage(SetupPrefs.fullDiskAccessAskedKey) private var asked = false

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    init() {}

    var body: some View {
        if !center.fullDiskAccessGranted {
            let tint = palette.color(for: Severity.attention)

            HStack(alignment: .top, spacing: Space.block) {
                Image(systemName: "eye.slash")
                    .font(.appBody)
                    .foregroundStyle(tint)
                    // The heading beside it says the same thing in words.
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Space.row) {
                    Text("Wellkept cannot see everything")
                        .font(.appHeadline)

                    Text(Self.explanation)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !asked {
                        Text(FullDiskAccess.reassurance)
                            .font(.appCallout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: Space.block) {
                        Button("Open System Settings…") {
                            center.openFullDiskAccessSettings()
                        }
                        .buttonStyle(.app)

                        if center.needsReopenToSee {
                            Button("Reopen Wellkept") { center.reopenWellkept() }
                                .buttonStyle(.app)
                        }
                    }
                    .padding(.top, Space.hairline)
                }

                Spacer(minLength: 0)
            }
            .padding(Space.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10), in: Radius.shape(Radius.card))
            // The border is the second channel: under Differentiate Without Color the wash says
            // nothing, and this row has to keep reading as a caveat rather than as a card.
            .overlay {
                Radius.shape(Radius.card)
                    .strokeBorder(tint.opacity(differentiate ? 0.85 : 0.35),
                                  lineWidth: differentiate ? Hairline.selection : Hairline.thin)
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// ⚠️ The second sentence is the load-bearing one. Overview may never say this Mac looks fine
    /// after a partial look, and this is where the user is told why a result might be short.
    private static let explanation = String(localized: """
        Full Disk Access is off, so parts of this Mac are hidden from Wellkept — what macOS has \
        already blocked, some of what is using your storage, and some of what is installed. \
        Anything Wellkept reports is what it could see, not everything there is.
        """)
}

// MARK: - The line inside a section

/// The same fact, said in one line, on the face of a section whose answer it actually shortens.
///
/// **Renders nothing** when the permission is on, and nothing on a section this permission does not
/// affect — Hardware reads the drive, battery and sensors through IOKit, which the switch does not
/// cover, and warning about it there would be a warning about something untrue.
@MainActor
struct PermissionNoticeLine: View {

    let section: SectionID

    private let center = PermissionCenter.shared

    @Environment(\.palette) private var palette

    init(section: SectionID) {
        self.section = section
    }

    var body: some View {
        if !center.fullDiskAccessGranted, let shortfall = FullDiskAccess.shortfall(for: section) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Image(systemName: "eye.slash")
                    .font(.appCaption)
                    .foregroundStyle(palette.color(for: Severity.attention))
                    .accessibilityHidden(true)

                Text(shortfall)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // A link-styled button, not a bare coloured word: SwiftUI draws this one, so it
                // keeps the app's font, and it still announces itself as a button.
                Button("Open System Settings…") {
                    center.openFullDiskAccessSettings()
                }
                .buttonStyle(.link)
                .font(.appCallout)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }
}
