// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI
import WellkeptCore

//  WelcomeView.swift
//  Wellkept — App/Onboarding
//
//  The first screen anyone ever sees.
//
//  ## What it says, and why it changed
//
//  Wellkept is a utility that looks through someone's whole Mac. The things a person needs to know
//  before letting it do that are exactly the things they cannot find out by using it, and they are
//  worth a page. Everything else they can discover by pressing a button.
//
//  ⚠️ **Until 2026-08-27 this page promised "Nothing leaves your Mac."** That was Claude's wording,
//  and John struck it — see the header of `Privacy.swift` for his words. The promise was already
//  carrying an "except" clause here, a different one in Help and none at all in Settings, and the
//  Apps section then needed to ask makers whether an app has a newer version, which the absolute
//  version forbids outright.
//
//  **An absolute promise the app breaks is worse than an honest conditional one.** So the page now
//  has three parts, in this order:
//
//  1. What Wellkept never does — unconditional, because every line of it is actually true.
//  2. **Everything that leaves this Mac**, named one by one, with what each buys you, that each has
//     a switch, and what switching it off costs. Today there are two.
//  3. What it is: it deletes nothing, and the source is public.
//
//  ⚠️ **Not one sentence on this page is written here.** They all come from `Privacy` in
//  `WellkeptCore`, which is the register: a section that later wants to send something adds a case
//  there, and this page grows the line by itself. That is the point — nothing can be added quietly,
//  and nothing can drift out of step with Help or Settings, because there is only one copy.
//
//  The page scrolls, and the button does not. The sheet is a fixed 560 × 520 and the text scale goes
//  to 200%; a fixed-height page whose content has grown is how a Continue button ends up below the
//  fold with nothing to say it is there.

struct WelcomeView: View {

    /// Move on to the next step of setup.
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            header

            StableScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    neverDone
                    departures
                    aboutTheApp
                }
                .padding(.bottom, Space.block)
            }

            HStack {
                Spacer(minLength: 0)
                Button("Continue", action: onContinue)
                    .buttonStyle(.appProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .fillsPane()
    }

    // MARK: The name

    private var header: some View {
        HStack(alignment: .center, spacing: Space.gutter) {
            // The real app icon rather than a symbol: it is the thing the user will look for in
            // the Dock afterwards, and it spends no colour the app has promised elsewhere.
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: AppFont.pt(52), height: AppFont.pt(52))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Space.hairline) {
                Text("Wellkept")
                    .font(.appTitle)
                Text("A health check for your Mac.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 1 — What is never done

    /// ⚠️ Unconditional, and allowed to be: every line is true under every setting. The moment one
    /// of them needs an "except", it stops belonging here and becomes a `Privacy.Departure`.
    private var neverDone: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHeading(text: String(localized: "What Wellkept never does"))

            ForEach(Privacy.neverDone, id: \.self) { line in
                BulletLine(text: line)
            }
        }
    }

    // MARK: 2 — Everything that leaves

    /// ⚠️ **Driven by `Privacy.Departure.allCases`, never by a list written here.** A third thing
    /// that leaves the Mac appears on this page the day its case is added, whether or not anybody
    /// remembered to come and edit the welcome screen.
    private var departures: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            SectionHeading(text: String(localized: "What leaves this Mac"))

            Text(Privacy.departuresIntro)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Privacy.Departure.allCases) { departure in
                DepartureLine(departure: departure)
            }
        }
    }

    // MARK: 3 — What it is

    private var aboutTheApp: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHeading(text: String(localized: "What it is"))

            BulletLine(text: String(localized: """
                Wellkept never deletes anything. It shows you what is on this Mac and what needs \
                you; what happens next is yours to decide.
                """))
            BulletLine(text: String(localized: """
                It looks over the hardware, your storage, your apps, security, backups and what has \
                changed, then says in plain words what needs you.
                """))
            BulletLine(text: String(localized: """
                Free, and open source under the GPL. Anyone can read exactly what it does.
                """))
        }
    }
}

// MARK: - The pieces

private struct SectionHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.appHeadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One plain line. A dot rather than a symbol: five different symbols down the left of a privacy
/// page decorate a list that is meant to be read as one thing.
private struct BulletLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.block) {
            Text("•")
                .font(.appBody)
                .foregroundStyle(Theme.textSecondary)
                // The words beside it say the same thing. A mark is never the only signal.
                .accessibilityHidden(true)
                .frame(width: AppFont.pt(10), alignment: .leading)

            Text(text)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One thing that leaves this Mac: its name, what actually goes out, and what turning it off costs.
///
/// ⚠️ **The cost line is not optional and is not smaller than the rest.** A switch with no stated
/// cost is a switch people flip out of caution and then wonder why the app got worse — which is
/// exactly what already happens with Full Disk Access, and the reason John's instruction was
/// "inform and consent" rather than "make it optional".
private struct DepartureLine: View {
    let departure: Privacy.Departure

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            Text(departure.title)
                .font(.appHeadline)
                .fixedSize(horizontal: false, vertical: true)

            Text(departure.whatLeaves)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            Text(departure.cost)
                .font(.appBody)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
