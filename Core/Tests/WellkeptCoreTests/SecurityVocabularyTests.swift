import Testing
import Foundation
@testable import WellkeptCore

//  SecurityVocabularyTests.swift
//  WellkeptCoreTests
//
//  ⭐ **One list of nine, and no second door into amber.**
//
//  `Tests/SecurityTests.swift` checks that the nine are the nine that were kept, one example at a
//  time. This file asks the harder question — **is there any other way in?** — and answers it by
//  enumerating the whole space rather than by picking cases. Every `Protection` that can be built,
//  every `Grant` that can be built, every row and every report, and then a count: the set of
//  concerns reachable from any of them is exactly `SecurityConcern.allCases`, and the set of ways
//  to make a row amber is exactly "it named one of the nine".
//
//  It lives in the package rather than in the app's test bundle for a reason that is not
//  bookkeeping. `swift test --package-path Core` runs with no Xcode project, no scheme, no app
//  target and no views — so this keeps running on a day when the app does not build, which is
//  precisely the day somebody is most likely to reach for `severity` and set it by hand.
//
//  ⚠️ Nothing here reads this Mac, and nothing here has a machine in it at all.

// MARK: - The list itself

@Suite struct SecurityConcernListTests {

    /// The nine, spelled out once. Everything below counts against this and nothing below repeats
    /// it — a second copy of the list is a second list.
    static let theNine: Set<SecurityConcern> = [
        .fileVaultOff, .firewallOff, .gatekeeperWeakened, .systemProtectionOff,
        .bootSecurityReduced, .automaticSecurityUpdatesOff, .automaticLoginOn,
        .signatureChangedSinceApproved, .permissionHeldByMissingApp,
    ]

    /// ⚠️ **`allCases` IS the list.** A tenth condition cannot be added anywhere else in the
    /// codebase without failing here, which is what makes "a tenth is a conversation with the
    /// developer" enforceable rather than aspirational.
    @Test func theListIsTheEnumAndTheEnumIsTheList() {
        #expect(Set(SecurityConcern.allCases) == Self.theNine)
        #expect(SecurityConcern.allCases.count == 9)
    }

    /// Raw values are storage. They reach `CheckRecord`s and, one day, a saved report — so renaming
    /// one silently reclassifies history. Pinned here, separately from the labels, so a wording
    /// change is free and a storage change is loud.
    @Test func rawValuesArePermanentAndSeparateFromTheWords() {
        #expect(SecurityConcern.allCases.map(\.rawValue) == [
            "fileVaultOff",
            "firewallOff",
            "gatekeeperWeakened",
            "systemProtectionOff",
            "bootSecurityReduced",
            "automaticSecurityUpdatesOff",
            "automaticLoginOn",
            "signatureChangedSinceApproved",
            "permissionHeldByMissingApp",
        ])
        for concern in SecurityConcern.allCases {
            #expect(concern.id == concern.rawValue)
            #expect(concern.title != concern.rawValue, "\(concern.rawValue) shows its raw value")
        }
    }

    /// ⚠️ **Nothing in Security is red, and this is the only place that can stay true by itself.**
    /// Severity is a property of the concern, so a row cannot decide to escalate one.
    @Test func everyOneOfTheNineIsAmber() {
        #expect(Set(SecurityConcern.allCases.map(\.severity)) == [.attention])
    }

    /// Every concern belongs to a row that exists, so none of them can be raised into a topic the
    /// panel does not draw.
    @Test func everyConcernLandsOnARowTheSectionActuallyDraws() {
        for concern in SecurityConcern.allCases {
            #expect(SecurityTopic.allCases.contains(concern.topic))
        }
    }

    /// The seven switch-shaped concerns and the two app-shaped ones account for all nine, with
    /// nothing left over in either direction. This is the mapping the organisation-set filter uses,
    /// so a concern missing from it would be one an employer could be blamed for.
    @Test func theSwitchesAndTheAppsAccountForAllNine() {
        let fromSwitches = Set(ProtectionKind.allCases.compactMap(\.concern))
        let fromApps: Set<SecurityConcern> = [.signatureChangedSinceApproved, .permissionHeldByMissingApp]

        #expect(fromSwitches.isDisjoint(with: fromApps))
        #expect(fromSwitches.union(fromApps) == Self.theNine)
        #expect(fromSwitches.count == 7)

        // And the round trip holds, so a switch and its concern can never point at each other's
        // neighbours.
        for concern in SecurityConcern.allCases {
            if let kind = concern.protection {
                #expect(kind.concern == concern)
            } else {
                #expect(fromApps.contains(concern))
            }
        }
    }
}

