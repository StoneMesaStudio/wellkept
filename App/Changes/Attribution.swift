// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  Attribution.swift
//  Wellkept — App/Changes
//
//  ⭐ **When something changed, and only as much of why as the evidence supports.**
//
//  ## ⛔ We can say WHEN. We can never say WHO.
//
//  Nothing an unprivileged app can read on macOS records which process wrote a setting, and the one
//  log that might forgets within a day. So there is no code in this file that names an app, there
//  is no `Cause` case that could hold one, and `ChangesCauseGuardTests` fails the build on anybody
//  adding either. Putting somebody's software on screen next to a security warning on the strength
//  of a coincidence is defamation with a nice typeface, and it would be wrong often.
//
//  ## What this file can actually establish, and the two sources it uses
//
//  | Source | Permission | What it gives |
//  |---|---|---|
//  | `/Library/Receipts/InstallHistory.plist` | **World-readable** (0664 root:admin) | Every install, 110 deep on this Mac, with a real date |
//  | `/usr/bin/last -y` | Readable here; **empty on a standard account** | Reboot and shutdown times, to the minute |
//  | `kern.boottime` | **None at all** | This boot, exact to the microsecond |
//  | `/private/var/log/shutdown_monitor.log`'s modification time | **World-readable** (0644 root:wheel) | The last shutdown, exact to the second |
//
//  ## ⚠️ The install record's dates are UTC
//
//  macOS 26.6.2 is stored as `2026-08-25T02:08:52Z` and happened on the **evening of the 24th**.
//  Read it as a day rather than as an instant and every update in this section lands a day out.
//
//  The plist stores a real `<date>`, so `PropertyListSerialization` hands back a correct `Date` and
//  the trap is not in the reading — it is in every later step that turns that instant into a day.
//  **Never use a UTC calendar on one of these.** `ChangesAttributionTests.the2662UpdateLandsOnThe24th`
//  pins the exact case, in a fixed time zone, so this cannot regress on a machine that happens to
//  be set to UTC.
//
//  ## ⚠️ A restart is not evidence of an update
//
//  **15 of this Mac's 25 recorded boots carried no update at all.** So a boot, on its own, can
//  never produce a `MacOSUpdate` — the install record has to name one inside the window first, and
//  the boot is then used only to measure how long the machine was off. There is deliberately no
//  function in this file that takes a boot and returns an update.
//
//  ## ⚠️ File timestamps are worthless as evidence — with one named exception
//
//  Three quarters of the preference files on this Mac were rewritten inside a day by daemons that
//  changed nothing, which is why `Diff` compares values and never dates. `lastShutdown()` below
//  reads a file's modification time anyway, and the difference is that there the timestamp **is**
//  the event: `shutdown_monitor.log` is written as the machine goes down, and its last line is
//  "Saved shutdown report". It is used only to sharpen a shutdown instant that `last` already
//  reported to the minute, never to establish that a shutdown happened.
//
//  ## ⚠️ On a standard account the boot record is unreadable, and the wording gets weaker
//
//  We still know an update happened and when. We lose the ability to say the Mac was off — which is
//  exactly the evidence that made the claim strong. That is `.notGrantable`, not `.notPermitted`:
//  it is decided by the kind of account you sign in with, not by a privacy setting, so there is no
//  button to offer and the check still counts as complete. Same reasoning, same shape, as
//  `RestartReader`.

enum Attribution {

    // MARK: - Where the evidence lives

    /// The install record. World-readable, and the only place an ordinary account can learn that
    /// macOS was updated.
    static let installHistoryFile = URL(filePath: "/Library/Receipts/InstallHistory.plist")

    /// Written as the machine goes down. Only its modification time is read — never its contents.
    static let shutdownMarkerFile = URL(filePath: "/private/var/log/shutdown_monitor.log")

    static let lastTool = URL(filePath: "/usr/bin/last")

    /// How far apart an update's recorded time and a boot may be and still be treated as the same
    /// event.
    ///
    /// Ten of eleven updates on this Mac landed within two minutes of a recorded boot; the one
    /// measured here was 83 seconds. Ten minutes is generous on purpose — the install record is
    /// written by `softwareupdated` after the restart, so the two are never identical, and being
    /// slightly too willing to pair them costs a sentence that says "about eleven minutes" rather
    /// than a wrong claim.
    static let updateBootTolerance: TimeInterval = 10 * 60

