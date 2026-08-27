import Foundation

//  AppleWords.swift
//  Wellkept
//
//  **Apple's own words, turned back into the English key they came from.**
//
//  ## The bug this file exists to fix
//
//  `system_profiler` **localises its values.** `BatteryReader` lowercased the battery's condition
//  word and looked for "service", "replace" and "poor" — English, spelled out, compared directly.
//  On a French Mac the same field reads *Réparation recommandée*, which contains none of those
//  three, so a battery Apple itself says needs servicing came back as `.normal`. Silently, on
//  every non-English Mac, in a shipped build.
//
//  It is worse than a missed word. **French maps both `Fair` and `Poor` onto the same string** —
//  *Réparation recommandée* — so normal wear and a service recommendation become indistinguishable
//  in both directions, and no amount of adding French words to the comparison can separate them
//  again. The information is gone before we see it.
//
//  ## Why the fix is a reverse map and not a bigger word list
//
//  Every `.spreporter` bundle ships a **world-readable `Localizable.loctable`**: one property list
//  holding every language, as `language → [key: localized value]`. The keys are stable English
//  identifiers Apple has not renamed in years. The values are the translated strings, and they are
//  the only thing that reaches us.
//
//      SPPowerReporter · English   "Good" → "Normal", "Fair" → "Service Recommended",
//                                  "Poor" → "Service Recommended", "Check Battery" → "…"
//      SPPowerReporter · fr        "Good" → "Normal", "Fair" → "Réparation recommandée",
//                                  "Poor" → "Réparation recommandée"
//
//      SPiBridgeReporter · en      "Full Security" → "Full Security"
//      SPiBridgeReporter · fr      "Full Security" → "Sécurité maximale"
//
//  So the fix is to read the same table Apple printed from, and run it backwards.
//
//  ⚠️ **The language cannot be forced.** `system_profiler` rejects `-AppleLanguages` outright — it
//  prints its usage and exits — so "just ask it in English" is not available. Verified on this Mac,
//  2026-08-27.
//
//  ## ⚠️ Ambiguity is returned, never guessed away
//
//  Reverse-mapping *Réparation recommandée* honestly yields **three** keys: `Fair`, `Poor` and
//  `Check Battery`. `Fair` is ordinary wear; the other two are Apple recommending service. There is
//  no way to tell which one this Mac has, and inventing one would be a guess printed as a fact —
//  the exact thing this app exists to not do.
//
//  `Meaning` therefore has a `.ambiguous` case, and the caller has to handle it. What a caller must
//  not do is silently pick a side; what it should do is take the safer reading **and say the
//  uncertainty out loud on the row**, which is what `BatteryReader` does.
//
//  Note that English is not the safe case either: the English table collapses `Fair`, `Poor` and
//  `Check Battery` onto "Service Recommended" too. This is Apple's own collapse, visible in
//  System Settings, and it is why a caller taking the cautious reading is agreeing with what the
//  person can see on their own screen rather than contradicting it.
//
//  ## What is deliberately not here
//
//  - **No shipped copy of Apple's words.** A table baked into this app would be a snapshot that
//    rots the first time Apple retranslates a string, and rot silently. This reads the machine's
//    own file, so it is right by construction or absent.
//  - **No private API.** A property list on disk, opened read-only. No entitlement, no permission,
//    no Full Disk Access, no subprocess.
//  - **No failure that costs a reading.** A missing, moved or unparsable loctable falls back to
//    comparing the value against the English keys directly, which is exactly as good as the code
//    this replaces and no worse.

/// Apple's localized `system_profiler` values, reversed back into their stable English keys.
///
/// Shared by `BatteryReader` and by the Security readers, which face the same problem with the
/// boot-security values (`Full Security` / `Medium Security` / `Permissive Security`).
enum AppleWords {

    // MARK: - Which reporter's words

