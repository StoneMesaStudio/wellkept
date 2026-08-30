// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  TimeMachineReader.swift
//  Wellkept — App/Backup
//
//  ⭐ **What Apple's own backup is actually doing, read with no permission at all — and the part of
//  this section that helps somebody today.**
//
//  Everything else in Backup is either an offer we may not make yet (`RehearsalGate`) or a page to
//  print. This file is the measured half: whether Time Machine is set up, whether it is switched
//  on, where it goes, whether that place is here, when it last worked, what stopped it, and what
//  its snapshots are holding on this Mac's own disk. Every one of those reads on a Mac that has
//  granted Wellkept nothing at all.
//
//  ## ⭐ The mistake this file exists to not repeat
//
//  On 2026-08-28 an earlier draft of this section reported **"Time Machine cannot reach the backup
//  drive"** on a real Mac, which reads as a fault. Measured properly the next morning, on the same
//  machine:
//
//  | Reading | Value |
//  |---|---|
//  | `AutoBackup` | **0 — automatic backups are switched off** |
//  | Destination | the configured backup drive, correct |
//  | Mounted right now | No. The drive is in a drawer. |
//  | Last successful backup | **25 August 13:03:41 UTC** |
//  | Backups recorded | **Four**, from 3 June to 25 August |
//  | `RESULT` on the destination | **0 — the last run succeeded** |
//
//  Nothing is broken. Somebody turned it off, or it turned itself off, and nobody said so.
//  **"Your backup is off and nobody told you" is both truer and more useful than "your backup is
//  broken."** `TimeMachineStanding` keeps those apart and `TimeMachineState.standing` tests
//  `.switchedOff` before it ever looks at a failure. This reader's job is to feed that type facts
//  rather than conclusions — see `failure(...)`, which throws a recorded failure away in the two
//  cases where it is no longer the last word.
//
//  ## Where each fact comes from
//
//  Measured by hand on an M3 running macOS 26.6.2, 2026-08-29. All read-only; nothing was mounted,
//  unmounted, enabled, disabled or triggered.
//
//  | Fact | Source | Cost |
//  |---|---|---|
//  | On or off, destination, history, last result | `CFPreferencesCopyValue` on `com.apple.TimeMachine` | under a millisecond |
//  | Is the drive here | `FileManager.mountedVolumeURLs`, matched on volume UUID | **4 ms** for ten volumes |
//  | How big it is, and how full | the mounted volume's own resource values | free |
//  | What stopped it | `RESULT`, then `log show` over the failing run's own minutes | **1.8 s**, and only on a Mac that is failing |
//  | Local snapshots | `FreeSpace.localSnapshots` — `tmutil listlocalsnapshots` | ~100 ms |
//
//  ## ⛔ The preference file cannot be opened, and that is the point
//
//  `/Library/Preferences/com.apple.TimeMachine.plist` is protected: `cat` on it fails for an
//  ordinary user and would fail for this app too. **So we ask macOS for the values instead.**
//  `CFPreferencesCopyValue` goes to `cfprefsd`, which holds the file and hands back the values with
//  no permission, no prompt and no Full Disk Access. Verified today, from a plain Swift process,
//  against a Mac where `cat` on the same path returns exit 1.
//
//  ## ⛔ Two things this reader will not do
//
//  1. **`tmutil latestbackup` is not called.** It looks like the obvious source for "when did it
//     last work", and on this Mac it printed
//     `Failed to mount backup destination, error: … Code=18 "Failed to mount destination."` —
//     **it tried to mount the drive.** Mounting a volume is a thing this app does not do, so the
//     last success is taken from the preference history instead, which needs nothing to be
//     attached. (The observation was not wasted: code 18 is the one `backupd` result code below
//     that was seen rather than guessed.)
//  2. **Nothing here enables, disables, starts or stops a backup**, and there is no function in
//     this file that could. The row's button opens Time Machine settings; the person decides.
//
//  ## ⚠️ The noise, and why the log is the last source consulted rather than the first
//
//  Measured over 24 hours on this Mac: **1,401 error-level messages from `com.apple.TimeMachine`,
//  on a Mac whose last backup succeeded.** 1,256 of them — 90% — are one sentence,
//  `com.apple.backupd.sandbox.xpc: connection invalid`, which is an XPC connection being torn down
//  normally. `LogNoise` in `WellkeptCore` removes that family. `LogFilter.isHousekeeping` below
//  removes three more shapes measured on the same quiet Mac.
//
//  **Even so, the log never decides whether a backup is failing.** That comes from `RESULT` on the
//  destination, which is a number Apple wrote about a run that actually happened. The log is read
//  only to put words to a failure that is already established, and only inside the minutes of the
//  run that failed. A Mac with `RESULT == 0` never spawns `log` at all.

