// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  UpdateReader.swift
//  Wellkept — App/Apps
//
//  ⭐ **Whether an app is current — and the four ways this file refuses to guess.**
//
//  Nothing here runs unless `UpdateConsent` says yes. See `UpdateConsent.swift` for the question and
//  where the answer lives.
//
//  ## The four sources, and there are no others
//
//  | Source | Reaches off this Mac | Covers, on the Mac this was measured on |
//  |---|---|---|
//  | Apple's storefront lookup | **Yes** — one request, no account, no cookie | The App Store apps |
//  | Homebrew's own cask list | No — a file `brew` already wrote here | Nothing here; casks are how most people install Mac software from the terminal |
//  | `SelfUpdatingApps` | No — a list inside this app | Chrome, Firefox, VS Code, Slack and eleven more |
//  | Nothing | — | Everything else: "we have no way to check this one" |
//
//  ⛔ **Three sources were designed, measured and dropped on 2026-08-27.** Do not add them back
//  without reading `APPS-QUESTIONS.md` first, because each was killed by a measurement rather than a
//  preference:
//
//  - **Sparkle appcasts** — the plan's headline mechanism. It covers **1 app out of 29** here. Of
//    six real vendor feeds fetched, three refused an unknown checker outright and the two that
//    worked disagree about which entry is newest: BBEdit's lists a 2011 version first.
//  - **CVE matching.** Of five ordinary Mac apps checked against the US vulnerability database, two
//    are absent entirely and one confuses a code editor with its plugins.
//  - **A hand-kept list of makers' version pages.** John declined it: *"I don't know that I want
//    that responsibility. They frequently release updates."* Coverage drops from about 13 apps to
//    about 9, and the section says so plainly rather than implying it looked everywhere.
//
//  ## ⚠️ The measurements this file is shaped by
//
//  All on an M3 running macOS 26.6.2, and every one of them is a way a naïve version check tells
//  somebody something untrue:
//
//  1. **Apple's storefront says Pages is 15.3. The installed copy says 15.3.1.** A plain `!=` calls
//     three of nine App Store apps outdated and advises **downgrading** Pages, Numbers and Keynote.
//  2. **`com.apple.Pages` comes back from the lookup as `kind: "software"` — the iPhone record.**
//     Verified today: with `entity=macSoftware` the storefront answers about the iOS app for a
//     universal purchase. Comparing a Mac build against an iPhone version is the same bug wearing a
//     better disguise, so this file requires `kind == "mac-software"` and treats anything else as no
//     answer at all.
//  3. **Chrome looks two versions behind and is current** — Google ships a staged rollout, so the
//     version at the top of their public list was serving to nobody. Self-updating apps are answered
//     by `SelfUpdatingApps` and never compared.
//  4. **13 of 18 apps carry a version-shape hazard**: `02.06.00.51`, dates used as version numbers,
//     marketing strings that lag the shipped build.
//
//  Hence the one rule the whole file is built to: **`.newerAvailable` requires a version we can name
//  and a comparison we can defend. Everything else is `.couldNotTell`, with the reason attached.** A
//  false "out of date" is worse than a missing answer, because a missing answer is visible and a
//  false one is not.
//
//  ## What this file never does
//
//  - It never runs `spctl`. Three minutes nine seconds for 29 apps, and it is slow *because* it
//    reports each unstapled app to Apple.
//  - It never asks a maker's own web site anything. See the dropped list above.
//  - It never says an update is *waiting* for macOS. That is knowable only by asking Apple, and
//    `MacOSUpdateState` reads only what this Mac already wrote down.

// MARK: - ⭐ Comparing two version strings

/// **The comparison, and it is not `!=`.**
///
/// Given what a person's installed copy says and what a publisher says is current, this answers one
/// of four things — and the fourth, `notComparable`, is the answer far more often than anybody
/// expects. That is the design: this type is built to *decline*.
///
/// ## What it will compare
///
/// Two versions made of dotted numbers, of the same shape. `15.3.1` against `15.3` — yes. `26.6`
/// against `26.6` — yes. `02.06.00.51` against `02.06.00.52` — yes, because both sides pad their
/// components the same way.
///
/// ## What it refuses, and why each refusal is a real app
///
/// | Refused | The app it came from |
/// |---|---|
/// | Anything with a letter, a dash or a space in it | Every beta, every `1.2.3 (4567)` |
/// | Zero-padded on one side only — `02.06.00.51` against `2.6.1` | A scanner utility here |
/// | A date on one side only — `2026.08.27` against `3.1` | Two apps here version by date |
/// | Component counts more than one apart — `1` against `1.2.3.4` | Two different schemes wearing dots |
///
/// ⚠️ **Identical strings are always comparable**, checked before anything is parsed. That is what
/// rescues the padded and date-shaped apps: an app whose version has not moved says so, whatever
/// shape its version happens to be.
enum VersionComparison {

    /// How the installed copy stands against the published one.
    enum Order: Sendable, Hashable {
        /// The same version, either as text or as numbers.
        case same
        /// The published version is unambiguously greater. **The only route to `.newerAvailable`.**
        case currentIsNewer
        /// The installed copy is ahead of what the publisher's record says. This is Pages 15.3.1
        /// against a storefront that says 15.3, and it means *current*, never *downgrade*.
        case installedIsNewer
        /// We have both strings and cannot honestly rank them.
        case notComparable
    }

    /// A version we were able to make sense of.
    struct Parsed: Sendable, Hashable {
        /// The dotted numbers, left to right.
        let components: [Int]
        /// Whether any component is written with a leading zero — `02`, `00`. A padded scheme and an
        /// unpadded one are two different schemes, and mixing them is how `02.06.00.51` gets ranked
        /// against `2.6.1`.
        let padded: Bool

