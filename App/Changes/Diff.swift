// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  Diff.swift
//  Wellkept — App/Changes
//
//  ⭐ **What is different, worked out by comparing values — never dates.**
//
//  ## ⚠️ The measurement this whole file is built on
//
//  **Three quarters of the preference files on this Mac were rewritten inside a day by daemons that
//  changed nothing.** A modification date therefore proves nothing at all, and a section built on
//  one would report a settled Mac as churning every time somebody opened it. So there is not a
//  single comparison of a timestamp anywhere below: two stored values are equal or they are not.
//
//  The corollary, measured the same day: **an idle Mac moved seven domains out of 2,186 in three
//  minutes, and not one of them was a setting.** The noise is real, small and nameable, and it is
//  named in `SnapshotStore.churnDomains`.
//
//  ## It does not re-read the world
//
//  Everything this section describes is already read by the Security section's readers, so `Diff`
//  takes their output rather than going back to the disk. `Readings.live()` exists for a caller
//  that has no reading to hand; a caller that has just run Security should build `Readings` from
//  what it already has, because running `ProtectionReader` twice costs eight seconds of somebody's
//  afternoon to learn nothing.
//
//  ## ⚠️ Undescribed changes are counted, never listed
//
//  A difference in the full capture that no `Watched` describes adds one to a number. It never
//  becomes a row. The scope was settled on 2026-08-28: version one describes the thirty-odd things
//  Wellkept already understands, and the general settings journal — the part that needs a curated
//  description for every key on the Mac — waits for version two. A row nobody can explain is a row
//  that worries somebody for no reason, which is precisely the trap the deferred half is full of.

enum Diff {

    // MARK: - What the section compares

    /// Everything the described half of this section needs, gathered once.
    ///
    /// Deliberately plain values rather than the reader types: this struct is what a test builds by
    /// hand, and a test that has to construct a `ProtectionsBlock` and a socket list to check a
    /// sentence is a test nobody writes.
    struct Readings: Sendable {
        /// Each protection's state as the row prints it — "On", "Off", "Reduced".
        var protections: [ProtectionKind: String] = [:]
        /// Protections that could not be read, and why.
        var protectionsUnreadable: [ProtectionKind: Unreadable] = [:]
        /// Protections an organisation's profile forces. **Never a fault**, and the one cause we
        /// can state outright.
        var protectionsSetByOrganisation: Set<ProtectionKind> = []

        /// Whether each sharing service was seen listening.
        var listening: [ReachableReader.Service: Bool] = [:]

        /// How many things start on their own, by where they were found.
        var startupCounts: [StartupReader.Origin: Int] = [:]
        var startupUnreadable: [StartupReader.Origin: Unreadable] = [:]

        /// Every app-and-permission pair, by bundle identifier.
        var grants: [Grant] = []
        /// True when Full Disk Access was refused, which collapses the whole grant list to nothing.
        var grantsRefused = false

        var systemVersion: String?
    }

