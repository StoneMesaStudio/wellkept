// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  ChangesGuardTests.swift
//  WellkeptTests — links WellkeptCore only
//
//  ⭐ **The four promises of the Changes section that no test of behaviour can protect, because
//  breaking them takes one well-meaning line and the build still passes.**
//
//  `ChangesTests` checks what the vocabulary does. `ChangesEngineTests` checks what the three app
//  files do. Neither can catch the day somebody adds `defaults write` to a button, or writes "the
//  update changed it" into a row, because both of those are *working code* that does exactly what
//  it says.
//
//  1. ⛔ **Wellkept writes no setting, ever.** Decided 2026-08-28, with no exception — not even the
//     default browser, which is the one write macOS actually permits. There is no fifth verb;
//     "Open Settings" is a destination. So the scan below fails the build on any preference-writing
//     API, any privileged tool, and any path into the system that is not one of the three this
//     section reads.
//  2. ⛔ **"Changed during", never "the update changed it."** The evidence is that two things
//     happened in the same window. It is not evidence that one caused the other, and the whole
//     value of the strongest sentence in this section is that it says so.
//  3. ⛔ **Values are compared, never dates.** Three quarters of the preference files on this Mac
//     were rewritten inside a day by daemons that changed nothing.
//  4. ⛔ **A description cannot be written with fewer than three parts.** The type refuses; this
//     proves the type still refuses.
//
//  The machinery is `OneMoveOnlyGuardTests`': read the shipping source, drop the comment lines,
//  look at what is left. Crude on purpose. A guard that over-reports gets read; one that
//  under-reports gets trusted wrongly.

// MARK: - Reading the section's own source

/// Every file that makes up the Changes section, as text.
///
/// ⚠️ **The list is discovered, not typed.** `App/Sections/Changes*` is a glob because the face is
/// built after this file and its filenames are not known here — a guard that names the files it
/// checks is a guard that stops covering the section the moment somebody adds one.
enum ChangesSource {

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the repository
    }

    struct File: Sendable {
        /// Repository-relative, so a failure names something a person can open.
        let path: String
        let text: String
    }

    /// The whole section: the vocabulary, the three engine files, and the face.
    static func files() -> [File] {
        var found: [File] = []
        let root = repositoryRoot

        func take(_ url: URL) {
            guard url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            found.append(File(path: String(url.path.dropFirst(root.path.count + 1)), text: text))
        }

        take(root.appendingPathComponent("Core/Sources/WellkeptCore/Changes.swift"))

        for folder in ["App/Changes", "App/Sections/Changes"] {
            let base = root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(at: base,
                                                              includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in walker { take(url) }
        }

        // The face itself, wherever it currently lives — a single file today, a folder later.
        let sections = root.appendingPathComponent("App/Sections")
        if let walker = FileManager.default.enumerator(at: sections,
                                                       includingPropertiesForKeys: nil) {
            for case let url as URL in walker
            where url.lastPathComponent.hasPrefix("Changes") {
                take(url)
            }
        }

        // A file can be reached by two of the passes above. Repository paths are unique keys.
        return Array(Dictionary(found.map { ($0.path, $0) },
                                uniquingKeysWith: { first, _ in first }).values)
            .sorted { $0.path < $1.path }
    }

    /// Lines that are code rather than commentary.
    ///
    /// ⚠️ **Every warning in this section lives in a comment**, including the exact sentences the
    /// guards forbid — the file that bans "the update changed it" has to be able to say what it is
    /// banning. So a comment line is not evidence and is dropped before anything is looked for.
    static func codeLines(of file: File) -> [(number: Int, line: String)] {
        file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { ($0.offset + 1, String($0.element)) }
            .filter {
                let trimmed = $0.1.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*")
            }
    }

    /// Where a needle appears in real code, as `path:line`.
    static func mentions(_ needle: String, caseSensitive: Bool = true) -> [String] {
        files().flatMap { file in
            codeLines(of: file)
                .filter {
                    caseSensitive ? $0.line.contains(needle)
                                  : $0.line.lowercased().contains(needle.lowercased())
                }
                .map { "\(file.path):\($0.number)" }
        }
    }
}

// MARK: - ⛔ Nothing in this section writes anything to this Mac