        /// Whether this looks like a date rather than a version.
        ///
        /// Two shapes: `2026.08.27`, where a plausible year leads three or more components, and
        /// `20260827`, where a single component is far too large to be a release number. Either one
        /// compared against an ordinary `3.1` produces a confident nonsense.
        var looksLikeADate: Bool {
            guard let first = components.first else { return false }
            if components.count == 1, first >= 10_000 { return true }
            if components.count >= 3, (1_990...2_100).contains(first) { return true }
            return false
        }
    }

    /// At most this many dotted components. Beyond it, the string is not a version scheme we know.
    static let maximumComponents = 6

    /// Trim, and drop a leading `v` where a digit follows it. Nothing else is normalised — every
    /// other difference between two version strings is a difference this file is not entitled to
    /// paper over.
    static func normalise(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, first == "v" || first == "V",
           text.dropFirst().first?.isNumber == true {
            text = String(text.dropFirst())
        }
        return text
    }

    /// Parse, or refuse. `nil` is the ordinary answer for a great many real versions.
    static func parse(_ raw: String) -> Parsed? {
        let text = normalise(raw)
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= maximumComponents else { return nil }

        var components: [Int] = []
        var padded = false
        for part in parts {
            // Nine digits keeps every real version inside `Int` on every platform and rejects the
            // hash-like strings a few installers use as a version.
            guard !part.isEmpty, part.count <= 9,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part) else { return nil }
            if part.count > 1, part.first == "0" { padded = true }
            components.append(value)
        }
        return Parsed(components: components, padded: padded)
    }

    /// **The comparison.** `nil` on either side is `notComparable`, never an assumption.
    static func compare(installed: String?, current: String?) -> Order {
        guard let installedRaw = installed, let currentRaw = current else { return .notComparable }

        let a = normalise(installedRaw)
        let b = normalise(currentRaw)
        guard !a.isEmpty, !b.isEmpty else { return .notComparable }

        // ⚠️ Before any parsing. Two identical strings are the same version whatever shape they are,
        // and this is the one line that keeps the date-versioned and zero-padded apps answerable.
        if a.compare(b, options: .caseInsensitive) == .orderedSame { return .same }

        guard let left = parse(a), let right = parse(b) else { return .notComparable }

        // The three shape guards. Each one is an app on the measured Mac; see the table above.
        guard left.padded == right.padded else { return .notComparable }
        guard left.looksLikeADate == right.looksLikeADate else { return .notComparable }
        guard abs(left.components.count - right.components.count) <= 1 else { return .notComparable }

        let width = max(left.components.count, right.components.count)
        for index in 0..<width {
            // Zero-extension, so `15.3` reads as `15.3.0` against `15.3.1`. Correct only because
            // both sides have already been proved to be the same kind of number.
            let l = index < left.components.count ? left.components[index] : 0
            let r = index < right.components.count ? right.components[index] : 0
            if l == r { continue }
            return l < r ? .currentIsNewer : .installedIsNewer
        }
        return .same
    }

    /// The comparison, as the standing that goes on the app's line.
    ///
    /// ⚠️ `.newerAvailable` carries the version, which is the guard `UpdateStanding` was built with:
    /// a caller that cannot name the newer version cannot claim one exists.
    static func standing(installed: String?, current: String?) -> UpdateStanding {
        switch compare(installed: installed, current: current) {
        case .currentIsNewer:
            // The publisher's spelling, trimmed but not rewritten, so the row can show both numbers
            // and the person can check our arithmetic.
            return .newerAvailable(normalise(current ?? ""))
        case .same, .installedIsNewer:
            return .current
        case .notComparable:
            return .couldNotTell(.versionsNotComparable)
        }
    }
}

// MARK: - ⭐ What macOS itself says about macOS

/// **The macOS row's facts, all of them read from this Mac and none of them from Apple.**
///
/// Everything here is in two property lists this Mac already keeps, both world-readable, and reading
/// them costs about a millisecond. No network, no `softwareupdate` command — which would spawn a
/// tool that *does* contact Apple, and would take seconds doing it.
///
/// ## ⚠️ The one thing this cannot say, and must not imply
///
/// **Whether an update is waiting right now.** That is a question only Apple can answer, and this
/// file does not ask it. macOS caches the answer to its own last check in a `RecommendedUpdates` key
/// — and that key is deliberately **not read here**, because a cached list is stale the moment the
/// check that produced it ends. A row saying "1 update available" on the strength of a fortnight-old
/// cache is exactly the confident wrong answer this whole section is built to avoid. What we can say
/// truthfully is what has already happened: what was offered, what was installed, and when.
///
/// ## Where each fact comes from
///
/// | Fact | Source |
/// |---|---|
/// | Running version and build | `/System/Library/CoreServices/SystemVersion.plist` |
/// | Automatic checking, downloading, installing | `/Library/Preferences/com.apple.SoftwareUpdate.plist` |
/// | Security fixes and malware definitions | the same file — `CriticalUpdateInstall`, `ConfigDataInstall` |
/// | When macOS last looked | `LastSuccessfulDate`, `LastFullSuccessfulDate`, `LastBackgroundSuccessfulDate` |
/// | What was offered, and when | `FirstOfferDateDictionary` — 14 entries here, back to November 2025 |
/// | What was installed, and when | `InstallDateDictionary` — 9 entries here |
///
/// An MDM-managed Mac has a second copy under `/Library/Managed Preferences`, and it wins. The same
/// precedence `ProtectionReader` uses in the Security section, deliberately: two files in one app
/// disagreeing about whether automatic updates are on would be worse than either answer.
///
/// ⚠️ **Security is the authority on whether automatic updates are a concern.** This type reports
/// the settings as facts on the macOS row because the row would be strange without them. It does not
/// grade them, and `AppsRow.severity` is `.information` by construction, so it cannot.
struct MacOSUpdateState: Sendable, Hashable {

