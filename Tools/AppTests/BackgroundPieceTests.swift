// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  BackgroundPieceTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The Login Item: what it is called, when it acts, what it refuses, and the sentence it made
//  false.**
//
//  ⚠️ Nothing here registers a login item, starts a process, or touches a drive. The schedule is
//  arithmetic and is tested as arithmetic; the sight probes are run against a pretend home folder
//  this file makes and throws away.

// MARK: - ⭐ Identity: the plist and the Swift cannot drift

@Suite("The Login Item is called the same thing in both places")
struct BackgroundPieceIdentityTests {

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests/
            .deletingLastPathComponent()   // Tools/
            .deletingLastPathComponent()   // the repository
    }

    static var plist: [String: Any] {
        let url = repositoryRoot
            .appendingPathComponent("Resources/LaunchAgents")
            .appendingPathComponent(BackgroundPiece.plistName)
        guard let data = try? Data(contentsOf: url),
              let parsed = try? PropertyListSerialization
                  .propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return parsed
    }

    /// ⚠️ A label typed twice is a job registered under one name and unregistered under another —
    /// which leaves a row in System Settings ▸ Login Items that nobody can clear.
    @Test func theLabelInTheCodeIsTheLabelInThePlist() {
        #expect(!Self.plist.isEmpty, "the launch agent plist was not found or would not parse")
        #expect(Self.plist["Label"] as? String == BackgroundPiece.label)
    }

    /// ⭐ The whole Full Disk Access argument rests on this being the app's own executable.
    @Test func itRunsTheAppsOwnExecutable() {
        #expect(Self.plist["BundleProgram"] as? String == "Contents/MacOS/Wellkept",
                "a separate helper is a different code signature, and macOS decides Full Disk Access from the signature")
    }

    @Test func theFlagIsTheOneTheEntryPointLooksFor() {
        let arguments = Self.plist["ProgramArguments"] as? [String] ?? []
        #expect(arguments.contains(BackgroundPiece.launchArgument))
        #expect(BackgroundPiece.isTheBackgroundPiece(arguments))
    }

    /// Without this the Login Items row shows a reverse-DNS label. Somebody who cannot place a
    /// background item switches it off, and they are right to.
    @Test func itIsListedUnderWellkeptsOwnName() {
        let associated = Self.plist["AssociatedBundleIdentifiers"] as? [String] ?? []
        #expect(associated.contains("studio.stonemesa.wellkept"))
    }

    @Test func theAppItselfIsNotTheBackgroundPiece() {
        #expect(!BackgroundPiece.isTheBackgroundPiece(["/Applications/Wellkept.app/Contents/MacOS/Wellkept"]))
        // ⚠️ argv[0] is dropped before looking, so an executable that happened to be *named* the
        // flag could not turn the app into its own background piece.
        #expect(!BackgroundPiece.isTheBackgroundPiece([BackgroundPiece.launchArgument]))
    }

    /// John's number, and there is no fourth job.
    @Test func itDoesExactlyThreeThings() {
        #expect(BackgroundPiece.Job.allCases.count == 3)
        #expect(BackgroundPiece.Job.allCases.filter(\.copiesFiles).count == 2)
        #expect(BackgroundPiece.Job.noticeABackupThatHasGoneQuiet.copiesFiles == false,
                "noticing is looking, not touching — it is the one job that may run before the gate opens")
    }
}

// MARK: - ⛔ The gate, and what it refuses today

@Suite("The background piece looks and does not copy")
struct BackgroundPieceGateTests {

