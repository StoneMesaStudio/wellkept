import Foundation
import OpenDirectory
import WellkeptCore

//  ReachableReader.swift
//  Wellkept — App/Security
//
//  **What can reach this Mac** — Screen Sharing, Remote Login, File Sharing, Remote Management,
//  AirPlay Receiver, the guest account, and folders shared with guests.
//
//  ## ⚠️ The one rule this whole file is built around
//
//  **We can prove a service is ON. We can never prove one is off.**
//
//  There is no reading anywhere on macOS that distinguishes "Screen Sharing is switched off" from
//  "Screen Sharing is on and we failed to see it". The preference files the internet names for
//  these were reorganised years ago; the launchd job state is behind a root-only store; and the
//  only honest evidence available to an ordinary app is a socket that is actually listening.
//
//  So this row never prints "Off" for a service, and `Standing` has no `.off` case for one to be
//  printed from. What it says instead is what it saw, and it says out loud that seeing nothing is
//  not the same as there being nothing. A row that confidently said "Remote Login: Off" about a
//  Mac somebody can log into is the single worst sentence this section could produce.
//
//  ## What is measured, and what each thing proves
//
//  Verified by hand on one real Mac, 2026-08-27, all read-only and none of it raising a dialog:
//
//  - **Listening sockets** — `netstat -an`. Unprivileged, unlocalised, and it reports the *bind
//    address*, which is the difference between "only this Mac can reach it" (127.0.0.1) and
//    "anything on your network can reach it" (`*`). That difference is the row's whole subject.
//    `lsof` was considered and dropped: without root it sees only the current user's own
//    processes, so it is blind to exactly the services that matter — `sshd` and `screensharingd`
//    both run as root.
//  - **Shared folders** — OpenDirectory, `/Local/Default`, record type SharePoints. Readable
//    without privilege, no subprocess. This Mac reports one: the Public folder, `smb_shared: 1`,
//    `smb_guestaccess: 1`.
//  - **The guest account** — `GuestEnabled` in `/Library/Preferences/com.apple.loginwindow.plist`,
//    which is world-readable.
//
//  ## ⚠️ Configuration is not observation, and the row keeps them apart
//
//  This Mac is the case in point. The Public folder **is set up to be shared with guests**, and
//  File Sharing is **not observed listening** — so nobody can currently reach it. Both facts are
//  true, and reporting either one alone would mislead: "a folder is open to guests" is a scare,
//  and "nothing is shared" is wrong. The row states the setting, and states separately what was
//  seen listening.
//
//  ## ⚠️ Nothing here is amber, and nothing here can be
//
//  None of the nine conditions in `SecurityConcern` is about a sharing service, so this row cannot
//  raise one — `SecurityRow.severity` is computed from concerns and there is no other route. That
//  is deliberate and it is settled 2026-08-27: on a real Mac the honest output is *AirPlay
//  Receiver is listening* and *the Public folder is shared with guests*, and neither is a crisis.
//  Both are plain facts with no colour. A tenth condition is a conversation with the developer.

enum ReachableReader {

    // MARK: - The ways in

    /// The services this row is about. Fixed list, fixed order, and it never grows by accident:
    /// every entry here is something a person can switch on in Sharing, with a port that proves it.
    enum Service: String, CaseIterable, Sendable, Hashable, Identifiable {
        case screenSharing
        case remoteLogin
        case fileSharing
        case remoteManagement
        case airPlayReceiver

        var id: String { rawValue }

        var label: String {
            switch self {
            case .screenSharing:    "Screen Sharing"
            case .remoteLogin:      "Remote Login"
            case .fileSharing:      "File Sharing"
            case .remoteManagement: "Remote Management"
            case .airPlayReceiver:  "AirPlay Receiver"
            }
        }

        /// What another machine can do with it, in one plain sentence.
        var explanation: String {
            switch self {
            case .screenSharing:
                "Lets another machine see and control this screen."
            case .remoteLogin:
                "Lets another machine open a command line on this Mac, over SSH."
            case .fileSharing:
                "Lets another machine open the folders you have shared."
            case .remoteManagement:
                "Lets an administrator's machine watch, control and install software on this Mac."
            case .airPlayReceiver:
                "Lets another Apple device send its screen or its sound to this Mac."
            }
        }

