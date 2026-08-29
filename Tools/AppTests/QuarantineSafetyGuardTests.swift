// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  QuarantineSafetyGuardTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The three ways somebody could quietly undo all of this later, each nailed shut.**
//
//  1. **A copy fallback.** Somebody hits `EXDEV` in a bug report, adds "just copy it then", and the
//     app starts losing creation dates, ACLs and download provenance on every move — visibly
//     working, every time. A source scan below fails the build on the day that line is written.
//  2. **Writing over the file the person came back for.** Restore into an occupied path, and the
//     newer file is destroyed by the thing that was supposed to be the undo.
//  3. **A broken symbolic link.** `FileManager.fileExists` follows the link and reports `false` for
//     one that points at nothing — so a link the engine is holding reads as absent. Leftovers from
//     uninstalled apps are full of these, which makes it the most ordinary junk file there is.

// MARK: - ⭐ There is one move, and there must never be a second

@Suite("Nothing in the app ever copies a file instead of moving it")
struct OneMoveOnlyGuardTests {

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tools/AppTests
            .deletingLastPathComponent()   // Tools
            .deletingLastPathComponent()   // the repository
    }

    /// Every shipping Swift file, as repository-relative paths.
    private static func shippingFiles() -> [(path: String, text: String)] {
        let root = repositoryRoot
        let base = root.appendingPathComponent("App")
        guard let walker = FileManager.default.enumerator(at: base,
                                                          includingPropertiesForKeys: nil)
        else { return [] }
        var found: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            found.append((String(url.path.dropFirst(root.path.count + 1)), text))
        }
        return found
    }

    /// Lines that are code rather than commentary. Crude on purpose — it over-reports, and a
    /// guard that over-reports gets read, while one that under-reports gets trusted wrongly.
    private static func codeLines(of text: String) -> [(number: Int, line: String)] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { ($0.offset + 1, String($0.element)) }
            .filter { !$0.1.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private static func mentions(_ needle: String) -> [String] {
        shippingFiles().flatMap { file in
            codeLines(of: file.text)
                .filter { $0.line.contains(needle) }
                .map { "\(file.path):\($0.number)" }
        }
    }

    @Test("The scanner is looking at the app")
    func theScannerReadsTheApp() {
        #expect(Self.shippingFiles().count > 20,
                "the source scan found almost nothing — it is pointed at the wrong folder")
        #expect(Self.mentions("renameatx_np").count == 1,
                "the scanner cannot find the one call it is guarding")
    }

    /// ⭐ **One rename, in one place.** `AtomicMove` is the only thing that moves a user's file.
    ///
    /// ⚠️ **Amended 2026-08-29, when the backup engine arrived.** The rule was never "only one file
    /// may call it" — it was **"there is one implementation of moving a file, and nobody writes a
    /// second"**. `App/Backup/Engine/BackupRun.swift` moves the previous copy of a file aside on the
    /// **backup drive's own volume** before writing the new one, and the correct thing for it to do
    /// is call this one. Writing its own rename there — without `RENAME_EXCL`, without
    /// `RENAME_NOFOLLOW_ANY` — is exactly the second mover this guard exists to prevent.
    ///
    /// So the syscall is still counted, and it is still in one file. The caller list is a short
    /// **named** list, and an entry that is not recorded here fails the build.
    static let mayPerformTheMove: [String: String] = [
        "App/Quarantine/Quarantine.swift":
            "the engine itself — set aside, put back, empty",
        "App/Backup/Engine/BackupRun.swift":
            "keeps the previous version on the backup drive, on that drive's own volume, before the new copy is written",
    ]

    @Test("There is exactly one move in the whole app")
    func onlyOneFileMovesAnything() {
        let syscall = Self.mentions("renameatx_np(")
        #expect(syscall.count == 1, "renameatx_np is called from more than one place: \(syscall)")
        #expect(syscall.first?.hasPrefix("App/Quarantine/Quarantine.swift:") == true,
                "the one rename in the app is not in the quarantine engine: \(syscall)")

        let callers = Set(Self.mentions("AtomicMove.perform(").map {
            $0.split(separator: ":").first.map(String.init) ?? $0
        })
        let unrecorded = callers.filter { Self.mayPerformTheMove[$0] == nil }
        #expect(unrecorded.isEmpty, """
            something performs the move without being recorded as allowed to: \(unrecorded.sorted()). \
            Add it to mayPerformTheMove WITH the reason, or — far more likely — call the one move \
            rather than writing a second one.
            """)
        // ⚠️ And the backup engine calls it exactly once. A second call there would be a copy
        // path growing quietly beside the one that is reviewed.
        let inTheBackupEngine = Self.mentions("AtomicMove.perform(")
            .filter { $0.hasPrefix("App/Backup/") }
        #expect(inTheBackupEngine.count <= 1,
                "the backup engine moves files in more than one place: \(inTheBackupEngine)")
    }

    /// ⚠️ **The line nobody may write.** A copy is a different act with different consequences:
    /// `clonefile` drops ACLs, `copyfile` loses the creation date and launders the attribute that
    /// tells macOS a file came off the internet, and neither is atomic.
    ///
    /// The one exception is `FileManager.copyItem` on the ledger itself, which is how a damaged
    /// record is kept rather than thrown away. That is a JSON file of ours, not anybody's document.
    @Test("There is no copy fallback anywhere, and no way to add one quietly")
    func nothingCopiesAUsersFile() {
        #expect(Self.mentions("clonefile").isEmpty,
                "clonefile drops ACLs: \(Self.mentions("clonefile"))")
        // ⚠️ **Amended 2026-08-29.** `copyfile` is still banned everywhere it would be a *move*
        // wearing a disguise — which is what this guard was written for. A **backup** is a
        // different act: the destination is a different drive by definition, so a rename is not
        // available at any price (`renameatx_np` returns `EXDEV` across volumes). One file is
        // allowed to copy, it is the whole of the backup copier, and it exists to pay back the four
        // things a copy costs — the creation date, the download-provenance tag, sparseness and hard
        // links. See the header of `App/Backup/Engine/CopyOne.swift`.
        let theOneCopier = "App/Backup/Engine/CopyOne.swift"
        let copyfiles = Self.mentions("copyfile(")
        #expect(copyfiles.allSatisfy { $0.hasPrefix(theOneCopier + ":") }, """
            copyfile is used outside the one copier: \(copyfiles). It loses the creation date, \
            launders the download-provenance tag, inflates sparse files and ignores hard links. \
            Inside a volume the answer is the move; across volumes the answer is \(theOneCopier), \
            which repairs all four — not a second copy path beside it.
            """)
        // ⭐ And that one copier cannot be called without asking the gate.
        let copier = (try? String(contentsOf: Self.repositoryRoot.appendingPathComponent(theOneCopier),
                                  encoding: .utf8)) ?? ""
        #expect(copier.contains("permittedBy pass: RehearsalGate.Pass"),
                "the backup copier no longer takes a RehearsalGate.Pass, so anything can call it")

        let copies = Self.mentions("copyItem")
        #expect(copies.allSatisfy { $0.hasPrefix("App/Quarantine/Ledger.swift:") }, """
            something copies a file outside the ledger's own keep-a-copy: \(copies). A copy is not \
            a move — it loses the creation date, the ACLs and the download provenance, and it is \
            not atomic. If this is a cross-volume case, the answer is the refusal, not a copy.
            """)
    }

    /// `FileManager.moveItem` copies and removes when it crosses a volume, so it is not the safe
    /// move — it is only allowed in `handOver`, where the person picked the destination themselves
    /// and the alternative is leaving their files in a folder belonging to a deleted app.
    @Test("The one function allowed to cross disks is the uninstaller's, and only that one")
    func onlyTheHandOverCrossesDisks() {
        // ⚠️ `.moveItem(`, with the dot: "moveItem" on its own is a substring of "removeItem",
        // and a guard that fires on every removal is a guard somebody deletes.
        let moves = Self.mentions(".moveItem(")
        #expect(moves.allSatisfy { $0.hasPrefix("App/Quarantine/Quarantine.swift:") }, """
            FileManager.moveItem is used outside the uninstaller hand-over: \(moves). It copies \
            and removes across a volume, which is exactly what the engine refuses to do.
            """)
        #expect(moves.count <= 1, "there is more than one cross-volume move: \(moves)")
    }

    /// Automatic removal has one entry point, and nothing else in the app deletes on a clock.
    @Test("Only the sweep on opening ever removes anything by itself")
    func theOnlyAutomaticRemovalIsTheOneJohnAgreedTo() {
        let root = Self.repositoryRoot
            .appendingPathComponent("App/Quarantine/Expiry.swift")
        let text = (try? String(contentsOf: root, encoding: .utf8)) ?? ""
        let deletes = Self.codeLines(of: text).filter { $0.line.contains("Quarantine.delete(") }
        #expect(deletes.count == 1,
                "Expiry removes things from more than one place: \(deletes.map(\.number))")
        #expect(!text.contains("Timer("), "expiry is on a timer, which John did not agree to")
        #expect(!text.contains("DispatchSourceTimer"), "expiry is on a timer")
    }
}

// MARK: - ⭐ Restore never writes over what the person came back for

@Suite("A restore refuses rather than destroying the newer file")
struct RestoreNeverOverwritesTests {

    /// Between the quarantine and the restore, the person re-downloaded the installer or saved the
    /// document again. Putting the old one back on top of it destroys the newer one — the exact
    /// opposite of what Restore is for.
    @Test func theNewerFileAtTheSamePathIsUntouched() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let path = "Downloads/report.pdf"
        let original = try ground.file(path, "the old one")
        let record = try #require(Quarantine.quarantine(
            [.init(original, section: .storage, reason: "proof")], home: ground.home).moved.first)

        // The person makes a new one, at the same path, with different everything.
        let newer = try ground.file(path, "the new one, which took all afternoon")
        try ground.setMode(0o600, on: newer)
        try ground.setExtendedAttribute("studio.stonemesa.marker", to: Data([1, 2, 3]), on: newer)
        let newerFacts = try #require(FileFacts.take(of: newer))

        let report = Quarantine.restore([record], home: ground.home)

        #expect(report.restored.isEmpty)
        #expect(report.stuck.count == 1)
        let refusal = try #require(report.stuck.first?.refusal)
        #expect(refusal == .somethingIsAlreadyThere(path: original.path(percentEncoded: false)))
        #expect(refusal.sentence.contains("will not write over it"))

        // ⭐ Not one byte of the newer file changed.
        #expect(FileFacts.take(of: newer)?.differences(from: newerFacts).isEmpty == true)
        #expect(ground.contents(of: newer) == "the new one, which took all afternoon")

        // And the old one is still safely in quarantine, still recorded, still restorable later.
        #expect(ground.exists(record.quarantinedURL))
        #expect(ground.contents(of: record.quarantinedURL) == "the old one")
        #expect(Quarantine.records(home: ground.home).map(\.id) == [record.id],
                "the record was dropped for a restore that never happened")
    }

    /// The same refusal when what is in the way is not a file at all. A folder, or a broken
    /// shortcut, occupies the name just as effectively.
    @Test func aFolderInTheWayIsAlsoARefusal() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/thing", "a file")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "proof")], home: ground.home).moved.first)

        try ground.folder("Downloads/thing")
        try ground.file("Downloads/thing/inside.txt", "somebody's work")

        let report = Quarantine.restore([record], home: ground.home)
        #expect(report.stuck.count == 1)
        #expect(ground.contents(of: try ground.inside("Downloads/thing/inside.txt"))
                    == "somebody's work")
        #expect(ground.exists(record.quarantinedURL))
    }

    /// If what is in the store is no longer the file Wellkept put there, it is left alone. The
    /// check is the inode and the volume, not the name — a name is not an identity here.
    @Test func somethingSubstitutedInTheStoreIsNotPutBack() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/Old Installer.dmg", "the real one")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "proof")], home: ground.home).moved.first)

        // Something replaces the held file with a different one under the same name.
        try FileManager.default.removeItem(at: record.quarantinedURL)
        try Data("not the same file at all".utf8).write(to: record.quarantinedURL)

        let report = Quarantine.restore([record], home: ground.home)
        #expect(report.stuck.first?.refusal == .notTheSameFile)
        #expect(!ground.exists(file), "the impostor was put into the person's Downloads folder")
        #expect(ground.contents(of: record.quarantinedURL) == "not the same file at all",
                "the impostor was moved or removed rather than left alone")
    }

    /// A store on a disk that is not plugged in says so, by name, instead of failing with an error
    /// number a person cannot act on.
    @Test func anUnmountedStoreSaysPlugItBackIn() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/on the other disk.dmg", "bytes")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "proof")], home: ground.home).moved.first)

        // The disk goes away: its store root is no longer there.
        try FileManager.default.removeItem(at: record.storeURL)

        let report = Quarantine.restore([record], home: ground.home)
        let refusal = try #require(report.stuck.first?.refusal)
        #expect(refusal.sentence.contains("not connected"))
        #expect(refusal.sentence.contains("Plug"))
    }
}

// MARK: - ⭐ A broken shortcut is a file, and the app has to be able to see it

@Suite("A symbolic link that points at nothing is still a thing on the disk")
struct DanglingLinkTests {

    /// ⚠️ **The reading everything here turns on.** `FileManager.fileExists` follows the link and
    /// answers about the target, so a link pointing at nothing reads as absent even while it is
    /// sitting right there. `lstat` answers about the link.
    ///
    /// This is not a curiosity. Leftovers from uninstalled apps are full of broken links, so it is
    /// among the most ordinary things this app will ever be asked to set aside.
    @Test func theTwoWaysOfAskingDisagree() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let dangling = try ground.link("Library/Caches/broken", to: "/nowhere/at/all")

        #expect(!FileManager.default.fileExists(atPath: dangling.path(percentEncoded: false)),
                "FileManager no longer follows the link — the premise has changed")
        #expect(ground.exists(dangling), "lstat cannot see a link that is right there")
        #expect(Movable.read(dangling)?.isSymbolicLink == true)
    }

    /// ⭐ It goes into quarantine, it comes back, and it is still a link to the same nowhere.
    @Test func aBrokenShortcutMakesTheWholeRoundTrip() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let dangling = try ground.link("Library/Caches/SomeApp/broken", to: "/nowhere/at/all")
        let before = try #require(FileFacts.take(of: dangling))

        let record = try #require(Quarantine.quarantine(
            [.init(dangling, section: .apps, reason: "left over")], home: ground.home).moved.first)
        #expect(record.isSymbolicLink)
        #expect(ground.exists(record.quarantinedURL))

        let report = Quarantine.restore([record], home: ground.home)
        #expect(report.stuck.isEmpty, "a broken shortcut could not be put back: \(report.sentence)")
        #expect(ground.exists(dangling))
        #expect(FileFacts.take(of: dangling)?.differences(from: before).isEmpty == true)
    }

    /// And when it is emptied, it is really gone — rather than counted as removed and left behind
    /// for ever with nothing in the ledger pointing at it.
    @Test func emptyingTheQuarantineReallyRemovesIt() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let dangling = try ground.link("Library/Caches/SomeApp/broken", to: "/nowhere/at/all")
        let record = try #require(Quarantine.quarantine(
            [.init(dangling, section: .apps, reason: "left over")], home: ground.home).moved.first)

        let report = Quarantine.delete([record], expecting: 1, home: ground.home)
        #expect(report.deleted.count == 1)
        #expect(!ground.exists(record.quarantinedURL), "it was reported removed and is still there")
        #expect(!ground.exists(record.holderURL))
        #expect(Quarantine.records(home: ground.home).isEmpty)
    }

    /// The launch reconcile has to see it too, or an interrupted move of a broken link is reported
    /// as a file at neither place — the loudest message the app has, for something that is fine.
    @Test func reconcilingDoesNotCallItUnaccountedFor() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let dangling = try ground.link("Library/Caches/SomeApp/broken", to: "/nowhere/at/all")
        let verdict = Movable.check(dangling, reach: Reach.standard(home: ground.home))
        let file = try #require(verdict.reading)
        guard case .success(let store) = QuarantineStore.forItem(on: file.volume,
                                                                 home: ground.home) else {
            Issue.record("no store")
            return
        }
        let record = QuarantineRecord.planned(from: file, store: store,
                                              section: .apps, reason: "left over")

        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: ground.home)
        try FileManager.default.createDirectory(at: record.holderURL,
                                                withIntermediateDirectories: true)
        #expect(AtomicMove.perform(from: record.originalPath, to: record.quarantinedPath) == .moved)
        // ☠️ killed here.

        let report = Quarantine.reconcileOnOpening(home: ground.home)
        #expect(report.isQuiet, "a broken shortcut in the store was called unaccounted for")
        #expect(report.finished.count == 1)
        #expect(Quarantine.records(home: ground.home).count == 1)
        #expect(Quarantine.summary(home: ground.home).unaccountedFor == 0,
                "the summary cannot see a link that is right there in the store")
    }

    /// A broken shortcut squatting the original path is in the way like anything else, and it is
    /// named as such rather than reported as a mysterious failure.
    @Test func aBrokenShortcutInTheWayIsRecognisedAsSomethingBeingThere() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/thing.dmg", "the real bytes")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "proof")], home: ground.home).moved.first)

        try ground.link("Downloads/thing.dmg", to: "/nowhere/at/all")

        let report = Quarantine.restore([record], home: ground.home)
        #expect(report.stuck.count == 1)
        #expect(report.stuck.first?.refusal
                    == .somethingIsAlreadyThere(path: file.path(percentEncoded: false)))
        #expect(ground.exists(record.quarantinedURL), "the file was moved on top of the shortcut")
    }
}
