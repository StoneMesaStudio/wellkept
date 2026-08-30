// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  MovableTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **Every test here is a way the engine could have destroyed something, and the reading that
//  stops it.**
//
//  The suite is written the other way round from a normal one: most of it proves that something is
//  **refused**. Four of the tests name traps that were measured on a real Mac on 2026-08-28 and that
//  the obvious implementation gets wrong — the shared device number between the two halves of the
//  boot disk, the symlinked parent, the folded filename, and the fact that a locked file is knowable
//  before it is touched.
//
//  Nothing here reads or writes anything outside a sandbox the test made itself.

// MARK: - ⭐ The four traps

@Suite struct MovableTrapTests {

    /// ⚠️ **The trap that defines the file.** The sealed System volume and the writable Data volume
    /// share a device number, and Foundation calls both "Macintosh HD" — even for `/System/Library`.
    /// Anything that separates them by `st_dev` or by display name will conclude that macOS itself
    /// is on the same volume as your Desktop, and offer to move it.
    @Test func onlyStatfsSeparatesTheTwoHalvesOfTheBootDisk() throws {
        guard let system = Movable.volume(of: "/System/Library"),
              let data = Movable.volume(of: FileManager.default.homeDirectoryForCurrentUser
                                            .path(percentEncoded: false))
        else { return }

        // The reading that works.
        #expect(system.mountPoint == "/", "the sealed system volume is the one mounted at /")
        #expect(system.isSealedSystem)
        #expect(!data.isSealedSystem, "the Data volume must never read as the sealed one")
        #expect(system.device != data.device,
                "f_mntfromname is the only thing that tells the two volumes apart")

        // The reading that does not, spelled out so nobody reaches for it later.
        var systemStat = stat(), dataStat = stat()
        _ = lstat("/System/Library", &systemStat)
        _ = lstat(FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
                  &dataStat)
        #expect(systemStat.st_dev == dataStat.st_dev,
                "st_dev is the same for both halves of the boot disk, so it cannot separate them")
    }

    /// ⚠️ **The failure class that ends a product.** Deleting through `Caches → RealAppSupport`
    /// destroys the real folder. The check names the component so the row can say which one.
    @Test func aSymlinkedParentIsRefusedByName() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let real = try sandbox.folder("RealAppSupport")
        try sandbox.file("RealAppSupport/live.db", contents: "somebody's actual data")
        try sandbox.link("Caches", to: real)

        let through = sandbox.home.appending(path: "Caches/live.db")
        let verdict = Movable.check(through, reach: sandbox.reach, checkOpenFiles: false)

        #expect(!verdict.isMovable)
        #expect(verdict.refusals.contains { if case .throughASymlink = $0 { return true }; return false },
                "acting through a symlinked parent must be refused, not followed")
        #expect(verdict.sentence?.contains("Caches") == true, "the row has to name the shortcut")
    }

    /// ⚠️ **Path strings are not identity here.** The volume folds case AND Unicode normalisation, so
    /// `casetest.TXT` opens `CaseTest.txt`. Moving it would work; restoring it would recreate
    /// somebody's file under a name it never had.
    @Test func aFoldedSpellingIsRefusedAndTheRealOneIsOffered() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let real = try sandbox.file("CaseTest.txt")
        let misspelt = sandbox.home.appending(path: "casetest.TXT")

        // Only meaningful on a case-insensitive volume, which is the default and what ships.
        guard FileManager.default.fileExists(atPath: misspelt.path(percentEncoded: false)) else {
            return
        }

        let verdict = Movable.check(misspelt, reach: sandbox.reach, checkOpenFiles: false)
        #expect(!verdict.isMovable)
        #expect(verdict.refusals.contains { if case .notWhatWasAsked = $0 { return true }; return false })

        // And the way forward, so a caller with a hand-typed path is not simply stuck.
        #expect(Movable.trueSpelling(of: misspelt.path(percentEncoded: false))
                == real.path(percentEncoded: false))
    }

    /// ⚠️ **What cannot be moved is knowable before trying**, with no root and no dialog. A path
    /// blocklist goes stale every macOS release; the flags travel with the file.
    @Test func aLockedFileIsRefusedFromItsFlagsRatherThanItsPath() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Documents/locked.txt")
        let path = file.path(percentEncoded: false)

        #expect(Movable.check(file, reach: sandbox.reach, checkOpenFiles: false).isMovable,
                "the same file, unlocked, is movable — so the refusal below is the flag and nothing else")

        #expect(chflags(path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(path, 0) }

        let verdict = Movable.check(file, reach: sandbox.reach, checkOpenFiles: false)
        #expect(!verdict.isMovable)
        #expect(verdict.refusals.contains { if case .locked = $0 { return true }; return false })
    }
}