/// ⭐ **Decided 2026-08-28: "Wellkept writes no setting, ever."**
///
/// The temptation is specific and it will arrive. Somebody looks at a row saying the firewall went
/// off, sees that macOS publishes a documented call to put it back, and adds a button. The measured
/// reason that is wrong is in `CHANGES-QUESTIONS.md`: **six of the seven things this section
/// reports cannot be written at any privilege**, and even where a write succeeds, Apple's own
/// documentation says a running app may overwrite it — Dock, Finder, Control Center and
/// loginwindow are always running. **A write that reports success and changes nothing is the worst
/// outcome available**, because the person believes it is fixed.
///
/// So the rule is not "write carefully". It is that the section contains no writing code at all,
/// and this is what makes that structural instead of remembered.
@Suite("The Changes section writes nothing to this Mac")
struct ChangesWritesNothingGuardTests {

    /// The APIs that change a preference, and the tools that change a machine.
    ///
    /// Split in two because they fail differently: an API call is a silent write, and a tool is a
    /// password dialog on somebody's screen. Both are banned; only the second has ever actually
    /// happened here, when `sfltool dumpbtm` put a system password box on the
    /// screen on 2026-08-27.
    static let writingAPIs = [
        "CFPreferencesSetValue", "CFPreferencesSetAppValue", "CFPreferencesSetMultiple",
        "CFPreferencesAppSynchronize", "CFPreferencesSynchronize",
        "SCPreferencesSetValue", "SCPreferencesCommitChanges",
        "setPersistentDomain", "removePersistentDomain", "removeSuite",
        "NSUserDefaultsController",
    ]

    static let writingTools = [
        "defaults write", "systemsetup", "spctl", "csrutil", "fdesetup", "socketfilterfw",
        "launchctl", "nvram", "sfltool", "osascript", "SMJobBless", "AuthorizationCreate",
        "AuthorizationExecuteWithPrivileges", "profiles install", "sudo",
    ]

