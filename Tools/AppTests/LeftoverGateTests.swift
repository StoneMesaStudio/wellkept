// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  LeftoverGateTests.swift
//  ViewShots — Tools/AppTests
//
//  ⭐ **Two rules, both learned the expensive way on 2026-08-27, both invisible from the outside
//  once they break.**
//
//  1. **The survey never reaches into a gated place unless the grant was handed to it.** Not
//     "handles the failure gracefully" — never attempts it. macOS raises *"would like to access
//     data from other apps"* on the ATTEMPT, so a speculative read to discover whether we are
//     allowed IS the harm. It happened twice while this section was being written, both times
//     naming Xcode, because the code was running under the test harness.
//
//  2. **A folder with no app, no Spotlight entry and a name matching nothing is not a leftover.**
//     On this Mac that folder is a working PHP and Composer install.
//
//  ⚠️ **Nothing here calls `survey(fullDiskAccess: true)`, and nothing ever should.** Passing `true`
//  from a test would walk the gated place under whatever process is hosting the run — which is the
//  dialog. Every assertion below is about the `false` path and about the shape of the gate itself.
//  `LeftoverReaderTests` covers what the guards decide; this file covers where we are willing to
//  look in the first place.

// MARK: - ⭐ 1. The gate

@Suite("Leftovers — nowhere gated is touched without the grant")
struct LeftoverAccessGateTests {