        /// The ports that are treated as proof.
        ///
        /// ⚠️ **Deliberately narrow.** AirPlay Receiver also holds port 5000, and 5000 is one of
        /// the most-used ports in software development — a person running a local web server would
        /// be told AirPlay was on. Only 7000 counts. Screen Sharing's 5900 has the same problem in
        /// milder form (third-party VNC servers use it), which is why the Options line names the
        /// port rather than asserting the product.
        var ports: [Int] {
            switch self {
            case .screenSharing:    [5900]
            case .remoteLogin:      [22]
            case .fileSharing:      [445, 139]
            case .remoteManagement: [3283]
            case .airPlayReceiver:  [7000]
            }
        }

        /// The sentence for the Options line when nothing was seen on those ports.
        ///
        /// It is a whole sentence rather than the word "Off" on purpose. See the file header.
        var notSeenSentence: String {
            "Not seen listening. macOS gives no way to prove a service is switched off, "
                + "so this is what we could observe rather than a complete answer."
        }
    }

    /// Where something listening can be reached from — read off the address it is bound to.
    enum Reach: String, Sendable, Hashable, Codable {
        /// Bound to every address: anything on the same network can reach it.
        case localNetwork
        /// Bound to the loopback address: only programs on this Mac can reach it.
        case thisMacOnly
        /// Bound to one particular address on this Mac.
        case oneAddress

        var clause: String {
            switch self {
            case .localNetwork: "reachable from the local network"
            case .thisMacOnly:  "reachable only from this Mac"
            case .oneAddress:   "reachable on one of this Mac's network addresses"
            }
        }
    }

    /// ⚠️ **There is no `.off`, and there must never be one.** See the file header.
    enum Standing: Sendable, Hashable {
        case listening(Reach)
        case notObserved

        var isListening: Bool {
            if case .listening = self { return true }
            return false
        }

        var reach: Reach? {
            if case let .listening(reach) = self { return reach }
            return nil
        }
    }

    /// One service, and what was seen of it.
    struct Observation: Sendable, Hashable, Identifiable {
        let service: Service
        let standing: Standing
        /// The ports it was actually seen on. Empty when nothing was seen.
        let ports: [Int]

        var id: String { service.rawValue }
    }

    // MARK: - What the machine reported

    /// One socket this Mac is listening on.
    struct Socket: Sendable, Hashable {
        let port: Int
        /// As `netstat` printed it: `*`, `127.0.0.1`, `::1`, `192.168.1.14`, `fe80::1%lo0`.
        let address: String
        /// `true` for a UDP socket bound to a port. Remote Management is the reason UDP is read at
        /// all — its agent answers on 3283 over both.
        let isUDP: Bool

        var isLoopback: Bool {
            address == "127.0.0.1" || address == "::1" || address.hasPrefix("127.")
        }

        var isEveryAddress: Bool { address == "*" || address == "0.0.0.0" || address == "::" }

        var reach: Reach {
            if isEveryAddress { return .localNetwork }
            if isLoopback { return .thisMacOnly }
            return .oneAddress
        }
    }

    /// One folder this Mac is set up to share.
    ///
    /// **A setting, not an observation.** The folder is shareable; whether anything is currently
    /// serving it is a separate question, answered by `Service.fileSharing`.
    struct SharedFolder: Sendable, Hashable, Identifiable {
        let name: String
        let path: String?
        /// Anyone may open it without a password.
        let guestAccess: Bool

        var id: String { name }
    }

    /// Everything one look at this Mac produced. `nil` on a field means we could not read it —
    /// which is never the same as an empty list, and the row keeps the two apart.
    struct Survey: Sendable, Hashable {
        /// `nil` where the listening sockets could not be listed at all.
        let sockets: [Socket]?
        /// `nil` where the setting could not be read.
        let guestLoginEnabled: Bool?
        /// `nil` where the sharing setup could not be read.
        let sharedFolders: [SharedFolder]?

        init(sockets: [Socket]? = nil,
             guestLoginEnabled: Bool? = nil,
             sharedFolders: [SharedFolder]? = nil) {
            self.sockets = sockets
            self.guestLoginEnabled = guestLoginEnabled
            self.sharedFolders = sharedFolders
        }
    }

    // MARK: - The row