enum TimeMachineReader {

    // MARK: - What one run produced

    /// Everything this reader measured, and the row it makes of it.
    struct Result: Sendable, Hashable {

        /// The facts, in the shape `WellkeptCore` reasons about. All conclusions come from here.
        let state: TimeMachineState

        /// The `.appleBackup` row, ready to hand to `BackupReport`.
        let row: BackupRow

        /// The local snapshots sitting on **this Mac's own disk**, not on the backup drive.
        let snapshots: SnapshotStanding

        /// ⭐ Time Machine's own reference point — the snapshot the next backup will start from.
        /// `nil` when there is not one, or when the preferences did not say.
        let referencePoint: Date?

        /// Every backup this destination has a record of, oldest first. Four, on this Mac.
        let backupsRecorded: [Date]

        /// ⭐ The sentence tying Storage's stuck snapshot to this section, when there is one.
        /// See `snapshotSentence(...)`.
        let snapshotLine: String?
    }

    // MARK: - ⭐ The read

    /// **Read Time Machine's whole state.** Needs nothing granted, changes nothing, and is safe to
    /// call on a Mac that has never had a backup drive.
    ///
    /// - Parameter now: injected so every sentence about "days since" can be tested without waiting.
    static func read(now: Date = Date()) -> Result {
        // Per thread, not per process. This reader does not walk the home folder, but it does read
        // resource values on whatever volumes are mounted, and one of those could be a cloud
        // provider's mount. Costs nothing and removes the question. See `ScanPolicy`.
        _ = ScanPolicy.prepareThisThread()

        let prefs = Preferences.read()
        let snapshots = FreeSpace.localSnapshots(on: ScanPolicy.root())

        // ── Nothing came back from cfprefsd at all ──────────────────────────────────────────────
        //
        // Two very different Macs land here: one that has never used Time Machine, and one where
        // the read itself failed. `tmutil destinationinfo` separates them — it answers on both, and
        // it does not mount anything to do it.
        guard prefs.answered else {
            let state = TimeMachineState.couldNotRead(.notReported)
            return assemble(state: state, prefs: prefs, snapshots: snapshots, now: now)
        }

        let chosen = prefs.chosenDestination
        let mounted = chosen.flatMap { MountedVolumes.find(matching: $0) }

        let destination = chosen.map { record in
            BackupDestination(name: record.displayName,
                              kind: record.kind,
                              isConnected: mounted != nil,
                              volumePath: mounted?.path,
                              capacity: mounted?.capacity,
                              free: mounted?.free)
        }

        let state = TimeMachineState(isConfigured: chosen != nil,
                                     automaticBackupsOn: prefs.automaticBackupsOn,
                                     destination: destination,
                                     lastSuccess: chosen?.lastSuccess,
                                     failure: failure(for: chosen, isConnected: mounted != nil))

        return assemble(state: state, prefs: prefs, snapshots: snapshots, now: now)
    }

    /// Build the row out of a state that has already been decided.
    private static func assemble(state: TimeMachineState,
                                 prefs: Preferences.Reading,
                                 snapshots: SnapshotStanding,
                                 now: Date) -> Result {
        let chosen = prefs.chosenDestination
        let reference = chosen?.referenceSnapshot
        let line = snapshotSentence(snapshots: snapshots, referencePoint: reference, now: now)

        return Result(state: state,
                      row: row(from: state, prefs: prefs, snapshots: snapshots,
                               snapshotLine: line, now: now),
                      snapshots: snapshots,
                      referencePoint: reference,
                      backupsRecorded: chosen?.successes ?? [],
                      snapshotLine: line)
    }

    // MARK: - The row

    /// The `.appleBackup` row. Every word of the verdict comes from `TimeMachineState`; this
    /// function only decides what goes behind **Options** and what the one measure says.
    static func row(from state: TimeMachineState,
                    prefs: Preferences.Reading,
                    snapshots: SnapshotStanding,
                    snapshotLine: String?,
                    now: Date) -> BackupRow {

        if let why = state.unreadable {
            return BackupRow.unreadable(.appleBackup, why,
                                        about: BackupTopic.appleBackup.label,
                                        reason: "macOS did not hand over Time Machine's settings, "
                                              + "and there is no permission in this app that asks for them.",
                                        details: snapshotDetails(snapshots, referencePoint: nil, now: now))
        }

        // Two sentences under the headline where there are two: the reason, then the snapshot line.
        // The snapshot line is a fact about this Mac's own disk and belongs with the backup that
        // left it there — Storage already tells people the number; this says why it is stuck.
        let reason = [state.reason(now: now), snapshotLine]
            .compactMap { $0 }
            .joined(separator: " ")

        return BackupRow(topic: .appleBackup,
                         headline: state.headline(now: now),
                         measure: measure(for: state, now: now),
                         reason: reason.isEmpty ? nil : reason,
                         severity: state.severity(now: now),
                         details: state.detailPairs(now: now)
                                + historyDetails(prefs.chosenDestination,
                                                 isConnected: state.destination?.isConnected ?? false)
                                + snapshotDetails(snapshots,
                                                  referencePoint: prefs.chosenDestination?.referenceSnapshot,
                                                  now: now),
                         remedy: state.remedy(now: now))
    }