    // MARK: One dated thing that happened

    /// A macOS update that was offered to this Mac, or installed on it.
    struct Event: Sendable, Hashable, Identifiable, Comparable {

        enum Kind: String, Sendable, Hashable {
            case offered, installed

            var verb: String {
                switch self {
                case .offered:   "was offered"
                case .installed: "was installed"
                }
            }
        }

        let kind: Kind
        /// "26.6.2". `nil` for an install whose build we could not match to a version — the install
        /// dictionary is keyed by build alone, so a build never offered on this Mac has no version.
        let version: String?
        /// "25G83". Always present; it is the key.
        let build: String
        let date: Date
        /// A Rapid Security Response — Apple's out-of-band security fix, keyed `_rsr`.
        let isSecurityResponse: Bool

        var id: String { "\(kind.rawValue)-\(build)-\(Int(date.timeIntervalSince1970))" }

        /// "macOS 26.6.2 (25G83)", or just the build where no version is known.
        var name: String {
            var text = version.map { "macOS \($0)" } ?? "macOS build \(build)"
            if version != nil { text += " (\(build))" }
            if isSecurityResponse { text += " — a security response" }
            return text
        }

        var sentence: String {
            "\(name) \(kind.verb) on \(date.formatted(date: .abbreviated, time: .omitted))."
        }

        /// Newest first is what every list of these wants, so `<` is defined the way they are sorted.
        static func < (a: Event, b: Event) -> Bool { a.date > b.date }
    }

    // MARK: The state

    /// "26.6.2". `nil` only if `SystemVersion.plist` could not be read, which would mean something
    /// far more broken than a missed update.
    let productVersion: String?
    /// "25G83".
    let buildVersion: String?

    /// `AutomaticCheckEnabled`. ⚠️ **`nil` is the ordinary case, not an error** — the key is absent
    /// on this Mac, because macOS only writes it when somebody changes it from the default. Absent
    /// is reported as "this Mac does not say", never guessed at.
    let automaticChecking: Bool?
    /// `AutomaticDownload`.
    let automaticDownload: Bool?
    /// `CriticalUpdateInstall` — security fixes installing on their own.
    let securityFixes: Bool?
    /// `ConfigDataInstall` — malware definitions and other system data files.
    let systemDataFiles: Bool?
    /// `AutomaticallyInstallMacOSUpdates` — whole macOS updates installing on their own.
    let installsMacOSUpdates: Bool?

    /// Whether any of the above came from an MDM profile rather than from this Mac's own settings.
    let managed: Bool

    /// When macOS itself last checked. Not when *we* did; Wellkept never checks.
    let lastCheckedAt: Date?

    /// Everything offered and everything installed, **newest first**.
    let history: [Event]

    /// Set when the settings file could not be read at all. `.notReported`, never `.notPermitted`:
    /// the file is world-readable, so no permission exists that would have helped.
    let unreadable: Unreadable?

    // MARK: What it can be asked

    /// "macOS 26.6.2 (25G83)".
    var versionText: String {
        guard let productVersion else { return Unreadable.notReported.sentence }
        guard let buildVersion else { return "macOS \(productVersion)" }
        return "macOS \(productVersion) (\(buildVersion))"
    }

    /// The row's own sentence — what this Mac is running, and nothing about what it might be missing.
    var headline: String {
        guard productVersion != nil else {
            return Unreadable.notReported.sentence(about: "The version of macOS")
        }
        return "This Mac is running \(versionText)."
    }

    /// ⚠️ **Printed wherever the history is.** Without it a dated list of past updates reads as a
    /// statement about the present, which is the one thing it is not.
    static let waitingCaveat = String(localized: """
        This is what has already happened on this Mac. Whether an update is waiting right now is a \
        question only Apple can answer, and Wellkept does not ask it — Software Update does.
        """)

    var installed: [Event] { history.filter { $0.kind == .installed } }
    var offered: [Event] { history.filter { $0.kind == .offered } }

    /// "macOS has installed 9 updates on this Mac, most recently on 25 Aug 2026."
    var installHistorySentence: String? {
        let events = installed
        guard let newest = events.first else { return nil }
        let when = newest.date.formatted(date: .abbreviated, time: .omitted)
        return events.count == 1
            ? "macOS has installed one update on this Mac, on \(when)."
            : "macOS has installed \(events.count) updates on this Mac, most recently on \(when)."
    }

    /// For the Options disclosure. Label above value, never a two-column table.
    var detailPairs: [DetailPair] {
        func onOff(_ value: Bool?) -> String {
            guard let value else { return "This Mac does not say" }
            return value ? "On" : "Off"
        }

        var pairs: [DetailPair] = [DetailPair("Version", versionText)]

        if let unreadable {
            pairs.append(DetailPair("Update settings", unreadable: unreadable))
            return pairs
        }

        pairs.append(DetailPair("Checks for updates on its own", onOff(automaticChecking)))
        pairs.append(DetailPair("Downloads them on its own", onOff(automaticDownload)))
        pairs.append(DetailPair("Security fixes install on their own", onOff(securityFixes)))
        pairs.append(DetailPair("Malware definitions update on their own", onOff(systemDataFiles)))
        pairs.append(DetailPair("macOS updates install on their own", onOff(installsMacOSUpdates)))

        if let lastCheckedAt {
            pairs.append(DetailPair("macOS last checked",
                                    lastCheckedAt.formatted(date: .abbreviated, time: .shortened)))
        }
        if managed {
            pairs.append(DetailPair("Set by whoever manages this Mac",
                                    "Some of these are fixed by a profile, not by this Mac's settings."))
        }
        if let sentence = installHistorySentence {
            pairs.append(DetailPair("Updates installed", sentence))
        }
        if let newestOffer = offered.first {
            pairs.append(DetailPair("Most recent update offered", newestOffer.sentence))
        }
        return pairs
    }