    /// Read this Mac and build the row.
    ///
    /// Blocking work — one short-lived subprocess and two directory reads — so it belongs on a
    /// detached task with the rest of the Security sweep, not on the main actor.
    static func read() -> SecurityRow { row(from: survey()) }

    /// The row, from a survey. **Pure**, so every sentence below can be tested against a Mac
    /// nobody owns: one with Remote Login open to the world, one that refused every read.
    static func row(from survey: Survey) -> SecurityRow {
        let observations = observations(from: survey.sockets)
        let listening = observations.filter { $0.standing.isListening }
        let shared = survey.sharedFolders ?? []
        let guestShared = shared.filter(\.guestAccess)
        let guestLoginOn = survey.guestLoginEnabled == true

        // ⚠️ Nothing was read at all → say so, rather than say nothing is listening. This is the
        // whole "never report zero because we could not look" rule, in the one place in this file
        // where it could be broken.
        //
        // `.notReported` rather than `.notPermitted`: no permission grant produces a socket list.
        // A row with no button, and a check that stays complete.
        if survey.sockets == nil, survey.sharedFolders == nil, survey.guestLoginEnabled == nil {
            return .unreadable(.reachableFrom, .notReported,
                               about: "What can reach this Mac",
                               reason: "We could not list what this Mac is listening on, and could "
                                     + "not read its sharing setup. Nothing here says a service is "
                                     + "off — only that we did not see one.",
                               details: [howWeLooked(survey)])
        }

        return SecurityRow(
            topic: .reachableFrom,
            headline: headline(listening: listening,
                               guestShared: guestShared,
                               guestLoginOn: guestLoginOn),
            measure: measure(listening: listening),
            reason: reason(survey: survey,
                           observations: observations,
                           guestShared: guestShared),
            details: details(survey: survey, observations: observations, shared: shared)
        )
    }

    // MARK: What was seen

    /// Match the sockets against the fixed service list. Always returns one observation per
    /// service, in `Service.allCases` order — a service we saw nothing of still gets its line, and
    /// that line says what "saw nothing" means.
    static func observations(from sockets: [Socket]?) -> [Observation] {
        Service.allCases.map { service in
            let matches = (sockets ?? []).filter { service.ports.contains($0.port) }
            guard let widest = matches.min(by: { rank($0.reach) < rank($1.reach) }) else {
                return Observation(service: service, standing: .notObserved, ports: [])
            }
            return Observation(service: service,
                               standing: .listening(widest.reach),
                               ports: Array(Set(matches.map(\.port))).sorted())
        }
    }

    /// Reach, worst-first: a service bound to every address is reported as reachable from the
    /// network even if it is *also* bound to loopback, which is the ordinary arrangement.
    private static func rank(_ reach: Reach) -> Int {
        switch reach {
        case .localNetwork: 0
        case .oneAddress:   1
        case .thisMacOnly:  2
        }
    }

    // MARK: The words

    /// The row's own sentence.
    ///
    /// It states what was observed and nothing else. On one real Mac it reads *"AirPlay
    /// Receiver is listening, and one folder is set up to be shared with guests allowed."* — two
    /// true things, neither of them an alarm.
    static func headline(listening: [Observation],
                         guestShared: [SharedFolder],
                         guestLoginOn: Bool) -> String {
        var clauses: [String] = []

        if !listening.isEmpty {
            let names = list(listening.map(\.service.label))
            clauses.append("\(names) \(listening.count == 1 ? "is" : "are") listening")
        }
        if let folders = guestFolderClause(guestShared) {
            clauses.append(folders)
        }
        if guestLoginOn {
            clauses.append("this Mac's guest login is switched on")
        }

        guard !clauses.isEmpty else {
            return "Nothing we can see is listening for another machine, and nothing here is "
                 + "shared with guests."
        }
        return sentence(from: clauses)
    }

    private static func guestFolderClause(_ folders: [SharedFolder]) -> String? {
        switch folders.count {
        case 0:  return nil
        case 1:  return "\(folders[0].name) is set up to be shared, with guests allowed"
        default: return "\(folders.count) folders are set up to be shared, with guests allowed"
        }
    }

    /// The count on the row. `nil` where nothing was seen — a row that prints "0 listening" is a
    /// row claiming a negative it cannot prove.
    static func measure(listening: [Observation]) -> String? {
        guard !listening.isEmpty else { return nil }
        return listening.count == 1 ? "1 service" : "\(listening.count) services"
    }

