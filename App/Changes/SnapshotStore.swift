// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import CryptoKit
import Foundation
import WellkeptCore

//  SnapshotStore.swift
//  Wellkept — App/Changes
//
//  ⭐ **What this Mac's settings were, at every launch, kept from the first one.**
//
//  ## Why it writes before anything reads it
//
//  Nothing in this version reads `Snapshot.settings` back. It is captured anyway, in full, from the
//  first launch, because **a record cannot be back-filled.** It is the same argument that put
//  `ReadingHistory` in before anything needed it, and it is the argument that settled the Changes
//  scope on: version one *describes* about thirty things it understands, version two describes
//  hundreds — and version two arrives with a year of history rather than an empty file, but only if
//  version one was already writing.
//
//  ## What it actually costs, measured on one real Mac on 2026-08-28
//
//  | | |
//  |---|---|
//  | Preference domains found | **1,409** in `~/Library/Preferences`, plus the global domain |
//  | Key/value pairs captured | **11,224** |
//  | Time to capture all of it | **0.16 seconds** |
//  | One snapshot as JSON | **about 1 MB** |
//  | Values that moved on an idle Mac in three minutes | **7 domains out of 2,186, and not one was a setting** |
//
//  ⚠️ **A megabyte a launch is not acceptable, and it is why this file stores differences.** An app
//  whose entire premise is catching other software leaving junk on somebody's disk cannot itself
//  write 96 MB a year of its own bookkeeping. So the file keeps a **full baseline every thirtieth
//  record and only the differences in between** — which, on the measurement above, is a few hundred
//  bytes for an ordinary launch. A damaged line costs at most the month back to the previous
//  baseline, never the whole record.
//
//  ## ⚠️ The domain-listing command omits the most important domain
//
//  `defaults domains` does not list `NSGlobalDomain` — appearance, accent colour, text size, key
//  repeat and scroll direction all live there, and they are the most visible settings on the Mac.
//  This file does not use that command, but it adds the global domain **by name** anyway, because
//  the next person to change how domains are found will reach for the command that omits it. See
//  `globalDomain`.
//
//  ## ⚠️ Where it does not look
//
//  `~/Library/Preferences` and nothing else. **Never `~/Library/Containers` or
//  `~/Library/Group Containers`** — those hold other apps' sandboxed data, macOS raises a privacy
//  dialog on the *attempt* rather than on the failure, and `ContainerGuardTests` fails the build on
//  a file that names them. That is also why Safari, Mail, Photos, Messages and Notes cannot be
//  covered by this section at all, and the face says so rather than implying it looked.
//
//  ## ⚠️ It is a record of the person's machine, so uninstall asks
//
//  **Answer 3, 2026-08-28:** three buttons — leave them where they are, save them to a
//  folder you pick, or delete them. "Leave them" matters because somebody who reinstalls next month
//  gets their history back. A saved copy is a **readable summary and the raw file**, so it is worth
//  something without Wellkept. See `Farewell` and `saveOut(to:)`.
//
//  Registered in `StorageManifest` with disposition `.ask` the moment this file was created, which
//  is what stops the uninstaller going stale.
//
//  ## What it never does
//
//  No network, no schedule, no notification, and **it never writes a setting.** Decided 2026-08-28:
//  Wellkept writes no setting, ever. This file only reads, and it adds no entry to
//  `Privacy.Departure` because nothing leaves this Mac.

enum SnapshotStore {

    // MARK: - Where it lives

    /// `~/Library/Application Support/Wellkept/Snapshots.jsonl` — one JSON object per line.
    ///
    /// Append-only, exactly like `ReadingHistory`: a line is written with a single `write` at the
    /// end of the file and nothing is rewritten in place, so an interrupted launch costs at most
    /// the line being written rather than the file.
    static func url(home: URL = StorageManifest.home()) -> URL {
        StorageManifest.snapshotStore(home: home)
    }

    static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    // MARK: - ⚠️ The domain the listing command forgets

    /// `NSGlobalDomain` — appearance, accent colour, text size, key repeat, scroll direction.
    ///
    /// ⚠️ **Named explicitly because `defaults domains` omits it**, and because the file on disk is
    /// called `.GlobalPreferences.plist`, so a listing built from filenames spells it differently
    /// from every other reference to it in Apple's tools. Adding it by name costs one insertion and
    /// removes the single most visible silent failure this file could have.
    static let globalDomain = kCFPreferencesAnyApplication as String

