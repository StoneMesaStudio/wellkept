import SwiftUI
import UniformTypeIdentifiers
import WellkeptCore

//  AppState.swift
//  Wellkept — App/Shell
//
//  Everything the window has to remember: which section is showing, what the last check found,
//  and which of the three modal slots is occupied.
//
//  ⚠️ **This object lives ABOVE `AppearanceHost`, and that is not optional.** `AppearanceHost`
//  hangs `.id(AppFont.typeKey)` on the whole content tree so a font or text-size change repaints
//  every view — which destroys every `@State` beneath it. Anything a ⌘+ press must not throw away
//  (the selected section, an open disclosure, a sheet mid-flow) has to be here, in the model,
//  rather than in a `@State` inside a face. Lode lost a register selection on every text-size
//  press for months before this rule was written down.

// MARK: - Stored keys that are not about looks

/// The shell's own stored keys. The appearance and type keys live in `AppearancePrefs`; these are
/// the ones the shell owns, declared here so no two files drift apart on a string literal.
///
/// ⚠️ Raw key strings are permanent — they are already in users' defaults, and renaming one
/// silently reverts the setting for anyone who upgrades. Take them from `docs/CONTRACTS.md`.
enum ShellPrefs {
    /// Fills all seven sections with invented sample results. Off by default.
    static let demoModeKey = "demoMode"

    /// Which invented Mac demo mode shows — `healthy` or `problems`. See `DemoMachine`.
    ///
    /// Read only while `demoMode` is on, and stored separately from it so that turning the demo
    /// off and on again does not silently move a person back to a machine they did not pick.
    static let demoMachineKey = "demoMachine"
}

// MARK: - The three modal slots

/// The app's one sheet.
///
/// ⚠️ **Two `.sheet` modifiers on one view make SwiftUI silently drop one** — no warning, no
/// crash, just a button that does nothing on the days the other sheet happens to be first. So the
/// window has exactly one slot and every caller routes through it.
///
/// The route carries its own content rather than naming it in an enum on purpose: the welcome
/// flow, Settings and Help are written by other people, and an enum here would drag all three of
/// their view types into this file — the coupling the ownership table exists to prevent. `id` is
/// what stops the same sheet re-presenting itself into a churn loop.
struct SheetRoute: Identifiable {
    let id: String
    let content: () -> AnyView

    init(id: String, @ViewBuilder content: @escaping () -> some View) {
        self.id = id
        self.content = { AnyView(content()) }
    }
}

/// The app's one alert. Same slot rule as the sheet.
///
/// **A title and the verbs.** `message` is the deliberate exception DESIGN §10 allows: the one
/// consequence sentence where an action cannot be undone. It is not a place for prose.
struct AlertRoute: Identifiable {
    let id: String
    let title: String
    /// The consequence sentence, where there is no undo. `nil` everywhere else.
    var message: String?
    var confirmTitle: String?
    var confirmRole: ButtonRole?
    var confirm: (() -> Void)?
}

/// The app's one file picker. Same slot rule again.
struct FileRequest: Identifiable {
    let id: String
    var contentTypes: [UTType] = []
    var allowsMultiple = false
    let completion: (Result<[URL], Error>) -> Void
}

// MARK: - The model

@MainActor
@Observable
final class AppState {

    // MARK: Navigation

    /// The section on screen. Written by the sidebar, by ⌘1–⌘7, and by an Overview row.
    var selection: SectionID = .overview

    // MARK: Disclosure state

    /// Which sections have their **Options** disclosure open.
    ///
    /// Here rather than in the face for the reason at the top of this file: a text-size press
    /// rebuilds every face, and re-collapsing a panel somebody had just opened reads as the app
    /// undoing their click.
    var openOptions: Set<SectionID> = []

    /// Whether Overview's **What was checked** list is open. `nil` means the user has not touched
    /// it yet, which lets Overview open it by default on a clean Mac — where the audit trail *is*
    /// the reassurance — and leave it shut when there are things to read above it.
    var whatWasCheckedOpen: Bool?

    // MARK: Modal slots

    var sheet: SheetRoute?
    var alert: AlertRoute?
    var fileRequest: FileRequest?

    // MARK: Results

    /// What the real checks found. Empty in the shell — nothing scans yet.
    private(set) var realFindings: [Finding] = []
    /// When each real check last ran. Empty in the shell.
    private(set) var realRecords: [SectionID: CheckRecord] = [:]

    /// Sample results in every section, for judging a screen months before its engine exists.
    ///
    /// ⚠️ **Nothing in demo mode touches this Mac.** Every path, size and app name in `DemoData`
    /// is invented, and no check runs while it is on — which is why the window wears a bar saying
    /// so. A demo that read even one real value would make the other rows look real too.
    var demoMode: Bool {
        didSet {
            guard demoMode != oldValue else { return }
            UserDefaults.standard.set(demoMode, forKey: ShellPrefs.demoModeKey)
        }
    }

