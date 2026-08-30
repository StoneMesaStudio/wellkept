// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  JunkClassifierTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **Most of this suite proves that something is NOT junk.**
//
//  That is the right shape for the one file in the product that may arrive with a box already
//  ticked. A test that says "Xcode's build folder was found" protects nobody; a test that says "the
//  audiobook in the cache folder was not" is the whole product.
//
//  Every fixture below is a real thing on the Mac this was measured on, 2026-08-28. Nothing here
//  writes, moves or opens anything; the four live tests at the end read directory listings and
//  assert shape, never contents.

private let home = URL(filePath: "/Users/measured")

private func folder(_ path: String,
                    _ entries: [String],
                    modifiedOn: Date? = nil,
                    cutShort: Bool = false) -> JunkClassifier.Subject {
    JunkClassifier.Subject(path: path,
                           isDirectory: true,
                           entries: entries,
                           listingWasCutShort: cutShort,
                           modifiedOn: modifiedOn)
}

private func file(_ path: String, modifiedOn: Date? = nil) -> JunkClassifier.Subject {
    JunkClassifier.Subject(path: path, isDirectory: false, modifiedOn: modifiedOn)
}

/// Sixty-four hexadecimal characters, the way Homebrew files a download.
private func checksum(_ seed: Int) -> String {
    String(format: "%064x", seed &* 2_654_435_761)
}

// MARK: - ⭐ The audiobook

@Suite("The audiobook in the cache folder survives every rule in the file")
struct TheAudiobookSurvives {

    /// ⭐ **The measured case: `~/Library/Caches/com.apple.bookassetd/1442759222/Track 1.m4b`,
    /// 1.3 GB, put there by Apple Books.**
    ///
    /// Three folders deep, and the classifier has to refuse all three. `com.apple.bookassetd` is a
    /// genuine Apple bundle identifier, so "filed under an installed app's identifier" would have
    /// convicted it — which is why that rule is not in the file.
    @Test func noLayerOfItIsEverJunk() {
        let outer = folder("/Users/measured/Library/Caches/com.apple.bookassetd",
                           ["1442759222", "1414995472"])
        let store = folder("/Users/measured/Library/Caches/com.apple.bookassetd/1442759222",
                           ["Track 1.m4b", "cover.jpg"])
        let track = file("/Users/measured/Library/Caches/com.apple.bookassetd/1442759222/Track 1.m4b")

        for subject in [outer, store, track] {
            let judgement = JunkClassifier.judge(subject, home: home)
            #expect(judgement.origin == .yours, "\(subject.name) was called the machine's")
            #expect(judgement.arrivesTicked == false)
            #expect(judgement.category == nil)
        }
    }

    /// The store number is ten digits, and every one of them is a hexadecimal character. Sixteen is
    /// the difference between a rule and an accident.
    @Test func aStoreNumberIsNotAChecksum() {
        #expect(JunkClassifier.looksLikeAChecksum("1442759222") == false)
        #expect(JunkClassifier.looksLikeAChecksum("1414995472") == false)
    }

    /// ⭐ **The second, independent reason it survives.** Even a file named after a perfect
    /// checksum is refused if it carries an extension a person recognises.
    @Test func anExtensionAPersonKnowsIsNeverPartOfACache() {
        #expect(JunkClassifier.looksLikeAChecksum("\(checksum(7)).m4b") == false)
        #expect(JunkClassifier.looksLikeAChecksum("\(checksum(7)).pdf") == false)
        #expect(JunkClassifier.looksLikeAChecksum("\(checksum(7)).heic") == false)
        // The machine's own formats are not on the list, or Homebrew's downloads would be refused.
        #expect(JunkClassifier.looksLikeAChecksum("\(checksum(7))--gettext.bottle_manifest.json"))
    }

