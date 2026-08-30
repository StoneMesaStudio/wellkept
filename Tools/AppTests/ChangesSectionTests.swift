import Foundation
import Testing
import WellkeptCore

//  ChangesSectionTests.swift
//  Wellkept — Tools/AppTests
//
//  **The Changes screen's own contracts: the two demo Macs, the catalogue's destinations, and the
//  four things this section is not allowed to do.**
//
//  These live in `Tools/AppTests` because it is the only bundle that compiles `App` — `DemoData`,
//  `ChangesModel`, `Diff` and `SystemSettingsPane` are all app-target types, and `WellkeptTests`
//  links only `WellkeptCore`.
//
//  ## What is tested here, and what is not
//
//  `ChangesEngineTests` tests the reading, the record and the arithmetic. Nothing here reads this
//  Mac. What is tested here is what the **screen** promises, and all of it is about words and
//  restraint:
//
//  - **No app is ever named as the cause of anything**, in either demo Mac, anywhere.
//  - **Nothing offers to change a setting.** Every destination is a System Settings pane that
//    actually resolves, and the one row that reaches Overview carries no verb at all.
//  - **What cannot be explained is counted, never listed.**
//  - **A change is not by itself a fault** — and a switch an organisation holds is never raised.

@Suite("Changes — the section screen and its two demo Macs")
@MainActor
struct ChangesSectionTests {

    private var bothMacs: [ChangesReport] {
        [DemoData.changes(.healthy), DemoData.changes(.problems)]
    }

    /// Everything a person could read on the screen for one demo Mac, flattened — including the
    /// three sentences on every change, because a promise about wording that only holds above the
    /// fold is not a promise.
    private func words(_ report: ChangesReport) -> [String] {
        var out = [report.summary]
        for change in report.ordered {
            out.append(change.what)
            out.append(change.from)
            out.append(change.to)
            out.append(change.sentence(now: report.ranAt))
            out.append(change.cause.clause)
            if let watched = Watched.of(change.key) {
                out.append(watched.title)
                out.append(contentsOf: watched.description.sentences)
            }
        }
        for topic in ChangesTopic.allCases {
            out.append(topic.label)
            out.append(topic.explanation)
        }
        if let finding = report.overviewFinding {
            out.append(finding.title)
            out.append(finding.reason)
        }
        return out
    }

    // MARK: - ⛔ Never who

