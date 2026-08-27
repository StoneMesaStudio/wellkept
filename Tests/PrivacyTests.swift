import Testing
import Foundation
import WellkeptCore

//  PrivacyTests.swift
//  WellkeptTests
//
//  ⭐ **The privacy wording, held by a machine, because the last version of it drifted apart across
//  three screens without anybody noticing.**
//
//  On 2026-08-27 John struck the welcome page's "Nothing leaves your Mac." It was Claude's wording,
//  not his, and by then it existed in three forms: with one exception on the welcome page, with a
//  different exception in Help, and with none at all in Settings. Then Apps arrived needing to ask
//  makers whether an app has a newer version, which the absolute form forbids outright.
//
//  These tests hold the replacement in shape:
//
//  1. **What is never done is unconditional** — no "except", no "unless", because every line of it
//     is actually true.
//  2. **Every departure is registered**, with what leaves, what it costs to switch off, and a key.
//  3. **The absolute claim cannot come back** in any canonical sentence.
//  4. **Raw values are permanent**, because they are stored preference keys.

@Suite struct PrivacyPromiseTests {

    /// ⚠️ **The list of things that never happen carries no exceptions, and that is the whole point
    /// of separating it from the departures.** A promise with an "except" clause welded on is the
    /// shape that failed. If a line here ever needs one, it stops being a promise and becomes a
    /// `Privacy.Departure`.
    @Test func nothingOnTheNeverListIsConditional() {
        #expect(!Privacy.neverDone.isEmpty)
        for line in Privacy.neverDone {
            let lowered = line.lowercased()
            for hedge in ["except", "unless", "apart from", "other than", "aside from"] {
                #expect(!lowered.contains(hedge), "\(hedge) appeared in: \(line)")
            }
            // Each line is a sentence, not a fragment.
            #expect(line.hasSuffix("."))
        }
    }

    /// The never-list names the four things John actually cared about: collection, selling,
    /// accounts, and marketing.
    @Test func theNeverListNamesWhatJohnNamed() {
        let all = Privacy.neverDone.joined(separator: " ").lowercased()
        #expect(all.contains("collected"))
        #expect(all.contains("sold"))
        #expect(all.contains("account"))
        #expect(all.contains("identifier"))
        #expect(all.contains("telemetry"))
        #expect(all.contains("mailing list"))
    }

    /// ⚠️ **The absolute claim must not come back.** This is the exact sentence that was struck, and
    /// every variant of it a well-meaning edit would reach for.
    @Test func theAbsoluteClaimIsGoneFromEveryCanonicalSentence() {
        let everything = ([Privacy.headline,
                           Privacy.departuresIntro,
                           Privacy.readingOnly,
                           Privacy.summaryLine]
                          + Privacy.neverDone
                          + Privacy.Departure.allCases.flatMap { [$0.title, $0.whatLeaves, $0.cost] })
            .joined(separator: " ")
            .lowercased()

        for claim in ["nothing leaves", "never leaves", "nothing ever leaves",
                      "stays on your mac", "stays on this mac", "fully offline",
                      "no data leaves"] {
            #expect(!everything.contains(claim), "the struck claim came back: \(claim)")
        }
    }

    /// The headline says both halves. "Wellkept collects nothing" on its own is the absolute claim
    /// wearing a different hat.
    @Test func theHeadlineNeverStatesOnlyTheFlatteringHalf() {
        let headline = Privacy.headline.lowercased()
        #expect(headline.contains("collects nothing"))
        #expect(headline.contains("leave"))
        #expect(headline.contains("switched off"))
    }
}

@Suite struct PrivacyDepartureTests {

    /// ⚠️ **The register.** Today it is exactly two: checking whether your apps are current, and
    /// checking whether Wellkept has an update. A third one changes this number, and changing this
    /// number is meant to be a decision rather than an accident.
    @Test func thereAreExactlyTwoThingsThatLeave() {
        #expect(Privacy.Departure.allCases == [.appUpdateCheck, .wellkeptUpdateCheck])
    }

    /// Every departure answers all four questions: what it is called, what actually goes out, what
    /// switching it off costs, and where the switch is stored. A case that skipped one would let
    /// something leave this Mac without anybody having written down what.
    @Test func everyDepartureAnswersAllFourQuestions() {
        for departure in Privacy.Departure.allCases {
            #expect(!departure.title.isEmpty)
            #expect(!departure.whatLeaves.isEmpty)
            #expect(!departure.cost.isEmpty)
            #expect(!departure.settingsKey.isEmpty)
            #expect(departure.detailPairs.count == 2)
        }
    }

    /// ⚠️ **The cost line is the half that usually goes missing.** A switch with no stated cost is a
    /// switch people flip out of caution and then wonder why the app got worse.
    @Test func everyCostLineSaysWhatIsLostAndWhatIsNot() {
        for departure in Privacy.Departure.allCases {
            let cost = departure.cost.lowercased()
            #expect(cost.contains("off"))
            // It has to name what still works, not only what stops.
            #expect(cost.contains("still") || cost.contains("everything else"))
        }
    }

    /// The app-update line says the unavoidable part out loud: asking a maker whether a newer
    /// version exists necessarily tells them a copy is installed somewhere.
    @Test func theAppUpdateLineAdmitsWhatAskingImplies() {
        let what = Privacy.Departure.appUpdateCheck.whatLeaves.lowercased()
        #expect(what.contains("necessarily tells them"))
        #expect(what.contains("nothing about you"))
    }

    /// Two switches, two distinct keys, and neither collides with anything in `docs/CONTRACTS.md`.
    @Test func theSettingsKeysAreDistinctAndPermanent() {
        let keys = Privacy.Departure.allCases.map(\.settingsKey)
        #expect(Set(keys).count == keys.count)
        #expect(Privacy.Departure.appUpdateCheck.settingsKey == "checkAppUpdates")
        #expect(Privacy.Departure.wellkeptUpdateCheck.settingsKey == "checkWellkeptUpdates")
    }

    /// Raw values are storage — they go into preferences and into anything that records a consent
    /// answer. Renaming one is a migration; renaming a title is a one-line edit.
    @Test func rawValuesArePermanentAndTitlesAreSeparate() {
        #expect(Privacy.Departure.appUpdateCheck.rawValue == "appUpdateCheck")
        #expect(Privacy.Departure.wellkeptUpdateCheck.rawValue == "wellkeptUpdateCheck")
        for departure in Privacy.Departure.allCases {
            #expect(departure.title != departure.rawValue)
        }
    }
}