    /// ⚠️ **One recognisable file spoils the whole folder**, whatever the other four thousand look
    /// like. This is the rule generalised: if a person could recognise something in there, it is not
    /// a cache.
    @Test func oneRecognisableFileDisqualifiesTheFolder() {
        var entries = (0..<400).map { checksum($0) }
        let clean = folder("/Users/measured/Library/Caches/Some/Store", entries)
        #expect(JunkClassifier.judge(clean, home: home).category == .contentAddressedCache)

        entries.append("Interview with mum.m4a")
        let spoiled = folder("/Users/measured/Library/Caches/Some/Store", entries)
        #expect(JunkClassifier.judge(spoiled, home: home).origin == .yours)
    }
}

// MARK: - ⚠️ The Herd trap

@Suite("Nothing is concluded from an absence")
struct TheHerdTrap {

    /// ⚠️ **90 MB in Application Support, no app, no receipt, no Spotlight entry, untouched for
    /// four and a half months — and it is a working PHP install.**
    ///
    /// It is safe because there is no rule in the file that reasons from absence. This test would
    /// fail the moment somebody adds one.
    @Test func theOwnersPhpIsNotJunk() {
        let herd = folder("/Users/measured/Library/Application Support/Herd",
                          ["bin", "config", "php", "composer.phar"],
                          modifiedOn: Date(timeIntervalSinceNow: -60 * 60 * 24 * 135))
        let judgement = JunkClassifier.judge(herd, home: home)
        #expect(judgement.origin == .yours)
        #expect(judgement.arrivesTicked == false)
    }

    /// Herd's own cache folder is under `~/Library/Caches`, and it is still not junk: its files have
    /// names a person could read.
    @Test func herdsCacheFolderIsNotAContentAddressedStore() {
        let cache = folder("/Users/measured/Library/Caches/de.beyondco.herd",
                           ["services.json", "valet", "logs", "nginx.conf"])
        #expect(JunkClassifier.judge(cache, home: home).origin == .yours)
    }

    /// ⭐ **Location narrows. It never convicts.** Being inside `~/Library/Caches` is not evidence
    /// of anything at all.
    @Test func beingInsideTheCacheFolderProvesNothing() {
        let readable = folder("/Users/measured/Library/Caches/pip",
                              ["http-v2", "wheels", "selfcheck.json"])
        #expect(JunkClassifier.judge(readable, home: home).origin == .yours)
    }
}

// MARK: - ⭐ Xcode's build folders

@Suite("Xcode's build folders are found by what is inside them")
struct XcodeBuildOutput {

    /// The ordinary shape: `Waypoint-djcjvzisnpplxdfssrrwkaetabzs`.
    @Test func aDerivedDataFolderIsJunk() {
        let built = folder("/Users/measured/Library/Developer/Xcode/DerivedData/Waypoint-djcjvzisnpplxdfssrrwkaetabzs",
                           ["Build", "Index.noindex", "Logs", "TestResults", "info.plist"])
        let judgement = JunkClassifier.judge(built, home: home)
        #expect(judgement.category == .xcodeBuildOutput)
        #expect(judgement.origin == .machineJunk)
        #expect(judgement.arrivesTicked)
        #expect(judgement.stopHere, "a junk folder is junk whole — descending counts it twice")
    }

    /// ⭐ **The case a name rule would have missed.** This folder is real and it is called
    /// `Lode-desktop-launcher` — no hash, no dash-and-28-letters. Structure catches it.
    @Test func aFolderWithNoHashInItsNameIsStillFound() {
        let built = folder("/Users/measured/Library/Developer/Xcode/DerivedData/Lode-desktop-launcher",
                           ["Build", "CompilationCache.noindex", "Index.noindex", "Logs",
                            "SourcePackages", "info.plist", "last-build.log"])
        #expect(JunkClassifier.judge(built, home: home).category == .xcodeBuildOutput)
    }

