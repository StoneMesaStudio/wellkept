// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  TimeMachineReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  **The guard on the sentence this section exists to get right: switched off is not failing.**
//
//  `TimeMachineState` already holds that precedence and `BackupTests` proves it in the abstract.
//  What is proved here is that the *reader* feeds it facts rather than conclusions — because the
//  2026-08-28 mistake was not made by the type, it was made by whoever looked at a log full of
//  errors and called a working Mac broken.
//
//  Four things are tested that nothing else can see:
//
//  1. **A recorded `RESULT` is thrown away in the two cases where it is no longer the last word** —
//     a later run succeeded, or the whole complaint was an absent drive that is now attached.
//  2. **The noise filter, against the real messages this Mac produced.** Every error-level line
//     `com.apple.TimeMachine` wrote in 24 hours — 1,400 of them, on a Mac whose last backup
//     succeeded — must come out empty, and an unrecognised message must survive.
//  3. **The snapshot sentence never promises bytes**, and says what the snapshot is *for* only when
//     it really is Time Machine's reference point.
//  4. **This Mac, live.** One test runs the real reader against the real machine, the way
//     `AppleWordsTests` does, because a reader that compiles and reads nothing is the failure mode
//     a hand-built fixture cannot catch.
//
//  ⚠️ Everything here is read-only. Nothing is mounted, unmounted, enabled, disabled or triggered,
//  and no test writes to any volume.

@Suite("Time Machine, read without permission")
struct TimeMachineReaderTests {

    // MARK: - Fixtures

    static let now = Date(timeIntervalSince1970: 1_787_000_000)   // a fixed afternoon
    static func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    /// ⭐ **This Mac's own record, as `cfprefsd` handed it over on 2026-08-29.** The keys and the
    /// shapes are copied from the real read; only the dates are moved onto the fixed clock so the
    /// "days since" sentences can be asserted.
    static func johnsMac(result: Int = 0,
                         lastSuccess: Double = 4,
                         lastAttempt: Double = 4.05) -> TimeMachineReader.Preferences.Destination {
        TimeMachineReader.Preferences.Destination(
            id: "9B081F90-EBE4-40A8-B6CE-F76456896027",
            volumeName: "JDS Backup",
            volumeUUIDs: ["34DD966B-07D3-432C-AA90-EF1151ECC2C2"],
            networkURL: nil,
            result: result,
            attempts: [daysAgo(87), daysAgo(60), daysAgo(32), daysAgo(lastAttempt)],
            successes: [daysAgo(87), daysAgo(72), daysAgo(60), daysAgo(lastSuccess)],
            bytesAvailable: 1_510_329_090_048,
            bytesUsed: 489_560_231_936,
            filesystem: "apfs",
            encryptionState: "NotEncrypted",
            referenceSnapshot: daysAgo(lastSuccess))
    }

    static func reading(_ destination: TimeMachineReader.Preferences.Destination?,
                        automaticBackupsOn: Bool) -> TimeMachineReader.Preferences.Reading {
        TimeMachineReader.Preferences.Reading(
            answered: true,
            automaticBackupsOn: automaticBackupsOn,
            destinations: destination.map { [$0] } ?? [],
            lastDestinationID: destination?.id)
    }

    // MARK: - ⭐ Switched off is not failing

