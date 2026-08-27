import Testing
import Foundation
import WellkeptCore

//  SecurityLocalizationTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The localization bug, checked on the Security side of the fix.**
//
//  `AppleWordsTests` proves the reverse map itself: a translated value resolves to Apple's English
//  key, and where a language collapses two keys onto one string it comes back as an ambiguity
//  rather than a guess. This file asks the next question — **does the Security reader that has to
//  live with that actually behave?**
//
//  Boot security is the live case. `ibridge_secure_boot` is a localised value, so on a French Mac
//  it reads *Sécurité maximale* rather than `Full Security`, and a reader comparing English would
//  have found nothing at all and reported a Mac that could not say. Worse, if it had matched loosely
//  it could have reported a reduced-security Mac as fully secure — a flattering wrong answer, which
//  is the only kind this app is genuinely afraid of.
//
//  ⚠️ **These tests read this Mac's own `Localizable.loctable` files** — read-only, in
//  `/System/Library` — for the reason `AppleWordsTests` gives: a test that supplied its own table
//  would prove only that the parser works on a table this file wrote. Nothing here depends on this
//  Mac's *language*.

@Suite struct SecurityLocalizationTests {

    // MARK: - The value a French Mac actually prints

    /// ⚠️ **The bug, on the row it would have shipped in.** All four of Apple's secure-boot levels,
    /// in a language that shares none of English's spelling, arriving at the same state the English
    /// word produces.
    @Test func bootSecurityIsUnderstoodInWhateverLanguageThisMacSpeaks() {
        let cases: [(word: String, english: String)] = [
            ("Sécurité maximale", "Full Security"),
            ("Sécurité normale",  "Medium Security"),
            ("完全なセキュリティ",   "Full Security"),
            ("Volle Sicherheit",  "Full Security"),
        ]

        for (word, english) in cases {
            let localised = ProtectionReader.secureBoot(controller: ["ibridge_secure_boot": word])
            let plain = ProtectionReader.secureBoot(controller: ["ibridge_secure_boot": english])

            #expect(localised.state == plain.state,
                    "“\(word)” read differently from “\(english)”")
            #expect(localised.protection.concern == plain.protection.concern)
            #expect(localised.state.wasRead, "“\(word)” was not recognised at all")
        }
    }

    /// A localised *Medium Security* is a reduced Mac and raises the concern, exactly as the English
    /// word does. The failure this guards is the quiet one: a translated value that matches nothing,
    /// so the row says "this Mac does not report it" on every non-English Mac on earth.
    @Test func aTranslatedReducedMacIsStillAReducedMac() {
        let reading = ProtectionReader.secureBoot(controller: ["ibridge_secure_boot": "Sécurité normale"])
        #expect(reading.state == .reduced)
        #expect(reading.protection.concern == .bootSecurityReduced)
        #expect(reading.state.label != "Off", "reduced is not off")
    }

    // MARK: - ⭐ Ambiguity is taken the cautious way, and said out loud

    /// ⚠️ **The half of the bug no amount of translating fixes.** Apple's own table maps more than
    /// one key onto one string in some languages, and reversing it honestly gives several keys with
    /// no way to tell which this Mac has.
    ///
    /// `SecureBootLevel.allCases` is ordered least secure first precisely so `first(where:)` is the
    /// cautious reading. Guessing the flattering side is how a reduced Mac reports as fully secure
    /// on the strength of a translation.
    @Test func theOrderIsWhatMakesAnAmbiguityResolveTheCautiousWay() {
        #expect(ProtectionReader.SecureBootLevel.allCases
                == [.unverified, .permissive, .reduced, .full])

        // The rule itself, applied to a hand-built ambiguity — which is what a collapsing language
        // hands the reader.
        let ambiguous = AppleWords.Meaning.ambiguous([ProtectionReader.SecureBootLevel.full,
                                                      .reduced])
        let chosen = ProtectionReader.SecureBootLevel.allCases.first(where: ambiguous.couldBe)
        #expect(chosen == .reduced, "the reader took the flattering side of a doubt")
    }

    /// And the doubt reaches the screen rather than being swallowed. A caveat nobody prints is a
    /// caveat that does nothing — the same rule the battery row follows.
    @Test func aCollapsedTranslationSaysSoOnTheRow() {
        // The battery is where a real collapse can be demonstrated from this Mac's own table:
        // French uses one string for `Fair`, `Poor` and `Check Battery`.
        let meaning = AppleWords.meaning(of: "Réparation recommandée", from: .power,
                                         keys: BatteryReader.appleConditionKeys)
        #expect(meaning.isAmbiguous)
        #expect(meaning.certainValue == nil, "a guess was printed as a fact")
        #expect(meaning.possibilities.count > 1)

        let verdict = BatteryReader.condition(source: nil, registry: nil,
                                              appleWord: "Réparation recommandée")
        #expect(verdict.uncertain, "the doubt was swallowed on the way to the row")
    }

    // MARK: - Keys are read, values are reversed

    /// ⚠️ **A field name never reverse-maps to somebody else's word**, and this is subtler than it
    /// sounds.
    ///
    /// `ibridge_secure_boot` is itself an entry in the controller's own table — it is the label
    /// Apple prints beside the value — so looking it up resolves it to *itself*, not to nothing.
    /// That is fine. What would be a shipped bug is a key resolving to a **different** key, or
    /// coming back ambiguous, because every Security reader asks by key and reverse-maps only what
    /// it finds inside.
    @Test func aFieldNameNeverResolvesToSomebodyElsesWord() {
        for key in ["ibridge_secure_boot", "ibridge_sb_ssv", "ibridge_sb_device_mdm",
                    "spfirewall_globalstate", "spfirewall_stealthenabled"] {
            let match = AppleWords.englishKey(for: key, from: .controller)
            #expect(!match.isAmbiguous, "\(key) came back ambiguous — a key is not a value")
            switch match {
            case .one(let resolved):
                #expect(resolved == key, "\(key) resolved to \(resolved), which is a different key")
            case .unrecognised(let given):
                #expect(given == key)
            case .several(let keys):
                Issue.record("\(key) resolved to several keys: \(keys)")
            }
        }
    }

    /// Apple's own key is matched as exactly as a translation of it, which is what keeps the reader
    /// working on the day macOS starts translating a string it currently emits raw.
    @Test func applesOwnRawStringsStillMatchThemselves() {
        #expect(AppleWords.englishKey(for: "Full Security", from: .controller) == .one("Full Security"))
        #expect(AppleWords.englishKey(for: "Medium Security", from: .controller) == .one("Medium Security"))
    }

    /// A value Apple has never printed is shown back verbatim and claimed nothing about. On a
    /// future macOS that renames a level, the row says what the Mac said rather than inventing a
    /// state for it.
    @Test func aWordFromNowhereIsShownRatherThanGuessedAt() {
        let odd = ProtectionReader.secureBoot(controller: ["ibridge_secure_boot": "Ultra Security"])
        #expect(odd.state.wasRead == false)
        #expect(odd.protection.concern == nil, "an unknown word became a finding about this Mac")
        #expect(odd.details.contains { $0.value == "Ultra Security" })
    }
}