    /// The one figure on the row. A date, because every other number here — how many backups, how
    /// many bytes on the drive — answers a question nobody asked at the top of a section.
    static func measure(for state: TimeMachineState, now: Date) -> String? {
        guard state.isConfigured else { return nil }
        guard state.lastSuccess != nil else { return "No backup has ever finished" }
        return "Last backup \(BackupFreshness.phrase(for: state.lastSuccess, now: now))"
    }

    // MARK: - ⛔ Turning a recorded result into a failure, or throwing it away

    /// **Whether there is a failure to report, and what to call it.**
    ///
    /// ⚠️ Two recorded failures are deliberately discarded, and both discards are the same
    /// argument: a `RESULT` is the outcome of *one* run, and this section reports what is true now.
    ///
    /// 1. **A later run succeeded.** If the last success is at or after the last attempt, whatever
    ///    `RESULT` holds is about an older run. Reporting it would flag a Mac whose backups are
    ///    working.
    /// 2. **The drive was missing and is here now.** A failure whose whole content is "could not
    ///    find the drive", on a Mac where the drive is currently mounted, is a fact about a moment
    ///    that has passed; macOS will retry within the hour. `FailureCause.driveNotConnected`'s own
    ///    advice is "plug the drive in", which is wrong to say to somebody who just did.
    ///    ⭐ Nothing is hidden by this: with the drive here and the last success old, `standing`
    ///    returns `.overdue` and the row says nothing has finished since the date it names.
    ///
    /// Everything else is kept, including a code we cannot translate — that comes back as
    /// `.unknown`, which prints "Something stopped it" and shows Apple's own number.
    static func failure(for record: Preferences.Destination?, isConnected: Bool) -> TimeMachineFailure? {
        guard let record, let code = record.result, code != 0 else { return nil }

        // 1. A later run succeeded, so this result is not the last word.
        if let success = record.lastSuccess, let attempt = record.lastAttempt, success >= attempt {
            return nil
        }

        let messages = LogFilter.realErrors(around: record.lastAttempt)
        let cause = cause(code: code, messages: messages)

        // 2. The only evidence is an absence that has since been resolved.
        if cause == .driveNotConnected && isConnected { return nil }

        return TimeMachineFailure(code: code,
                                  message: messages.first,
                                  cause: cause,
                                  noticedOn: record.lastAttempt)
    }

    /// **What stopped it**, from the code first and the words second.
    ///
    /// ⚠️ **Only one code below was observed rather than inferred.** Running `tmutil latestbackup`
    /// on this Mac with the drive unplugged returned
    /// `Error Domain=com.apple.backupd.ErrorDomain Code=18 "Failed to mount destination."` — so 18
    /// is measured. Apple publishes no table for the rest, and inventing one would put confident
    /// wrong words on a screen, so every other code falls through to the message text and then to
    /// `.unknown`.
    ///
    /// The text rules match **POSIX error names**, which `backupd` embeds verbatim
    /// (`NSPOSIXErrorDomain Code=28 "No space left on device"`). Those strings come from the C
    /// library, not from a localisation table, so they are the same on a French Mac — which is the
    /// bug `BatteryReader` shipped and this file is not repeating.
    static func cause(code: Int, messages: [String]) -> FailureCause {
        if code == 18 { return .driveNotConnected }

        let text = messages.joined(separator: " ").lowercased()

        // Ordered most specific first: a message can contain more than one of these, and the
        // narrower reading is the more useful one.
        if text.contains("no space left on device") { return .driveFull }
        if text.contains("read-only file system")
            || text.contains("operation not permitted")
            || text.contains("permission denied") { return .cannotWriteThere }
        if text.contains("needs to be repaired")
            || text.contains("must be repaired")
            || text.contains("is damaged") { return .destinationDamaged }
        if text.contains("failed to mount")
            || text.contains("no such file or directory") { return .driveNotConnected }
        if text.contains("could not connect to the server")
            || text.contains("authentication")
            || text.contains("network is unreachable") { return .cannotReachTheNetworkPlace }
        if text.contains("backup was not found")
            || text.contains("no backup was found") { return .backupNoLongerThere }
        if text.contains("was cancelled") || text.contains("was canceled") { return .interrupted }

        return .unknown
    }