    /// ⚠️ **Why the row says what it says, and it always names the limit of what was looked at.**
    ///
    /// The caveat is not optional and not conditional: it is here on a Mac with five services
    /// listening and on a Mac with none, because it is a fact about our method rather than about
    /// the machine.
    static func reason(survey: Survey,
                       observations: [Observation],
                       guestShared: [SharedFolder]) -> String {
        var parts: [String] = []

        // The one nuance this Mac actually produces: a folder configured for guests while nothing
        // is serving it. Stating only half of that would be a scare or a false comfort.
        if !guestShared.isEmpty,
           observations.first(where: { $0.service == .fileSharing })?.standing.isListening == false {
            parts.append("The shared folder is a setting, not an open door: we did not see File "
                       + "Sharing listening, though we cannot prove it is switched off.")
        }

        if let wide = observations.first(where: { $0.standing.reach == .localNetwork }) {
            parts.append("\(wide.service.label) is bound to every network address, so anything on "
                       + "the same network can try to reach it.")
        }

        parts.append("We looked at what this Mac is listening on. A service that is switched off "
                   + "and one we simply could not see look the same from here, so nothing above "
                   + "says a service is off.")

        if survey.sockets == nil {
            parts.append("The list of what this Mac is listening on could not be read at all on "
                       + "this run.")
        }

        return parts.joined(separator: " ")
    }

    /// Everything more exact, behind **Options**.
    static func details(survey: Survey,
                        observations: [Observation],
                        shared: [SharedFolder]) -> [DetailPair] {
        var pairs: [DetailPair] = []

        for observation in observations {
            pairs.append(DetailPair(observation.service.label, value(for: observation)))
        }

        pairs.append(DetailPair("Guest login", guestLoginValue(survey.guestLoginEnabled)))

        if let folders = survey.sharedFolders {
            if folders.isEmpty {
                pairs.append(DetailPair("Shared folders", "None are set up."))
            } else {
                var used = Set<String>()
                for folder in folders {
                    // `DetailPair.id` is its label, and two share points can carry the same name.
                    var label = "Shared folder — \(folder.name)"
                    var suffix = 2
                    while !used.insert(label).inserted {
                        label = "Shared folder — \(folder.name) (\(suffix))"
                        suffix += 1
                    }
                    let where_ = folder.path ?? "Location not reported"
                    let who = folder.guestAccess
                        ? "guests allowed — anyone can open it without a password"
                        : "a password is needed"
                    pairs.append(DetailPair(label, "\(where_) — \(who)"))
                }
            }
        } else {
            pairs.append(DetailPair("Shared folders", unreadable: .notReported))
        }

        if let others = otherPortsValue(survey.sockets, observations: observations) {
            pairs.append(DetailPair("Other ports open to the network", others))
        }

        pairs.append(howWeLooked(survey))
        return pairs
    }

    private static func value(for observation: Observation) -> String {
        guard case let .listening(reach) = observation.standing else {
            return observation.service.notSeenSentence
        }
        let ports = observation.ports.map(String.init).joined(separator: ", ")
        let noun = observation.ports.count == 1 ? "port" : "ports"
        // Named as "the port X uses" rather than asserted, because a third-party program can hold
        // the same port — VNC servers on 5900 being the common case.
        return "Something is listening on \(noun) \(ports), which \(observation.service.label) "
             + "uses, \(reach.clause)."
    }

    private static func guestLoginValue(_ enabled: Bool?) -> String {
        switch enabled {
        case true:
            "On — anybody can sign in to this Mac without a password, into an account that is "
                + "wiped when they log out."
        case false:
            "Off, as this Mac's own setting reports it."
        case nil:
            Unreadable.notReported.sentence
        }
    }

    /// What macOS itself is doing on a port, where we can say so honestly.
    ///
    /// ⚠️ **Only Apple's own.** A table naming third-party products by port would be wrong the
    /// moment somebody ran a different program on 3306, and it would be wrong invisibly. These five
    /// are macOS's own machinery and are the ones that would otherwise read as mysterious.
    static let macOSPortNames: [Int: String] = [
        137: "Windows file discovery",
        138: "Windows file discovery",
        631: "printing",
        5000: "AirPlay's second port",
        5353: "Bonjour, how Apple devices find each other",
    ]

