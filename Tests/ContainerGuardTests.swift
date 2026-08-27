// SPDX-License-Identifier: GPL-3.0-or-later
//
//  ContainerGuardTests.swift
//
//  ⚠️ **Wellkept must never be the cause of an unexplained privacy dialog.**
//
//  `~/Library/Containers` and `~/Library/Group Containers` hold other apps' sandboxed data, and
//  macOS gates them behind *"<app> would like to access data from other apps"* — which it raises on
//  the ATTEMPT, not on the failure. So a speculative read to discover whether we are allowed is
//  itself the harm: it puts a dialog on somebody's screen naming a process they did not start.
//
//  This happened twice on 2026-08-27 while the Apps section was being written, both times naming
//  *Xcode* because the code was running under the test harness, and the owner had to be told to
//  press Don't Allow. The fix is `LeftoverReader.Place.needsFullDiskAccess`: those places are
//  visited only when the grant is ALREADY held, and skipped untouched otherwise.
//
//  This test is what stops the fix being undone by a later file that means well. It is deliberately
//  a source scan rather than a behaviour test, because the failure it guards against is a dialog on
//  a person's screen — by the time a behaviour test could observe it, the harm has happened.
//  Same shape, and the same reason, as `ColorRuleGuardTests`.
import Testing
import Foundation

@Suite("Nothing reaches into another app's data without the grant")
struct ContainerGuardTests {

    /// Only this file may name those folders, and only inside the gate.
    static let permitted = "App/Apps/LeftoverReader.swift"

    static func swiftFiles() -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the repository
        var found: [String] = []
        for directory in ["App", "Tools", "Core/Sources"] {
            let base = root.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: base,
                                                              includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append(String(url.path.dropFirst(root.path.count + 1)))
            }
        }
        return found
    }

    @Test("The scanner reads the repository")
    func scannerWorks() {
        #expect(Self.swiftFiles().count > 20, "the source scan found almost nothing — it is looking in the wrong place")
    }

    @Test("No file but the gated reader names another app's container folders")
    func nobodyElseNamesThem() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []

        for relative in Self.swiftFiles() where relative != Self.permitted {
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // Prose in a comment is how the reason gets recorded; only code counts.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                if line.contains("\"Containers\"") || line.contains("Group Containers") {
                    offenders.append("\(relative):\(number + 1)")
                }
            }
        }

        #expect(offenders.isEmpty, """
            These reach into another app's sandboxed data: \(offenders.joined(separator: ", ")).
            macOS raises "would like to access data from other apps" on the attempt, so this puts a
            dialog on somebody's screen. Route it through LeftoverReader, which visits those places
            only when Full Disk Access is already granted.
            """)
    }

    @Test("The gated places are gated")
    func theGateExists() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = (try? String(contentsOf: root.appendingPathComponent(Self.permitted), encoding: .utf8)) ?? ""
        #expect(text.contains("needsFullDiskAccess"),
                "LeftoverReader lost its gate — the container walk is unguarded again")
        #expect(text.contains("survey(fullDiskAccess:"),
                "survey() no longer takes the grant, so it will find out by trying, which is the dialog")
    }
}