    // MARK: Reading it

    static let settingsPath = "/Library/Preferences/com.apple.SoftwareUpdate.plist"
    static let managedSettingsPath = "/Library/Managed Preferences/com.apple.SoftwareUpdate.plist"
    static let systemVersionPath = "/System/Library/CoreServices/SystemVersion.plist"

    /// **Read it.** Blocking, and about a millisecond; safe from any thread and free of side effects.
    static func read(fileManager: FileManager = .default) -> MacOSUpdateState {
        make(settings: propertyList(atPath: settingsPath, fileManager: fileManager),
             managed: propertyList(atPath: managedSettingsPath, fileManager: fileManager),
             systemVersion: propertyList(atPath: systemVersionPath, fileManager: fileManager))
    }

    /// The pure half, so every branch above can be tested without a Mac in a particular state.
    static func make(settings: [String: Any]?,
                     managed: [String: Any]?,
                     systemVersion: [String: Any]?) -> MacOSUpdateState {

        // MDM wins, exactly as it does in `ProtectionReader`.
        func flag(_ key: String) -> Bool? {
            (managed?[key] as? Bool) ?? (settings?[key] as? Bool)
        }
        func date(_ key: String) -> Date? { settings?[key] as? Date }

        let product = (systemVersion?["ProductVersion"] as? String)
            ?? fallbackProductVersion()
        let build = (systemVersion?["ProductBuildVersion"] as? String)

        let offers = events(from: settings?["FirstOfferDateDictionary"] as? [String: Any],
                            kind: .offered)
        // The install dictionary is keyed by bare build, so the version has to be borrowed from
        // whatever offer carried the same build. A build installed but never offered on this Mac —
        // a machine that arrived with it — keeps a `nil` version and says so.
        var versionsByBuild: [String: String] = [:]
        for offer in offers where offer.version != nil {
            versionsByBuild[offer.build] = offer.version
        }
        let installs = events(from: settings?["InstallDateDictionary"] as? [String: Any],
                              kind: .installed,
                              versionsByBuild: versionsByBuild)

        let lastChecked = [date("LastSuccessfulDate"),
                           date("LastFullSuccessfulDate"),
                           date("LastBackgroundSuccessfulDate")]
            .compactMap { $0 }
            .max()

        // Managed only counts where the profile actually supplies one of the values we report. A
        // present-but-empty managed file is not a managed update policy.
        let managedKeys = ["AutomaticCheckEnabled", "AutomaticDownload", "CriticalUpdateInstall",
                           "ConfigDataInstall", "AutomaticallyInstallMacOSUpdates"]
        let isManaged = managedKeys.contains { managed?[$0] != nil }

        return MacOSUpdateState(
            productVersion: product,
            buildVersion: build,
            automaticChecking: flag("AutomaticCheckEnabled"),
            automaticDownload: flag("AutomaticDownload"),
            securityFixes: flag("CriticalUpdateInstall"),
            systemDataFiles: flag("ConfigDataInstall"),
            installsMacOSUpdates: flag("AutomaticallyInstallMacOSUpdates"),
            managed: isManaged,
            lastCheckedAt: lastChecked,
            history: (offers + installs).sorted(),
            // Nothing readable in the settings file at all. The version is still reported, because
            // it comes from somewhere else and is still true.
            unreadable: settings == nil ? .notReported : nil)
    }

