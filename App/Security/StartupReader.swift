import Foundation
import Security
import WellkeptCore

//  StartupReader.swift
//  Wellkept — App/Security
//
//  **What starts on its own on this Mac.**
//
//  Launch agents, launch daemons, an app's own background item, cron, configuration profiles.
//  One `SecurityRow` for `.startsOnItsOwn`, and a `Survey` underneath it that the Apps section is
//  meant to reuse rather than write again.
//
//  ## ⚠️ The rule this file exists to obey: count real startup items, never files
//
//  There are seven third-party startup files on the Mac this was written against. **Two of them
//  start nothing at all.** `/Library/LaunchAgents/com.google.keystone.agent.plist` and its
//  `xpcservice` twin are 181-byte XML documents whose entire body is `<dict/>` — no `Label`, no
//  `Program`, no `ProgramArguments`. `launchd` refuses them. They are what Google left behind when
//  something was uninstalled.
//
//  A tool that counts files therefore announces *"Google runs 2 things at login"* on a Mac where
//  Google runs nothing at login. That is precisely the scare the other cleaners sell, and it is
//  why every file here is opened, parsed, and resolved to a program that actually exists before it
//  is allowed to count. The leftovers are still *reported* — as leftovers, in Options, plainly
//  described as starting nothing — because silently dropping them would leave a person wondering
//  why our number disagrees with the file listing they can see in Finder.
//
//  ## ⚠️ Apple's own list is not readable, and the row says so
//
//  The list in **System Settings ▸ General ▸ Login Items & Extensions** comes out of the
//  background task management store at `/var/db/com.apple.backgroundtaskmanagement`, which is
//  root-only. The one tool that prints it, `sfltool dumpbtm`, **puts an authorization password box
//  on the screen** — banned outright in this project after it happened to John once.
//
//  So we build our own list from what is on disk and **say that ours can differ from Apple's by an
//  item or two**, and point at Apple's rather than pretending to replace it. That is the honest
//  shape: `Unreadable.notGrantable` for the store itself — refused, no button, and the check stays
//  complete, because no permission this app could ever ask for would have shown it.
//
//  ## ⚠️ An unrecognised item is unrecognised, never suspicious
//
//  This is where the cleaners frighten people into deleting the thing that makes their printer
//  work. `/opt/homebrew/opt/mysql/bin/mysqld_safe` on this Mac is a shell script with no code
//  signature at all — perfectly ordinary, and a tool looking for something to flag would flag it.
//
//  **Nothing in this file raises a concern.** Not one of the nine in `SecurityConcern` is about a
//  startup item, so `SecurityRow.severity` cannot make this row amber even by accident, which is
//  the whole reason severity is computed there rather than declared here. The row states what
//  starts, when, and who signed it. Where nobody signed it, it says nobody signed it.
//
//  ## What is deliberately not here
//
//  - **`emond` and `periodic`.** Both are gone entirely in macOS 26. Shipping those checks would
//    mean two rows that always come back clean because there is nothing left to find.
//  - **`/System/Library/LaunchAgents` and `/System/Library/LaunchDaemons`.** Around a thousand
//    Apple items that are macOS itself. Listing them is not information.
//  - **Provisioning profiles counted as configuration profiles.** `system_profiler`'s configuration
//    profile report has three sections, and on a developer's Mac the *only* populated one is
//    `spconfigprofile_section_provprofiles` — Xcode's provisioning profiles, of which this machine
//    has thirty-one. Counting those would say "31 configuration profiles are installed on this
//    Mac", which is the empty-stub bug again in a different coat. Only the device and user sections
//    count; the provisioning profiles get one honest line saying what they are.

enum StartupReader {

    // MARK: - What one startup item is

    /// Where an item was found, which is also what decides when it can run.
    enum Origin: String, Sendable, Hashable, CaseIterable {
        /// `~/Library/LaunchAgents` — this account only.
        case userAgent
        /// `/Library/LaunchAgents` — every account on this Mac.
        case globalAgent
        /// `/Library/LaunchDaemons` — runs as the system, before anybody logs in.
        case globalDaemon
        /// A background item an app carries inside itself. **macOS decides whether these run and
        /// we cannot read that decision**, so they are listed and not counted. See `Survey`.
        case appBundled
        /// This account's `crontab`.
        case cron
        /// A configuration profile installed on this Mac.
        case configurationProfile

        var label: String {
            switch self {
            case .userAgent:            "Starts when you log in"
            case .globalAgent:          "Starts when anyone logs in"
            case .globalDaemon:         "Starts with the Mac"
            case .appBundled:           "Carried inside an app"
            case .cron:                 "Scheduled job"
            case .configurationProfile: "Configuration profile"
            }
        }
    }