    /// The values a snapshot stores, and the ones it could not read.
    ///
    /// ⚠️ **An absent key means "we did not look then", not "it was different".** Every launch takes
    /// a snapshot, and most launches will not have run the Security readers — so a comparison that
    /// treated absence as a change would report the whole section as having moved every other time
    /// the app was opened.
    static func values(from readings: Readings) -> (watched: [String: String],
                                                    unreadable: [String: String]) {
        var watched: [String: String] = [:]
        var unreadable: [String: String] = [:]

        for kind in ProtectionKind.allCases {
            let key = WatchedKey(.protections, kind.rawValue)
            if let why = readings.protectionsUnreadable[kind] {
                unreadable[key.storageKey] = why.rawValue
            } else if let state = readings.protections[kind] {
                watched[key.storageKey] = state
            }
        }

        for service in ReachableReader.Service.allCases {
            guard let isListening = readings.listening[service] else { continue }
            let key = WatchedKey(.reachableFrom, service.rawValue)
            // ⚠️ The exact phrase the Security reader prints, and it is not "Off". macOS gives no
            // reading that proves a sharing service is switched off, so a snapshot must never
            // record one as off — a later build comparing against "Off" would find a change that
            // never happened.
            watched[key.storageKey] = isListening ? "Listening" : "Not seen listening"
        }

        for origin in describedStartupOrigins {
            let key = WatchedKey(.startsOnItsOwn, origin.rawValue)
            if let why = readings.startupUnreadable[origin] {
                unreadable[key.storageKey] = why.rawValue
            } else if let count = readings.startupCounts[origin] {
                watched[key.storageKey] = String(count)
            }
        }

        if readings.grantsRefused {
            for permission in WellkeptCore.Permission.allCases {
                unreadable[WatchedKey(.whoCanWatch, permission.rawValue).storageKey] =
                    Unreadable.notPermitted.rawValue
            }
        } else {
            for grant in readings.grants where !grant.isWellkept {
                let key = instanceKey(WatchedKey(.whoCanWatch, grant.permission.rawValue),
                                      instance: grant.bundleID)
                watched[key] = "Allowed"
            }
        }

        if let version = readings.systemVersion {
            watched[WatchedKey(.macOSItself, "systemVersion").storageKey] = version
        }

        return (watched, unreadable)
    }

    /// The four startup origins this section describes.
    ///
    /// `appBundled` is absent on purpose: macOS decides whether those run and we cannot read that
    /// decision, so a change in the count would be a change in what we found rather than in what
    /// starts. `globalAgent` is absent because it and `userAgent` are one thing to a person — the
    /// count is folded into `userAgent` by the caller.
    static let describedStartupOrigins: [StartupReader.Origin] =
        [.userAgent, .globalDaemon, .cron, .configurationProfile]

    // MARK: - Keys with an instance attached

    //  ⚠️ A privacy grant is not one value, it is one value per app. So the map key carries the
    //  app's bundle identifier after the `WatchedKey`, separated by the same control character
    //  `SnapshotStore` uses — it cannot appear in either half, so the two are always separable.
    //
    //  The **bundle identifier**, never the app's name. A name changes when a developer renames
    //  their app, and a renamed app would otherwise read as one permission lost and another gained
    //  by something new — which is exactly the alarming sentence this section must not print
    //  without cause.

    static func instanceKey(_ key: WatchedKey, instance: String?) -> String {
        guard let instance, !instance.isEmpty else { return key.storageKey }
        return "\(key.storageKey)\u{1}\(instance)"
    }

    static func parse(_ mapKey: String) -> (key: WatchedKey, instance: String?)? {
        if let separator = mapKey.firstIndex(of: "\u{1}") {
            let head = String(mapKey[mapKey.startIndex..<separator])
            let instance = String(mapKey[mapKey.index(after: separator)...])
            guard let key = WatchedKey(storageKey: head) else { return nil }
            return (key, instance.isEmpty ? nil : instance)
        }
        guard let key = WatchedKey(storageKey: mapKey) else { return nil }
        return (key, nil)
    }

    // MARK: - ⭐ The comparison

