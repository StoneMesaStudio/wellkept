// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  WhatIsWatchedList.swift
//  Wellkept — App/Sections/Changes
//
//  ⭐ **The whole list of what this section compares, by name, and what it does not.**
//
//  ## Why this list exists at all
//
//  Changes could very easily imply it watched every preference on the Mac. It does not, and the
//  scope settled on 2026-08-28 is narrower than the plan's: **Wellkept compares the things it
//  already understands** — the protections, what can reach this Mac, what starts on its own, which
//  apps hold which privacy permission, and the version of macOS. About thirty things, each with
//  three sentences we wrote and can defend.
//
//  A section that let a person believe otherwise would be claiming a look it never took, which is
//  the same failure as reporting a clean Mac after a partial scan. So the face says the scope in a
//  sentence, and this is the list behind it, item by item.
//
//  ## ⛔ What is deliberately not here
//
//  No promise of more. There is no "coming soon", no greyed row, no count of what a later version
//  might explain. A screen that advertises a feature nobody has built is a screen that ages badly
//  and gets believed in the meantime.

struct WhatIsWatchedList: View {

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            VStack(alignment: .leading, spacing: Space.row) {
                Text("What Wellkept watches")
                    .font(.appHeadline)

                Text("\(Watched.all.count) things, listed below. Wellkept compares these against "
                     + "what they were the last time you opened it. It does not compare every "
                     + "preference on this Mac.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(ChangesTopic.allCases) { topic in
                VStack(alignment: .leading, spacing: Space.row) {
                    Text(topic.label)
                        .font(.appHeadline)

                    VStack(spacing: 0) {
                        ForEach(Array(Watched.inTopic(topic).enumerated()), id: \.element.id) { index, watched in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(watched.title)
                                    .font(.appCallout.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                // One sentence each here — what it does. The other two arrive on a
                                // change, where a person is deciding something and they earn their
                                // space; thirty-four sets of three would be a wall nobody reads.
                                Text(watched.description.does)
                                    .font(.appCallout)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appRow(index, compact: true)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            notCovered
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// ⚠️ **Said plainly, because the alternative is a person assuming we looked.**
    ///
    /// Safari, Mail, Photos, Messages and Notes keep their settings inside containers no app can
    /// read without putting a privacy dialog on the screen. Wellkept does not reach for them —
    /// macOS raises that dialog on the *attempt*, not on the failure — so their settings are
    /// genuinely outside this comparison and always will be.
    private var notCovered: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("What this does not cover")
                .font(.appHeadline)

            Text("Safari, Mail, Photos, Messages and Notes keep their settings where no app can "
                 + "read them without putting a permission box on your screen. Wellkept does not "
                 + "reach for them, so nothing in those apps is part of this comparison.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Everything else readable is written into Wellkept's own record when it looks, "
                 + "including values it has no description for. Those are counted on this screen "
                 + "and never listed, because a row nobody can explain is a row that worries "
                 + "somebody for no reason.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
