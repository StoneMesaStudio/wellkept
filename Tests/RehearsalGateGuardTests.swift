// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  RehearsalGateGuardTests.swift
//  WellkeptTests
//
//  ⛔⛔ **The build fails if anything can copy somebody's files without asking the gate.**
//
//  `RehearsalGate.Pass` has a `fileprivate` initialiser, so the compiler already stops a copier
//  being *called* without one. This file guards the two things a compiler cannot see:
//
//  1. **A copier that never takes a `Pass` at all.** Nothing forces a new file to adopt the shape;
//     somebody can write `FileManager.default.copyItem(…)` and never mention the gate. So this
//     scans the repository's own Swift: **a file in `App/` or `Core/Sources/` that uses a copy
//     primitive must name `RehearsalGate.Pass`**, or be on a short list of files that legitimately
//     copy something other than a person's files, with the reason recorded here.
//  2. **The debug-only door being used outside a test.** `RehearsalGate.passForTesting` exists so
//     the engine can be exercised before the rehearsal makes it real. Called from the app it would
//     hand a real copier a real pass in a Debug build, which is precisely the thing the
//     condition forbids.
//
//  Same instrument, and the same reasoning, as `ContainerGuardTests`, `ColorRuleGuardTests` and
//  `StorageLawGuardTests`: **the harm here is somebody's files, and by the time a behaviour test
//  could observe it, it has already happened.**
//
//  ⚠️ Nothing here touches the disk except to read this repository's own text.

@Suite("Nothing copies a person's files without the gate")
struct RehearsalGateGuardTests {

    // MARK: ── The scanner ──────────────────────────────────────────────────────────────────────