    // MARK: - What one install record entry is

    /// One line of the install record.
    struct Install: Sendable, Hashable {
        /// "macOS 26.6.2", "Pages", "XProtectPlistConfigData".
        let name: String
        /// "26.6.2", where the record carries one.
        let version: String?
        /// ⚠️ An instant, not a day. See the file note.
        let installedAt: Date
        /// "softwareupdated", "appstoreagent". Kept because it is in the record, and used for
        /// nothing: it names the installer, not whatever later changed a setting.
        let process: String?

        /// Whether this line is macOS itself rather than an app or a data file.
        ///
        /// Apple writes the operating system as `macOS <version>` with no `contentType`. The
        /// XProtect and configuration-data entries share `softwareupdated` as their process, so
        /// the process name cannot be the test — `XProtectPlistConfigData` would otherwise be
        /// reported to somebody as a macOS update.
        var isMacOS: Bool { name.hasPrefix("macOS ") }
    }

    /// A stretch of time the Mac was running.
    struct BootSession: Sendable, Hashable {
        let startedAt: Date
        /// When it went down, where that was recorded. `nil` for a session that crashed, was cut
        /// by a power failure, or is the one currently running.
        let stoppedAt: Date?
        /// Both ends came from a second-precision source.
        let exact: Bool
    }

    // MARK: - Reading the install record

    /// Every install this Mac has a record of, oldest first. `nil` where the file could not be read
    /// at all — which on a normal Mac does not happen, since it is world-readable.
    static func installs(at file: URL = installHistoryFile) -> [Install]? {
        guard let data = try? Data(contentsOf: file),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let entries = raw as? [[String: Any]] else { return nil }

        return entries.compactMap { entry -> Install? in
            // ⚠️ A real `Date`, taken as an instant. The value in the file is UTC; Foundation has
            // already accounted for that, and every later step must keep working in the Mac's own
            // time zone rather than reaching for a UTC calendar.
            guard let date = entry["date"] as? Date else { return nil }
            let name = (entry["displayName"] as? String) ?? "Unnamed"
            return Install(name: name,
                           version: entry["displayVersion"] as? String,
                           installedAt: date,
                           process: entry["processName"] as? String)
        }
        .sorted { $0.installedAt < $1.installedAt }
    }

    /// The macOS updates recorded inside a window, oldest first.
    static func macOSUpdates(in window: Window, installs: [Install]) -> [Install] {
        installs.filter {
            $0.isMacOS && $0.installedAt >= window.after && $0.installedAt <= window.before
        }
    }

    // MARK: - Reading the boot record

    /// This boot, exact to the microsecond, readable by any account with no permission at all.
    static func currentBoot() -> Date? { SnapshotStore.bootedAt() }

    /// The most recent shutdown, exact to the second.
    ///
    /// See the file note on why this one file's timestamp is allowed to be evidence when no other
    /// file's is. `nil` where the file is absent — some Macs have never written one.
    static func lastShutdown(file: URL = shutdownMarkerFile,
                             fileManager: FileManager = .default) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: file.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    /// The reboot and shutdown times macOS still has a record of, newest first.
    ///
    /// ⚠️ **`LC_ALL=C` is load-bearing.** `last` prints its dates with the C library's month and
    /// weekday names, in whatever locale the process inherits. Wellkept has already shipped one bug
    /// of exactly this shape — the battery row compared Apple's English words on a Mac that may not
    /// be in English — so the subprocess is pinned to the POSIX locale and the parser uses
    /// `en_US_POSIX`. Neither half works without the other.
    ///
    /// `-y` prints the year. Without it the output is "Mon Aug 24 20:07" and every boot older than
    /// twelve months lands in the wrong one.
    ///
    /// Returns `nil` where the record could not be read — which is what a standard account gets.
    static func bootLines(timeout: TimeInterval = 6) -> [String]? {
        guard let text = run(lastTool, arguments: ["-y"], timeout: timeout) else { return nil }
        let lines = text.split(separator: "\n").map(String.init)
        return lines.isEmpty ? nil : lines
    }