    /// ⛔ **The one thing this section may never do.**
    ///
    /// Nothing an unprivileged app can read on macOS records which process wrote a setting. So no
    /// sentence either demo Mac can produce may attribute a change to a piece of software — that
    /// would be an accusation on no evidence, and it would be wrong often.
    ///
    /// The four clauses below are the complete set `Cause` can produce, and the test pins them: a
    /// fifth one appearing in the demo means somebody built a sentence by hand.
    @Test("Neither demo Mac ever says an app changed anything")
    func noAppIsEverNamedAsTheCause() {
        let allowed = Set([Cause.whileYouWereUsingTheMac.clause,
                           Cause.setByAnOrganisation.clause,
                           Cause.unknown.clause])
        for report in bothMacs {
            for change in report.changes {
                let clause = change.cause.clause
                if case .duringMacOSUpdate = change.cause {
                    #expect(clause.contains("while your Mac was off for the macOS")
                            || clause.contains("in the same period as the macOS"),
                            Comment(rawValue: "Unexpected update clause: \(clause)"))
                    // ⭐ *changed during*, never *the update changed it*.
                    #expect(!clause.lowercased().contains("the update changed"))
                } else {
                    #expect(allowed.contains(clause),
                            Comment(rawValue: "A cause clause nobody wrote: \(clause)"))
                }
            }
        }
    }

    /// The app names that do appear are apps that **hold** a permission, which is what the reader
    /// actually knows. None of them appears in a sentence about why something moved.
    @Test("An app's name appears on what it holds, never on why something moved")
    func anAppIsNamedOnlyForWhatItHolds() {
        let unwell = DemoData.changes(.problems)
        let gained = unwell.changes(in: .whoCanWatch)
        #expect(gained.count == 1)
        #expect(gained.first?.what.contains("Sample Remote") == true)

        for change in unwell.changes {
            #expect(!change.cause.clause.contains("Sample Remote"))
            #expect(!change.cause.clause.contains("Zoom"))
        }
    }

    // MARK: - ⛔ Nothing here changes anything

    /// ⛔ **Decided 2026-08-28: Wellkept writes no setting, ever.** The row's only control is a
    /// destination, so the row Overview gets carries no verb at all — Overview is not where
    /// somebody should be sent to System Settings.
    @Test("The row that reaches Overview offers no verb")
    func nothingOffersToChangeASetting() {
        for report in bothMacs {
            #expect(report.overviewFinding?.verb == nil)
        }
    }

    /// **Every destination in the catalogue resolves to a real pane.**
    ///
    /// `Watched.settingsPane` is a `String` because `WellkeptCore` cannot see the app layer's
    /// `SystemSettingsPane`. That is the right dependency and it costs exactly one thing: nothing
    /// checks the spelling. This is that check, and without it a typo would ship as a button that
    /// silently opens the wrong pane — which still opens *a* pane, so nobody would report it.
    @Test("Every settings destination in the catalogue is a real pane")
    func everyDestinationResolves() {
        for watched in Watched.all {
            guard let raw = watched.settingsPane else { continue }
            #expect(SystemSettingsPane(rawValue: raw) != nil,
                    Comment(rawValue: "\(watched.title) points at a pane that does not exist: \(raw)"))
        }
    }

    /// Every pane the catalogue points at has button words that name where it goes — because a
    /// button called "Fix" on a screen that changes nothing would be a lie about what pressing it
    /// does.
    @Test("Every destination's button names the pane it opens")
    func everyButtonNamesItsDestination() {
        for watched in Watched.all {
            guard let raw = watched.settingsPane,
                  let pane = SystemSettingsPane(rawValue: raw) else { continue }
            let words = ConcernView.words(for: pane)
            #expect(words.hasPrefix("Open"))
            #expect(!words.lowercased().contains("fix"))
            #expect(!words.lowercased().contains("turn on"))
        }
    }

    // MARK: - A quiet Mac

    /// **The case the product exists to be able to show.** One macOS update, two harmless things
    /// that moved during it, nothing amber, and the check saw everything.
    @Test("The healthy demo Mac is a quiet journal with nothing amber")
    func theHealthyMacIsQuiet() {
        let report = DemoData.changes(.healthy)
        #expect(!report.isFirstLook)
        #expect(report.changes.count == 2)
        #expect(report.worst == .information)
        #expect(report.status == .good)
        #expect(report.complete)
        #expect(report.macWasOffOrAsleep)

        let versions = report.changes(in: .macOSItself)
        #expect(versions.count == 1)
        #expect(versions.first?.from == "26.6.1")
        #expect(versions.first?.to == "26.6.2")
    }

    /// ⭐ **The strongest sentence this section has**, and the wording is the whole point: a
    /// coincidence in time, stated as one, with the outage measured to the second.
    @Test("The healthy Mac carries the update sentence, with the seconds it measured")
    func theUpdateSentenceIsACoincidenceStatedAsOne() {
        let report = DemoData.changes(.healthy)
        let sentences = report.ordered.map { $0.cause.clause }
        #expect(sentences.allSatisfy { $0.contains("while your Mac was off for the macOS 26.6.2 update") })
        // ⚠️ "four minutes and 52 seconds", not "fifty-two": `Outage` spells small numbers as words
        // and falls back to digits above twelve rather than inventing English for 143.
        #expect(sentences.allSatisfy { $0.contains("four minutes and 52 seconds") })
    }

    /// The other half of the pair: an outage measured only to the minute never claims seconds.
    @Test("The unwell Mac's outage says about, because that is all it measured")
    func aMinuteResolutionOutageNeverClaimsSeconds() {
        let report = DemoData.changes(.problems)
        let clause = report.ordered.first?.cause.clause ?? ""
        #expect(clause.contains("about six minutes"))
        #expect(!clause.contains("second"))
    }

    // MARK: - A Mac with problems

    /// **The four paths nobody will otherwise see**, all in one window.
    @Test("The unwell demo Mac exercises all four of the paths it exists for")
    func theUnwellMacExercisesItsPaths() {
        let report = DemoData.changes(.problems)

        let firewall = report.changes.first { $0.key == WatchedKey(.protections, "firewall") }
        #expect(firewall?.from == "On")
        #expect(firewall?.to == "Off")
        #expect(firewall?.severity(Watched.of(firewall!.key)) == .attention)

        let profile = report.changes.first {
            $0.key == WatchedKey(.startsOnItsOwn, "configurationProfile")
        }
        #expect(profile?.from == "0")
        #expect(profile?.to == "1")

        let screen = report.changes.first {
            $0.key == WatchedKey(.whoCanWatch, "screenRecording")
        }
        #expect(screen?.from == "Not allowed")
        #expect(screen?.to == "Allowed")
        #expect(screen?.severity(Watched.of(screen!.key)) == .attention)

        #expect(report.status == .needsAttention)
        #expect(report.worst == .attention)
    }

    /// ⚠️ **A switch an organisation holds is stated and never raised.** A Mac configured by an
    /// employer is not a Mac with something wrong with it, and the person reading the screen cannot
    /// act on it.
    @Test("A switch an organisation set is stated, certain, and never amber")
    func anOrganisationsSwitchIsNeverAFault() {
        let report = DemoData.changes(.problems)
        let managed = report.changes.first {
            $0.key == WatchedKey(.protections, "automaticSecurityUpdates")
        }
        #expect(managed != nil)
        #expect(managed?.cause == .setByAnOrganisation)
        #expect(managed?.confidence == .certain)
        #expect(managed?.severity(Watched.of(managed!.key)) == .information)
    }

    /// ⚠️ **Nothing in this section reaches `.problem`, however bad the Mac.** Whether the resulting
    /// state is a problem is Security's question, answered there once.
    @Test("However much moved, nothing here is a problem")
    func nothingIsEverAProblem() {
        for report in bothMacs {
            for change in report.changes {
                #expect(change.severity(Watched.of(change.key)) <= .attention)
            }
            #expect(report.overviewFinding.map { $0.severity <= .attention } ?? true)
        }
    }

    // MARK: - ⭐ Counted, never listed

    /// **The undescribed count is a number in a sentence and never a row.**
    ///
    /// Every change the face can draw has a `Watched` behind it — that is what `Diff.changes`
    /// enforces — so the rows and the count can never overlap. The unwell Mac's 41 is the figure
    /// from the plan, and it is produced by the real arithmetic over two captures rather than typed.
    @Test("What cannot be explained is counted and never drawn as a row")
    func theUndescribedAreCountedNeverListed() {
        #expect(DemoData.changes(.healthy).undescribed == 6)
        #expect(DemoData.changes(.problems).undescribed == 41)

        for report in bothMacs {
            #expect(report.undescribed > 0)
            #expect(report.ordered.count == report.changes.count)
            for change in report.changes {
                #expect(Watched.of(change.key) != nil,
                        Comment(rawValue: "A row with nothing to say about it: \(change.key.storageKey)"))
            }
        }
    }

    /// The count reaches the summary line, in words, without being turned into rows.
    @Test("The summary says how many were not explained")
    func theSummaryCarriesTheCount() {
        #expect(DemoData.changes(.problems).summary.contains("41 other values"))
        #expect(DemoData.changes(.healthy).summary.contains("6 other values"))
    }

    // MARK: - Every change is worth reading

    /// ⭐ **Decided 2026-08-28: our descriptions, and better than the prior art.** Every change the
    /// face can draw carries all three sentences — what it does, what turning it off costs you, and
    /// why it might have changed — and they are three different sentences.
    @Test("Every change on either demo Mac carries all three sentences")
    func everyChangeCarriesItsDescription() {
        for report in bothMacs {
            for change in report.ordered {
                let watched = Watched.of(change.key)
                #expect(watched != nil)
                #expect(watched?.description.isComplete == true,
                        Comment(rawValue: "Incomplete description on \(change.key.storageKey)"))
                #expect(watched?.description.sentences.count == 3)
            }
        }
    }

    /// The demo never leaks a raw storage key onto the screen. Those are file format, not English.
    @Test("No raw storage key ever reaches the screen")
    func noRawKeysOnScreen() {
        for report in bothMacs {
            for sentence in words(report) {
                #expect(!sentence.contains("protections."))
                #expect(!sentence.contains("whoCanWatch."))
                #expect(!sentence.contains("\u{1}"),
                        Comment(rawValue: "A separator character reached the screen: \(sentence)"))
            }
        }
    }

    // MARK: - The row that reaches Overview

    /// ⚠️ **One row, whatever this section found** — a section that posts a row per change turns
    /// Overview into a second copy of itself.
    @Test("However much changed, Changes sends Overview exactly one row")
    func exactlyOneRowReachesOverview() {
        let overview = DemoData.findings(.problems).filter { $0.section == .changes }
        #expect(overview.count == 1)
        #expect(DemoData.changes(.problems).changes.count > 1)
    }

    /// The row keeps its identity between draws. `Finding.id` defaults to a fresh `UUID` and
    /// `overviewFinding` is computed, so without a derived id a list would animate itself to pieces
    /// on every redraw.
    @Test("The Overview row keeps its identity between draws")
    func theOverviewRowIsStable() {
        let first = DemoData.changes(.problems).overviewFinding
        let second = DemoData.changes(.problems).overviewFinding
        #expect(first?.id == second?.id)
        #expect(first == second)
    }

    /// ⚠️ **Nothing is filed on a first look and nothing on a quiet one.** The audit trail already
    /// says both, and a row saying nothing changed is a row that has to be read to learn nothing.
    @Test("A first look and a quiet look both file nothing")
    func aQuietLookFilesNothing() {
        let firstLook = ChangesReport(ranAt: Date(), previous: nil, changes: [])
        #expect(firstLook.overviewFinding == nil)

        let quiet = ChangesReport(ranAt: Date(),
                                  previous: Date().addingTimeInterval(-86_400),
                                  changes: [])
        #expect(quiet.overviewFinding == nil)
    }

    /// The demo's audit line comes out of the report itself, so the chip in the sidebar's audit
    /// trail and the chip on the Changes screen are one fact that cannot drift apart.
    @Test("The demo audit trail takes Changes' line from the report")
    func theAuditLineComesFromTheReport() {
        for machine in DemoMachine.allCases {
            let record = DemoData.records(machine)[.changes]
            #expect(record == DemoData.changes(machine).record)
            #expect(record?.section == .changes)
        }
    }

    // MARK: - The model

    /// ⚠️ **A fresh model has read nothing and is not running.** Changes never runs by itself, so
    /// this is the state on every launch until somebody presses the button — and a model that read
    /// on creation would take eight seconds off every launch and write a snapshot nobody asked for.
    @Test("A fresh model has compared nothing and is not running")
    func aFreshModelHasDoneNothing() {
        let model = ChangesModel()
        #expect(model.report == nil)
        #expect(!model.isChecking)
        #expect(model.stage == nil)
    }

    /// Both stages are named, in the order they happen, and the count matches what the screen
    /// prints beside the spinner.
    @Test("The two stages are in order and the step count matches")
    func theStagesAreInOrder() {
        #expect(ChangesModel.Stage.allCases == [.reading, .comparing])
        #expect(ChangesModel.Stage.reading.step == 1)
        #expect(ChangesModel.Stage.comparing.step == 2)
        #expect(ChangesModel.Stage.count == 2)
        for stage in ChangesModel.Stage.allCases {
            #expect(!stage.sentence.isEmpty)
        }
    }

    // MARK: - The screen says what it watches

    /// **The face has to be able to name everything it compares.** The scope sentence prints the
    /// catalogue's own count, and Options lists every one of them by name — so a catalogue that
    /// grew without the list growing is not possible.
    @Test("Every watched thing belongs to a drawn row and can be named")
    func everyWatchedThingIsReachableFromTheScreen() {
        let drawn = ChangesTopic.allCases.flatMap { Watched.inTopic($0) }
        #expect(drawn.count == Watched.all.count)
        for watched in Watched.all {
            #expect(!watched.title.isEmpty)
            #expect(drawn.contains(watched))
        }
    }
}