    /// ⚠️ **A guard that finds no files passes vacuously.** The same assertion `ColorRuleGuardTests`
    /// opens with, and for the same reason: this file is the only thing standing between the
    /// section and a write, and it is worth one test to know it is looking at something.
    @Test("The scanner is reading the whole section")
    func theScannerReadsTheSection() {
        let files = ChangesSource.files()
        let named = files.map(\.path).joined(separator: ", ")
        #expect(files.count >= 5,
                "the scan found only \(files.count) files — it is pointed at the wrong folders: \(named)")
        #expect(files.contains { $0.path.hasSuffix("SnapshotStore.swift") })
        #expect(files.contains { $0.path.hasSuffix("Attribution.swift") })
        #expect(files.contains { $0.path.hasSuffix("Diff.swift") })
        #expect(files.contains { $0.path.hasSuffix("WellkeptCore/Changes.swift") })
        // Whatever the face is called, something under App/Sections answers to "Changes".
        #expect(files.contains { $0.path.hasPrefix("App/Sections/Changes") },
                "the section's face is not in the scan, so nothing checks what it says")

        // The positive control: the scanner can find a string that is genuinely there.
        #expect(!ChangesSource.mentions("CFPreferencesCopyValue").isEmpty,
                "the scanner cannot find a call it is standing next to — it is reading nothing")
    }

    /// ⛔ Not one preference-writing call, anywhere in the section.
    @Test("No preference is ever written")
    func nothingWritesAPreference() {
        for api in Self.writingAPIs {
            let found = ChangesSource.mentions(api)
            #expect(found.isEmpty, "\(api) writes a setting, and this section never writes: \(found)")
        }
    }

    /// ⛔ And no privileged tool is run. Every one of these either changes the Mac or puts an
    /// authorization dialog on the screen, and this app is banned from both.
    @Test("No tool that changes the Mac is ever run")
    func nothingRunsAPrivilegedTool() {
        for tool in Self.writingTools {
            let found = ChangesSource.mentions(tool, caseSensitive: false)
            #expect(found.isEmpty, "\(tool) changes this Mac or asks for a password: \(found)")
        }
    }

    /// ⚠️ **`UserDefaults` is not banned outright — mutating it is.** The face may perfectly well
    /// read a preference of Wellkept's own. What it may not do is set one from this section, and a
    /// bare grep for the type would forbid the reading too.
    @Test("Nothing in the section sets a default")
    func nothingSetsADefault() {
        let setters = ["defaults.set(", "defaults.setValue(", "defaults.removeObject(",
                       "UserDefaults.standard.set(", "UserDefaults.standard.setValue(",
                       "UserDefaults.standard.removeObject("]
        for setter in setters {
            let found = ChangesSource.mentions(setter)
            #expect(found.isEmpty, "\(setter) writes a preference from the Changes section: \(found)")
        }
    }

    /// ⭐ **Every path into the system, named.**
    ///
    /// The section reads three things that do not belong to Wellkept: the install record, the
    /// shutdown marker, and `last`. Anything else is a new reach into somebody's Mac, and it should
    /// cost the person adding it one line in this test rather than nothing at all.
    ///
    /// This is also the guard that catches the write that arrives disguised as a read — a path to
    /// `/Library/Preferences` or `/var/db` handed to a `FileHandle` is not distinguishable from a
    /// read by any of the scans above, and it is distinguishable here.
    @Test("The section reaches into exactly three places outside Wellkept's own files")
    func everySystemPathIsNamed() {
        let allowed: Set<String> = [
            "/Library/Receipts/InstallHistory.plist",
            "/private/var/log/shutdown_monitor.log",
            "/usr/bin/last",
        ]

        var found = Set<String>()
        for file in ChangesSource.files() {
            for (_, line) in ChangesSource.codeLines(of: file) {
                // Absolute-path string literals: `URL(filePath: "/…")`, `"/usr/bin/…"`.
                var rest = Substring(line)
                while let open = rest.firstIndex(of: "\"") {
                    let after = rest.index(after: open)
                    guard let close = rest[after...].firstIndex(of: "\"") else { break }
                    let literal = String(rest[after..<close])
                    // A colon means a `PATH` list rather than a path — `Attribution.run` replaces
                    // the child's environment instead of inheriting one, and the value it sets is
                    // four directories, not a file it opens.
                    if literal.hasPrefix("/"), !literal.contains(":") { found.insert(literal) }
                    rest = rest[rest.index(after: close)...]
                }
            }
        }

        let strays = found.subtracting(allowed).sorted()
        let lost = allowed.subtracting(found).sorted()
        #expect(strays.isEmpty,
                "the section reaches somewhere new: \(strays). Add it here deliberately, or take it out.")
        #expect(lost.isEmpty, "a source this section is built on is no longer read: \(lost)")
    }

    /// ⚠️ **One subprocess, and it prints boot times.** `Attribution.run` is the only place in the
    /// section that starts a process; a second one is how a section that reads quietly turns into a
    /// section that shells out.
    @Test("Only one thing in the section starts a process")
    func onlyOneSubprocessExists() {
        let processes = ChangesSource.mentions("Process()")
        #expect(processes.count == 1, "more than one subprocess in the section: \(processes)")
        #expect(processes.first?.hasPrefix("App/Changes/Attribution.swift:") == true,
                "a subprocess appeared outside Attribution: \(processes)")
    }

    /// ⚠️ **Wellkept writes exactly one file here — its own record — and only from one place.**
    ///
    /// `SnapshotStore` writes `Snapshots.jsonl`, and writes the two files somebody asked for when
    /// they chose "save it to a folder I pick" on uninstall. Nothing else in the section touches
    /// the disk with a pen.
    @Test("The only file the section writes is Wellkept's own record")
    func onlyTheRecordIsWritten() {
        for needle in ["write(to:", "FileHandle(forWritingTo", "createFile(atPath"] {
            let writers = Set(ChangesSource.mentions(needle).map {
                $0.split(separator: ":").first.map(String.init) ?? $0
            })
            #expect(writers.isSubset(of: ["App/Changes/SnapshotStore.swift"]),
                    "something outside the snapshot store writes to disk: \(writers.sorted())")
        }
    }
}

// MARK: - ⛔ Changed during, never the update changed it