    /// `ProcessInfo`'s answer, for the case where the plist is missing. It is assembled from the same
    /// numbers, so this is a second route rather than a second source.
    private static func fallbackProductVersion() -> String? {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        guard v.majorVersion > 0 else { return nil }
        return v.patchVersion == 0
            ? "\(v.majorVersion).\(v.minorVersion)"
            : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Turn one of the two date dictionaries into events.
    static func events(from dictionary: [String: Any]?,
                       kind: Event.Kind,
                       versionsByBuild: [String: String] = [:]) -> [Event] {
        guard let dictionary else { return [] }
        return dictionary.compactMap { key, value in
            guard let date = value as? Date else { return nil }
            let decoded = decode(updateKey: key)
            return Event(kind: kind,
                         version: decoded.version ?? versionsByBuild[decoded.build],
                         build: decoded.build,
                         date: date,
                         isSecurityResponse: decoded.isSecurityResponse)
        }
    }

    /// **Pull a build and a version out of one of Apple's keys.**
    ///
    /// The offer dictionary is keyed `MSU_UPDATE_25G83_patch_26.6.2_minor`; the install dictionary is
    /// keyed with the bare build, `25G83`. Both shapes go through here, and an unrecognised key is
    /// treated as a bare build rather than dropped — a key we cannot decode is still a dated thing
    /// that happened, and losing it would quietly shorten the history.
    static func decode(updateKey key: String) -> (build: String, version: String?, isSecurityResponse: Bool) {
        let parts = key.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard let patchIndex = parts.firstIndex(of: "patch"), patchIndex > 0 else {
            return (key, nil, key.lowercased().hasSuffix("rsr"))
        }
        let build = parts[patchIndex - 1]
        let version = patchIndex + 1 < parts.count ? parts[patchIndex + 1] : nil
        return (build, version, parts.last == "rsr")
    }

    /// A property list, or `nil`. Never throws at the caller: an unreadable settings file is a state
    /// this type reports, not an error it propagates.
    static func propertyList(atPath path: String, fileManager: FileManager) -> [String: Any]? {
        guard fileManager.isReadableFile(atPath: path),
              let data = fileManager.contents(atPath: path),
              let object = try? PropertyListSerialization.propertyList(from: data,
                                                                      options: [],
                                                                      format: nil)
        else { return nil }
        return object as? [String: Any]
    }
}

// MARK: - ⭐ Apple's storefront — the one thing that leaves this Mac

/// **One request to Apple's public lookup, and nothing else ever.**
///
/// No account, no sign-in, no cookie, no identifier, nothing about this Mac. What the request
/// unavoidably discloses is the list of App Store apps installed here, which is said in plain words
/// on the consent sheet, on the welcome page, in Settings and in Help — because it is arithmetic
/// rather than a leak, and a person deciding deserves to be told rather than to work it out.
///
/// ## ⚠️ Verified by hand, 2026-08-27, and worth knowing before touching this
///
/// - **Bundle identifiers batch, comma-separated.** `?bundleId=a,b,c` returned both records in one
///   response. That is what makes "one request" true rather than aspirational.
/// - **`entity=macSoftware` is a trap and is not used.** With it, `com.apple.Pages` answers with the
///   *iPhone* record — `kind: "software"`, version 15.3 — while the installed Mac copy is 15.3.1.
///   Without it, the same request returns only genuine `mac-software` records, which is what we
///   want, and Pages simply does not answer. Fewer answers, no wrong ones.
/// - **An unknown identifier is silently absent** from the results rather than an error, so "not in
///   the response" has to mean "the store publishes no Mac version for this app" — which is the
///   truth, and is `.noSourceToAsk`, not a failure.
enum AppStoreVersions {

    /// What the storefront said about one app.
    struct Record: Sendable, Hashable {
        let bundleID: String
        /// The current version, as the storefront spells it.
        let version: String
        let name: String?
        let releasedAt: Date?
    }

    /// One round of asking.
    struct Answer: Sendable, Hashable {
        /// Keyed by lower-cased bundle identifier.
        let records: [String: Record]
        /// Identifiers in a batch whose request itself failed — offline, refused, timed out. These
        /// become `.askFailed`, which is a different sentence from "the store has no Mac version".
        let failed: Set<String>

        static let none = Answer(records: [:], failed: [])
    }

    /// How many identifiers go in one request. Twenty keeps the URL well inside every limit and, on
    /// the measured Mac, means the whole App Store check is a single request.
    static let batchSize = 20

    /// The storefront to ask. A person in Canada gets Canadian answers, which is the only correct
    /// thing to do — availability and versions genuinely differ by region.
    static func region(locale: Locale = .current) -> String {
        guard let code = locale.region?.identifier, code.count == 2 else { return "US" }
        return code.uppercased()
    }

    /// **A session that carries nothing.**
    ///
    /// Ephemeral, so no cache and no cookie store survives the call; cookies refused outright; no
    /// credentials; no custom user agent, because a user agent naming this app and its version would
    /// be a small identifier we had no reason to send.
    static func session(timeout: TimeInterval = 15) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }

    static func url(for bundleIDs: [String], region: String) -> URL? {
        guard !bundleIDs.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIDs.joined(separator: ",")),
            URLQueryItem(name: "country", value: region),
        ]
        return components?.url
    }

    /// **Parse, and throw away anything that is not a Mac app.**
    ///
    /// ⚠️ `kind == "mac-software"` is the guard, and it is the Pages guard. A universal purchase
    /// answers with an iPhone record whose version belongs to a different piece of software; ranking
    /// a Mac build against it is the whole embarrassment this section was rebuilt to avoid.
    static func records(fromJSON data: Data) -> [String: Record] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return [:] }

        let dates = ISO8601DateFormatter()
        var records: [String: Record] = [:]
        for result in results {
            guard let bundleID = result["bundleId"] as? String,
                  let version = result["version"] as? String,
                  (result["kind"] as? String) == "mac-software"
            else { continue }
            records[bundleID.lowercased()] = Record(
                bundleID: bundleID,
                version: version,
                name: result["trackName"] as? String,
                releasedAt: (result["currentVersionReleaseDate"] as? String).flatMap(dates.date(from:)))
        }
        return records
    }

    /// Ask, in batches. A failed batch fails only its own identifiers.
    static func look(up bundleIDs: [String],
                     session: URLSession,
                     region: String) async -> Answer {
        let wanted = Array(Set(bundleIDs.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })).sorted()
        guard !wanted.isEmpty else { return .none }

        var found: [String: Record] = [:]
        var failed: Set<String> = []

        for start in stride(from: 0, to: wanted.count, by: batchSize) {
            let batch = Array(wanted[start..<min(start + batchSize, wanted.count)])
            guard let url = Self.url(for: batch, region: region) else {
                failed.formUnion(batch.map { $0.lowercased() })
                continue
            }
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    failed.formUnion(batch.map { $0.lowercased() })
                    continue
                }
                found.merge(Self.records(fromJSON: data)) { _, new in new }
            } catch {
                failed.formUnion(batch.map { $0.lowercased() })
            }
        }
        return Answer(records: found, failed: failed)
    }
}

// MARK: - ⭐ Homebrew casks — local metadata, no network at all

