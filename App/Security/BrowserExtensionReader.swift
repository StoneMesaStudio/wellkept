import Foundation
import WellkeptCore

//  BrowserExtensionReader.swift
//  Wellkept — App/Security
//
//  **What is installed in the browsers on this Mac, and what each one can see.**
//
//  Safari, Chrome, Edge, Brave, Arc, Firefox — whichever are actually here. One `SecurityRow` for
//  `.browserExtensions`, and a list underneath it the Apps section is meant to reuse.
//
//  ## ⚠️ "Can read every site you visit" is a capability, not an accusation
//
//  Two extensions on the Mac this was written against hold broad host permissions: **Claude** and
//  **iCloud Passwords**. Both were installed deliberately, by the person who owns the machine, and
//  neither can do its job without that access — a password manager that cannot see the page cannot
//  fill in the password.
//
//  So the row **states the capability, names the extension, and stops**. It does not rank, warn,
//  or suggest removing anything, and it raises none of the nine `SecurityConcern` cases, which
//  means `SecurityRow.severity` cannot turn it amber even by accident. That is deliberate: an app
//  that paints a warning colour beside a person's password manager has taught them to ignore its
//  warnings by Tuesday.
//
//  What is genuinely worth knowing is *which* ones have it, because most people have never seen
//  the list. That is the whole value of the row.
//
//  ## What counts as an extension, and what does not
//
//  **Extensions the browser ships with itself are not listed.** Chrome carries eight of them on
//  this Mac — the PDF viewer, the Web Store, Hangout Services, the speech synthesiser — and
//  reporting "you have 13 extensions" when the person installed five is the same inflation as
//  counting empty startup files. Chromium records this precisely: `location` 5 (component) and 10
//  (external component) are Google's own, and their `path` is an absolute one inside the browser's
//  own app bundle rather than a folder under the profile. Firefox files its own under
//  `app-builtin-addons` and `app-system-addons`.
//
//  **A leftover profile folder is not an installed browser.** This Mac has Application Support
//  folders for Arc, Brave, Edge, Vivaldi, Chromium and Opera, and none of those browsers is
//  installed. So a browser is reported when the app is actually on disk **or** when its profile
//  really does contain an extension — which catches a browser installed somewhere unusual without
//  resurrecting six dead folders.
//
//  ## What we cannot tell, and say so
//
//  - **Safari does not tell us which of its extensions are switched on.** `pluginkit` prints a
//    flag only where somebody has explicitly enabled or disabled a plug-in; the ordinary state is
//    blank, and blank means Safari decides. Reported as unknown, never as off.
//  - **Per-site permissions inside Safari** — the "Always Allow on Every Website" choice — live in
//    a container we cannot read. What the extension's own manifest asks for is readable, and that
//    is what is reported: what it can ask to see, not what it was granted.
//
//  Nothing here needs Full Disk Access, and nothing here can raise an authorization dialog:
//  `pluginkit` reads a registry the current account already owns.

enum BrowserExtensionReader {

    // MARK: - The browsers

    enum Browser: String, CaseIterable, Sendable, Hashable, Identifiable {
        case safari, chrome, edge, brave, arc, vivaldi, opera, chromium, firefox

        var id: String { rawValue }

        var label: String {
            switch self {
            case .safari:   "Safari"
            case .chrome:   "Chrome"
            case .edge:     "Edge"
            case .brave:    "Brave"
            case .arc:      "Arc"
            case .vivaldi:  "Vivaldi"
            case .opera:    "Opera"
            case .chromium: "Chromium"
            case .firefox:  "Firefox"
            }
        }

        /// The app bundle's name, looked for in the usual places.
        var appName: String {
            switch self {
            case .safari:   "Safari.app"
            case .chrome:   "Google Chrome.app"
            case .edge:     "Microsoft Edge.app"
            case .brave:    "Brave Browser.app"
            case .arc:      "Arc.app"
            case .vivaldi:  "Vivaldi.app"
            case .opera:    "Opera.app"
            case .chromium: "Chromium.app"
            case .firefox:  "Firefox.app"
            }
        }