    // MARK: - ⭐ The snapshots, and the fact that belongs here

    /// **What the local snapshots are holding, said where it can be acted on.**
    ///
    /// Storage already prints the number: a stuck local snapshot means deleting anything older than
    /// its date returns no space at all. It cannot say *why*, because the reason belongs to Time
    /// Machine. Measured here on 2026-08-29:
    ///
    /// | Reading | Value |
    /// |---|---|
    /// | `tmutil listlocalsnapshots /` | one — `com.apple.TimeMachine.2026-08-25-062503.local` |
    /// | `ReferenceLocalSnapshotDate` in Time Machine's preferences | `2026-08-25 12:25:03 +0000` |
    /// | This Mac's clock | MDT, UTC−6 |
    ///
    /// **12:25:03 UTC is 06:25:03 MDT — they are the same snapshot to the second.** So the snapshot
    /// Storage reports as stuck is not stray: it is Time Machine's **reference point**, the state
    /// the next backup will measure its changes against, and macOS keeps it precisely until a
    /// backup finishes. That turns a dead number into an action: plug the drive in and let one
    /// backup complete.
    ///
    /// ⚠️ The sentence promises a release, never a figure. How many bytes come back depends on what
    /// has changed since, and that is Storage's arithmetic to do afterwards, not ours to predict.
    ///
    /// `nil` when there is nothing worth saying: no snapshots, or a recent one macOS will thin by
    /// itself within about a day.
    static func snapshotSentence(snapshots: SnapshotStanding,
                                 referencePoint: Date?,
                                 now: Date) -> String? {
        guard snapshots.wasRead else { return nil }
        guard let oldest = snapshots.oldest, snapshots.isStuck(now: now) else { return nil }

        let date = oldest.takenOn.formatted(date: .abbreviated, time: .omitted)

        // Same snapshot, to the minute? Then we can say what it is FOR, which is the useful half.
        if let referencePoint, abs(referencePoint.timeIntervalSince(oldest.takenOn)) <= 120 {
            return "Time Machine is still holding a snapshot on this Mac's own disk from \(date). "
                 + "It is the point the next backup starts from, so macOS keeps it until one "
                 + "finishes — and until then, deleting anything older than that date frees no "
                 + "space. Letting one backup finish releases it."
        }

        return "Time Machine is still holding a snapshot on this Mac's own disk from \(date), so "
             + "deleting anything older than that date frees no space until it is released."
    }

    /// The snapshot facts, behind **Options**.
    static func snapshotDetails(_ snapshots: SnapshotStanding,
                                referencePoint: Date?,
                                now: Date) -> [DetailPair] {
        var pairs: [DetailPair] = []

        if !snapshots.wasRead {
            pairs.append(DetailPair("Local snapshots on this Mac", unreadable: .notReported))
        } else if snapshots.isEmpty {
            pairs.append(DetailPair("Local snapshots on this Mac", "None"))
        } else {
            pairs.append(DetailPair("Local snapshots on this Mac", snapshots.snapshots.count.formatted()))
            if let oldest = snapshots.oldest {
                let age = snapshots.ageInDays(now: now).map { " · \($0.formatted()) days old" } ?? ""
                pairs.append(DetailPair("Oldest snapshot",
                                        oldest.takenOn.formatted(date: .abbreviated, time: .shortened) + age))
            }
        }

        if let referencePoint {
            pairs.append(DetailPair("Time Machine's reference point",
                                    referencePoint.formatted(date: .abbreviated, time: .shortened)))
        }
        return pairs
    }

    // MARK: - The history, behind Options

    /// What the destination's own record says, for anybody who wants the exact shape of it.
    ///
    /// ⚠️ **The drive's capacity is only shown live.** `BytesAvailable` and `BytesUsed` in the
    /// preferences are whatever they were the last time the drive was attached — on this Mac,
    /// figures from 25 August about a drive in a drawer. They are labelled as such rather than
    /// printed beside today's date as if they were current. When the drive *is* mounted, the
    /// numbers come from the volume itself and go on `BackupDestination` where they belong.
    static func historyDetails(_ record: Preferences.Destination?,
                               isConnected: Bool) -> [DetailPair] {
        guard let record else { return [] }
        var pairs: [DetailPair] = []

        if !record.successes.isEmpty {
            let span: String
            if let first = record.successes.first, let last = record.successes.last, first != last {
                span = ", from \(first.formatted(date: .abbreviated, time: .omitted)) "
                     + "to \(last.formatted(date: .abbreviated, time: .omitted))"
            } else {
                span = ""
            }
            pairs.append(DetailPair("Backups recorded", "\(record.successes.count.formatted())\(span)"))
        }

        if !isConnected, let used = record.bytesUsed, let free = record.bytesAvailable {
            pairs.append(DetailPair("On the drive when it was last connected",
                                    "\(SizeOnDisk(used).text) used · \(SizeOnDisk(free).text) free"))
        }
        if let format = record.filesystem {
            pairs.append(DetailPair("Backup drive format", Words.format(format)))
        }
        if let encryption = record.encryptionState {
            pairs.append(DetailPair("Backup drive encryption", Words.encryption(encryption)))
        }
        if let id = record.id {
            pairs.append(DetailPair("Destination ID", id, sensitive: true))
        }
        return pairs
    }

