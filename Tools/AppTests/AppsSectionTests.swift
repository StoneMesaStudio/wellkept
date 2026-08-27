import Foundation
import Testing
import WellkeptCore

//  AppsSectionTests.swift
//  Wellkept — Tools/AppTests
//
//  **The Apps screen's own contracts: the two demo Macs, the five rows, and the four things this
//  section is not allowed to say.**
//
//  These live in `Tools/AppTests` because it is the only bundle that compiles `App` — `DemoData`,
//  `AppsModel`, `UpdatesRow`, `MacOSRow` and `SelfUpdatingApps` are all app-target types, and
//  `WellkeptTests` links only `WellkeptCore`.
//
//  ## What is worth testing here, and what is not
//
//  The five readers have their own suites and they test the reading. Nothing here reads this Mac.
//  What is tested here is what the **screen** promises, which is a different set of claims and
//  almost all of them are about words and arithmetic:
//
//  - **A count never appears without its denominator.**
//  - **Nothing in this section is ever amber**, however out of date the Mac.
//  - **"Keeps itself up to date" is never said about an app that is not on the list**, because that
//    message and "cannot be checked" are opposites.
//  - **The number on the first line is the number a person recognises**, never 422.
//  - **The demo shows nothing the real readers cannot produce**, which is what makes a screenshot
//    of it evidence rather than an artist's impression.

@Suite("Apps — the section screen and its two demo Macs")
@MainActor
struct AppsSectionTests {

    private var bothMacs: [AppsAnswer] { [DemoData.apps(.healthy), DemoData.apps(.problems)] }

    /// Everything a person could read on the screen for one demo Mac, flattened — the details
    /// behind Options included. A promise about wording that only holds above the fold is not a
    /// promise.
    private func words(_ answer: AppsAnswer) -> [String] {
        var out = [answer.report.summary, answer.report.coverage.sentence,
                   answer.report.tally.sentenceWithCoverage, answer.update.disclosureSentence]
        for row in answer.report.rows {
            out.append(row.headline)
            out.append(row.topic.label)
            out.append(row.topic.explanation)
            if let measure = row.measure { out.append(measure) }
            if let reason = row.reason { out.append(reason) }
            if let remedy = row.remedy { out.append(remedy.title) }
            for pair in row.details { out.append(pair.label); out.append(pair.value) }
        }
        for app in answer.apps {
            out.append(app.name)
            out.append(app.update.label)
            out.append(app.signedBy.label)
            out.append(app.origin.label)
        }
        for crash in answer.crashes { out.append(crash.sentence) }
        for item in answer.leftovers { out.append(item.appName); out.append(item.reason) }
        if let finding = answer.report.overviewFinding {
            out.append(finding.title)
            out.append(finding.reason)
        }
        return out
    }

    // MARK: - The five rows