    /// ⭐ And the same rule catches a project whose derived data was pointed somewhere else, because
    /// nothing about it depends on where it is.
    @Test func derivedDataPointedElsewhereIsStillFound() {
        let built = folder("/Users/measured/Projects/scratch/DerivedOutput",
                           ["Build", "Index.noindex", "info.plist"])
        #expect(JunkClassifier.judge(built, home: home).category == .xcodeBuildOutput)
    }

    /// ⚠️ Two markers are not three. A folder with an `info.plist` and a `Build` folder and nothing
    /// of Apple's do-not-index suffix is somebody's project, and this is the near miss that proves
    /// the rule is not loose.
    @Test func twoMarkersAreNotEnough() {
        let project = folder("/Users/measured/Sites/thing", ["Build", "info.plist", "src"])
        #expect(JunkClassifier.judge(project, home: home).origin == .yours)
    }

    /// `ModuleCache.noindex` is 4.4 GB here — a third of the whole category — and carries no marker
    /// of its own.
    @Test func xcodesSharedCachesAreFound() {
        let shared = folder("/Users/measured/Library/Developer/Xcode/DerivedData/ModuleCache.noindex",
                            ["A1B2C3", "D4E5F6"])
        #expect(JunkClassifier.judge(shared, home: home).category == .xcodeBuildOutput)
    }

    /// The same name anywhere else is not.
    @Test func aNoIndexFolderSomewhereElseIsNotXcodes() {
        let elsewhere = folder("/Users/measured/Documents/ModuleCache.noindex", ["a", "b"])
        #expect(JunkClassifier.judge(elsewhere, home: home).origin == .yours)
    }

    /// ⚠️ **The measurement that keeps the 30-day filter away from this category.** 96% of the 13 GB
    /// here was written in the last month, so an age filter would untick nearly all of it.
    @Test func ageDoesNotUntickABuildFolder() {
        let fresh = folder("/Users/measured/Library/Developer/Xcode/DerivedData/Wellkept-abc",
                           ["Build", "Index.noindex", "info.plist"],
                           modifiedOn: Date())
        #expect(JunkClassifier.judge(fresh, home: home).arrivesTicked)
        #expect(JunkClassifier.Category.xcodeBuildOutput.theAnnoyanceFilterApplies == false)
    }
}

// MARK: - ⭐ The three content-addressed stores measured here

@Suite("A store where every name is a checksum")
struct ContentAddressedCaches {

    /// Firefox: `cache2/entries`, 760 MB, forty uppercase hexadecimal characters each.
    @Test func firefoxsPageCacheIsFound() {
        let entries = folder("/Users/measured/Library/Caches/Firefox/Profiles/jpwwfy37.default-release/cache2/entries",
                             ["001A35731806701800B01AD330846DA5B7176DA3",
                              "002701DF61C1CF0B80A3F1635EA8F32375070D4E",
                              "0030C32FBF063A910EF3A98F9868226944D95795",
                              "0130C32FBF063A910EF3A98F9868226944D95795",
                              "0230C32FBF063A910EF3A98F9868226944D95795",
                              "0330C32FBF063A910EF3A98F9868226944D95795",
                              "0430C32FBF063A910EF3A98F9868226944D95795",
                              "0530C32FBF063A910EF3A98F9868226944D95795"])
        #expect(JunkClassifier.judge(entries, home: home).category == .contentAddressedCache)
    }

    /// ⚠️ And `cache2` itself is not, because its own children have names — `entries`, `doomed`,
    /// `index`. The walk goes one level further and finds the bytes there.
    @Test func theFolderAboveItIsNot() {
        let cache2 = folder("/Users/measured/Library/Caches/Firefox/Profiles/jpwwfy37.default-release/cache2",
                            ["entries", "doomed", "index"])
        #expect(JunkClassifier.judge(cache2, home: home).origin == .yours)
    }