    /// **Apple's stored keys, in a person's words.**
    ///
    /// ⚠️ These are *keys*, not translations — `LastKnownEncryptionState` is the literal string
    /// `NotEncrypted` on a French Mac too, which is why they may be compared. The battery bug came
    /// from comparing values macOS had already localised; this is the opposite case, and the
    /// difference is that these strings never pass through a localisation table.
    ///
    /// Anything unrecognised is **passed through unchanged** rather than dropped or guessed at. A
    /// filesystem this list has never heard of is still worth showing somebody.
    enum Words {

        static func format(_ raw: String) -> String {
            switch raw.lowercased() {
            case "apfs":            "APFS"
            case "hfs", "hfsplus":  "Mac OS Extended"
            case "smbfs":           "A network share (SMB)"
            case "afpfs":           "A network share (AFP)"
            case "exfat":           "ExFAT"
            default:                raw
            }
        }

        static func encryption(_ raw: String) -> String {
            switch raw.lowercased() {
            case "notencrypted": "Not encrypted"
            case "encrypted":    "Encrypted"
            case "unknown":      Unreadable.notReported.sentence
            default:             raw
            }
        }
    }
}

// MARK: - ⛔ Asking macOS for the values

extension TimeMachineReader {

    /// **Time Machine's settings, read through `cfprefsd` rather than off the disk.**
    ///
    /// ⛔ `/Library/Preferences/com.apple.TimeMachine.plist` cannot be opened: `cat` on it returns
    /// exit 1 for an ordinary user, and it would do the same for this app. `CFPreferencesCopyValue`
    /// asks the preferences daemon, which holds the file — no permission, no prompt, no Full Disk
    /// Access. Verified from a plain Swift process on 2026-08-29 against the same Mac where the
    /// direct read fails.
    ///
    /// The domain is `AnyUser` + `AnyHost` because the file lives in `/Library/Preferences` rather
    /// than in a per-user or per-host folder.
    ///
    /// ⚠️ **Nothing here writes.** `CFPreferencesSetValue` and `CFPreferencesSynchronize` are not
    /// called, deliberately: this reader has no business flushing another process's preference
    /// domain, and `defaults write` in any form is banned outright in this project.
    enum Preferences {

        static let domain = "com.apple.TimeMachine"

        /// One destination, as Apple records it.
        struct Destination: Sendable, Hashable {
            let id: String?
            let volumeName: String?
            let volumeUUIDs: [String]
            let networkURL: String?

            /// `RESULT` — the outcome of the last run. `0` is success.
            let result: Int?

            /// `AttemptDates` — every run that started, oldest first.
            let attempts: [Date]

            /// `SnapshotDates` — every run that **finished**, oldest first. This is the honest
            /// source for "when did it last work", and it needs nothing mounted to read.
            let successes: [Date]

            let bytesAvailable: Int64?
            let bytesUsed: Int64?
            let filesystem: String?
            let encryptionState: String?

            /// ⭐ `ReferenceLocalSnapshotDate` — the local snapshot the next backup starts from.
            let referenceSnapshot: Date?

            var lastSuccess: Date? { successes.last }
            var lastAttempt: Date? { attempts.last }

            /// What a person would call it. A network destination has no volume name until it is
            /// mounted, so it falls back to the address and then to plain words.
            var displayName: String {
                if let volumeName, !volumeName.isEmpty { return volumeName }
                if let networkURL, !networkURL.isEmpty { return networkURL }
                return "the backup destination"
            }

            /// ⚠️ **Decided by which keys are present, never by Apple's English.** `tmutil
            /// destinationinfo` prints `Kind : Local`, and a word on a screen is a word that can be
            /// translated. The presence of a network address is not.
            var kind: DestinationKind {
                if networkURL != nil { return .networkShare }
                if !volumeUUIDs.isEmpty || volumeName != nil { return .localDrive }
                return .unknown
            }
        }

        /// One read of the domain.
        struct Reading: Sendable, Hashable {
            /// Whether `cfprefsd` gave us anything at all. `false` means the domain is empty or the
            /// read failed — two different Macs, separated by `tmutil destinationinfo`.
            let answered: Bool