    /// The ports that are open to the network and are not one of the five services.
    ///
    /// ⚠️ **Reported as a plain fact and nothing more**, and the sentence is careful about whose
    /// they are. This Mac's list is 137, 138, 3306, 5353 and half a dozen others — some are macOS's
    /// own and some belong to software somebody installed, and an app that filed the lot under
    /// "programs you installed" would be blaming a person for Bonjour. Nothing here carries colour:
    /// listing somebody's own database under a security heading with a warning on it is inventing
    /// alarm out of their own work. `nil` where there are none, or where nothing could be read.
    static func otherPortsValue(_ sockets: [Socket]?, observations: [Observation]) -> String? {
        guard let sockets else { return nil }
        let known = Set(Service.allCases.flatMap(\.ports))
        let others = Set(sockets.filter { !$0.isLoopback && !known.contains($0.port) }.map(\.port))
        guard !others.isEmpty else { return nil }

        let shown = others.sorted().prefix(10)
        let list = shown
            .map { port in macOSPortNames[port].map { "\(port) (\($0))" } ?? "\(port)" }
            .joined(separator: ", ")
        let more = others.count > shown.count ? ", and \(others.count - shown.count) more" : ""
        return "\(list)\(more). Some of these are macOS's own, and some belong to software "
             + "installed on this Mac. Wellkept does not treat any of them as sharing services."
    }

    private static func howWeLooked(_ survey: Survey) -> DetailPair {
        DetailPair("How we looked",
                   "We listed the ports this Mac is listening on"
                       + (survey.sharedFolders == nil ? "" : " and read its sharing setup")
                       + ". Nothing was changed, and nothing was connected to.")
    }

    // MARK: Small language helpers