    /// The same domain as it appears on disk, so a listing built from filenames and the constant
    /// above are recognised as the same thing rather than captured twice under two names.
    static let globalDomainFilename = ".GlobalPreferences"

    // MARK: - ⚠️ The churn domains, by name, with the reason beside each

    //  **An idle Mac changed 40 values in six minutes and not one of them was a setting.** Measured
    //  again here on 2026-08-28 over three minutes: of 2,186 domains, **seven** moved, and every one
    //  of them was a daemon keeping score.
    //
    //  ⚠️ **"Excluded" means not COUNTED. It never means not captured.** Every domain below is still
    //  written into the snapshot, because a record cannot be back-filled and a domain wrongly named
    //  in this list would otherwise cost somebody a change they never get to see. The list only
    //  subtracts from a number on screen — the "and 41 other values also changed" line — which is
    //  the one direction in which being wrong is cheap.
    //
    //  ⚠️ **A third-party app that churned is deliberately NOT here.** The seventh domain that moved
    //  in the measurement belonged to somebody else's application. Naming another developer's
    //  software in a hard-coded exclusion list is a judgement about their software on three minutes
    //  of evidence, and it is the same instinct this section refuses everywhere else.

    /// One domain that moves on its own, and what it is keeping score of.
    struct ChurnDomain: Sendable, Hashable {
        let domain: String
        /// What it holds. Kept beside the name so a list nobody can justify cannot quietly grow.
        let why: String
        /// `true` where this Mac was observed changing it with nothing at all happening.
        let measured: Bool
    }

    static let churnDomains: [ChurnDomain] = [
        // Observed changing on an idle Mac, 2026-08-28, three minutes, nothing happening.
        .init(domain: "ContextStoreAgent",
              why: "macOS's own record of what you have been doing, rewritten continuously.",
              measured: true),
        .init(domain: "com.apple.DuetExpertCenter.AppPredictionExpert",
              why: "The guesses behind app suggestions. Re-scored every few minutes.",
              measured: true),
        .init(domain: "com.apple.inputAnalytics.serverStats",
              why: "Counters for typing and dictation analytics. Numbers, not settings.",
              measured: true),
        .init(domain: "com.apple.knowledge-agent",
              why: "The on-device activity database's bookkeeping.",
              measured: true),
        .init(domain: "com.apple.spaces",
              why: "Which desktop each window is on. Moves every time a window does.",
              measured: true),
        .init(domain: "com.apple.xpc.activity2",
              why: "When macOS last ran each background job, and when it plans to run it next.",
              measured: true),

        // Named for what they hold rather than observed moving in that particular window.
        .init(domain: "TokenBucketRateLimiter",
              why: "Counters for how often macOS has recently allowed something. Nothing here is a choice anybody made.",
              measured: false),
        .init(domain: "com.apple.spotlightknowledged.pipeline",
              why: "Spotlight's indexing progress. A position in a queue, not a setting.",
              measured: false),
    ]

    private static let churnLookup = Set(churnDomains.map(\.domain))

    static func isChurn(_ domain: String) -> Bool { churnLookup.contains(domain) }

    // MARK: - Capturing

    /// Where a capture reads from. Injectable so the whole file is testable against a folder a test
    /// made itself, rather than only against whatever this particular Mac happens to be set to.
    struct Sources: Sendable {
        /// The folder of `*.plist` files that names the domains.
        var preferencesFolder: URL
        /// Reads one domain's keys. `nil` where the domain could not be read at all, which happens
        /// for about six hundred of them and is not an error.
        var keys: @Sendable (String) -> [String]?
        /// Reads one value, already turned into a stable string.
        var value: @Sendable (String, String) -> String?

        static func live(home: URL = StorageManifest.home()) -> Sources {
            Sources(
                preferencesFolder: home.appending(path: "Library/Preferences"),
                keys: { domain in
                    CFPreferencesCopyKeyList(domain as CFString,
                                             kCFPreferencesCurrentUser,
                                             kCFPreferencesAnyHost) as? [String]
                },
                value: { domain, key in
                    guard let raw = CFPreferencesCopyValue(key as CFString,
                                                           domain as CFString,
                                                           kCFPreferencesCurrentUser,
                                                           kCFPreferencesAnyHost) else { return nil }
                    return stableString(raw)
                }
            )
        }
    }