/// **What `brew` already wrote down, read as a file.**
///
/// Homebrew installs a cask into `<prefix>/Caskroom/<token>/<version>/`, so the installed version is
/// a directory name, and it keeps the whole catalogue of current cask versions in a JSON file it
/// refreshes on `brew update`. Both are on this Mac. **Nothing here touches the network, and nothing
/// here runs `brew`** — spawning `brew` would be seconds of Ruby start-up, and `brew outdated` would
/// happily go and fetch.
///
/// ⚠️ **A stale catalogue is treated as no answer.** The file is only as current as the last
/// `brew update`, and on a Mac where that has not run for months it would report versions that are
/// months behind — which produces confident *wrong* answers in both directions. Past
/// ``maximumAge``, every cask answers `.askFailed` instead.
///
/// ⚠️ **Nothing here was exercised against a real cask.** The Mac this was written on has Homebrew
/// installed and an empty Caskroom, so every path below is written from Homebrew's documented layout
/// and reads defensively: a shape it does not recognise produces no answer rather than a wrong one.
enum HomebrewCasks {

    /// One cask found in the Caskroom.
    struct InstalledCask: Sendable, Hashable {
        let token: String
        let version: String
    }

    /// One cask in Homebrew's catalogue.
    struct CaskRecord: Sendable, Hashable {
        let token: String
        /// `nil`, or Homebrew's sentinel `latest`, both mean there is no version to compare.
        let version: String?
        /// The apps this cask installs, without the `.app` — "Firefox", "Visual Studio Code".
        let appNames: [String]
    }

    /// What one read produced.
    struct Answer: Sendable, Hashable {
        /// Keyed by lower-cased app name with no extension, because that is the only thing a cask
        /// and an `InstalledApp` reliably share. A cask's record names the app it installs; an
        /// `InstalledApp` carries no path to match against.
        let standingsByAppName: [String: UpdateStanding]
        /// How many casks were found installed. Zero is an ordinary answer.
        let caskCount: Int
        /// When Homebrew last refreshed its catalogue. `nil` where there is no catalogue.
        let catalogueUpdatedAt: Date?

        static let none = Answer(standingsByAppName: [:], caskCount: 0, catalogueUpdatedAt: nil)
    }

    /// Older than this, the catalogue is not evidence about today.
    static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    /// Homebrew's sentinel for a cask that does not carry a version.
    static let unversioned = "latest"