    /// Chrome: `Cache_Data`, 434 MB. Sixteen hexadecimal characters and a suffix, plus the two
    /// index files a store of this kind keeps beside its contents.
    @Test func chromesPageCacheIsFound() {
        var entries = ["index", "index-dir", "a280fc951a3a105c_s", "dcb7d2faaf6ca81d_s"]
        entries += (0..<20).map { String(format: "%016x_0", $0 &* 2_654_435_761) }
        let data = folder("/Users/measured/Library/Caches/Google/Chrome/Default/Cache/Cache_Data", entries)
        #expect(JunkClassifier.judge(data, home: home).category == .contentAddressedCache)
    }

    /// Homebrew: 155 MB across 141 files, each a 64-character checksum, two dashes and a readable
    /// tail. The tail is why the rule is "hexadecimal then a separator" and not "hexadecimal only".
    @Test func homebrewsDownloadsAreFound() {
        let entries = (0..<12).map { "\(checksum($0))--package-\($0).arm64_tahoe.bottle.tar.gz" }
        let downloads = folder("/Users/measured/Library/Caches/Homebrew/downloads", entries)
        #expect(JunkClassifier.judge(downloads, home: home).category == .contentAddressedCache)
    }

    /// ⚠️ **A store filed under checksums is also what a backup looks like from outside.** So we
    /// look for one only where the system says caches live — never in a project folder, never in
    /// Documents.
    @Test func aChecksumStoreOutsideACacheFolderIsLeftAlone() {
        let entries = (0..<40).map { checksum($0) }
        for path in ["/Users/measured/Backups/restic/data/ab",
                     "/Users/measured/Sites/app/storage/framework/cache/data",
                     "/Users/measured/Documents/objects"] {
            #expect(JunkClassifier.judge(folder(path, entries), home: home).origin == .yours,
                    "\(path) was swept")
        }
    }

    /// ⛔ The whole cache folder is never one thing to press once.
    @Test func theCacheFolderItselfIsNeverOffered() {
        let entries = (0..<40).map { checksum($0) }
        let root = folder("/Users/measured/Library/Caches", entries)
        #expect(JunkClassifier.judge(root, home: home).origin == .yours)
    }

    /// Eight is the smallest number of checksum-named files that reads as a store rather than a
    /// coincidence.
    @Test func aHandfulIsNotAStore() {
        let few = folder("/Users/measured/Library/Caches/Thing", (0..<4).map { checksum($0) })
        #expect(JunkClassifier.judge(few, home: home).origin == .yours)
    }

    /// ⚠️ **A folder too big to list in full convicts nobody.** Sampling would put one audiobook at
    /// position thirty thousand out of reach of the only rule that protects it.
    @Test func aTruncatedListingIsNotJunk() {
        let entries = (0..<400).map { checksum($0) }
        let cut = folder("/Users/measured/Library/Caches/Huge", entries, cutShort: true)
        #expect(JunkClassifier.judge(cut, home: home).origin == .yours)
    }
}

// MARK: - Half-finished downloads, and the one job age has

@Suite("A download that stopped part way")
struct HalfFinishedDownloads {

    @Test func anOldPartialIsJunkAndArrivesTicked() {
        let old = file("/Users/measured/Downloads/ubuntu.iso.crdownload",
                       modifiedOn: Date(timeIntervalSinceNow: -60 * 60 * 24 * 200))
        let judgement = JunkClassifier.judge(old, home: home)
        #expect(judgement.category == .halfFinishedDownload)
        #expect(judgement.arrivesTicked)
    }

    /// ⚠️ **The annoyance filter's one real job**: do not make me start over on something I was
    /// downloading this week. It takes the tick away and leaves the row.
    @Test func aRecentPartialIsListedButNotTicked() {
        let recent = file("/Users/measured/Downloads/film.mkv.part",
                          modifiedOn: Date(timeIntervalSinceNow: -60 * 60 * 24 * 3))
        let judgement = JunkClassifier.judge(recent, home: home)
        #expect(judgement.category == .halfFinishedDownload)
        #expect(judgement.arrivesTicked == false)
        #expect(judgement.notTickedBecause != nil)
    }