    /// ⚠️ **`App/` and `Core/Sources/` only.** `Tools/` is test scaffolding and icon generation —
    /// it writes files by design, it never ships, and including it would mean a permitted list long
    /// enough that nobody reads it. A guard nobody reads is a guard that gets deleted.
    static let directories = ["App", "Core/Sources"]

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the repository
    }

    static func swiftFiles() -> [String] {
        let root = repositoryRoot
        var found: [String] = []
        for directory in directories {
            let base = root.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: base,
                                                              includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append(String(url.path.dropFirst(root.path.count + 1)))
            }
        }
        return found.sorted()
    }

    static func text(of relative: String) -> String {
        (try? String(contentsOf: repositoryRoot.appendingPathComponent(relative), encoding: .utf8)) ?? ""
    }

    /// Lines that are code rather than prose. A comment is how the reason gets recorded, and a
    /// guard that fires on its own explanation is useless.
    static func codeLines(of relative: String) -> [(number: Int, line: String)] {
        text(of: relative)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { (number: $0.offset + 1, line: String($0.element)) }
            .filter {
                let trimmed = $0.line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///") && !trimmed.hasPrefix("*")
            }
    }

    @Test("The source scan is looking at the right place")
    func theScannerWorks() {
        let files = Self.swiftFiles()
        #expect(files.count > 20, "the source scan found almost nothing — it is looking in the wrong place")
        #expect(files.contains("Core/Sources/WellkeptCore/RehearsalGate.swift"))
    }

    // MARK: ── ⭐ 1. Every copy entry point asks the gate ─────────────────────────────────────────

    /// The primitives that copy a file's contents from one place to another.
    static let copyPrimitives = ["copyfile(", "copyItem(", "copyItemAtPath"]

    /// **Files permitted to copy without a pass, and why.**
    ///
    /// ⚠️ Every entry is a file that copies something that is **not a person's files**. Adding to
    /// this list is how the guard gets defeated, so an entry that does not carry its reason here
    /// does not belong.
    static let permittedCopiers: [String: String] = [
        // The quarantine ledger keeps a copy of itself before rewriting it, on the same volume,
        // in Wellkept's own folder. It is our bookkeeping, not the user's files, and it predates
        // this gate by two days.
        "App/Quarantine/Ledger.swift": "copies Wellkept's own ledger, on the same volume, as its crash safety net",
    ]

    @Test("⭐ Nothing copies a file without naming the gate")
    func everyCopierAsksTheGate() {
        var offenders: [String] = []

        for relative in Self.swiftFiles() {
            if Self.permittedCopiers[relative] != nil { continue }
            let body = Self.text(of: relative)
            let mentionsTheGate = body.contains("RehearsalGate.Pass") || body.contains("RehearsalGate")

            for (number, line) in Self.codeLines(of: relative) {
                guard Self.copyPrimitives.contains(where: { line.contains($0) }) else { continue }
                if mentionsTheGate { continue }
                offenders.append("\(relative):\(number)")
            }
        }

        #expect(offenders.isEmpty, """
            These copy a file and never mention RehearsalGate: \(offenders.joined(separator: ", ")).

            A backup is proven by erasing a drive and restoring from it, and that has not been done
            with this code. Every entry point that writes to a drive takes a RehearsalGate.Pass, which
            only RehearsalGate.permissionToWrite(to:) can produce. If this file copies something that
            is not a person's files, add it to permittedCopiers WITH the reason.
            """)
    }

    /// ⚠️ The other half: a file under `App/Backup/` that writes **anything** has to name the gate,
    /// not only one that uses a copy primitive. A backup engine that creates its destination folder
    /// before checking whether it is allowed to exist has already started.
    @Test("Everything in the backup engine names the gate")
    func theBackupEngineIsGated() {
        let writePrimitives = ["createDirectory", "removeItem(", "moveItem(", ".write(to:",
                               "createFile(", "FileHandle(forWriting", "open(", "rename("]
        var offenders: [String] = []

        for relative in Self.swiftFiles() where relative.hasPrefix("App/Backup/") {
            let body = Self.text(of: relative)
            guard !body.contains("RehearsalGate") else { continue }
            for (number, line) in Self.codeLines(of: relative)
            where writePrimitives.contains(where: { line.contains($0) }) {
                offenders.append("\(relative):\(number)")
            }
        }

        #expect(offenders.isEmpty, """
            These write to the disk from inside the backup engine without naming RehearsalGate:
            \(offenders.joined(separator: ", ")). Ask the gate first, and take a Pass.
            """)
    }

    // MARK: ── ⚠️ 2. The debug door stays in the tests ───────────────────────────────────────────

    @Test("⚠️ Nothing outside a test reaches for the testing pass")
    func theTestingDoorIsNotUsedByTheApp() {
        var offenders: [String] = []
        let definedIn = "Core/Sources/WellkeptCore/RehearsalGate.swift"

        for relative in Self.swiftFiles() where relative != definedIn {
            for (number, line) in Self.codeLines(of: relative) where line.contains("passForTesting") {
                offenders.append("\(relative):\(number)")
            }
        }

        #expect(offenders.isEmpty, """
            These use RehearsalGate.passForTesting outside a test bundle: \(offenders.joined(separator: ", ")).
            In a Debug build that hands a real copier a real pass, which is exactly what the gate
            exists to prevent. Call RehearsalGate.permissionToWrite(to:) instead and handle the
            refusal.
            """)
    }

    @Test("⭐ The Pass initialiser is still the only door")
    func thePassCannotBeForged() {
        let gate = Self.text(of: "Core/Sources/WellkeptCore/RehearsalGate.swift")
        #expect(gate.contains("fileprivate init(rehearsal: Rehearsal?, grantedFor: String, isForTestingOnly: Bool)"),
                "RehearsalGate.Pass lost its fileprivate initialiser — anything in the app can now forge permission to write to a drive")
        #expect(gate.contains("public static let performed: Rehearsal? = nil")
                || RehearsalGate.hasBeenRehearsed,
                "the rehearsal constant was edited into something that is neither nil nor a properly recorded rehearsal")
        #expect(gate.contains("#if DEBUG"),
                "passForTesting is no longer compiled out of a release build")
    }

    // MARK: ── The promise this section may not make ─────────────────────────────────────────────

    /// ⚠️ **Migration Assistant accepting a data-only volume is unverified**, with Apple's own
    /// string arguing against it, and a whole-Mac copy is impossible unprivileged. The promise is
    /// "all your files" and it is never "rebuild your Mac".
    @Test("Nothing promises to rebuild somebody's Mac")
    func thePromiseIsNotMade() {
        var offenders: [String] = []
        for relative in Self.swiftFiles() {
            for (number, line) in Self.codeLines(of: relative) {
                guard line.lowercased().contains("rebuild your mac") else { continue }
                // The one permitted mention is the constant that records the forbidden phrase so
                // this test can look for it.
                if line.contains("promiseWeDoNotMake") { continue }
                offenders.append("\(relative):\(number)")
            }
        }
        #expect(offenders.isEmpty, """
            These promise to rebuild the Mac: \(offenders.joined(separator: ", ")).
            Migration Assistant accepting a data-only volume is unverified, and a whole-Mac backup is
            impossible without root. The promise is "all your files".
            """)
    }

    /// ⛔ **"Time Machine copies serially" is out of date** — macOS 26's backupd is parallel. It was
    /// in the plan, it is wrong, and a reviewer reading it would be right to stop reading.
    @Test("The stale claim about Time Machine is nowhere in the app")
    func theSerialClaimIsGone() {
        var offenders: [String] = []
        for relative in Self.swiftFiles() {
            for (number, line) in Self.codeLines(of: relative)
            where line.lowercased().contains("copies serially") || line.lowercased().contains("copy serially") {
                offenders.append("\(relative):\(number)")
            }
        }
        #expect(offenders.isEmpty, "macOS 26's backupd is parallel: \(offenders.joined(separator: ", "))")
    }

    // MARK: ── The gate is visible, not just present ─────────────────────────────────────────────

    /// The condition was that the gate is **a shipped, visible thing**. A gate that refuses
    /// silently is a feature that looks broken.
    @Test("The refusal is a sentence a person can read")
    func theGateSaysSomethingOutLoud() {
        #expect(RehearsalGate.faceLine.count > 80, "the face line is too short to explain itself")
        #expect(RehearsalGate.helpParagraph.contains("a belief, not a backup"))
        #expect(BackupTopic.wellkeptBackup.needsRehearsal)
        #expect(RehearsalGate.detailPairs.isEmpty == false,
                "Options shows nothing about the gate, so a person cannot see which side of it this build is on")
    }
}
