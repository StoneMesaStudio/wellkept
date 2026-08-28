// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import Darwin
import WellkeptCore

//  StoragePolicyTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The reader and the policy: the two files that decide where a scan goes and what it may say.**
//
//  Everything here is read-only. Nothing writes, moves, deletes or downloads, and the one
//  subprocess (`tmutil listlocalsnapshots`) is a read that needs no privilege and raises no dialog.

// MARK: - ⚠️ The thread I/O policy

@Suite("A scan cannot pull a file down from iCloud")
struct ScanIOPolicyTests {

    /// ⭐ **The one line that turned a nine-minute scan back into 36 seconds.**
    ///
    /// Without it, touching a dataless file makes macOS download it — 524 of them came down over
    /// the owner's internet during the research, filling the disk we were there to help him empty.
    @Test func theThreadHoldsCloudFilesWhereTheyAre() {
        #expect(ScanPolicy.prepareThisThread())
        #expect(ScanPolicy.thisThreadHoldsCloudFilesWhereTheyAre)
    }

    /// ⚠️ **Reading a file's contents is gated on the policy actually being set**, not on somebody
    /// having remembered to call it. A duplicate comparison on an unprepared thread is refused.
    @Test func contentsAreOnlyReadForAComparisonAndOnlyOnAPreparedThread() {
        ScanPolicy.prepareThisThread()
        let size = SizeOnDisk(4_000_000)

        #expect(ScanPolicy.mayReadContents(ofSize: size, cloudStanding: .onThisMac,
                                           forDuplicateComparison: true))
        // Nothing else in the section has a reason to open a file.
        #expect(ScanPolicy.mayReadContents(ofSize: size, cloudStanding: .onThisMac,
                                           forDuplicateComparison: false) == false)
        // A file that is not on this Mac is exactly the file that must not be touched.
        #expect(ScanPolicy.mayReadContents(ofSize: size, cloudStanding: .inTheCloudOnly,
                                           forDuplicateComparison: true) == false)
        #expect(ScanPolicy.mayReadContents(ofSize: .zero, cloudStanding: .onThisMac,
                                           forDuplicateComparison: true) == false)
    }

    /// ⚠️ The last-accessed date is not in the key set, and it never comes back. Our own research
    /// scan rewrote 2,012 of them, so on any Mac where Wellkept has run, "not opened in years" is a
    /// statement about Wellkept.
    @Test func theLastAccessedDateIsNotAskedFor() {
        #expect(ScanPolicy.resourceKeys.contains(.contentAccessDateKey) == false)
        #expect(ScanPolicy.resourceKeys.contains(.totalFileAllocatedSizeKey))
    }
}

// MARK: - ⚠️ Where a scan may go

@Suite("A scan never starts at the root and never leaves the disk")
struct ScanDescentTests {

    /// ⭐ Started at `/`, a walk counts the disk twice and reports 501 GB used on a 494 GB drive.
    @Test func theScanRootIsNeverTheSystemVolume() {
        let root = ScanPolicy.root()
        #expect(root.path(percentEncoded: false) != "/")

        let volume = Movable.volume(of: root.path(percentEncoded: false))
        #expect(volume?.isSealedSystem == false)
    }

    /// ⚠️ `/System/Library` is on the sealed volume, which shares a device number and a display name
    /// with the Data volume. Only `statfs` separates them, and only that separation stops a scan
    /// counting macOS as if it were somebody's files.
    @Test func theSealedSystemVolumeIsRefused() {
        let scanVolume = Movable.volume(of: ScanPolicy.root().path(percentEncoded: false))
        let verdict = ScanPolicy.descend(into: URL(filePath: "/System/Library"),
                                         stayingOn: scanVolume)
        #expect(verdict.reason == .sealedSystemVolume)
    }

    /// The engine pointed at itself. A walk into our own store would offer to quarantine the
    /// quarantine.
    @Test func wellkeptsOwnStoreIsRefused() {
        let home = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let store = StorageManifest.quarantineDirectory(home: home)
        let verdict = ScanPolicy.descend(into: store.appending(path: "anything"),
                                         stayingOn: nil, home: home)
        #expect(verdict.reason == .wellkeptsOwnStore)
    }