    /// The whole point of the section, exercised through the reader rather than through the type.
    ///
    /// This is John's Mac to the letter: a configured destination, the drive in a drawer, the last
    /// backup four days old, and the switch off. The row must say **off**, not broken, and it must
    /// not use the word "failing" anywhere on it.
    @Test("A configured Mac with the switch off says off, not broken")
    func switchedOffReadsAsSwitchedOff() {
        let record = Self.johnsMac()
        let state = TimeMachineState(isConfigured: true,
                                     automaticBackupsOn: false,
                                     destination: BackupDestination(name: "JDS Backup",
                                                                    kind: .localDrive,
                                                                    isConnected: false),
                                     lastSuccess: record.lastSuccess,
                                     failure: TimeMachineReader.failure(for: record, isConnected: false))

        #expect(state.standing(now: Self.now) == .switchedOff)
        #expect(state.standing(now: Self.now).isAMalfunction == false)

        let row = TimeMachineReader.row(from: state,
                                        prefs: Self.reading(record, automaticBackupsOn: false),
                                        snapshots: .none,
                                        snapshotLine: nil,
                                        now: Self.now)

        #expect(row.headline.contains("switched off"))
        #expect(row.measure == "Last backup 4 days ago")
        #expect(row.reason?.contains("Nothing is broken") == true)
        for word in ["failing", "cannot reach", "error", "fault"] {
            #expect(row.facts.joined(separator: " ").lowercased().contains(word) == false,
                    "a Mac with the switch off must not be described with the word \"\(word)\"")
        }
    }

    /// The drive being in a drawer is somebody's system, not a fault — while it is recent.
    @Test("An unplugged drive is waiting, and only becomes a problem when it has been forgotten")
    func anUnpluggedDriveIsNotAFault() {
        func state(daysSince: Double) -> TimeMachineState {
            TimeMachineState(isConfigured: true,
                             automaticBackupsOn: true,
                             destination: BackupDestination(name: "JDS Backup",
                                                            kind: .localDrive,
                                                            isConnected: false),
                             lastSuccess: Self.daysAgo(daysSince))
        }
        #expect(state(daysSince: 4).standing(now: Self.now) == .waitingForTheDrive)
        #expect(state(daysSince: 4).severity(now: Self.now) == .attention)
        #expect(state(daysSince: 40).severity(now: Self.now) == .problem)
    }

    // MARK: - ⭐ Throwing a stale result away

    /// A `RESULT` is the outcome of one run. If a later run finished, it is not the last word.
    @Test("A failure recorded before a later success is not reported")
    func aLaterSuccessBuriesAnOlderFailure() {
        // Attempt 4.05 days ago, success 4 days ago: the success came after.
        let recovered = Self.johnsMac(result: 45, lastSuccess: 4, lastAttempt: 4.05)
        #expect(TimeMachineReader.failure(for: recovered, isConnected: false) == nil)

        // Attempt 3 days ago, success 4 days ago: the attempt is the last word, and it failed.
        let stillBroken = Self.johnsMac(result: 45, lastSuccess: 4, lastAttempt: 3)
        #expect(TimeMachineReader.failure(for: stillBroken, isConnected: false) != nil)
    }

    /// ⭐ "Plug the drive in" is the wrong thing to say to somebody who just did.
    @Test("A missing-drive failure is dropped once the drive is attached")
    func aResolvedAbsenceIsNotAFailure() {
        let record = Self.johnsMac(result: 18, lastSuccess: 4, lastAttempt: 3)

        #expect(TimeMachineReader.failure(for: record, isConnected: true) == nil,
                "the drive is here now — the recorded complaint is about a moment that has passed")

        let whileAbsent = TimeMachineReader.failure(for: record, isConnected: false)
        #expect(whileAbsent?.cause == .driveNotConnected)
    }

    /// Nothing is hidden by that drop: the row still says nothing has finished.
    @Test("Dropping the resolved absence still leaves an overdue Mac reading as overdue")
    func nothingIsHiddenByTheDrop() {
        let record = Self.johnsMac(result: 18, lastSuccess: 40, lastAttempt: 3)
        let state = TimeMachineState(isConfigured: true,
                                     automaticBackupsOn: true,
                                     destination: BackupDestination(name: "JDS Backup",
                                                                    kind: .localDrive,
                                                                    isConnected: true),
                                     lastSuccess: record.lastSuccess,
                                     failure: TimeMachineReader.failure(for: record, isConnected: true))
        #expect(state.standing(now: Self.now) == .overdue)
        #expect(state.severity(now: Self.now) == .problem)
    }

    @Test("A result of zero is never a failure")
    func successIsNotAFailure() {
        #expect(TimeMachineReader.failure(for: Self.johnsMac(result: 0), isConnected: false) == nil)
        #expect(TimeMachineReader.failure(for: nil, isConnected: false) == nil)
    }

    // MARK: - What stopped it

    /// ⚠️ Code 18 is the only one that was measured — `tmutil latestbackup` returned it on this Mac
    /// with the drive unplugged. Every other code has to fall through to the words.
    @Test("The one measured code is translated, and an unknown one is not guessed at")
    func onlyTheMeasuredCodeIsTranslated() {
        #expect(TimeMachineReader.cause(code: 18, messages: []) == .driveNotConnected)
        #expect(TimeMachineReader.cause(code: 45, messages: []) == .unknown)
        #expect(TimeMachineReader.cause(code: 999, messages: ["something new Apple invented"]) == .unknown)
    }

    /// The text rules match POSIX error names, which the C library writes the same way in every
    /// language — the bug `BatteryReader` shipped by comparing Apple's English.
    @Test("POSIX error names decide the cause")
    func posixNamesDecideTheCause() {
        let cases: [(String, FailureCause)] = [
            ("Error Domain=NSPOSIXErrorDomain Code=28 \"No space left on device\"", .driveFull),
            ("Error Domain=NSPOSIXErrorDomain Code=30 \"Read-only file system\"", .cannotWriteThere),
            ("Error Domain=NSPOSIXErrorDomain Code=1 \"Operation not permitted\"", .cannotWriteThere),
            ("The backup disk image is damaged and cannot be used", .destinationDamaged),
            ("Failed to mount destination", .driveNotConnected),
            ("Could not connect to the server", .cannotReachTheNetworkPlace),
            ("The backup was cancelled", .interrupted),
        ]
        for (message, expected) in cases {
            #expect(TimeMachineReader.cause(code: 45, messages: [message]) == expected,
                    "\(message) should read as \(expected.label)")
        }
    }

    /// Every cause we can produce has words for the person. `.unknown` is the one that admits it.
    @Test("Every cause the reader can produce has something to say")
    func everyCauseSaysSomething() {
        for cause in FailureCause.allCases {
            #expect(!cause.label.isEmpty)
            if cause != .unknown { #expect(cause.whatToDo != nil) }
        }
    }

    // MARK: - ⚠️ The noise, against the real thing

    /// ⭐ **Every error-level message this Mac wrote in 24 hours, on a Mac whose last backup
    /// succeeded.** Counted 2026-08-29: 1,191 + 63 + 2 XPC teardowns, 84 snapshot-list failures,
    /// 42 snapshot deletions against the read-only system volume, 18 vanished scratch mounts.
    /// **All 1,400 are noise, and the filter must take all of them.**
    static let everyMessageThisMacProduced = [
        "com.apple.backupd.sandbox.xpc: connection invalid",
        "com.apple.backupd.xpc: connection invalid",
        "com.apple.backupd.status.xpc: connection invalid",
        "fs_snapshot_list failed: Operation not supported",
        "Snapshot deletion failed for disk '/', timeout date: 4001-01-01 00:00:00 +0000, error: Error Domain=NSPOSIXErrorDomain Code=30 \"Read-only file system\"",
        "attrVolumeWithMountPoint 'file:///private/tmp/tmp-mount-y39ay2/' failed, error: Error Domain=NSPOSIXErrorDomain Code=2 \"No such file or directory\"",
        "attrVolumeWithMountPoint 'file:///Volumes/Recovery/' failed, error: Error Domain=NSPOSIXErrorDomain Code=2 \"No such file or directory\"",
    ]

    @Test("⭐ A day of this Mac's backup log filters down to nothing")
    func aWorkingMacProducesNoErrors() {
        let kept = LogNoise.realErrors(in: Self.everyMessageThisMacProduced)
            .filter { !TimeMachineReader.LogFilter.isHousekeeping($0) }
        #expect(kept.isEmpty, "a Mac whose backups all succeeded still read as broken: \(kept)")
    }

    /// The direction of safety. Both lists only subtract shapes somebody measured.
    @Test("A message nobody recognised is kept")
    func theUnrecognisedSurvivesBothFilters() {
        let real = "Backup failed with error 45: the backup disk image could not be created"
        let kept = LogNoise.realErrors(in: Self.everyMessageThisMacProduced + [real])
            .filter { !TimeMachineReader.LogFilter.isHousekeeping($0) }
        #expect(kept == [real])
    }

    /// A message that merely mentions one of the housekeeping words on its way somewhere else is
    /// not caught — the patterns are the start of a known line, not keywords.
    @Test("The housekeeping list does not swallow a real sentence")
    func housekeepingIsNarrow() {
        #expect(TimeMachineReader.LogFilter.isHousekeeping("fs_snapshot_list failed: Operation not supported"))
        #expect(TimeMachineReader.LogFilter.isHousekeeping("Backup failed: the drive is full") == false)
        #expect(TimeMachineReader.LogFilter.isHousekeeping("Snapshot could not be created on the backup drive") == false)
    }

    /// The compact-format parser, against real lines including the header `log show` prints first.
    @Test("The log parser takes the message and drops the header")
    func theLogParserWorks() {
        let output = """
            Timestamp               Ty Process[PID:TID]
            2026-08-29 08:12:55.956 E  backupd[669:4cf173] [com.apple.TimeMachine:General] com.apple.backupd.sandbox.xpc: connection invalid
            2026-08-29 08:13:03.004 E  backupd[669:4cf5c4] [com.apple.TimeMachine:General] Backup failed with error 45
            """
        let messages = TimeMachineReader.LogFilter.messages(in: output)
        #expect(messages.count == 2)
        #expect(messages.last == "Backup failed with error 45")
    }

    /// ⚠️ The log is never consulted without a reason, and never over a window that costs seconds.
    /// Measured: 4.4 s for 24 hours against 1.8 s for the four minutes a run occupies.
    @Test("The log is not read when there is nothing to look up")
    func theLogIsNotReadWithoutReason() {
        #expect(TimeMachineReader.LogFilter.realErrors(around: nil, now: Self.now).isEmpty)

        let tooOld = Self.now.addingTimeInterval(-TimeMachineReader.LogFilter.maxLookbackHours * 3600 - 60)
        #expect(TimeMachineReader.LogFilter.realErrors(around: tooOld, now: Self.now).isEmpty)

        let inTheFuture = Self.now.addingTimeInterval(3600)
        #expect(TimeMachineReader.LogFilter.realErrors(around: inTheFuture, now: Self.now).isEmpty)
    }

    @Test("The timestamp is in the shape log show wants")
    func theStampIsRight() {
        let stamp = TimeMachineReader.LogFilter.stamp(Self.now)
        #expect(stamp.count == 19)
        #expect(stamp.contains("-") && stamp.contains(":") && stamp.contains(" "))
    }

    // MARK: - ⭐ The snapshot, and the fact that belongs in this section

    static func snapshot(_ date: Date) -> SnapshotStanding {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        return SnapshotStanding(snapshots: [LocalSnapshot(name: "com.apple.TimeMachine.\(stamp.string(from: date)).local",
                                                          takenOn: date)])
    }

    /// ⭐ On this Mac the stuck snapshot and `ReferenceLocalSnapshotDate` are the same instant to
    /// the second — 2026-08-25 06:25:03 MDT and 2026-08-25 12:25:03 UTC. That is what lets the
    /// sentence say what the snapshot is **for**, and give somebody an action.
    @Test("When the stuck snapshot is Time Machine's reference point, the sentence says so")
    func theReferencePointIsNamed() {
        let taken = Self.daysAgo(9)
        let line = TimeMachineReader.snapshotSentence(snapshots: Self.snapshot(taken),
                                                      referencePoint: taken,
                                                      now: Self.now)
        #expect(line?.contains("the point the next backup starts from") == true)
        #expect(line?.contains("Letting one backup finish releases it") == true)
    }

    /// A snapshot that is not the reference point still gets the plain fact and no explanation we
    /// cannot support.
    @Test("An unrelated stuck snapshot gets the fact and not the story")
    func anUnrelatedSnapshotGetsTheShortSentence() {
        let taken = Self.daysAgo(9)
        let line = TimeMachineReader.snapshotSentence(snapshots: Self.snapshot(taken),
                                                      referencePoint: Self.daysAgo(40),
                                                      now: Self.now)
        #expect(line?.contains("frees no space") == true)
        #expect(line?.contains("the point the next backup starts from") == false)
    }

    /// ⚠️ The sentence promises a release, never a figure. How many bytes come back is Storage's
    /// arithmetic afterwards, not ours to predict.
    @Test("The snapshot sentence never quotes a size")
    func theSnapshotSentenceNeverQuotesASize() {
        for reference in [Self.daysAgo(9), Self.daysAgo(40)] {
            let line = TimeMachineReader.snapshotSentence(snapshots: Self.snapshot(Self.daysAgo(9)),
                                                          referencePoint: reference,
                                                          now: Self.now) ?? ""
            for unit in ["GB", "MB", "KB", "bytes", "%"] {
                #expect(line.contains(unit) == false, "the snapshot line quoted \(unit)")
            }
        }
    }

    /// Nothing is said when there is nothing worth saying — no snapshots, a fresh one macOS will
    /// thin by itself, or a listing that failed.
    @Test("A snapshot macOS will clear by itself is not mentioned")
    func aFreshSnapshotIsSilent() {
        #expect(TimeMachineReader.snapshotSentence(snapshots: .none,
                                                   referencePoint: nil, now: Self.now) == nil)
        #expect(TimeMachineReader.snapshotSentence(snapshots: Self.snapshot(Self.daysAgo(1)),
                                                   referencePoint: Self.daysAgo(1), now: Self.now) == nil)
        #expect(TimeMachineReader.snapshotSentence(snapshots: .couldNotBeRead,
                                                   referencePoint: nil, now: Self.now) == nil)
    }

    /// A failed listing and an empty one are opposite answers, and the details must not read alike.
    @Test("Not reading the snapshots is not the same as there being none")
    func unreadIsNotTheSameAsNone() {
        let none = TimeMachineReader.snapshotDetails(.none, referencePoint: nil, now: Self.now)
        let unread = TimeMachineReader.snapshotDetails(.couldNotBeRead, referencePoint: nil, now: Self.now)
        #expect(none.first?.value == "None")
        #expect(unread.first?.value == Unreadable.notReported.sentence)
    }

    // MARK: - Reading the preferences

    /// The record is parsed out of the keys Apple actually writes, copied from this Mac's own read.
    @Test("This Mac's recorded destination parses")
    func theRealShapeParses() {
        let raw: [String: Any] = [
            "DestinationID": "9B081F90-EBE4-40A8-B6CE-F76456896027",
            "LastKnownVolumeName": "JDS Backup",
            "DestinationUUIDs": ["34DD966B-07D3-432C-AA90-EF1151ECC2C2"],
            "RESULT": 0,
            "BytesAvailable": 1_510_329_090_048,
            "BytesUsed": 489_560_231_936,
            "FilesystemTypeName": "apfs",
            "LastKnownEncryptionState": "NotEncrypted",
            "SnapshotDates": [Self.daysAgo(87), Self.daysAgo(4), Self.daysAgo(60)],
            "AttemptDates": [Self.daysAgo(4.05)],
            "ReferenceLocalSnapshotDate": Self.daysAgo(4),
        ]
        let record = TimeMachineReader.Preferences.destination(from: raw)

        #expect(record.displayName == "JDS Backup")
        #expect(record.kind == .localDrive)
        #expect(record.result == 0)
        #expect(record.successes.count == 3)
        #expect(record.lastSuccess == Self.daysAgo(4), "the successes must be sorted oldest first")
        #expect(record.lastAttempt == Self.daysAgo(4.05))
        #expect(record.referenceSnapshot == Self.daysAgo(4))
        #expect(record.filesystem == "apfs")
    }

    /// ⚠️ The kind is decided by which keys are present, never by `tmutil`'s English word "Local".
    @Test("A network destination is recognised by its address, not by a translated word")
    func theKindComesFromTheKeysNotTheWords() {
        let network = TimeMachineReader.Preferences.destination(from: [
            "NetworkURL": "afp://timecapsule.local/Backups",
            "RESULT": 0,
        ])
        #expect(network.kind == .networkShare)
        #expect(network.kind.isPluggedIn == false, "\"plug the drive in\" is wrong for a network share")
        #expect(network.displayName == "afp://timecapsule.local/Backups")

        let bare = TimeMachineReader.Preferences.destination(from: ["RESULT": 0])
        #expect(bare.kind == .unknown)
        #expect(bare.displayName == "the backup destination")
    }

    @Test("Anything that is not a date is dropped rather than guessed at")
    func datesAreParsedStrictly() {
        let parsed = TimeMachineReader.Preferences.dates([Self.daysAgo(2), "not a date", 17, Self.daysAgo(9)] as [Any])
        #expect(parsed == [Self.daysAgo(9), Self.daysAgo(2)])
        #expect(TimeMachineReader.Preferences.dates(nil).isEmpty)
    }

    /// Where there are several destinations, the one macOS itself last used is the one a person
    /// means.
    @Test("The destination macOS last used is the one reported")
    func theLastUsedDestinationWins() {
        let other = TimeMachineReader.Preferences.destination(from: ["DestinationID": "OTHER"])
        let reading = TimeMachineReader.Preferences.Reading(answered: true,
                                                            automaticBackupsOn: true,
                                                            destinations: [other, Self.johnsMac()],
                                                            lastDestinationID: Self.johnsMac().id)
        #expect(reading.chosenDestination?.volumeName == "JDS Backup")
    }

    // MARK: - The details behind Options

    /// ⚠️ The drive's capacity in the preferences is whatever it was the last time the drive was
    /// attached. It is labelled as such rather than printed as if it were today's figure.
    @Test("Stale capacity figures say when they were taken")
    func staleFiguresAreLabelled() {
        let whileAway = TimeMachineReader.historyDetails(Self.johnsMac(), isConnected: false)
        #expect(whileAway.contains { $0.label.contains("when it was last connected") })

        let whileHere = TimeMachineReader.historyDetails(Self.johnsMac(), isConnected: true)
        #expect(whileHere.contains { $0.label.contains("when it was last connected") } == false,
                "with the drive attached the live figures are on the destination itself")
    }

    /// Four backups in three months — the fact that made the owner's Mac legible.
    @Test("The backup history is reported with its span")
    func theHistoryCarriesItsSpan() {
        let pairs = TimeMachineReader.historyDetails(Self.johnsMac(), isConnected: false)
        let backups = pairs.first { $0.label == "Backups recorded" }
        #expect(backups?.value.hasPrefix("4, from ") == true)
    }

    /// ⚠️ Apple's stored keys are shown in a person's words, and anything unrecognised is passed
    /// through rather than dropped. `NotEncrypted` is a key, not a translation — it reads the same
    /// on a French Mac — which is what makes comparing it safe.
    @Test("Apple's stored keys are turned into words, and an unknown one survives")
    func storedKeysBecomeWords() {
        #expect(TimeMachineReader.Words.format("apfs") == "APFS")
        #expect(TimeMachineReader.Words.format("zfs") == "zfs")
        #expect(TimeMachineReader.Words.encryption("NotEncrypted") == "Not encrypted")
        #expect(TimeMachineReader.Words.encryption("Encrypted") == "Encrypted")
        #expect(TimeMachineReader.Words.encryption("SomethingNew") == "SomethingNew")

        let pairs = TimeMachineReader.historyDetails(Self.johnsMac(), isConnected: false)
        #expect(pairs.first { $0.label == "Backup drive format" }?.value == "APFS")
        #expect(pairs.first { $0.label == "Backup drive encryption" }?.value == "Not encrypted")
    }

    /// A destination identifier is a machine identifier. It is marked so the "copy this for a
    /// repair shop" button can show what is about to leave.
    @Test("The destination ID is marked sensitive")
    func theDestinationIDIsMarkedSensitive() {
        let pairs = TimeMachineReader.historyDetails(Self.johnsMac(), isConnected: false)
        #expect(pairs.first { $0.label == "Destination ID" }?.sensitive == true)
    }

    // MARK: - The row

    /// A state we could not read claims nothing else, and carries no button — there is no
    /// permission that would have changed the answer.
    @Test("An unreadable state says so and offers no door")
    func anUnreadableStateOffersNoDoor() {
        let row = TimeMachineReader.row(from: .couldNotRead(.notReported),
                                        prefs: .nothing,
                                        snapshots: .couldNotBeRead,
                                        snapshotLine: nil,
                                        now: Self.now)
        #expect(row.status == .notChecked)
        #expect(row.severity == .information)
        #expect(row.measure == nil)
        #expect(row.remedy == nil)
        #expect(row.complete, "a refusal nobody can lift does not make the check incomplete")
    }

    /// The button opens the pane. It never switches anything on.
    @Test("The row's button is a destination, and the pane exists")
    func theButtonIsADestination() {
        let state = TimeMachineState(isConfigured: true, automaticBackupsOn: false,
                                     destination: BackupDestination(name: "JDS Backup",
                                                                    kind: .localDrive,
                                                                    isConnected: false),
                                     lastSuccess: Self.daysAgo(4))
        let remedy = state.remedy(now: Self.now)
        #expect(remedy?.title == "Open Time Machine settings")
        #expect(remedy?.settingsPane == SystemSettingsPane.timeMachine.rawValue,
                "Core names a pane the app layer must actually have, or the button does nothing")
        #expect(SystemSettingsPane(rawValue: remedy?.settingsPane ?? "") != nil)
    }

    /// A Mac that has never had a backup drive is an absence, not a fault — Wellkept can only see
    /// Time Machine, and somebody using another tool has a backup we cannot see.
    @Test("A Mac that never set up Time Machine is not called unprotected")
    func neverSetUpIsNotAFault() {
        let state = TimeMachineState(isConfigured: false, automaticBackupsOn: false)
        #expect(state.standing(now: Self.now) == .neverSetUp)
        #expect(state.severity(now: Self.now) == .attention)

        let row = TimeMachineReader.row(from: state,
                                        prefs: Self.reading(nil, automaticBackupsOn: false),
                                        snapshots: .none, snapshotLine: nil, now: Self.now)
        #expect(row.measure == nil)
        #expect(row.headline.contains("Wellkept cannot see it"))
    }

    /// The snapshot line rides under the reason rather than replacing it. Both are true and both
    /// are said.
    @Test("The snapshot line joins the reason rather than replacing it")
    func theSnapshotLineJoinsTheReason() {
        let state = TimeMachineState(isConfigured: true, automaticBackupsOn: false,
                                     destination: BackupDestination(name: "JDS Backup",
                                                                    kind: .localDrive,
                                                                    isConnected: false),
                                     lastSuccess: Self.daysAgo(4))
        let row = TimeMachineReader.row(from: state,
                                        prefs: Self.reading(Self.johnsMac(), automaticBackupsOn: false),
                                        snapshots: .none,
                                        snapshotLine: "A snapshot is holding space.",
                                        now: Self.now)
        #expect(row.reason?.contains("Automatic backups are turned off") == true)
        #expect(row.reason?.contains("A snapshot is holding space.") == true)
    }

    // MARK: - ⭐ This Mac, live

    /// ⚠️ **This test reads the real machine**, the way `AppleWordsTests` does, because a reader
    /// that compiles and reads nothing is exactly the failure a fixture cannot catch. Every
    /// expectation below is true of any Mac — nothing here depends on John's drive existing.
    ///
    /// ⛔ Read-only. It mounts nothing, changes nothing, and needs no permission — which is the
    /// claim it is really testing.
    @Test("The reader runs on this Mac and reads without being granted anything")
    func itReadsThisMac() {
        let answer = TimeMachineReader.read()

        #expect(answer.row.topic == .appleBackup)
        #expect(!answer.row.headline.isEmpty)

        if answer.state.unreadable == nil {
            // A configured Mac must be able to name where its backup goes; an unconfigured one must
            // not invent one.
            #expect(answer.state.isConfigured == (answer.state.destination != nil))
        }

        if let last = answer.state.lastSuccess {
            #expect(last <= Date().addingTimeInterval(60), "a backup dated in the future is a parse bug")
        }

        // The snapshot list is this Mac's own; either it read or it said it could not.
        if answer.snapshots.wasRead, let oldest = answer.snapshots.oldest {
            #expect(oldest.takenOn <= Date())
        }

        // ⛔ Whatever this Mac's state is, the row must never describe a switch as a malfunction.
        if answer.state.standing() == .switchedOff {
            #expect(answer.row.reason?.contains("Nothing is broken") == true)
        }
    }

    // MARK: - ⛔ The guard: this reader only ever reads

    /// **Nothing in this file may name a verb that changes a volume or a backup.**
    ///
    /// A behaviour test cannot catch this: by the time one could observe a mount, it has happened
    /// on somebody's real drive. So the source is read instead, the same instrument as
    /// `RehearsalGateGuardTests` and `StorageLawGuardTests`.
    @Test("⛔ The reader names no verb that changes anything")
    func theReaderOnlyReads() {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tools/AppTests
            .deletingLastPathComponent()      // Tools
            .deletingLastPathComponent()      // the repository
            .appendingPathComponent("App/Backup/TimeMachineReader.swift")

        guard let body = try? String(contentsOf: path, encoding: .utf8) else {
            Issue.record("the reader could not be read at \(path.path)")
            return
        }

        // Code lines only: the file explains at length why it does not do these things, and a guard
        // that fires on its own explanation is useless.
        let code = body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") && !$0.hasPrefix("*") }
            .joined(separator: "\n")

        let forbidden = ["\"enable\"", "\"disable\"", "\"startbackup\"", "\"stopbackup\"",
                         "\"latestbackup\"", "\"setdestination\"", "\"removedestination\"",
                         "\"localsnapshot\"", "\"deletelocalsnapshots\"", "\"delete\"",
                         "diskutil", "CFPreferencesSetValue", "CFPreferencesSynchronize",
                         "unmount", "sudo"]
        for verb in forbidden {
            #expect(code.contains(verb) == false,
                    "TimeMachineReader names \(verb) — this file only reads")
        }

        // And the two arguments it IS allowed to pass.
        #expect(code.contains("\"destinationinfo\""))
        #expect(code.contains("\"show\""))
    }
}