    /// Which invented Mac the demo shows. Decided 2026-08-27: *"I would give them both. The goal is
    /// a healthy mac."* — so the default is the healthy one, and the unwell one is a choice.
    var demoMachine: DemoMachine {
        didSet {
            guard demoMachine != oldValue else { return }
            UserDefaults.standard.set(demoMachine.rawValue, forKey: ShellPrefs.demoMachineKey)
        }
    }

    /// What the faces draw.
    var findings: [Finding] { demoMode ? DemoData.findings(demoMachine) : realFindings }
    var records: [SectionID: CheckRecord] { demoMode ? DemoData.records(demoMachine) : realRecords }

    // MARK: The sweep

    /// **"Check my Mac" — the state of the one press that runs all six sections.**
    ///
    /// The loop itself is in `RunEverything.swift`, together with the running order and the reason
    /// for it. This holds only where that loop has got to; the results go where every section's own
    /// button puts them, which is what stops the sweep becoming a second copy of the audit trail.
    ///
    /// ⚠️ Held here, above `AppearanceHost`, like everything else that must survive a text-size
    /// change: a ⌘+ press rebuilds every view, and a half-minute sweep whose progress lived in a
    /// `@State` inside Overview would appear to restart every time somebody nudged the text size.
    let sweep = Sweep()

    // MARK: The Hardware engine

    /// Hardware's own model — the first section with an engine behind it.
    ///
    /// Held here, above `AppearanceHost`, for the reason at the top of this file: a ⌘+ press
    /// rebuilds every view, and a check whose result lived in a `@State` inside the face would be
    /// thrown away and have to run again every time somebody nudged the text size.
    let hardware = HardwareModel()

    /// Run the Hardware check and file what it found.
    ///
    /// ⚠️ **Never in demo mode.** Demo mode's whole promise is that nothing here has been read
    /// from this Mac, and a check that ran underneath the invented rows would break it silently.
    func runHardwareCheck() async {
        guard !demoMode else { return }
        await hardware.check()
        fileHardwareResult()
    }

    /// Measure the drive's speed — the one button in this app that writes anything.
    func runSpeedTest() async {
        guard !demoMode else { return }
        await hardware.measureSpeed()
        fileHardwareResult()
    }

    private func fileHardwareResult() {
        guard let report = hardware.report else { return }
        publish(report.record, finding: report.overviewFinding)
    }

    // MARK: The quarantine

    /// The two things the quarantine has to say when the window opens: anything a crash interrupted,
    /// and the thirty-day sweep.
    ///
    /// ⚠️ Held here, above `AppearanceHost`, like everything else that must survive a text-size
    /// change — and because it must run **once per launch**, not once per rebuild of a view.
    let quarantineLaunch = QuarantineLaunch()

    // MARK: The Storage engine

    /// Storage's own model — five readers, one report, and the two ceremonies.
    ///
    /// ⚠️ **Nothing starts this but a press.** A full sweep took 56.7 seconds on this Mac for
    /// 983,868 files, and Full Disk Access makes it slower rather than faster — the folders it was
    /// refused are folders it would then walk. A section that spent a minute of every launch on that
    /// would make the app feel broken.
    ///
    /// It also owns the quarantine's list, which moved here from Settings the day this section
    /// existed to hold it.
    let storage = StorageModel()

    /// Run the Storage scan and file what it found.
    ///
    /// ⚠️ **Never in demo mode.** Demo mode's whole promise is that nothing on screen has been read
    /// from this Mac — and this is the one section that also offers to move files, so a real scan
    /// running underneath the invented rows would put real paths behind invented buttons.
    func runStorageCheck() async {
        guard !demoMode else { return }
        await storage.scan()
        guard let report = storage.answer?.report else { return }
        publish(report.record, finding: report.overviewFinding)
    }

    // MARK: The Security engine

    /// Security's own model — six readers, one report.
    ///
    /// ⚠️ **Nothing starts this but a press.** There is no launch check here and there must not be
    /// one: the log read alone is about six seconds, and a section that spent that on every launch
    /// would make the app feel broken on the screen where that matters most.
    let security = SecurityModel()

    /// Run the Security check and file what it found.
    ///
    /// ⚠️ **Never in demo mode.** Demo mode's whole promise is that nothing on screen has been read
    /// from this Mac, and a check running underneath the invented rows would break it silently.
    func runSecurityCheck() async {
        guard !demoMode else { return }
        await security.check()
        guard let report = security.answer?.report else { return }
        publish(report.record, finding: report.overviewFinding)
    }

    // MARK: The Apps engine