            /// ⚠️ `AutoBackup`. **Absent counts as off**, and that is a judgement rather than a
            /// measurement: macOS writes this key explicitly — it is `0` on this Mac, not missing —
            /// so a domain that has the file and not the key has never had the switch turned on.
            let automaticBackupsOn: Bool

            let destinations: [Destination]
            let lastDestinationID: String?

            /// The one a person means. Almost always the only one; where there are several, the one
            /// macOS itself last used.
            var chosenDestination: Destination? {
                if let lastDestinationID,
                   let match = destinations.first(where: { $0.id == lastDestinationID }) {
                    return match
                }
                return destinations.first
            }

            static let nothing = Reading(answered: false,
                                         automaticBackupsOn: false,
                                         destinations: [],
                                         lastDestinationID: nil)
        }

        static func read() -> Reading {
            let auto = value("AutoBackup")
            let raw = value("Destinations") as? [[String: Any]]
            let lastID = value("LastDestinationID") as? String
            let version = value("PreferencesVersion")

            // "The domain answered" means cfprefsd handed back *something*. A Mac that has never
            // opened Time Machine still has a `PreferencesVersion`; one where the read failed has
            // nothing at all. Where even that is absent, `destinationInfoAnswers()` is the tie
            // break — it runs on a Mac with no destination and says so, and it mounts nothing.
            let answered = auto != nil || raw != nil || version != nil || destinationInfoAnswers()

            return Reading(answered: answered,
                           automaticBackupsOn: (auto as? NSNumber)?.boolValue ?? false,
                           destinations: (raw ?? []).map(destination(from:)),
                           lastDestinationID: lastID)
        }

        private static func value(_ key: String) -> Any? {
            CFPreferencesCopyValue(key as CFString,
                                   domain as CFString,
                                   kCFPreferencesAnyUser,
                                   kCFPreferencesAnyHost)
        }

        static func destination(from raw: [String: Any]) -> Destination {
            Destination(id: raw["DestinationID"] as? String,
                        volumeName: raw["LastKnownVolumeName"] as? String,
                        volumeUUIDs: (raw["DestinationUUIDs"] as? [String]) ?? [],
                        networkURL: (raw["NetworkURL"] as? String) ?? (raw["ServerAddress"] as? String),
                        result: (raw["RESULT"] as? NSNumber)?.intValue,
                        attempts: dates(raw["AttemptDates"]),
                        successes: dates(raw["SnapshotDates"]),
                        bytesAvailable: (raw["BytesAvailable"] as? NSNumber)?.int64Value,
                        bytesUsed: (raw["BytesUsed"] as? NSNumber)?.int64Value,
                        filesystem: raw["FilesystemTypeName"] as? String,
                        encryptionState: raw["LastKnownEncryptionState"] as? String,
                        referenceSnapshot: raw["ReferenceLocalSnapshotDate"] as? Date)
        }

        /// Dates, oldest first, with anything that is not a date dropped rather than guessed at.
        static func dates(_ raw: Any?) -> [Date] {
            ((raw as? [Any]) ?? []).compactMap { $0 as? Date }.sorted()
        }

        /// ⛔ **Read-only, and it does not mount.** `tmutil destinationinfo` prints the configured
        /// destinations with the drive in a drawer — verified on one real Mac, which is exactly why it
        /// is the tie-break rather than `latestbackup`, whose first act is to try to mount the
        /// drive.
        ///
        /// The output is not parsed. All that is wanted is whether `tmutil` answered at all, which
        /// separates "this Mac has never had a backup" from "we could not read".
        static func destinationInfoAnswers() -> Bool {
            let tool = URL(filePath: "/usr/bin/tmutil")
            guard FileManager.default.isExecutableFile(atPath: tool.path(percentEncoded: false)) else {
                return false
            }
            return Spawn.run(tool, arguments: ["destinationinfo"], timeout: 5) != nil
        }
    }
}

// MARK: - Is the drive here

extension TimeMachineReader {

    /// **Whether the backup destination is attached right now**, matched on identity rather than on
    /// a name.
    ///
    /// ⛔ Reading only. `mountedVolumeURLs` lists what macOS has already mounted; it does not mount,
    /// unmount or touch anything, and it took **4 ms** across ten volumes on this Mac.
    enum MountedVolumes {

        struct Match: Sendable, Hashable {
            let path: String
            let capacity: SizeOnDisk?
            let free: SizeOnDisk?
        }

        static let keys: [URLResourceKey] = [.volumeNameKey, .volumeUUIDStringKey,
                                             .volumeTotalCapacityKey, .volumeAvailableCapacityKey]

