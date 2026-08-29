// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  BackupEntryPointGuardTests.swift
//  WellkeptTests
//
//  ⛔⛔ **The gate, checked one function at a time.**
//
//  ## Why this file exists when two guards already do
//
//  `RehearsalGateGuardTests` asks whether a **file** that copies names `RehearsalGate`.
//  `BackupEngineGuardTests` asks whether a **file** in the engine that writes names it. Both are
//  right and both have the same hole, and it is the hole somebody falls into a year from now:
//
//  ```swift
//  // CopyOne.swift — a file that already names the gate on line 250
//  static func quickCopy(_ item: SourceItem, to path: String) {   // ⛔ no Pass, and both guards pass
//      copyfile(item.path, path, nil, copyfile_flags_t(COPYFILE_ALL))
//  }
//  ```
//
//  A file-level guard cannot see that. So this one splits every Swift file under `App/Backup` at
//  its `func` declarations and asks the question of **each function**: it writes, so does it hold a
//  `RehearsalGate.Pass` in its own signature, or ask the gate in its own body? Nothing else counts.
//  A private helper is not exempt — `CopyOne.linkAgain` writes the second name of a hard link onto
//  somebody's drive, and it takes the token like everything else.
//
//  ## The other three things in here, and why each is a guard rather than a test
//
//  - **`fullDiskAccessHeld: true` is never written down.** The single fact that decides whether a
//    backup may be called complete is measured on the machine, every run. Typed as a literal it
//    becomes the silent lie this whole section exists to prevent: macOS hands over no mail, no
//    messages and no photos without the grant, and it reports **no error at all**.
//  - **The strongest word, outside the engine.** `BackupEngineGuardTests` reserves "verified" to
//    `Verification.swift`; this extends the same rule to the readers, the Core vocabulary and the
//    section's screens, which is where a sentence about a backup actually reaches a person.
//  - **The two claims this app may not make**, wherever they might be typed: rebuilding a Mac, and
//    a bootable backup. The first is unverified with Apple's own string arguing against it; the
//    second is dead and must never be proposed again.
//
//  ⚠️ Nothing here touches the disk except to read this repository's own text.

@Suite("⛔ Every function that writes holds the token")
struct BackupEntryPointGuardTests {

