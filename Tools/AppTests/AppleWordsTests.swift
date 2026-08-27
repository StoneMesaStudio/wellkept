import Testing
import Foundation
import WellkeptCore

//  AppleWordsTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The guard on the bug that shipped: Apple's words were compared in English.**
//
//  `system_profiler` localises its values. `BatteryReader` lowercased the battery's condition word
//  and looked for "service", "replace" and "poor", so on a French Mac — where the same field reads
//  *Réparation recommandée* — a battery Apple itself says needs servicing came back normal. French
//  also uses that one string for `Fair`, ordinary wear, so the two are not separable in either
//  direction by any amount of adding words to the comparison.
//
//  ⚠️ **This file reads this Mac**, and it is the only test in the repo that does. It has to: the
//  fix is "read the reporter's own `Localizable.loctable`", and a test that supplied its own table
//  would prove only that the parser works on a table this file wrote. What it does not do is depend
//  on this Mac's *language* — every expectation below is either language-independent or is checked
//  against the table's own contents rather than against a string typed out here.
//
//  Everything here is read-only: one property list, opened for reading, in `/System/Library`.

@Suite struct AppleWordsTests {

    // MARK: - The table is really there

    /// The premise. If Apple ever stops shipping these, every test below turns into a check that
    /// the fallback still works — which is why the fallback exists, but it should be noticed.
    @Test func theReportersShipAWorldReadableTable() {
        for reporter in [AppleWords.Reporter.power, .controller] {
            #expect(FileManager.default.isReadableFile(atPath: reporter.loctableURL.path),
                    "\(reporter.rawValue) has no readable loctable — the reverse map is now a no-op")
        }
    }

    // MARK: - Keys come back as keys

    /// On this Mac `sppower_battery_health` comes back as `"Good"` — the raw key, not the English
    /// string `"Normal"` it maps to. Some fields are emitted untranslated and some are not, with no
    /// flag saying which, so the key set is checked first and that lookup can never be ambiguous.
    @Test func aRawKeyResolvesToItselfAndIsNeverAmbiguous() {
        #expect(AppleWords.englishKey(for: "Good", from: .power) == .one("Good"))
        #expect(AppleWords.englishKey(for: "Fair", from: .power) == .one("Fair"))
        #expect(AppleWords.englishKey(for: "Poor", from: .power) == .one("Poor"))
        #expect(AppleWords.englishKey(for: "Full Security", from: .controller) == .one("Full Security"))
    }

    /// Case and stray whitespace do not cost a match. Apple indents its own label strings with two
    /// spaces, and a capitalisation change between macOS releases must not blank a row.
    @Test func caseAndSpacingDoNotCostAMatch() {
        #expect(AppleWords.englishKey(for: "  good  ", from: .power) == .one("Good"))
        #expect(AppleWords.englishKey(for: "FULL SECURITY", from: .controller) == .one("Full Security"))
    }

    // MARK: - ⚠️ The translated value, reversed

    /// ⚠️ **The bug, caught.** *Sécurité maximale* is what a French Mac prints for `Full Security`.
    /// The old comparison would have matched nothing; this resolves it, on an English Mac, out of
    /// the machine's own table.
    @Test func aFrenchValueResolvesToItsEnglishKey() {
        #expect(AppleWords.englishKey(for: "Sécurité maximale", from: .controller)
                == .one("Full Security"))
        #expect(AppleWords.englishKey(for: "Sécurité normale", from: .controller)
                == .one("Medium Security"))
    }

    /// And the same in a script that shares none of English's letters, so the match is genuinely
    /// coming from the table rather than from an accidental substring or a shared root.
    @Test func theReverseMapIsNotAnAccidentOfSpelling() {
        #expect(AppleWords.englishKey(for: "完全なセキュリティ", from: .controller)
                == .one("Full Security"))
        #expect(AppleWords.englishKey(for: "Высший уровень безопасности", from: .controller)
                == .one("Full Security"))
        #expect(AppleWords.englishKey(for: "Volle Sicherheit", from: .controller)
                == .one("Full Security"))
    }

    /// A word from nowhere is handed back unchanged, so a caller can still print what the machine
    /// actually said rather than a blank.
    @Test func anUnknownWordIsGivenBackRatherThanGuessedAt() {
        let match = AppleWords.englishKey(for: "Nothing Apple Has Ever Printed", from: .power)
        #expect(match == .unrecognised("Nothing Apple Has Ever Printed"))
        #expect(match.keys.isEmpty)
        #expect(match.certainKey == nil)
    }

    // MARK: - ⭐ Ambiguity is returned, never guessed away

    /// ⚠️ **The half of the bug that cannot be fixed by translating harder.**
    ///
    /// Apple's own table maps `Fair`, `Poor` and `Check Battery` onto a single string — "Service
    /// Recommended" in English, *Réparation recommandée* in French. Reversing it honestly gives
    /// three keys, and there is no way to tell which one this Mac has. Returning one of them would
    /// be a guess printed as a fact.
    @Test func aCollapsedTranslationComesBackAsAnAmbiguity() {
        let match = AppleWords.englishKey(for: "Réparation recommandée", from: .power)
        #expect(match.isAmbiguous, "French collapses Fair and Poor, and this claimed to know which")
        #expect(match.certainKey == nil)
        #expect(Set(match.keys).isSuperset(of: ["Fair", "Poor"]))
    }

    /// Several keys meaning the same thing to *us* are not an ambiguity — they are one answer said
    /// three ways. This is what stops the caller's vocabulary from inheriting Apple's.
    @Test func keysThatMeanTheSameThingToUsCollapseToOneAnswer() {
        let meaning = AppleWords.meaning(of: "Réparation recommandée", from: .power, keys: [
            "Fair":          "service",
            "Poor":          "service",
            "Check Battery": "service",
        ])
        #expect(meaning == .certain("service"))
        #expect(!meaning.isAmbiguous)
    }

    /// ⚠️ **And where they do not, the caller is told.** `Fair` is ordinary wear and `Poor` is Apple
    /// recommending service; one French string covers both, and `BatteryReader` has to know that
    /// rather than being handed a verdict.
    @Test func keysThatMeanDifferentThingsComeBackAsAnAmbiguity() {
        let meaning = AppleWords.meaning(of: "Réparation recommandée", from: .power,
                                         keys: BatteryReader.appleConditionKeys)
        #expect(meaning.isAmbiguous)
        #expect(meaning.certainValue == nil)
        #expect(meaning.possibilities == [.normal, .serviceRecommended])
        #expect(meaning.couldBe(.normal))
        #expect(meaning.couldBe(.serviceRecommended))
    }

    /// A key we have never mapped is `.unrecognised`, not a default. A value we have never seen must
    /// not quietly become "normal".
    @Test func anUnmappedKeyIsNeverGivenADefault() {
        let meaning = AppleWords.meaning(of: "Disabled", from: .controller,
                                         keys: ["Enabled": "on"])
        #expect(meaning == .unrecognised)
        #expect(meaning.possibilities.isEmpty)
    }
}