    /// ⭐ **Not going there is the right answer, and it does not make the run incomplete.** Only a
    /// refusal a person could lift does — otherwise Overview would carry a permanent caveat that
    /// nobody can clear, for a scan that behaved correctly.
    @Test func onlyALiftableRefusalMakesARunIncomplete() {
        #expect(ScanPolicy.SkipReason.notPermitted.makesTheRunIncomplete)
        for reason in [ScanPolicy.SkipReason.sealedSystemVolume, .snapshot, .symbolicLink,
                       .anotherAppsData, .wellkeptsOwnStore] {
            #expect(reason.makesTheRunIncomplete == false, "\(reason) marks a good run incomplete")
            #expect(reason.sentence.isEmpty == false)
        }
    }

    /// ⛔ **Another app's sandboxed data is refused before anything touches it**, because for those
    /// folders macOS raises its dialog on the attempt rather than on the failure.
    ///
    /// The name comes from `LeftoverReader.Place`, the one file permitted to spell it. The rule is a
    /// suffix rather than a list, so the group variant is covered by the same line — which is what
    /// this test is really checking.
    @Test func anotherAppsDataIsRefusedByShapeNotByAList() {
        let home = URL(filePath: "/Users/somebody")
        let gated = LeftoverReader.Place.containers.directory
        let library = home.appending(path: "Library")

        #expect(ScanPolicy.isAnotherAppsData(
            library.appending(path: "\(gated)/com.example.app").path(percentEncoded: false),
            home: home))

        // The group variant, built from the same one name so this file does not spell it either.
        #expect(ScanPolicy.isAnotherAppsData(
            library.appending(path: "Group \(gated)/group.example").path(percentEncoded: false),
            home: home))

        // A folder of the same name inside somebody's project is their own file.
        #expect(ScanPolicy.isAnotherAppsData(
            home.appending(path: "Code/app/\(gated)").path(percentEncoded: false),
            home: home) == false)

        #expect(ScanPolicy.isAnotherAppsData(
            library.appending(path: "Caches/com.example.app").path(percentEncoded: false),
            home: home) == false)
    }

    /// The home folder itself is where the scan lives, so it had better be allowed in.
    @Test func theHomeFolderIsAllowed() {
        let home = StorageManifest.home()
        let scanVolume = Movable.volume(of: home.path(percentEncoded: false))
        #expect(ScanPolicy.descend(into: home, stayingOn: scanVolume).isAllowed)
    }
}

// MARK: - ⭐ The refusal list

@Suite("What Storage will never offer to touch")
struct RefusalListTests {

    private let home = URL(filePath: "/Users/somebody")

    @Test func everyEntryCarriesItsReason() {
        for refusal in ScanPolicy.neverOffered {
            #expect(refusal.why.isEmpty == false, "\(refusal.place) refuses without saying why")
            #expect(refusal.name.isEmpty == false)
        }
        for shape in ScanPolicy.Shape.allCases {
            #expect(shape.why.isEmpty == false)
        }
    }

    /// The four that matter most, measured or argued: a Photos library that Photos manages, a Trash
    /// that already has an undo, 30 GB of simulator images with no possible undo, and a project's
    /// entire history.
    @Test func theFourThatMatterMostAreRefused() {
        #expect(ScanPolicy.mayOfferToActOn(
            home.appending(path: "Pictures/Photos Library.photoslibrary").path(percentEncoded: false),
            home: home) == false)

        #expect(ScanPolicy.mayOfferToActOn(
            home.appending(path: ".Trash/old.zip").path(percentEncoded: false),
            home: home) == false)

        #expect(ScanPolicy.mayOfferToActOn(
            "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.simruntime",
            home: home) == false)

        #expect(ScanPolicy.mayOfferToActOn(
            home.appending(path: "Code/wellkept/.git/objects/pack").path(percentEncoded: false),
            home: home) == false)
    }

    /// An ordinary large file in Downloads is not on the list, or the section would have nothing to
    /// offer at all. A refusal list that refuses everything is a section with no product in it.
    @Test func anOrdinaryFileIsNotRefused() {
        #expect(ScanPolicy.mayOfferToActOn(
            home.appending(path: "Downloads/installer.dmg").path(percentEncoded: false),
            home: home))
    }

    /// ⚠️ **Age is an annoyance filter and never a reason.** Measured, "older than 30 days" picks a
    /// 1.3 GB audiobook out of the cache folder first and protects 4% of Xcode's build output.
    @Test func ageOnlyEverAnswersDoNotMakeMeDownloadItAgain() {
        let now = Date()
        #expect(ScanPolicy.isRecentlyUsed(now.addingTimeInterval(-3 * 86_400), now: now))
        #expect(ScanPolicy.isRecentlyUsed(now.addingTimeInterval(-60 * 86_400), now: now) == false)
        // No date is not "old". It is no date.
        #expect(ScanPolicy.isRecentlyUsed(nil, now: now) == false)
    }
}

