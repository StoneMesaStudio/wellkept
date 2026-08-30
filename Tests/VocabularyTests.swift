import Testing
import Foundation
// Plain import, not `@testable`. Everything the vocabulary promises is public — and a package
// module reached through an Xcode project is not always compiled for testing, which turns a
// missing `public` into a confusing build failure instead of a clear one.
import WellkeptCore

/// ⭐ **The seven sections keep their raw values and their ⌘1–⌘7 order forever.**
///
/// Modelled on Scout's `LaneTests.theOriginalSixKeepTheirNumbersByDefault`, which exists to stop
/// exactly one thing: a tidy-minded reordering of an enum, made for perfectly good reasons, that
/// silently changes what a keyboard shortcut does for everyone who already learned it.
///
/// There are two separate promises here and they fail in different ways.
///
///  1. **A raw value is storage.** `SectionID.rawValue` is written into the saved audit trail and
///     into UserDefaults. Renaming one is a migration: a released build that reads `needsAttention`
///     back as an unknown string forgets that a Mac had a problem. Nobody would deliberately do
///     that — but "Apps" reading better as "Applications" is a one-word change somebody makes
///     without thinking about where the word is stored, which is why the promise is checked by a
///     machine rather than remembered.
///
///  2. **The order is muscle memory.** The sidebar is `allCases`, and ⌘1–⌘7 follow it. Insert a
///     new section in the middle and every number below it shifts. A new section goes at the END,
///     even when the middle is where it belongs conceptually.
///
/// ⚠️ **This suite is written to fail loudly and specifically.** A single `#expect` on the whole
/// array tells you the array changed; the per-case assertions tell you which one moved. Both are
/// here on purpose.
@Suite struct VocabularyTests {

    // MARK: - The order

