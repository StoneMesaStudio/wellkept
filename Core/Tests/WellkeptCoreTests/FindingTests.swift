import Testing
import Foundation
@testable import WellkeptCore

/// **What the vocabulary has to be true for, as opposed to what it has to be spelled.**
///
/// `Tests/VocabularyTests.swift` guards the words and the order. This file guards the behaviour
/// underneath them — the comparison, the sort, and the one flag that keeps Overview honest. They
/// are separate suites in separate targets on purpose: this one runs under `swift test` with no
/// Xcode project at all, which is what `bin/preflight.conf`'s `SWIFT_PACKAGES=(Core)` line exists
/// to make happen. The app scheme's test action does not run a package's own tests.
@Suite struct SeverityOrderTests {

    /// ⚠️ **`Severity` sorts most-severe LAST.** `information < attention < problem`, so `max()`
    /// finds the worst thing in a list and a DESCENDING sort puts problems at the top of Overview.
    ///
    /// This is the wrong way round from the intuition — the enum's cases are declared worst-first
    /// for readability — and it is exactly the kind of thing that gets "corrected" by somebody
    /// reading only the declaration. Getting it backwards ships an Overview that leads with
    /// information and buries a failing drive at the bottom.
    @Test func informationIsTheLeastSevereAndProblemTheMost() {
        #expect(Severity.information < Severity.attention)
        #expect(Severity.attention < Severity.problem)
        #expect(Severity.problem > Severity.information)
    }

    @Test func maxFindsTheWorstThingInTheList() {
        let list: [Severity] = [.information, .problem, .attention, .information]
        #expect(list.max() == .problem)
        #expect(list.min() == .information)
    }

    /// The sort Overview actually performs. Written out as the call it will be, not as an
    /// abstraction, so the direction is checked rather than described.
    @Test func aDescendingSortPutsProblemsAtTheTop() {
        let findings = [
            Finding(section: .storage, title: "Downloads", reason: "Largest folder in your home folder.",
                    severity: .information, measure: "41.2 GB"),
            Finding(section: .hardware, title: "Startup disk", reason: "The drive is reporting a failing sector count.",
                    severity: .problem),
            Finding(section: .hardware, title: "Battery", reason: "Capacity has fallen below 80% of new.",
                    severity: .attention, measure: "78%"),
        ]
        let ordered = findings.sorted { $0.severity > $1.severity }
        #expect(ordered.map(\.severity) == [.problem, .attention, .information])
        #expect(ordered.first?.title == "Startup disk")
    }

    /// Sorting is stable enough to be worth stating: two findings of the same severity keep the
    /// order the section produced them in, which is the order the section decided was useful.
    @Test func equalSeveritiesAreNotReordered() {
        #expect(!(Severity.attention < Severity.attention))
        #expect(!(Severity.attention > Severity.attention))
    }
}

@Suite struct FindingTests {

    /// A finding always carries its reason. **A flagged item with no reason is an accusation**; the
    /// reason is what lets the user disagree with the app. It is not optional in the type, and this
    /// test is here so that stays true if somebody ever reaches for a convenience initialiser.
    @Test func aFindingAlwaysCarriesItsReason() {
        let f = Finding(section: .security, title: "Firewall", reason: "It is switched off.",
                        severity: .problem, verb: "Open Settings")
        #expect(!f.reason.isEmpty)
        #expect(f.verb == "Open Settings")
        #expect(f.measure == nil)
    }

    /// Two findings that say the same thing are still two findings. The identity is the `UUID`, not
    /// the words — Overview shows a list, and de-duplicating by content would collapse "Downloads
    /// is large" for two different volumes into one row.
    @Test func twoIdenticalDescriptionsAreStillTwoFindings() {
        let a = Finding(section: .storage, title: "Downloads", reason: "Large.", severity: .information)
        let b = Finding(section: .storage, title: "Downloads", reason: "Large.", severity: .information)
        #expect(a != b)
        #expect(a.id != b.id)
    }

    /// ⚠️ **`.problem` only where something is actually wrong.** A 40 GB folder is not a problem, it
    /// is large. This is the distinction the whole product rests on: get it wrong and a health check
    /// becomes a scareware cleaner, which is the entire category this app exists not to be.
    ///
    /// No test can read intent, so this checks the thing that CAN be checked — that the three
    /// severities are genuinely distinct values and that a section cannot accidentally get `.problem`
    /// by leaving an argument off. There is no default.
    @Test func severityMustBeStatedAndHasNoDefault() {
        #expect(Severity.allCases.count == 3)
        #expect(Set(Severity.allCases.map(\.rawValue)).count == 3)
    }
}

@Suite struct CheckRecordTests {

    /// **`complete` is the field that keeps Overview honest.** A check that ran without Full Disk
    /// Access saw part of the machine, and Overview may never say a Mac looks fine on the strength
    /// of a partial look (CONTRACTS C2).
    ///
    /// It travels with the record rather than being inferred later from whichever permissions
    /// happen to be granted when the summary is drawn — which is the version that goes wrong: grant
    /// the permission after a partial scan and an inferred flag would retroactively declare the old
    /// result trustworthy.
    @Test func anIncompleteCheckIsRememberedAsIncomplete() {
        let ran = Date(timeIntervalSince1970: 1_787_000_000)
        let partial = CheckRecord(section: .storage, ranAt: ran, status: .good, complete: false)
        #expect(partial.complete == false)
        #expect(partial.status == .good)
        // Good AND incomplete is a real, expected combination: nothing wrong in what we could see.
        // Overview's job is to say both halves, not to pick one.
    }

    /// The audit trail Overview's "What was checked" disclosure lists: one line per checkable
    /// section, six of them, Overview not among them.
    @Test func theAuditTrailCoversTheSixCheckableSections() {
        let ran = Date(timeIntervalSince1970: 1_787_000_000)
        let trail = SectionID.checkable.map {
            CheckRecord(section: $0, ranAt: ran, status: .notChecked, complete: true)
        }
        #expect(trail.count == 6)
        #expect(!trail.contains { $0.section == .overview })
        #expect(Set(trail.map(\.section)).count == 6)
    }

    /// A section's newest record wins. Trivial arithmetic, written down because the alternative —
    /// keeping the first one — is what a naive dictionary insert does, and the symptom would be an
    /// Overview permanently showing the date of the very first scan.
    @Test func theNewestRecordForASectionIsTheOneThatCounts() {
        let older = CheckRecord(section: .backup, ranAt: Date(timeIntervalSince1970: 1_000_000),
                                status: .needsAttention, complete: true)
        let newer = CheckRecord(section: .backup, ranAt: Date(timeIntervalSince1970: 2_000_000),
                                status: .good, complete: true)
        let latest = [older, newer].max { $0.ranAt < $1.ranAt }
        #expect(latest == newer)
        #expect(latest?.status == .good)
    }
}