    /// The differences between two snapshots' described values.
    ///
    /// ⚠️ **A key present in only one snapshot is not a change**, with one exception. If the earlier
    /// snapshot never recorded FileVault, we did not look; reporting that as "FileVault appeared"
    /// would be reporting our own scheduling. The exception is a **privacy grant**, where the
    /// appearance or disappearance of a key genuinely is the news — an app gained a permission, or
    /// lost one — because those keys exist only while the grant does.
    static func changes(from earlier: Snapshot,
                        to later: Snapshot,
                        window: Window,
                        cause: Cause,
                        confidence: Confidence,
                        organisationSets: Set<WatchedKey> = [],
                        names: [String: String] = [:]) -> [Change] {

        var found: [Change] = []

        func add(_ key: WatchedKey, instance: String?, from: String, to: String) {
            guard let watched = Watched.of(key) else { return }   // counted elsewhere, never listed
            let what = instance.map { "\(names[$0] ?? $0) — \(watched.title)" } ?? watched.title
            let theCause: WellkeptCore.Cause = organisationSets.contains(key)
                ? .setByAnOrganisation : cause
            found.append(Change(key: key, what: what, from: from, to: to,
                                window: window, cause: theCause, confidence: confidence))
        }

        for (mapKey, newValue) in later.watched {
            guard let (key, instance) = parse(mapKey) else { continue }
            if let oldValue = earlier.watched[mapKey] {
                guard oldValue != newValue else { continue }
                add(key, instance: instance, from: oldValue, to: newValue)
            } else if key.topic == .whoCanWatch, instance != nil, !earlier.watched.isEmpty {
                // An app that did not hold this permission and now does.
                add(key, instance: instance, from: "Not allowed", to: newValue)
            }
        }

        // A permission that has gone. Only for grants, and only when the earlier snapshot actually
        // read them — otherwise a launch that skipped the readers would report every app on the Mac
        // as having lost everything.
        let laterReadGrants = later.watched.keys.contains { parse($0)?.key.topic == .whoCanWatch }
        if laterReadGrants {
            for (mapKey, oldValue) in earlier.watched where later.watched[mapKey] == nil {
                guard let (key, instance) = parse(mapKey), key.topic == .whoCanWatch,
                      instance != nil else { continue }
                add(key, instance: instance, from: oldValue, to: "Not allowed")
            }
        }

        return found
    }

    /// How many values in the full capture moved without being anything we describe.
    ///
    /// ⚠️ **Counted, never listed.** And counted only when both snapshots actually captured
    /// settings: an empty capture on either side would otherwise report the entire Mac as changed
    /// the first time a capture failed.
    ///
    /// Wellkept's own domain is excluded. Our preferences moving because somebody opened our own
    /// Settings window is our noise, not the Mac's, and reporting it would be the app pointing at
    /// itself.
    static func undescribed(from earlier: Snapshot,
                            to later: Snapshot,
                            ourBundleID: String? = Bundle.main.bundleIdentifier) -> Int {
        guard !earlier.settings.isEmpty, !later.settings.isEmpty else { return 0 }

        func skip(_ settingKey: String) -> Bool {
            guard let (domain, _) = SnapshotStore.split(settingKey) else { return true }
            if SnapshotStore.isChurn(domain) { return true }
            if let ourBundleID, domain == ourBundleID { return true }
            return false
        }

        var count = 0
        for (key, value) in later.settings where !skip(key) {
            if earlier.settings[key] != value { count += 1 }
        }
        for key in earlier.settings.keys where later.settings[key] == nil && !skip(key) {
            count += 1
        }
        return count
    }

    // MARK: - ⭐ The section's answer

