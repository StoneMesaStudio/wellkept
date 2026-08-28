// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import SwiftUI
import WellkeptCore

//  QuarantineLaunch.swift
//  Wellkept — App/SetAside
//
//  ⭐ **The two things the quarantine has to say when the window opens, and the bar that says
//  them.**
//
//  1. **`Quarantine.reconcileOnOpening()`** — finishes the bookkeeping of anything a crash
//     interrupted, and reports the one state nothing else in the app can see: an item at neither
//     the place it came from nor the place Wellkept was putting it. Its record is not in the ledger,
//     so no count anywhere will ever mention it. Called here or never.
//  2. **`Expiry.sweepOnOpening()`** — the thirty days. In **manual**, which is the default, it
//     removes nothing and only counts. In **auto** it removes what the person asked to have
//     removed, *and says what it removed*.
//
//  ## ⚠️ Why the sentence is not optional
//
//  Automatic removal is allowed to exist for exactly one reason: it is the person's own standing
//  instruction, carried out in front of them the first moment they are there to see it. That is only
//  true if the app tells them. A sweep that deleted files and said nothing would be the app acting
//  unbidden — the thing "automatic means looking, manual means touching" rules out — and it would be
//  indistinguishable from a bug in which the quarantine emptied itself.
//
//  ## ⚠️ Three guards, and each one has cost somebody something somewhere
//
//  - **Once per launch.** The window can be closed and reopened; the sweep must not run twice.
//  - **Never in demo mode.** Demo mode's whole promise is that nothing on screen came from this Mac.
//  - **Never under the test harness.** `ViewShots` renders the real shell into an off-screen window,
//    and that render pumps a run loop — which is enough for a `.task` to fire. This is the one piece
//    of the app that can *delete somebody's files* without a press, so the harness gate here is not
//    a nicety: without it, taking a screenshot of the sidebar could empty a real quarantine.

@MainActor
@Observable
final class QuarantineLaunch {

    /// What to tell the person, in the engine's own words. Empty on an ordinary Mac, which is the
    /// common case by a very wide margin.
    private(set) var notices: [String] = []

    /// Set once the launch pass has had its turn, whether it ran or refused.
    private var done = false

    let home: URL

    init(home: URL = StorageManifest.home()) {
        self.home = home
    }

    /// Run when the window opens, and **nowhere else**. Never a timer, never a launch agent.
    func runOnOpening(demoMode: Bool) async {
        guard !done else { return }
        done = true
        guard !demoMode, !Self.runningUnderTests else { return }

        let home = home
        notices = await Task.detached(priority: .utility) { () -> [String] in
            var said: [String] = []
            if let sentence = Quarantine.reconcileOnOpening(home: home).sentence {
                said.append(sentence)
            }
            if let sentence = Expiry.sweepOnOpening(home: home).sentence {
                said.append(sentence)
            }
            return said
        }.value
    }

    func dismiss() { notices = [] }

    /// The same test `HardwareModel` uses, and for the same reason.
    private nonisolated static var runningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
}

// MARK: - The bar

/// **What the quarantine did while nobody was looking, said across the top of the window.**
///
/// A bar rather than an alert: this is the app reporting its own state, not asking a question, and
/// an alert on launch is the thing every person learns to dismiss without reading — which is
/// precisely the wrong reflex to teach about the one message that reports a deletion.
///
/// Achromatic, like the demo bar. The three semantic colours mean good, not-yet-wrong and wrong;
/// dressing a report as one of those is how a person learns to ignore the real ones.
struct QuarantineLaunchBar: View {
    let notices: [String]
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                    Text(notice)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            // Claims the width outright. A `Spacer` here is as flexible as the wrapping text beside
            // it, so the two split the leftover and every sentence wraps at half the window.
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Show Quarantine", action: onOpen)
                .buttonStyle(.app)
                .controlSize(.small)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.app)
                .controlSize(.small)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.stripe)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairlineInk).frame(height: Hairline.thin)
        }
    }
}