    /// ⚠️ A file something is writing to right now is not offered at all. A move would succeed and
    /// the browser would keep writing into a copy nobody will ever see.
    @Test func aDownloadInProgressIsNotOffered() {
        let live = file("/Users/measured/Downloads/big.zip.crdownload",
                        modifiedOn: Date(timeIntervalSinceNow: -120))
        #expect(JunkClassifier.judge(live, home: home).origin == .yours)
    }

    @Test func safarisPartialPackageCounts() {
        let safari = file("/Users/measured/Downloads/Xcode.xip.download",
                          modifiedOn: Date(timeIntervalSinceNow: -60 * 60 * 24 * 90))
        #expect(JunkClassifier.judge(safari, home: home).category == .halfFinishedDownload)
    }
}

// MARK: - ⛔ The simulator runtimes: a size, and no offer

@Suite("The simulator runtimes are reported and never offered")
struct SimulatorRuntimes {

    /// ⛔ The one category that may not be ticked, and it is not a near miss.
    @Test func theyMayNeverBeTicked() {
        #expect(JunkClassifier.Category.simulatorRuntime.mayBeTicked == false)
        for other in JunkClassifier.Category.allCases where other != .simulatorRuntime {
            #expect(other.mayBeTicked, "\(other.rawValue) is a category that would never be ticked")
        }
    }

    /// ⭐ **Read on this Mac.** Shape only — a Mac with no Xcode has none, and that is a fine
    /// answer. What must hold everywhere is that not one of them offers a button, and that not one
    /// of them claims anything comes back.
    @Test func nothingReadFromThisMacOffersAButton() {
        for item in JunkClassifier.simulatorRuntimeItems() {
            #expect(item.origin == .machineJunk)
            #expect(item.handling.mayOfferAButton == false)
            #expect(item.mayBePreSelected == false)
            #expect(item.bytes.recoverableToday.isZero)
            #expect(item.bytes.onDisk.bytes > 0)
            #expect(item.reason.isEmpty == false)
        }
    }

    /// ⚠️ **Size on disk, not the size of the volume it mounts to.** Measured 2026-08-28: the two
    /// mounted runtimes report 24 GB used between them and the images behind them are 11.6 GB. If
    /// this ever reads the mount, the section starts overstating by more than double.
    @Test func theSizeComesFromTheImageAndNotTheMount() {
        let runtimes = JunkClassifier.simulatorRuntimes()
        for runtime in runtimes {
            #expect(runtime.path.hasSuffix(".dmg"))
            #expect(runtime.path.hasPrefix(JunkClassifier.assetStore))
            #expect(runtime.bytes.bytes > 0)
        }
        // Largest first, so the row does not have to sort them again.
        #expect(runtimes == runtimes.sorted { $0.bytes > $1.bytes })
    }

    /// The mount table is read for the sentence, not for the size. No subprocess, no privilege.
    @Test func theMountedVolumesReadWithoutPrivilege() {
        for point in JunkClassifier.mountedSimulatorVolumes() {
            #expect(point.hasPrefix("/Library/Developer/CoreSimulator/Volumes/"))
        }
    }
}

// MARK: - ⭐ The law, as tests

@Suite("The law the classifier exists to keep")
struct TheLaw {

    /// ⭐ **Anything this file cannot convict is the person's**, is never ticked, and never sweeps.
    @Test func theDefaultIsAlwaysYours() {
        let unknown = [folder("/Users/measured/Documents/Media", ["a.mov", "b.mov"]),
                       folder("/Users/measured/Library/Application Support/SomeThing", ["data"]),
                       file("/Users/measured/Desktop/notes.txt"),
                       folder("/Users/measured/Library/Caches/Weird", [])]
        for subject in unknown {
            let judgement = JunkClassifier.judge(subject, home: home)
            #expect(judgement.origin == .yours)
            #expect(judgement.origin.mayBePreSelected == false)
            #expect(judgement.origin.maySweep == false)
            #expect(judgement.origin.ceremony == .oneAtATime)
            #expect(judgement.arrivesTicked == false)
            #expect(judgement.stopHere == false)
        }
    }