// MARK: - ⭐ The two free-space numbers

@Suite("Free space has two answers and we lead with the real one")
struct FreeSpaceReadingTests {

    /// A real reading of this Mac. Deliberately loose: the point is that both figures arrive and
    /// agree with each other's shape, not what they happen to be today.
    @Test func theVolumeAnswersWithBothFigures() {
        guard case let .read(picture) = FreeSpace.read(listSnapshots: false) else {
            Issue.record("the Data volume would not report its own size")
            return
        }
        #expect(picture.capacity.bytes > 0)
        #expect(picture.actuallyFree.bytes <= picture.capacity.bytes)
        #expect(picture.used.bytes == picture.capacity.bytes - picture.actuallyFree.bytes)
        #expect(picture.volumeName.isEmpty == false)
    }

    /// ⚠️ Never `/`, and never assumed to be `/System/Volumes/Data` either — it is read from the
    /// home folder's own volume.
    @Test func theDataVolumeIsNeverTheRoot() {
        #expect(FreeSpace.dataVolume().path(percentEncoded: false) != "/")
    }

    /// The format `tmutil` has printed since High Sierra, including the one this Mac has today.
    @Test func snapshotNamesAreParsed() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-08-25-062503.local
        com.apple.TimeMachine.2026-08-26-101500.local
        """
        let parsed = FreeSpace.parseSnapshots(output)
        #expect(parsed.count == 2)
        #expect(parsed.first?.name.hasSuffix(".local") == true)

        let calendar = Calendar.current
        let first = parsed.first!.takenOn
        #expect(calendar.component(.year, from: first) == 2026)
        #expect(calendar.component(.month, from: first) == 8)
        #expect(calendar.component(.day, from: first) == 25)
        #expect(calendar.component(.hour, from: first) == 6)
        #expect(calendar.component(.minute, from: first) == 25)
    }

    /// Anything that is not a dated snapshot name is skipped rather than guessed at.
    @Test func anythingElseInTheOutputIsIgnored() {
        #expect(FreeSpace.parseSnapshots("Snapshots for disk /:").isEmpty)
        #expect(FreeSpace.parseSnapshots("com.apple.TimeMachine.not-a-date.local").isEmpty)
        #expect(FreeSpace.parseSnapshots("").isEmpty)
    }

    /// ⚠️ A failed listing is **not** "there are no snapshots". They are opposite answers, and
    /// collapsing them would make a Mac we could not read look like the most generous case there is.
    @Test func anUnreadListingPromisesNothing() {
        #expect(SnapshotStanding.couldNotBeRead.wasRead == false)
        #expect(SnapshotStanding.none.wasRead)
        #expect(SnapshotStanding.couldNotBeRead
            .recoverable(onDisk: SizeOnDisk(1_000), modifiedOn: Date()).isZero)
    }

    /// Reading this Mac's real snapshot list. It must come back read — the tool is present on every
    /// Mac and needs no privilege — and it must not raise anything.
    @Test func thisMacsSnapshotsAreReadable() {
        let standing = FreeSpace.localSnapshots(on: FreeSpace.dataVolume())
        #expect(standing.wasRead, "tmutil would not list local snapshots")
    }
}

// MARK: - ⭐ The arithmetic John approved

@Suite("The sheet states the arithmetic before the press")
struct FreeSpaceArithmeticTests {

    /// ⭐ **John's sentence, 2026-08-28.** The figure quoted is what would come back, not the size
    /// on disk — where a snapshot is holding the blocks the two differ by up to 150×, and quoting
    /// the larger one would be a promise the second press cannot keep.
    @Test func theSheetQuotesWhatWouldActuallyComeBack() {
        let twelveGigs = Bytes(onDisk: SizeOnDisk(12_000_000_000),
                               recoverableToday: .all(of: SizeOnDisk(12_000_000_000)))
        let sentence = FreeSpace.Says.arithmetic(for: twelveGigs)
        #expect(sentence.contains("will not make your Mac emptier today"))
        #expect(sentence.contains("empty the quarantine"))
        #expect(sentence.contains(twelveGigs.recoverableToday.text))
    }

    /// Where a snapshot holds everything, the sheet says the second press will not help either —
    /// rather than quoting a figure nothing can deliver.
    @Test func aFileHeldByASnapshotIsNotPromisedAnything() {
        let held = Bytes.heldBackBySnapshot(SizeOnDisk(12_000_000_000))
        let sentence = FreeSpace.Says.arithmetic(for: held)
        #expect(sentence.contains("snapshot"))
        #expect(sentence.contains("12 GB") == false)
    }

    /// ⭐ Both buttons, in John's order: the ordinary one, and the one for somebody who needs the
    /// room today. The second exists because setting 40 GB aside and watching nothing happen is the
    /// failure this section was designed around.
    @Test func theSheetOffersBothRoutes() {
        #expect(FreeSpace.Says.setAsideOnly == "Set aside")
        #expect(FreeSpace.Says.setAsideAndEmpty.contains("empty the quarantine"))
        #expect(FreeSpace.Says.whenTheDiskIsAlreadyFull == QuarantineWords.whenTheDiskIsAlreadyFull)
    }

    /// ⚠️ Never a figure that came back from a quarantine, because none did: 391 MB across 100,000
    /// files moved free space by −8 KiB.
    @Test func theAfterSentenceNeverClaimsRoomAppeared() {
        let sentence = FreeSpace.Says.afterSettingAside(SizeOnDisk(13_000_000_000))
        #expect(sentence.contains("13 GB"))
        #expect(sentence.contains("no space comes back until you empty the quarantine"))
    }

    /// ⭐ **The one place allowed to state a figure that came back states a measured one.** Zero is
    /// a real answer here and it is said plainly, and a figure going the other way is normal
    /// because the Mac keeps working while a delete runs.
    @Test func whatCameBackIsMeasuredRatherThanCalculated() {
        let gained = FreeSpace.Change(before: SizeOnDisk(100_000_000_000),
                                      after: SizeOnDisk(104_200_000_000))
        #expect(gained.difference.bytes == 4_200_000_000)
        #expect(gained.sentence.contains("came back"))

        let held = FreeSpace.Change(before: SizeOnDisk(100_000_000_000),
                                    after: SizeOnDisk(100_000_000_000))
        #expect(held.sentence.contains("did not change"))
        #expect(held.sentence.contains("snapshot"))

        let busy = FreeSpace.Change(before: SizeOnDisk(100_000_000_000),
                                    after: SizeOnDisk(99_000_000_000))
        #expect(busy.wentDown)
        #expect(busy.sentence.contains("writing"))
    }

    /// The measuring wrapper takes both readings or reports none. **Never a zero**, which would read
    /// as "nothing came back".
    @Test func measuringTakesBothReadingsOrNone() {
        var ran = false
        let (result, change) = FreeSpace.measuring { () -> Int in ran = true; return 7 }
        #expect(ran)
        #expect(result == 7)
        // On a real Mac both readings succeed; what matters is that a failure is `nil` and not zero.
        if let change { #expect(change.before.bytes > 0) }
    }
}

// MARK: - The two copies of one sentence

@Suite("Sentences that exist twice stay identical")
struct StorageWordingTests {

    /// John's line has a copy in `WellkeptCore` for a row that has not been through the engine, and
    /// one in the engine itself. Two copies of a sentence is one copy too many unless something
    /// checks them.
    @Test func theICloudWarningIsOneSentence() {
        #expect(CloudStanding.alsoRemovesItFromYourDevices == Movable.iCloudWarning)
    }

    /// `WellkeptCore` names the Full Disk Access pane by the raw value of an app-layer enum, because
    /// the `x-apple.systempreferences:` anchors are Apple internals that live in one file. If that
    /// case is ever renamed, the Storage remedy button quietly stops resolving.
    @Test func theRemedyNamesARealPane() {
        let refused = UnreadablePlaces(count: 54, notable: ["your Trash"])
        #expect(refused.remedy?.settingsPane == SystemSettingsPane.fullDiskAccess.rawValue)
    }

    /// ⛔ There is no time estimate, and there is not going to be one.
    @Test func theScanNeverPromisesATime() {
        #expect(ScanPolicy.Running.verb == "Scanning")
        #expect(ScanPolicy.Running.at("Downloads") == "Looking in Downloads")
        #expect(ScanPolicy.Running.whyThereIsNoEstimate.isEmpty == false)
    }
}