    /// ⚠️ **Every row every time, in `AppsTopic` order, on a Mac where nothing has happened.**
    ///
    /// Worst-first is right for a list of findings and wrong for a fixed panel. A person who learns
    /// that updates are the third row should find them there next week, on a Mac where nothing
    /// happens to have an update.
    @Test("Both demo Macs draw all five rows in the declared order")
    func fiveRowsInOrder() {
        for answer in bothMacs {
            #expect(answer.report.rows.map(\.topic) == AppsTopic.allCases,
                    "the rows are not the five topics in their declared order")
        }
    }

    // MARK: - ⭐ Nothing here is ever amber

    /// ⚠️ **The ruling of 2026-08-27, checked by a machine.** Without vulnerability data an old app
    /// is not dangerous, and a version behind is not something wrong. `AppsRow.severity` is a
    /// computed constant and `AppsReport` builds its Overview row with a literal — so if this ever
    /// fails, somebody has reached past both.
    @Test("No row, no report and no Overview row in Apps is ever above information")
    func nothingIsEverAmber() {
        for answer in bothMacs {
            for row in answer.report.rows {
                #expect(row.severity == .information,
                        Comment(rawValue: "\(row.topic.label) raised \(row.severity.label)"))
                #expect(row.status != .needsAttention,
                        Comment(rawValue: "\(row.topic.label) went to Needs attention"))
            }
            #expect(answer.report.status != .needsAttention)
            #expect(answer.report.record.status != .needsAttention)
            if let finding = answer.report.overviewFinding {
                #expect(finding.severity == .information,
                        "Apps put a row above information on Overview")
            }
        }
    }

    /// The other half of the same ruling: `.information` is below `.attention`, so `AppState`'s
    /// "what needs you" list never contains an Apps row — which is the correct outcome, not an
    /// oversight.
    @Test("Apps never appears in what needs you")
    func appsNeverNeedsYou() {
        for machine in DemoMachine.allCases {
            let state = AppState()
            state.demoMode = true
            state.demoMachine = machine
            #expect(!state.needsYou.contains { $0.section == .apps },
                    "an Apps row reached the list of things that need a person")
        }
    }

    // MARK: - ⭐ A count never travels without its denominator

    /// The summary is the section's own line, and it is where the count and the coverage are welded
    /// together. It may never be a bare count.
    @Test("The summary carries both the app count and the coverage")
    func summaryCarriesCoverage() {
        for answer in bothMacs {
            let summary = answer.report.summary
            #expect(summary.contains("\(answer.apps.count) apps are installed"),
                    Comment(rawValue: "the summary does not open with the count: \(summary)"))
            #expect(summary.contains(answer.report.tally.sentenceWithCoverage),
                    Comment(rawValue: "the summary dropped its coverage: \(summary)"))
        }
    }

    /// ⚠️ **The Overview line always carries its denominator.** "4 apps are out of date" is true and
    /// leaves out the eleven nobody could check — in the direction that makes the app look more
    /// capable than it is.
    @Test("The Overview row's reason names how many apps were actually checked")
    func overviewRowCarriesItsDenominator() {
        for answer in bothMacs {
            guard let finding = answer.report.overviewFinding else { continue }
            #expect(finding.reason.contains("we could check"),
                    Comment(rawValue: "no denominator on the Overview row: \(finding.reason)"))
        }
    }

    /// The figure beside the Updates row is a pair, never a bare count.
    @Test("The Updates row's figure is a count over its denominator")
    func updateMeasureIsAPair() {
        for answer in bothMacs {
            guard let row = answer.report.row(.updates), let measure = row.measure else { continue }
            #expect(measure.contains(" of "),
                    Comment(rawValue: "the Updates figure is a bare number: \(measure)"))
        }
    }

    /// ⚠️ **The coverage sentence is next to the result, not behind Options.** It is inside the row's
    /// own headline, so there is no edit that drops it without deleting the row's answer.
    @Test("The Updates row's headline states the coverage")
    func coverageIsOnTheRow() {
        for answer in bothMacs {
            guard let row = answer.report.row(.updates) else { continue }
            #expect(row.headline == answer.report.tally.sentenceWithCoverage,
                    Comment(rawValue: "the Updates headline is not the coverage sentence: \(row.headline)"))
        }
    }

    /// ⚠️ **The account of what left this Mac appears once on the row.**
    ///
    /// It was in two places for one render on 2026-08-27 — inside the Updates row's reason and again
    /// as the sentence drawn under it — and the two paragraphs sat one line apart saying exactly the
    /// same thing. DESIGN §8: never say the same thing twice on one screen. This is the cheapest
    /// possible guard against it coming back.
    @Test("The account of what was sent is not repeated on the row it sits under")
    func whatWasSentIsSaidOnce() {
        for answer in bothMacs {
            guard let row = answer.report.row(.updates) else { continue }
            #expect(row.reason?.contains(answer.update.disclosureSentence) != true,
                    "the Updates row prints the disclosure sentence twice")
            for pair in row.details {
                #expect(pair.value != answer.update.disclosureSentence,
                        "the disclosure sentence is repeated behind Options as well")
            }
        }
    }

    // MARK: - ⭐ Two opposite messages, never collapsed

    /// ⚠️ **"Keeps itself up to date" and "cannot be checked" are opposites.** Collapsing them makes
    /// a working Mac look neglected. This checks the stronger half: nothing may claim the first
    /// message unless `SelfUpdatingApps` actually says so.
    @Test("Only apps on the self-updating list are said to keep themselves up to date")
    func selfUpdatingIsNeverAsserted() {
        for answer in bothMacs {
            for app in answer.apps where app.update == .keepsItselfUpToDate {
                #expect(SelfUpdatingApps.isSelfUpdating(bundleID: app.bundleID),
                        Comment(rawValue: "\(app.name) claims to update itself and is not on the list"))
            }
        }
    }

    /// And the other half: an app that updates itself is not counted as one nobody could check.
    @Test("Self-updating apps are counted apart from the ones we could not check")
    func selfUpdatingIsNotAGap() {
        for answer in bothMacs {
            let coverage = answer.report.coverage
            let selfUpdating = answer.apps.filter { $0.update == .keepsItselfUpToDate }.count
            #expect(coverage.selfUpdating == selfUpdating)
            #expect(coverage.checked + coverage.selfUpdating + coverage.unchecked == coverage.checkable,
                    "the three coverage numbers do not add up to the apps in scope")
        }
    }

    // MARK: - ⭐ The number a person recognises

    /// ⚠️ **422 is the number a naive tool prints and it is wrong by a factor of three.** The count
    /// on the first line is the Applications folders; everything else is one sentence saying where
    /// it went.
    @Test("The count on the first line is the apps, never the bundles")
    func theCountIsTheAppsAPersonRecognises() {
        for answer in bothMacs {
            let installed = answer.report.row(.installed)
            #expect(installed?.measure == "\(answer.apps.count) apps")
            // The other bundles exist, are stated, and are not counted as apps.
            //
            // ⚠️ **Where they are stated moved on 2026-08-27, and the reason is the point.** The
            // "What is installed" panel sits an inch above this row and says the count, the
            // origins and where the other bundles went. The row was saying all of it a second
            // time — the same paragraph twice on one screen, which is exactly what the house rule
            // forbids. It was caught by looking at a rendered picture, not by a test, so this test
            // now asserts the fact is said **once**: in the panel, not on the row.
            if let others = answer.report.inventory.otherBundles {
                #expect(others > answer.apps.count, "the demo's other-bundle figure is implausible")
                #expect(InventoryReader.reason(answer.report.inventory,
                                               bundledWithMacOS: answer.bundledWithMacOS)
                            .contains("\(others)"),
                        "the sentence that says where the other bundles went has been lost entirely")
                #expect(installed?.reason == nil,
                        "the row is repeating what the panel above it already said")
            }
        }
    }

    // MARK: - ⭐ Nothing the real readers cannot produce

    /// ⚠️ The rule that makes a screenshot of the demo evidence rather than an artist's impression.
    /// `.newerAvailable` cannot exist without a version — the type sees to that — so what is left to
    /// check is that the versions are real strings and that the arithmetic the section prints is the
    /// arithmetic the list supports.
    @Test("Every demo standing is one a reader could have reached")
    func demoStandingsAreProducible() {
        for answer in bothMacs {
            for app in answer.apps {
                if let newer = app.update.newerVersion {
                    #expect(!newer.isEmpty, Comment(rawValue: "\(app.name) has an empty newer version"))
                    #expect(app.version != nil,
                            Comment(rawValue: "\(app.name) is behind a version it has no version to compare"))
                }
                if app.update == .couldNotTell(.testFlightBuild) {
                    #expect(UpdateReader.isTestFlightBuild(app),
                            Comment(rawValue: "\(app.name) is called a test build and is not signed like one"))
                }
                if app.update == .couldNotTell(.shipsWithMacOS) {
                    #expect(app.origin == .bundledWithMacOS || app.addedByHand,
                            Comment(rawValue: "\(app.name) is said to ship with macOS and does not"))
                }
            }
            // Derived, so they cannot disagree with the list they are about.
            #expect(answer.report.tally == UpdateTally.measuring(answer.apps))
            #expect(answer.report.coverage == UpdateCoverage.measuring(answer.apps))
        }
    }

    /// The demo is cached, so an `AppsReport`'s Overview row keeps its identity between draws. A
    /// `Finding` with a fresh `UUID` on every redraw is how a list animates itself to pieces.
    @Test("The demo answer is the same object twice")
    func theDemoIsStable() {
        for machine in DemoMachine.allCases {
            #expect(DemoData.apps(machine).report.overviewFinding?.id
                    == DemoData.apps(machine).report.overviewFinding?.id)
            #expect(DemoData.apps(machine).report.ranAt == DemoData.apps(machine).report.ranAt)
        }
    }

    // MARK: - The healthy Mac

    /// **A tidy list, a couple of updates, and honest coverage** — the case the product exists to be
    /// able to show, and the one worth reading hardest.
    @Test("The healthy Mac has updates waiting and admits what it could not check")
    func theHealthyMac() {
        let answer = DemoData.apps(.healthy)
        let coverage = answer.report.coverage

        #expect(answer.report.tally.newerAvailable == 2, "the healthy Mac should show a couple")
        #expect(coverage.checked < coverage.checkable,
                "the healthy Mac claims complete coverage, which is the flattering lie")
        #expect(coverage.unchecked > 0, "nothing is admitted as unchecked")
        #expect(coverage.selfUpdating > 0, "no app is shown looking after itself")

        // Nothing crashed and nothing was left behind — and both rows are still drawn.
        #expect(answer.crashes.isEmpty)
        #expect(answer.leftovers.isEmpty)
        #expect(answer.report.row(.stoppedWorking) != nil)
        #expect(answer.report.row(.removedLeftovers) != nil)

        // ⚠️ Safari is added by hand, and the row says so. A list that quietly contains a row macOS
        // did not report is a list nobody can check.
        #expect(answer.report.inventory.addedByHand.map(\.name) == ["Safari"])
        #expect(answer.report.row(.installed)?.headline.contains("added it by hand") == true)
    }

    /// ⚠️ **108 crash files reduce to zero real crashes**, and the healthy Mac has to show that the
    /// filtering happened rather than that the folder was empty.
    @Test("The healthy Mac saw crash files and reported no crashes")
    func theQuietCrashFolder() {
        let answer = DemoData.apps(.healthy)
        let row = answer.report.row(.stoppedWorking)
        #expect(answer.crashes.isEmpty)
        #expect(row?.reason?.contains("78") == true,
                Comment(rawValue: "the row does not say how many files it read: \(row?.reason ?? "")"))
        #expect(row?.headline.contains("No app on this Mac has stopped working") == true)
    }

    // MARK: - The Mac with problems

    /// **The four things nobody building this will otherwise see**: an app that stopped working over
    /// and over, several updates, an Intel-only app, and two removed apps that left things behind.
    @Test("The unwell Mac exercises the paths a real Mac will not")
    func theUnwellMac() {
        let answer = DemoData.apps(.problems)

        // An app that stopped working repeatedly.
        #expect(answer.crashes.count == 1)
        #expect(answer.crashes.first?.crashes == 5)
        #expect(answer.crashes.first?.appName == "Microsoft Teams")

        // Several updates.
        #expect(answer.report.tally.newerAvailable >= 3)

        // One Intel-only app, as a plain labelled fact.
        #expect(answer.report.inventory.intelOnly.map(\.name) == ["Audacity"])

        // Two removed apps, each with its own size and no total anywhere.
        #expect(answer.leftovers.count == 2)
        #expect(Set(answer.leftovers.map(\.appName)) == ["Super Duper", "Evernote"])
        for item in answer.leftovers {
            #expect(!item.reason.isEmpty, "a flagged item with no reason is an accusation")
        }
    }

    /// ⚠️ **The guards are the product on the leftovers row.** An updater belonging to an installed
    /// browser, filed under a name that app has never used, is exactly what a name-matching cleaner
    /// offers to delete — so both demo Macs carry one and neither reports it.
    @Test("Neither demo Mac calls an installed app's files a leftover")
    func theGuardsHold() {
        for answer in bothMacs {
            let named = answer.leftovers.compactMap(\.bundleID)
            #expect(!named.contains("com.google.Keystone"),
                    "Chrome's updater was reported as a removed app's leftovers")
            #expect(!named.contains { $0.hasPrefix("com.apple.") },
                    "macOS's own files were reported as leftovers")
            for app in answer.apps {
                #expect(!named.contains(app.bundleID),
                        Comment(rawValue: "\(app.name) is installed and its files were called leftovers"))
            }
        }
    }

    /// ⚠️ **Never totalled.** Name-matching on the measured Mac produces 7.6 GB against about 350 MB
    /// genuinely orphaned. Each item carries its own size; there is no section-wide figure, and the
    /// row's measure counts apps rather than bytes.
    @Test("The leftovers row counts apps, never bytes")
    func leftoversAreNeverTotalled() {
        for answer in bothMacs {
            guard let row = answer.report.row(.removedLeftovers), let measure = row.measure
            else { continue }
            #expect(measure.hasSuffix("app") || measure.hasSuffix("apps"),
                    Comment(rawValue: "the leftovers figure is not a count of apps: \(measure)"))
            for unit in ["GB", "MB", "KB", "bytes"] {
                #expect(!measure.contains(unit),
                        Comment(rawValue: "the leftovers figure is a size: \(measure)"))
            }
        }
    }

    // MARK: - Intel-only is a fact, not a countdown

    /// ⚠️ **Deliberately the other way round from Hardware's ruling on security updates.** Nothing
    /// about a Rosetta app is a security matter, macOS 26.4 already warns at launch, and only the
    /// developer can act. So it is never a problem, never a countdown, and never says the app will
    /// stop working.
    @Test("Nothing anywhere in Apps threatens that an app will stop working")
    func intelOnlyIsNeverACountdown() {
        let banned = ["will stop working", "no longer supported", "stop working soon",
                      "end of life", "unsupported"]
        for answer in bothMacs {
            for sentence in words(answer) {
                for phrase in banned {
                    #expect(!sentence.lowercased().contains(phrase),
                            Comment(rawValue: "Apps threatened something: \(sentence)"))
                }
            }
        }
    }

    /// The Intel-only app is still stated plainly. A rule against alarm is not a rule against
    /// saying it.
    @Test("The Intel-only app is counted on the block that lists what is installed")
    func intelOnlyIsStillSaid() {
        let answer = DemoData.apps(.problems)
        let pairs = answer.report.inventory.detailPairs
        #expect(pairs.contains { $0.label == "Built for Intel only" && $0.value == "1" })
    }

    // MARK: - macOS's own row

    /// ⚠️ **Wellkept never asks Apple whether an update is waiting**, so the row may never imply it
    /// knows. The caveat travels with every state of the row.
    @Test("The macOS row always says what only Software Update can answer")
    func theMacOSRowNeverClaimsToKnow() {
        for answer in bothMacs {
            let row = MacOSRow.row(answer.macOS)
            #expect(row.reason?.contains(MacOSUpdateState.waitingCaveat) == true,
                    "the macOS row dropped the caveat that keeps its past tense honest")
        }
        // Including on a Mac whose settings file cannot be read at all.
        let blind = MacOSUpdateState.make(settings: nil, managed: nil,
                                          systemVersion: ["ProductVersion": "26.6.2",
                                                          "ProductBuildVersion": "25G83"])
        let row = MacOSRow.row(blind)
        #expect(row.headline.contains("26.6.2"), "the version is known and was thrown away")
        #expect(row.reason?.contains(MacOSUpdateState.waitingCaveat) == true)
    }

    // MARK: - ⭐ The answer when consent is withheld

    /// ⚠️ **Saying no is a supported way to run this section**, and it is not a failure.
    ///
    /// The row is not an `Unreadable` — nothing refused us and nothing broke, somebody answered a
    /// question — so the section keeps its `Good` chip, still lists everything installed, and says
    /// plainly that nothing about this Mac was named to anybody.
    @Test("With update checking off, the section still works and nothing was sent")
    func withheldConsentStillWorks() {
        let apps = DemoData.apps(.healthy).apps.map { $0.withUpdate(.notChecked) }
        let inventory = AppsInventory(apps: apps, otherBundles: 274)
        let update = UpdateReader.Answer(standings: [:], namedToAppStore: [],
                                         consent: .declined, casksRead: 0)
        let row = UpdatesRow.row(inventory: inventory, update: update)

        #expect(row.unreadable == nil, "a person's answer was dressed up as a machine's refusal")
        #expect(row.status == .good)
        #expect(row.measure == nil, "a figure was printed for a check nobody ran")
        #expect(row.headline.contains("off"))
        // The confirmation that nothing left this Mac is drawn under the row, from the reader's own
        // sentence — once, on the row, and not repeated in the reason beside it.
        #expect(update.disclosureSentence.contains("Nothing was sent"),
                Comment(rawValue: "no confirmation that nothing left: \(update.disclosureSentence)"))
        #expect(row.reason?.contains("Nothing was sent") != true,
                "the account of what was sent is printed twice on one row")

        // And every app's own line reads "Not checked", never "current".
        for app in apps {
            #expect(app.update.label == "Not checked")
            #expect(!app.update.wasChecked)
        }

        let report = AppsReport(inventory: inventory, rows: [row])
        #expect(report.coverage.checkable == 0, "apps were counted as checkable when nothing was")
        #expect(report.overviewFinding == nil, "Apps sent Overview a row about a check nobody ran")
    }

    // MARK: - The search field

    /// It matches the four fields on the line and **not** the update standing. Typing "current"
    /// would otherwise return every app that is, which looks like a filter and is not one.
    @Test("Search looks at the name, the identifier, the signer and the version only")
    func searchMatchesTheLineAndNotTheProse() {
        let app = InstalledApp(name: "Transmit",
                               bundleID: "com.panic.Transmit",
                               version: "5.10.6",
                               signedBy: .developer("Panic, Inc."),
                               origin: .developerID,
                               update: .current)
        #expect(InstalledAppsList.matches(app, "transmit"))
        #expect(InstalledAppsList.matches(app, "PANIC"))
        #expect(InstalledAppsList.matches(app, "5.10"))
        #expect(InstalledAppsList.matches(app, "com.panic"))
        #expect(!InstalledAppsList.matches(app, "current"))
        #expect(!InstalledAppsList.matches(app, "developer"))
    }

    // MARK: - The stages

    /// One stage per reader, in the section's own row order, so the "step 3 of 5" beside the spinner
    /// cannot drift from the rows filling in above it.
    @Test("The in-flight stages are the five topics in order")
    func stagesMatchTheRows() {
        #expect(AppsModel.Stage.allCases.map(\.topic) == AppsTopic.allCases)
        #expect(AppsModel.Stage.count == AppsTopic.allCases.count)
        for stage in AppsModel.Stage.allCases {
            #expect(!stage.sentence.isEmpty)
        }
    }

    /// ⚠️ **Apps does not run on launch.** A fresh model has read nothing, and nothing but a press
    /// may change that — the inventory call alone is 7–8 seconds.
    @Test("A fresh model has read nothing")
    func nothingRunsOnItsOwn() {
        let model = AppsModel()
        #expect(model.answer == nil)
        #expect(!model.isChecking)
        #expect(model.stage == nil)
    }

    /// ⚠️ **Demo mode may never start a real check.** Its whole promise is that nothing on screen
    /// has been read from this Mac.
    @Test("Nothing runs while demo mode is on")
    func demoModeRunsNothing() async {
        let state = AppState()
        state.demoMode = true
        await state.runAppsCheck()
        #expect(state.apps.answer == nil, "a real check ran underneath the invented rows")
        #expect(!state.askingUpdateConsent, "demo mode put the consent question on screen")
    }

    // MARK: - The consent question

    /// It is asked once, on the first press, and the answer is remembered. Either answer starts the
    /// check — saying no is an answer, not a refusal to proceed.
    @Test("The consent answer is a three-state value and notAsked is not declined")
    func consentHasThreeStates() {
        let store = UserDefaults(suiteName: "wellkept.apps.consent.tests")!
        store.removePersistentDomain(forName: "wellkept.apps.consent.tests")

        #expect(UpdateConsent.read(from: store) == .notAsked)
        UpdateConsent.write(.declined, to: store)
        #expect(UpdateConsent.read(from: store) == .declined)
        #expect(UpdateConsent.read(from: store) != .notAsked)
        UpdateConsent.write(.allowed, to: store)
        #expect(UpdateConsent.read(from: store).isAllowed)
        UpdateConsent.write(.notAsked, to: store)
        #expect(store.object(forKey: UpdateConsent.key) == nil,
                "forgetting the answer left a value behind, so the third state is unreachable")

        store.removePersistentDomain(forName: "wellkept.apps.consent.tests")
    }

    /// The key the answer is stored under comes from the privacy register, and the uninstaller knows
    /// about it. A setting the uninstaller does not know about is a setting that survives an
    /// uninstall.
    @Test("The consent key is the register's, and the uninstaller removes it")
    func theConsentKeyIsAccountedFor() {
        #expect(UpdateConsent.key == "checkAppUpdates")
        #expect(StorageManifest.Keys.all.contains(UpdateConsent.key),
                "the update-checking answer would survive an uninstall")
    }
}
