// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import Observation
import WellkeptCore

//  ChangesModel.swift
//  Wellkept — App/Sections/Changes
//
//  **The one place the Changes check is actually run**, and the one row it sends up to Overview.
//
//  Same shape as `SecurityModel` and `AppsModel`: a detached read, one report, one finding. The
//  section is the fifth instance of a pattern rather than a new design, and a person who has
//  learned the Security screen has already learned this one.
//
//  ## ⚠️ Changes does not run on launch, and this file is where that promise is kept
//
//  The read is the Security section's read — protections through `system_profiler`, sockets through
//  `lsof`, the privacy database, the startup files — which is about eight seconds. A section that
//  spent that on every launch would make the app feel broken. So there is no launch check here.
//
//  ⚠️ **The snapshot is a different thing from the check, and it must not be confused with one.**
//  Taking a snapshot costs under a second and belongs on every launch, because *a record cannot be
//  back-filled*. Comparing two snapshots and explaining the difference is what this model does, and
//  it happens on a press. Whoever wires the launch snapshot must not reach for `check()` to do it.
//
//  ## ⚠️ Why this reads for itself rather than borrowing Security's reading
//
//  `Diff` wants raw readings — every protection's printed state, every socket, every grant.
//  Security's readers hand back finished `SecurityRow`s instead, with the raw material already
//  spent. Reaching into six readers to recover it would couple this section to the inside of
//  another one for the sake of eight seconds a person asked for by pressing a button.
//
//  What matters is the rule `Diff` actually states: **`live()` is called at most once per check.**
//  There is exactly one call below, and the reading it produces is handed to `Diff.run` rather than
//  letting `run` fetch its own.

@MainActor
@Observable
final class ChangesModel {

    // MARK: What the screen draws

    /// The last report. `nil` until the first check finishes — the ordinary state on every launch,
    /// because nothing starts this but a press.
    private(set) var report: ChangesReport?

    private(set) var isChecking = false

    /// What it is doing at this moment. `nil` when nothing is running.
    private(set) var stage: Stage?

    // MARK: - The stages

    /// Two honest steps, in the order they happen.
    ///
    /// The first is the whole cost — the same readers Security waits on. The second is arithmetic
    /// over two files and is effectively instant, and it is still named, because "comparing" is the
    /// step a person came here for and a progress line that never mentions it looks like it never
    /// happened.
    enum Stage: String, CaseIterable, Sendable, Hashable {
        case reading
        case comparing

        var sentence: String {
            switch self {
            case .reading:
                "Reading the settings Wellkept watches — this takes a few seconds…"
            case .comparing:
                "Recording them, and comparing with the last time we looked…"
            }
        }

        /// How far through the run this is, one-based, for the count beside the spinner.
        var step: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

        static var count: Int { allCases.count }
    }

    // MARK: - Running it

    /// **Read the machine, record a snapshot, and say what changed.**
    ///
    /// Safe to call again; a second call while one is running is ignored rather than queued.
    ///
    /// Both halves run detached. The readers block — subprocesses, property lists and a SQLite
    /// file — and none of that may happen where the window is waiting to draw.
    func check(now: Date = Date()) async {
        guard !isChecking else { return }
        isChecking = true
        defer {
            isChecking = false
            stage = nil
        }

        stage = .reading
        let readings = await Task.detached(priority: .userInitiated) {
            Diff.live()
        }.value

        stage = .comparing
        report = await Task.detached(priority: .userInitiated) {
            Diff.run(now: now, readings: readings)
        }.value
    }
}

// MARK: - The one row that goes up to Overview

extension ChangesReport {

    /// **At most one row, whatever this section found.**
    ///
    /// A section that posts a row per change turns Overview into a second copy of itself, and the
    /// section a person should actually open gets lost among its own details. The same rule
    /// Hardware, Security, Apps and Storage all follow.
    ///
    /// ⚠️ **Nothing is filed on a first look, and nothing is filed on a quiet one.** The audit trail
    /// already carries both — "Not checked" the first time, "Good" afterwards — and a row saying
    /// nothing changed is a row that has to be read to learn nothing.
    ///
    /// ⚠️ **The severity is `worst`, which cannot exceed `.attention`.** A change is a change;
    /// whether the resulting state is a problem is Security's question, answered there once.
    var overviewFinding: Finding? {
        guard !isFirstLook, !changes.isEmpty else { return nil }

        let since = previous.map { " since \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        let title = changes.count == 1
            ? "One thing Wellkept watches changed\(since)"
            : "\(changes.count) things Wellkept watches changed\(since)"

        // The strongest one, in its own words — the sentence that already carries what moved, when,
        // and how much of "why" the evidence supports. Never re-composed here.
        let reason = ordered.first?.sentence(now: ranAt) ?? summary

        return Finding(id: Self.stableID("changes|\(title)|\(reason)"),
                       section: .changes,
                       title: title,
                       reason: reason,
                       severity: worst,
                       measure: nil,
                       // ⛔ No verb. Wellkept writes no setting, ever — there is nowhere for a
                       // button on this row to go that is not System Settings, and Overview is not
                       // where somebody should be sent to it.
                       verb: nil)
    }

    // MARK: - A row that keeps its identity between draws

    /// A `UUID` derived from the row's own words rather than minted fresh.
    ///
    /// ⚠️ **`Finding.id` defaults to a new `UUID` every time it is read, and `overviewFinding` is a
    /// computed property** — the other four sections dodge this by storing their finding in the
    /// report's initialiser, which `ChangesReport` does not do. A row whose identity changed on
    /// every redraw would make Overview animate its own list to pieces, and it took Waypoint two
    /// weeks to find that the last time.
    ///
    /// FNV-1a rather than `Hasher`, because `Hasher` is seeded per process: the same report would
    /// then produce a different id in the shot harness than in the app, which is the sort of
    /// difference that makes a picture disagree with the screen it is a picture of.
    static func stableID(_ text: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01b3
            }
            return hash
        }
        let a = fnv(0xcbf2_9ce4_8422_2325), b = fnv(0x9e37_79b9_7f4a_7c15)
        var bytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((a >> UInt64(shift)) & 0xff)) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((b >> UInt64(shift)) & 0xff)) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6],
                           bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12],
                           bytes[13], bytes[14], bytes[15]))
    }
}