    /// When an item runs, taken from the file rather than guessed.
    enum Trigger: Sendable, Hashable {
        /// `RunAtLoad` on an agent.
        case atLogin
        /// `RunAtLoad` on a daemon.
        case atStartup
        /// `StartInterval` or `StartCalendarInterval`, already put into words.
        case onASchedule(String)
        /// `KeepAlive` — macOS starts it again every time it stops.
        case keptRunning
        /// `MachServices` and nothing else: it sits there until another program asks for it.
        case whenSomethingAsksForIt
        /// `WatchPaths` or `QueueDirectories`.
        case whenAFolderChanges
        /// The file says nothing about when. macOS decides.
        case whenMacOSDecides

        var sentence: String {
            switch self {
            case .atLogin:                "Starts when you log in"
            case .atStartup:              "Starts with the Mac"
            case let .onASchedule(when):  when
            case .keptRunning:            "Kept running — macOS starts it again if it stops"
            case .whenSomethingAsksForIt: "Waits until another program asks for it"
            case .whenAFolderChanges:     "Starts when a folder it watches changes"
            case .whenMacOSDecides:       "macOS decides when it runs"
            }
        }
    }

    /// One thing that is set to start on its own, resolved to a program that exists.
    struct Item: Sendable, Hashable, Identifiable {

        /// The `launchd` label, the cron line's own identity, or the profile identifier.
        let label: String

        /// The best human name we could resolve — an app's display name where the program lives
        /// inside one, otherwise the program's file name. **Never invented from the label**: a
        /// reverse-engineered "Microsoft Update Agent" from `com.microsoft.update.agent` is a
        /// guess printed as a fact.
        let name: String

        /// Who signed the program, where anybody did. `nil` is ordinary and means exactly that:
        /// unrecognised, not suspicious.
        let developer: String?

        /// The program this item actually runs. `nil` only for a profile, which runs nothing.
        let program: String?

        let origin: Origin
        let trigger: Trigger

        /// `Disabled` in the file. A disabled item is still listed, because it is still there.
        let disabled: Bool

        /// The file it came from, so a person can go and look.
        let file: String

        var id: String { "\(origin.rawValue)|\(label)|\(file)" }

        /// Whether a signature named somebody. The word for `false` is **unrecognised**.
        var isRecognised: Bool { developer != nil }
    }

    /// A startup file that starts nothing. The point of the whole file — see the header.
    struct Leftover: Sendable, Hashable, Identifiable {
        let file: String
        /// What is actually wrong with it, in plain words.
        let why: String
        var id: String { file }
    }

    // MARK: - What one run found

    struct Survey: Sendable, Hashable {

        /// Everything that resolves to a real program and is counted in the headline.
        var items: [Item] = []

        /// Background items apps carry inside themselves. **Listed, never counted** — the switch
        /// that decides whether these run lives in the store we are not allowed to read, so
        /// counting them would be reporting a file again rather than a startup item.
        var carriedInsideApps: [Item] = []

        /// Startup files that start nothing.
        var leftovers: [Leftover] = []

        /// Files we opened.
        var filesRead = 0

        /// Files that would not parse at all — distinct from a file that parses to nothing.
        var unreadableFiles: [String] = []

        /// Set when this account's crontab could not be read. `nil` means it was read, and an
        /// empty crontab is a real answer.
        var cronUnreadable: Unreadable?

        /// Set when the configuration profile report could not be run.
        var profilesUnreadable: Unreadable?

        /// Xcode provisioning profiles. Counted separately so they can never be mistaken for
        /// configuration profiles. See the header.
        var provisioningProfiles = 0

        /// The folders we actually looked in, for the row to show its working.
        var foldersSearched: [String] = []
    }

    // MARK: - Where we look

    static let userAgents = URL(filePath: "\(NSHomeDirectory())/Library/LaunchAgents",
                                directoryHint: .isDirectory)
    static let globalAgents = URL(filePath: "/Library/LaunchAgents", directoryHint: .isDirectory)
    static let globalDaemons = URL(filePath: "/Library/LaunchDaemons", directoryHint: .isDirectory)

    /// Where apps live. `/System/Applications` is deliberately absent: those are macOS.
    static let applicationFolders = [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        URL(filePath: "/Applications/Utilities", directoryHint: .isDirectory),
        URL(filePath: "\(NSHomeDirectory())/Applications", directoryHint: .isDirectory)
    ]