// MARK: - ⭐ No second door into amber

/// ⚠️ **The question this file exists for.** Not "does naming a concern make a row amber" — the
/// other suite covers that — but **"can anything else?"**
///
/// `SecurityRow.severity` is computed rather than stored, which is the mechanism. These tests are
/// what would fail on the day somebody adds a stored `severity` beside it "just for one reader",
/// which is exactly how six parallel readers end up with twenty conditions between them.
@Suite struct NoOtherRouteToAmberTests {

    /// Every row that can be built out of the vocabulary, enumerated: six topics × the three
    /// unreadable states and none × with and without a measure × every subset-of-one of the nine,
    /// plus the whole nine at once.
    ///
    /// In every single one, amber happens if and only if the row ended up holding a concern.
    @Test func amberHappensIfAndOnlyIfTheRowHoldsOneOfTheNine() {
        var rowsChecked = 0
        var amberSeen = 0

        let concernSets: [[SecurityConcern]] =
            [[]] + SecurityConcern.allCases.map { [$0] } + [SecurityConcern.allCases]

        for topic in SecurityTopic.allCases {
            for why in [Unreadable?.none] + Unreadable.allCases.map(Optional.init) {
                for concerns in concernSets {
                    for measure in [String?.none, "7 apps"] {
                        let row = SecurityRow(topic: topic,
                                              headline: "A sentence.",
                                              measure: measure,
                                              concerns: concerns,
                                              unreadable: why)
                        rowsChecked += 1
                        if row.severity == .attention { amberSeen += 1 }

                        #expect(row.severity == (row.concerns.isEmpty ? .information : .attention),
                                "\(topic.rawValue)/\(why?.rawValue ?? "read") found another way in")
                        #expect(row.severity != .problem, "Security has no red")
                        #expect(row.status == (row.concerns.isEmpty
                                               ? (why == nil ? .good : .notChecked)
                                               : .needsAttention))
                    }
                }
            }
        }

        // A guard against the loop quietly enumerating nothing — a vacuous pass is the failure
        // this whole file is written to avoid.
        #expect(rowsChecked == SecurityTopic.allCases.count * 4 * concernSets.count * 2)
        #expect(amberSeen > 0, "not one row went amber — the enumeration proved nothing")
    }

    /// ⚠️ **A row we could not read is never amber, whatever a reader hands in.** Nine concerns and
    /// three refusals, all thirty-six combinations: the concern is dropped, the figure is dropped,
    /// and the row reports Not checked instead of a finding about a Mac nobody looked at.
    @Test func anUnreadRowCannotBeMadeAmberByAnyConcern() {
        for why in Unreadable.allCases {
            for concern in SecurityConcern.allCases {
                let row = SecurityRow(topic: concern.topic,
                                      headline: "ignored",
                                      measure: "0 apps",
                                      concerns: [concern],
                                      unreadable: why)
                #expect(row.concerns.isEmpty)
                #expect(row.measure == nil, "an unread row kept a figure — it prints as a zero")
                #expect(row.severity == .information)
                #expect(row.status == .notChecked)
            }
        }
    }

    /// Every `Protection` the vocabulary can express — eight switches × four states × set or not —
    /// and the concerns that come out of all of them are inside the nine, with none invented.
    @Test func noProtectionCanRaiseAnythingOutsideTheNine() {
        var raised = Set<SecurityConcern>()

        for kind in ProtectionKind.allCases {
            for state in Self.everyState {
                for organisation in [false, true] {
                    let protection = Protection(kind: kind,
                                                state: state,
                                                setByOrganisation: organisation)
                    guard let concern = protection.concern else { continue }
                    raised.insert(concern)

                    #expect(SecurityConcern.allCases.contains(concern))
                    #expect(!organisation, "an organisation's setting reached the user as a fault")
                    #expect(protection.isProtecting == false)
                    #expect(concern.protection == kind)
                }
            }
        }

        // Seven of the nine are reachable this way; the last two belong to apps. Lockdown Mode is
        // the switch that reaches nothing, because nothing on this Mac can read it.
        #expect(raised == Set(ProtectionKind.allCases.compactMap(\.concern)))
        #expect(raised.count == 7)
    }

    /// And every `Grant` — twelve permissions × three signature standings × installed or not.
    /// Exactly two of the nine are reachable, and holding a permission is not one of them.
    @Test func noGrantCanRaiseAnythingOutsideTheNine() {
        var raised = Set<SecurityConcern>()
        var quiet = 0

        for permission in Permission.allCases {
            for signature in SignatureStanding.allCases {
                for installed in [true, false] {
                    let grant = Grant(appName: "Something",
                                      bundleID: "com.example.something",
                                      permission: permission,
                                      stillInstalled: installed,
                                      signature: signature)
                    guard let concern = grant.concern else { quiet += 1; continue }
                    raised.insert(concern)
                    #expect(SecurityConcern.allCases.contains(concern))
                }
            }
        }

        #expect(raised == [.signatureChangedSinceApproved, .permissionHeldByMissingApp])
        // ⚠️ **Holding a permission is not a finding.** Most of the space is silent, and it has to
        // be: a list where every row is amber is a list nobody reads.
        #expect(quiet > raised.count * 3)
    }

    /// A report's own colour comes from the same nine and nowhere else — including the case that
    /// matters most, a run where every row was read and every row was clean.
    @Test func aReportGoesAmberOnlyByCarryingOneOfTheNine() {
        let clean = SecurityReport(block: .unknown, rows: SecurityTopic.allCases.map {
            SecurityRow(topic: $0, headline: "Nothing here needs you.")
        }, measuredDays: 11)
        #expect(clean.concerns.isEmpty)
        #expect(clean.status == .good)
        #expect(clean.overviewFinding == nil)

        for concern in SecurityConcern.allCases {
            let flagged = SecurityReport(block: .unknown, rows: [
                SecurityRow(topic: concern.topic, headline: "One thing.", concerns: [concern]),
            ], measuredDays: 11)
            #expect(flagged.concerns == [concern])
            #expect(flagged.status == .needsAttention)
            #expect(flagged.overviewFinding?.severity == .attention)
            #expect(flagged.overviewFinding?.severity != .problem)
        }
    }

    private static let everyState: [ProtectionState] =
        [.on, .off, .reduced] + Unreadable.allCases.map(ProtectionState.unreadable)
}