    @Test func theGateRefusesTheBackgroundPieceOnEveryMacToday() {
        let decision = RehearsalGate.permissionForTheBackgroundPiece(to: "a drive")
        #expect(!decision.isGranted)
        let missing = decision.refusal?.missing ?? []
        #expect(missing.contains(.rehearsal))
        #expect(missing.contains(.agentFullDiskAccess),
                "a scheduled backup that cannot read mail reports success and holds nothing")
    }

    /// ⭐ The rule that makes this feature useful before the gate opens: *automatic means looking.*
    @Test func theNoticeStillHappensWhileCopyingIsRefused() {
        let now = Date()
        let decision = AgentSchedule.decide(
            now: now,
            driveIsConnected: true,
            lastRunStarted: nil,
            lastSuccess: now.addingTimeInterval(-25 * 86_400),
            mayCopy: false,
            missing: [.rehearsal, .agentFullDiskAccess])

        #expect(!decision.action.isACopy)
        #expect(decision.notice != nil, "the one job that does not write to a drive must still run")
        #expect(decision.notice?.contains("25 days ago") == true)
    }

    @Test func aRefusalExplainsItselfInWords() {
        let decision = AgentSchedule.decide(now: Date(), driveIsConnected: true,
                                            lastRunStarted: nil, lastSuccess: Date(),
                                            mayCopy: false, missing: [.agentFullDiskAccess])
        #expect(decision.action.sentence.contains("Copied nothing"))
        #expect(decision.action.sentence.contains("mail"))
    }
}

// MARK: - The schedule, as arithmetic

@Suite("When the background piece acts")
struct AgentScheduleTests {

    private static let hour: TimeInterval = 3600

    @Test func hourlyWhileTheDriveIsConnected() {
        let now = Date()
        let justRan = AgentSchedule.decide(now: now, driveIsConnected: true,
                                           lastRunStarted: now.addingTimeInterval(-60),
                                           lastSuccess: now, mayCopy: true)
        if case .waitUntil = justRan.action {} else { Issue.record("should be waiting: \(justRan.action)") }

        let anHourAgo = AgentSchedule.decide(now: now, driveIsConnected: true,
                                             lastRunStarted: now.addingTimeInterval(-Self.hour),
                                             lastSuccess: now, mayCopy: true)
        #expect(anHourAgo.action == .backUpNow(.anHourHasPassed))
    }

    @Test func nothingHasEverRunIsItsOwnReason() {
        let decision = AgentSchedule.decide(now: Date(), driveIsConnected: true,
                                            lastRunStarted: nil, lastSuccess: nil, mayCopy: true)
        #expect(decision.action == .backUpNow(.nothingHasEverRun))
    }

    @Test func noDriveMeansWaitForTheDrive() {
        let decision = AgentSchedule.decide(now: Date(), driveIsConnected: false,
                                            lastRunStarted: nil, lastSuccess: Date(), mayCopy: true)
        #expect(decision.action == .waitForTheDrive)
    }

    /// ⚠️ **The bug this shape was written to prevent.** An earlier version folded the stale notice
    /// into the action, so a Mac whose drive had been away a fortnight reported "your backup has
    /// gone quiet" *instead of* "waiting for the drive" — and plugging the drive in started nothing.
    @Test func aQuietBackupDoesNotReplaceTheAction() {
        let now = Date()
        let decision = AgentSchedule.decide(now: now, driveIsConnected: false,
                                            lastRunStarted: nil,
                                            lastSuccess: now.addingTimeInterval(-30 * 86_400),
                                            mayCopy: true)
        #expect(decision.action == .waitForTheDrive)
        #expect(decision.notice != nil)
    }

    @Test func pluggingTheDriveInStartsOneImmediately() {
        let decision = AgentSchedule.decideOnConnect(lastSuccess: Date(), mayCopy: true)
        #expect(decision.action == .backUpNow(.theDriveWasPluggedIn))
    }

    /// Nine days is John's number, and it is taken from Core rather than repeated here.
    @Test func nineDaysIsWhereItSaysSomething() {
        let now = Date()
        #expect(AgentSchedule.quietAfterDays == BackupFreshness.staleAfterDays)
        #expect(AgentSchedule.noticeAboutAQuietBackup(
            lastSuccess: now.addingTimeInterval(-8 * 86_400), now: now) == nil)
        #expect(AgentSchedule.noticeAboutAQuietBackup(
            lastSuccess: now.addingTimeInterval(-9 * 86_400), now: now) != nil)
    }

    @Test func neverIsSaidAsNeverRatherThanAsANumber() {
        let notice = AgentSchedule.noticeAboutAQuietBackup(lastSuccess: nil)
        #expect(notice == "No backup has ever finished on this Mac.")
    }
}

// MARK: - ⭐ The self-check, and the third answer

