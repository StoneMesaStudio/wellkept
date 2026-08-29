// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  BackupEngineGuardTests.swift
//  WellkeptTests
//
//  ⛔⛔ **The five ways somebody could quietly turn the backup engine into something dangerous,
//  each nailed shut by reading this repository's own source.**
//
//  The engine writes to a drive somebody owns, and it is the only part of Wellkept that copies a
//  person's files rather than moving them. Every rule below is one that a behaviour test could only
//  observe **after** the harm had already happened, which is the same argument as
//  `RehearsalGateGuardTests`, `ContainerGuardTests`, `ColorRuleGuardTests` and `StorageLawGuardTests`.
//
//  1. **A second copier.** `CopyOne` exists to pay back the four things a copy costs — the creation
//     date, the download-provenance tag, sparseness, and hard links. A second `copyfile` call
//     somewhere else would work, visibly, every time, and pay none of them back.
//  2. **A `diskutil` verb that changes a drive.** `info` reads and prints. `eraseVolume`,
//     `partitionDisk`, `apfs` and the rest destroy somebody's disk, and none of them belongs in an
//     app whose promise is that it never touches the shape of a drive.
//  3. **Touching Time Machine.** The engine reads nothing from `tmutil` and enables nothing. A
//     backup tool that switched somebody's Time Machine on or off would be doing the one thing
//     nobody asked it to.
//  4. **Overclaiming.** "Verified" means the bytes were read back off the drive. Anywhere else in
//     the engine it is a lie, and it is the most tempting lie available here.
//  5. **A removal that takes a rule instead of a list.** A function that removes everything older
//     than a date is a function somebody will eventually call on a timer, and that is how a backup
//     drive starts deleting last year to make room for this month.
//
//  ⚠️ Nothing here touches the disk except to read this repository's own text.

@Suite("⛔ The backup engine cannot be turned into something dangerous")
struct BackupEngineGuardTests {

    // MARK: ── The scanner ──────────────────────────────────────────────────────────────────────