    @Test func theSevenSectionsAreInSidebarOrder() {
        #expect(SectionID.allCases.map(\.rawValue) ==
                ["overview", "hardware", "storage", "apps", "security", "backup", "changes"])
    }

    /// The numbers, one at a time, so a failure names the section that moved rather than printing
    /// two arrays and leaving the diff to the reader.
    @Test func everySectionKeepsItsNumber() {
        let order = SectionID.allCases
        #expect(order.firstIndex(of: .overview) == 0)   // ⌘1
        #expect(order.firstIndex(of: .hardware) == 1)   // ⌘2
        #expect(order.firstIndex(of: .storage)  == 2)   // ⌘3
        #expect(order.firstIndex(of: .apps)     == 3)   // ⌘4
        #expect(order.firstIndex(of: .security) == 4)   // ⌘5
        #expect(order.firstIndex(of: .backup)   == 5)   // ⌘6
        #expect(order.firstIndex(of: .changes)  == 6)   // ⌘7
    }

    /// Seven, and seven only. ⌘8 does not exist, so an eighth section is a decision about the
    /// keyboard as well as about the sidebar — this is the line that makes somebody notice.
    @Test func thereAreSevenOfThem() {
        #expect(SectionID.allCases.count == 7)
    }

    /// `checkable` is the six Overview summarises. Written as a filter rather than
    /// `allCases.dropFirst()` because "drop the first one" is correct only while `overview` happens
    /// to be first — and a section inserted in the wrong place would silently remove Hardware from
    /// every audit trail in the app.
    @Test func overviewIsNotOneOfTheThingsItSummarises() {
        #expect(SectionID.checkable.count == 6)
        #expect(!SectionID.checkable.contains(.overview))
        #expect(SectionID.checkable == [.hardware, .storage, .apps, .security, .backup, .changes])
    }

    // MARK: - Raw values are storage, labels are English

    @Test func everySectionRawValueIsItsPermanentStorageKey() {
        #expect(SectionID.overview.rawValue == "overview")
        #expect(SectionID.hardware.rawValue == "hardware")
        #expect(SectionID.storage.rawValue  == "storage")
        #expect(SectionID.apps.rawValue     == "apps")
        #expect(SectionID.security.rawValue == "security")
        #expect(SectionID.backup.rawValue   == "backup")
        #expect(SectionID.changes.rawValue  == "changes")
    }

    /// The status words the whole app uses. `needsAttention` is the one that matters: its raw value
    /// is a storage key and its label is two words with a space and a capital N. **A label change
    /// must never be a stored-value change**, and this is the pair that proves the two are allowed
    /// to drift apart.
    @Test func statusRawValuesAndLabelsAreSeparateThings() {
        #expect(SectionStatus.good.rawValue           == "good")
        #expect(SectionStatus.needsAttention.rawValue == "needsAttention")
        #expect(SectionStatus.notChecked.rawValue     == "notChecked")

        #expect(SectionStatus.good.label           == "Good")
        #expect(SectionStatus.needsAttention.label == "Needs attention")
        #expect(SectionStatus.notChecked.label     == "Not checked")

        // Not the same string. If somebody "simplifies" this by deriving the label from the raw
        // value, this line is what stops it — deriving means a better word costs a migration.
        #expect(SectionStatus.needsAttention.label != SectionStatus.needsAttention.rawValue)
    }

    /// There is no fourth status and there is never a score. A number invites the user to chase it,
    /// and a Mac with nothing wrong would then be graded on how little it happened to have
    /// installed.
    @Test func thereAreExactlyThreeStatuses() {
        #expect(SectionStatus.allCases.count == 3)
    }

    @Test func severityRawValuesAndLabelsAreSeparateThings() {
        #expect(Severity.problem.rawValue     == "problem")
        #expect(Severity.attention.rawValue   == "attention")
        #expect(Severity.information.rawValue == "information")

        // The word chosen, chosen 2026-08-26: plainer than "issue".
        #expect(Severity.problem.label == "Problem")
        #expect(Severity.attention.label == "Needs attention")
        #expect(Severity.information.label == "Information")
    }

    // MARK: - Every section has all four of its words

    /// A section with an empty sentence or an empty verb ships a face with a blank line and a blank
    /// button, and nothing else in the build would notice. Cheap to check, and it is the shape of
    /// mistake that arrives with a new section rather than with an edit to an old one.
    @Test func everySectionHasAllFourOfItsWords() {
        for section in SectionID.allCases {
            #expect(!section.title.isEmpty,    "\(section.rawValue) has no title")
            #expect(!section.question.isEmpty, "\(section.rawValue) has no question")
            #expect(!section.sentence.isEmpty, "\(section.rawValue) has no sentence")
            #expect(!section.verb.isEmpty,     "\(section.rawValue) has no verb")
        }
    }

    /// **The vocabulary is fixed app-wide: no screen invents a synonym.** Two sections sharing a
    /// verb means the same button does two different things, which is the failure DESIGN.md §8 is
    /// about.
    @Test func noTwoSectionsShareAVerbOrATitle() {
        #expect(Set(SectionID.allCases.map(\.verb)).count == 7)
        #expect(Set(SectionID.allCases.map(\.title)).count == 7)
    }

    /// The app's main verb, named in CONTRACTS and used on Overview's one button. It is the
    /// Sentence chosen; a rewrite of it is a product decision, not a tidy-up.
    @Test func overviewsButtonIsTheAppsMainVerb() {
        #expect(SectionID.overview.verb == "Check my Mac")
        #expect(SectionID.overview.question == "Is my Mac OK?")
    }

    /// The heading confirms the click rather than renaming the destination — the sidebar row and
    /// the page heading are the same word, so `title` is used for both and there is nowhere for a
    /// second spelling to live.
    @Test func aSectionsTitleIsCapitalisedForDisplayAndItsRawValueIsNot() {
        for section in SectionID.allCases {
            #expect(section.title.lowercased() == section.rawValue,
                    """
                    \(section.rawValue): the title and the storage key have drifted apart. That is \
                    allowed — but if it was not deliberate, one of them is a typo.
                    """)
        }
    }
}