/// ⭐ **The strongest sentence this section has, and the half of it that is the whole point.**
///
/// *"This changed while your Mac was off for the macOS 26.6.2 update — it was off for four minutes
/// and 52 seconds."*
///
/// It reports a coincidence in time, as a coincidence. Ten of eleven updates on this Mac landed
/// within two minutes of a recorded boot, so the coincidence is real and worth saying; **it is
/// still not evidence that the update did it**, and one edit turning "while" into "because" would
/// convert the most careful sentence in the app into a claim nothing can support.
@Suite("Nothing in the section says the update changed it")
struct ChangesWordingGuardTests {

    /// Phrasings that assert an author or a cause rather than a coincidence.
    ///
    /// ⚠️ Deliberately not "changed it" on its own — `Cause.unknown` says *"we cannot tell what
    /// changed it"*, which is the section admitting it does not know, and is exactly the sentence
    /// this guard exists to protect.
    static let forbidden = [
        "the update changed", "update changed it", "changed by the", "was changed by",
        "caused", "because of the update", "responsible for", "to blame", "the culprit",
        "did this", "made this change", "is what changed",
    ]

    @Test("No sentence in the section claims the update did it")
    func nothingClaimsTheUpdateDidIt() {
        for phrase in Self.forbidden {
            let found = ChangesSource.mentions(phrase, caseSensitive: false)
            #expect(found.isEmpty,
                    "\"\(phrase)\" asserts a cause the evidence does not carry: \(found)")
        }
    }

    /// ⚠️ The positive half. A guard that only bans wording passes on the day somebody deletes the
    /// sentence entirely, which loses the thing it was protecting just as thoroughly.
    @Test("The coincidence is still stated as a coincidence")
    func theSentenceStillSaysWhile() {
        let strong = MacOSUpdate(version: "26.6.2",
                                 installedAt: Date(timeIntervalSince1970: 1_787_623_732),
                                 outage: Outage(wentDown: Date(timeIntervalSince1970: 1_787_623_440),
                                                cameBack: Date(timeIntervalSince1970: 1_787_623_732),
                                                precision: .toTheSecond))
        #expect(strong.sentence.hasPrefix("this changed while your Mac was off for the macOS"))
        // Small numbers are spelled out; 52 falls back to digits rather than inventing English for
        // it, which is the same rule `Outage` applies everywhere.
        #expect(strong.sentence.contains("four minutes and 52 seconds"))

        let weak = MacOSUpdate(version: "26.6.2", installedAt: Date(), outage: nil)
        #expect(weak.sentence == "this changed in the same period as the macOS 26.6.2 update")

        // Neither wording asserts an actor, in any grammatical disguise.
        for sentence in [strong.sentence, weak.sentence] {
            let lowered = sentence.lowercased()
            #expect(!lowered.contains("caused"))
            #expect(!lowered.contains("by the update"))
            #expect(!lowered.contains("the update set"))
            #expect(!lowered.contains("the update turned"))
        }
    }

    /// Every clause the section can print for a cause, listed. A fifth would fail
    /// `ChangesCauseGuardTests`; a **reworded** one would not, and the wording is the promise.
    @Test("The four things the section can say about why")
    func theFourClausesAreWhatTheyWere() {
        let update = MacOSUpdate(version: "26.6.2", installedAt: Date(), outage: nil)
        #expect(Cause.duringMacOSUpdate(update).clause
                == "this changed in the same period as the macOS 26.6.2 update")
        #expect(Cause.whileYouWereUsingTheMac.clause == "this changed while the Mac was in use")
        #expect(Cause.setByAnOrganisation.clause == "an organisation's profile sets this")
        #expect(Cause.unknown.clause == "we cannot tell what changed it")
    }
}

// MARK: - ⛔ Values, never dates

/// ⭐ **Measured 2026-08-28: three quarters of the preference files on this Mac had been rewritten
/// inside a day, by daemons, without changing a single value.**
///
/// A section built on modification dates would therefore report a settled Mac as churning every
/// time it was opened — and, worse, would look right while doing it, because *something did happen
/// to those files*. `ChangesRecordTests.aFileRewrittenWithTheSameContentsIsNoChange` proves the
/// behaviour on real files; this proves there is no timestamp comparison anywhere to regress to.
@Suite("Nothing in the section compares a file's date")
struct ChangesComparesValuesGuardTests {

