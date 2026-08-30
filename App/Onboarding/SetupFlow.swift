// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import Observation
import SwiftUI
import WellkeptCore

//  SetupFlow.swift
//  Wellkept — App/Onboarding
//
//  Welcome → Full Disk Access → Overview. Two steps, and the second one is optional.
//
//  ## The rule this flow is built to
//
//  **"Finish later" is an answer, not an unfinished job.** Pressing it marks setup done and lands
//  the user on Overview, exactly as pressing through would. Nothing nags afterwards; the only
//  reminder the app ever gives is the quiet notice in `PermissionNotice.swift`, which sits where
//  the missing permission actually costs something.
//
//  That is deliberate, and it is the difference between a setup flow and a wall. A flow that keeps
//  score of what you skipped is a wall with a progress bar on it.
//
//  ## Where this runs from
//
//  Once, on first launch, and again whenever the user picks it from Help. Nothing that runs once
//  may be unreachable afterwards (DESIGN §14.6), which is also why every word here is written to
//  be read a second time by someone who already knows the app.

// MARK: - Stored keys

/// The two stored keys that belong to setup. Raw strings taken verbatim from `docs/CONTRACTS.md`;
/// they are written into the user's defaults and are therefore permanent.
///
/// `setupFinished` is removed by the uninstaller. That single fact is what makes setup run again
/// after a reinstall but stay quiet after an update — there is no version check anywhere, and there
/// does not need to be one.
enum SetupPrefs {
    static let setupFinishedKey = "setupFinished"
    static let fullDiskAccessAskedKey = "fullDiskAccessAsked"
}

// MARK: - The state

/// Whether setup is on screen.
///
/// ⚠️ **This must be owned above `AppearanceHost`.** That view re-identifies its whole subtree when
/// the font or text size changes, which resets every `@State` inside it. Setup held in there would
/// vanish mid-flow the first time somebody changed the text size from the menu bar.
@MainActor
@Observable
final class SetupState {

    private(set) var isPresented: Bool

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        // First launch is simply the absence of the mark. No version numbers, no migration.
        isPresented = !store.bool(forKey: SetupPrefs.setupFinishedKey)
    }

    /// Whether setup has ever been through to the end — either answer counts.
    var hasFinished: Bool { store.bool(forKey: SetupPrefs.setupFinishedKey) }

    /// Run it again, from Help. The mark stays set; this is a revisit, not a reset.
    func present() { isPresented = true }

    /// For `.sheet(isPresented:)`.
    ///
    /// Setting it false is the same answer as pressing "Finish later" — dismissing with Escape ends
    /// setup rather than deferring it, because there is no such thing as deferred here.
    var presentation: Binding<Bool> {
        Binding(get: { self.isPresented }, set: { if !$0 { self.finish() } })
    }

    /// The one exit.
    ///
    /// Both "Finish later" and pressing through arrive here, because both are answers. Anything
    /// that treated them differently would have to remember the difference, and remembering it is
    /// the first step toward nagging about it.
    func finish() {
        store.set(true, forKey: SetupPrefs.setupFinishedKey)
        isPresented = false
    }
}

// MARK: - The flow

struct SetupFlow: View {

    var onFinish: () -> Void

    /// Two steps. The order is fixed: what the app is, then the one thing it needs from you.
    private enum Step: Hashable {
        case welcome
        case fullDiskAccess
    }

    @State private var step: Step = .welcome

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(Space.page)
                // ⚠️ **A page, not a sheet.** This used to carry
                // `.frame(width: SheetMetrics.width(560), height: SheetMetrics.height(520))` —
                // sheet chrome on something `RootView` renders as a full-window cover, and
                // `SheetMetrics` measures against the *screen*, never the window, so dragging the
                // window wider bought it nothing. The result was a 560-pt island in an 1800-pt
                // field, with half the welcome text behind a scroll bar and a sentence sliced
                // through the middle. Reported from a real screenshot, 2026-08-30.
                //
                // The house answer is the one every section face already uses: fill the pane and
                // let the 700-pt readable column do the narrowing. Setup was the only screen in
                // the app asserting its own size.
                .readableColumn()
                // Fade in; the outgoing step leaves instantly. Never a slide between our own
                // screens — see `AnyTransition.faceFade`.
                .faceTransition(step)
        }
        .fillsPane()
        .pageGround()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeView { advance(to: .fullDiskAccess) }
        case .fullDiskAccess:
            FullDiskAccessStep(onFinish: onFinish)
        }
    }

    private func advance(to next: Step) {
        Motion.run(Motion.selection) { step = next }
    }
}

// MARK: - The Full Disk Access step