    /// Values longer than this are stored as a fingerprint instead of in full.
    ///
    /// ⚠️ **This is a real loss and it is deliberate.** A window position, a recent-documents list
    /// or a cached image is hundreds of bytes of nothing, and 149 of the 11,224 values on this Mac
    /// are long. Storing a fingerprint still detects that one changed — which is all version one
    /// does with them — but version two will be able to say only *that* such a value changed and
    /// not what it was. Short values, which is every real setting, are kept whole.
    static let longestStoredValue = 64

    /// One value as a stable string.
    ///
    /// ⚠️ **Stable is the whole requirement.** Two runs must produce the same string for the same
    /// value, or every launch reports the entire Mac as changed. Dictionaries and arrays are
    /// therefore rendered with their keys sorted rather than in whatever order the plist decoder
    /// handed them over.
    static func stableString(_ value: Any) -> String {
        switch value {
        case let text as String:     text
        case let number as NSNumber: number.stringValue
        case let date as Date:       ISO8601DateFormatter().string(from: date)
        case let data as Data:       "<\(data.count) bytes>"
        case let list as [Any]:      "[" + list.map(stableString).joined(separator: ",") + "]"
        case let map as [String: Any]:
            "{" + map.keys.sorted().map { "\($0)=\(stableString(map[$0] as Any))" }
                          .joined(separator: ",") + "}"
        default: String(describing: value)
        }
    }

    /// The stored form of a value: itself when short, a fingerprint when not.
    static func stored(_ rendered: String) -> String {
        guard rendered.count > longestStoredValue else { return rendered }
        let digest = SHA256.hash(data: Data(rendered.utf8))
        return "#" + digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
    }

    /// The composite key one setting is filed under. The separator is a control character on
    /// purpose: it cannot appear in a domain or a key, so the two halves are always separable.
    static func settingKey(domain: String, key: String) -> String { "\(domain)\u{1}\(key)" }

    static func split(_ settingKey: String) -> (domain: String, key: String)? {
        guard let separator = settingKey.firstIndex(of: "\u{1}") else { return nil }
        return (String(settingKey[settingKey.startIndex..<separator]),
                String(settingKey[settingKey.index(after: separator)...]))
    }

    /// **Capture everything readable**, plus whatever watched values the caller has already read.
    ///
    /// `watched` and `unreadable` are passed in rather than gathered here, because the things this
    /// section describes are read by the Security section's readers and re-reading the world at
    /// every launch would cost seconds rather than the measured 0.16. A launch that has not run
    /// those readers passes nothing, and `Diff` treats an absent key as *we did not look then*
    /// rather than as a change — which is the difference between a record and a rumour.
    static func capture(watched: [String: String] = [:],
                        unreadable: [String: String] = [:],
                        now: Date = Date(),
                        sources: Sources = .live(),
                        fileManager: FileManager = .default) -> Snapshot {

        var domains = Set<String>()
        let listing = (try? fileManager.contentsOfDirectory(atPath: sources.preferencesFolder.path)) ?? []
        for file in listing where file.hasSuffix(".plist") {
            let name = String(file.dropLast(6))
            // The global domain's file is called `.GlobalPreferences`; every API calls it something
            // else. Normalise, so it is captured once under the name the rest of the app uses.
            domains.insert(name == globalDomainFilename ? globalDomain : name)
        }
        // ⚠️ By name, always. See `globalDomain`.
        domains.insert(globalDomain)

        var settings: [String: String] = [:]
        for domain in domains {
            guard let keys = sources.keys(domain) else { continue }
            for key in keys {
                guard let rendered = sources.value(domain, key) else { continue }
                settings[settingKey(domain: domain, key: key)] = stored(rendered)
            }
        }

        return Snapshot(takenAt: now,
                        bootedAt: bootedAt(),
                        systemVersion: systemVersion(),
                        machine: machineIdentifier(),
                        appVersion: appVersion,
                        watched: watched,
                        unreadable: unreadable,
                        settings: settings,
                        excludedDomains: churnDomains.map(\.domain))
    }

