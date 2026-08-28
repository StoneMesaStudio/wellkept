// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  Expiry.swift
//  Wellkept — App/Quarantine
//
//  ⭐ **The thirty days.**
//
//  John's answer, 2026-08-28: **thirty CALENDAR days**, not days the app happened to be open. And
//  **the user chooses**, in Settings, between *remove them at thirty days* and *tell me at thirty
//  days*. **Manual is the default.**
//
//  ## Why "auto" does not break "nothing changes the Mac on a schedule"
//
//  Wellkept ships no background piece — no helper, no login item, no agent — and building one is not
//  on the table. So automatic removal can only ever happen **the next time Wellkept is opened**, and
//  when it does the app **says what it removed**.
//
//  That is the whole reason it is allowed. It is not the app acting unbidden on a timer; it is the
//  person's own standing instruction being carried out in front of them, the first moment they are
//  there to see it. *Automatic means looking. Manual means touching* — and this is the one place the
//  user is permitted to convert a manual verb into a standing one, because they said so, by name, in
//  Settings.
//
//  ⚠️ **Nothing here may ever be moved onto a timer, a scheduled task, or a launch agent.** If a
//  future version ships a background piece, this decision is re-opened with John before a single
//  line here changes.
//
//  ## Manual, which is the default
//
//  At thirty days the item **rises to the top of the quarantine screen, marked ready to remove, and
//  waits.** An item nobody acknowledges waits for ever. That is not an oversight: the alternative is
//  an app that eventually deletes somebody's file because they were busy, which is the failure the
//  whole quarantine exists to prevent.
//
//  ## Two different ways of counting, on purpose
//
//  - **Whether it is ready** is calendar arithmetic: `quarantinedOn` plus thirty days, by the
//    calendar, so a daylight-saving change cannot make it a day early or a day late.
//  - **What the row says** — "12 days old" — counts day boundaries, because that is what a person
//    means by "days ago". An item set aside at 23:50 last night is "1 day old" this morning and not
//    "0 days old", which would read as a bug.
//
//  They are deliberately not the same function. Using day-boundary counting for expiry would make an
//  item set aside at 23:59 ready after twenty-nine days and one minute.

// MARK: - The setting

/// What happens at thirty days. **Manual is the default and John chose it.**
enum ExpiryMode: String, CaseIterable, Sendable, Identifiable {

    /// The item is marked ready and waits. Nothing is removed until somebody presses the button.
    case manual

    /// The next time Wellkept is opened, anything past thirty days is removed, and the app says so.
    case auto

    var id: String { rawValue }

    /// What the Settings row says.
    var label: String {
        switch self {
        case .manual: "Tell me when they reach \(Expiry.days) days"
        case .auto:   "Remove them at \(Expiry.days) days"
        }
    }

    /// The sentence under the row. It states the limitation rather than hiding it — an app that
    /// implied it was watching the clock while closed would be lying about what it is.
    var explanation: String {
        switch self {
        case .manual:
            "Items you set aside move to the top of the list after \(Expiry.days) days and wait "
            + "there until you remove them. Wellkept never removes anything on its own."
        case .auto:
            "The next time you open Wellkept, anything you set aside more than \(Expiry.days) days "
            + "ago is removed, and Wellkept tells you what it removed. Nothing happens while "
            + "Wellkept is closed — it has no part that runs in the background."
        }
    }
}

// MARK: - The thirty days

enum Expiry {

    /// Thirty. Calendar days.
    static let days = 30

    /// The stored preference. Declared in `StorageManifest.Keys`, like every other key the app
    /// writes, so the uninstaller cannot go stale.
    static let settingsKey = StorageManifest.Keys.quarantineExpiry

    /// ⚠️ **Absent means manual**, and that is a real default rather than a migration — a fresh
    /// install with nothing stored lands here too, and so does a stored value this build does not
    /// recognise. Nobody is opted into automatic removal by a missing key.
    static func mode(defaults: UserDefaults = .standard) -> ExpiryMode {
        ExpiryMode(rawValue: defaults.string(forKey: settingsKey) ?? "") ?? .manual
    }