    /// Compare the two most recent snapshots and say what can honestly be said.
    ///
    /// `verdict` is injectable so the whole report can be exercised against a known machine
    /// history — including one with holes in it — rather than only against whatever this Mac
    /// happens to have done lately.
    static func report(earlier: Snapshot?,
                       latest: Snapshot?,
                       now: Date = Date(),
                       organisationSets: Set<WatchedKey> = [],
                       names: [String: String] = [:],
                       verdict: Attribution.Verdict? = nil) -> ChangesReport {

        guard let latest else {
            return ChangesReport(ranAt: now, previous: nil, changes: [])
        }

        // ⚠️ A comparison across a change of machine is not a comparison. Migration Assistant
        // carries this file to a new Mac, and every setting on the new one would read as a change
        // made by somebody. It is honestly a first look, and it says so.
        guard let earlier, latest.comparable(with: earlier) else {
            return ChangesReport(ranAt: now, previous: nil, changes: [],
                                 unreadable: unread(latest))
        }

        let outline = Window(after: earlier.takenAt, before: latest.takenAt)
        let verdict = verdict ?? Attribution.verdict(for: outline)
        let window = Window(after: earlier.takenAt,
                            before: latest.takenAt,
                            macWasOffOrAsleep: verdict.macWasOffOrAsleep)

        let differences = changes(from: earlier, to: latest, window: window,
                                  cause: verdict.cause, confidence: verdict.confidence,
                                  organisationSets: organisationSets, names: names)

        return ChangesReport(ranAt: now,
                             previous: earlier.takenAt,
                             changes: differences,
                             undescribed: undescribed(from: earlier, to: latest),
                             unreadable: unread(latest),
                             privacyChangedButUnreadable: privacyWentDark(earlier, latest),
                             macWasOffOrAsleep: verdict.macWasOffOrAsleep,
                             outageUnreadable: verdict.outageUnreadable)
    }

    /// Everything the latest snapshot was **refused**.
    ///
    /// ⚠️ **`.notReported` is recorded in the snapshot and dropped from the report, and the two are
    /// different jobs.** Lockdown Mode is unreadable on every Mac Apple has ever shipped, so
    /// keeping it in the record is worth something — the day Apple starts publishing it, the change
    /// is visible — while putting it on the face every launch is a caveat that can never be cleared
    /// on any machine. That is precisely how an app teaches people to stop reading its caveats, and
    /// this section already banned it once for Overview. Security says it once, on its own row, and
    /// that is the right number of times.
    static func unread(_ snapshot: Snapshot) -> [ChangesReport.Unread] {
        snapshot.unreadable.compactMap { mapKey, raw -> ChangesReport.Unread? in
            guard let (key, _) = parse(mapKey), let why = Unreadable(rawValue: raw),
                  why.wasRefused else { return nil }
            return ChangesReport.Unread(key: key, why: why)
        }
        .sorted { $0.key < $1.key }
        .reduce(into: [ChangesReport.Unread]()) { unique, item in
            // One line per topic, not one per permission. **Answer 4, 2026-08-28**: the
            // Full Disk Access line is shown once and never repeated per permission.
            if !unique.contains(where: { $0.key.topic == item.key.topic }) { unique.append(item) }
        }
    }

    /// ⭐ **Answer 4, 2026-08-28** — the one line saying privacy permissions changed and we
    /// could not see what, with the button that grants access.
    ///
    /// ## ⚠️ What this actually detects, and what it deliberately does not
    ///
    /// It fires when the grants were readable at one of the two moments and not at the other: the
    /// person granted Full Disk Access and then took it away, or the reverse. That is a real change
    /// in what can be seen, and the honest sentence is that we cannot say what moved underneath it.
    ///
    /// It does **not** watch the permission database itself, which would catch more. Reaching for
    /// `~/Library/Application Support/com.apple.TCC` is exactly the kind of speculative touch that
    /// puts a privacy dialog on somebody's screen naming a process they did not start — macOS
    /// raises that on the **attempt**, not on the failure, and it has already happened twice on
    /// this Mac while the Apps section was being written. Catching one more case is not worth
    /// being the cause of that dialog.
    static func privacyWentDark(_ earlier: Snapshot, _ later: Snapshot) -> Bool {
        func couldSee(_ snapshot: Snapshot) -> Bool? {
            let refused = WellkeptCore.Permission.allCases.contains {
                snapshot.unreadable(WatchedKey(.whoCanWatch, $0.rawValue)) == .notPermitted
            }
            if refused { return false }
            let read = snapshot.watched.keys.contains { parse($0)?.key.topic == .whoCanWatch }
            return read ? true : nil     // nil: this launch did not look either way
        }
        guard let before = couldSee(earlier), let after = couldSee(later) else { return false }
        return before != after
    }