    // MARK: ── The scanner ──────────────────────────────────────────────────────────────────────

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the repository
    }

    static func swiftFiles(under directory: String) -> [(path: String, text: String)] {
        let root = repositoryRoot
        let base = root.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        else { return [] }
        var found: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            found.append((String(url.path.dropFirst(root.path.count + 1)), text))
        }
        return found.sorted { $0.0 < $1.0 }
    }

    static func text(of relative: String) -> String {
        (try? String(contentsOf: repositoryRoot.appendingPathComponent(relative), encoding: .utf8)) ?? ""
    }

    /// Lines that are code rather than commentary. The reason a thing is allowed is recorded in a
    /// comment, and a guard that fires on its own explanation is a guard somebody deletes.
    static func isProse(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("*")
    }

    /// One function: where it starts, its declaration, and everything down to the next one.
    struct Function {
        let file: String
        let line: Int
        let declaration: String
        let signature: String
        let body: String
    }

    /// Split a file at its `func` declarations.
    ///
    /// ⚠️ Crude on purpose, and the same instrument the other guards use: a real parser would be a
    /// dependency, and the failure mode here is over-reporting, which somebody reads and fixes. The
    /// failure mode of *no* guard is a copier nobody noticed.
    static func functions(in file: (path: String, text: String)) -> [Function] {
        let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let declaration = try! Regex(#"^\s*(?:@\w+\s+)*(?:public |private |fileprivate |internal |open )?(?:static |class |final )*func "#)
        var starts: [Int] = []
        for (index, line) in lines.enumerated() where (try? declaration.firstMatch(in: line)) != nil {
            starts.append(index)
        }
        guard !starts.isEmpty else { return [] }
        var out: [Function] = []
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : lines.count
            out.append(Function(file: file.path,
                                line: start + 1,
                                declaration: lines[start].trimmingCharacters(in: .whitespaces),
                                // The declaration can run over several lines before the brace.
                                signature: lines[start..<min(start + 10, end)].joined(separator: "\n"),
                                body: lines[start..<end].joined(separator: "\n")))
        }
        return out
    }

    // MARK: ── ⭐ 1. Every function that writes ──────────────────────────────────────────────────

    /// The calls that bring a file into existence, change its contents, or take it away.
    ///
    /// ⚠️ Deliberately **not** `setxattr`/`setattrlist`. Those write metadata onto a file the same
    /// pass-holding path created a line earlier, and `BackupEngineGuardTests` already covers them at
    /// file level. Listing them here would make every repair helper carry a token it cannot use for
    /// anything, and a guard that fires on harmless code gets an exemption list nobody reads.
    static let writePrimitives = [
        "copyfile(", "fcopyfile(", "clonefile(", "copyItem(",
        "createDirectory", "createFile(", ".write(to:", "write(toFile:", "FileHandle(forWriting",
        "renameatx_np", "AtomicMove.perform", "moveItem(",
        "link(", "symlink(", "removeItem(", "unlink(", "mkdir(", "rmdir(",
    ]

    /// **Files that write something which is not a person's files, and why.**
    ///
    /// ⚠️ Same discipline as `permittedCopiers`: this list is the way the guard gets defeated, so an
    /// entry without its reason does not belong in it.
    static let permittedWriters: [String: String] = [
        // Wellkept's own note to itself about what the background piece could see, in Wellkept's
        // own folder in Application Support. It exists precisely so a human can read it and decide
        // whether to record the proof the gate is waiting for — writing it is looking, not touching.
        "App/Backup/Agent/AgentRecord.swift":
            "writes Wellkept's own record of what the background piece could see, in Wellkept's own folder",

        // The one page that was actually printed, remembered in Wellkept's own folder so the row can
        // say whether the page on record still describes this Mac. ⛔ It holds no value from the
        // page — `RecoveryBlank` has nowhere to put one — so there is nothing of the person's in it.
        "App/Sections/Backup/RecoveryPlanStore.swift":
            "writes Wellkept's own record of which Recovery Plan was printed, in Wellkept's own folder",
    ]

    /// The folders the function-level rule covers: the engine, the readers, the background piece,
    /// and the section's own screens.
    static let backupDirectories = ["App/Backup", "App/Sections/Backup"]

    @Test("The scanner found the engine and can see inside a function")
    func theScannerWorks() {
        let files = Self.swiftFiles(under: "App/Backup")
        #expect(files.count >= 10, "the scan found \(files.count) files under App/Backup — wrong folder")
        let copier = files.first { $0.path.hasSuffix("CopyOne.swift") }
        #expect(copier != nil)
        let inside = Self.functions(in: copier!)
        #expect(inside.count >= 4, "the function splitter found \(inside.count) functions in the copier")
        #expect(inside.contains { $0.body.contains("copyfile(") },
                "the splitter did not find the one copy — every test below would pass by accident")
    }

    @Test("⭐ No function anywhere in the backup section writes without holding a Pass")
    func everyWritingFunctionHoldsTheToken() {
        var offenders: [String] = []

        for file in Self.backupDirectories.flatMap({ Self.swiftFiles(under: $0) }) {
            if Self.permittedWriters[file.path] != nil { continue }
            for function in Self.functions(in: file) {
                let writes = function.body
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                    .filter { !Self.isProse($0) }
                    .contains { line in Self.writePrimitives.contains { line.contains($0) } }
                guard writes else { continue }

                let holdsIt = function.signature.contains("RehearsalGate.Pass")
                            || function.signature.contains("permittedBy")
                let asksForIt = function.body.contains("RehearsalGate.permission")
                if holdsIt || asksForIt { continue }
                offenders.append("\(function.file):\(function.line) \(function.declaration)")
            }
        }

        #expect(offenders.isEmpty, """
            These functions write to a disk and neither take a RehearsalGate.Pass nor ask the gate:
            \(offenders.joined(separator: "\n")).

            The token is the enforcement. A function declared `func run(…, permittedBy pass:
            RehearsalGate.Pass)` cannot be called by anything that has not asked, because only
            RehearsalGate can make a Pass — that is a compile error rather than a convention. A
            private helper is not an exception: it writes to somebody's drive like everything else.
            If what it writes is not a person's files, put it in permittedWriters WITH the reason.
            """)
    }

    // MARK: ── ⭐ 2. The three doors, each asking for itself ─────────────────────────────────────

    /// The entry points a screen may call, and what each has to ask for.
    ///
    /// ⚠️ **The background piece asks a different question**, and it is the harder one: a scheduled
    /// backup that silently holds no mail is worse than a manual one, because nobody is watching
    /// when it runs and nobody is told what it contains.
    static let entryPoints: [(file: String, function: String, asks: String)] = [
        ("App/Backup/Engine/BackupRun.swift", "func start(", "RehearsalGate.permissionToWrite"),
        ("App/Backup/Engine/BackupRun.swift", "func startInTheBackground(",
         "RehearsalGate.permissionForTheBackgroundPiece"),
        ("App/Backup/Engine/RestoreEngine.swift", "func start(", "RehearsalGate.permissionToWrite"),
    ]

    @Test("⭐ Every door a screen can press asks the gate itself, and the background one asks harder")
    func everyEntryPointAsksTheGate() {
        for entry in Self.entryPoints {
            let file = (path: entry.file, text: Self.text(of: entry.file))
            guard let door = Self.functions(in: file).first(where: {
                $0.declaration.contains(entry.function)
            }) else {
                Issue.record("\(entry.file) no longer declares \(entry.function) — a documented entry point vanished")
                continue
            }
            #expect(door.body.contains(entry.asks), """
                \(entry.file) · \(entry.function) does not call \(entry.asks). Every top-level entry \
                point asks the gate for itself. Taking a Pass from a caller would push the question \
                onto whoever happens to call next.
                """)
        }
    }

    // MARK: ── ⭐ 3. The one fact nobody may type out ────────────────────────────────────────────

    /// ⚠️ **Without Full Disk Access a backup contains no mail, no messages, no photos, no contacts,
    /// no Safari data and no Trash — not partial, nothing — and macOS refuses silently.** So the one
    /// fact that decides whether a run may be called complete is read off the machine every time.
    /// **Files allowed to state the grant, and why.**
    ///
    /// ⚠️ Same discipline as `permittedWriters` and `permittedCopiers`: this list is the way the
    /// guard gets defeated, so an entry without its reason does not belong in it. There is exactly
    /// one, and it is the file whose entire purpose is that nothing in it was measured.
    static let permittedGrantAssertions: [String: String] = [
        // Demo mode is a picture of an invented Mac, and **every** fact in it is typed out — the
        // free space, the app versions, the backup dates. Nothing here is a run, nothing is copied,
        // and no completeness verdict rests on it. The value is a property of the imaginary machine
        // being drawn, in the same way its serial number is. `AppState.runBackupCheck` refuses to
        // run at all while demo mode is on, so no real reading can borrow it.
        "App/Shell/DemoData.swift":
            "invents a Mac; every fact in the file is typed out and none of it describes a run",
    ]

    @Test("⭐ Whether the grant was held is measured, never asserted")
    func theGrantIsNeverTypedOut() {
        var offenders: [String] = []
        for directory in ["App", "Core/Sources"] {
            for file in Self.swiftFiles(under: directory) {
                if Self.permittedGrantAssertions[file.path] != nil { continue }
                for (number, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated().map({ ($0.offset + 1, String($0.element)) })
                where !Self.isProse(line)
                   && (line.contains("fullDiskAccessHeld: true")
                       || line.contains("fullDiskAccessHeld = true")) {
                    offenders.append("\(file.path):\(number)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            These write down that Full Disk Access was held instead of measuring it: \
            \(offenders.joined(separator: ", ")). macOS hands over none of somebody's mail, messages \
            or photos without the grant and reports no error, so a backup made without it looks \
            finished and is not. The value comes from FullDiskAccess.isGranted, every run. If the \
            file invents a Mac rather than reading one, add it to permittedGrantAssertions WITH the \
            reason.
            """)
    }

    // MARK: ── ⭐ 4. The strongest word, outside the engine too ──────────────────────────────────

    /// Where a sentence about a backup can reach a person: the readers, the shared vocabulary and
    /// the section's own screens.
    static var backupFacingFiles: [(path: String, text: String)] {
        let engineException = "App/Backup/Engine/Verification.swift"
        var files = swiftFiles(under: "App/Backup").filter { $0.path != engineException }
        files += swiftFiles(under: "Core/Sources").filter {
            $0.path.hasSuffix("Backup.swift") || $0.path.hasSuffix("RecoveryPlan.swift")
                || $0.path.hasSuffix("RehearsalGate.swift")
        }
        files += swiftFiles(under: "App/Sections").filter { $0.path.contains("Backup") }
        return files
    }

    @Test("⭐ Nothing says the bytes were checked unless the bytes were read back")
    func theStrongestWordIsEarnedEverywhere() {
        var offenders: [String] = []
        for file in Self.backupFacingFiles {
            for (number, raw) in file.text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated().map({ ($0.offset + 1, String($0.element)) }) {
                guard !Self.isProse(raw) else { continue }
                // ⚠️ "unverified" is a different word and it is one this section is required to
                // say — Migration Assistant accepting a data-only volume is exactly that.
                let line = raw.replacingOccurrences(of: "unverified", with: "")
                              .replacingOccurrences(of: "Unverified", with: "")
                guard line.lowercased().contains("verified") else { continue }
                offenders.append("\(file.path):\(number)")
            }
        }
        #expect(offenders.isEmpty, """
            "verified" appears outside App/Backup/Engine/Verification.swift: \
            \(offenders.joined(separator: ", ")). It means every byte was read back off the drive \
            and hashed against the source. A copy that returned zero has not been verified — see \
            Backup.whyTheReturnCodeIsNotEvidence — and this is the most tempting overclaim in the \
            whole app.
            """)
        // And the level that earns it is still the one that reads the bytes.
        #expect(Self.text(of: "App/Backup/Engine/Verification.swift")
            .contains("var mayUseTheWordVerified: Bool { self == .readBack }"))
    }

    // MARK: ── ⛔ 5. The two claims this app may not make ────────────────────────────────────────

    /// ⛔ **"Rebuild your Mac" and "bootable", in any string, anywhere.**
    ///
    /// The first is unverified with Apple's own words against it — Migration Assistant's own string
    /// reads *"Volume does not contain an installation of macOS or OS X."* The second is dead: Apple
    /// removed the ability years ago, and a bootable copy that does not survive a macOS update is
    /// advice that fails at the moment it is needed.
    @Test("⛔ Neither claim appears anywhere in the app, in any string")
    func theTwoClaimsAreNowhere() {
        var offenders: [String] = []
        for directory in ["App", "Core/Sources"] {
            for file in Self.swiftFiles(under: directory) {
                for (number, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated().map({ ($0.offset + 1, String($0.element)) }) {
                    guard !Self.isProse(line) else { continue }
                    let lowered = line.lowercased()
                    // The one permitted mention is the constant that records the forbidden phrase
                    // so a test can look for it.
                    if line.contains("promiseWeDoNotMake") { continue }
                    if lowered.contains("rebuild your mac") || lowered.contains("bootable") {
                        offenders.append("\(file.path):\(number)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, """
            These make a claim this app is not allowed to make: \(offenders.joined(separator: ", ")). \
            The promise is "all your files" and never "rebuild your Mac", and a bootable backup is \
            dead — the Recovery Plan replaces it.
            """)
        // The vocabulary still records what the promise actually is, so the words exist somewhere.
        #expect(Backup.whatItPromises.contains("plain copy of your home folder"))
        #expect(Backup.promiseWeDoNotMake == "rebuild your Mac")
    }
}