// MARK: - The rest of the refusal list

@Suite struct MovableRefusalTests {

    @Test func macOSItselfIsRefusedAsTheSealedSystemVolume() {
        let verdict = Movable.check(URL(filePath: "/System/Library/CoreServices"),
                                    checkOpenFiles: false)
        #expect(!verdict.isMovable)
        #expect(verdict.refusals.contains {
            if case .onTheSealedSystemVolume = $0 { return true }; return false
        })
    }

    /// Without a privileged helper the engine reaches the home folder and `/Applications`, and the
    /// row says so rather than failing at the syscall with a permissions error nobody can read.
    @Test func theSystemLibraryIsOutOfReachAndSaysWhy() {
        let verdict = Movable.check(URL(filePath: "/Library/LaunchDaemons"), checkOpenFiles: false)
        #expect(!verdict.isMovable)
        #expect(verdict.refusals.contains { if case .outOfReach = $0 { return true }; return false })
        #expect(verdict.sentence?.contains("password") == true,
                "the sentence has to say that Wellkept will not ask for one")
    }

    @Test func nothingThereIsSaidPlainlyRatherThanSkipped() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let verdict = Movable.check(sandbox.home.appending(path: "was-never-here"),
                                    reach: sandbox.reach, checkOpenFiles: false)
        #expect(verdict.refusals == [.missing])
        #expect(verdict.reading == nil)
    }

    /// Pointing the engine at its own store is refused before anything else can be confused by it.
    @Test func wellkeptsOwnStoreIsOffLimits() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        try sandbox.folder("Library/Application Support/Wellkept/Quarantine")
        let inside = try sandbox.file("Library/Application Support/Wellkept/Quarantine/x.txt")

        let verdict = Movable.check(inside, reach: sandbox.reach, checkOpenFiles: false)
        #expect(verdict.refusals.contains(.inWellkeptsOwnStore))
    }

    /// Several true refusals are all reported. A person who unlocks a file only to be told it is
    /// also out of reach has been sent on an errand.
    @Test func everyReasonIsGivenAtOnce() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Documents/two-problems.txt")
        let path = file.path(percentEncoded: false)
        #expect(chflags(path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(path, 0) }

        // Reach that excludes the sandbox, so "locked" and "out of reach" are both true.
        let narrow = Reach(allowed: ["/Applications"], forbidden: [])
        let verdict = Movable.check(file, reach: narrow, checkOpenFiles: false)
        #expect(verdict.refusals.count >= 2, "both reasons, not just the first one found")
    }

    @Test func anOrdinaryFileInReachIsMovable() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Documents/fine.txt")
        let verdict = Movable.check(file, reach: sandbox.reach, checkOpenFiles: false)
        #expect(verdict.isMovable, "an ordinary file was refused: \(verdict.sentence ?? "no reason given")")
        #expect(verdict.reading?.bytes == 12)   // "the contents"
        #expect(verdict.reading?.isDirectory == false)
    }
}

// MARK: - Containment arithmetic

@Suite struct ReachTests {

    /// ⚠️ A plain `hasPrefix` gets two things wrong: it folds nothing, and it says `/Users/adams`
    /// is inside `/Users/ada`.
    @Test func aLongerNameIsNotInsideAShorterOne() {
        #expect(!Movable.isInside("/Users/adams/Documents", any: ["/Users/ada"]))
        #expect(Movable.isInside("/Users/ada/Documents", any: ["/Users/ada"]))
    }