    // MARK: - Reading the machine, once

    /// Gather everything from the readers that already exist.
    ///
    /// ⚠️ **Call this at most once per check.** `ProtectionReader` runs `system_profiler` with an
    /// eight-second watchdog and `ReachableReader` runs `lsof`; a caller that has just produced a
    /// Security report already holds all of this and should build `Readings` from that instead.
    static func live(fullDiskAccess: Bool = FullDiskAccess.isGranted) -> Readings {
        var readings = Readings()

        let protections = ProtectionReader.read()
        for protection in protections.block.protections {
            if let why = protection.state.unreadable {
                readings.protectionsUnreadable[protection.kind] = why
            } else {
                readings.protections[protection.kind] = protection.state.label
            }
            if protection.setByOrganisation { readings.protectionsSetByOrganisation.insert(protection.kind) }
        }

        let survey = ReachableReader.survey()
        let observations = ReachableReader.observations(from: survey.sockets)
        for service in ReachableReader.Service.allCases {
            let standing = observations.first { $0.service == service }?.standing
            readings.listening[service] = standing?.isListening ?? false
        }

        let startup = StartupReader.survey()
        var counts: [StartupReader.Origin: Int] = [:]
        for item in startup.items where !item.disabled { counts[item.origin, default: 0] += 1 }
        // Login items are one idea to a person: an agent that starts for this account and one that
        // starts for every account are both "things that start when I log in".
        readings.startupCounts[.userAgent] = (counts[.userAgent] ?? 0) + (counts[.globalAgent] ?? 0)
        readings.startupCounts[.globalDaemon] = counts[.globalDaemon] ?? 0
        readings.startupCounts[.cron] = counts[.cron] ?? 0
        readings.startupCounts[.configurationProfile] = counts[.configurationProfile] ?? 0
        if let why = startup.cronUnreadable { readings.startupUnreadable[.cron] = why }
        if let why = startup.profilesUnreadable { readings.startupUnreadable[.configurationProfile] = why }

        let grants = GrantReader.read(fullDiskAccess: fullDiskAccess)
        readings.grantsRefused = grants.wasRefused
        readings.grants = grants.grants

        readings.systemVersion = SnapshotStore.systemVersion()
        return readings
    }

    /// Which watched keys an organisation's profile is forcing.
    ///
    /// ⚠️ **Never a fault.** A Mac whose settings were chosen by an employer is not a Mac with
    /// something wrong with it, and a health check that says otherwise is an accusation aimed at
    /// somebody who cannot act on it. `Change.severity` drops the colour for these, exactly as
    /// `SecurityReport` does.
    static func organisationSets(_ readings: Readings) -> Set<WatchedKey> {
        var keys = Set<WatchedKey>()
        for kind in ProtectionKind.allCases where readings.protectionsSetByOrganisation.contains(kind)
            || ManagedMac.sets(kind) {
            keys.insert(WatchedKey(.protections, kind.rawValue))
        }
        return keys
    }

    /// Bundle identifier to app name, so a grant row can say "Zoom" rather than "us.zoom.xos".
    static func names(_ readings: Readings) -> [String: String] {
        Dictionary(readings.grants.map { ($0.bundleID, $0.appName) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - The whole run, end to end

    /// Read the machine, record a snapshot, and say what changed since the last one.
    ///
    /// This is what the section's button does.
    static func run(now: Date = Date(),
                    home: URL = StorageManifest.home(),
                    readings: Readings? = nil) -> ChangesReport {
        let gathered = readings ?? live()
        let (watched, unreadable) = values(from: gathered)

        let earlier = SnapshotStore.latest(home: home)
        let latest = SnapshotStore.take(watched: watched, unreadable: unreadable,
                                        now: now, home: home)

        return report(earlier: earlier,
                      latest: latest,
                      now: now,
                      organisationSets: organisationSets(gathered),
                      names: names(gathered))
    }
}