    /// ⭐ **Every category answers all four questions.** Anything that cannot is not a category —
    /// this is that sentence, enforced.
    @Test func everyCategoryAnswersAllFour() {
        for category in JunkClassifier.Category.allCases {
            #expect(category.whatItIs.count > 20, "\(category.rawValue) does not say what it is")
            #expect(category.howItComesBack.count > 20,
                    "\(category.rawValue) cannot name what puts it back, so it is not a category")
            #expect(category.ifWeAreWrong.count > 10,
                    "\(category.rawValue) does not say what being wrong costs")
            #expect(category.label.isEmpty == false)
            #expect(category.origin == .machineJunk)
            #expect(category.reason.contains(category.howItComesBack))
        }
    }

    /// ⚠️ **Age never causes a tick.** It can only ever take one away, on the one category where it
    /// is not a lie.
    @Test func ageIsNeverTheReasonForAnything() {
        let ancient = Date(timeIntervalSinceNow: -60 * 60 * 24 * 4_000)
        let old = folder("/Users/measured/Documents/Old project", ["a", "b"], modifiedOn: ancient)
        #expect(JunkClassifier.judge(old, home: home).origin == .yours)

        let filtered = JunkClassifier.Category.allCases.filter(\.theAnnoyanceFilterApplies)
        #expect(filtered == [.halfFinishedDownload],
                "the 30-day filter spread to a category where it unticks the whole win")
    }

    /// ⛔ **`ScanPolicy`'s refusals are absolute.** Anything on the refusal list gets its reason and
    /// no button, whatever category it might otherwise have fallen into.
    @Test func aRefusedThingNeverGetsAButton() {
        let insideAnApp = folder("/Applications/Thing.app/Contents/Frameworks/Cache.noindex",
                                 ["Build", "Index.noindex", "info.plist"])
        let judgement = JunkClassifier.judge(insideAnApp, home: home)
        #expect(judgement.arrivesTicked == false)
        #expect(judgement.handling.mayOfferAButton == false)

        let library = folder("/Users/measured/Pictures/Photos Library.photoslibrary/resources",
                             (0..<40).map { checksum($0) })
        #expect(JunkClassifier.judge(library, home: home).arrivesTicked == false)
    }

    /// ⭐ **The tick this file chooses is always inside the ceiling the row permits.**
    ///
    /// `Item.mayBePreSelected` also refuses anything that is not on this Mac, which is how a file
    /// living only in iCloud can never arrive ticked whatever category it fell into.
    @Test func theTickNeverExceedsWhatTheRowWouldAllow() {
        let built = folder("/Users/measured/Library/Developer/Xcode/DerivedData/Waypoint-abc",
                           ["Build", "Index.noindex", "info.plist"])
        let identity = ItemIdentity(volumeUUID: nil, volumeDevice: "/dev/disk3s5", inode: 42)
        let bytes = Bytes.allOfIt(SizeOnDisk(2_000_000_000))

        let here = JunkClassifier.classify(built, identity: identity, bytes: bytes, kind: .folder,
                                           home: home)
        #expect(here.arrivesTicked)
        #expect(here.item.mayBePreSelected)

        let inTheCloud = JunkClassifier.classify(built, identity: identity, bytes: bytes,
                                                 kind: .folder, cloudStanding: .inTheCloudOnly,
                                                 home: home)
        #expect(inTheCloud.arrivesTicked == false)
        #expect(inTheCloud.item.origin == .machineJunk)
    }

    /// A row built from these ticks: what arrives ticked is a subset of what the row permits.
    @Test func theRowAndTheClassifierAgree() {
        let identity = { (n: UInt64) in ItemIdentity(volumeUUID: nil, volumeDevice: "d", inode: n) }
        let junk = JunkClassifier.classify(
            folder("/Users/measured/Library/Developer/Xcode/DerivedData/A-b",
                   ["Build", "Index.noindex", "info.plist"]),
            identity: identity(1), bytes: .allOfIt(SizeOnDisk(1_000)), kind: .folder, home: home)
        let mine = JunkClassifier.classify(
            folder("/Users/measured/Documents/Media", ["film.mov"]),
            identity: identity(2), bytes: .allOfIt(SizeOnDisk(9_000)), kind: .folder, home: home)

        let row = StorageRow(topic: .machineJunk,
                             headline: "Two things this Mac made",
                             items: [junk.item, mine.item])
        let ticked = Set(JunkClassifier.arrivingTicked([junk, mine]).map(\.id))
        let permitted = Set(row.preSelected.map(\.id))
        #expect(ticked.isSubset(of: permitted))
        #expect(ticked.contains(junk.item.id))
        #expect(permitted.contains(mine.item.id) == false)
    }

    /// ⭐ Your own files are never pre-selected on any row, whatever anybody claims about them.
    @Test func yourOwnFilesAreNeverPreSelectedOnAnyRow() {
        let mine = JunkClassifier.classify(
            folder("/Users/measured/Movies/Wedding", ["a.mov"]),
            identity: ItemIdentity(volumeUUID: nil, volumeDevice: "d", inode: 3),
            bytes: .allOfIt(SizeOnDisk(12_000_000_000)), kind: .folder, home: home)

        for topic in StorageTopic.allCases {
            let row = StorageRow(topic: topic, headline: "x", items: [mine.item])
            #expect(row.preSelected.isEmpty, "\(topic.rawValue) pre-selected somebody's own file")
        }
    }
}