@Suite("What the background piece can see, established rather than assumed")
struct AgentSightTests {

    /// ⭐ **The whole reason this is not a two-state check.** macOS refuses a protected folder by
    /// handing back an empty listing and no error, which is indistinguishable from an empty folder.
    @Test func anEmptyFolderIsNotProofOfAnything() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try FileManager.default.createDirectory(at: sandbox.home.appending(path: ".Trash"),
                                                withIntermediateDirectories: true)
        #expect(AgentSight.read(.trash, home: sandbox.home) == .cannotTell)
    }

    @Test func aFolderWithSomethingInItIsProof() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file(".Trash/something.txt")
        #expect(AgentSight.read(.trash, home: sandbox.home) == .saw)
    }

    @Test func aFileThatCanBeReadIsProof() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Library/Safari/Bookmarks.plist")
        #expect(AgentSight.read(.safari, home: sandbox.home) == .saw)
    }

    /// A Mac with no Mail account is not a Mac we were refused on, and must never be counted as one.
    @Test func nothingThereIsNotARefusal() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        #expect(AgentSight.read(.mail, home: sandbox.home) == .notThere)
        #expect(AgentSight.read(.messages, home: sandbox.home) == .notThere)
    }

    /// ⚠️ **An allow-list, not a ban-list, and that is the whole point.**
    ///
    /// `ContainerGuardTests` forbids reaching into another app's sandboxed data, because macOS
    /// raises "would like to access data from other apps" on the attempt and puts a dialog on
    /// somebody's screen with Wellkept's name on it. A test that banned the two folder names would
    /// pass the day a seventh probe reached a third one. So every probe has to be under a place
    /// named here, and adding one is an edit somebody has to justify.
    @Test func everyProbeIsSomewhereOnThisList() {
        let allowed = ["Library/Mail", "Library/Messages", "Library/Safari",
                       "Library/Application Support/AddressBook", "Pictures", ".Trash"]
        let home = URL(filePath: "/Users/example")

        for place in ProtectedPlace.allCases {
            for probe in AgentSight.candidates(for: place, home: home) {
                let path = probe.url.path(percentEncoded: false)
                #expect(path.hasPrefix("/Users/example/"),
                        Comment(rawValue: "probe outside the home folder: \(path)"))
                let inside = String(path.dropFirst("/Users/example/".count))
                #expect(allowed.contains { inside == $0 || inside.hasPrefix($0 + "/") },
                        Comment(rawValue: "probe in a place this test does not know about: \(inside)"))
            }
        }
    }
}

// MARK: - ⭐ The comparison, which is the answer

@Suite("The background piece is compared with the window, not trusted")
struct AgentVerdictTests {

    private func sight(_ who: Watcher, saw: [ProtectedPlace], unclear: [ProtectedPlace] = []) -> AgentSight {
        AgentSight(takenBy: who, takenOn: Date(), executablePath: "/x", fullDiskAccessProbe: true,
                   sightings: ProtectedPlace.allCases.map {
                       Sighting(place: $0, path: "/x",
                                reading: saw.contains($0) ? .saw
                                       : unclear.contains($0) ? .cannotTell : .notThere)
                   })
    }

    /// ⛔ **The failure the whole file exists to catch.**
    @Test func aBackgroundPieceThatCannotSeeMailIsCaught() {
        let verdict = AgentVerdict.compare(app: sight(.theApp, saw: [.mail, .photos]),
                                           agent: sight(.theBackgroundPiece, saw: [.photos]))
        #expect(verdict == .blind(missing: [.mail]))
        #expect(!verdict.isProof)
        #expect(verdict.sentence.contains("macOS would report no error"))
    }

    @Test func seeingEverythingTheWindowSawIsTheOnlyPass() {
        let verdict = AgentVerdict.compare(app: sight(.theApp, saw: [.mail, .photos]),
                                           agent: sight(.theBackgroundPiece, saw: [.mail, .photos, .trash]))
        #expect(verdict == .sawEverythingTheAppSaw)
        #expect(verdict.isProof)
    }

