// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  NeverAScoreGuardTests.swift
//  WellkeptTests
//
//  ⛔ **"Never a score" is John's oldest instruction about this app, and this is what enforces it.**
//
//  From `SHELL-QUESTIONS.md` B6, and repeated in `CLAUDE.md` and `docs/CONTRACTS.md`: the clean
//  state is *"Everything looks fine"* and the date, and **never a score**. The reasoning is in
//  `Vocabulary.swift`: a number invites you to chase it, and a Mac with nothing wrong would then be
//  graded on how little it happened to have installed. Every commercial cleaner on the Mac ships a
//  number out of 100, and the number is the product.
//
//  ⚠️ **A source scan and not a behaviour test, deliberately** — the same reasoning as
//  `QuarantineWordsTests` and `ContainerGuardTests`. The failure this guards against is a number on
//  somebody's screen, and by the time a behaviour test could observe it the wrong thing has already
//  been drawn. It also catches the realistic version of the mistake, which is not a deliberate
//  betrayal: it is a later owner adding a perfectly ordinary "Health score: 84" to a new summary,
//  having never read the question John answered in 2026-08-26.
//
//  Only **string literals in shipping code** are scanned. Comments are where the reason gets
//  recorded — this file's own subject matter has to be sayable — and the test bundles are exempt
//  because half their job is asserting the words are absent.
//
//  ## What is NOT banned, and why the list is phrases rather than words
//
//  "Rated", "scored" and "graded" all appear legitimately and correctly today: a drive is *rated*
//  for so many terabytes written, a battery is *rated* for so many cycles, macOS *re-scores* its app
//  suggestions every few minutes, and the Help page explains that a Mac would end up *graded* on how
//  little was installed. Banning the words would fail the honest sentences along with the dishonest
//  ones, and the next owner would delete the test rather than the sentence. **What is banned is the
//  shape of a grade.**

@Suite("Nothing in Wellkept ever gives the Mac a score")
struct NeverAScoreGuardTests {

    /// The shapes a grade actually takes. Each is a phrase, not a word — see the header.
    static let banned = ["out of 100", "/100", "out of ten", "health score", "overall score",
                         "score of", "score:", "your score", "wellkept score"]

    /// Shipping code only. `Tools` holds the test bundles, which assert on these phrases by name.
    static let roots = ["App", "Core/Sources"]

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the repository
    }

    static func swiftFiles() -> [String] {
        let root = repoRoot
        var found: [String] = []
        for directory in roots {
            let base = root.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: base,
                                                              includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append(String(url.path.dropFirst(root.path.count + 1)))
            }
        }
        return found
    }

    /// Every double-quoted run on a line, with comment lines dropped first. The same deliberately
    /// crude scanner `QuarantineWordsTests` uses; it over-reports rather than under-reports.
    static func stringLiterals(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") { return [] }

        var literals: [String] = []
        var current = ""
        var inside = false
        var escaped = false
        for character in line {
            if escaped { if inside { current.append(character) }; escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "\"" {
                if inside { literals.append(current); current = "" }
                inside.toggle()
                continue
            }
            if inside { current.append(character) }
        }
        return literals
    }

    @Test("The scanner reads the repository")
    func theScannerReadsTheRepository() {
        #expect(Self.swiftFiles().count > 20,
                "the source scan found almost nothing — it is looking in the wrong place")
    }

    /// A green run means nothing unless the scanner can see the thing it is looking for.
    @Test("The scanner can tell a grade from a comment about grades")
    func theScannerCanSeeAGrade() {
        #expect(Self.stringLiterals(in: #"    let x = "Health score: 84""#) == ["Health score: 84"])
        #expect(Self.stringLiterals(in: #"    // never a "health score" anywhere"#).isEmpty)
    }

    @Test("No screen in the app grades this Mac")
    func nothingGradesTheMac() {
        let root = Self.repoRoot
        var offenders: [String] = []

        for relative in Self.swiftFiles() {
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative),
                                         encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                for literal in Self.stringLiterals(in: String(line)) {
                    let lowered = literal.lowercased()
                    for phrase in Self.banned where lowered.contains(phrase) {
                        offenders.append("\(relative):\(number + 1) — \"\(literal)\"")
                    }
                }
            }
        }

        #expect(offenders.isEmpty, """
            These grade the Mac: \(offenders.joined(separator: "; ")).
            John settled this on 2026-08-26 and it is not open: the clean state is "Everything looks
            fine" and the date. A number invites the user to chase it, and a Mac with nothing wrong
            would be graded on how little happened to be installed on it.
            """)
    }

    /// ⚠️ The ban has no exemption list. If a screen genuinely needs one of these phrases, that is a
    /// conversation with John, not an entry here.
    @Test("The ban has nowhere to grow an exception")
    func thereIsNowhereToAddAnException() {
        #expect(Self.banned.count == 9,
                "a phrase was added or removed — the reason has to be written down first")
    }

    /// ⛔ **The structural half.** There is nowhere in the shared vocabulary to put a score even if
    /// somebody wanted one: three statuses, three severities, and no rank on either that reaches a
    /// screen. A guard on the words alone would be defeated by a computed `Int`.
    @Test("The vocabulary has no numeric verdict to print")
    func theVocabularyHasNoGrade() {
        #expect(SectionStatus.allCases.count == 3)
        #expect(Severity.allCases.count == 3)
        // The status of a section is a word. If this ever became a number, every screen in the app
        // would have one to print.
        for status in SectionStatus.allCases {
            #expect(Int(status.label) == nil)
        }
    }
}
