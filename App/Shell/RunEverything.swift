import Foundation
import SwiftUI
import WellkeptCore

//  RunEverything.swift
//  Wellkept — App/Shell
//
//  ⭐ **"Check my Mac" — the app's main verb, and the only thing in Wellkept that runs more than
//  one section.**
//
//  Six checks, in a fixed order, one after another. It calls each section's existing check; it
//  reimplements none of them. A sweep that had its own readers would be a second app inside this
//  one, and the two would disagree about the same Mac within a release.
//
//  ## The order, and why it is this order
//
//      Hardware → Backup → Security → Changes → Apps → Storage
//
//  Measured, not guessed: Security's log read is about 6 seconds, Apps' inventory 7–8 (the whole
//  Apps sweep about 13), Storage about 12 on this Mac and up to 56.7 on a full disk. One press is
//  therefore roughly half a minute, and rows have to start landing long before it ends.
//
//  1. **Hardware first.** It is the only section that already runs at launch, so it is the one
//     whose readers are warm, and it is where the worst news in the app lives — a drive that is
//     wearing out should not wait behind twenty seconds of app inventory.
//  2. **Backup second.** Time Machine's own state is 52 ms. "Is my stuff safe" is answered almost
//     instantly, which is the most reassuring thing this app can put on the screen early.
//  3. **Security, then Changes, adjacent.** Changes re-reads what Security just read, so it runs
//     against warm caches — the same two readers, back to back, cost less than the same two
//     readers separated by a thirteen-second app inventory.
//  4. **Apps.** Thirteen seconds, and the one section that can be skipped outright (see below), so
//     it goes late where skipping it costs the least momentum.
//  5. **Storage last.** The longest, the most variable, and the only one whose partial result is
//     discarded rather than kept — so it is the section where pressing **Stop** costs the least.
//
//  ## ⚠️ Pressing this button is not consent
//
//  Apps is allowed to ask Apple and a few makers whether an app is current, and `UpdateConsent`
//  has three states because "nobody has been asked" is a real one. A person who has not answered
//  that question must not have it answered for them by pressing a *different* button. So a sweep
//  that meets an unanswered consent question **skips Apps**, says on the face that it did and why,
//  and files no record for it. The question is put on the Apps screen, by the Apps button, where
//  it has context — never here.
//
//  ## ⚠️ Two things this never shows: a percentage, and a time remaining
//
//  Same law as `ScanPolicy.Running.whyThereIsNoEstimate`. Six sections whose individual costs vary
//  by a factor of ten cannot be turned into a bar without inventing the number, and the first scan
//  after a restart has never been measured. What the face shows instead is the *name of the
//  section being read* and *what has already come back* — both of which are facts.
//
//  ## Stopping
//
//  **A stopped sweep keeps what already finished.** Every section publishes its own result the
//  moment it lands, so stopping is simply "run no more sections"; nothing is rolled back. The one
//  section that can be interrupted mid-flight is Storage, whose own `scan()` throws away a partial
//  walk on purpose — a half-read disk is not a shorter answer, it is a wrong one.
//
//  ⚠️ **Stop is not instant, and the face says so.** Every section's readers run on detached
//  tasks, which do not inherit cancellation. So the sweep finishes the section it is inside — up
//  to about eight seconds — and then stops. Claiming otherwise would be a button that appears not
//  to work.

// MARK: - What the sweep says

/// Every sentence "Check my Mac" puts on the screen, in one place.
///
/// Here rather than in `OverviewView` for the reason `StorageWords` exists: the words are tested,
/// and a string typed inline in a view is a string no test can reach.
enum SweepWords {

    /// The button while it is running. The verb itself is `SectionID.overview.verb`, and is never
    /// re-typed.
    static let running = "Checking"

    /// The house word for stopping something that is under way — the same one Storage uses.
    static let stop = StorageWords.cancel

    /// What pressing the button will do, said before it is pressed. Every section face carries one
    /// of these; this is Overview's, and it is the only one that has to name the cost of six
    /// checks at once.
    ///
    /// ⚠️ **The half-minute is measured and the caveat is real.** 6 seconds for Security, about 13
    /// for Apps, about 12 for Storage on this Mac — and Storage alone reached 56.7 on a full disk.
    /// A figure with no caveat would be wrong on exactly the machines that need this app most.
    static let whatThePressDoes =
        "Press \(SectionID.overview.verb) and Wellkept runs all six checks in turn — hardware, "
        + "backup, security, changes, apps and storage — and brings back only what needs you. It "
        + "reads; it changes nothing and moves nothing. It takes about half a minute, longer on a "
        + "very full disk, and it names each section as it reads it."

