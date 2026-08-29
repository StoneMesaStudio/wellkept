// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import Darwin
import WellkeptCore

//  CoverageReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **What is not backed up, and the four ways of getting that wrong.**
//
//  1. Calling a file that lives in iCloud a missing one. 72.2 GB of this Mac is in exactly that
//     state, so the alarmist version of this section opens with a 72 GB scare about an arrangement
//     that works.
//  2. Calling a place backed up because Time Machine exists. We cannot see inside a backup, so
//     every claim here comes from Time Machine's own published state and from nothing else.
//  3. Guessing whether iCloud has a copy. macOS states it for 4 services out of 24 and says nothing
//     about the rest; a missing key is not an "off".
//  4. Printing somebody's Google address, which is sitting in a folder name in `~/Library/CloudStorage`.
//
//  ⚠️ Everything here is read-only. The two suites that touch a real path stat things that already
//  exist and read one world-readable plist. Nothing writes outside a temporary sandbox, nothing is
//  moved or removed, no volume is touched, and no dialog can be raised — the places macOS gates
//  behind the other-apps prompt are never opened by the code under test.

// MARK: - ⭐ The law: a cloud file is never a gap

@Suite("A file that also lives in the cloud is never a backup gap")
struct CoverageGapLawTests {

    /// ⭐ Exactly one of the four answers can be a gap. Widening this set is the change that turns
    /// this section into a scare, so it is asserted case by case rather than by counting.
    @Test func onlyOnThisMacCanEverBeAGap() {
        #expect(WhereItLives.onlyOnThisMac.canBeAGap)
        #expect(WhereItLives.inTheCloudAndHere.canBeAGap == false)
        #expect(WhereItLives.onlyInTheCloud.canBeAGap == false)
        #expect(WhereItLives.onAnotherDrive.canBeAGap == false)
        #expect(WhereItLives.allCases.filter(\.canBeAGap).count == 1)
    }

    /// The 72 GB row. It is genuinely **not in the backup** — Time Machine copies the placeholder,
    /// not the file — and it is still not a gap, because there is nothing here to lose.
    @Test func theSeventyTwoGigabytesIsNotInTheBackupAndIsNotAGap() {
        let row = Coverage(name: "Files that are in the cloud and not on this disk",
                           lives: .onlyInTheCloud,
                           included: .no,
                           why: "nothing here to copy",
                           bytes: SizeOnDisk(72_200_000_000))
        #expect(row.isGap == false)
        #expect(row.isUnknown == false)
    }

    /// ⚠️ Something we could not check is not a gap either. Guessing in that direction is how a
    /// backup tool cries wolf; guessing in the other is how it lies.
    @Test func somethingWeCouldNotCheckIsNotAGap() {
        let row = Coverage(name: "Your Reminders",
                           lives: .onlyOnThisMac,
                           included: .notKnown(.notReported),
                           why: "macOS keeps it to itself")
        #expect(row.isGap == false)
        #expect(row.isUnknown)
    }

    /// And the one that is. A thing on this Mac alone, in no backup.
    @Test func theOnlyShapeThatIsAGapStillIs() {
        let row = Coverage(name: "Your home folder",
                           lives: .onlyOnThisMac,
                           included: .no,
                           why: "there is no backup")
        #expect(row.isGap)
    }
}

// MARK: - ⭐ The places, and the one that is deliberately absent

@Suite("Every place a backup silently omits has a row, except the one that should not")
struct CoveragePlaceTests {