/// The one thing macOS will not let Wellkept do for itself.
///
/// This is where utilities lose people: the switch is in another app, the app has to be dragged
/// into a list, and nothing tells you when it worked. So this screen does three things — says what
/// the grant is for before asking, says exactly what to do, and detects the moment it is granted
/// rather than asking whether you did it.
///
/// ## ⚠️ It leads with the camera, the microphone and the screen, and that was a correction
///
/// Until 2026-08-27 this screen sold the grant on storage. Then somebody measured what actually
/// happens without it: **eleven of the twelve permissions read exactly zero**, so the screen that
/// lists which apps can use your camera, your microphone and your screen is *empty*, not short.
/// That is the strongest true reason to grant it, and it was the one being left out. Storage is
/// second, because storage is merely incomplete without it.
///
/// The words themselves live in `FullDiskAccess.purpose`, shared with the standing notice and with
/// Settings ▸ Permissions, so the app cannot make three different cases for the same switch.
///
/// **"Finish later" is untouched by that change.** It is still an answer, it still sits beside the
/// primary button rather than hidden as a grey word, and it still ends setup outright.
@MainActor
private struct FullDiskAccessStep: View {

    var onFinish: () -> Void

    // `@MainActor` on the type is what lets this default to the shared centre: the singleton is
    // main-actor isolated, and a stored property's default expression is evaluated in the type's
    // own context, not inside `body`.
    private let center = PermissionCenter.shared

    @AppStorage(SetupPrefs.fullDiskAccessAskedKey) private var asked = false

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gutter) {
            Text("Full Disk Access")
                .sectionHeading()

            Text(FullDiskAccess.purpose)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            Text(FullDiskAccess.consequence)
                .font(.appBody)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(FullDiskAccess.reassurance)
                .font(.appBody)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.row)

            status

            HStack(spacing: Space.block) {
                Spacer(minLength: 0)

                // ⚠️ **Once the grant is held there is nothing left to ask, so there is nothing
                // left to skip.** The screen used to offer "Finish later" and "Open System
                // Settings…" directly under a green line saying Full Disk Access was already on —
                // three controls arguing with each other, and one of them inviting the person to
                // postpone something they had already done. Reported from a real screenshot,
                // 2026-08-29.
                if center.fullDiskAccessGranted {
                    Button("Continue", action: onFinish)
                        .buttonStyle(.appProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    // ⚠️ "Finish later" is a real answer and sits beside the primary, not hidden in
                    // a corner as a grey word. A skip the user cannot find is not a skip.
                    Button("Finish later", action: onFinish)
                        .buttonStyle(.app)
                        .controlSize(.large)

                    Button("Open System Settings…") {
                        center.openFullDiskAccessSettings()
                    }
                    .buttonStyle(.appProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .fillsPane()
        // The record that Wellkept has made its one ask. Read by `PermissionNoticeRow`, which uses
        // it to avoid repeating a paragraph this person has already read, and cleared by the
        // uninstaller along with everything else.
        .onAppear { asked = true }
    }

    // MARK: The status band

    /// What macOS currently says, and the remedy when there is one.
    ///
    /// ⚠️ **The height is reserved**, so nothing on this screen moves when the answer changes
    /// underneath the user while they are in another app. The "Reopen Wellkept" button genuinely
    /// only exists in one state — offering it while the grant is already on would be nonsense — so
    /// this is the narrow exception to "controls never come and go", and the layout half of that
    /// rule, which is the half that actually bites, is enforced by the fixed frame.
    private var status: some View {
        HStack(alignment: .center, spacing: Space.block) {
            Image(systemName: center.fullDiskAccessGranted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.appBody)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            Text(statusLine)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if center.needsReopenToSee {
                Button("Reopen Wellkept") { center.reopenWellkept() }
                    .buttonStyle(.app)
                    .fixedSize()
            }
        }
        .padding(Space.block)
        .frame(minHeight: AppFont.pt(64), alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: Radius.shape(Radius.control))
        .accessibilityElement(children: .contain)
        .appAnimation(Motion.chrome, value: center.fullDiskAccessGranted)
    }

    private var statusColor: Color {
        center.fullDiskAccessGranted
            ? palette.color(for: SectionStatus.good)
            : Theme.textTertiary
    }

    private var statusLine: String {
        if center.fullDiskAccessGranted {
            String(localized: "Full Disk Access is on. Wellkept can see the whole disk.")
        } else if center.needsReopenToSee {
            // Not a question. Wellkept has looked and still cannot read, which usually means the
            // switch is on but this copy of the app started before it was.
            String(localized: """
                Wellkept still cannot read. macOS gives the new setting to Wellkept only once it \
                has started again.
                """)
        } else {
            String(localized: "Full Disk Access is off. In System Settings, switch Wellkept on in the list.")
        }
    }
}