    /// **Exactly one place needs the grant, and it is the sandbox folder.**
    ///
    /// Stated as an equality rather than a spot check, so adding a ninth place forces somebody to
    /// decide which side of the gate it is on instead of inheriting `false` by omission.
    @Test func onlyTheSandboxFolderIsGated() {
        let gated = LeftoverReader.Place.allCases.filter(\.needsFullDiskAccess)
        #expect(gated == [.containers], """
            The set of places behind Full Disk Access changed to \(gated.map(\.rawValue)). \
            Every place in that set is a folder macOS will put a privacy dialog on somebody's \
            screen for, so it is a decision, not a default.
            """)
    }

    /// **Without the grant, the gated place is skipped and said out loud.**
    ///
    /// `skipped` is what the row turns into "where we did not look". A survey that quietly returned
    /// an empty list here would produce a clean bill of health for a folder nobody opened.
    @Test func withoutTheGrantTheGatedPlaceIsNamedRatherThanRead() {
        let survey = LeftoverReader.survey(fullDiskAccess: false)
        #expect(survey.skipped == [.containers])
        #expect(survey.candidates != nil, """
            The Library could not be read at all without Full Disk Access. The section's claim that \
            Apps needs no permission rests on this.
            """)
    }

    /// ⚠️ **Not one candidate came out of a gated place.** The previous test says we announced the
    /// skip; this one says we actually did skip it. They are different failures: a gate that
    /// records the skip and walks anyway raises the dialog and looks correct in the report.
    @Test func nothingSurveyedWithoutTheGrantCameFromAGatedPlace() {
        let survey = LeftoverReader.survey(fullDiskAccess: false)
        let offenders = (survey.candidates ?? []).filter(\.place.needsFullDiskAccess)
        #expect(offenders.isEmpty, """
            \(offenders.count) entries came from a place that needs Full Disk Access, which was not \
            granted — so the walk happened anyway and the dialog has already been raised.
            """)
    }

    /// The gated place is only ever reachable through the parameter. There is no second door: the
    /// one caller that reads this Mac takes the grant from `FullDiskAccess` and passes it down, and
    /// `read(appsOnThisMac:)` is the only function that does so.
    @Test func theOnlyWayInIsTheParameter() {
        let source = LeftoverReaderSource.text
        #expect(source.contains("place.needsFullDiskAccess && !fullDiskAccess"), """
            The skip inside survey() is gone or has been rewritten. That single line is what stops \
            the walk; everything else in this file is a description of it.
            """)
        #expect(source.contains("survey(fullDiskAccess: FullDiskAccess.isGranted)"), """
            read() no longer takes the grant from FullDiskAccess before surveying — so the survey \
            is finding out by trying, which is the dialog.
            """)
    }

    /// **A place that proves an app was here is not the same as a place that needs permission.**
    /// Two independent columns that happen to overlap on one row today; collapsing them is how the
    /// gate gets widened by somebody tidying up.
    @Test func theTwoColumnsAreNotTheSameColumn() {
        let proves = Set(LeftoverReader.Place.allCases.filter(\.provesAnAppWasHere))
        let gated = Set(LeftoverReader.Place.allCases.filter(\.needsFullDiskAccess))
        #expect(proves.count == 4)
        #expect(gated.count == 1)
        #expect(gated.isSubset(of: proves))
        #expect(proves != gated)
    }
}

/// The reader's own source, read once. A source scan rather than a behaviour test for the reason
/// `ContainerGuardTests` gives: by the time a behaviour test could observe the failure, a dialog is
/// already on somebody's screen.
private enum LeftoverReaderSource {
    static let text: String = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tools/AppTests
            .deletingLastPathComponent()   // Tools
            .deletingLastPathComponent()   // the repository
        let file = root.appendingPathComponent("App/Apps/LeftoverReader.swift")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }()
}

// MARK: - ⭐ 2. The Herd regression

/// ⚠️ **The named case. `~/Library/Application Support/Herd` is a working PHP and Composer install.**
///
/// It has no app, no Spotlight entry, and its name matches nothing installed — every signal a
/// name-matching cleaner uses to decide a folder is dead weight. It is 100% safe here for exactly
/// one reason: **"Herd" is not a bundle identifier**, and this section will not act on anything
/// that is not one.
///
/// `LeftoverReaderTests` checks the guard in isolation. This checks the whole path, under the most
/// hostile inputs the reader can be given — nothing installed, nothing running, nothing registered —
/// because that is the configuration in which a wrong answer is easiest to produce.
@Suite("Leftovers — the Herd case")
struct HerdRegressionTests {

    /// Nothing at all is installed, running, or registered.
    private static func answer(_ candidates: [LeftoverReader.Candidate]) -> LeftoverReader.Answer {
        LeftoverReader.answer(from: LeftoverReader.Survey(candidates: candidates),
                              appsOnThisMac: [],
                              runningBundleIDs: [],
                              isRegistered: { _ in false })
    }

    private static func candidate(_ name: String,
                                  _ place: LeftoverReader.Place) -> LeftoverReader.Candidate {
        LeftoverReader.Candidate(identifier: name,
                                 place: place,
                                 path: "/Users/x/Library/\(place.directory)/\(name)",
                                 bytes: 1_400_000_000)
    }

    /// ⭐ **The regression itself.** Herd survives every hostile input and is never reported.
    @Test func herdIsNeverReported() {
        let answer = Self.answer([Self.candidate("Herd", .applicationSupport)])
        #expect(answer.leftovers.isEmpty, """
            Herd was reported as a removed app's leftovers. On one real Mac that folder is a working \
            PHP and Composer, and the row would have offered to set aside 1.4 GB of working \
            software with no app, no Spotlight entry and no name to check it against.
            """)
        #expect(answer.row.measure == nil)
        #expect(answer.row.headline == "Nothing here belonged to an app that has been removed.")
    }

    /// The same folder in every place it could turn up, including the two that count as proof.
    @Test func herdIsSafeWhereverItIsFiled() {
        for place in LeftoverReader.Place.allCases where !place.needsFullDiskAccess {
            let answer = Self.answer([Self.candidate("Herd", place)])
            #expect(answer.leftovers.isEmpty,
                    "Herd in \(place.rawValue) produced a row")
        }
    }

    /// The other four measured folders on this Mac that a name-matching cleaner would offer up.
    /// "Google" is the one that matters most: Chrome's real files are about 5.9 GB and they live
    /// under a name matching neither the app nor its identifier.
    @Test func theOtherProductNamedFoldersAreSafeToo() {
        for name in ["Google", "Adobe", "Firefox", "MobileSync", "CrashReporter", "SyncServices"] {
            let answer = Self.answer([Self.candidate(name, .applicationSupport)])
            #expect(answer.leftovers.isEmpty, "\(name) produced a row")
        }
    }

    /// ⚠️ **Being set aside is counted, not silent.** The row says how much it deliberately left
    /// alone, which is what makes "nothing was found" checkable rather than a claim.
    @Test func whatWasLeftAloneIsCounted() {
        let survey = LeftoverReader.Survey(candidates: [], notIdentifiers: 47)
        let answer = LeftoverReader.answer(from: survey,
                                           appsOnThisMac: [],
                                           runningBundleIDs: [],
                                           isRegistered: { _ in false })
        #expect(answer.leftovers.isEmpty)
        let reason = answer.row.reason ?? ""
        #expect(reason.contains("47"), """
            47 folders were set aside for not being identifiers and the row does not mention them. \
            A count of what was skipped is the only evidence a person has that "nothing found" \
            means anything.
            """)
    }

    /// **A real removed app still gets through.** The point of the file is not that nothing is ever
    /// reported — it is that only proof is. Opera, filed where macOS files it, with the app gone.
    @Test func aGenuinelyRemovedAppIsStillFound() {
        let answer = Self.answer([
            Self.candidate("com.operasoftware.Opera", .applicationSupport),
            Self.candidate("Herd", .applicationSupport),
        ])
        #expect(answer.leftovers.count == 1)
        #expect(answer.leftovers.first?.bundleID == "com.operasoftware.Opera")
        #expect(answer.leftovers.first?.reason.isEmpty == false)
    }
}
