import Foundation
import Testing
import WellkeptCore

//  SweepTests.swift
//  Wellkept — Tools/AppTests
//
//  **"Check my Mac" — the running order, the consent gate, Stop, and the record the sweep files
//  about itself.**
//
//  Here rather than in `WellkeptTests` because `Sweep`, `AppState` and `OverviewWords` are all
//  app-target types and `WellkeptTests` links only `WellkeptCore`. This is the one bundle that
//  compiles `App`.
//
//  ## ⛔ Nothing in this file runs a check against this Mac
//
//  Six real checks are about half a minute of reading the disk, the log store and every installed
//  app — in a test suite that is both slow and dishonest, because the result would depend on the
//  machine the gate happened to run on. So every test here drives either a pure function
//  (`Sweep.skipReason`, `OverviewWords.headline`) or the sweep's own state machine, which holds no
//  results and reads nothing. The one test that touches `AppState.runEverything` does it in demo
//  mode, where it refuses before it starts — which is the thing that test is about.

@Suite("Check my Mac — the sweep", .serialized)
@MainActor
struct SweepTests {

    /// A state that is definitely reading real records rather than the invented Mac.
    ///
    /// ⚠️ **`demoMode` is a stored preference, and under `xctest` "stored" means this process's own
    /// defaults — shared by every suite in the bundle.** A test that ran earlier and left the demo
    /// switch on makes `AppState.records` return `DemoData`, and the next test then asserts about a
    /// Mac that does not exist. This cost two failures the first time this file ran; setting it
    /// explicitly is the whole fix.
    private func realState() -> AppState {
        let app = AppState()
        app.demoMode = false
        return app
    }

    // MARK: - ⭐ The running order