    /// One `system_profiler` reporter bundle, named by the vocabulary it owns rather than by the
    /// data type a caller passes on the command line.
    ///
    /// The raw value is the bundle's own name under `/System/Library/SystemProfiler`. Adding a
    /// reporter costs one line and no lookup: nothing here enumerates the folder, so a case that
    /// names a bundle Apple has removed simply falls back to the English comparison.
    enum Reporter: String, CaseIterable, Sendable {
        /// Battery condition and cycle count. `SPPowerDataType`.
        case power = "SPPowerReporter"
        /// Secure boot, SIP, kernel extension policy. `SPiBridgeDataType`.
        case controller = "SPiBridgeReporter"
        /// Firewall state and its per-app list. `SPFirewallDataType`.
        case firewall = "SPFirewallReporter"
        /// Installed configuration profiles — how a managed Mac announces itself.
        case configurationProfiles = "SPConfigurationProfileReporter"
        /// System and app extensions.
        case extensions = "SPExtensionsReporter"
        /// Installed applications, signing authority, obtained-from.
        case applications = "SPApplicationsReporter"
        /// Volumes, encryption and free space.
        case storage = "SPStorageReporter"
        /// The internal drive's own SMART verdict.
        case nvme = "SPNVMeReporter"

        /// Where the table lives. Read-only; nothing in this file writes anywhere.
        var loctableURL: URL {
            URL(filePath: "/System/Library/SystemProfiler")
                .appending(path: "\(rawValue).spreporter", directoryHint: .isDirectory)
                .appending(path: "Contents/Resources/Localizable.loctable", directoryHint: .notDirectory)
        }
    }

    // MARK: - What a value turned back into

    /// The English key or keys a localized value could have come from.
    ///
    /// `.several` is a real answer, not an error. See the header: *Réparation recommandée* genuinely
    /// is three keys, and pretending otherwise is where the information gets lost.
    enum Match: Sendable, Hashable {
        /// Exactly one English key. The ordinary case.
        case one(String)
        /// More than one English key produces this same string in this language. Sorted, so two
        /// runs on the same Mac give the same answer in the same order.
        case several([String])
        /// Nothing in the table produces this string. Carries the value back unchanged, so a caller
        /// can still show what the machine actually said rather than a blank.
        case unrecognised(String)

        /// Every key this could be — empty when nothing matched.
        var keys: [String] {
            switch self {
            case let .one(key):      [key]
            case let .several(keys): keys
            case .unrecognised:      []
            }
        }

        /// The key, only when there is exactly one. `nil` where a caller would be guessing.
        var certainKey: String? {
            if case let .one(key) = self { return key }
            return nil
        }

        var isAmbiguous: Bool {
            if case .several = self { return true }
            return false
        }
    }

    /// A localized value, resolved into whatever the caller's own vocabulary calls it.
    ///
    /// The generic is the caller's enum — `BatteryReader.Condition`, a boot-security level, a
    /// firewall state. Several English keys mapping onto the same value of yours collapse to
    /// `.certain`: three keys meaning "service recommended" are not an ambiguity, they are one
    /// answer said three ways.
    enum Meaning<Value: Hashable & Sendable>: Sendable, Hashable {
        /// One answer, and we are sure of it.
        case certain(Value)
        /// This Mac's language cannot tell these apart. **Always more than one.** A caller must
        /// choose the safer reading *and say so on the row*.
        case ambiguous(Set<Value>)
        /// The machine said something this table has never heard of, or the table could not be
        /// read at all.
        case unrecognised

        /// The answer where there is one, `nil` where the caller would be guessing.
        var certainValue: Value? {
            if case let .certain(value) = self { return value }
            return nil
        }

        /// Everything it might be. One element when certain, none when unrecognised.
        var possibilities: Set<Value> {
            switch self {
            case let .certain(value):     [value]
            case let .ambiguous(values):  values
            case .unrecognised:           []
            }
        }

        var isAmbiguous: Bool {
            if case .ambiguous = self { return true }
            return false
        }

        /// Whether this could be the given value — true for a certain match and for an ambiguity
        /// that includes it.
        func couldBe(_ value: Value) -> Bool { possibilities.contains(value) }
    }