    /// "Screen Sharing", "Screen Sharing and Remote Login", "A, B and C".
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and \(items[items.count - 1])"
        }
    }

    /// Join clauses into one sentence and capitalise it, without touching the rest of the string —
    /// `capitalized` would turn "port" into "Port" halfway through.
    private static func sentence(from clauses: [String]) -> String {
        let joined = list(clauses)
        guard let first = joined.first else { return "" }
        return String(first).uppercased() + joined.dropFirst() + "."
    }

    // MARK: - Reading this Mac

    /// Everything this file knows how to read, in one pass.
    static func survey() -> Survey {
        Survey(sockets: listeningSockets(),
               guestLoginEnabled: guestLoginEnabled(),
               sharedFolders: sharedFolders())
    }

    // MARK: The sockets

    static let netstatTool = URL(filePath: "/usr/sbin/netstat")

    /// What this Mac is listening on. `nil` where the list could not be produced.
    static func listeningSockets(tool: URL = netstatTool, timeout: TimeInterval = 5) -> [Socket]? {
        guard let text = run(tool, arguments: ["-an"], timeout: timeout) else { return nil }
        return parseNetstat(text)
    }

    /// Parse `netstat -an`. **Pure**, and the reason this file can be tested at all.
    ///
    /// The format is fixed-column text, unlocalised, and has been the same for twenty years:
    ///
    /// ```
    /// tcp4       0      0  127.0.0.1.631          *.*                    LISTEN
    /// tcp46      0      0  *.7000                 *.*                    LISTEN
    /// udp4       0      0  *.5353                 *.*
    /// ```
    ///
    /// Address and port are separated by the **last** dot, which is what makes an IPv6 line like
    /// `::1.631` parse correctly. Anything that does not look like one of these lines is skipped
    /// rather than guessed at — including the Unix-domain socket table `netstat` prints after the
    /// internet one.
    static func parseNetstat(_ text: String) -> [Socket] {
        var sockets: [Socket] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 5 else { continue }

            let proto = fields[0].lowercased()
            let isUDP: Bool
            if proto.hasPrefix("tcp") {
                // Only a socket in LISTEN is evidence. An established connection on port 5900 is a
                // session somebody already has, not a service accepting new ones.
                guard fields.last == "LISTEN" else { continue }
                isUDP = false
            } else if proto.hasPrefix("udp") {
                // UDP has no state column. A bound socket shows `*.*` as its foreign address; one
                // that is talking to somebody shows an address, and is a conversation rather than
                // a door.
                guard fields.count >= 5, fields[4] == "*.*" else { continue }
                isUDP = true
            } else {
                continue
            }

            guard let socket = socket(fromLocalAddress: fields[3], isUDP: isUDP) else { continue }
            sockets.append(socket)
        }

        return sockets
    }

    private static func socket(fromLocalAddress field: String, isUDP: Bool) -> Socket? {
        guard let dot = field.lastIndex(of: ".") else { return nil }
        let address = String(field[field.startIndex..<dot])
        guard let port = Int(field[field.index(after: dot)...]), port > 0, !address.isEmpty else {
            return nil
        }
        return Socket(port: port, address: address, isUDP: isUDP)
    }

    // MARK: The guest account

    static let loginWindowPreferences =
        URL(filePath: "/Library/Preferences/com.apple.loginwindow.plist")

    /// Whether this Mac lets a guest sign in. `nil` where the setting could not be read.
    ///
    /// The file is world-readable, so this is one of the few things in Security that reads the same
    /// on every account. The key is absent on a Mac that has never been asked — and absent is
    /// reported as unread rather than as off, because we did not read anything.
    static func guestLoginEnabled(file: URL = loginWindowPreferences) -> Bool? {
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                     options: [],
                                                                     format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["GuestEnabled"] as? Bool
    }

    // MARK: The shared folders

    /// The folders this Mac is set up to share, read straight out of the local directory.
    ///
    /// `/var/db/dslocal/nodes/Default/sharepoints/` is root-only, but OpenDirectory serves the same
    /// records to anybody — verified on one real Mac. No subprocess, no privilege, no dialog.
    ///
    /// `nil` where the directory could not be queried at all, which is not the same as a Mac with
    /// nothing shared.
    static func sharedFolders() -> [SharedFolder]? {
        guard let node = try? ODNode(session: ODSession.default(), name: "/Local/Default"),
              let query = try? ODQuery(node: node,
                                       forRecordTypes: kODRecordTypeSharePoints,
                                       attribute: nil,
                                       matchType: ODMatchType(kODMatchAny),
                                       queryValues: nil,
                                       returnAttributes: kODAttributeTypeAllAttributes,
                                       maximumResults: 0),
              let records = try? query.resultsAllowingPartial(false) as? [ODRecord] else {
            return nil
        }

        return records.compactMap { record in
            let name = record.recordName ?? "A shared folder"

            // Only a share point that is actually shared counts. macOS leaves the record behind
            // with `shared: 0` when somebody turns a share off, and listing those would report
            // folders that are not shared as folders that are.
            let shared = flag(record, "smb_shared") || flag(record, "afp_shared")
            guard shared else { return nil }

            return SharedFolder(name: name,
                                path: first(record, "directory_path"),
                                guestAccess: flag(record, "smb_guestaccess")
                                          || flag(record, "afp_guestaccess"))
        }
    }

    private static func first(_ record: ODRecord, _ attribute: String) -> String? {
        guard let values = try? record.values(forAttribute: "dsAttrTypeNative:\(attribute)") else {
            return nil
        }
        return values.compactMap { $0 as? String }.first
    }

    private static func flag(_ record: ODRecord, _ attribute: String) -> Bool {
        first(record, attribute) == "1"
    }

    // MARK: - One short-lived subprocess

    /// Run a tool and read what it printed, with a watchdog.
    ///
    /// The watchdog is the same shape as `BatteryReader`'s and for the same reason: this is a place
    /// where the app hands control to another process, and a version of that process which blocks
    /// would otherwise hold the whole Security check open for as long as it liked. The output is
    /// drained **before** `waitUntilExit` — a child filling the pipe while the parent waits for it
    /// to exit is a deadlock, and it is one that only appears on the machine with the most to say.
    private static func run(_ tool: URL, arguments: [String], timeout: TimeInterval) -> String? {
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }

        let process = Process()
        process.executableURL = tool
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        let box = Watchdog(process)
        let killer = DispatchWorkItem { box.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// One reference, read from two threads, and all either of them does is ask whether the process
    /// is still running.
    private final class Watchdog: @unchecked Sendable {
        private let process: Process
        init(_ process: Process) { self.process = process }
        func terminate() { if process.isRunning { process.terminate() } }
    }
}