// MARK: - The words the nine are allowed to use

@Suite struct SecurityConcernWordingTests {

    /// ⚠️ **No imperatives, on any of the nine.** The section states what is true and offers the
    /// pane; it never tells somebody what to do about their own Mac — and on a managed Mac the
    /// person reading cannot act on it at all.
    @Test func notOneOfTheNineGivesAnOrder() {
        let orders = ["you should", "you must", "you need to", "turn on", "turn off",
                      "make sure", "we recommend", "please "]
        for concern in SecurityConcern.allCases {
            let words = "\(concern.title) \(concern.explanation)".lowercased()
            for order in orders {
                #expect(!words.contains(order), "\(concern.rawValue) says “\(order)”")
            }
        }
    }

    /// ⚠️ **"Safe" is never a verdict, anywhere in the vocabulary.** Not in a concern, not on a
    /// switch, not on a topic, not on a permission. Wellkept is not watching in real time, and the
    /// one sentence that would make somebody stop looking is the one this section may never print.
    @Test func nothingInTheVocabularyCallsThisMacSafe() {
        var everyString: [String] = []
        for concern in SecurityConcern.allCases { everyString += [concern.title, concern.explanation] }
        for topic in SecurityTopic.allCases { everyString += [topic.label, topic.explanation] }
        for kind in ProtectionKind.allCases { everyString += [kind.label, kind.explanation] }
        for permission in Permission.allCases { everyString += [permission.label, permission.explanation] }

        for words in everyString {
            let lower = words.lowercased()
            #expect(!lower.contains("safe"), "“\(words)” calls something safe")
            #expect(!lower.contains("you are protected"))
        }
        #expect(everyString.count > 60, "the sweep looked at almost nothing")
    }

    /// A row and a concern both have to say something, and neither may reach a screen as an
    /// identifier.
    @Test func everythingInTheVocabularyHasWordsOfItsOwn() {
        for concern in SecurityConcern.allCases {
            #expect(!concern.title.isEmpty)
            #expect(!concern.explanation.isEmpty)
        }
        for kind in ProtectionKind.allCases {
            #expect(!kind.label.isEmpty)
            #expect(!kind.explanation.isEmpty)
            #expect(kind.label != kind.rawValue)
        }
        #expect(Set(SecurityConcern.allCases.map(\.title)).count == 9, "two of the nine read alike")
    }
}