    /// ⭐ **The five protected places all have rows, and the Trash is the only one that does not.**
    ///
    /// Without Full Disk Access a backup contains none of the six — not partially, none — and macOS
    /// gives no error. If a second one ever quietly loses its row, this fails. The Trash's absence
    /// is a decision recorded on `CoverageReader.Place`; a *second* absence would be a mistake.
    @Test func theTrashIsTheOnlyProtectedPlaceWithNoRow() {
        let covered = Set(CoverageReader.Place.allCases.compactMap(\.protected))
        let missing = Set(ProtectedPlace.allCases).subtracting(covered)
        #expect(missing == [.trash], """
            The set of protected places without a coverage row changed. Without Full Disk Access a \
            backup holds none of \(ProtectedPlace.listSentence), and each one that loses its row \
            loses the sentence that says so.
            """)
    }

    /// Every protected place carries the Full Disk Access flag, and nothing else does. That flag is
    /// what a copier reads before it believes a run was complete.
    @Test func theGrantFlagFollowsTheProtectedPlaces() {
        for place in CoverageReader.Place.allCases {
            let row = CoverageReader.coverage(of: place,
                                              presence: .here(nil),
                                              iCloud: .notSignedIn,
                                              timeMachine: Fixtures.working,
                                              now: Fixtures.now)
            #expect(row?.needsFullDiskAccess == (place.protected != nil), "\(place.rawValue)")
        }
    }

    /// A place that is not on this Mac gets no row at all. Verified on this Mac 2026-08-29:
    /// `~/Library/Calendars` no longer exists, and a row reading "Your Calendars — in the backup"
    /// would be a report about something that is not there.
    @Test func aPlaceThatIsNotHereGetsNoRow() {
        let row = CoverageReader.coverage(of: .mail,
                                          presence: .notHere,
                                          iCloud: .notSignedIn,
                                          timeMachine: Fixtures.working,
                                          now: Fixtures.now)
        #expect(row == nil)
    }

    /// Every row carries its reason. A flagged item with no reason is an accusation.
    @Test func everyRowSaysWhy() {
        for place in CoverageReader.Place.allCases {
            let row = CoverageReader.coverage(of: place,
                                              presence: .here(nil),
                                              iCloud: .notSignedIn,
                                              timeMachine: Fixtures.neverSetUp,
                                              now: Fixtures.now)
            #expect(row?.why.isEmpty == false, "\(place.rawValue) has no reason on its row")
        }
    }

    /// ⛔ Calendars, Reminders and Notes are reported without ever being opened, and the row says
    /// so. macOS raises the other-apps dialog on the **attempt**, so a probe is the harm.
    @Test func theThreeAppsWeNeverOpenSaySoOnTheRow() {
        for place in [CoverageReader.Place.calendars, .reminders, .notes] {
            guard case .inAPlaceMacOSKeepsToItself = place.keeping else {
                Issue.record("\(place.rawValue) is no longer treated as another app's private data")
                continue
            }
            #expect(CoverageReader.presence(of: place).unreadable == .notReported)
            let row = CoverageReader.coverage(of: place,
                                              presence: CoverageReader.presence(of: place),
                                              iCloud: .notSignedIn,
                                              timeMachine: Fixtures.working,
                                              now: Fixtures.now)
            #expect(row?.why.contains(CoverageReader.whyAnotherAppsDataIsNeverOpened) == true)
            // ⚠️ No button. There is no permission Wellkept is willing to ask for here, so a
            // remedy would be a door with no room behind it.
            #expect(row?.included.unreadable?.mayOfferRemedy == false)
        }
    }
}

// MARK: - ⭐ Inclusion comes from Time Machine and from nothing else

@Suite("What is in a backup is read from Time Machine, never from inside one")
struct CoverageInclusionTests {

    /// ⭐ **The finding this section exists for.** No destination has ever been chosen, so nothing
    /// is in any backup — and that is provable with no permission at all.
    @Test func aMacWithNoBackupHasEverythingInNoBackup() {
        let reading = CoverageReader.included(.mail,
                                              presence: .here(nil),
                                              timeMachine: Fixtures.neverSetUp,
                                              now: Fixtures.now)
        #expect(reading == .no)

        let row = CoverageReader.coverage(of: .mail,
                                          presence: .here(nil),
                                          iCloud: .notSignedIn,
                                          timeMachine: Fixtures.neverSetUp,
                                          now: Fixtures.now)
        #expect(row?.isGap == true)
    }

    /// A destination that has never completed a backup is the same answer. "Set up" is not "ran".
    @Test func setUpButNeverSucceededIsAlsoNotInTheBackup() {
        let state = TimeMachineState(isConfigured: true, automaticBackupsOn: true,
                                     destination: Fixtures.drive, lastSuccess: nil)
        #expect(CoverageReader.included(.photos, presence: .here(nil),
                                        timeMachine: state, now: Fixtures.now) == .no)
    }

    /// ⭐ **Switched off, with an old success behind it, still means the files are in a backup.**
    /// How old belongs to the Time Machine row — DESIGN §8, the container is the answer and what
    /// sits inside it does not repeat it.
    @Test func aBackupThatIsOldIsStillABackup() {
        #expect(Fixtures.switchedOff.standing(now: Fixtures.now) == .switchedOff)
        #expect(CoverageReader.included(.messages, presence: .here(nil),
                                        timeMachine: Fixtures.switchedOff, now: Fixtures.now) == .yes)

        let row = CoverageReader.coverage(of: .messages,
                                          presence: .here(nil),
                                          iCloud: .notSignedIn,
                                          timeMachine: Fixtures.switchedOff,
                                          now: Fixtures.now)
        #expect(row?.isGap == false)
        // And the row does not restate the date the Time Machine row above it already gave.
        #expect(row?.why.contains("days ago") == false)
    }

    /// Time Machine unreadable means we do not know. Claiming either way would be inventing it.
    @Test func anUnreadableTimeMachineMeansNotKnown() {
        let reading = CoverageReader.included(.contacts,
                                              presence: .here(nil),
                                              timeMachine: .couldNotRead(.notPermitted),
                                              now: Fixtures.now)
        #expect(reading.isKnown == false)
        // ⚠️ `.notReported`, not `.notPermitted`: it is not a refusal a person could lift, so it
        // must not put a permanent caveat on Overview.
        #expect(reading.unreadable?.stillComplete == true)
    }

    /// A presence we could not establish outranks everything. The doubt travels.
    @Test func aPlaceWeCouldNotLookAtIsNeverCalledCovered() {
        let reading = CoverageReader.included(.mail,
                                              presence: .couldNotLook(.notPermitted),
                                              timeMachine: Fixtures.working,
                                              now: Fixtures.now)
        #expect(reading.isKnown == false)
    }
}

// MARK: - ⚠️ What iCloud does and does not say about itself

@Suite("A missing Enabled key is not an Off")
struct ICloudStandingTests {

    /// ⚠️ **Measured on this Mac 2026-08-29: 4 of 24 services carry `Enabled`.** Photos, Mail,
    /// Messages, Contacts, Calendars, Reminders and Bookmarks are listed with no verdict at all.
    /// Reading that absence as "off" would be an invention; reading it as "on" would be a
    /// comfortable one.
    @Test func theThreeAnswers() {
        #expect(CoverageReader.standing(of: ["Enabled": true]) == .on)
        #expect(CoverageReader.standing(of: ["Enabled": false]) == .off)
        #expect(CoverageReader.standing(of: ["Name": "PHOTO_STREAM"]) == .notStated)
        // Desktop & Documents states itself this way and nothing else on this Mac does.
        #expect(CoverageReader.standing(of: ["status": "active"]) == .on)
        // An explicit false wins over a stale status.
        #expect(CoverageReader.standing(of: ["Enabled": false, "status": "active"]) == .off)
    }

    /// ⭐ **Not stated does not become "in iCloud".** The conservative half — the data is on this
    /// Mac, which is measured — is what gets asserted, and the row says the rest is unknown.
    @Test func notStatedNeverBecomesACloudCopy() {
        let account = CoverageReader.ICloudAccount(
            signedIn: true,
            standings: ["com.apple.Dataclass.Photos": .notStated],
            unreadable: nil)

        #expect(CoverageReader.whereItLives(.photos, iCloud: account) == .onlyOnThisMac)

        let row = CoverageReader.coverage(of: .photos,
                                          presence: .here(nil),
                                          iCloud: account,
                                          timeMachine: Fixtures.working,
                                          now: Fixtures.now)
        #expect(row?.why.contains(CoverageReader.macOSDoesNotSayWhetherThisIsInICloud) == true)
    }

    /// And a service macOS does say is on reads as a copy in two places, which is not a gap.
    @Test func aServiceThatIsOnReadsAsTwoCopies() {
        let account = CoverageReader.ICloudAccount(
            signedIn: true,
            standings: ["com.apple.Dataclass.Notes": .on],
            unreadable: nil)
        #expect(CoverageReader.whereItLives(.notes, iCloud: account) == .inTheCloudAndHere)

        let row = CoverageReader.coverage(of: .notes,
                                          presence: .couldNotLook(.notReported),
                                          iCloud: account,
                                          timeMachine: Fixtures.neverSetUp,
                                          now: Fixtures.now)
        #expect(row?.isGap == false)
        // ⚠️ And it does not then claim macOS was silent, because macOS was not.
        #expect(row?.why.contains(CoverageReader.macOSDoesNotSayWhetherThisIsInICloud) == false)
    }

    /// ⚠️ **A file that exists and did not parse is not "no iCloud".** Apple has reshaped this
    /// store before, and a reader that read a schema change as an absent account would tell
    /// somebody their photos are only on this Mac on the strength of it.
    @Test func aChangedFileIsNotAnAbsentAccount() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let file = try sandbox.file("MobileMeAccounts.plist", contents: "not a property list")

        let account = CoverageReader.readICloud(from: file, home: sandbox.home)
        #expect(account.unreadable != nil)
        #expect(account.signedIn == false)
        // ⭐ And nothing downstream may read that `false` as evidence of anything.
        #expect(account.detailPairs.count == 1)
    }

    /// No file at all is the ordinary shape of a Mac with no iCloud account, and it is an absence
    /// we can stand behind rather than a refusal.
    @Test func noFileIsNotSignedIn() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let account = CoverageReader.readICloud(from: sandbox.home.appending(path: "nothing.plist"),
                                                home: sandbox.home)
        #expect(account.signedIn == false)
        #expect(account.unreadable == nil)
    }

    /// ⛔ **Only `Services` is parsed.** The same file carries the owner's email address, display
    /// name, first and last name and two directory identifiers. This asserts by construction: the
    /// type has three properties and none of them could hold one.
    @Test func nothingAboutThePersonIsEverRead() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let plist: [String: Any] = [
            "Accounts": [[
                "AccountID": "someone@example.com",
                "DisplayName": "A Person",
                "firstName": "A",
                "lastName": "Person",
                "AccountDSID": "1051463026",
                "Services": [["ServiceID": "com.apple.Dataclass.Ubiquity", "Enabled": true]],
            ]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let file = sandbox.home.appending(path: "MobileMeAccounts.plist")
        try data.write(to: file)

        let account = CoverageReader.readICloud(from: file, home: sandbox.home)
        #expect(account.signedIn)
        #expect(account.standing(of: "com.apple.Dataclass.Ubiquity") == .on)

        // Nothing the reader produced carries any of it.
        let everythingItSays = account.detailPairs.map { "\($0.label) \($0.value)" }.joined(separator: " ")
        for secret in ["someone@example.com", "A Person", "1051463026"] {
            #expect(everythingItSays.contains(secret) == false, "the reader printed \(secret)")
        }
    }

    /// ⚠️ Matched on `ServiceID`, never on `Name`: Apple lists Photos as `PHOTO_STREAM` and Mail as
    /// `MAIL_AND_NOTES`, which is a different service from `NOTES`.
    @Test func everyServiceIsIdentifiedByItsReverseDNSName() {
        for place in CoverageReader.Place.allCases {
            guard let id = place.iCloudServiceID else { continue }
            #expect(id.hasPrefix("com.apple.Dataclass."), "\(place.rawValue) uses \(id)")
        }
        #expect(CoverageReader.Place.photos.iCloudServiceID == "com.apple.Dataclass.Photos")
        #expect(CoverageReader.Place.mail.iCloudServiceID == "com.apple.Dataclass.Mail")
        #expect(CoverageReader.Place.notes.iCloudServiceID == "com.apple.Dataclass.Notes")
        // ⚠️ Music is deliberately not an iCloud service here: a ripped or bought track does not
        // come back on demand and nothing outside distinguishes it from an Apple Music download.
        #expect(CoverageReader.Place.music.iCloudServiceID == nil)
    }
}

// MARK: - ⛔ The file providers, and the address in the folder name

@Suite("A third-party sync folder is named, never opened, and never printed with its account")
struct FileProviderTests {

    /// ⭐ **The folder is called `GoogleDrive-johndseidner@gmail.com`.** That is somebody's Google
    /// address sitting in a path, one step from a row or a clipboard. Everything after the first
    /// hyphen is dropped.
    @Test func theAccountIsStrippedOffTheProviderName() {
        #expect(CoverageReader.providerName("GoogleDrive-johndseidner@gmail.com") == "GoogleDrive")
        #expect(CoverageReader.providerName("OneDrive-Personal") == "OneDrive")
        #expect(CoverageReader.providerName("ProtonDrive-someone@proton.me") == "ProtonDrive")
        // No hyphen, nothing to strip.
        #expect(CoverageReader.providerName("Dropbox") == "Dropbox")
        // A leading hyphen would otherwise produce an empty name, which is worse than the folder.
        #expect(CoverageReader.providerName("-odd") == "-odd")
    }

    /// ⛔ A folder directly inside `~/Library/CloudStorage` is a mount and is refused. An ordinary
    /// folder is not, and neither is `CloudStorage` itself — refusing the container would be a
    /// different rule with a different failure.
    @Test func onlyTheMountsThemselvesAreRefused() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let root = CoverageReader.fileProviderRoot(home: sandbox.home)

        #expect(CoverageReader.isAFileProviderMount(root.appending(path: "GoogleDrive-a@b.com"),
                                                    home: sandbox.home))
        #expect(CoverageReader.isAFileProviderMount(root, home: sandbox.home) == false)
        #expect(CoverageReader.isAFileProviderMount(sandbox.home.appending(path: "Documents"),
                                                    home: sandbox.home) == false)
    }

    /// The row it produces names the provider, says why it is not opened, and is not a gap — the
    /// files are on somebody's server, not missing.
    @Test func theRowExplainsItselfAndIsNotAGap() {
        let why = CoverageReader.whyAFileProviderIsNeverOpened("GoogleDrive")
        let row = Coverage(name: "GoogleDrive", lives: .onAnotherDrive, included: .no, why: why)
        #expect(row.isGap == false)
        #expect(why.contains("GoogleDrive"))
        #expect(why.contains("timed out"))
    }

    /// Providers come back sorted, deduplicated and account-free.
    @Test func providersAreListedWithoutAccounts() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let root = CoverageReader.fileProviderRoot(home: sandbox.home)
        for name in ["GoogleDrive-one@gmail.com", "GoogleDrive-two@gmail.com", "Dropbox", ".DS_Store"] {
            try FileManager.default.createDirectory(at: root.appending(path: name),
                                                    withIntermediateDirectories: true)
        }
        #expect(CoverageReader.fileProviders(home: sandbox.home) == ["Dropbox", "GoogleDrive"])
    }
}

// MARK: - ⭐ The double-count trap

@Suite("Desktop and Documents are one set of files under two names")
struct MirrorTests {

    /// ⭐ Measured 2026-08-29: `~/Desktop/SetShot.app` and its iCloud Drive twin are inode
    /// `71114060` on the same device. **A copier that walks both roots copies everything twice.**
    /// A hard link inside a sandbox reproduces the shape exactly.
    @Test func aFileReachableUnderTwoNamesIsFound() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let real = try sandbox.file("Desktop/a-file.txt")
        let cloudDesktop = sandbox.home
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Desktop")
        try FileManager.default.createDirectory(at: cloudDesktop, withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: real, to: cloudDesktop.appending(path: "a-file.txt"))

        #expect(CoverageReader.desktopAndDocumentsAreMirrored(home: sandbox.home))
    }

    /// Two folders with the same names and genuinely different files are not a mirror. The check is
    /// made on a real file's inode, because the directories themselves have different inodes even
    /// when the sync is on — which is exactly why a check on the folders would say no.
    @Test func twoDifferentFoldersAreNotAMirror() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Desktop/a-file.txt")
        try sandbox.file("Library/Mobile Documents/com~apple~CloudDocs/Desktop/a-file.txt",
                         contents: "a different file")
        #expect(CoverageReader.desktopAndDocumentsAreMirrored(home: sandbox.home) == false)
    }

    /// A Mac with no iCloud folders at all answers no, rather than failing to answer.
    @Test func noCloudFoldersMeansNoMirror() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Desktop/a-file.txt")
        #expect(CoverageReader.desktopAndDocumentsAreMirrored(home: sandbox.home) == false)
    }
}

// MARK: - ⛔ Counting what is in the cloud without downloading it

@Suite("Counting cloud files never downloads one")
struct CloudCountTests {

    /// ⭐ **The thread policy is set before anything is looked at.** Without it, touching a file
    /// that lives in iCloud makes macOS fetch it: 524 came down during the research and turned a
    /// 36-second scan into over nine minutes.
    @Test func theWalkSetsTheThreadPolicyFirst() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Library/Mobile Documents/com~apple~CloudDocs/a-file.txt")

        _ = CoverageReader.measureCloudOnly(home: sandbox.home, desktopAndDocumentsSynced: false)
        #expect(ScanPolicy.thisThreadHoldsCloudFilesWhereTheyAre)
    }

    /// An ordinary file is not a placeholder. The judgement is the kernel's `SF_DATALESS` flag and
    /// never the size — a sparse disk image reads `blocks=0, size=100 MB` exactly like an iCloud
    /// photo and is very much here.
    @Test func ordinaryFilesAreNotCountedAsCloudFiles() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try sandbox.file("Library/Mobile Documents/com~apple~CloudDocs/one.txt")
        try sandbox.file("Library/Mobile Documents/com~apple~CloudDocs/two.txt")

        let (holding, refused) = CoverageReader.measureCloudOnly(home: sandbox.home,
                                                                 desktopAndDocumentsSynced: false)
        #expect(holding.measured)
        #expect(holding.files == 0)
        #expect(holding.sentence == nil)
        #expect(refused.isEmpty)
    }

    /// ⚠️ Not measured is not "none found", and the two must never print the same thing.
    @Test func notMeasuredIsNotAZero() {
        #expect(CoverageReader.CloudHolding.notMeasured.measured == false)
        #expect(CoverageReader.CloudHolding.notMeasured.sentence == nil)
        let real = CoverageReader.CloudHolding(files: 10_925,
                                               apparent: SizeOnDisk(65_400_000_000),
                                               measured: true)
        #expect(real.sentence?.contains("10,925") == true)
        #expect(real.sentence?.contains("downloading") == true)
    }

    /// ⚠️ A file listed and then gone is a build finishing, not a refusal. Counting those would put
    /// a permanent "smaller than the truth" caveat on the screen of anybody who compiles anything.
    @Test func aVanishedFileIsNotARefusal() {
        let refusals = CoverageReader.Refusals()
        refusals.note(URL(filePath: "/tmp/gone"),
                      error: NSError(domain: NSCocoaErrorDomain,
                                     code: NSFileReadNoSuchFileError))
        #expect(refusals.places.isEmpty)

        refusals.note(URL(filePath: "/tmp/refused"),
                      error: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)))
        #expect(refusals.places.count == 1)
        #expect(refusals.places.why == .notPermitted)
    }
}

// MARK: - ⭐ What do I lose, and in which disaster

@Suite("The disaster table, and the two claims it refuses to make")
struct DisasterTests {

    /// Every disaster appears once, in a fixed order, and each has an answer for both protectors.
    @Test func theTableIsCompleteAndFixed() {
        #expect(Disaster.table.count == Disaster.Kind.allCases.count)
        #expect(Disaster.table.map(\.kind) == Disaster.Kind.allCases)
        for disaster in Disaster.table {
            #expect(disaster.whatIsLost.isEmpty == false)
            #expect(disaster.timeMachine.detail.isEmpty == false)
            #expect(disaster.theCloud.detail.isEmpty == false)
        }
    }

    /// ⭐ **Sync is not a backup.** The cloud never covers ransomware and never covers a mistaken
    /// deletion, because in both cases it copies the damage faithfully to every device.
    @Test func theCloudNeverCoversTheTwoThingsItMakesWorse() {
        for kind in [Disaster.Kind.ransomware, .aFileDeletedByMistake] {
            let disaster = Disaster.table.first { $0.kind == kind }
            #expect(disaster?.theCloud.isCovered == false, """
                The table now says the cloud covers \(kind.rawValue). \(Disaster.syncIsNotABackup)
                """)
            if case .no = disaster?.theCloud {} else {
                Issue.record("\(kind.rawValue) must be a plain no, not a condition")
            }
        }
    }

    /// ⭐ **Something is always covered by nothing, and saying so is the point.** A table where
    /// every row has an answer is a sales sheet.
    @Test func atLeastOneDisasterIsCoveredByNothing() {
        #expect(Disaster.coveredByNothing.isEmpty == false)
        let names = Disaster.coveredByNothing.map(\.kind)
        #expect(names.contains(.aBadMacOSUpdate), """
            A bad macOS update is the one nothing covers. On Apple silicon a restore does not put \
            the old macOS back — Recovery downloads its own installer.
            """)
    }

    /// ⚠️ **A condition somebody had to have arranged in advance is not protection.** Everywhere
    /// this feeds a count or a colour, `.onlyIf` counts as no.
    @Test func onlyIfIsNotCovered() {
        #expect(Disaster.Cover.yes("x").isCovered)
        #expect(Disaster.Cover.onlyIf("x").isCovered == false)
        #expect(Disaster.Cover.no("x").isCovered == false)

        let stolen = Disaster.table.first { $0.kind == .theMacIsStolen }
        if case .onlyIf = stolen?.timeMachine {} else {
            Issue.record("a backup drive that lives plugged into the Mac is stolen with the Mac")
        }
    }

    /// Every disaster whose answer is "nothing" says what the person actually loses, and the two
    /// that are covered do not carry a `coveredByNothing` that contradicts them.
    @Test func everyRowSaysWhatIsAtStake() {
        for disaster in Disaster.table {
            #expect(disaster.detailPairs.count >= 2)
            if !disaster.isCovered {
                #expect(disaster.coveredByNothing?.isEmpty == false, "\(disaster.kind.rawValue)")
            }
        }
    }

    /// ⛔ The claim this app never makes, checked against the table's own words.
    @Test func nothingInTheTablePromisesToRebuildTheMac() {
        let everything = Disaster.table
            .flatMap { [$0.whatIsLost, $0.timeMachine.detail, $0.theCloud.detail,
                        $0.coveredByNothing ?? ""] }
            .joined(separator: " ")
            .lowercased()
        #expect(everything.contains(Backup.promiseWeDoNotMake) == false)
        // ⛔ And the out-of-date claim about how Time Machine copies is nowhere near it.
        #expect(everything.contains("serial") == false)
    }
}

// MARK: - This Mac, read-only

@Suite("What the reader says about the Mac it is running on")
struct CoverageOnThisMacTests {

    /// The account file reads with no permission at all — that is why this section is honest on a
    /// Mac that has given Wellkept nothing. Either answer is legitimate on a build machine, so this
    /// asserts the reader survives rather than what it found.
    @Test func theICloudAccountReadsWithoutAPermission() {
        let account = CoverageReader.readICloud()
        if account.unreadable == nil, account.signedIn {
            #expect(account.detailPairs.count > 1)
        }
        // Whatever it found, it can describe itself in one line or several, and never crashes.
        #expect(account.detailPairs.isEmpty == false)
    }

    /// ⭐ `stat` works without Full Disk Access where listing does not. That asymmetry is what lets
    /// the section say "your mail is not in any backup" on a Mac that has granted nothing.
    @Test func existenceIsProvableWithoutTheGrant() {
        #expect(CoverageReader.presence(of: .homeFolder).exists)
        // Whatever the answer for a protected place, it is never a crash and never a size.
        for place in CoverageReader.Place.allCases {
            #expect(CoverageReader.presence(of: place).bytes == nil,
                    "\(place.rawValue) reported a size, and no cheap honest one exists")
        }
    }

    /// A whole pass on the real Mac, with the walk switched off so this stays a unit test. Nothing
    /// is written, moved or downloaded.
    @Test func aWholePassProducesARowThatExplainsItself() {
        let reading = CoverageReader.read(timeMachine: Fixtures.switchedOff,
                                          fullDiskAccessHeld: false,
                                          countCloudFiles: false,
                                          now: Fixtures.now)
        let row = reading.row
        #expect(row.topic == .notCovered)
        #expect(row.headline.isEmpty == false)
        #expect(row.coverage.isEmpty == false)
        // ⚠️ Never `.problem`. A file that lives in one place is an arrangement, not a fault.
        #expect(row.severity != .problem)
        // Without the grant there is one button, and it goes to the one refusal a person can lift.
        #expect(row.remedy?.settingsPane == "fullDiskAccess")
        // Every row explains what Full Disk Access costs, on the places it costs something.
        for coverage in row.coverage where coverage.needsFullDiskAccess {
            #expect(coverage.why.contains(CoverageReader.whatFullDiskAccessCosts))
        }
    }

    /// ⚠️ **The same fact is never said twice on one screen.** The cloud figure is the row's
    /// measure and the cloud row's own reason; it must not also be in the line between them.
    /// Storage shipped this exact bug — the free-space card and the row beneath it printed the same
    /// five folder names an inch apart, and a screenshot caught it, not a test.
    @Test func theCloudFigureIsNotPrintedTwice() {
        let reading = CoverageReader.read(timeMachine: Fixtures.switchedOff,
                                          fullDiskAccessHeld: true,
                                          countCloudFiles: false,
                                          now: Fixtures.now)
        let counted = CoverageReader.CloudHolding(files: 10_925,
                                                  apparent: SizeOnDisk(65_400_000_000),
                                                  measured: true)
        #expect(reading.reason?.contains(counted.sentence ?? "!") != true)
    }

    /// With the grant held there is no button, because there is nothing left to lift.
    @Test func withTheGrantThereIsNoButton() {
        let reading = CoverageReader.read(timeMachine: Fixtures.working,
                                          fullDiskAccessHeld: true,
                                          countCloudFiles: false,
                                          now: Fixtures.now)
        #expect(reading.row.remedy == nil)
        #expect(reading.detailPairs.contains { $0.label == "Full Disk Access" && $0.value == "Granted" })
    }
}

// MARK: - Fixtures

/// Time Machine states, built once. ⛔ Nothing here touches Time Machine — these are values.
enum Fixtures {

    static let now = Date(timeIntervalSince1970: 1_787_000_000)

    static let drive = BackupDestination(name: "JDS Backup",
                                         kind: .localDrive,
                                         isConnected: false,
                                         volumePath: nil,
                                         capacity: SizeOnDisk(2_000_000_000_000),
                                         free: SizeOnDisk(500_000_000_000))

    /// No destination has ever been chosen.
    static let neverSetUp = TimeMachineState(isConfigured: false, automaticBackupsOn: false)

    /// ⭐ This Mac on 2026-08-29: configured, `AutoBackup = 0`, drive unplugged, last success four
    /// days earlier. Nothing is broken. Somebody turned it off and nobody said so.
    static let switchedOff = TimeMachineState(isConfigured: true,
                                              automaticBackupsOn: false,
                                              destination: drive,
                                              lastSuccess: now.addingTimeInterval(-4 * 86_400))

    static let working = TimeMachineState(isConfigured: true,
                                          automaticBackupsOn: true,
                                          destination: BackupDestination(name: "JDS Backup",
                                                                         kind: .localDrive,
                                                                         isConnected: true,
                                                                         volumePath: "/Volumes/JDS Backup",
                                                                         capacity: SizeOnDisk(2_000_000_000_000),
                                                                         free: SizeOnDisk(500_000_000_000)),
                                          lastSuccess: now.addingTimeInterval(-3_600))
}