    /// ⚠️ `.cannotTell` never counts as sight, in either direction.
    @Test func aShrugIsNotAPass() {
        let verdict = AgentVerdict.compare(app: sight(.theApp, saw: [.mail]),
                                           agent: sight(.theBackgroundPiece, saw: [], unclear: [.mail]))
        #expect(verdict == .blind(missing: [.mail]))
    }

    @Test func nothingToCompareWithIsNeitherAPassNorAFailure() {
        let verdict = AgentVerdict.compare(app: nil, agent: sight(.theBackgroundPiece, saw: [.mail]))
        #expect(verdict == .nothingToCompareWith)
        #expect(!verdict.isProof)
    }

    @Test func twoBlindProcessesAreInconclusiveRatherThanAgreeing() {
        let verdict = AgentVerdict.compare(app: sight(.theApp, saw: [], unclear: [.trash]),
                                           agent: sight(.theBackgroundPiece, saw: [], unclear: [.trash]))
        #expect(verdict == .inconclusive(unclear: [.trash]))
        #expect(!verdict.isProof)
    }

    /// ⛔ **A good verdict is evidence for a human, not permission for the app.** Nothing about the
    /// record can open the gate; `RehearsalGate.agentHoldsFullDiskAccess` is typed by a person.
    @Test func aGoodVerdictDoesNotOpenTheGate() {
        var record = AgentRecord()
        record.noted(sight(.theApp, saw: [.mail]))
        record.noted(sight(.theBackgroundPiece, saw: [.mail]))
        #expect(record.holdsTheEvidence)
        #expect(record.proofSentence != nil)
        #expect(!RehearsalGate.agentIsProved,
                "the record cleared its own safety check — the gate constant must be a human edit")
        #expect(!RehearsalGate.permissionForTheBackgroundPiece(to: "a drive").isGranted)
    }
}

// MARK: - The record on disk

@Suite("The record survives a round trip and an older build")
struct AgentRecordTests {

    @Test func itWritesAndReadsBack() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let url = sandbox.home.appending(path: "BackgroundPiece.json")

        var record = AgentRecord()
        record.noted("Started.", on: Date(timeIntervalSince1970: 1_000))
        record.lastSuccessfulBackup = Date(timeIntervalSince1970: 2_000)
        #expect(record.write(to: url))

        let back = AgentRecord.read(at: url)
        #expect(back.runs.count == 1)
        #expect(back.runs.first?.what == "Started.")
        #expect(back.lastSuccessfulBackup == Date(timeIntervalSince1970: 2_000))
    }

    /// ⚠️ **A record written by an older build must not be unreadable.** Swift's own decoder treats a
    /// missing non-optional key as a failure, which would silently lose the app's sighting after an
    /// update — and the comparison is the entire point of the file.
    @Test func anOlderRecordStillReads() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let url = sandbox.home.appending(path: "old.json")
        try Data("{}".utf8).write(to: url)

        let back = AgentRecord.read(at: url)
        #expect(back.runs.isEmpty)
        #expect(back.app == nil)
        #expect(back.verdict == .nothingToCompareWith)
    }

    /// A missing file is an empty record, never a crash and never an error. A background piece that
    /// refused to start because its own log would not parse is worse than the log.
    @Test func aMissingRecordIsAnEmptyOne() {
        let record = AgentRecord.read(at: URL(filePath: "/nowhere/at/all/BackgroundPiece.json"))
        #expect(record.runs.isEmpty)
        #expect(!record.holdsTheEvidence)
    }

    @Test func theLogHasACeiling() {
        var record = AgentRecord()
        for index in 0..<(AgentRecord.keepAtMost + 20) {
            record.noted("line \(index)", on: Date(timeIntervalSince1970: TimeInterval(index)))
        }
        #expect(record.runs.count == AgentRecord.keepAtMost)
        #expect(record.runs.first?.what == "line 20", "the oldest lines go, not the newest")
    }
}

// MARK: - The uninstaller can take it back

@Suite("The Login Item is declared where the uninstaller reads")
struct BackgroundPieceManifestTests {