    // MARK: - The two calls

    /// Turn one localized `system_profiler` value back into its English key.
    ///
    /// Three steps, in this order, and the order is the whole design:
    ///
    /// 1. **Is it already a key?** On this Mac `sppower_battery_health` comes back as `"Good"` —
    ///    the raw key, not the English string `"Normal"` it maps to. Some fields are emitted
    ///    untranslated and some are not, and there is no flag saying which, so the key set is
    ///    checked first. It is also the one lookup that cannot be ambiguous.
    /// 2. **Reverse the reader's own language**, then English, then everything else. Preferring the
    ///    Mac's language first is what stops a word that happens to be spelled the same in two
    ///    languages from resolving to the wrong key.
    /// 3. **Give the value back unchanged**, so the caller can print what the machine said.
    static func englishKey(for value: String, from reporter: Reporter) -> Match {
        let wanted = normalise(value)
        guard !wanted.isEmpty, let table = Table.load(reporter) else {
            return .unrecognised(value)
        }

        if let exact = table.keysByNormalisedKey[wanted] {
            return .one(exact)
        }

        for tier in table.reverseMapsInPreferenceOrder {
            if let keys = tier[wanted] {
                return keys.count == 1 ? .one(keys[0]) : .several(keys)
            }
        }

        return .unrecognised(value)
    }

    /// Turn one localized value into the caller's own vocabulary.
    ///
    /// `meanings` is keyed by **English key**, which is the part Apple keeps stable. Anything the
    /// table does not mention is `.unrecognised` rather than a default: a value we have never seen
    /// must not quietly become "normal".
    static func meaning<Value: Hashable & Sendable>(
        of value: String,
        from reporter: Reporter,
        keys meanings: [String: Value]
    ) -> Meaning<Value> {
        let match = englishKey(for: value, from: reporter)
        let found = Set(match.keys.compactMap { meanings[$0] })

        if found.count == 1, let only = found.first { return .certain(only) }
        if found.count > 1 { return .ambiguous(found) }

        // Nothing matched through the table. Last resort, and the same comparison the old code
        // made: the value may literally be one of the English keys under different casing or
        // spacing, which `englishKey` already tried — so if we are here there is genuinely nothing.
        return .unrecognised
    }

    // MARK: - Normalising

