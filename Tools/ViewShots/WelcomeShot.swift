//
//  WelcomeShot.swift
//  ViewShots
//
//  **The rewritten welcome page, photographed at the size the sheet actually is.**
//
//  ## Why this page needed a picture the day it changed
//
//  On 2026-08-27 the welcome page stopped being four short lines and became three sections: what
//  Wellkept never does, **every single thing that leaves this Mac**, and what the app is. That is
//  roughly three times the words, inside a sheet that is a fixed 560 × 520 — and the app's text
//  scale goes to 200%.
//
//  Nothing in the test suite can see a Continue button that has been pushed below the fold. Waypoint
//  learned that the expensive way and built this harness for it; this is exactly the shape of
//  failure it exists to catch, on the one screen where the consequence is a person unable to finish
//  setup.
//
//  What to look at in these pictures: the header and the **Continue** button are outside the scroll
//  view and stay put, the privacy text scrolls between them, and no sentence is clipped at either
//  text size.
//
//  ⚠️ Nothing here reads this Mac, and nothing here is written here — every sentence on the page
//  comes from `Privacy` in `WellkeptCore`. A picture can therefore never show wording the app is no
//  longer capable of producing.
//
//      bin/make-shots.sh
//

import AppKit
import SwiftUI
import Testing
import WellkeptCore

@Suite("View shots — the welcome page", .serialized)
@MainActor
struct WelcomeShot {

    /// The real sheet size from `SetupFlow`, typed out rather than read from `SheetMetrics`.
    ///
    /// `SheetMetrics` shrinks a sheet to fit the screen it will open on, which is the right
    /// behaviour in the app and the wrong one here: a picture whose size depends on the build
    /// machine's display is a picture two people cannot compare.
    private let sheet = CGSize(width: 560, height: 520)

    /// The page inside the chrome `SetupFlow` puts around it.
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            WelcomeView {}
                .padding(Space.page)
        }
        .pageGround()
    }

    private func bothAppearances(_ view: some View, _ number: Int, _ name: String) {
        ShotWriter.write(view, width: sheet.width, height: sheet.height,
                         name: "\(number)-\(name)-light", scheme: .light)
        ShotWriter.write(view, width: sheet.width, height: sheet.height,
                         name: "\(number + 1)-\(name)-dark", scheme: .dark)
    }

    /// Run a block at a **named** text scale, then put back whatever was there.
    ///
    /// ⚠️ **The 100% shot sets 1.0 rather than trusting whatever is already stored, and that is not
    /// belt-and-braces.** The text scale is one global preference, the shot suites set it while they
    /// render, and Swift Testing runs suites concurrently even under
    /// `-parallel-testing-enabled NO`, which only governs xctest's own parallelism. The first
    /// version of this file assumed the ambient value was 1.0 and produced a "100%" picture and a
    /// "200%" picture that were byte-for-byte identical — both at 200%, because a neighbouring suite
    /// had the setting turned up at the time. A picture that silently shows the wrong thing is worse
    /// than no picture.
    private func atTextScale(_ scale: Double, _ body: () -> Void) {
        let key = AppearancePrefs.textScaleKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(scale, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        body()
    }

    /// Both sizes in one test, so nothing between them can move the setting.
    ///
    /// ⚠️ **The 200% pair is the one that matters.** At that size the never-list alone is taller than
    /// the sheet, so those two pictures are the proof that the header and the **Continue** button
    /// stayed put while the privacy text scrolled between them.
    @Test("The welcome page, at 100% and at 200% text")
    func welcomePageAtBothTextSizes() {
        atTextScale(1.0) { bothAppearances(page, 140, "welcome") }
        atTextScale(Double(AppFont.maxScale)) { bothAppearances(page, 142, "welcome-200") }
    }
}

// MARK: - What the page is obliged to say

/// ⭐ **The welcome page is a promise, so what is on it is checked rather than admired.**
///
/// These read the same `Privacy` register the page renders from, which is the point: the page cannot
/// pass this by having its own copy of the words, because it has no copy of the words.
@Suite("The welcome page names everything that leaves this Mac")
@MainActor
struct WelcomePageContentTests {

    /// Every departure appears on the page, because the page is built from `allCases`. A third thing
    /// that leaves this Mac shows up here the day its case is added, whether or not anybody
    /// remembered to edit the welcome screen.
    @Test func thePageIsDrivenByTheRegisterRatherThanAList() {
        // ⚠️ Not a literal count. The point of this test is that the page follows the register, so
        // pinning the register's size here contradicts it — and it did, on 2026-08-30.
        #expect(!Privacy.Departure.allCases.isEmpty)
        for departure in Privacy.Departure.allCases {
            #expect(!departure.title.isEmpty)
            #expect(!departure.whatLeaves.isEmpty)
            #expect(!departure.cost.isEmpty)
        }
    }

    /// The three sections the page is made of are all non-empty. An empty never-list would render as
    /// a heading with nothing under it — a privacy page that appears to promise nothing.
    @Test func noSectionOfThePageCanRenderEmpty() {
        #expect(!Privacy.neverDone.isEmpty)
        #expect(!Privacy.departuresIntro.isEmpty)
        #expect(!Privacy.Departure.allCases.isEmpty)
    }
}