    /// ⚠️ **One exemption, and it is not a comparison.** `Attribution.lastShutdown` reads the
    /// modification time of `shutdown_monitor.log`, where the timestamp **is** the event — the file
    /// is written as the machine goes down. It sharpens a shutdown instant that `last` already
    /// reported to the minute; it never establishes that a shutdown happened.
    @Test("The only timestamp the section reads is the one that is itself the event")
    func onlyTheShutdownMarkerIsATimestamp() {
        for needle in [".modificationDate", "contentModificationDateKey", ".creationDate",
                       "creationDateKey"] {
            let found = ChangesSource.mentions(needle)
            let strays = found.filter { !$0.hasPrefix("App/Changes/Attribution.swift:") }
            #expect(strays.isEmpty,
                    "\(needle) is being read outside the one documented exemption: \(strays)")
        }

        let exemption = ChangesSource.mentions(".modificationDate")
        #expect(exemption.count == 1,
                "the shutdown marker's timestamp is read from more than one place: \(exemption)")
    }
}

// MARK: - ⛔ A description has three parts or it does not exist

/// ⭐ **Decided 2026-08-28: "Let's show him up and do it better."**
///
/// Better was defined concretely, against prior art that is 787 one-line descriptions with 383 of
/// them flagged AI-generated: every description says **what the setting does**, **what turning it
/// off actually costs you**, and **why it might have changed**.
///
/// `ChangesDescriptionTests` proves the catalogue fills all three. This proves the *type* refuses
/// anything less — which is the part that matters in eight months, when somebody adds the
/// thirty-fifth entry at four in the afternoon.
@Suite("A description cannot be written with fewer than three parts")
struct ChangesDescriptionShapeGuardTests {

    /// The initialiser's three parameters carry **no default values**, so `Description(does:)` is
    /// not a thing that compiles. A default of `""` added for convenience would silently reopen the
    /// one-line description, and `isComplete` would then be the only thing standing in the way —
    /// a check somebody can forget to run, rather than a check the compiler runs for them.
    @Test("The three parts have no defaults, so a one-line description does not compile")
    func theInitialiserHasNoDefaults() {
        let text = ChangesSource.files()
            .first { $0.path.hasSuffix("WellkeptCore/Changes.swift") }?.text ?? ""

        guard let start = text.range(of: "public init(does: String,") else {
            Issue.record("the Description initialiser was not found — this guard is guarding nothing")
            return
        }
        guard let end = text.range(of: ")", range: start.upperBound..<text.endIndex) else { return }
        let parameters = String(text[start.lowerBound..<end.upperBound])

        #expect(!parameters.contains("="),
                "a description parameter gained a default value, so a one-part description now compiles: \(parameters)")
        #expect(parameters.contains("costOfTurningItOff: String"))
        #expect(parameters.contains("whyItMightHaveChanged: String"))
    }

    /// The three stored properties are `let` and non-optional. An optional would let `nil` stand in
    /// for the missing sentence, which is the same hole in a different shape.
    @Test("None of the three parts is optional")
    func noPartIsOptional() {
        let text = ChangesSource.files()
            .first { $0.path.hasSuffix("WellkeptCore/Changes.swift") }?.text ?? ""
        for property in ["public let does: String", "public let costOfTurningItOff: String",
                         "public let whyItMightHaveChanged: String"] {
            #expect(text.contains(property),
                    "\(property) is not declared as a required string any more")
        }
    }

    /// And the completeness check still rejects the three things that actually go wrong: an empty
    /// field, a stub, and the same sentence typed three times.
    @Test("The completeness check still refuses the three real failures")
    func theCheckStillRefusesWhatGoesWrong() {
        let long = "A sentence long enough to clear the floor this check sets."

        #expect(!Watched.Description(does: "", costOfTurningItOff: long,
                                     whyItMightHaveChanged: long).isComplete)
        #expect(!Watched.Description(does: long, costOfTurningItOff: "N/A",
                                     whyItMightHaveChanged: long).isComplete)
        #expect(!Watched.Description(does: long, costOfTurningItOff: long,
                                     whyItMightHaveChanged: long).isComplete)
        // A sentence that does not end in a full stop is a fragment, and a fragment is a note to
        // self rather than something to put in front of somebody.
        #expect(!Watched.Description(does: String(long.dropLast()), costOfTurningItOff: long + " x",
                                     whyItMightHaveChanged: long + " y").isComplete)
    }
}
