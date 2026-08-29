// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import Foundation
import Observation
import ServiceManagement
import WellkeptCore

//  BackgroundPieceService.swift
//  Wellkept — App/Backup/Agent
//
//  ⭐ **Switching the Login Item on and off, and reading the truth about whether it is on.**
//
//  `SMAppService.agent` — **no password, no root, no privileged helper, no installer.** The job
//  description lives inside Wellkept's own bundle at `Contents/Library/LaunchAgents/`, macOS
//  registers it for this user only, and it appears in **System Settings ▸ General ▸ Login Items**
//  under Wellkept's own name, where the person can switch it off without asking us.
//
//  ## ⚠️ Nothing here is stored in a preference, and that is deliberate
//
//  Whether the background piece is registered is a fact about the system, and `SMAppService.status`
//  is the only honest source for it. A stored Bool would be a second answer that goes wrong the
//  first time somebody switches the row off in System Settings — which is precisely the thing this
//  design promises they can do. Same rule the app already follows for Full Disk Access: **ask, do
//  not remember.**
//
//  ## ⚠️ Registering is allowed before the gate opens. Copying is not.
//
//  This looks like a contradiction and it is the resolution of one. `RehearsalGate` will not let
//  the background piece copy until somebody has proved it can see mail, messages and photos — and
//  **the only way to obtain that proof is to run it**, in its own process, with the window closed.
//  So the switch works today, the background piece starts, it looks at what it can see, it writes
//  down what it found in `AgentRecord`, and it copies nothing. That record is the evidence a human
//  reads before filling in `RehearsalGate.agentHoldsFullDiskAccess`.
//
//  Registering a login item moves no bytes. `RehearsalGate` is named here so nobody has to go and
//  check whether it should have been.

@MainActor
enum BackgroundPieceService {

    /// The service object. Cheap; made fresh each time rather than cached, because a cached one
    /// outlives the answer it was made for.
    private static var service: SMAppService {
        SMAppService.agent(plistName: BackgroundPiece.plistName)
    }

    // MARK: ── Reading ───────────────────────────────────────────────────────────────────────────

    /// What macOS says. Never a stored guess.
    static var status: SMAppService.Status { service.status }

    /// Whether the background piece is switched on.
    static var isOn: Bool { status == .enabled }

    /// ⚠️ **`.requiresApproval` is not an error and must never be reported as one.** It means macOS
    /// accepted the registration and is waiting for the person to allow it in System Settings —
    /// which is exactly the arrangement John asked for. An app that showed a failure here would send
    /// somebody hunting for a problem that is a checkbox.
    static var needsTheirApproval: Bool { status == .requiresApproval }

    /// The line under the switch, in the person's terms rather than Apple's enum.
    static var statusSentence: String {
        switch status {
        case .enabled:
            "On. Wellkept keeps a small part of itself running to back up while your drive is connected."
        case .requiresApproval:
            "Waiting for you. macOS has added Wellkept to Login Items and needs you to allow it there."
        case .notRegistered:
            "Off. Wellkept quits when you close its window."
        case .notFound:
            "This copy of Wellkept does not carry the background piece."
        @unknown default:
            "Wellkept could not tell whether the background piece is switched on."
        }
    }

    // MARK: ── Switching ─────────────────────────────────────────────────────────────────────────

    /// What came back from a switch. Deliberately three outcomes, not two.
    enum Outcome: Sendable, Hashable {
        case on
        /// Registered, and macOS is waiting for the person to allow it in System Settings.
        case waitingForApproval
        case off
        case failed(String)

        var sentence: String {
            switch self {
            case .on:                "The background piece is on."
            case .waitingForApproval: "Allow Wellkept in System Settings ▸ General ▸ Login Items to finish switching this on."
            case .off:               "The background piece is off. Wellkept quits when you close its window."
            case .failed(let why):   "Wellkept could not change that: \(why)"
            }
        }
    }

    @discardableResult
    static func turnOn() -> Outcome {
        do {
            try service.register()
            // Register can succeed and still be waiting on the person, so the answer comes from
            // reading the status back rather than from the absence of a throw.
            AgentRecord.recordSight(as: .theApp, saying: "The background piece was switched on.")
            return needsTheirApproval ? .waitingForApproval : .on
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    static func turnOff() -> Outcome {
        do {
            try service.unregister()
            return .off
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// ⭐ **Every login item Wellkept has ever registered, taken back.**
    ///
    /// Driven by `StorageManifest.BackgroundItems.loginItemPlists` rather than by a name typed
    /// here, so a second background piece added in two years is unregistered by the uninstaller
    /// without anybody remembering to edit the uninstaller. See `Uninstaller.unregisterBackgroundItems`
    /// for why the order matters: once the bundle moves, macOS can no longer find the job it was
    /// registered from, and the Login Items row survives for years with no way to clear it.
    static func unregisterEverythingDeclared() {
        for plist in StorageManifest.BackgroundItems.loginItemPlists {
            try? SMAppService.agent(plistName: plist).unregister()
        }
    }

    // MARK: ── The row in System Settings ────────────────────────────────────────────────────────

    /// Show them the row, so "you can switch it off yourself" is one press rather than a hunt.
    static func showTheirLoginItems() {
        SystemSettingsPane.loginItems.open()
    }
}

// MARK: - What a face binds to

/// **The switch, as something a view can hold.**
///
/// Written here rather than in a section face so the Backup face, Settings and anywhere else all
/// drive the same object and cannot show two different answers about one login item.
@MainActor
@Observable
final class BackgroundPieceModel {

    private(set) var isOn = false
    private(set) var needsApproval = false
    private(set) var statusSentence = ""

    /// The last thing that happened, for a line under the switch. Cleared on the next change.
    private(set) var lastOutcome: BackgroundPieceService.Outcome?

    /// ⛔ What the gate says about letting the background piece copy. Refused on every Mac today.
    var permission: RehearsalGate.Decision {
        RehearsalGate.permissionForTheBackgroundPiece(to: "the background piece")
    }

    /// ⚠️ **True while the switch works but the copying does not.** The switch is still offered,
    /// because running it is how the proof gets taken — see the note at the top of this file.
    var willLookButNotCopy: Bool { !permission.isGranted }

    /// The sentence that has to appear beside the switch while that is true.
    var whyItWillNotCopyYet: String? { permission.refusal?.sentence }

    init() { refresh() }

    func refresh() {
        isOn = BackgroundPieceService.isOn
        needsApproval = BackgroundPieceService.needsTheirApproval
        statusSentence = BackgroundPieceService.statusSentence
    }

    func set(_ on: Bool) {
        lastOutcome = on ? BackgroundPieceService.turnOn() : BackgroundPieceService.turnOff()
        refresh()
    }

    func showTheirLoginItems() { BackgroundPieceService.showTheirLoginItems() }
}