// MARK: - What this Mac actually says

@Suite("Read from this Mac, read-only")
struct OnThisMac {

    /// ⭐ **The live version of the audiobook test.** On one real Mac there are two audiobooks under
    /// `~/Library/Caches/com.apple.bookassetd`, 1.5 GB between them. Every folder on the way down to
    /// them has to come back as the person's. On a Mac with no audiobooks this passes trivially,
    /// which is correct.
    @Test func theRealAudiobooksAreNotTouched() {
        let manager = FileManager.default
        let books = manager.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/com.apple.bookassetd")
        guard let subject = JunkClassifier.Subject.onDisk(books) else { return }

        #expect(JunkClassifier.judge(subject).origin == .yours)
        for entry in subject.entries.prefix(50) {
            guard let store = JunkClassifier.Subject.onDisk(books.appending(path: entry)) else { continue }
            #expect(JunkClassifier.judge(store).origin == .yours,
                    "\(entry) inside the book cache was called the machine's")
        }
    }

    /// ⚠️ **Whatever this Mac's cache folder holds, nothing directly inside it may be swept whole.**
    ///
    /// The stores are always further down, under the program that owns them — Firefox's is five
    /// levels below, Chrome's six. A hit at the first level would mean the rule had become loose
    /// enough to take a whole vendor's folder in one press.
    @Test func nothingOneLevelIntoTheCacheFolderIsSweptWhole() {
        let caches = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: caches.path(percentEncoded: false))
        else { return }

        for entry in entries.prefix(200) {
            guard let subject = JunkClassifier.Subject.onDisk(caches.appending(path: entry)) else { continue }
            #expect(JunkClassifier.judge(subject).category != .contentAddressedCache,
                    "\(entry) was swept whole, one level below the cache folder")
        }
    }

    /// The reader that finds the real folders is doing something rather than returning nothing.
    @Test func aFolderCanBeReadFromTheDisk() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let subject = JunkClassifier.Subject.onDisk(home)
        #expect(subject != nil)
        #expect(subject?.isDirectory == true)
        #expect(subject?.entries.isEmpty == false)
    }
}