    /// Apps' own model — five readers, one report.
    ///
    /// ⚠️ **Nothing starts this but a press.** There is no launch check here and there must not be
    /// one: asking macOS for the list of apps alone takes 7–8 seconds and the whole sweep about
    /// thirteen, and a section that spent that on every launch would make the app feel broken.
    let apps = AppsModel()

    /// Whether Wellkept may ask anybody whether an app is current.
    ///
    /// ⚠️ **Held here, above `AppearanceHost`, like everything else that must survive a text-size
    /// change.** A ⌘+ press re-identifies the whole content tree and throws away every `@State`
    /// beneath it; a consent question held in a `@State` inside the Apps face would vanish
    /// mid-question the first time somebody made the text bigger in order to read it.
    let updateConsent = UpdateConsentStore()

    /// True while the consent question is on the Apps screen, waiting for an answer.
    ///
    /// It is a panel in the page rather than a sheet — see `AppsView.consentQuestion` — so it does
    /// not go through the window's one sheet slot.
    private(set) var askingUpdateConsent = false

    /// Run the Apps check and file what it found.
    ///
    /// ⚠️ **The question comes first, and only once.** On the very first press, nobody has been
    /// asked whether Wellkept may ask Apple and a few makers about the apps installed here. So the
    /// press puts the question on the screen instead of starting a check that would have to guess
    /// at the answer. Every press after that runs straight through.
    ///
    /// ⚠️ **Never in demo mode.** Demo mode's whole promise is that nothing on screen has been read
    /// from this Mac, and a check running underneath the invented rows would break it silently.
    func runAppsCheck() async {
        guard !demoMode else { return }
        guard updateConsent.hasBeenAsked else {
            askingUpdateConsent = true
            return
        }
        await runApps()
    }

    /// The answer to the consent question, and the check it was holding up.
    ///
    /// Either answer starts the check. Saying no is a supported way to run this section — every
    /// app's line reads "Not checked", the section still lists everything installed, and nothing
    /// about this Mac is named to anybody.
    func answerUpdateConsent(_ allowed: Bool) async {
        updateConsent.setAllowed(allowed)
        askingUpdateConsent = false
        await runApps()
    }

    private func runApps() async {
        await apps.check(consent: updateConsent.answer)
        guard let report = apps.answer?.report else { return }
        publish(report.record, finding: report.overviewFinding)
    }

    // MARK: The Changes engine

    /// Changes' own model — one read, one comparison, one report.
    ///
    /// ⚠️ **Nothing starts this but a press.** The read is Security's read, about eight seconds,
    /// and a section that spent that on every launch would make the app feel broken.
    ///
    /// ⚠️ Taking a *snapshot* is the other half and it is not this. It costs under a second and
    /// belongs on every launch, because a record of what your settings were cannot be back-filled.
    /// Whoever wires that must not reach for `runChangesCheck()` to do it.
    let changes = ChangesModel()

    /// Run the Changes check and file what it found.
    ///
    /// ⚠️ **Never in demo mode.** Demo mode's whole promise is that nothing on screen has been read
    /// from this Mac — and this section writes a snapshot of the real machine as part of running,
    /// so a check underneath the invented rows would put this Mac's settings into the record while
    /// the screen said it was looking at somebody else's.
    func runChangesCheck() async {
        guard !demoMode else { return }
        await changes.check()
        guard let report = changes.report else { return }
        publish(report.record, finding: report.overviewFinding)
    }

    // MARK: The Backup engine

    /// Backup's own model — Time Machine's state, what is not covered, and the printed page.
    ///
    /// ⚠️ **Nothing starts this but a press.** The Time Machine half is free — 52 ms, nothing
    /// granted — but the coverage half is a bounded walk of the home folder looking for files that
    /// are in the cloud and not on the disk, and a section that spent that on every launch would
    /// make the app feel slow on a screen where nothing had changed.
    ///
    /// ⛔ **It writes to no drive.** `BackupRun` takes a `RehearsalGate.Pass`, which cannot be
    /// constructed outside `RehearsalGate`, and nothing reachable from this model asks for one.
    let backup = BackupModel()

    /// Run the Backup check and file what it found.
    ///
    /// ⚠️ **Never in demo mode.** Demo mode's whole promise is that nothing on screen has been read
    /// from this Mac — and this section's Recovery Plan names the Mac, its macOS version and its
    /// backup drive, so a real check underneath the invented rows would put this machine's own
    /// facts on a page about somebody else's.
    func runBackupCheck() async {
        guard !demoMode else { return }
        await backup.check()
        guard let report = backup.answer?.report else { return }
        publish(report.record, finding: report.overviewFinding)
    }