    /// ⚠️ Said on Overview because it is true of Overview: Security and Apps deliberately do not
    /// run when the app opens, and this button is the thing that runs them.
    static let onlyOnAPress =
        "Security and Apps never run when the app opens — they are slow, and they run only when "
        + "you press this."

    /// Which section is being read, right now.
    static func reading(_ section: SectionID) -> String { "Reading \(section.title)" }

    /// Where the sweep is in the queue. **A count of sections, not a percentage and not a clock.**
    /// The same device every section face already uses for its own stages.
    static func position(_ index: Int) -> String { "Section \(index) of \(Sweep.order.count)" }

    /// After **Stop** is pressed, and before the current section lets go.
    static let stopping = "Finishing this section, then stopping."

    /// What a stopped sweep left behind. It is the reassurance that pressing Stop cost nothing.
    static let stopped =
        "Stopped. Everything that had already finished was kept — press \(SectionID.overview.verb) "
        + "again to run the rest."

    /// ⚠️ **The skip that is a matter of consent, not of capability.**
    ///
    /// It names the button that *is* the answer, because a person who reads this and wants their
    /// apps checked needs somewhere to go. It does not restate what leaves this Mac —
    /// `UpdateConsent.departure` owns those two sentences and this would be a third copy of them.
    static let appsNotAsked =
        "Wellkept has not asked yet whether it may check whether your apps are current, and "
        + "pressing \(SectionID.overview.verb) is not an answer to that question. Open Apps and "
        + "press \(SectionID.apps.verb) to decide."

    /// A section that was queued and never reached, because the sweep was stopped.
    static let notReached = "You pressed \(stop) before this one ran."

    /// A section that ran and published nothing. Rare — a check already in flight from that
    /// section's own button, or a reader that came back with nothing to file.
    static let noResult = "It ran, but it had nothing new to file."

    // MARK: Row labels

    /// The short phrase on an audit-trail row. Long reasons go under the button, where there is
    /// room for them; a row has one line.
    static let waitingShort = "waiting"
    static let readingShort = "reading now"
    static let skippedShort = "not checked"
    static let unfinishedShort = "no result"
}

// MARK: - The sweep's own state

/// **What "Check my Mac" is doing, and what it has already done.**
///
/// It holds no results of its own. Every section publishes into `AppState.realRecords` as it
/// lands, exactly as it does when its own button is pressed; this object only knows where the
/// sweep has got to. Keeping the two apart is what stops the sweep becoming a second, disagreeing
/// copy of the audit trail.
///
/// ⚠️ **It lives on `AppState`, above `AppearanceHost`,** like everything else that must survive a
/// text-size change: a ⌘+ press re-identifies the whole content tree, and a sweep whose progress
/// lived in a `@State` inside Overview would appear to restart every time somebody made the text
/// bigger in order to read it.
@MainActor
@Observable
final class Sweep {

    /// Where one section stands in this sweep.
    enum Step: Equatable, Sendable {
        /// Queued, not started.
        case waiting
        /// Being read right now.
        case reading
        /// Ran, and filed a result.
        case done
        /// Deliberately not run, and why. Consent, today; there may be others.
        case skipped(String)
        /// Reached or queued, and there is no result. Why.
        case unfinished(String)

        /// The one-line phrase for an audit-trail row. `nil` on `.done`, where the status chip and
        /// the date already say everything.
        var short: String? {
            switch self {
            case .waiting:    SweepWords.waitingShort
            case .reading:    SweepWords.readingShort
            case .done:       nil
            case .skipped:    SweepWords.skippedShort
            case .unfinished: SweepWords.unfinishedShort
            }
        }

        /// The sentence that explains it, where there is one.
        var reason: String? {
            switch self {
            case let .skipped(why):    why
            case let .unfinished(why): why
            default:                   nil
            }
        }
    }

    // MARK: The order

    /// ⭐ **The running order. Justified in the file header; do not reorder without reading it.**
    ///
    /// ⚠️ It is written out rather than derived from `SectionID.checkable`, because the sidebar's
    /// order and the *cheapest-first* order are different questions with different answers.
    /// `SweepTests.everySectionIsInTheOrder` is what stops a seventh section being added to the
    /// app and silently never checked.
    nonisolated static let order: [SectionID] = [.hardware, .backup, .security, .changes, .apps, .storage]

    // MARK: State

    /// True from the first section to the last.
    private(set) var isRunning = false