    static let caskroomPaths = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]

    /// **Read it.** Blocking, a directory listing and one JSON file; a few milliseconds.
    static func read(fileManager: FileManager = .default) -> Answer {
        guard let caskroom = caskroom(fileManager: fileManager) else { return .none }
        let installed = installedCasks(inCaskroom: caskroom, fileManager: fileManager)
        guard !installed.isEmpty else { return .none }

        guard let catalogueURL = catalogueFile(fileManager: fileManager) else {
            return Answer(standingsByAppName: standings(installed: installed, catalogue: [:], fresh: false),
                          caskCount: installed.count,
                          catalogueUpdatedAt: nil)
        }

        let attributes = try? fileManager.attributesOfItem(atPath: catalogueURL.path)
        let updatedAt = attributes?[.modificationDate] as? Date
        let fresh = updatedAt.map { Date().timeIntervalSince($0) < maximumAge } ?? false
        let records = (try? Data(contentsOf: catalogueURL)).map { Self.catalogue(fromJSON: $0) } ?? [:]

        return Answer(standingsByAppName: standings(installed: installed, catalogue: records, fresh: fresh),
                      caskCount: installed.count,
                      catalogueUpdatedAt: updatedAt)
    }

    /// Where the Caskroom is. `HOMEBREW_PREFIX` first, for an installation somewhere unusual.
    static func caskroom(fileManager: FileManager,
                         environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates: [String] = []
        if let prefix = environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            candidates.append(prefix + "/Caskroom")
        }
        candidates += caskroomPaths
        for path in candidates {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return nil
    }

    /// The catalogue file. Homebrew moved this once already, so both places are tried.
    static func catalogueFile(fileManager: FileManager) -> URL? {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Homebrew/api", isDirectory: true)
        for name in ["cask.jws.json", "internal/cask.jws.json", "cask.json"] {
            let url = root.appendingPathComponent(name)
            if fileManager.isReadableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// Every cask installed, with the version directory that is actually on disk.
    ///
    /// A token can hold more than one version directory — Homebrew leaves the old one behind after
    /// some upgrades — so the newest by modification date is the installed one.
    static func installedCasks(inCaskroom caskroom: URL, fileManager: FileManager) -> [InstalledCask] {
        let tokens = (try? fileManager.contentsOfDirectory(at: caskroom,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])) ?? []
        return tokens.compactMap { token in
            let versions = (try? fileManager.contentsOfDirectory(
                at: token,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            let newest = versions
                .filter { $0.lastPathComponent != ".metadata" }
                .max { a, b in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da < db
                }
            guard let newest else { return nil }
            return InstalledCask(token: token.lastPathComponent, version: newest.lastPathComponent)
        }
    }

    /// **Parse Homebrew's catalogue.** It ships as a JWS envelope — an object with a `payload`
    /// string that itself holds the JSON — and used to ship as a bare array. Both are handled,
    /// because the shape has changed once already and will change again.
    static func catalogue(fromJSON data: Data) -> [String: CaskRecord] {
        var casks: [[String: Any]] = []
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            casks = array
        } else if let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = envelope["payload"] as? String,
                  let inner = payload.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: inner) as? [[String: Any]] {
            casks = array
        }

        var records: [String: CaskRecord] = [:]
        for cask in casks {
            guard let token = cask["token"] as? String else { continue }
            records[token] = CaskRecord(token: token,
                                        version: cask["version"] as? String,
                                        appNames: appNames(inArtifacts: cask["artifacts"]))
        }
        return records
    }

    /// The `.app` names a cask installs, out of its artifact list. Two shapes are known — a list of
    /// objects keyed `app`, and a bare list of names — and anything else contributes nothing.
    static func appNames(inArtifacts artifacts: Any?) -> [String] {
        guard let artifacts = artifacts as? [Any] else { return [] }
        var names: [String] = []
        for artifact in artifacts {
            if let object = artifact as? [String: Any], let apps = object["app"] as? [Any] {
                names += apps.compactMap { $0 as? String }
            } else if let name = artifact as? String, name.hasSuffix(".app") {
                names.append(name)
            }
        }
        return names.map(matchKey)
    }

    /// The key an app name is matched on: lower-cased, no `.app`, no surrounding space.
    static func matchKey(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasSuffix(".app") { text = String(text.dropLast(4)) }
        return text.lowercased()
    }

    /// **Compare two cask versions.**
    ///
    /// Homebrew writes some versions as `version,revision` — `3.4.5,1234` — where the part after the
    /// comma is the publisher's build number. Both halves are compared, in order, and a comma on one
    /// side only is two different schemes and is refused. `latest` on either side is Homebrew saying
    /// the cask has no version at all.
    static func standing(installed: String, current: String?) -> UpdateStanding {
        guard let current, !current.isEmpty, !installed.isEmpty else {
            return .couldNotTell(.noSourceToAsk)
        }
        if installed.caseInsensitiveCompare(unversioned) == .orderedSame
            || current.caseInsensitiveCompare(unversioned) == .orderedSame {
            return .couldNotTell(.versionsNotComparable)
        }
        if installed == current { return .current }

        let left = installed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let right = current.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard left.count == right.count else { return .couldNotTell(.versionsNotComparable) }

        switch VersionComparison.compare(installed: left[0], current: right[0]) {
        case .currentIsNewer:
            return .newerAvailable(current)
        case .installedIsNewer:
            return .current
        case .notComparable:
            return .couldNotTell(.versionsNotComparable)
        case .same:
            guard left.count == 2 else { return .current }
            switch VersionComparison.compare(installed: left[1], current: right[1]) {
            case .currentIsNewer:  return .newerAvailable(current)
            case .same, .installedIsNewer: return .current
            case .notComparable:   return .couldNotTell(.versionsNotComparable)
            }
        }
    }

    /// Every installed cask's answer, keyed by the app it installs.
    static func standings(installed: [InstalledCask],
                          catalogue: [String: CaskRecord],
                          fresh: Bool) -> [String: UpdateStanding] {
        var result: [String: UpdateStanding] = [:]
        for cask in installed {
            guard let record = catalogue[cask.token] else { continue }
            // No catalogue, or one too old to be evidence about today. We looked and got nothing
            // usable back, which is exactly what `.askFailed` says — and it is deliberately not
            // `.noSourceToAsk`, because there *is* a source and it will work again after
            // `brew update`.
            let answer: UpdateStanding = fresh
                ? Self.standing(installed: cask.version, current: record.version)
                : .couldNotTell(.askFailed)
            // A cask with no named app cannot be matched to anything on the Applications list, and
            // the cask token is not an app name. Skipped rather than guessed at.
            for name in record.appNames where !name.isEmpty {
                result[name] = answer
            }
        }
        return result
    }
}

// MARK: - ⭐ The reader

/// **One run of the update check.**
///
/// Hand it the inventory and the consent answer; it hands back one standing per app, ready for
/// `AppsInventory.applying(_:)`, plus the exact list of what was named to anybody.
enum UpdateReader {

    /// What one run produced.
    struct Answer: Sendable, Hashable {

        /// One standing per app, keyed by bundle identifier.
        let standings: [String: UpdateStanding]

        /// **The apps whose names left this Mac**, alphabetical. Empty when consent was withheld or
        /// nothing here is an App Store app.
        ///
        /// ⚠️ Kept so the section can *show* it. The disclosure on the consent sheet says the
        /// storefront learns which App Store apps are installed; this is that list, after the fact,
        /// for the person who wants to see exactly what was said rather than take it on trust.
        let namedToAppStore: [String]

        /// The answer that was in force for this run.
        let consent: UpdateConsent.Answer

        /// How many Homebrew casks were read locally. Zero is ordinary.
        let casksRead: Int

        /// The sentence the section prints under the Updates row.
        var disclosureSentence: String {
            guard consent == .allowed else {
                return String(localized: """
                    Nothing was sent. Update checking is off, so no app on this Mac was named to \
                    anybody.
                    """)
            }
            guard !namedToAppStore.isEmpty else {
                return String(localized: """
                    Nothing was sent. Nothing installed here publishes a version we can ask about.
                    """)
            }
            let names = namedToAppStore.formatted(.list(type: .and))
            return namedToAppStore.count == 1
                ? String(localized: "Wellkept asked Apple's App Store about one app: \(names). Nothing else left this Mac.")
                : String(localized: "Wellkept asked Apple's App Store about \(namedToAppStore.count) apps: \(names). Nothing else left this Mac.")
        }

        static let notChecked = Answer(standings: [:],
                                       namedToAppStore: [],
                                       consent: .notAsked,
                                       casksRead: 0)
    }