// MARK: - What the battery does with all of it

@Suite struct BatteryConditionTests {

    /// ⚠️ **The English key set, and the one entry that surprises people.** `Fair` is `.normal`:
    /// it is Apple's word for ordinary wear, and wear is a number on this row, never a condition.
    /// "Worn but working is never a problem."
    @Test func fairIsOrdinaryWearRatherThanAFault() {
        #expect(BatteryReader.appleConditionKeys["Good"] == .normal)
        #expect(BatteryReader.appleConditionKeys["Fair"] == .normal)
        #expect(BatteryReader.appleConditionKeys["Poor"] == .serviceRecommended)
        #expect(BatteryReader.appleConditionKeys["Check Battery"] == .serviceRecommended)
    }

    /// The ordinary case: a raw key, read straight, no doubt attached.
    @Test func aReadableWordProducesNoUncertainty() {
        let good = BatteryReader.condition(source: nil, registry: nil, appleWord: "Good")
        #expect(good.condition == .normal)
        #expect(good.uncertain == false)

        let poor = BatteryReader.condition(source: nil, registry: nil, appleWord: "Poor")
        #expect(poor.condition == .serviceRecommended)
        #expect(poor.uncertain == false)
    }

    /// ⚠️ **The French case, decided and said out loud.** The row takes the safer of the two
    /// readings — which is also the one Apple's own System Settings is showing this person, since
    /// the English table collapses `Fair` and `Poor` the same way — and the doubt travels with it
    /// instead of being swallowed.
    @Test func aCollapsedTranslationTakesTheSaferReadingAndSaysSo() {
        let verdict = BatteryReader.condition(source: nil, registry: nil,
                                              appleWord: "Réparation recommandée")
        #expect(verdict.condition == .serviceRecommended)
        #expect(verdict.uncertain, "the row is about to print a verdict it did not earn")
    }

    /// And the uncertainty reaches the screen. A flag nobody prints is a flag that does nothing.
    @Test func theUncertaintyIsOnTheRowAndInTheOptionsPanel() {
        var facts = BatteryReader.Facts(
            applePercent: 84, measuredPercent: nil, condition: .serviceRecommended,
            failureModes: [], charge: 61, cycles: 640, designCycles: 1_000,
            fullChargeCapacity: 4_100, designCapacity: 4_900,
            pluggedIn: false, charging: false, fullyCharged: false, isVirtualMachine: false)
        facts.uncertain = true

        let row = BatteryReader.row(facts)
        #expect(row.reason?.contains("ordinary wear") == true,
                "the row prints a verdict without the caveat that it might be wear")
        #expect(row.details.contains { $0.label == "Condition" && $0.value.contains("ordinary wear") })

        // A certain reading says nothing about doubt — the caveat must not become boilerplate.
        facts.uncertain = false
        let certain = BatteryReader.row(facts)
        #expect(certain.reason?.contains("One caveat") != true)
    }

    /// A battery that told us nothing usable is still a row we could not read, and it stays
    /// `.notReported`: nothing refused us, the machine simply did not answer.
    @Test func aSilentBatteryIsNotReportedRatherThanRefused() {
        let facts = BatteryReader.Facts(
            applePercent: nil, measuredPercent: nil, condition: .unknown,
            failureModes: [], charge: nil, cycles: nil, designCycles: nil,
            fullChargeCapacity: nil, designCapacity: nil,
            pluggedIn: true, charging: false, fullyCharged: false, isVirtualMachine: false)

        let row = BatteryReader.row(facts)
        #expect(row.unreadable == .notReported)
        #expect(row.measure == nil)
    }
}