    /// Capture one and write it. The whole of what a launch does.
    ///
    /// ⚠️ **Returns the snapshot whether or not the write succeeded, and callers ignore the write.**
    /// A health check that fails because it could not write its own diary is worse than a gap in
    /// the diary; the user asked about their Mac, not about our bookkeeping.
    @discardableResult
    static func take(watched: [String: String] = [:],
                     unreadable: [String: String] = [:],
                     now: Date = Date(),
                     home: URL = StorageManifest.home(),
                     sources: Sources? = nil) -> Snapshot {
        let snapshot = capture(watched: watched, unreadable: unreadable, now: now,
                               sources: sources ?? .live(home: home))
        record(snapshot, home: home)
        return snapshot
    }

    // MARK: - The machine's own facts

    /// `kern.boottime`, exact to the microsecond, readable by any account and needing no permission
    /// at all.
    ///
    /// ⛔ Two snapshots with different boot instants prove the Mac restarted. They prove **nothing
    /// about an update** — 15 of this Mac's 25 recorded boots carried none. See `Attribution`.
    static func bootedAt() -> Date? {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0, value.tv_sec > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000)
    }

    static func systemVersion() -> String? {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.patchVersion == 0
            ? "\(version.majorVersion).\(version.minorVersion)"
            : "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// "Mac15,3". Without it, a history carried to a new Mac by Migration Assistant would splice two
    /// machines together and report the second one's settings as the first one's changes.
    static func machineIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer)
        return text.isEmpty ? nil : text
    }

    // MARK: - On disk

    /// One line of the file.
    ///
    /// ⚠️ **A `difference` line is only meaningful after the `full` line before it.** That is why
    /// trimming may never cut into the middle of a run — see `trimIfNeeded`.
    struct Line: Codable, Sendable {

        enum Kind: String, Codable, Sendable {
            /// Every setting this Mac had at that moment.
            case full
            /// Only what differed from the line before, plus what disappeared.
            case difference
        }

        var kind: Kind
        var id: UUID
        var takenAt: Date
        var bootedAt: Date?
        var systemVersion: String?
        var machine: String?
        var appVersion: String?
        /// Always stored whole. Thirty entries costs nothing, and it makes the section's own data
        /// readable from any single line.
        var watched: [String: String]
        var unreadable: [String: String]
        /// Everything, or only the differences, according to `kind`.
        var settings: [String: String]
        /// Keys that existed in the previous line and do not exist now. Empty on a `full` line.
        var removed: [String]
        var excludedDomains: [String]
    }

    /// How many difference lines may follow one full line.
    ///
    /// Thirty is about a month of daily launches: a damaged line costs at most a month of the raw
    /// capture, never the whole record, and the file grows by roughly a megabyte a month rather
    /// than a megabyte a day.
    static let differencesPerBaseline = 30

    /// Roughly thirty-two megabytes, which at a megabyte a month is over twenty years.
    ///
    /// ⚠️ The cap is a real loss: trimming throws away the oldest records, which are exactly the
    /// ones that cannot be recreated. It exists because an unbounded file in somebody's Application
    /// Support folder is precisely the behaviour this app exists to catch other software doing.
    static let maximumBytes = 32 * 1024 * 1024

    private static let lock = NSLock()

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted keys so a line is byte-stable for the same input: the file stays diffable, and a
        // corrupted line is obvious beside its neighbours.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Append one snapshot, as a full baseline or as a difference from the one before.
    @discardableResult
    static func record(_ snapshot: Snapshot, home: URL = StorageManifest.home()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let existing = decodeLines(home: home)
        let sinceBaseline = countSinceBaseline(existing)
        let previous = existing.isEmpty ? nil : replay(existing)

        // A snapshot from a different machine starts a new baseline. Storing it as a difference
        // against another Mac's settings would record thousands of imaginary changes.
        let sameMachine = previous.map {
            $0.machine == nil || snapshot.machine == nil || $0.machine == snapshot.machine
        } ?? false

        let line: Line
        if let previous, sameMachine, sinceBaseline < differencesPerBaseline {
            var changed: [String: String] = [:]
            for (key, value) in snapshot.settings where previous.settings[key] != value {
                changed[key] = value
            }
            let gone = previous.settings.keys.filter { snapshot.settings[$0] == nil }.sorted()
            line = Line(kind: .difference, id: snapshot.id, takenAt: snapshot.takenAt,
                        bootedAt: snapshot.bootedAt, systemVersion: snapshot.systemVersion,
                        machine: snapshot.machine, appVersion: snapshot.appVersion,
                        watched: snapshot.watched, unreadable: snapshot.unreadable,
                        settings: changed, removed: gone,
                        excludedDomains: snapshot.excludedDomains)
        } else {
            line = Line(kind: .full, id: snapshot.id, takenAt: snapshot.takenAt,
                        bootedAt: snapshot.bootedAt, systemVersion: snapshot.systemVersion,
                        machine: snapshot.machine, appVersion: snapshot.appVersion,
                        watched: snapshot.watched, unreadable: snapshot.unreadable,
                        settings: snapshot.settings, removed: [],
                        excludedDomains: snapshot.excludedDomains)
        }

        guard let encoded = try? encoder().encode(line) else { return false }
        var payload = encoded
        payload.append(0x0A)

        let file = url(home: home)
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: file.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
            if manager.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
            } else {
                try payload.write(to: file, options: .atomic)
            }
        } catch {
            return false
        }

        trimIfNeeded(home: home)
        return true
    }

    /// Every snapshot on file, oldest first, with the differences replayed back into whole states.
    static func snapshots(home: URL = StorageManifest.home()) -> [Snapshot] {
        lock.lock()
        defer { lock.unlock() }
        return replayAll(decodeLines(home: home))
    }

    /// The most recent snapshot, or `nil` on a Mac that has never launched the app.
    static func latest(home: URL = StorageManifest.home()) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        let lines = decodeLines(home: home)
        return lines.isEmpty ? nil : replay(lines)
    }

    /// The two most recent snapshots, oldest first — everything `Diff` needs.
    ///
    /// The earlier one is `nil` on the very first launch, which is the one run where "nothing
    /// changed" would be a lie rather than an answer.
    static func lastTwo(home: URL = StorageManifest.home()) -> (earlier: Snapshot?, latest: Snapshot?) {
        let all = snapshots(home: home)
        return (all.count >= 2 ? all[all.count - 2] : nil, all.last)
    }

    /// Whether anything has ever been recorded. Used by the face to say "this is the first look"
    /// rather than "nothing has changed".
    static func isEmpty(home: URL = StorageManifest.home()) -> Bool {
        latest(home: home) == nil
    }

    // MARK: Replaying

    /// Decode the file, skipping any line that will not parse.
    ///
    /// A future build that adds a field must not make an old file unreadable, and one bad line must
    /// never cost the rest. Callers hold `lock`.
    private static func decodeLines(home: URL) -> [Line] {
        guard let data = try? Data(contentsOf: url(home: home)),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decode = decoder()
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let bytes = line.data(using: .utf8) else { return nil }
            return try? decode.decode(Line.self, from: bytes)
        }
    }

    /// The state after every line has been applied in order.
    private static func replay(_ lines: [Line]) -> Snapshot? { replayAll(lines).last }

    /// Every state, in order.
    ///
    /// ⚠️ A `difference` line arriving before any `full` line — which is what a trim cutting into
    /// the middle of a run would produce — is applied to an empty state rather than dropped. The
    /// result is honestly incomplete rather than absent, and `Diff` compares only keys present in
    /// both snapshots, so an incomplete old state produces no imaginary changes.
    private static func replayAll(_ lines: [Line]) -> [Snapshot] {
        var settings: [String: String] = [:]
        var built: [Snapshot] = []
        for line in lines {
            if line.kind == .full {
                settings = line.settings
            } else {
                for key in line.removed { settings[key] = nil }
                for (key, value) in line.settings { settings[key] = value }
            }
            built.append(Snapshot(id: line.id,
                                  takenAt: line.takenAt,
                                  bootedAt: line.bootedAt,
                                  systemVersion: line.systemVersion,
                                  machine: line.machine,
                                  appVersion: line.appVersion,
                                  watched: line.watched,
                                  unreadable: line.unreadable,
                                  settings: settings,
                                  excludedDomains: line.excludedDomains))
        }
        return built
    }

    private static func countSinceBaseline(_ lines: [Line]) -> Int {
        var count = 0
        for line in lines.reversed() {
            if line.kind == .full { return count }
            count += 1
        }
        return count
    }

    // MARK: Housekeeping

    /// Rewrite the file keeping the newest records, once it has grown past `maximumBytes`.
    ///
    /// ⚠️ **The cut is made at a full baseline, never inside a run of differences.** Cutting mid-run
    /// would leave difference lines describing a state nothing in the file still holds — the record
    /// would still parse, which is the dangerous kind of broken.
    ///
    /// The rewrite is atomic: a trim that failed halfway would take the whole record with it, and
    /// this is the one file in the section that cannot be recreated by running the check again.
    private static func trimIfNeeded(home: URL) {
        let file = url(home: home)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > maximumBytes else { return }

        let lines = decodeLines(home: home)
        // Baselines, in order. Cut at the newest one that still leaves most of the file behind —
        // three quarters, matching `ReadingHistory`, so a trim happens rarely rather than on every
        // launch once the file is full.
        let baselines = lines.indices.filter { lines[$0].kind == .full }
        let target = Int(Double(lines.count) * 0.25)
        guard let cut = baselines.last(where: { $0 <= target }) ?? baselines.first, cut > 0 else {
            return
        }

        let encode = encoder()
        var payload = Data()
        for line in lines[cut...] {
            guard let bytes = try? encode.encode(line) else { continue }
            payload.append(bytes)
            payload.append(0x0A)
        }
        try? payload.write(to: file, options: .atomic)
    }

    // MARK: - ⭐ Uninstall — asked about, never assumed

    /// **The three buttons, 2026-08-28.**
    ///
    /// There is no fourth option and no default. The record belongs to the person whose Mac it
    /// describes, and an uninstaller that decides for them is the "buried" outcome ruled out
    /// for the quarantine, applied to a different kind of file.
    enum Farewell: Sendable, Hashable {
        /// Leave it where it is. Somebody who reinstalls next month gets their history back.
        case leave
        /// Save it to a folder the person picks: a readable summary **and** the raw file.
        case save(to: URL)
        /// Delete it.
        case delete
    }

    /// The question, in the words it is asked in. Kept here rather than in the uninstaller so the
    /// wording can be tested without putting a dialog on anybody's screen.
    static func farewellQuestion(home: URL = StorageManifest.home()) -> (title: String, body: String) {
        let all = snapshots(home: home)
        let count = all.count
        let since = all.first?.takenAt.formatted(date: .abbreviated, time: .omitted)

        let title = "What should happen to your settings record?"
        var body = count == 1
            ? "Wellkept has one record of what this Mac's settings were."
            : "Wellkept has \(count) records of what this Mac's settings were"
        if count != 1 {
            if let since { body += ", going back to \(since)" }
            body += "."
        }
        body += "\n\nIt is a record of your Mac rather than Wellkept's own bookkeeping, so it is "
              + "yours to decide about. Leaving it costs nothing and means a reinstall picks up "
              + "where this left off. Saving it gives you a readable summary and the raw file, "
              + "both of which are useful without Wellkept."
        return (title, body)
    }

    /// Carry out the person's answer.
    ///
    /// ⚠️ `.delete` removes the one file and **nothing else**. It never reaches for the folder that
    /// file sits in: `~/Library/Application Support/Wellkept` also holds the quarantine, which holds
    /// the user's own files, and a recursive remove there would destroy them while doing exactly
    /// what it was told. `StorageManifest.tidyEmptyFolders()` clears the folder up afterwards, and
    /// only while it is already empty.
    @discardableResult
    static func carryOut(_ farewell: Farewell,
                         home: URL = StorageManifest.home(),
                         fileManager: FileManager = .default) throws -> [URL] {
        switch farewell {
        case .leave:
            return []
        case let .save(folder):
            let written = try saveOut(to: folder, home: home, fileManager: fileManager)
            try? fileManager.removeItem(at: url(home: home))
            return written
        case .delete:
            let file = url(home: home)
            if fileManager.fileExists(atPath: file.path) { try fileManager.removeItem(at: file) }
            return []
        }
    }

    /// Write the record out where somebody can use it: **a readable summary and the raw file.**
    ///
    /// Two files rather than one because they answer different questions. The summary is what a
    /// person opens; the raw file is what they still have if they ever want the detail, or if a
    /// later version of Wellkept can read it back.
    @discardableResult
    static func saveOut(to folder: URL,
                        home: URL = StorageManifest.home(),
                        now: Date = Date(),
                        fileManager: FileManager = .default) throws -> [URL] {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let summaryURL = folder.appending(path: "Wellkept settings record.txt")
        try Data(summary(now: now, home: home).utf8).write(to: summaryURL, options: .atomic)

        var written = [summaryURL]
        let raw = url(home: home)
        if fileManager.fileExists(atPath: raw.path) {
            let copy = folder.appending(path: "Wellkept snapshots.jsonl")
            // ⚠️ **Read the bytes and write them, rather than `FileManager.copyItem`.** The app has
            // one rule about copying, enforced by `OneMoveOnlyGuardTests`: a copy is a different act
            // from a move and only the ledger is allowed one. This file is ours rather than
            // anybody's document, so the rule is not really aimed at it — but a guard with a second
            // exception in it is a guard on its way to having a third, and writing the bytes costs
            // one line. Mapped rather than loaded: the record is capped at 32 MB and there is no
            // reason to hold all of it in memory at once.
            let bytes = try Data(contentsOf: raw, options: .mappedIfSafe)
            try bytes.write(to: copy, options: .atomic)
            written.append(copy)
        }
        return written
    }

    /// The readable half: plain text, no jargon, and it says what it cannot say.
    static func summary(now: Date = Date(), home: URL = StorageManifest.home()) -> String {
        let all = snapshots(home: home)
        var text = "Wellkept — what your Mac's settings were\n"
        text += String(repeating: "=", count: 40) + "\n\n"
        text += "Written \(now.formatted(date: .long, time: .shortened)).\n\n"

        guard let newest = all.last else {
            text += "There is nothing recorded. Wellkept had not taken a snapshot on this Mac.\n"
            return text
        }

        text += "\(all.count) snapshot\(all.count == 1 ? "" : "s"), "
        text += "from \(all[0].takenAt.formatted(date: .abbreviated, time: .shortened)) "
        text += "to \(newest.takenAt.formatted(date: .abbreviated, time: .shortened)).\n"
        if let machine = newest.machine { text += "Machine: \(machine)\n" }
        if let version = newest.systemVersion { text += "macOS: \(version)\n" }
        text += "Settings recorded in the most recent snapshot: \(newest.settings.count)\n\n"

        text += "WHAT WELLKEPT WATCHED\n---------------------\n"
        if newest.watched.isEmpty {
            text += "Nothing — no check had been run on this Mac when the last snapshot was taken.\n"
        } else {
            for watched in Watched.all {
                guard let value = newest.value(watched.key) else { continue }
                text += "\(watched.title): \(value)\n"
            }
        }

        text += "\nWHAT THIS DOES NOT COVER\n------------------------\n"
        text += "Safari, Mail, Photos, Messages and Notes keep their settings where no app can read\n"
        text += "them without putting a privacy dialog on your screen, so they are not in here.\n\n"
        text += "The raw file beside this one holds every value, including the ones Wellkept never\n"
        text += "described. It is one JSON object per line, oldest first.\n"
        return text
    }
}

// MARK: - The one that runs by itself

extension SnapshotStore {

    /// Take the launch snapshot, or refuse and say nothing.
    ///
    /// ⚠️ **This is the only reason the snapshots ship in version one at all.** The described half
    /// of this section is small on purpose, and the general settings journal is a version-two
    /// feature — but **a record cannot be back-filled.** Every launch that does not capture is a
    /// day version two will never be able to show. So the capture is full from the first launch and
    /// the describing catches up later.
    ///
    /// It captures **settings only**, with no watched values. Those come from the Security readers,
    /// and Security deliberately does not run at launch — its log query alone is about six seconds.
    /// So launch establishes the settings baseline, and the first time somebody presses the button
    /// in Changes establishes the described one.
    ///
    /// Refuses in demo mode (an invented Mac must never be written into the real record) and under
    /// the test harness (a test run is not a launch, and 888 of them would be 888 snapshots).
    /// Same guards, and the same reasons, as `HardwareModel.checkOnLaunch`.
    static func takeOnLaunch(demoMode: Bool, home: URL = StorageManifest.home()) {
        guard !demoMode else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        _ = take(home: home)
    }
}
