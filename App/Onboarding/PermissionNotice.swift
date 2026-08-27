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

                    // ⚠️ The dead end, made honest. A grant given to an app that is already
                    // running does not reach it — macOS offers "Quit & Reopen" and somebody who
                    // declines is left with an app insisting it was not allowed. When there is
                    // reason to think that is what happened, this says so and offers the restart.
                    if center.needsReopenToSee {
                        Text(center.reopenSentence)
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
        Full Disk Access is off, so parts of this Mac are hidden from Wellkept — which apps can use \
        your camera, your microphone and your screen, some of what is using your storage, and what \
        macOS has already blocked. Anything Wellkept reports is what it could see, not everything \
        there is.
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

    /// ⚠️ **A seam for the shot harness, and for nothing else.** `nil` — the only value the app ever
    /// passes — reads this Mac's real answer.
    ///
    /// It exists because this notice draws only while the grant is OFF, which makes it the one piece
    /// of the app that cannot be photographed on a machine where it is on. Without the seam, whether
    /// the refused screen gets a picture at all depends on the permissions of whoever ran the shots
    /// — and the refused screen is precisely the one nobody sees by accident.
    private let grantedOverride: Bool?

    @Environment(\.palette) private var palette

    init(section: SectionID, granted: Bool? = nil) {
        self.section = section
        self.grantedOverride = granted
    }

    var body: some View {
        if !(grantedOverride ?? center.fullDiskAccessGranted),
           let shortfall = FullDiskAccess.shortfall(for: section) {
            // The button sits UNDER the sentence, not beside it. Beside it, the button claims a
            // column and the sentence wraps into a four-line ribbon three words wide — measured,
            // not guessed: see the 2026-08-27 shots of the Security face.
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Image(systemName: "eye.slash")
                    .font(.appCaption)
                    .foregroundStyle(palette.color(for: Severity.attention))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Space.row) {
                Text(shortfall)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // ⚠️ NOT `.buttonStyle(.link)`. That draws in the system accent, and since
                // `AccentColor` ships empty (DESIGN §3.8) the accent is Apple's blue — which
                // would be the only blue anywhere in Wellkept, sitting on the section a person
                // is most likely to see first. Tinting it bronze is no better: bronze is spent
                // in exactly three places and a link is not one of them. So it is the ordinary
                // achromatic button, the same control this same notice uses in its card form.
                Button("Open System Settings…") {
                    center.openFullDiskAccessSettings()
                }
                .font(.appCallout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }
}
