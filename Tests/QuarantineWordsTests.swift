// SPDX-License-Identifier: GPL-3.0-or-later
//
//  QuarantineWordsTests.swift
//  WellkeptTests
//
//  ⭐ **The word "freed" is banned from anything a person reads, and this is what enforces it.**
//
//  Measured 2026-08-28: setting aside 391 MB across 100,000 files moved free space by **−8 KiB**. A
//  same-volume rename re-points an inode; the bytes never leave the disk. So quarantine frees
//  nothing, and a screen that says it did is a claim the person can disprove in About This Mac
//  within a minute — after which they are right to distrust everything else the app says.
//
//  ⚠️ **This is a source scan and not a behaviour test, on purpose**, and for the same reason as
//  `ContainerGuardTests`: the failure it guards against is a sentence on somebody's screen, and by
//  the time a behaviour test could observe it the wrong claim has already been made. It also catches
//  the realistic version of the mistake, which is not a deliberate lie — it is a later owner writing
//  a perfectly ordinary "Freed 4.2 GB" on a new screen, having never read the measurement.
//
//  Only **string literals in shipping code** are scanned. Comments are where the reason gets
//  recorded, so they are exempt; the test bundles are exempt too, since half their job is asserting
//  that these words are absent.
import Testing
import Foundation

@Suite("Nothing tells a person that space was freed")
struct QuarantineWordsTests {

    /// The words, and why each is banned.
    ///
    /// - `freed` — quarantine returns nothing, and after a real delete the figure is measured
    ///   rather than claimed. ("frees" is deliberately NOT on the list: Hardware says that quitting
    ///   an app *frees up memory*, which is both true and about something else entirely. A guard
    ///   that cries wolf gets deleted.)
    /// - `reclaim` — every commercial cleaner's headline, and the one this app is not.
    /// - `recovered space` / `space recovered` — the same claim wearing a different coat.
    static let banned = ["freed", "reclaim", "recovered space", "space recovered"]

    /// Shipping code only. `Tools` holds the test bundles, which assert on these words by name.
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

    /// Every double-quoted run on a line, with comment lines dropped first.
    ///
    /// Deliberately crude. It over-reports rather than under-reports — a doc comment that happens to
    /// contain quotes is exempt because the whole line is dropped, and an escaped quote inside a
    /// literal splits the literal, which at worst scans the same words twice.
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

    /// The scanner has to be able to see the thing it is looking for, or a green run means nothing.
    @Test("The scanner can tell a string from a comment")
    func theScannerCanTellAStringFromAComment() {
        #expect(Self.stringLiterals(in: #"    let x = "Freed 4.2 GB""#) == ["Freed 4.2 GB"])
        #expect(Self.stringLiterals(in: #"    // we never say "freed" anywhere"#).isEmpty)
        #expect(Self.stringLiterals(in: #"    /// "freed" is banned"#).isEmpty)
        #expect(Self.stringLiterals(in: #"let a = "one", b = "two""#) == ["one", "two"])
    }

    @Test("No sentence in the app claims space was freed or reclaimed")
    func nothingClaimsSpaceCameBackFromAQuarantine() {
        let root = Self.repoRoot
        var offenders: [String] = []

        for relative in Self.swiftFiles() {
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative),
                                         encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                for literal in Self.stringLiterals(in: String(line)) {
                    let lowered = literal.lowercased()
                    for word in Self.banned where lowered.contains(word) {
                        offenders.append("\(relative):\(number + 1) — \"\(literal)\"")
                    }
                }
            }
        }

        #expect(offenders.isEmpty, """
            These tell a person that space was freed: \(offenders.joined(separator: "; ")).
            Setting 391 MB aside moved free space by −8 KiB — a same-volume rename moves no bytes.
            After a real delete the figure is measured before and after and reported as what came
            back, because a local snapshot can hold the blocks. Say what was measured, or say
            nothing.
            """)
    }

    /// ⚠️ The banned list is not a style rule with an exception queue. If a screen genuinely needs
    /// one of these words, that is a conversation about the measurement, not an entry here.
    @Test("The ban has no exemption list to grow")
    func thereIsNowhereToAddAnException() {
        #expect(Self.banned.count == 4,
                "a word was added or removed — the reason has to be written down first")
    }
}
