import Testing
import Foundation
import WellkeptCore

//  PrivacyWordingTests.swift
//  ViewShots — Tools/AppTests
//
//  ⭐ **The app-layer half of the privacy rewrite: nothing on any screen makes the promise the app
//  cannot keep.**
//
//  `PrivacyTests` in `WellkeptTests` holds the canonical sentences. This file holds the screens that
//  quote them, because `WellkeptTests` links only `WellkeptCore` and cannot see Help, Settings or
//  the permission copy. This is the one bundle that compiles `App`.
//
//  ⚠️ **The failure this prevents is specific and it has already happened once.** Until 2026-08-27
//  the welcome page promised "Nothing leaves your Mac" with one exception attached, Help promised it
//  with a different exception, and Settings ▸ Permissions promised it with none. Three copies of one
//  promise is three promises, and the Apps section then needed to break all three. Every screen now
//  quotes `Privacy`, and these tests fail the moment one of them writes its own version again.

@Suite struct AppPrivacyWordingTests {

    /// Every sentence any of these screens shows about privacy, in one string.
    private var everyWord: String {
        var parts: [String] = HelpLibrary.all.map(\.searchText)
        parts.append(FullDiskAccess.purpose)
        parts.append(FullDiskAccess.consequence)
        parts.append(FullDiskAccess.reassurance)
        for permission in WellkeptPermission.all {
            parts.append(permission.purpose)
            parts.append(permission.without)
        }
        return parts.joined(separator: "\n").lowercased()
    }

    /// ⚠️ **The struck claim, and every variant of it.** If this fails, somebody has written an
    /// absolute promise into a screen again — and the Apps section breaks it the first time it asks
    /// Apple what version Pages is on.
    ///
    /// ⚠️ The list is the *claims*, not the words. "What leaves this Mac" is a heading this app
    /// needs and now has; banning the phrase outright would fail the honest wording along with the
    /// dishonest, and the next maintainer would delete the test rather than the sentence.
    @Test func noScreenMakesTheAbsoluteClaim() {
        for claim in ["nothing leaves", "never leaves", "nothing ever leaves",
                      "no data leaves", "nothing is sent",
                      "stays on this mac", "stays on your mac",
                      "fully offline", "works entirely offline"] {
            #expect(!everyWord.contains(claim), "an absolute privacy claim is on a screen: \(claim)")
        }
    }

    /// The Help page that exists to be exact about the privilege actually names both halves.
    @Test func helpNamesEveryDepartureAndItsCost() throws {
        let article = try #require(HelpLibrary.all.first { $0.id == "never" })
        let text = article.searchText

        for departure in Privacy.Departure.allCases {
            #expect(text.contains(departure.title),
                    "Help does not name \(departure.rawValue)")
            #expect(text.contains(departure.whatLeaves),
                    "Help does not say what leaves for \(departure.rawValue)")
            #expect(text.contains(departure.cost),
                    "Help does not say the cost of switching off \(departure.rawValue)")
        }

        // And the promises that are unconditional are there too, verbatim.
        for line in Privacy.neverDone {
            #expect(text.contains(line))
        }
    }

    /// The permission copy quotes the canonical sentence rather than inventing a reassurance. A
    /// permission screen is exactly where a soothing over-claim is most tempting.
    @Test func thePermissionCopyQuotesTheCanonicalSentence() {
        #expect(FullDiskAccess.reassurance.contains(Privacy.readingOnly))
        #expect(FullDiskAccess.reassurance.contains("never deletes anything"))
    }

    /// Help counts the departures rather than saying "two". A third one would otherwise appear on
    /// the page under a sentence still claiming there are two.
    @Test func helpCountsTheDeparturesRatherThanStatingTwo() throws {
        let article = try #require(HelpLibrary.all.first { $0.id == "never" })
        // ⚠️ The page counts from the register, and so must this. Asserting the literal "Two
        // things" was itself the mistake the test's own name warns about — it went red on
        // 2026-08-30 when `wellkeptUpdateCheck` was removed for describing an updater nobody built,
        // which is exactly the change this test should have waved through.
        let spelled = ["Nothing", "One thing", "Two things", "Three things"]
        let count = Privacy.Departure.allCases.count
        let expected = count < spelled.count ? spelled[count] : "\(count) things"
        #expect(article.searchText.contains("\(expected), and there is nothing else."))
        #expect(count >= 1, "the register is empty — either something was lost, or the app stopped talking to anything at all")
    }
}