    /// Case and whitespace folded, so a stray leading space in a table (Apple indents its label
    /// strings with two) or a capitalisation change cannot cost a match.
    ///
    /// `lowercased()` rather than `localizedLowercase`: this runs against a table of many languages
    /// at once, and a fold that depends on the *current* locale would give different answers on a
    /// Turkish Mac for the same two strings.
    private static func normalise(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - The table, read once

    /// One reporter's loctable, parsed and reversed, cached for the life of the process.
    ///
    /// Parsing is a property-list read of a file that does not change while the app is running, and
    /// the reverse maps are built once. A check that reads the battery and six security facts would
    /// otherwise open and parse the same file seven times.
    private struct Table: Sendable {

        /// Normalised English key → the key exactly as Apple spells it.
        let keysByNormalisedKey: [String: String]

        /// Normalised localized value → the English keys that produce it, sorted. In tiers: the
        /// Mac's own language first, then English, then every other language in the file.
        let reverseMapsInPreferenceOrder: [[String: [String]]]

        // MARK: Loading

        /// Cached per reporter. `nil` is cached too — a machine with no loctable must not be asked
        /// for one on every reading.
        static func load(_ reporter: Reporter) -> Table? {
            cache.withLock { store in
                if let known = store[reporter] { return known }
                let built = build(reporter)
                store[reporter] = .some(built)
                return built
            }
        }

        /// `[Reporter: Table?]` — the outer optional is "have we looked", the inner is "was there
        /// anything there".
        private static let cache = Lock<[Reporter: Table?]>([:])

        private static func build(_ reporter: Reporter) -> Table? {
            guard let data = try? Data(contentsOf: reporter.loctableURL, options: [.mappedIfSafe]),
                  let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                         options: [],
                                                                         format: nil),
                  let raw = plist as? [String: Any]
            else { return nil }

            // ⚠️ **Not `as? [String: [String: String]]` on the whole file.** `LocProvenance` is a
            // dictionary of *numbers*, so the strict cast fails and takes every language with it —
            // the file would parse and then be thrown away, and the fallback would look like a
            // machine with no loctable. Each language is cast on its own instead, and anything that
            // is not a table of strings is skipped.
            var byLanguage: [String: [String: String]] = [:]
            for (name, value) in raw where !metadataKeys.contains(name) {
                if let table = value as? [String: String] { byLanguage[name] = table }
            }
            guard !byLanguage.isEmpty else { return nil }

            var keysByNormalisedKey: [String: String] = [:]
            for table in byLanguage.values {
                for key in table.keys {
                    let folded = AppleWords.normalise(key)
                    if !folded.isEmpty { keysByNormalisedKey[folded] = key }
                }
            }

            let names = Set(byLanguage.keys)
            let ownLanguage = preferredNames.filter(names.contains)
            let english = englishNames.filter { names.contains($0) && !ownLanguage.contains($0) }
            let rest = names.subtracting(ownLanguage).subtracting(english).sorted()

            let tiers = [ownLanguage, english, rest].map { group in
                reverse(group.compactMap { byLanguage[$0] })
            }

            return Table(keysByNormalisedKey: keysByNormalisedKey,
                         reverseMapsInPreferenceOrder: tiers.filter { !$0.isEmpty })
        }

        /// Value → keys, for one tier of language tables.
        private static func reverse(_ tables: [[String: String]]) -> [String: [String]] {
            var map: [String: Set<String>] = [:]
            for table in tables {
                for (key, value) in table {
                    let folded = AppleWords.normalise(value)
                    guard !folded.isEmpty else { continue }
                    map[folded, default: []].insert(key)
                }
            }
            return map.mapValues { $0.sorted() }
        }

        // MARK: Which language tables, in which order

        /// Not languages. `LocProvenance` is Apple's own bookkeeping and holds no strings.
        private static let metadataKeys: Set<String> = ["LocProvenance"]

        /// Every spelling of English a loctable has been seen to use. `SPPowerReporter` files its
        /// English under the literal string **"English"**; `SPiBridgeReporter` files it under
        /// **"en"**. Both are checked, because a table that used the other one would silently lose
        /// the fallback tier.
        private static let englishNames = ["en", "English", "en_US", "en_GB", "en_AU", "Base"]

        /// This Mac's languages, in its own order, in every spelling a table might use:
        /// `fr-CA` → `fr_CA`, `fr`. Computed once — `Locale.preferredLanguages` does not change
        /// while the app is running, and a change to it restarts the app anyway.
        private static let preferredNames: [String] = {
            var names: [String] = []
            for tag in Locale.preferredLanguages {
                let underscored = tag.replacingOccurrences(of: "-", with: "_")
                let base = String(underscored.prefix { $0 != "_" })
                for candidate in [underscored, base] where !names.contains(candidate) {
                    names.append(candidate)
                }
                if base == "en", !names.contains("English") { names.append("English") }
            }
            return names
        }()
    }
}

// MARK: - The smallest possible lock

/// A value behind a mutex, for the one cache in this file.
///
/// `NSLock` rather than an actor: `AppleWords` is called from readers that are plain synchronous
/// functions on whatever queue the check is running on, and making the lookup `async` would push
/// `await` through four readers to protect a dictionary that is written once per reporter.
///
/// `@unchecked Sendable` is the honest admission: the compiler cannot see that `value` is only ever
/// touched inside `withLock`. It is `private` to this file and nothing else can reach it.
private final class Lock<Value>: @unchecked Sendable {
    private var value: Value
    private let mutex = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        mutex.lock()
        defer { mutex.unlock() }
        return body(&value)
    }
}