    /// ⚠️ **The test that stops a seventh section being added and silently never checked.**
    ///
    /// `Sweep.order` is written out by hand — the sidebar's order and the cheapest-first order are
    /// different questions — so nothing else guarantees it stays complete. A new `SectionID` that
    /// nobody adds to the order would appear in the sidebar, appear in the audit trail, and never
    /// once be read by the app's main verb.
    @Test("The order is every checkable section, exactly once")
    func everySectionIsInTheOrder() {
        #expect(Set(Sweep.order) == Set(SectionID.checkable),
                "the sweep's order and the app's checkable sections have come apart")
        #expect(Sweep.order.count == SectionID.checkable.count,
                "a section is in the running order twice")
        #expect(!Sweep.order.contains(.overview),
                "Overview is in its own running order — it would check itself for ever")
    }

    /// The order itself, spelled out, because the reasoning behind it is in a file header and a
    /// header cannot fail a build. Cheapest and most reassuring first; the two slowest last.
    @Test("Cheapest and most reassuring first, storage last")
    func theOrderIsCheapestFirst() {
        #expect(Sweep.order == [.hardware, .backup, .security, .changes, .apps, .storage],
                "the running order changed — read the header of RunEverything.swift before agreeing")
        #expect(Sweep.order.last == .storage,
                "the longest and most variable check is no longer last")
    }

    // MARK: - ⭐ Pressing this button is not consent

    /// ⚠️ **The rule the whole feature turns on.** A person who has never been asked whether
    /// Wellkept may check for app updates must not have that question answered for them by
    /// pressing a different button.
    @Test("An unanswered update question means Apps is skipped, with a reason")
    func unansweredConsentSkipsApps() {
        let reason = Sweep.skipReason(for: .apps, consent: .notAsked)
        #expect(reason != nil, "a sweep would have run Apps without anybody having been asked")
        #expect(reason == SweepWords.appsNotAsked)
    }

    /// The reason has to be actionable. A person told their apps were skipped needs the place the
    /// answer is given, or the message is a dead end.
    @Test("The skip names the button that is the answer")
    func theSkipSaysWhereToAnswer() {
        let reason = SweepWords.appsNotAsked
        #expect(reason.contains(SectionID.apps.verb),
                "the skip message does not say where to answer the question")
        #expect(reason.contains(SectionID.overview.verb),
                "the skip message does not name the button that did not count as an answer")
    }

    /// ⚠️ **Declining is an answer, and Apps still runs.** Everything installed, macOS's own
    /// updates, crashes and leftovers are all read without asking anybody anything; only the
    /// per-app update line reads "Not checked". Skipping the section on a "no" would punish the
    /// answer and quietly push people towards yes.
    @Test("Both real answers run Apps")
    func answeringEitherWayRunsApps() {
        #expect(Sweep.skipReason(for: .apps, consent: .allowed) == nil)
        #expect(Sweep.skipReason(for: .apps, consent: .declined) == nil)
    }

    /// Consent is about Apps and about nothing else. A gate that leaked would silently stop a
    /// sweep reading the drive.
    @Test("No other section is ever gated on the update question")
    func noOtherSectionIsGated() {
        for section in SectionID.allCases where section != .apps {
            for answer in UpdateConsent.Answer.allCases {
                #expect(Sweep.skipReason(for: section, consent: answer) == nil,
                        Comment(rawValue: "\(section.title) was gated on the update question"))
            }
        }
    }

    // MARK: - Refusals

    /// ⚠️ Demo mode's whole promise is that nothing on screen was read from this Mac. A sweep
    /// underneath the invented rows would break it six times over.
    @Test("A sweep refuses to start in demo mode")
    func demoModeRefuses() async throws {
        let app = AppState()
        app.demoMode = true
        // ⛔ Asserted before the call, not after. If demo mode had somehow not taken, the next line
        // would read this Mac for half a minute inside the gate — which is precisely the thing
        // this test exists to prove cannot happen.
        try #require(app.demoMode, "demo mode did not take, so the sweep was never asked to refuse")

        await app.runEverything()

        #expect(!app.sweep.isRunning)
        #expect(app.sweep.startedAt == nil, "a sweep started while demo mode was on")
        #expect(app.sweep.steps.isEmpty)
        #expect(app.realRecords.isEmpty, "demo mode filed a real record")

        // Put the shared preference back. Every suite in this bundle reads the same defaults.
        app.demoMode = false
    }

    /// A second press while one is running is ignored rather than queued — the same rule every
    /// section model already keeps for its own button.
    @Test("A sweep refuses to start twice")
    func refusesToStartTwice() async {
        let app = realState()
        let firstStart = Date(timeIntervalSince1970: 1_000)
        app.sweep.begin(at: firstStart)
        app.sweep.enter(.hardware)

        await app.runEverything()

        #expect(app.sweep.startedAt == firstStart, "a second sweep restarted the first one")
        #expect(app.sweep.current == .hardware, "a second sweep moved the running one along")
    }

    // MARK: - The state machine

    /// Everything queued, nothing done, and no memory of the last run's Stop.
    @Test("Beginning a sweep queues every section")
    func beginningQueuesEverything() {
        let sweep = Sweep()
        sweep.begin()

        #expect(sweep.isRunning)
        #expect(!sweep.wasStopped)
        for section in Sweep.order {
            #expect(sweep.step(section) == Sweep.Step.waiting,
                    Comment(rawValue: "\(section.title) was not queued"))
        }
        #expect(!sweep.anythingLanded)
    }

    /// "Section 3 of 6" is a count of sections. **It is not a percentage and it is not a clock** —
    /// which is the only kind of progress figure this app is allowed to print.
    @Test("Position is a count of sections, and it tracks the section being read")
    func positionCountsSections() {
        let sweep = Sweep()
        sweep.begin()
        #expect(sweep.position == nil, "a sweep reported a position before it entered a section")

        sweep.enter(.security)
        #expect(sweep.position == 3, "Security is third in the order")
        #expect(SweepWords.position(3) == "Section 3 of 6")
        #expect(!SweepWords.position(3).contains("%"))
    }

    /// ⚠️ **"It returned" is not "it ran".** Every section model ignores a second call while its own
    /// button already has one in flight, and a cancelled Storage scan keeps the previous answer
    /// rather than filing a new one. So the sweep is told whether anything landed; it never assumes.
    @Test("A section that filed nothing is not marked done")
    func aSectionThatFiledNothingIsNotDone() {
        let sweep = Sweep()
        sweep.begin()

        sweep.enter(.hardware)
        sweep.leave(.hardware, landed: true)
        sweep.enter(.backup)
        sweep.leave(.backup, landed: false)

        #expect(sweep.step(.hardware) == Sweep.Step.done)
        #expect(sweep.step(.backup) == Sweep.Step.unfinished(SweepWords.noResult))
        #expect(sweep.current == nil)
        #expect(sweep.anythingLanded)
    }

    /// ⚠️ **A stopped sweep keeps what already finished.** Stopping is "run no more sections";
    /// nothing that landed is rolled back, and the sections never reached say so rather than
    /// sitting on "waiting" for ever.
    @Test("Stopping keeps what finished and names what was never reached")
    func stoppingKeepsWhatFinished() {
        let sweep = Sweep()
        sweep.begin()
        sweep.enter(.hardware)
        sweep.leave(.hardware, landed: true)

        sweep.requestStop()
        #expect(sweep.stopRequested)
        sweep.end()

        #expect(!sweep.isRunning)
        #expect(sweep.wasStopped)
        #expect(sweep.step(.hardware) == Sweep.Step.done, "a finished section was thrown away by Stop")
        #expect(sweep.step(.storage) == Sweep.Step.unfinished(SweepWords.notReached))
        #expect(sweep.shortfalls.contains { $0.section == .storage })
        #expect(!sweep.shortfalls.contains { $0.section == .hardware })
    }

    /// The skip has to survive the end of the sweep — it is the thing the face prints under the
    /// button afterwards.
    @Test("A skipped section keeps its reason after the sweep ends")
    func aSkipSurvivesTheEnd() {
        let sweep = Sweep()
        sweep.begin()
        sweep.skip(.apps, why: SweepWords.appsNotAsked)
        for section in Sweep.order where section != .apps {
            sweep.enter(section)
            sweep.leave(section, landed: true)
        }
        sweep.end()

        #expect(sweep.step(.apps) == Sweep.Step.skipped(SweepWords.appsNotAsked))
        #expect(sweep.shortfalls.map(\.section) == [.apps])
        #expect(sweep.step(.apps)?.short == SweepWords.skippedShort)
        #expect(sweep.step(.hardware)?.short == nil, "a finished row has a status chip, not a word")
    }

    // MARK: - ⭐ Overview's own record

    /// A sweep that landed nothing files nothing. Pressing Check my Mac and Stop in the same second
    /// must not leave a record saying this Mac was checked.
    @Test("A sweep that landed nothing files no record")
    func nothingLandedFilesNothing() {
        let app = realState()
        let started = Date()
        app.sweep.begin(at: started)
        app.sweep.requestStop()

        app.closeSweep(startedAt: started, now: started.addingTimeInterval(1))

        #expect(app.realRecords[.overview] == nil,
                "a sweep that read nothing filed a record saying the Mac was checked")
    }

    /// ⚠️ **Overview's record is never `complete` when the sweep was partial.** That flag is what
    /// keeps the audit trail's own top line honest — and `incompleteSections` deliberately looks
    /// only at `SectionID.checkable`, so this never puts the word "Overview" into the sentence
    /// naming what could not be seen.
    @Test("A partial sweep files an incomplete record")
    func aPartialSweepIsNotComplete() {
        let app = realState()
        let started = Date()
        app.sweep.begin(at: started)
        app.sweep.enter(.hardware)
        app.publish(CheckRecord(section: .hardware, ranAt: started, status: .good, complete: true),
                    finding: nil)
        app.sweep.leave(.hardware, landed: true)
        app.sweep.requestStop()

        app.closeSweep(startedAt: started, now: started.addingTimeInterval(1))

        let record = app.realRecords[.overview]
        #expect(record != nil, "a sweep that read something filed no record of itself")
        #expect(record?.complete == false,
                "a sweep that checked one section out of six called itself complete")
        #expect(record?.status == .good, "nothing needed a person, so the sweep is Good")
        #expect(!app.incompleteSections.contains(.overview),
                "Overview named itself in the list of sections that could not see everything")
    }

    // MARK: - What Overview says afterwards

    /// The headline's branch order is the product: bad news, then missing news, then good news.
    @Test("The headline never says fine while something is unchecked")
    func theHeadlineNeverOverclaims() {
        #expect(OverviewWords.headline(needsYou: 0, blind: [], unchecked: [], everChecked: false)
                == "Nothing has been checked yet.")

        #expect(OverviewWords.headline(needsYou: 0, blind: [], unchecked: [], everChecked: true)
                == "Everything looks fine.")

        let unchecked = OverviewWords.headline(needsYou: 0, blind: [], unchecked: ["Apps"],
                                               everChecked: true)
        #expect(unchecked.contains("Apps"))
        #expect(unchecked != "Everything looks fine.",
                "Overview called a Mac fine with a section nobody had checked")

        let blind = OverviewWords.headline(needsYou: 0, blind: ["Security"], unchecked: ["Apps"],
                                           everChecked: true)
        #expect(blind.contains("Security"), "being blocked outranks never having looked")

        #expect(OverviewWords.headline(needsYou: 1, blind: ["Security"], unchecked: ["Apps"],
                                       everChecked: true) == "One thing needs you.",
                "the headline spent its one sentence on something other than the worst news")
    }

    /// ⛔ **Never a score.** Not in the headline, not in the progress, not anywhere.
    @Test("Nothing Overview or the sweep says is a score or an estimate")
    func noScoreAndNoEstimate() {
        var everySentence = [SweepWords.whatThePressDoes, SweepWords.onlyOnAPress,
                             SweepWords.stopping, SweepWords.stopped, SweepWords.appsNotAsked,
                             SweepWords.notReached, SweepWords.noResult,
                             SweepWords.reading(.storage), SweepWords.position(1)]
        for count in 0...2 {
            everySentence.append(OverviewWords.headline(needsYou: count,
                                                        blind: count == 1 ? ["Security"] : [],
                                                        unchecked: ["Apps"],
                                                        everChecked: true))
        }
        for sentence in everySentence {
            #expect(!sentence.contains("%"),
                    Comment(rawValue: "a percentage reached a screen: \(sentence)"))
            #expect(!sentence.lowercased().contains("out of 100"),
                    Comment(rawValue: "a score reached a screen: \(sentence)"))
            #expect(!sentence.lowercased().contains("remaining"),
                    Comment(rawValue: "an estimate reached a screen: \(sentence)"))
        }
    }

    /// Subject–verb agreement on a list this app builds at runtime. One section hasn't; two
    /// haven't. Getting it wrong is what makes an app read as machine-written.
    @Test("The unchecked sentence agrees with its list")
    func theUncheckedSentenceAgrees() {
        #expect(OverviewWords.uncheckedNote(["Apps"]) == "Apps hasn’t been checked.")
        #expect(OverviewWords.uncheckedNote(["Apps", "Storage"])
                == "Apps and Storage haven’t been checked.")
    }

    /// The clean-state empty note has to stay true when part of the Mac was never looked at.
    @Test("Nothing needs you is qualified when something was never checked")
    func theEmptyNoteIsQualified() {
        #expect(OverviewWords.nothingNeedsYou(anythingUnchecked: false)
                == "Nothing on this Mac needs you right now.")
        #expect(OverviewWords.nothingNeedsYou(anythingUnchecked: true)
                .contains("that has been checked"),
                "the empty note claimed nothing needs you about sections nobody read")
    }

    // MARK: - What Overview derives

    /// `uncheckedSections` is the other half of the honesty rule, and it must never name Overview —
    /// a list of things Overview did not check that contains Overview is a sentence nobody can act
    /// on.
    @Test("Unchecked sections are the six, never Overview itself")
    func uncheckedNeverNamesOverview() {
        let app = realState()
        #expect(app.uncheckedSections == SectionID.checkable)

        app.publish(CheckRecord(section: .hardware, ranAt: Date(), status: .good, complete: true),
                    finding: nil)
        #expect(!app.uncheckedSections.contains(.hardware))
        #expect(!app.uncheckedSections.contains(.overview))
    }
}