        /// Where its profiles live, under `~/Library/Application Support`. `nil` for Safari, whose
        /// extensions are app extensions rather than profile folders.
        var profileRoot: String? {
            switch self {
            case .safari:   nil
            case .chrome:   "Google/Chrome"
            case .edge:     "Microsoft Edge"
            case .brave:    "BraveSoftware/Brave-Browser"
            case .arc:      "Arc/User Data"
            case .vivaldi:  "Vivaldi"
            case .opera:    "com.operasoftware.Opera"
            case .chromium: "Chromium"
            case .firefox:  "Firefox/Profiles"
            }
        }
    }

    // MARK: - What an extension can see

    /// What the extension is able to read, stated as capability.
    enum Reach: Sendable, Hashable {
        /// Broad host permissions — `<all_urls>` or `*://*/*`.
        case everySite
        /// A named list, already tidied into domains a person can read.
        case namedSites([String])
        /// Chrome's "on click" — the person withheld the standing grant.
        case onlyWhenYouClickIt
        /// It asked for no host access at all.
        case noSites
        /// We could not tell.
        case unknown

        /// ⚠️ The sentence John's rule turns on. It says what the extension **can** do, in the
        /// second person, with no verdict attached and no imperative after it.
        var sentence: String {
            switch self {
            case .everySite:           "Can read every site you visit"
            case let .namedSites(sites): "Can read \(StartupReader.list(sites))"
            case .onlyWhenYouClickIt:  "Reads a site only when you click it"
            case .noSites:             "Does not ask to read any site"
            case .unknown:             "The browser does not say what it can read"
            }
        }

        var isEverySite: Bool { self == .everySite }
    }

    /// One extension in one browser.
    struct Extension: Sendable, Hashable, Identifiable {

        /// What it calls itself, with `__MSG_…` placeholders already resolved.
        let name: String

        /// The store id, the add-on id, or the app extension's bundle id.
        let identifier: String

        let browser: Browser

        /// Who published it, where anybody says. `nil` is ordinary — Chrome records no publisher
        /// at all, so this is usually only known for Safari, where the app around it is signed.
        let publisher: String?

        let version: String?

        let reach: Reach

        /// `nil` where the browser does not tell us. **Never treated as off** — see the header.
        let enabled: Bool?

        var id: String { "\(browser.rawValue)|\(identifier)" }
    }

    /// One run's findings.
    struct Survey: Sendable, Hashable {

        /// Everything a person installed, in a fixed order.
        var extensions: [Extension] = []

        /// Browsers we actually looked inside.
        var browsersSearched: [Browser] = []

        /// Extensions the browser itself ships with, counted and not listed.
        var shippedWithBrowser = 0

        /// Profile files we opened.
        var profilesRead = 0

        /// True when at least one browser refuses to say whether its extensions are on.
        var enablementUnknown: Bool {
            extensions.contains { $0.enabled == nil }
        }
    }

    // MARK: - Where apps live

    static let applicationFolders = [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        URL(filePath: "/Applications/Utilities", directoryHint: .isDirectory),
        URL(filePath: "/System/Applications", directoryHint: .isDirectory),
        URL(filePath: "\(NSHomeDirectory())/Applications", directoryHint: .isDirectory)
    ]

    static let applicationSupport = URL(filePath: "\(NSHomeDirectory())/Library/Application Support",
                                        directoryHint: .isDirectory)

    // MARK: - The row

    static func read(applicationSupport: URL = applicationSupport,
                     applicationFolders: [URL] = applicationFolders,
                     includeSafari: Bool = true,
                     fileManager: FileManager = .default) -> SecurityRow {
        row(from: survey(applicationSupport: applicationSupport,
                         applicationFolders: applicationFolders,
                         includeSafari: includeSafari,
                         fileManager: fileManager))
    }