    /// The section being read, or `nil` between sweeps.
    private(set) var current: SectionID?

    /// Where every section stands. Empty before the first sweep of the session.
    private(set) var steps: [SectionID: Step] = [:]

    /// When this sweep started. `nil` before the first one.
    private(set) var startedAt: Date?

    /// When the last sweep ended, however it ended.
    private(set) var finishedAt: Date?

    /// Somebody pressed **Stop** and the current section has not let go yet.
    private(set) var stopRequested = false

    /// The last sweep ended early because somebody pressed **Stop**.
    private(set) var wasStopped = false

    /// The running sweep, so **Stop** can reach it. Cancelling it is what propagates into
    /// `StorageModel.scan()`, which is the one reader that can actually be interrupted.
    @ObservationIgnored var task: Task<Void, Never>?

    // MARK: Reading it

    func step(_ section: SectionID) -> Step? { steps[section] }

    /// Which section of six is being read. `nil` when nothing is.
    var position: Int? {
        current.flatMap { Self.order.firstIndex(of: $0) }.map { $0 + 1 }
    }

    /// Everything this sweep did not check, and why, in running order. What the face prints under
    /// the button once the sweep is over.
    var shortfalls: [(section: SectionID, reason: String)] {
        Self.order.compactMap { section in
            steps[section]?.reason.map { (section, $0) }
        }
    }

    /// Whether any section actually filed something. A sweep that landed nothing files no record
    /// of its own — see `AppState.runEverything`.
    var anythingLanded: Bool { steps.values.contains(.done) }

    // MARK: The consent gate

    /// ⭐ **Why this sweep will not run a section.** `nil` means run it.
    ///
    /// ⚠️ **Pressing "Check my Mac" is not an answer to the update question, and this function is
    /// the whole reason that stays true.** `AppState.runAppsCheck()` puts the consent question on
    /// the Apps screen when nobody has answered it — which, called from a sweep, would be a
    /// question raised by a button on a different screen. Somebody who then said yes to make the
    /// panel go away would have agreed to a departure they never went looking for. So the sweep
    /// reads the answer itself, and where there isn't one it leaves Apps alone and says why.
    ///
    /// ⚠️ **Declining is an answer, and Apps still runs.** A person who said no gets the whole
    /// section — everything installed, macOS's own updates, crashes, leftovers — with every app's
    /// update line reading "Not checked". Skipping the section on a "no" would punish the answer.
    ///
    /// Static and free of `UserDefaults` so the rule can be tested against all three answers
    /// without a single write to anybody's preferences.
    nonisolated static func skipReason(for section: SectionID,
                                       consent: UpdateConsent.Answer) -> String? {
        guard section == .apps else { return nil }
        return consent == .notAsked ? SweepWords.appsNotAsked : nil
    }

    // MARK: Driving it — the run loop's, and the harness's

    /// Start a sweep: everything queued, nothing done.
    func begin(at now: Date = Date()) {
        isRunning = true
        stopRequested = false
        wasStopped = false
        startedAt = now
        finishedAt = nil
        current = nil
        steps = Dictionary(uniqueKeysWithValues: Self.order.map { ($0, Step.waiting) })
    }

    func enter(_ section: SectionID) {
        current = section
        steps[section] = .reading
    }

    /// One section is over. `landed` is whether it actually filed a result — the run loop works
    /// that out from the records, not from the fact that the call returned.
    func leave(_ section: SectionID, landed: Bool) {
        steps[section] = landed ? .done : .unfinished(SweepWords.noResult)
        current = nil
    }

    func skip(_ section: SectionID, why: String) {
        steps[section] = .skipped(why)
        current = nil
    }

    /// **Stop.** The current section finishes; nothing after it runs.
    func requestStop() { stopRequested = true }

    /// The sweep is over. Anything still queued is marked as never reached, which is the honest
    /// word for it — the alternative is a row that says "waiting" for ever.
    func end(at now: Date = Date()) {
        wasStopped = stopRequested
        for section in Self.order where steps[section] == .waiting || steps[section] == .reading {
            steps[section] = .unfinished(stopRequested ? SweepWords.notReached : SweepWords.noResult)
        }
        isRunning = false
        stopRequested = false
        current = nil
        finishedAt = now
    }
}

// MARK: - Running everything

extension AppState {