        /// ⚠️ **UUID first, name second.** `DestinationUUIDs` holds the volume's own identifier, so
        /// a drive that was renamed still matches and a different drive that happens to share the
        /// name does not. The name is kept as a fallback for a destination recorded before the UUID
        /// was written, and for a network share, where there is no volume UUID to compare.
        ///
        /// ⚠️ **The UUID path is unverified against real hardware**: the drive was in a drawer all
        /// day and this app may not plug it in. The name fallback is what actually ran here. If the
        /// UUID comparison turns out to be against the wrong identifier, the symptom is a connected
        /// drive reported as absent — which reads as `.waitingForTheDrive`, not as a fault.
        static func find(matching record: TimeMachineReader.Preferences.Destination) -> Match? {
            let wanted = Set(record.volumeUUIDs.map { $0.uppercased() })
            let wantedName = record.volumeName

            let volumes = FileManager.default
                .mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []

            var byName: Match?

            for volume in volumes {
                guard let values = try? volume.resourceValues(forKeys: Set(keys)) else { continue }

                if let uuid = values.volumeUUIDString, wanted.contains(uuid.uppercased()) {
                    return match(volume, values)
                }
                if byName == nil, let name = values.volumeName, let wantedName, name == wantedName {
                    byName = match(volume, values)
                }
            }
            return byName
        }

        private static func match(_ volume: URL, _ values: URLResourceValues) -> Match {
            Match(path: volume.path(percentEncoded: false),
                  capacity: values.volumeTotalCapacity.map { SizeOnDisk(Int64($0)) },
                  free: values.volumeAvailableCapacity.map { SizeOnDisk(Int64($0)) })
        }
    }
}

// MARK: - ⚠️ The log, filtered twice and consulted last

extension TimeMachineReader {

    /// **Words for a failure that has already been established, and nothing else.**
    ///
    /// ⚠️ **The log cannot make a Mac look broken here, because it is never asked whether one is.**
    /// `failure(for:isConnected:)` only calls this after `RESULT` came back non-zero, and
    /// `TimeMachineFailure.init?` in `WellkeptCore` refuses to build a failure out of text this
    /// filter recognises as noise. On a Mac with `RESULT == 0` — which is this Mac — `log` is never
    /// spawned at all.
    ///
    /// ## What was measured
    ///
    /// 24 hours of `messageType == error` from `com.apple.TimeMachine`, on a Mac whose last backup
    /// succeeded and whose drive has been unplugged for four days:
    ///
    /// | Message | Count | Filtered by |
    /// |---|---|---|
    /// | `com.apple.backupd.sandbox.xpc: connection invalid` | 1,191 | `LogNoise` |
    /// | `com.apple.backupd.xpc: connection invalid` | 63 | `LogNoise` |
    /// | `com.apple.backupd.status.xpc: connection invalid` | 2 | `LogNoise` |
    /// | `fs_snapshot_list failed: Operation not supported` | 84 | `isHousekeeping` |
    /// | `Snapshot deletion failed for disk '/' … Read-only file system` | 42 | `isHousekeeping` |
    /// | `attrVolumeWithMountPoint 'file:///private/tmp/tmp-mount-…' failed …` | 18 | `isHousekeeping` |
    /// | **Total** | **1,400** | **all of it** |
    ///
    /// **Every error-level message this Mac produced in a day is noise.** Print them raw and a Mac
    /// that is working perfectly reads as one with a thousand faults.
    ///
    /// ## The direction of safety
    ///
    /// Identical to `LogNoise`'s, and for the same reason: **a message nobody recognised is kept.**
    /// Both lists only ever subtract shapes somebody measured. The worst this can do is show a
    /// person a line that turned out to be nothing; the opposite arrangement's worst case is hiding
    /// the day their backups stopped.
    enum LogFilter {

        /// How far back a failing run may be and still be worth looking up.
        ///
        /// Beyond this the unified log has usually rolled anyway, and `log show` over a window that
        /// wide costs seconds — measured at **4.4 s for 24 hours** on this Mac, against **1.8 s**
        /// for the four minutes a run actually occupies. A failure older than two days still
        /// reports its code and its cause; it simply has no quotation attached.
        static let maxLookbackHours: Double = 48

        /// How long after the attempt started to keep reading. A run that fails fails early.
        static let windowMinutes: Double = 30