// MARK: - The self-updating list

//  ⭐ **The list is ours, it is short, and being wrong on it is cheap — but it is not free.**
//
//  A hand-maintained list of vendor *version endpoints* was declined on 2026-08-27: *"I don't know
//  that I want that responsibility. They frequently release updates."* This list survives because
//  its failure mode is different — a stale entry swaps one truthful sentence for another truthful
//  sentence, where a stale endpoint reports a wrong version. These tests hold that distinction.

@Suite struct SelfUpdatingAppsTests {

    /// ⚠️ **Short enough that a person can audit it in a minute.** That is the entire justification
    /// for shipping a hardcoded list at all. If this ever fails, the approach was wrong and the
    /// conversation to have is with the developer.
    @Test func theListIsShortEnoughToRead() {
        #expect(SelfUpdatingApps.entries.count <= 40)
        #expect(!SelfUpdatingApps.entries.isEmpty)
    }

    /// A duplicate identifier is invisible on the page and means somebody added an app twice.
    @Test func noIdentifierAppearsTwice() {
        let ids = SelfUpdatingApps.entries.map { $0.bundleID.lowercased() }
        #expect(Set(ids).count == ids.count)
    }

    /// Every entry says which updater earns it a place. "Has a Check for Updates menu item" is a
    /// person remembering, not an app updating itself — and the field is where somebody has to say
    /// which of the two this is.
    @Test func everyEntryNamesItsUpdater() {
        for entry in SelfUpdatingApps.entries {
            #expect(!entry.name.isEmpty)
            #expect(!entry.updater.isEmpty)
            #expect(entry.bundleID.contains("."))
        }
    }

    /// Bundle identifiers are compared case-insensitively by macOS, and Chrome's real one is
    /// `com.google.Chrome`. A case-sensitive match would miss it on some Macs and not others.
    @Test func theLookupIgnoresCase() {
        #expect(SelfUpdatingApps.isSelfUpdating(bundleID: "com.google.chrome"))
        #expect(SelfUpdatingApps.isSelfUpdating(bundleID: "COM.GOOGLE.CHROME"))
        #expect(SelfUpdatingApps.standing(forBundleID: "com.google.Chrome") == .keepsItselfUpToDate)
    }

    /// ⚠️ **`nil` means "this file has nothing to say", not "it cannot be checked."** Returning a
    /// `.couldNotTell` from here would let the list's silence look like a finding about the app.
    @Test func anAppNotOnTheListGetsNoAnswerRatherThanABadOne() {
        #expect(SelfUpdatingApps.standing(forBundleID: "com.example.nothing") == nil)
        #expect(SelfUpdatingApps.entry(forBundleID: "com.example.nothing") == nil)
    }

    /// ⚠️ **Wellkept is not on this list and must never be.** It does not update itself: it checks,
    /// and asks. Putting itself on a list of apps that need no checking is how an app quietly stops
    /// telling you about its own updates.
    @Test func wellkeptIsNotOnItsOwnList() {
        #expect(!SelfUpdatingApps.isSelfUpdating(bundleID: "studio.stonemesa.wellkept"))
    }

    /// Chrome is on the list for a measured reason, and the entry says so: its staged rollout put a
    /// version at the top of Google's public list that was serving to nobody, so a comparison
    /// reported a current browser as two versions behind.
    @Test func chromeIsOnTheListAndTheEntrySaysWhy() throws {
        let entry = try #require(SelfUpdatingApps.entry(forBundleID: "com.google.Chrome"))
        #expect(entry.name == "Google Chrome")
        #expect(entry.updater.lowercased().contains("staged rollout"))
    }
}