    /// **The app's main verb.** Six checks, in `Sweep.order`, each publishing as it lands.
    ///
    /// Refuses in demo mode — demo mode's whole promise is that nothing on screen was read from
    /// this Mac, and a sweep underneath the invented rows would break it six times over. Refuses a
    /// second time while one is running, rather than queueing.
    ///
    /// - Parameter now: the clock, injectable so the record this files can be tested.
    func runEverything(now: () -> Date = { Date() }) async {
        guard !demoMode, !sweep.isRunning else { return }

        let started = now()
        sweep.begin(at: started)
        defer { closeSweep(startedAt: started, now: now()) }

        for section in Sweep.order {
            // Two conditions, and they are not the same one. `Task.isCancelled` is Stop reaching
            // in from the outside; `stopRequested` is Stop pressed on a sweep nobody cancelled —
            // which is what happens when `runEverything` is awaited directly rather than through
            // `startEverything`.
            if Task.isCancelled || sweep.stopRequested { break }

            if let why = sweepSkipReason(for: section) {
                sweep.skip(section, why: why)
                continue
            }

            sweep.enter(section)
            await runSection(section)

            // ⚠️ **"It returned" is not "it ran".** Every section model ignores a second call while
            // its own button already has one in flight, and a cancelled Storage scan keeps the
            // previous answer rather than filing a new one. So the sweep asks the records whether
            // anything actually landed since it started, rather than trusting the call.
            let landed = (records[section]?.ranAt).map { $0 >= started } ?? false
            sweep.leave(section, landed: landed)
        }
    }

    /// Start a sweep and keep hold of it, so **Stop** has something to cancel.
    ///
    /// The button calls this rather than wrapping `runEverything` in its own `Task`: a task created
    /// inside a view's action is a task nobody can reach afterwards, and Stop would then be a
    /// button that changes a flag while the disk carries on being walked.
    func startEverything() {
        guard !demoMode, !sweep.isRunning else { return }
        // `Task {}` in a `@MainActor` context inherits that isolation, so the whole body — the
        // sweep and the clean-up — runs where `AppState` lives.
        sweep.task = Task { [weak self] in
            await self?.runEverything()
            self?.sweep.task = nil
        }
    }

    /// **Stop.** Both halves, and both are needed.
    ///
    /// The flag stops the loop starting another section. The cancellation reaches into
    /// `StorageModel.scan()`, which is the only reader in the app that watches for it — everything
    /// else runs on detached tasks that do not inherit cancellation and will finish the step they
    /// are inside. That is why the face says "finishing this section, then stopping" rather than
    /// pretending the press was instant.
    func stopEverything() {
        guard sweep.isRunning else { return }
        sweep.requestStop()
        sweep.task?.cancel()
    }

    /// Why this sweep will not run a section, for the answer this Mac actually holds. The rule
    /// itself — and the reason there is one — is `Sweep.skipReason`.
    func sweepSkipReason(for section: SectionID) -> String? {
        Sweep.skipReason(for: section, consent: updateConsent.answer)
    }

    /// Call one section's existing check. **Nothing here reimplements a check**; every case is the
    /// same call that section's own button makes.
    private func runSection(_ section: SectionID) async {
        switch section {
        case .hardware: await runHardwareCheck()
        case .backup:   await runBackupCheck()
        case .security: await runSecurityCheck()
        case .changes:  await runChangesCheck()
        case .apps:     await runAppsCheck()
        case .storage:  await runStorageCheck()
        // Overview does not check itself. The sweep IS Overview's check, and its record is filed
        // by `closeSweep` below.
        case .overview: break
        }
    }

    /// End the sweep and file Overview's own line in the audit trail.
    ///
    /// ⚠️ **`complete` is false whenever the sweep was partial** — a section blocked by a
    /// permission, a section skipped for consent, a section never reached. `incompleteSections`
    /// deliberately looks only at `SectionID.checkable`, so this flag never puts the word
    /// "Overview" into the sentence naming what could not be seen; it just stops Overview's own
    /// row claiming a clean full sweep that did not happen.
    ///
    /// ⚠️ **A sweep that landed nothing files nothing.** Pressing Check my Mac and Stop in the same
    /// second must not leave a record saying the Mac was checked.
    /// Internal rather than private so `SweepTests` can prove the two rules above without running
    /// six real checks against this Mac. Nothing else calls it.
    func closeSweep(startedAt: Date, now: Date) {
        sweep.end(at: now)
        guard sweep.anythingLanded else { return }

        let complete = incompleteSections.isEmpty
            && uncheckedSections.isEmpty
            && sweep.shortfalls.isEmpty
        publish(CheckRecord(section: .overview,
                            ranAt: now,
                            status: needsYou.isEmpty ? .good : .needsAttention,
                            complete: complete),
                finding: nil)
    }
}