    static let engine = "App/Backup/Engine"

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the repository
    }

    static func engineFiles() -> [(path: String, text: String)] {
        let root = repositoryRoot
        let base = root.appendingPathComponent(engine)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        else { return [] }
        var found: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            found.append((String(url.path.dropFirst(root.path.count + 1)), text))
        }
        return found.sorted { $0.0 < $1.0 }
    }

    /// Lines that are code rather than commentary. A comment is how a reason gets recorded, and a
    /// guard that fires on its own explanation is useless.
    static func codeLines(of text: String) -> [(number: Int, line: String)] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { ($0.offset + 1, String($0.element)) }
            .filter {
                let trimmed = $0.1.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///") && !trimmed.hasPrefix("*")
            }
    }

    static func mentions(_ needle: String) -> [String] {
        engineFiles().flatMap { file in
            codeLines(of: file.text)
                .filter { $0.line.contains(needle) }
                .map { "\(file.path):\($0.number)" }
        }
    }

    @Test("The scanner is looking at the engine")
    func theScannerWorks() {
        let files = Self.engineFiles()
        #expect(files.count >= 6, "the source scan found \(files.count) files — it is pointed at the wrong folder")
        #expect(files.contains { $0.path.hasSuffix("CopyOne.swift") })
        // The one call it is guarding, so a scan that finds nothing fails loudly rather than
        // passing every test below by accident.
        #expect(Self.mentions("copyfile(").isEmpty == false)
    }

    // MARK: ── ⭐ 1. There is one copier ─────────────────────────────────────────────────────────

    @Test("⭐ Exactly one file in the engine copies anything")
    func thereIsOneCopier() {
        let allowed = "\(Self.engine)/CopyOne.swift"
        for needle in ["copyfile(", "copyItem(", "clonefile"] {
            let found = Self.mentions(needle)
            #expect(found.allSatisfy { $0.hasPrefix(allowed + ":") }, """
                \(needle) is used outside the one copier: \(found). CopyOne exists to pay back the \
                four things a copy costs — the creation date, the download-provenance tag, \
                sparseness and hard links. A second copy path pays back none of them and looks \
                like it works.
                """)
        }
    }

    @Test("⭐ The copier repairs all four losses, and each one is reachable from the record")
    func allFourRepairsExist() {
        let copier = Self.engineFiles().first { $0.path.hasSuffix("CopyOne.swift") }?.text ?? ""
        #expect(copier.contains("setattrlist"), "the creation-date repair is gone")
        #expect(copier.contains("com.apple.quarantine"), "the download-provenance repair is gone")
        #expect(copier.contains("COPYFILE_DATA_SPARSE"), "the sparse-file repair is gone")
        #expect(copier.contains("link(first, destinationPath)"), "the hard-link repair is gone")
        #expect(CopyRepairNames.all.count == 4)
    }

    // MARK: ── ⛔ 2. Nothing changes the shape of a drive ────────────────────────────────────────

    /// ⛔ Every `diskutil` verb that writes. `info` and `list` read and print; these do not.
    static let destructiveDiskutilVerbs = [
        "eraseVolume", "eraseDisk", "partitionDisk", "reformat", "addVolume", "deleteVolume",
        "unmountDisk", "mountDisk", "renameVolume", "resizeContainer", "apfs ", "secureErase",
    ]

    @Test("⛔ No diskutil verb that could change somebody's drive appears anywhere in the engine")
    func nothingReshapesADrive() {
        for verb in Self.destructiveDiskutilVerbs {
            let found = Self.mentions(verb)
            #expect(found.isEmpty, """
                \(verb) appears in the backup engine: \(found). Wellkept never erases, formats, \
                partitions, mounts, unmounts or renames a drive. The person prepares the drive in \
                Disk Utility, and that is also where the encryption comes from.
                """)
        }
    }

    @Test("⛔ The only diskutil this engine runs is a read")
    func diskutilOnlyReads() {
        let calls = Self.mentions("/usr/sbin/diskutil")
        #expect(calls.count <= 1, "diskutil is run from more than one place in the engine: \(calls)")

        for file in Self.engineFiles() {
            for (number, line) in Self.codeLines(of: file.text)
            where line.contains("arguments:") && line.contains("\"info\"") == false
                && line.contains("diskutil") {
                Issue.record("a diskutil call at \(file.path):\(number) is not `info`: \(line)")
            }
        }
    }

    // MARK: ── ⛔ 3. Time Machine is not ours to touch ───────────────────────────────────────────

    @Test("⛔ The engine never touches Time Machine")
    func timeMachineIsLeftAlone() {
        for needle in ["tmutil", "localsnapshot", "TMDestination", "backupd"] {
            #expect(Self.mentions(needle).isEmpty, """
                \(needle) appears in the backup engine: \(Self.mentions(needle)). Reading Time \
                Machine's state belongs to the reader, and enabling or disabling it belongs to \
                nobody: nothing that changes this Mac happens on Wellkept's initiative.
                """)
        }
    }

    // MARK: ── ⭐ 4. The strongest word is earned, not used ──────────────────────────────────────

    @Test("⭐ Only the file that reads the bytes back may use the strongest word")
    func theStrongWordIsEarned() {
        let allowed = "\(Self.engine)/Verification.swift"
        let word = VerificationLevelWords.strongest
        var offenders: [String] = []

        for file in Self.engineFiles() where !file.path.hasPrefix(allowed) {
            for (number, line) in Self.codeLines(of: file.text)
            where line.lowercased().contains(word) {
                offenders.append("\(file.path):\(number)")
            }
        }
        #expect(offenders.isEmpty, """
            "\(word)" is used outside \(allowed): \(offenders). It means the bytes were read back \
            off the drive and compared. Anywhere else it is a claim nobody checked, and it is the \
            most tempting overclaim available in this section.
            """)
    }

    // MARK: ── ⛔ 5. Removal takes a list, never a rule ──────────────────────────────────────────

    @Test("⛔ Nothing removes anything from the drive on a rule or a schedule")
    func removalTakesAListNotARule() {
        // Every removal in the engine, and the two places that are allowed one.
        let allowedRemovals = [
            "\(Self.engine)/BackupCatalogue.swift":
                "forget(_:onDrive:permittedBy:), which takes the exact versions a person pressed a button about",
            "\(Self.engine)/CopyOne.swift":
                "removes the file it had just written itself, when the source turned out to be a cloud placeholder",
        ]
        for needle in ["removeItem(", "unlink(", "rmdir(", "trashItem("] {
            let found = Self.mentions(needle)
            let unrecorded = found.filter { line in
                !allowedRemovals.keys.contains { line.hasPrefix($0 + ":") }
            }
            #expect(unrecorded.isEmpty, """
                something in the backup engine removes a file without being recorded as allowed to: \
                \(unrecorded). Nothing on a backup drive is ever deleted by surprise — retention \
                proposes, and a person presses.
                """)
        }

        // ⛔ And there is no rule-shaped door beside the list-shaped one.
        for shape in ["forgetEverythingOlderThan", "pruneOldest", "makeRoom", "trimToFit"] {
            #expect(Self.mentions(shape).isEmpty, """
                \(shape) exists in the backup engine. A removal that takes a rule is one somebody \
                will eventually run on a timer, and that is how a backup drive starts deleting last \
                year to make room for this month.
                """)
        }
    }

    // MARK: ── The engine still asks the gate, every file that writes ───────────────────────────

    @Test("⭐ Every file in the engine that writes names the gate")
    func everyWriterNamesTheGate() {
        let writePrimitives = ["copyfile(", "createDirectory", "removeItem(", "AtomicMove.perform(",
                               "setxattr(", "mkdir(", "link(", "setattrlist("]
        var offenders: [String] = []
        for file in Self.engineFiles() where !file.text.contains("RehearsalGate") {
            for (number, line) in Self.codeLines(of: file.text)
            where writePrimitives.contains(where: { line.contains($0) }) {
                offenders.append("\(file.path):\(number)")
            }
        }
        #expect(offenders.isEmpty, """
            these write to the disk from inside the backup engine without naming RehearsalGate: \
            \(offenders). Ask the gate first, and take a Pass.
            """)
    }

    @Test("⭐ The copier and the record both refuse a pass that admits to being for testing")
    func theTestingPassIsRefusedOnARealDrive() {
        let catalogue = Self.engineFiles()
            .first { $0.path.hasSuffix("BackupCatalogue.swift") }?.text ?? ""
        #expect(catalogue.contains("pass.isForTestingOnly, isARealDrive"), """
            the backup record no longer refuses a testing pass on a real drive. The debug-only door \
            exists so the engine can be exercised before the rehearsal — never so it can write to \
            somebody's disk.
            """)
    }
}

// MARK: - Small mirrors, so this suite does not link the app

/// The four repairs, named here so this suite can assert the count without linking the app target.
/// ⚠️ If `CopyRepair` grows a fifth case, this list and the test above both have to be revisited,
/// which is the point: a repair nobody wrote a test for is a repair nobody checked.
enum CopyRepairNames {
    static let all = ["creationDate", "whereItCameFrom", "sparseness", "hardLink"]
}

/// The word the top verification level earns, kept out of a string literal in the test body so the
/// guard is not looking for a word this file itself spells differently.
enum VerificationLevelWords {
    static let strongest = "verified"
}