    static func survey(applicationSupport: URL = applicationSupport,
                       applicationFolders: [URL] = applicationFolders,
                       includeSafari: Bool = true,
                       fileManager: FileManager = .default) -> Survey {

        var survey = Survey()

        for browser in Browser.allCases {
            let installed = isInstalled(browser, in: applicationFolders, fileManager: fileManager)

            switch browser {
            case .safari:
                guard includeSafari, installed else { continue }
                survey.browsersSearched.append(.safari)
                readSafari(into: &survey)

            case .firefox:
                let found = readFirefox(root: applicationSupport, into: &survey,
                                        fileManager: fileManager)
                // ⚠️ A dead profile folder is not an installed browser — see the header. It is
                // only reported when the app is here, or when the folder really did hold
                // something a person installed.
                if installed || found > 0 { survey.browsersSearched.append(.firefox) }

            default:
                let found = readChromium(browser, root: applicationSupport, into: &survey,
                                         fileManager: fileManager)
                if installed || found > 0 { survey.browsersSearched.append(browser) }
            }
        }

        // Anything found in a browser we decided not to report is dropped, so the count and the
        // list can never disagree with the browsers named beside them.
        let reported = Set(survey.browsersSearched)
        survey.extensions = survey.extensions
            .filter { reported.contains($0.browser) }
            .sorted(by: order)

        return survey
    }

    // MARK: - Turning a survey into words

    static func row(from survey: Survey) -> SecurityRow {
        // ⚠️ Never report zero because we could not look. No browser at all is a different
        // statement from no extensions, and this is the only shape that says so.
        guard !survey.browsersSearched.isEmpty else {
            return .unreadable(.browserExtensions, .notReported,
                               about: "Browser extensions",
                               reason: "No browser we recognise is installed on this Mac.")
        }

        let broad = survey.extensions.filter(\.reach.isEverySite)

        return SecurityRow(topic: .browserExtensions,
                           headline: headline(survey),
                           measure: measure(survey.extensions.count),
                           reason: reason(survey, broad: broad),
                           details: details(from: survey))
    }

    static func headline(_ survey: Survey) -> String {
        let where_ = StartupReader.list(survey.browsersSearched.map(\.label))
        switch survey.extensions.count {
        case 0:  return "No extensions are installed in \(where_)."
        case 1:  return "One extension is installed, in \(where_)."
        default: return "\(survey.extensions.count) extensions are installed, across \(where_)."
        }
    }

    private static func measure(_ count: Int) -> String {
        count == 1 ? "1 extension" : "\(count) extensions"
    }