    /// File one section's result: its line in the audit trail, and the single row it sends up to
    /// Overview.
    ///
    /// ⚠️ **One row per section, replacing whatever that section filed last.** Appending would
    /// leave yesterday's failing drive on Overview beside today's healthy one, and the two would
    /// disagree with nobody to arbitrate.
    func publish(_ record: CheckRecord, finding: Finding?) {
        realRecords[record.section] = record
        realFindings.removeAll { $0.section == record.section }
        if let finding { realFindings.append(finding) }
    }

    // MARK: Derived

    /// One section's results, worst first.
    func findings(in section: SectionID) -> [Finding] {
        findings.filter { $0.section == section }.sorted(by: Self.worstFirst)
    }

    /// What Overview lists: the things that need a person, worst first.
    ///
    /// `.information` is deliberately absent. A 40 GB folder is a fact Wellkept revealed, not a
    /// thing that needs you, and putting it on the summary would make the summary a chore list.
    var needsYou: [Finding] {
        findings.filter { $0.severity >= .attention }.sorted(by: Self.worstFirst)
    }

    /// The sections whose last check could not see everything, in sidebar order.
    ///
    /// This is the flag that keeps Overview honest: it may never report a clean Mac on the
    /// strength of a partial look.
    /// `checkable` and not `allCases`: Overview's own record is the sweep, and a sweep that
    /// contained a partial check is partial too — so listing it here would name Overview alongside
    /// the section that actually could not see something, and the sentence would read as two
    /// failures where there was one.
    var incompleteSections: [SectionID] {
        SectionID.checkable.filter { records[$0]?.complete == false }
    }

    /// The sections with no result at all — never run, or skipped by the last sweep.
    ///
    /// ⚠️ This is the other half of Overview's honesty rule, and it is a different fact from
    /// `incompleteSections`. That one is "we looked and a permission stopped us"; this one is "we
    /// never looked". Both have to keep the headline from saying the Mac looks fine, and merging
    /// them would put the wrong sentence on one of the two.
    ///
    /// `checkable` and not `allCases` for the same reason as above: Overview's own record is the
    /// sweep, and naming Overview in a list of things Overview did not check is a sentence nobody
    /// can act on.
    var uncheckedSections: [SectionID] {
        SectionID.checkable.filter { records[$0] == nil }
    }

    /// Whether everything that ran, ran in full. Computed rather than stored so it cannot drift
    /// from the records it is about.
    var lastCheckWasComplete: Bool { incompleteSections.isEmpty }

    /// The most recent check of any kind, or `nil` if nothing has ever run.
    var lastCheckedAt: Date? { records.values.map(\.ranAt).max() }

    /// Sort order for every list in the app: worst first, then sidebar order, then title.
    ///
    /// `Severity` sorts most-severe **last** (`information < attention < problem`), so "worst
    /// first" is `>`. Ties are broken deterministically — an unstable sort that reshuffles two
    /// equal rows between redraws is a list you have to re-read every time you look at it.
    private static func worstFirst(_ a: Finding, _ b: Finding) -> Bool {
        if a.severity != b.severity { return a.severity > b.severity }
        let ai = SectionID.allCases.firstIndex(of: a.section) ?? 0
        let bi = SectionID.allCases.firstIndex(of: b.section) ?? 0
        if ai != bi { return ai < bi }
        return a.title < b.title
    }

    // MARK: Bindings

    /// The **Options** disclosure for one section.
    func optionsOpen(_ section: SectionID) -> Binding<Bool> {
        Binding(get: { self.openOptions.contains(section) },
                set: { open in
                    if open { self.openOptions.insert(section) } else { self.openOptions.remove(section) }
                })
    }

    /// Overview's **What was checked** disclosure. `whenUntouched` is what it shows until somebody
    /// clicks it — see the property's own note.
    func whatWasChecked(default whenUntouched: Bool) -> Binding<Bool> {
        Binding(get: { self.whatWasCheckedOpen ?? whenUntouched },
                set: { self.whatWasCheckedOpen = $0 })
    }

    // MARK: Life

    init() {
        demoMode = UserDefaults.standard.bool(forKey: ShellPrefs.demoModeKey)
        demoMachine = UserDefaults.standard.string(forKey: ShellPrefs.demoMachineKey)
            .flatMap(DemoMachine.init(rawValue:)) ?? .healthy

        // Settings owns a switch for the same key, and it may well write it through `@AppStorage`
        // rather than through this object. Without this the window would keep showing sample
        // results after the switch was turned off — the app disagreeing with its own settings,
        // which is the worst kind of bug to be told about second-hand.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let stored = UserDefaults.standard.bool(forKey: ShellPrefs.demoModeKey)
                    if stored != self.demoMode { self.demoMode = stored }
                    let machine = UserDefaults.standard.string(forKey: ShellPrefs.demoMachineKey)
                        .flatMap(DemoMachine.init(rawValue:)) ?? .healthy
                    if machine != self.demoMachine { self.demoMachine = machine }
                }
            }
    }
}