    /// Apple's own list, named rather than linked. Every `x-apple.systempreferences:` anchor in
    /// this app lives in `SystemSettingsPane`, and there is no Login Items case there yet — so
    /// this row points at the pane in words, which is also what stops us implying our list is the
    /// authoritative one.
    static let applesOwnList = "System Settings ▸ General ▸ Login Items & Extensions"

    // MARK: - The row

    /// Read the "What starts on its own" row.
    ///
    /// Folders are injectable so a test can point this at fixtures. That matters more here than
    /// anywhere else in the app: the behaviour worth testing — an empty stub not counting — cannot
    /// be exercised on a machine that happens not to have one.
    static func read(userAgents: URL = userAgents,
                     globalAgents: URL = globalAgents,
                     globalDaemons: URL = globalDaemons,
                     applicationFolders: [URL] = applicationFolders,
                     includeCron: Bool = true,
                     includeProfiles: Bool = true,
                     fileManager: FileManager = .default) -> SecurityRow {

        let survey = survey(userAgents: userAgents,
                            globalAgents: globalAgents,
                            globalDaemons: globalDaemons,
                            applicationFolders: applicationFolders,
                            includeCron: includeCron,
                            includeProfiles: includeProfiles,
                            fileManager: fileManager)
        return row(from: survey)
    }

    /// Everything one run found, before it is turned into words. Exposed so the Apps section can
    /// reuse the work instead of writing this again — John's call, 2026-08-27.
    static func survey(userAgents: URL = userAgents,
                       globalAgents: URL = globalAgents,
                       globalDaemons: URL = globalDaemons,
                       applicationFolders: [URL] = applicationFolders,
                       includeCron: Bool = true,
                       includeProfiles: Bool = true,
                       fileManager: FileManager = .default) -> Survey {

        var survey = Survey()

        for (folder, origin) in [(userAgents, Origin.userAgent),
                                 (globalAgents, Origin.globalAgent),
                                 (globalDaemons, Origin.globalDaemon)] {
            survey.foldersSearched.append(folder.path)
            read(folder: folder, origin: origin, into: &survey, fileManager: fileManager)
        }

        for folder in applicationFolders {
            readBundledItems(inApplications: folder, into: &survey, fileManager: fileManager)
        }

        if includeCron { readCron(into: &survey) }
        if includeProfiles { readConfigurationProfiles(into: &survey) }

        return survey
    }

    // MARK: - Turning a survey into words

    static func row(from survey: Survey) -> SecurityRow {
        let counted = survey.items
        let headline = headline(counted)

        // ⚠️ The caveat is on the row, not behind Options. A list that could differ from Apple's
        // and does not say so is a list that will be believed.
        var reason = "This list is built from the startup files on this Mac. Apple's own list, "
                   + "in \(applesOwnList), is kept in a place no app can read without an "
                   + "administrator password, so ours can differ from it by an item or two."
        if !survey.leftovers.isEmpty {
            let count = survey.leftovers.count
            reason += count == 1
                ? " One file here starts nothing at all and is not counted."
                : " \(count) of these files start nothing at all and are not counted."
        }

        return SecurityRow(topic: .startsOnItsOwn,
                           headline: headline,
                           measure: measure(counted.count),
                           reason: reason,
                           details: details(from: survey))
    }

    /// The row's sentence. Never a bare number, and never "0" for something we did not read.
    static func headline(_ items: [Item]) -> String {
        switch items.count {
        case 0:
            return "Nothing outside macOS itself is set to start on its own."
        case 1:
            return "One thing is set to start on its own."
        default:
            let signed = items.filter(\.isRecognised).count
            if signed == items.count {
                return "\(items.count) things are set to start on their own, all from software "
                     + "we could identify."
            }
            let rest = items.count - signed
            return "\(items.count) things are set to start on their own. "
                 + (rest == 1
                    ? "One of them is not signed by anybody we can name."
                    : "\(rest) of them are not signed by anybody we can name.")
        }
    }