    /// **A TestFlight build, recognised by who signed it.**
    ///
    /// ⚠️ `AppOrigin` has no TestFlight case, and that is correct: macOS itself files these under
    /// `obtained_from: unknown`, and none of the six origins fits. What the app *does* carry is the
    /// signature, whose subject reads **"TestFlight Beta Distribution"** in full. `InventoryReader`
    /// says so in its own header and leaves the conclusion to this file.
    ///
    /// It matters more than six apps' worth. The storefront answers about the **shipping** version,
    /// which is a different piece of software from the pre-release build somebody is running on
    /// purpose — so comparing them tells six people their beta is out of date, every time, for ever.
    /// `.testFlightBuild` is also out of scope for coverage, so those six neither flatter the
    /// coverage figure nor count against it.
    static func isTestFlightBuild(_ app: InstalledApp) -> Bool {
        guard let signer = app.signedBy.name else { return false }
        return signer.range(of: "TestFlight", options: .caseInsensitive) != nil
    }

    /// **Read every app's standing.**
    ///
    /// ## The order sources are tried, and why it is this order
    ///
    /// 1. **A standing the inventory already set is kept.** The inventory sees the bundle on disk
    ///    and this reader does not, so a decision it made with evidence we do not have is never
    ///    overwritten. Then **TestFlight builds** — recognised from the signature, six apps on the
    ///    measured Mac; see ``isTestFlightBuild(_:)``.
    /// 2. **Anything that ships with macOS** answers `.shipsWithMacOS`, so it does not repeat what
    ///    the macOS row already says. Safari is in here by way of `addedByHand`: it is absent from
    ///    Apple's own inventory, added by hand, and it comes with the system.
    /// 3. **`SelfUpdatingApps`** answers `.keepsItselfUpToDate` — the opposite message from "cannot
    ///    be checked", and never collapsed into it.
    /// 4. **Homebrew's local catalogue**, matched by app name. Tried for every remaining app rather
    ///    than only for apps the inventory called `.homebrew`, because the Caskroom is direct
    ///    evidence that a cask installed that app and does not depend on our guess about its origin.
    /// 5. **Apple's storefront**, for App Store apps only. Restricted deliberately: asking about an
    ///    app we have no reason to think came from the store both discloses more and invites a wrong
    ///    answer, because a directly-downloaded build and the store's build of the same app are two
    ///    different pieces of software with two different version lines.
    /// 6. **Everything else** answers `.noSourceToAsk`, which is the honest cost of the maker-list
    ///    decision and is said in those words on the row.
    ///
    /// Blocking on the network only in step 5, and off the main thread throughout.
    static func read(apps: [InstalledApp],
                     consent: UpdateConsent.Answer,
                     session: URLSession? = nil,
                     fileManager: FileManager = .default,
                     locale: Locale = .current) async -> Answer {

        // ⚠️ No consent, no answers — including the ones that need no network. The sentence already
        // shipped to the user says the section "does not know whether any of them is current", and
        // splitting that by which fact happened to need a request is a distinction nobody agreed to.
        guard consent == .allowed else {
            return Answer(standings: apps.reduce(into: [:]) { $0[$1.bundleID] = .notChecked },
                          namedToAppStore: [],
                          consent: consent,
                          casksRead: 0)
        }

        var standings: [String: UpdateStanding] = [:]
        var unresolved: [InstalledApp] = []

        for app in apps {
            if app.update != .notChecked {
                standings[app.bundleID] = app.update
            } else if isTestFlightBuild(app) {
                standings[app.bundleID] = .couldNotTell(.testFlightBuild)
            } else if app.origin == .bundledWithMacOS || app.addedByHand {
                standings[app.bundleID] = .couldNotTell(.shipsWithMacOS)
            } else if let selfUpdating = SelfUpdatingApps.standing(forBundleID: app.bundleID) {
                standings[app.bundleID] = selfUpdating
            } else {
                unresolved.append(app)
            }
        }

        let casks = HomebrewCasks.read(fileManager: fileManager)
        var stillUnresolved: [InstalledApp] = []
        for app in unresolved {
            if let standing = casks.standingsByAppName[HomebrewCasks.matchKey(app.name)] {
                standings[app.bundleID] = standing
            } else {
                stillUnresolved.append(app)
            }
        }

        let storeApps = stillUnresolved.filter { $0.origin == .appStore }
        for app in stillUnresolved where app.origin != .appStore {
            standings[app.bundleID] = .couldNotTell(.noSourceToAsk)
        }

        guard !storeApps.isEmpty else {
            return Answer(standings: standings,
                          namedToAppStore: [],
                          consent: consent,
                          casksRead: casks.caskCount)
        }

        // The one request. A session we made is ours to invalidate; one handed in belongs to the
        // caller, and tests hand one in.
        let ownSession = session == nil
        let session = session ?? AppStoreVersions.session()
        defer { if ownSession { session.finishTasksAndInvalidate() } }

        let answer = await AppStoreVersions.look(up: storeApps.map(\.bundleID),
                                                 session: session,
                                                 region: AppStoreVersions.region(locale: locale))

        for app in storeApps {
            let key = app.bundleID.lowercased()
            if let record = answer.records[key] {
                standings[app.bundleID] = VersionComparison.standing(installed: app.version,
                                                                     current: record.version)
            } else if answer.failed.contains(key) {
                standings[app.bundleID] = .couldNotTell(.askFailed)
            } else {
                // Asked, answered, and the store has no Mac version for this app. Pages is exactly
                // this: the storefront's record is the iPhone one, and we threw it away on purpose.
                standings[app.bundleID] = .couldNotTell(.noSourceToAsk)
            }
        }

        return Answer(standings: standings,
                      namedToAppStore: storeApps.map(\.name).sorted(),
                      consent: consent,
                      casksRead: casks.caskCount)
    }
}