    /// The date at the end of a `last -y` line, or `nil` for a line that is not one of ours.
    ///
    /// Matches on the leading word rather than on the whole shape, because the middle columns —
    /// tty, host, padding — differ between macOS releases and are not information we want.
    static func parseBootLine(_ line: String,
                              timeZone: TimeZone = .current) -> (kind: String, at: Date)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let kind: String
        if trimmed.hasPrefix("reboot") { kind = "reboot" }
        else if trimmed.hasPrefix("shutdown") { kind = "shutdown" }
        else { return nil }

        // "Mon Aug 24 2026 20:07" — the last five whitespace-separated tokens of the line.
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 5 else { return nil }
        let tail = tokens.suffix(5).joined(separator: " ")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE MMM d yyyy HH:mm"
        guard let date = formatter.date(from: tail) else { return nil }
        return (kind, date)
    }

    /// Turn `last`'s newest-first list into sessions, newest first.
    ///
    /// A reboot with no shutdown recorded before it is a crash or a power cut, and it gets
    /// `stoppedAt: nil` rather than an invented instant. There is no reading anywhere on macOS that
    /// distinguishes a power cut from a clean shutdown after the fact, so saying nothing is the
    /// only honest option.
    static func sessions(from lines: [String],
                         currentBoot: Date? = nil,
                         lastShutdown: Date? = nil,
                         timeZone: TimeZone = .current) -> [BootSession] {

        let events = lines.compactMap { parseBootLine($0, timeZone: timeZone) }
        var built: [BootSession] = []

        for (index, event) in events.enumerated() where event.kind == "reboot" {
            var start = event.at
            var stop: Date?
            var exact = false

            // The line immediately after a reboot, in newest-first order, is the shutdown that
            // preceded it — if there is one, and if nothing else intervened.
            if index + 1 < events.count, events[index + 1].kind == "shutdown" {
                stop = events[index + 1].at
            }

            // Sharpen both ends where a second-precision source describes the same minute. Same
            // minute rather than same instant: `last` truncates, so 20:07:29 prints as 20:07.
            let bootIsExact = currentBoot.map { sameMinute($0, start) } ?? false
            if bootIsExact, let currentBoot { start = currentBoot }

            if let recorded = stop, let lastShutdown, sameMinute(lastShutdown, recorded) {
                stop = lastShutdown
                // Both ends now come from a second-precision source, so the sentence may say
                // seconds. Either end short of that and it says "about four minutes" instead —
                // inventing 52 seconds out of two minute-resolution readings is exactly the kind of
                // confident wrong answer this app exists to avoid.
                exact = bootIsExact
            }

            built.append(BootSession(startedAt: start, stoppedAt: stop, exact: exact))
        }
        return built
    }

    /// The sessions this Mac can report, newest first. `nil` where the record is unreadable.
    static func bootSessions(timeZone: TimeZone = .current) -> [BootSession]? {
        guard let lines = bootLines() else { return nil }
        let sessions = sessions(from: lines,
                                currentBoot: currentBoot(),
                                lastShutdown: lastShutdown(),
                                timeZone: timeZone)
        return sessions.isEmpty ? nil : sessions
    }

    private static func sameMinute(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 60
    }

    // MARK: - ⭐ Putting it together

    /// Everything this file can say about one window between two snapshots.
    struct Verdict: Sendable {
        /// The cause every change in this window shares, unless a change has one of its own.
        let cause: Cause
        let confidence: Confidence
        /// The Mac was off for part of the window, and we measured it.
        ///
        /// ⚠️ **We can prove "off". We cannot prove "asleep".** Nothing unprivileged distinguishes
        /// a sleeping Mac from an idle one after the fact. The sentence says "asleep or switched
        /// off" because a person cannot tell those apart either, and because claiming to know which
        /// would be the confident wrong answer.
        let macWasOffOrAsleep: Bool
        /// Set where the boot record could not be read — a standard account.
        let outageUnreadable: Unreadable?
    }

    /// Read this Mac, then decide. What the section's button calls.
    static func verdict(for window: Window) -> Verdict {
        verdict(for: window, record: installs(), boots: bootSessions())
    }

    /// What can honestly be said about a window.
    ///
    /// ⚠️ **`nil` means "could not be read", and it is a different thing from an empty array.** A
    /// Mac with no updates in the window and a Mac whose install record we could not open are two
    /// different sentences, and collapsing them is how a section ends up reporting zero because it
    /// did not look. That is also why this takes the evidence rather than fetching it: a test can
    /// hand it a machine's history, including a history with holes in it.
    ///
    /// The order of the tests is the order of the evidence:
    ///
    /// 1. **A macOS update recorded inside the window** — the strongest thing available, and still
    ///    only `.consistent`. Two things happened in the same period; that is not evidence that one
    ///    caused the other.
    /// 2. **No update, and the Mac never went down** — somebody was at the machine. Still not who.
    /// 3. **Everything else** — `.unknown`, with no confidence claimed, which is the ordinary
    ///    answer and must read as ordinary.
    static func verdict(for window: Window,
                        record: [Install]?,
                        boots: [BootSession]?) -> Verdict {

        let bootRecordUnreadable: Unreadable? = boots == nil ? .notGrantable : nil

        // ⚠️ A boot alone proves nothing. The update has to be named in the install record first.
        let updates = record.map { macOSUpdates(in: window, installs: $0) } ?? []
        let wentDown = boots.map { outages(in: window, sessions: $0) } ?? []

        if let latest = updates.last {
            let outage = wentDown.first { overlaps($0, latest.installedAt) }
            let update = MacOSUpdate(version: latest.version ?? versionFromName(latest.name),
                                     installedAt: latest.installedAt,
                                     outage: outage)
            return Verdict(cause: .duringMacOSUpdate(update),
                           confidence: .consistent,
                           macWasOffOrAsleep: !wentDown.isEmpty,
                           outageUnreadable: bootRecordUnreadable)
        }

        if boots != nil, wentDown.isEmpty, record != nil {
            return Verdict(cause: .whileYouWereUsingTheMac,
                           confidence: .consistent,
                           macWasOffOrAsleep: false,
                           outageUnreadable: nil)
        }

        return Verdict(cause: .unknown,
                       confidence: .noEvidence,
                       macWasOffOrAsleep: !wentDown.isEmpty,
                       outageUnreadable: bootRecordUnreadable)
    }

    /// Every stretch inside the window during which the Mac was off.
    static func outages(in window: Window, sessions: [BootSession]) -> [Outage] {
        var found: [Outage] = []
        // Sessions arrive newest first; pair each start with the stop of the session before it in
        // time, which the parser has already attached.
        for session in sessions {
            guard let stopped = session.stoppedAt else { continue }
            guard session.startedAt > stopped else { continue }
            // The outage has to touch the window. A shutdown last March is not news today.
            guard session.startedAt >= window.after, stopped <= window.before else { continue }
            found.append(Outage(wentDown: stopped,
                                cameBack: session.startedAt,
                                precision: session.exact ? .toTheSecond : .toTheMinute))
        }
        return found.sorted { $0.cameBack > $1.cameBack }
    }

    private static func overlaps(_ outage: Outage, _ moment: Date) -> Bool {
        moment >= outage.wentDown.addingTimeInterval(-updateBootTolerance)
            && moment <= outage.cameBack.addingTimeInterval(updateBootTolerance)
    }

    /// "macOS 26.6.2" → "26.6.2", for the rare record with no `displayVersion`.
    static func versionFromName(_ name: String) -> String {
        let stripped = name.hasPrefix("macOS ") ? String(name.dropFirst(6)) : name
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - One short-lived subprocess

    /// Run a tool and read what it printed, with a watchdog.
    ///
    /// The same shape as `ReachableReader.run` and for the same reasons: the output is drained
    /// **before** `waitUntilExit`, because a child filling the pipe while the parent waits for it
    /// to exit is a deadlock that only shows up on the machine with the most to say.
    ///
    /// ⚠️ The environment is replaced rather than inherited, so the child cannot be handed a locale
    /// that changes how it prints a date. `PATH` is set because a process with none is a process
    /// that behaves differently from the one anybody tested.
    private static func run(_ tool: URL, arguments: [String], timeout: TimeInterval) -> String? {
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }

        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.environment = ["LC_ALL": "C", "LANG": "C",
                               "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        let box = Watchdog(process)
        let killer = DispatchWorkItem { box.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// One reference, read from two threads, and all either of them does is ask whether the process
    /// is still running.
    private final class Watchdog: @unchecked Sendable {
        private let process: Process
        init(_ process: Process) { self.process = process }
        func terminate() { if process.isRunning { process.terminate() } }
    }
}