    /// ⚠️ **Unregister comes first, before the bundle moves.** Once the app is in the Trash, macOS
    /// cannot find the job at the path it was registered from and the Login Items row survives for
    /// years with no way to clear it.
    @Test func theLoginItemIsInTheManifest() {
        #expect(StorageManifest.BackgroundItems.loginItemPlists.contains(BackgroundPiece.plistName))
        #expect(StorageManifest.BackgroundItems.loginItemLabels.contains(BackgroundPiece.label))
    }

    @Test func theUninstallerUnregistersBeforeItMovesAnything() {
        let source = BackgroundPieceSource.text("App/Uninstaller.swift")
        guard let unregister = source.range(of: "unregisterBackgroundItems()"),
              let trash = source.range(of: "trashItem(at: app")
        else { Issue.record("the uninstaller no longer has both steps"); return }
        #expect(unregister.lowerBound < trash.lowerBound,
                "the bundle moves before the login item is handed back — the row would survive for years")
    }

    @Test func theRecordIsDeclaredAndIsOursToDelete() {
        let path = StorageManifest.backgroundPieceRecord().path(percentEncoded: false)
        #expect(path.hasSuffix("Application Support/Wellkept/BackgroundPiece.json"))
    }
}

// MARK: - ⚠️ The sentence that stopped being true

/// Reads the repository's own text. Same instrument as the other guards in this suite.
enum BackgroundPieceSource {
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func text(_ relative: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)) ?? ""
    }

    static func files(in directory: String, extension ext: String) -> [String] {
        let base = root.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        else { return [] }
        var found: [String] = []
        for case let url as URL in walker where url.pathExtension == ext {
            found.append(String(url.path.dropFirst(root.path.count + 1)))
        }
        return found.sorted()
    }
}

@Suite("Nothing still says Wellkept has no background piece")
struct BackgroundPieceWordingTests {

    /// The one file allowed to contain the old wording is the one that records it so this test can
    /// look for it.
    static let permitted = "App/Backup/Agent/BackgroundPiece.swift"

    @Test func theScannerIsLookingAtTheRightPlace() {
        let files = BackgroundPieceSource.files(in: "App", extension: "swift")
        #expect(files.count > 20)
        #expect(files.contains(Self.permitted))
    }

    /// ⛔ It was in the Help page, three source files and `docs/CONTRACTS.md`. Deleting the claim was
    /// not enough — the failure mode is somebody copying a familiar sentence forward from a file
    /// nobody re-read.
    @Test func theOldClaimIsGoneFromEveryFile() {
        var offenders: [String] = []
        let places = BackgroundPieceSource.files(in: "App", extension: "swift") + ["docs/CONTRACTS.md"]
        for relative in places where relative != Self.permitted {
            let body = BackgroundPieceSource.text(relative).lowercased()
            for banned in BackgroundPiece.sentencesThatAreNoLongerTrue where body.contains(banned) {
                offenders.append("\(relative): “\(banned)”")
            }
        }
        #expect(offenders.isEmpty, """
            These still say Wellkept has no background piece: \(offenders.joined(separator: "; ")).
            It took a Login Item on 2026-08-29. The replacement is Backup.whatHappensWhenTheWindowCloses,
            and it keeps both halves — the app still quits unless the person switches this on.
            """)
    }

    /// The replacement is on the page a person actually reads, not only in a comment.
    @Test func helpCarriesTheReplacement() {
        let help = BackgroundPieceSource.text("App/Help/HelpContent.swift")
        #expect(help.contains("Backup.whatHappensWhenTheWindowCloses"),
                "the Help page no longer says what happens when the window closes")
        #expect(help.contains("Login Items"),
                "Help never tells anybody where to switch the background piece off")
    }

    /// ⚠️ **Off is a complete app**, and it has to be said in the same breath as the offer.
    @Test func offIsSaidToBeACompleteApp() {
        #expect(BackgroundPiece.whenItIsOff.contains("Nothing else changes"))
        #expect(Backup.whatHappensWhenTheWindowCloses.contains("switching it off leaves you a complete app"))
    }

    @Test func theOfferSaysWhereToSwitchItOff() {
        #expect(BackgroundPiece.switchExplanation.contains("Login Items"))
        #expect(BackgroundPiece.switchExplanation.contains("no password"))
    }
}
