// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI

//  WelcomeView.swift
//  Wellkept — App/Onboarding
//
//  The first screen anyone ever sees.
//
//  ## Why it exists, and why it is this short
//
//  Wellkept is a utility that looks through someone's whole Mac. The three things a person needs
//  to know before letting it do that — that it deletes nothing, that nothing leaves the machine,
//  and that the source is public — are exactly the things they cannot find out by using it. Those
//  are worth a page. Anything else they can discover by pressing a button, and so does not belong
//  here.
//
//  Four lines and one button. No tour, no feature list, no marketing screen: the next thing after
//  this is the app doing its job.

struct WelcomeView: View {

    /// Move on to the next step of setup.
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            header

            VStack(alignment: .leading, spacing: Space.gutter) {
                ForEach(Self.promises) { promise in
                    PromiseLine(promise: promise)
                }
            }

            Spacer(minLength: Space.block)

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

    // MARK: The four lines

    fileprivate struct Promise: Identifiable {
        let id: String
        let symbol: String
        let text: String
    }

    /// ⚠️ These four are the app's standing promises, not copy. Two of them — deleting nothing, and
    /// nothing leaving the Mac — are the reason the rest of the app is shaped the way it is. If one
    /// of them ever stops being true, this page is where it has to change first.
    fileprivate static let promises: [Promise] = [
        Promise(
            id: "deletes",
            symbol: "trash.slash",
            text: String(localized: """
                Wellkept never deletes anything. It shows you what is on this Mac and what needs \
                you; what happens next is yours to decide.
                """)
        ),
        Promise(
            id: "offline",
            symbol: "wifi.slash",
            text: String(localized: """
                Nothing leaves your Mac. The one thing Wellkept sends anywhere is a check for \
                whether a newer version of Wellkept exists.
                """)
        ),
        Promise(
            id: "source",
            symbol: "chevron.left.forwardslash.chevron.right",
            text: String(localized: """
                Free, and open source under the GPL. Anyone can read exactly what it does.
                """)
        ),
        Promise(
            id: "purpose",
            symbol: "stethoscope",
            text: String(localized: """
                It looks over the hardware, your storage, your apps, security, backups and what \
                has changed, then says in plain words what needs you.
                """)
        ),
    ]
}

private struct PromiseLine: View {
    let promise: WelcomeView.Promise

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.block) {
            Image(systemName: promise.symbol)
                .font(.appBody)
                .foregroundStyle(Theme.textSecondary)
                // The words beside it say the same thing. A symbol is never the only signal.
                .accessibilityHidden(true)
                .frame(width: AppFont.pt(22), alignment: .leading)

            Text(promise.text)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