    /// The filesystem folds case, so the containment test has to as well — otherwise reach is a
    /// guard that a differently-spelled path walks straight past.
    @Test func containmentFoldsCase() {
        #expect(Movable.isInside("/USERS/ADA/Documents/x", any: ["/Users/ada"]))
    }

    /// And normalisation. An NFD spelling opens the NFC file, so it has to land in the same place.
    @Test func containmentFoldsNormalisation() {
        let composed = "/Users/jos\u{00E9}/Documents"           // josé, one code point
        let decomposed = "/Users/jose\u{0301}/Documents/x"      // josé, e + combining acute
        #expect(Movable.isInside(decomposed, any: [composed]))
    }

    @Test func aRootIsInsideItself() {
        #expect(Movable.isInside("/Users/ada", any: ["/Users/ada"]))
    }

    @Test func theStandardReachIsTheHomeFolderAndApplications() {
        let reach = Reach.standard(home: URL(filePath: "/Users/example"))
        #expect(reach.allowed == ["/Users/example", "/Applications"])
        #expect(reach.forbidden.contains { $0.hasSuffix("Wellkept/Quarantine") })
    }

    @Test func placesAreNamedInWordsRatherThanPaths() {
        #expect(Reach.place(of: "/System/Library/Foo") == "macOS itself")
        #expect(Reach.place(of: "/Library/LaunchDaemons") == "the system Library folder")
        #expect(Reach.place(of: "/Volumes/Backup Drive/x") == "Backup Drive")
        #expect(Reach.place(of: "/usr/local/bin/x") == "the system folders")
    }
}

// MARK: - Who has it open

@Suite struct OpenFileCensusTests {

    /// ⚠️ The census exists because moving a file a running program holds open **succeeds
    /// silently** — the program keeps writing into the quarantined copy and breaks hours later.
    @Test func aFileThisProcessHoldsOpenIsReportedWithTheProgramsName() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Documents/held-open.txt")
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        let census = OpenFileCensus.take(of: [file])
        let holders = census.holders(of: file.path(percentEncoded: false))
        #expect(!holders.isEmpty, "lsof did not see a file this very process has open")

        let verdict = Movable.check(file, reach: sandbox.reach, census: census)
        #expect(!verdict.isMovable)
        #expect(verdict.refusals.contains { if case .openBy = $0 { return true }; return false })
        #expect(verdict.sentence?.contains("Quit") == true, "the sentence has to say what to do")
    }

    @Test func aFileNothingHasOpenIsNotReported() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Documents/closed.txt")
        #expect(OpenFileCensus.take(of: [file]).holders(of: file.path(percentEncoded: false)).isEmpty)
    }

    @Test func anEmptyListAsksNothingOfLsof() {
        #expect(OpenFileCensus.take(of: []).isEmpty)
    }
}

// MARK: - iCloud

@Suite struct ICloudWarningTests {

    /// The answer, 2026-08-28: allowed, **with** the warning. Never refused.
    @Test func theWarningIsOneLineAndNamesBothDevices() {
        #expect(Movable.iCloudWarning == "This also removes it from your iPhone and iPad.")
        #expect(QuarantineWords.iCloud == Movable.iCloudWarning,
                "one copy of the line, or it drifts")
    }

    @Test func aFileInICloudDriveIsRecognisedByItsPlace() {
        let inDrive = URL(filePath: "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/x")
        #expect(Movable.isInICloud(inDrive))
        #expect(!Movable.isInICloud(URL(filePath: "/Users/example/Documents/x")))
    }

    /// ⚠️ Being in iCloud is never a refusal. If it were, the most ordinary finding in the product
    /// would be blocked on every Mac with Desktop & Documents sync switched on.
    @Test func iCloudIsNotOnTheRefusalList() {
        let reasons: [MoveRefusal] = [
            .missing, .protectedBySystem, .inADataVault, .notDownloaded, .inWellkeptsOwnStore,
        ]
        for reason in reasons {
            #expect(!reason.sentence.lowercased().contains("icloud"),
                    "no refusal may be about iCloud — it is allowed, with a warning")
        }
    }
}