    static func setMode(_ mode: ExpiryMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: settingsKey)
    }

    // MARK: When something is ready

    /// The day an item becomes ready to remove: thirty days by the calendar.
    static func readyOn(_ record: QuarantineRecord,
                        calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: record.quarantinedOn)
            // `date(byAdding:)` returns nil only for a calendar that cannot represent the result,
            // which none of ours can hit. Falling back to plain arithmetic keeps the item from
            // becoming permanently un-expirable if it ever did.
            ?? record.quarantinedOn.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    static func isReady(_ record: QuarantineRecord,
                        now: Date = Date(),
                        calendar: Calendar = .current) -> Bool {
        now >= readyOn(record, calendar: calendar)
    }

    /// Everything past thirty days.
    static func ready(among records: [QuarantineRecord],
                      now: Date = Date(),
                      calendar: Calendar = .current) -> [QuarantineRecord] {
        records.filter { isReady($0, now: now, calendar: calendar) }
    }

    // MARK: What the row says

    /// Whole days between two moments, counted by day boundary — what a person means by "days ago".
    static func calendarDays(from start: Date, to end: Date,
                             calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: start)
        let b = calendar.startOfDay(for: end)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    static func daysHeld(_ record: QuarantineRecord, now: Date = Date(),
                         calendar: Calendar = .current) -> Int {
        calendarDays(from: record.quarantinedOn, to: now, calendar: calendar)
    }

    /// Days still to run. Zero once it is ready.
    static func daysLeft(_ record: QuarantineRecord, now: Date = Date(),
                         calendar: Calendar = .current) -> Int {
        isReady(record, now: now, calendar: calendar)
            ? 0
            : calendarDays(from: now, to: readyOn(record, calendar: calendar), calendar: calendar)
    }

    /// The age line on the row. **Never a countdown for something already ready** — a person looking
    /// at "0 days left" cannot tell it from a bug.
    static func ageSentence(_ record: QuarantineRecord, now: Date = Date(),
                            calendar: Calendar = .current) -> String {
        if isReady(record, now: now, calendar: calendar) {
            return "Set aside \(daysHeld(record, now: now, calendar: calendar)) days ago — ready to "
                 + "remove."
        }
        let held = daysHeld(record, now: now, calendar: calendar)
        switch held {
        case 0:  return "Set aside today."
        case 1:  return "Set aside yesterday."
        default: return "Set aside \(held) days ago."
        }
    }

    /// The screen's order: **ready first, oldest first within each group.**
    ///
    /// John's shape — at thirty days the item *rises to the top* and waits there. A list that sorted
    /// only by date would bury a ready item under a week of newer ones.
    static func sortedForTheScreen(_ records: [QuarantineRecord],
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> [QuarantineRecord] {
        records.sorted { left, right in
            let leftReady = isReady(left, now: now, calendar: calendar)
            let rightReady = isReady(right, now: now, calendar: calendar)
            if leftReady != rightReady { return leftReady }
            return left.quarantinedOn < right.quarantinedOn
        }
    }

    // MARK: Opening the app

    /// What the sweep did, if anything.
    struct LaunchSweep: Sendable {
        let mode: ExpiryMode
        /// Everything past thirty days at the moment the app was opened.
        let wereReady: [QuarantineRecord]
        /// The delete, in `auto`. `nil` in `manual`, where nothing is removed.
        let report: Quarantine.DeleteReport?

        var removed: [QuarantineRecord] { report?.deleted ?? [] }

        /// ⚠️ **What the app says out loud.** In `auto` this is not optional politeness — it is the
        /// thing that makes automatic removal the user's own instruction rather than the app acting
        /// behind their back. `nil` only when there is genuinely nothing to say.
        var sentence: String? {
            switch mode {
            case .manual:
                guard !wereReady.isEmpty else { return nil }
                return wereReady.count == 1
                    ? "1 item you set aside has been in quarantine \(Expiry.days) days and is ready "
                      + "to remove."
                    : "\(wereReady.count) items you set aside have been in quarantine "
                      + "\(Expiry.days) days and are ready to remove."
            case .auto:
                guard let report, !report.deleted.isEmpty else { return nil }
                return "You asked Wellkept to remove things after \(Expiry.days) days. "
                     + report.sentence
            }
        }
    }

    /// Run when the window opens, and never at any other time.
    ///
    /// ⚠️ **This is the only automatic destructive action in Wellkept, and it exists only because
    /// the user asked for it by name in Settings.** In `manual` — the default — it removes nothing
    /// and only counts. Anything that makes this run from a timer, a notification, or a background
    /// task is a change John has to agree to first.
    @discardableResult
    static func sweepOnOpening(home: URL = StorageManifest.home(),
                               now: Date = Date(),
                               calendar: Calendar = .current,
                               defaults: UserDefaults = .standard) -> LaunchSweep {
        let mode = mode(defaults: defaults)
        let reading = Quarantine.reading(home: home)

        // ⚠️ An unreadable ledger removes NOTHING, in either mode. Deleting on the strength of a
        // record we could not read is exactly the shape of every accident on the list.
        guard reading.isTrustworthy else {
            return LaunchSweep(mode: mode, wereReady: [], report: nil)
        }

        let ready = ready(among: reading.records, now: now, calendar: calendar)
        guard mode == .auto, !ready.isEmpty else {
            return LaunchSweep(mode: mode, wereReady: ready, report: nil)
        }

        let report = Quarantine.delete(ready, expecting: ready.count, home: home)
        return LaunchSweep(mode: mode, wereReady: ready, report: report)
    }
}