    /// The sentence under the headline.
    ///
    /// ⚠️ The wording of the broad-access line is the whole point of this row. It says what the
    /// access **is for** before it says who has it, because the two extensions that had it on the
    /// Mac this was written for were a password manager and an assistant, both installed on
    /// purpose. Leading with the capability and not the alarm is what keeps this a health check.
    static func reason(_ survey: Survey, broad: [Extension]) -> String? {
        var sentences: [String] = []

        if !broad.isEmpty {
            let names = StartupReader.list(broad.map { "\($0.name) in \($0.browser.label)" })
            sentences.append(broad.count == 1
                ? "\(names) can read every page you open."
                : "\(names) can each read every page you open.")
            sentences.append("That is what a password manager, a content blocker or an assistant "
                           + "needs in order to work at all, so it is worth knowing rather than "
                           + "worth worrying about.")
        }

        if survey.shippedWithBrowser > 0 {
            sentences.append("Extensions the browsers ship with themselves — "
                           + "\(survey.shippedWithBrowser) of them — are not counted.")
        }

        if survey.enablementUnknown {
            sentences.append("Safari does not say which of its extensions are switched on, so "
                           + "those are listed without one.")
        }

        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    static func details(from survey: Survey) -> [DetailPair] {
        var pairs: [DetailPair] = []
        var used = Set<String>()

        func add(_ label: String, _ value: String) {
            pairs.append(DetailPair(StartupReader.uniquely(label, in: &used), value))
        }

        for extended in survey.extensions {
            add("\(extended.name) (\(extended.browser.label))", describe(extended))
        }

        add("Browsers we looked in", StartupReader.list(survey.browsersSearched.map(\.label)))
        add("Extensions that came with the browser", "\(survey.shippedWithBrowser)")
        add("Profiles opened", "\(survey.profilesRead)")

        return pairs
    }

    /// "Can read every site you visit · 1.0.85 · switched on".
    static func describe(_ extended: Extension) -> String {
        var parts = [extended.reach.sentence]
        if let publisher = extended.publisher { parts.append(publisher) }
        if let version = extended.version { parts.append("version \(version)") }
        switch extended.enabled {
        case .some(true):  parts.append("switched on")
        case .some(false): parts.append("switched off")
        case .none:        break
        }
        return parts.joined(separator: " · ")
    }

    /// Broad access first, then by browser, then by name — fixed, so two runs draw the same list.
    private static func order(_ a: Extension, _ b: Extension) -> Bool {
        if a.reach.isEverySite != b.reach.isEverySite { return a.reach.isEverySite }
        if a.browser != b.browser {
            let cases = Browser.allCases
            return (cases.firstIndex(of: a.browser) ?? 0) < (cases.firstIndex(of: b.browser) ?? 0)
        }
        if a.name != b.name { return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
        return a.identifier < b.identifier
    }

    // MARK: - Is the browser actually here

    static func isInstalled(_ browser: Browser,
                            in folders: [URL],
                            fileManager: FileManager = .default) -> Bool {
        folders.contains { folder in
            fileManager.fileExists(atPath: folder.appending(path: browser.appName,
                                                            directoryHint: .isDirectory).path)
        }
    }

    // MARK: - Chromium browsers

    /// Chrome and everything built on it. Returns how many the person installed.
    @discardableResult
    private static func readChromium(_ browser: Browser,
                                     root: URL,
                                     into survey: inout Survey,
                                     fileManager: FileManager) -> Int {
        guard let relative = browser.profileRoot else { return 0 }
        let base = root.appending(path: relative, directoryHint: .isDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(atPath: base.path) else { return 0 }

        var found = 0
        // "System Profile" and "Guest Profile" are the browser's own scaffolding, not a person's.
        let skip: Set<String> = ["System Profile", "Guest Profile"]

        for entry in entries.sorted() where !skip.contains(entry) {
            let profile = base.appending(path: entry, directoryHint: .isDirectory)
            guard let settings = chromiumSettings(in: profile, fileManager: fileManager) else {
                continue
            }
            survey.profilesRead += 1

            for (identifier, raw) in settings.sorted(by: { $0.key < $1.key }) {
                guard let record = raw as? [String: Any] else { continue }

                if isShippedWithChromium(record) {
                    survey.shippedWithBrowser += 1
                    continue
                }

                let manifest = (record["manifest"] as? [String: Any]) ?? [:]
                let folder = extensionFolder(for: record, in: profile, identifier: identifier)

                survey.extensions.append(
                    Extension(name: name(fromManifest: manifest, folder: folder,
                                         fallback: identifier),
                              identifier: identifier,
                              browser: browser,
                              publisher: nil,
                              version: manifest["version"] as? String,
                              reach: chromiumReach(record, manifest: manifest),
                              enabled: isEnabled(record)))
                found += 1
            }
        }
        return found
    }

    /// `extensions.settings`, preferring the signed copy the browser actually trusts.
    private static func chromiumSettings(in profile: URL,
                                         fileManager: FileManager) -> [String: Any]? {
        for name in ["Secure Preferences", "Preferences"] {
            let file = profile.appending(path: name, directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: file.path),
                  let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let extensions = parsed["extensions"] as? [String: Any],
                  let settings = extensions["settings"] as? [String: Any] else { continue }
            return settings
        }
        return nil
    }

    /// **Google's own, not the person's.**
    ///
    /// Chromium's `Manifest::Location`: 5 is a component extension and 10 an external component —
    /// both shipped inside the browser. Their `path` is absolute, pointing into the browser's own
    /// framework, where a person's extension has a path relative to the profile's `Extensions`
    /// folder. Either signal alone is enough; both are checked because forks disagree about which
    /// they write.
    static func isShippedWithChromium(_ record: [String: Any]) -> Bool {
        if let location = record["location"] as? Int, location == 5 || location == 10 { return true }
        if let path = record["path"] as? String, path.hasPrefix("/") { return true }
        if let byDefault = record["was_installed_by_default"] as? Bool, byDefault { return true }
        return false
    }

    /// Empty `disable_reasons` is enabled. A missing key is not evidence of anything, so it is
    /// treated as enabled rather than as unknown — Chromium omits it on a healthy install.
    static func isEnabled(_ record: [String: Any]) -> Bool {
        guard let reasons = record["disable_reasons"] as? [Any] else { return true }
        return reasons.isEmpty
    }

    /// What this extension can actually read **now** — the granted permissions, not the manifest's
    /// wish list.
    ///
    /// `active_permissions` is what Chrome is honouring at this moment;
    /// `withholding_permissions` is the person having chosen "on click" instead. Reading the
    /// manifest alone would report standing access for an extension the person had already
    /// restricted, which is a false alarm about a decision they made themselves.
    static func chromiumReach(_ record: [String: Any], manifest: [String: Any]) -> Reach {
        let active = record["active_permissions"] as? [String: Any]
        var hosts = (active?["explicit_host"] as? [String] ?? [])
                  + (active?["scriptable_host"] as? [String] ?? [])

        if hosts.isEmpty {
            hosts = (manifest["host_permissions"] as? [String] ?? [])
                  + ((manifest["permissions"] as? [String] ?? []).filter(looksLikeHostPattern))
        }
        if hosts.isEmpty { return .noSites }
        if hosts.contains(where: isEverySitePattern) { return .everySite }
        if (record["withholding_permissions"] as? Bool) == true { return .onlyWhenYouClickIt }
        return .namedSites(domains(in: hosts))
    }

    /// Where this extension's files are, so a `__MSG_…` name can be resolved.
    private static func extensionFolder(for record: [String: Any],
                                        in profile: URL,
                                        identifier: String) -> URL? {
        guard let path = record["path"] as? String, !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(filePath: path, directoryHint: .isDirectory) }
        return profile.appending(path: "Extensions", directoryHint: .isDirectory)
                      .appending(path: path, directoryHint: .isDirectory)
    }

    // MARK: - Firefox

    @discardableResult
    private static func readFirefox(root: URL,
                                    into survey: inout Survey,
                                    fileManager: FileManager) -> Int {
        guard let relative = Browser.firefox.profileRoot else { return 0 }
        let base = root.appending(path: relative, directoryHint: .isDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(atPath: base.path) else { return 0 }

        var found = 0
        var seen = Set<String>()

        for entry in entries.sorted() {
            let file = base.appending(path: entry, directoryHint: .isDirectory)
                           .appending(path: "extensions.json", directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let addons = parsed["addons"] as? [[String: Any]] else { continue }
            survey.profilesRead += 1

            for addon in addons {
                guard (addon["type"] as? String) == "extension",
                      let identifier = addon["id"] as? String else { continue }

                if isShippedWithFirefox(addon) {
                    // The same add-on appears twice — once built in, once updated into the
                    // profile — so it is counted on the identifier, not on the entry.
                    if seen.insert("built-in|\(identifier)").inserted {
                        survey.shippedWithBrowser += 1
                    }
                    continue
                }
                guard seen.insert(identifier).inserted else { continue }

                let locale = addon["defaultLocale"] as? [String: Any]
                let permissions = addon["userPermissions"] as? [String: Any]
                let origins = permissions?["origins"] as? [String] ?? []

                survey.extensions.append(
                    Extension(name: (locale?["name"] as? String) ?? identifier,
                              identifier: identifier,
                              browser: .firefox,
                              publisher: locale?["creator"] as? String,
                              version: addon["version"] as? String,
                              reach: firefoxReach(origins),
                              enabled: (addon["active"] as? Bool) == true
                                    && (addon["userDisabled"] as? Bool) != true))
                found += 1
            }
        }
        return found
    }

    /// Mozilla's own. Filed under a built-in location, or published under a Mozilla identity —
    /// either is enough, because a system add-on updated into the profile loses the location but
    /// keeps the id.
    static func isShippedWithFirefox(_ addon: [String: Any]) -> Bool {
        if let location = addon["location"] as? String,
           location.hasPrefix("app-builtin") || location.hasPrefix("app-system") { return true }
        if let identifier = addon["id"] as? String,
           identifier.hasSuffix("@mozilla.org") || identifier.hasSuffix("@mozilla.com") {
            return true
        }
        return false
    }

    static func firefoxReach(_ origins: [String]) -> Reach {
        if origins.isEmpty { return .noSites }
        if origins.contains(where: isEverySitePattern) { return .everySite }
        return .namedSites(domains(in: origins))
    }

    // MARK: - Safari

    /// Safari's extensions are app extensions, and `pluginkit` is the registry that knows them.
    ///
    /// Two extension points, two calls: `pluginkit` honours only the last `-p` it is given.
    /// `.extension` is the older kind — content blockers and share actions — and `.web-extension`
    /// is the modern kind, which carries a readable `manifest.json` inside the `.appex`.
    private static func readSafari(into survey: inout Survey) {
        let tool = URL(filePath: "/usr/bin/pluginkit")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return }

        for point in ["com.apple.Safari.extension", "com.apple.Safari.web-extension"] {
            guard let data = StartupReader.toolOutput(tool, ["-mAvvv", "-p", point], timeout: 8)
            else { continue }

            for record in parsePluginKit(String(decoding: data, as: UTF8.self)) {
                survey.extensions.append(record)
            }
        }
    }

    /// `pluginkit -mAvvv` output, turned into extensions.
    ///
    /// The shape, verbatim from this Mac:
    ///
    ///     "     com.khanov.BlockerX.MacWebExtension(6.6.1)"
    ///     "\t            Path = /Applications/1Blocker.app/Contents/PlugIns/MacWebExtension.appex"
    ///     "\t   Parent Bundle = /Applications/1Blocker.app"
    ///     "\t    Display Name = MacWebExtension"
    ///     "\t     Parent Name = 1Blocker"
    ///
    /// ⚠️ The first column carries `+` or `-` only when somebody has explicitly switched the
    /// plug-in on or off. Blank — which is what every extension on this Mac reads — means Safari
    /// decides, and that is reported as unknown rather than as off.
    static func parsePluginKit(_ output: String) -> [Extension] {
        var found: [Extension] = []
        var identifier: String?
        var version: String?
        var enabled: Bool?
        var fields: [String: String] = [:]

        func flush() {
            defer { identifier = nil; version = nil; enabled = nil; fields = [:] }
            guard let identifier, let path = fields["Path"] else { return }

            let appex = URL(filePath: path, directoryHint: .isDirectory)
            let parentBundle = fields["Parent Bundle"].map {
                URL(filePath: $0, directoryHint: .isDirectory)
            }
            let manifest = manifest(inSafariExtension: appex)

            let fallback = fields["Parent Name"].map { parent in
                fields["Display Name"].map { "\(parent) — \($0)" } ?? parent
            } ?? fields["Display Name"] ?? identifier

            found.append(
                Extension(name: manifest.map {
                              name(fromManifest: $0,
                                   folder: appex.appending(path: "Contents/Resources",
                                                           directoryHint: .isDirectory),
                                   fallback: fallback)
                          } ?? fallback,
                          identifier: identifier,
                          browser: .safari,
                          publisher: parentBundle.flatMap(StartupReader.developerName(of:)),
                          version: version,
                          reach: manifest.map(safariReach) ?? .unknown,
                          enabled: enabled))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\t") {
                let body = line.drop { $0 == "\t" || $0 == " " }
                guard let split = body.range(of: " = ") else { continue }
                fields[String(body[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)] =
                    String(body[split.upperBound...]).trimmingCharacters(in: .whitespaces)
                continue
            }

            flush()

            // " (1 plug-in)" and blank lines are the trailer, not a record.
            let flag = line.first
            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            guard body.contains("("), body.hasSuffix(")"), !body.hasPrefix("(") else { continue }
            guard let open = body.lastIndex(of: "(") else { continue }

            identifier = String(body[..<open])
            version = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            enabled = flag == "+" ? true : (flag == "-" ? false : nil)
        }
        flush()

        return found
    }

    /// A modern Safari extension's own `manifest.json`, which is a plain readable file inside the
    /// `.appex`. The older kind has none, and gets `Reach.unknown`.
    static func manifest(inSafariExtension appex: URL) -> [String: Any]? {
        let file = appex.appending(path: "Contents/Resources/manifest.json",
                                   directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: file),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parsed
    }

    /// What a Safari web extension asks for.
    ///
    /// ⚠️ This is what it can **ask** to see. Safari's own per-site answer lives in a container we
    /// cannot read, so an extension the person restricted to one site still reports what its
    /// manifest requests. That is the honest limit and it is stated on the row.
    static func safariReach(_ manifest: [String: Any]) -> Reach {
        var hosts = manifest["host_permissions"] as? [String] ?? []
        // Manifest v2 keeps host patterns in `permissions` alongside the API names — 1Blocker's
        // `*://*/*` arrives that way.
        hosts += (manifest["permissions"] as? [String] ?? []).filter(looksLikeHostPattern)
        for script in manifest["content_scripts"] as? [[String: Any]] ?? [] {
            hosts += script["matches"] as? [String] ?? []
        }

        if hosts.isEmpty { return .noSites }
        if hosts.contains(where: isEverySitePattern) { return .everySite }
        return .namedSites(domains(in: hosts))
    }

    // MARK: - Reading host patterns and names

    /// Whether a match pattern covers everything.
    ///
    /// `<all_urls>` is the declared form; `*://*/*` is the same thing spelled by hand, and both
    /// appear on this Mac. A scheme-specific wildcard — `https://*/*` — is broad too: an extension
    /// that can read every https page can read every page anybody actually visits.
    static func isEverySitePattern(_ pattern: String) -> Bool {
        let lowered = pattern.lowercased()
        if lowered == "<all_urls>" { return true }
        guard let separator = lowered.range(of: "://") else { return false }
        let host = lowered[separator.upperBound...].prefix { $0 != "/" }
        return host == "*"
    }

    /// Whether a manifest v2 `permissions` entry is a host pattern rather than an API name.
    static func looksLikeHostPattern(_ entry: String) -> Bool {
        entry == "<all_urls>" || entry.contains("://")
    }

    /// `https://docs.google.com/*` → `docs.google.com`, de-duplicated and readable.
    ///
    /// Trimmed to five, because a row is not the place for an extension's forty-line match list and
    /// a truncated list that says so is more honest than a wall a person will not read.
    static func domains(in patterns: [String]) -> [String] {
        var names: [String] = []
        for pattern in patterns {
            let body = pattern.range(of: "://").map { String(pattern[$0.upperBound...]) } ?? pattern
            let host = String(body.prefix { $0 != "/" })
                .replacingOccurrences(of: "*.", with: "")
            guard !host.isEmpty, host != "*", !names.contains(host) else { continue }
            names.append(host)
        }
        guard names.count > 5 else { return names }
        return Array(names.prefix(5)) + ["\(names.count - 5) more"]
    }

    /// An extension's name, with a `__MSG_key__` placeholder resolved out of its own `_locales`.
    ///
    /// Chrome writes the resolved name into its preferences and Safari does not, so both routes
    /// exist. Where the message file cannot be read the fallback is used rather than printing
    /// `__MSG_extName__` at a person.
    static func name(fromManifest manifest: [String: Any],
                     folder: URL?,
                     fallback: String) -> String {
        guard let raw = manifest["name"] as? String, !raw.isEmpty else { return fallback }
        guard raw.hasPrefix("__MSG_"), raw.hasSuffix("__") else { return raw }

        let key = String(raw.dropFirst(6).dropLast(2))
        guard !key.isEmpty, let folder else { return fallback }

        let locale = (manifest["default_locale"] as? String) ?? "en"
        for candidate in [locale, "en", "en_US"] {
            let file = folder.appending(path: "_locales/\(candidate)/messages.json",
                                        directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: file),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            // Chrome matches message keys case-insensitively; a manifest that says `extName` and a
            // file that says `extname` is ordinary.
            let entry = messages[key] as? [String: Any]
                     ?? messages.first { $0.key.lowercased() == key.lowercased() }?.value
                        as? [String: Any]
            if let message = entry?["message"] as? String, !message.isEmpty { return message }
        }
        return fallback
    }
}