    private static func measure(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    /// Everything more exact, for the Options disclosure.
    ///
    /// ⚠️ `DetailPair` is identified by its label, so every label in this array has to be unique or
    /// a list that draws them collapses two rows into one. `uniquely(_:)` is what guarantees it.
    static func details(from survey: Survey) -> [DetailPair] {
        var pairs: [DetailPair] = []
        var used = Set<String>()

        func add(_ label: String, _ value: String) {
            pairs.append(DetailPair(uniquely(label, in: &used), value))
        }

        for item in survey.items.sorted(by: order) {
            add(item.name, describe(item))
        }

        if !survey.carriedInsideApps.isEmpty {
            let names = survey.carriedInsideApps.map(\.name).sorted()
            add("Apps that carry a background item",
                "\(list(Array(Set(names)).sorted())) — macOS decides whether these run, and that "
              + "switch is in \(applesOwnList). Not counted above.")
        }

        if !survey.leftovers.isEmpty {
            for leftover in survey.leftovers.sorted(by: { $0.file < $1.file }) {
                add(URL(filePath: leftover.file).lastPathComponent,
                    "\(leftover.why) — a leftover, not counted.")
            }
        }

        if let why = survey.cronUnreadable {
            pairs.append(DetailPair(uniquely("Scheduled jobs (cron)", in: &used), unreadable: why))
        } else {
            let jobs = survey.items.filter { $0.origin == .cron }
            add("Scheduled jobs (cron)",
                jobs.isEmpty ? "None for this account" : "\(jobs.count)")
        }
        // Every other account's crontab needs an administrator. Stated once, as a limit of the
        // reading rather than as a finding about the Mac.
        add("Other accounts' scheduled jobs",
            "Only an administrator can read those, so they are not included.")

        if let why = survey.profilesUnreadable {
            pairs.append(DetailPair(uniquely("Configuration profiles", in: &used), unreadable: why))
        } else {
            let profiles = survey.items.filter { $0.origin == .configurationProfile }
            add("Configuration profiles",
                profiles.isEmpty ? "None" : list(profiles.map(\.name).sorted()))
        }

        // ⚠️ Named, and named as harmless. Thirty-one of these on a developer's Mac counted as
        // configuration profiles would be the empty-stub scare all over again.
        if survey.provisioningProfiles > 0 {
            add("Provisioning profiles",
                "\(survey.provisioningProfiles) — these come from Xcode and change nothing about "
              + "how this Mac behaves.")
        }

        if !survey.unreadableFiles.isEmpty {
            add("Files we could not read", list(survey.unreadableFiles.map {
                URL(filePath: $0).lastPathComponent
            }.sorted()))
        }

        add("Files opened", "\(survey.filesRead)")
        add("Where we looked", survey.foldersSearched.joined(separator: ", "))
        add("Apple's own list", applesOwnList)

        return pairs
    }

    /// A fixed order, so two runs on the same Mac draw the same list in the same order.
    private static func order(_ a: Item, _ b: Item) -> Bool {
        if a.origin != b.origin {
            let cases = Origin.allCases
            return (cases.firstIndex(of: a.origin) ?? 0) < (cases.firstIndex(of: b.origin) ?? 0)
        }
        if a.name != b.name { return a.name < b.name }
        return a.label < b.label
    }

    /// "Starts when you log in · Microsoft Corporation".
    static func describe(_ item: Item) -> String {
        var parts = [item.trigger.sentence]
        parts.append(item.developer ?? "Not signed by anybody we can name")
        if item.disabled { parts.append("switched off") }
        return parts.joined(separator: " · ")
    }

    /// "a, b and c" — and never a raw array description on a screen.
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0:  return "None"
        case 1:  return names[0]
        case 2:  return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and \(names[names.count - 1])"
        }
    }

    /// `DetailPair` is identified by its label, so a list that draws two pairs with the same label
    /// collapses them into one row. Shared with `BrowserExtensionReader`, which builds its Options
    /// list from extension names and has exactly the same problem.
    static func uniquely(_ label: String, in used: inout Set<String>) -> String {
        guard used.contains(label) else {
            used.insert(label)
            return label
        }
        var attempt = 2
        while used.contains("\(label) (\(attempt))") { attempt += 1 }
        let unique = "\(label) (\(attempt))"
        used.insert(unique)
        return unique
    }

    // MARK: - Reading a launchd folder

    private static func read(folder: URL,
                             origin: Origin,
                             into survey: inout Survey,
                             fileManager: FileManager) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return }

        for name in names.sorted() where name.hasSuffix(".plist") {
            let file = folder.appending(path: name, directoryHint: .notDirectory)
            survey.filesRead += 1

            guard let job = plist(at: file) else {
                survey.unreadableFiles.append(file.path)
                continue
            }
            switch interpret(job: job, file: file, origin: origin) {
            case let .item(item):          survey.items.append(item)
            case let .leftover(leftover):  survey.leftovers.append(leftover)
            }
        }
    }

    enum Outcome: Sendable, Hashable {
        case item(Item)
        case leftover(Leftover)
    }

    /// **The parse that decides whether a file counts.**
    ///
    /// Exposed rather than private because it is the one piece of judgement in this file, and a
    /// test that cannot reach it cannot hold the rule the header is about.
    static func interpret(job: [String: Any],
                          file: URL,
                          origin: Origin,
                          fileManager: FileManager = .default) -> Outcome {

        let label = (job["Label"] as? String) ?? ""
        let arguments = job["ProgramArguments"] as? [String]
        let declared = (job["Program"] as? String) ?? arguments?.first

        // The two Google stubs land here: `<dict/>` parses fine and says nothing at all.
        guard !label.isEmpty || declared != nil else {
            return .leftover(Leftover(file: file.path, why: "An empty file that starts nothing"))
        }
        guard let declared, !declared.isEmpty else {
            return .leftover(Leftover(file: file.path, why: "Names no program to run"))
        }

        // ⚠️ Only an *absolute* path that is missing makes something a leftover. A bare command
        // name is resolved through the usual folders, and if that fails it is still reported as an
        // item, because `launchd` may well find it where we did not. Dropping a real startup item
        // is the more expensive mistake of the two.
        let resolved = resolve(program: declared, fileManager: fileManager)
        if declared.hasPrefix("/"), resolved == nil {
            return .leftover(Leftover(file: file.path,
                                      why: "Points at a program that is not on this Mac"))
        }

        let program = resolved ?? declared
        let identity = label.isEmpty ? file.deletingPathExtension().lastPathComponent : label

        // ⚠️ `/usr/bin/open -a Whatever.app` runs Whatever, not `open`. Naming the launcher would
        // put "open · Apple" on the row for a job Apple has nothing to do with — a signature
        // attributed to the wrong party, which is worse than no signature at all.
        if launchers.contains(program) {
            guard let target = target(of: arguments, fileManager: fileManager) else {
                return .item(Item(label: identity,
                                  name: identity,
                                  developer: nil,
                                  program: program,
                                  origin: origin,
                                  trigger: trigger(job: job, origin: origin),
                                  disabled: (job["Disabled"] as? Bool) ?? false,
                                  file: file.path))
            }
            return .item(item(identity: identity, program: target, job: job,
                              origin: origin, file: file))
        }

        return .item(item(identity: identity, program: program, job: job,
                          origin: origin, file: file))
    }

    private static func item(identity: String,
                             program: String,
                             job: [String: Any],
                             origin: Origin,
                             file: URL) -> Item {
        let url = URL(filePath: program)
        return Item(label: identity,
                    name: name(ofProgramAt: url),
                    developer: developerName(of: enclosingBundle(of: url) ?? url),
                    program: program,
                    origin: origin,
                    trigger: trigger(job: job, origin: origin),
                    disabled: (job["Disabled"] as? Bool) ?? false,
                    file: file.path)
    }

    /// Programs whose whole job is to start something else.
    ///
    /// Kept short and literal. Anything on this list makes the reader look past it for what is
    /// actually being run; anything not on it is taken at face value, which is the safe default.
    static let launchers: Set<String> = [
        "/usr/bin/open", "/usr/bin/env", "/usr/bin/arch", "/usr/bin/nohup",
        "/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/osascript",
        "/usr/bin/python3", "/usr/bin/ruby", "/usr/bin/perl"
    ]

    /// The first argument after a launcher that names something on disk.
    ///
    /// Flags are skipped; a bare name that resolves nowhere gives `nil`, and the caller then
    /// reports the item without a developer rather than crediting the launcher's signer.
    static func target(of arguments: [String]?, fileManager: FileManager = .default) -> String? {
        guard let arguments else { return nil }
        for argument in arguments.dropFirst() {
            guard !argument.hasPrefix("-"), !argument.isEmpty else { continue }
            if let found = resolve(program: argument, fileManager: fileManager) { return found }
        }
        return nil
    }

    /// When this job runs, read out of the file rather than assumed.
    static func trigger(job: [String: Any], origin: Origin) -> Trigger {
        if let seconds = job["StartInterval"] as? Int, seconds > 0 {
            return .onASchedule("Runs \(every(seconds: seconds))")
        }
        if let calendar = job["StartCalendarInterval"] {
            return .onASchedule(schedule(calendar))
        }
        if (job["RunAtLoad"] as? Bool) == true {
            return origin == .globalDaemon ? .atStartup : .atLogin
        }
        if (job["KeepAlive"] as? Bool) == true || job["KeepAlive"] is [String: Any] {
            return .keptRunning
        }
        if job["WatchPaths"] != nil || job["QueueDirectories"] != nil {
            return .whenAFolderChanges
        }
        if job["MachServices"] != nil {
            return .whenSomethingAsksForIt
        }
        return .whenMacOSDecides
    }

    /// 3600 → "every hour". Whole units only; nobody needs "every 1.0 hours".
    static func every(seconds: Int) -> String {
        switch seconds {
        case ..<60:                        return seconds == 1 ? "every second" : "every \(seconds) seconds"
        case ..<3_600 where seconds % 60 == 0:
            let minutes = seconds / 60
            return minutes == 1 ? "every minute" : "every \(minutes) minutes"
        case ..<86_400 where seconds % 3_600 == 0:
            let hours = seconds / 3_600
            return hours == 1 ? "every hour" : "every \(hours) hours"
        case _ where seconds % 86_400 == 0:
            let days = seconds / 86_400
            return days == 1 ? "every day" : "every \(days) days"
        default:
            return "every \(seconds / 60) minutes"
        }
    }

    /// `StartCalendarInterval` — one dictionary or an array of them — put into words.
    ///
    /// The time is formatted through the reader's own region rather than hard-coded to 24 hours:
    /// "02:30" is a foreign-looking string to most of the people this app is for.
    static func schedule(_ raw: Any) -> String {
        let entries: [[String: Any]]
        if let one = raw as? [String: Any] { entries = [one] }
        else if let many = raw as? [[String: Any]] { entries = many }
        else { return "Runs on a schedule" }

        let times = entries.compactMap { entry -> String? in
            guard let hour = entry["Hour"] as? Int else { return nil }
            let minute = (entry["Minute"] as? Int) ?? 0
            var parts = DateComponents()
            parts.hour = hour
            parts.minute = minute
            guard let moment = Calendar(identifier: .gregorian).date(from: parts) else { return nil }
            return moment.formatted(date: .omitted, time: .shortened)
        }

        guard !times.isEmpty else { return "Runs on a schedule" }
        return "Runs every day at \(list(times))"
    }

    // MARK: - Background items apps carry inside themselves

    /// An app that registers with `SMAppService` keeps the job description inside its own bundle.
    ///
    /// ⚠️ **Whether it is switched on lives in the store we are not allowed to read.** Microsoft
    /// Teams carries two of these on this Mac; whether either is actually registered is a fact only
    /// `sfltool` can print, and `sfltool` raises a password box. So these are gathered, shown, and
    /// **kept out of the count** — a bundled agent nobody enabled is a file, not a startup item,
    /// and this file's whole rule is that we count items.
    private static func readBundledItems(inApplications folder: URL,
                                         into survey: inout Survey,
                                         fileManager: FileManager) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return }
        survey.foldersSearched.append(folder.path)

        for appName in names.sorted() where appName.hasSuffix(".app") {
            let app = folder.appending(path: appName, directoryHint: .isDirectory)
            for sub in ["Contents/Library/LaunchAgents", "Contents/Library/LaunchDaemons"] {
                let inside = app.appending(path: sub, directoryHint: .isDirectory)
                guard let jobs = try? fileManager.contentsOfDirectory(atPath: inside.path) else {
                    continue
                }
                for job in jobs.sorted() where job.hasSuffix(".plist") {
                    let file = inside.appending(path: job, directoryHint: .notDirectory)
                    survey.filesRead += 1
                    guard let parsed = plist(at: file) else {
                        survey.unreadableFiles.append(file.path)
                        continue
                    }
                    let label = (parsed["Label"] as? String)
                        ?? file.deletingPathExtension().lastPathComponent
                    survey.carriedInsideApps.append(
                        Item(label: label,
                             name: name(ofBundleAt: app) ?? appName,
                             developer: developerName(of: app),
                             program: parsed["Program"] as? String
                                   ?? (parsed["ProgramArguments"] as? [String])?.first,
                             origin: .appBundled,
                             trigger: trigger(job: parsed, origin: .appBundled),
                             disabled: (parsed["Disabled"] as? Bool) ?? false,
                             file: file.path))
                }
            }
        }
    }

    // MARK: - cron

    /// This account's scheduled jobs.
    ///
    /// ⚠️ `/usr/lib/cron/tabs` is `0700 root:wheel` — we cannot read the file, and `crontab -l` is
    /// the only route. Other accounts' crontabs need an administrator, which is `.notGrantable`:
    /// no permission this app could ask for would ever show them. An **empty** crontab is a real
    /// answer and is reported as none, not as unreadable.
    private static func readCron(into survey: inout Survey) {
        let tool = URL(filePath: "/usr/bin/crontab")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            survey.cronUnreadable = .notReported
            return
        }
        guard let output = toolOutput(tool, ["-l"], timeout: 4) else {
            survey.cronUnreadable = .notGrantable
            return
        }
        for line in String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            // A crontab line is five schedule fields and then the command. Anything with fewer is
            // an environment assignment (`PATH=…`), which schedules nothing.
            let fields = trimmed.split(separator: " ", maxSplits: 5,
                                       omittingEmptySubsequences: true)
            guard fields.count == 6 else { continue }
            let command = String(fields[5])
            let first = command.split(separator: " ").first.map(String.init) ?? command
            let programURL = resolve(program: first).map { URL(filePath: $0) }
            survey.items.append(
                Item(label: command,
                     name: programURL.map { name(ofProgramAt: $0) } ?? first,
                     developer: programURL.flatMap { developerName(of: enclosingBundle(of: $0) ?? $0) },
                     program: programURL?.path ?? first,
                     origin: .cron,
                     trigger: .onASchedule("Runs on a schedule (\(fields[0..<5].joined(separator: " ")))"),
                     disabled: false,
                     file: "this account's crontab"))
        }
    }

    // MARK: - Configuration profiles

    /// Device and user configuration profiles — and **not** Xcode's provisioning profiles.
    ///
    /// See the header. `system_profiler` puts all three in one report; the section names are the
    /// raw English keys even on a localised Mac, but an unrecognised one is reverse-mapped through
    /// `AppleWords` rather than guessed at, because a section name we do not recognise must never
    /// silently become a configuration profile.
    private static func readConfigurationProfiles(into survey: inout Survey) {
        let tool = URL(filePath: "/usr/sbin/system_profiler")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            survey.profilesUnreadable = .notReported
            return
        }
        guard let data = toolOutput(tool, ["SPConfigurationProfileDataType", "-json"], timeout: 8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = parsed["SPConfigurationProfileDataType"] as? [[String: Any]] else {
            survey.profilesUnreadable = .notReported
            return
        }

        for group in groups {
            let name = (group["_name"] as? String) ?? ""
            let items = (group["_items"] as? [[String: Any]]) ?? []

            switch section(named: name) {
            case .provisioning:
                survey.provisioningProfiles += items.count
            case .configuration:
                for item in items {
                    let title = (item["_name"] as? String) ?? "A configuration profile"
                    let organisation = item["spconfigprofile_organization"] as? String
                    survey.items.append(
                        Item(label: (item["spconfigprofile_profile_identifier"] as? String) ?? title,
                             name: title,
                             developer: organisation,
                             program: nil,
                             origin: .configurationProfile,
                             trigger: .atStartup,
                             disabled: false,
                             file: "installed on this Mac"))
                }
            case .unknown:
                // Neither counted nor discarded silently — a section we do not recognise is worth
                // one honest line rather than a number nobody can check.
                if !items.isEmpty { survey.unreadableFiles.append(name) }
            }
        }
    }

    enum ProfileSection: Sendable, Hashable { case configuration, provisioning, unknown }

    /// `spconfigprofile_section_deviceconfigprofiles` → `.configuration`.
    static func section(named name: String) -> ProfileSection {
        if name.hasPrefix("spconfigprofile_section_prov") { return .provisioning }
        if name.hasPrefix("spconfigprofile_section_device")
            || name.hasPrefix("spconfigprofile_section_user") { return .configuration }

        // A localised or renamed section name, turned back into its key. Nothing is guessed: an
        // ambiguous or unrecognised answer stays `.unknown`.
        let meaning = AppleWords.meaning(
            of: name,
            from: .configurationProfiles,
            keys: ["spconfigprofile_section_deviceconfigprofiles": ProfileSection.configuration,
                   "spconfigprofile_section_userconfigprofiles": .configuration,
                   "spconfigprofile_section_userconfigprofilesWithUID": .configuration,
                   "spconfigprofile_section_provprofiles": .provisioning])
        return meaning.certainValue ?? .unknown
    }

    // MARK: - Resolving a program to a name and a signature

    /// A declared program turned into a path that exists, or `nil`.
    ///
    /// `launchd` accepts a bare command and finds it on its own path. `/usr/bin/open` was absolute
    /// on this Mac, but the shape is allowed and a reader that only understood absolute paths would
    /// call a working item a leftover.
    static func resolve(program: String, fileManager: FileManager = .default) -> String? {
        if program.hasPrefix("/") {
            return fileManager.fileExists(atPath: program) ? program : nil
        }
        for folder in ["/usr/bin", "/bin", "/usr/sbin", "/sbin",
                       "/usr/local/bin", "/opt/homebrew/bin"] {
            let candidate = "\(folder)/\(program)"
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// The app bundle a program lives inside, where it lives inside one.
    ///
    /// A launch agent almost always points at a binary buried in `Contents/MacOS`, and the useful
    /// name and the signature both belong to the bundle around it, not to the file.
    static func enclosingBundle(of program: URL) -> URL? {
        var walk = program
        while walk.pathComponents.count > 1 {
            if walk.pathExtension == "app" || walk.pathExtension == "appex" { return walk }
            walk = walk.deletingLastPathComponent()
        }
        return nil
    }

    /// The best honest name for a program: the enclosing app's, or the file's own.
    ///
    /// ⚠️ Never derived from the `launchd` label. Turning `com.microsoft.update.agent` into
    /// "Microsoft Update Agent" reads like a fact and is a guess.
    static func name(ofProgramAt program: URL) -> String {
        if let bundle = enclosingBundle(of: program), let name = name(ofBundleAt: bundle) {
            return name
        }
        return program.lastPathComponent
    }

    /// An app bundle's display name, from its own `Info.plist`.
    static func name(ofBundleAt bundle: URL) -> String? {
        let info = bundle.appending(path: "Contents/Info.plist", directoryHint: .notDirectory)
        guard let plist = plist(at: info) else {
            let stem = bundle.deletingPathExtension().lastPathComponent
            return stem.isEmpty ? nil : stem
        }
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = plist[key] as? String, !name.isEmpty { return name }
        }
        let stem = bundle.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? nil : stem
    }

    // MARK: - Shared with BrowserExtensionReader

    /// **Who signed this, in a name a person recognises** — or `nil`, which means unrecognised.
    ///
    /// Shared with `BrowserExtensionReader`, which needs exactly the same answer about the app a
    /// Safari extension is carried inside. One copy on purpose: two would drift, and the wording of
    /// "we could not identify a signer" is the sentence that decides whether this app reads as a
    /// health check or as an accusation.
    ///
    /// What the certificate actually says, measured on this Mac:
    ///
    ///     Developer ID Application: Microsoft Corporation (UBF8T346G9)  → Microsoft Corporation
    ///     macOS Software Signing                                        → Apple
    ///     Apple Mac OS Application Signing                              → the Mac App Store
    ///     (a shell script with no signature)                            → nil
    ///
    /// ⚠️ **`Apple Mac OS Application Signing` is not Apple the developer.** It is the receipt
    /// Apple staples onto a Mac App Store app, and the publisher's name is nowhere in it. Reporting
    /// "Apple" for every App Store app would be wrong about who wrote the software.
    static func developerName(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }

        var informationRef: CFDictionary?
        guard SecCodeCopySigningInformation(code,
                                            SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &informationRef) == errSecSuccess,
              let information = informationRef as? [String: Any],
              let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String? else { return nil }

        return organisation(inCertificateSummary: summary)
    }

    /// The readable half of a signing certificate's subject.
    static func organisation(inCertificateSummary summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "Software Signing" || trimmed.hasSuffix("macOS Software Signing") {
            return "Apple"
        }
        if trimmed == "Apple Mac OS Application Signing" {
            return "From the Mac App Store"
        }
        for prefix in ["Developer ID Application: ", "Developer ID Installer: ",
                       "Apple Development: ", "Apple Distribution: ",
                       "3rd Party Mac Developer Application: ",
                       "Mac Developer: "] where trimmed.hasPrefix(prefix) {
            let body = String(trimmed.dropFirst(prefix.count))
            // Trailing " (TEAMID)" is Apple's, not the publisher's name.
            guard let open = body.lastIndex(of: "("), body.hasSuffix(")") else { return body }
            let name = body[..<open].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? body : name
        }
        return trimmed
    }

    /// A property list at a path, or `nil` where it will not parse.
    ///
    /// `nil` is deliberately different from an empty dictionary: an empty dictionary is the Google
    /// stub and is a finding, while `nil` is a file we could not read and is not.
    static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data,
                                                            options: [],
                                                            format: nil)) as? [String: Any]
    }

    /// Run a tool and take its output, with a watchdog.
    ///
    /// The same shape as `BatteryReader.systemProfilerPowerData` — output drained *before*
    /// `waitUntilExit`, which is the order that stops a chatty child filling the pipe while the
    /// parent waits for it to exit. Shared with `BrowserExtensionReader`, which needs `pluginkit`.
    ///
    /// Nothing here can raise an authorization dialog: `crontab -l`, `system_profiler` and
    /// `pluginkit` all read what the current account may already read, and refuse quietly when it
    /// may not.
    static func toolOutput(_ tool: URL, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        let watchdog = Watchdog(process)
        let killer = DispatchWorkItem { watchdog.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    /// One reference, two threads, and the only thing either does with it is ask whether the
    /// process is still running.
    private final class Watchdog: @unchecked Sendable {
        private let process: Process
        init(_ process: Process) { self.process = process }
        func terminate() { if process.isRunning { process.terminate() } }
    }
}