        /// ⚠️ **Three more noise shapes, measured on the same quiet Mac** — 144 messages in a day,
        /// none of them about a backup failing.
        ///
        /// - `fs_snapshot_list failed: Operation not supported` — asking a filesystem that has no
        ///   snapshots whether it has snapshots.
        /// - `Snapshot deletion failed … Read-only file system` — thinning attempted against the
        ///   sealed system volume, which is read-only by design and always will be.
        /// - `attrVolumeWithMountPoint 'file:///private/tmp/tmp-mount-…'` — a scratch mount point
        ///   that has already gone away by the time it is asked about.
        ///
        /// These are matched as substrings rather than by `LogNoise`'s share-of-the-line rule,
        /// because each is a short prefix on a long message. That is a wider match, so the list is
        /// kept to shapes that were counted rather than imagined.
        static let housekeeping = [
            "fs_snapshot_list failed",
            "snapshot deletion failed for disk",
            "attrvolumewithmountpoint",
        ]

        static func isHousekeeping(_ message: String) -> Bool {
            let text = message.lowercased()
            return housekeeping.contains { text.contains($0) }
        }

        /// The messages worth quoting from the minutes around a failing run, best first.
        ///
        /// Returns empty — never `nil` — because "the log said nothing useful" and "we did not
        /// look" lead to the same row: a failure with its code and no quotation.
        static func realErrors(around attempt: Date?, now: Date = Date()) -> [String] {
            guard let attempt else { return [] }
            guard now.timeIntervalSince(attempt) <= maxLookbackHours * 3600,
                  attempt <= now else { return [] }

            let end = min(attempt.addingTimeInterval(windowMinutes * 60), now)
            guard let output = show(from: attempt.addingTimeInterval(-300), to: end) else { return [] }

            return LogNoise.realErrors(in: messages(in: output)).filter { !isHousekeeping($0) }
        }

        /// ⛔ Read-only. `log show` reads the system's own archive; it writes nothing and needs
        /// nothing granted.
        static func show(from start: Date, to end: Date) -> String? {
            let tool = URL(filePath: "/usr/bin/log")
            guard FileManager.default.isExecutableFile(atPath: tool.path(percentEncoded: false)) else {
                return nil
            }
            let arguments = ["show",
                             "--start", stamp(start),
                             "--end", stamp(end),
                             "--predicate", #"subsystem == "com.apple.TimeMachine" AND messageType == error"#,
                             "--style", "compact"]
            guard let data = Spawn.run(tool, arguments: arguments, timeout: 20) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }

        /// `log show` wants local wall-clock time in this exact shape.
        static func stamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }

        /// The message out of each compact line.
        ///
        /// A compact line is
        /// `2026-08-29 08:12:55.956 E  backupd[669:4cf173] [com.apple.TimeMachine:General] the message`
        /// — and note that the **process** bracket closes first. Taking everything after the first
        /// `] ` hands back the subsystem tag as though it were part of the message, so the anchor is
        /// the subsystem bracket itself, which is the one thing every line of this query has.
        ///
        /// The backwards search is the fallback for the day Apple changes the format: it keeps a
        /// message rather than losing one. `log show`'s header line has no closing bracket at all
        /// and falls away under both.
        static let subsystemTag = "[com.apple.TimeMachine:"

        static func messages(in output: String) -> [String] {
            output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
                let line = String(raw)
                let after: String.Index
                if let tag = line.range(of: subsystemTag),
                   let close = line.range(of: "] ", range: tag.upperBound..<line.endIndex) {
                    after = close.upperBound
                } else if let close = line.range(of: "] ", options: .backwards) {
                    after = close.upperBound
                } else {
                    return nil
                }
                let message = line[after...].trimmingCharacters(in: .whitespaces)
                return message.isEmpty ? nil : message
            }
        }
    }
}

// MARK: - Running a tool, with a watchdog

extension TimeMachineReader {

    /// Same shape as `ProtectionReader.run`, including the ordering that matters: the pipe is
    /// drained **before** `waitUntilExit`, because a child filling the pipe buffer while the parent
    /// waits for it to exit is a deadlock — and the Mac with a great deal to say is precisely the
    /// failing one this code path exists for.
    ///
    /// ⛔ Both callers are reads. Neither tool is invoked with a verb that changes anything, and
    /// nothing in this file runs `sudo`, `tmutil enable`, `tmutil disable`, `tmutil startbackup`,
    /// `tmutil latestbackup` or `diskutil` in any form.
    enum Spawn {

        static func run(_ tool: URL, arguments: [String], timeout: TimeInterval) -> Data? {
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            guard (try? process.run()) != nil else { return nil }

            let watchdog = Watchdog(process)
            let killer = DispatchWorkItem { watchdog.terminate() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            killer.cancel()

            guard process.terminationStatus == 0 else { return nil }
            return data
        }

        /// One `Process` reference, read by two threads, doing exactly one thing. `Process` is not
        /// `Sendable`; this is the narrowest possible admission of that.
        private final class Watchdog: @unchecked Sendable {
            private let process: Process
            init(_ process: Process) { self.process = process }
            func terminate() { if process.isRunning { process.terminate() } }
        }
    }
}
