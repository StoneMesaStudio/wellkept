// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import Foundation
import SQLite3
import Security
import WellkeptCore

//  GrantReader.swift
//  Wellkept — App/Security
//
//  **Which apps you have allowed to use the camera, the microphone, the screen, or to control
//  this Mac.**
//
//  This is the most delicate screen in the app, and the reason is not technical. Every other row
//  reports a machine. This one reports a person's own choices back at them, and the difference
//  between a health check and an anxiety machine is entirely in which of those choices we colour.
//
//  ## The rule that decides what this file is
//
//  **Holding a permission is not a finding.** A screen-sharing app holding Screen Recording is how
//  it works. A video app holding the camera is how it works. If every held permission were amber,
//  a normal Mac would open on a screen of amber and the person would learn, correctly, that our
//  colours mean nothing.
//
//  So exactly **two** things here go amber, and both are in `SecurityConcern`:
//
//  1. `.signatureChangedSinceApproved` — the app on disk no longer signs as the app the permission
//     was granted to, **and** the permission is the camera, the microphone or the screen.
//  2. `.permissionHeldByMissingApp` — the permission is still on the list and the app is not on
//     this Mac.
//
//  Everything else is a plain fact with no colour. There is no third condition and adding one is a
//  conversation with John, not a commit.
//
//  ## ⚠️ Without Full Disk Access this screen is EMPTY, not partial
//
//  Measured 2026-08-27: eleven of the twelve permissions read **exactly zero** without the grant.
//  Only Location reads without it, out of a world-readable plist.
//
//  So a refusal collapses the whole row to the one house sentence and **hides Location too**. One
//  populated row surrounded by refusals reads as "we checked and found almost nothing", which is
//  precisely the sentence this product promised never to say. It is `.notPermitted` — the one
//  refusal a person can actually lift — so it carries a button and it marks the check incomplete.
//
//  ## ⚠️ macOS 27 may move this
//
//  Everything below reads `TCC.db`, which is Apple's private store and not API. It has been
//  reshaped before. So the reader **proves the schema before it believes a number**: it asks the
//  database for its own columns, and it treats "we opened it and found nothing at all" as a
//  changed store rather than as an empty one — because a Mac that just demonstrated it has Full
//  Disk Access has, at minimum, the row recording that grant. A schema change therefore makes this
//  row say it could not read. It does not crash, and it does not quietly show an empty list, which
//  is the failure that would look exactly like good news.
//
//  ## ⚠️ Location's last-used times are never printed
//
//  `/var/db/locationd/clients.plist` carries, for every app, the moment it last received a
//  location. It is world-readable and it is none of our business. "Maps used your location on
//  Saturday at 16:20" is us watching the user, in a section about who is watching the user.
//
//  `locationFieldsRead` is the enforcement rather than the promise: the parser takes only the three
//  keys named there, and a test holds the set.
//
//  ## Wellkept is in its own list
//
//  Wellkept holds Full Disk Access — that is how it read any of this — so Wellkept appears here
//  like anything else. John's call, 2026-08-27: say so rather than filter ourselves out. An app
//  that quietly removes itself from the list of apps that can read your disk has answered the
//  question of whether to trust it.
//
//  ## What we deliberately do not claim
//
//  - **Held is not the same as in use.** Nothing unprivileged distinguishes an app that has the
//    camera from an app that is using the camera right now, so this file never implies the
//    difference. The row says what is allowed, and the word "using" does not appear.
//  - **"Not installed" is claimed only where we are sure.** See `Placement`. A background helper
//    that LaunchServices has never registered is *not* evidence that anything was uninstalled, and
//    concern 9 is amber: a false one is an accusation about software the person cannot even find.
//  - **An unchecked signature is not a failed one.** Only `errSecCSReqFailed` — the system saying
//    the code does not satisfy the requirement the grant was made against — becomes `.changed`.
//    Every other error is `.unknown`.
//
//  ## ⚠️ Not verified against a real database
//
//  The research that produced this file ran in a shell **without** Full Disk Access, so the TCC
//  reads below were written against Apple's documented schema and exercised against fixture
//  databases this repo builds, not against this Mac's own. The Location half, which needs no
//  permission, was read for real: 47 clients, 11 authorised. The schema guard exists partly
//  because of that gap.

//  ⚠️ **`Permission` is spelled `WellkeptCore.Permission` throughout this file, and it has to be.**
//  `App/Permissions.swift` — owner C's — already owns the bare name in this target, for the one
//  permission *this* app asks for. This file is about the twelve permissions *other* apps hold,
//  which live in the shared vocabulary. Same word, two subjects; a `typealias` would only move the
//  ambiguity somewhere less obvious.

enum GrantReader {

    // MARK: - Where the answers live

    /// The files this reader opens. Injectable, so the tests can point at fixtures — a reader that
    /// can only be exercised on a machine with Full Disk Access is a reader nobody exercises.
    struct Sources: Sendable, Hashable {

        /// `~/Library/Application Support/com.apple.TCC/TCC.db` — camera, microphone, contacts,
        /// calendars, reminders, photos, controlling other apps.
        var userDatabase: URL

        /// `/Library/Application Support/com.apple.TCC/TCC.db` — screen recording, control of this
        /// Mac, keystrokes, Full Disk Access.
        ///
        /// ⚠️ **Both databases are asked for every service**, rather than each being asked only for
        /// the ones it is supposed to hold. Which store owns which service has moved between macOS
        /// releases — screen recording in particular — and a reader built on a belief about that
        /// goes silently empty on the release that moves one. Asking both costs one extra query and
        /// removes the belief.
        var systemDatabase: URL

        /// `/var/db/locationd/clients.plist` — world-readable, and the only one of the twelve that
        /// needs no permission at all.
        var locationClients: URL

        /// Us. Compared against the grants so the row can say out loud that we are on it.
        var ourBundleID: String

        static let machine = Sources(
            userDatabase: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
            systemDatabase: URL(filePath: "/Library/Application Support/com.apple.TCC/TCC.db"),
            locationClients: URL(filePath: "/var/db/locationd/clients.plist"),
            ourBundleID: Bundle.main.bundleIdentifier ?? "studio.stonemesa.wellkept"
        )
    }

    /// The two questions this reader asks the rest of the machine: where an app lives, and whether
    /// it is still the app that was approved.
    ///
    /// Injected rather than called directly so the row-building logic — which is where every
    /// judgement of this file lives — can be tested without an app bundle to hand.
    struct Lookups: Sendable {

        /// Where the app with this bundle id is, or `nil` if nothing registered claims it.
        var applicationURL: @Sendable (String) -> URL?

        /// Does the code at this URL still satisfy the requirement the grant was made against?
        var signature: @Sendable (URL, Data) -> SignatureStanding

        var fileExists: @Sendable (URL) -> Bool

        static let machine = Lookups(
            applicationURL: { GrantReader.registeredApplication(for: $0) },
            signature: { GrantReader.standing(of: $0, against: $1) },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
    }

    // MARK: - What one run produced

    /// The row for the section, and the list the screen draws under it.
    ///
    /// `SecurityRow` is the shared shape and it carries only `DetailPair`s, which is right for
    /// Options and wrong for a screen whose whole content is a list of apps. So the grants come
    /// back beside the row rather than being flattened into it, in this file's own namespace —
    /// `Security.swift` belongs to somebody else and this is not a name to invent there.
    struct Findings: Sendable, Hashable {

        /// The row in the section's fixed row set. Never re-sorted, never one row per app.
        let row: SecurityRow

        /// Every app-and-permission pair we found, in a stable order. **Empty when `row` is
        /// unreadable** — never a short list standing in for a refusal.
        let grants: [Grant]

        /// Identifiers we could neither place nor rule out — background helpers, mostly. Counted,
        /// stated, and never accused. See `Placement.uncertain`.
        let unplaceable: [String]

        /// Parts of macOS itself that use location and are not apps anybody installed.
        let systemServicesUsingLocation: Int

        /// True when the screen is collapsed because Full Disk Access was refused.
        var wasRefused: Bool { row.unreadable == .notPermitted }
    }

    // MARK: - The read

    /// Read the row.
    ///
    /// - Parameter fullDiskAccess: whether the grant is actually in place — probed by reading a
    ///   protected file, never by asking the user what they intended. See `FullDiskAccess`.
    static func read(fullDiskAccess: Bool = FullDiskAccess.isGranted,
                     sources: Sources = .machine,
                     lookups: Lookups = .machine) -> Findings {

        // ⚠️ The collapse. Not "some of the twelve" — none of them, Location included.
        guard fullDiskAccess else {
            return Findings(row: refusedRow(),
                            grants: [],
                            unplaceable: [],
                            systemServicesUsingLocation: 0)
        }

        let user = scan(sources.userDatabase)
        let system = scan(sources.systemDatabase)
        let scans = [user, system]

        // Neither store was recognisable. Say so; do not print an empty screen.
        guard scans.contains(where: \.wasUnderstood) else {
            return Findings(row: unrecognisedStoreRow(reason: scans.allSatisfy(\.wasUnopenable)
                                                        ? .unopenable : .schema),
                            grants: [],
                            unplaceable: [],
                            systemServicesUsingLocation: 0)
        }

        let raw = scans.flatMap(\.rows)

        // ⚠️ Zero rows across both stores, on a Mac that has just proved it holds Full Disk Access,
        // is not an empty list — the grant that let us open the file is itself a row. Something has
        // moved. Reporting "no app holds any permission" here would be the most reassuring wrong
        // answer this app is capable of producing.
        guard !raw.isEmpty else {
            return Findings(row: unrecognisedStoreRow(reason: .empty),
                            grants: [],
                            unplaceable: [],
                            systemServicesUsingLocation: 0)
        }

        var resolver = Resolver(lookups: lookups, ourBundleID: sources.ourBundleID)
        var grants = resolver.grants(from: raw)

        let location = locationGrants(at: sources.locationClients, lookups: lookups)
        grants.append(contentsOf: location.grants)

        let tidied = tidy(grants)
        let unplaceable = resolver.unplaceable.sorted()

        return Findings(row: row(grants: tidied,
                                 unplaceable: unplaceable,
                                 systemServicesUsingLocation: location.systemServices,
                                 storesNotRead: scans.count { !$0.wasUnderstood }),
                        grants: tidied,
                        unplaceable: unplaceable,
                        systemServicesUsingLocation: location.systemServices)
    }

    // MARK: - The row, when we could read

    /// Build the row from a finished list of grants. Pure, and where every judgement in this file
    /// actually happens — which is why it takes values rather than reading anything.
    /// - Parameter storesNotRead: how many of the two `TCC.db` files could not be understood while
    ///   the other one could.
    ///
    ///   ⚠️ **Half a list is still stated as half a list.** One store moving would otherwise take
    ///   screen recording, control of this Mac and Full Disk Access off the screen with no word
    ///   said, which is the same silence as reporting zero because we could not look. The row
    ///   cannot mark itself incomplete — `SecurityRow.complete` follows `unreadable`, and this row
    ///   did read something — so it says it in the words instead.
    static func row(grants: [Grant],
                    unplaceable: [String] = [],
                    systemServicesUsingLocation: Int = 0,
                    storesNotRead: Int = 0) -> SecurityRow {

        let apps = Set(grants.map(\.bundleID)).count
        let changed = grants.filter { $0.concern == .signatureChangedSinceApproved }
        let missing = grants.filter { $0.concern == .permissionHeldByMissingApp }

        return SecurityRow(
            topic: .whoCanWatch,
            headline: headline(apps: apps),
            measure: apps == 0 ? nil : (apps == 1 ? "1 app" : "\(apps) apps"),
            concerns: grants.compactMap(\.concern),
            reason: reason(grants: grants,
                           changed: changed,
                           missing: missing,
                           storesNotRead: storesNotRead),
            details: details(grants: grants,
                             changed: changed,
                             missing: missing,
                             unplaceable: unplaceable,
                             systemServicesUsingLocation: systemServicesUsingLocation,
                             storesNotRead: storesNotRead)
        )
    }

    private static func headline(apps: Int) -> String {
        switch apps {
        case 0:  "No app on this Mac holds any of these permissions."
        case 1:  "One app holds one of these permissions."
        default: "\(apps) apps hold one or more of these permissions."
        }
    }

    /// Why the row says what it says. Shown on the row itself, never behind a disclosure.
    ///
    /// ⚠️ The first sentence is load-bearing. Without it a list of twenty apps that can see the
    /// screen reads as twenty problems, and the person's first act is to start revoking things
    /// their software needs.
    private static func reason(grants: [Grant],
                               changed: [Grant],
                               missing: [Grant],
                               storesNotRead: Int) -> String {
        guard !grants.isEmpty else {
            return "Nothing has been allowed to use the camera, the microphone, the screen, or to "
                 + "control this Mac."
        }

        var sentences = [
            "Holding a permission is not a problem — a video app needs the camera and a "
          + "screen-sharing app needs the screen. This is the list of what you have allowed."
        ]

        if !changed.isEmpty {
            let names = list(changed.map(\.appName))
            sentences.append(changed.count == 1
                ? "\(names) no longer signs as the app the permission was given to."
                : "\(names) no longer sign as the apps the permissions were given to.")
        }
        if !missing.isEmpty {
            let apps = Set(missing.map(\.bundleID)).count
            sentences.append(apps == 1
                ? "One permission is still held by an app that is no longer on this Mac."
                : "\(apps) apps that are no longer on this Mac still hold permissions.")
        }
        if grants.contains(where: \.isWellkept) {
            sentences.append("Wellkept is on the list itself — it holds Full Disk Access, which is "
                           + "how it read the list.")
        }
        if storesNotRead > 0 {
            sentences.append("macOS keeps these permissions in two lists and one of them could not "
                           + "be read, so this is not all of them.")
        }
        return sentences.joined(separator: " ")
    }

    /// Options: the breakdown a person would go looking for.
    ///
    /// ⚠️ Every label must be unique. `DetailPair.id` is its label, so two pairs called "Changed"
    /// collide in a list and one of them silently does not draw — which RestartReader learned on a
    /// Mac in a boot loop.
    private static func details(grants: [Grant],
                                changed: [Grant],
                                missing: [Grant],
                                unplaceable: [String],
                                systemServicesUsingLocation: Int,
                                storesNotRead: Int) -> [DetailPair] {
        var pairs: [DetailPair] = []

        for permission in WellkeptCore.Permission.allCases {
            let holders = grants.filter { $0.permission == permission }
            guard !holders.isEmpty else { continue }
            pairs.append(DetailPair(permission.label, roster(holders)))
        }

        for grant in changed {
            pairs.append(DetailPair(
                "Changed — \(grant.appName) (\(grant.bundleID))",
                "Holds \(grant.permission.label.lowercased()). The app on disk signs as something "
              + "other than the app that permission was granted to."))
        }

        for grant in missing {
            pairs.append(DetailPair(
                "No longer installed — \(grant.appName) (\(grant.bundleID))",
                "\(grant.permission.label) is still granted to this identity. Anything installed "
              + "under it later starts with the permission already given."))
        }

        if !unplaceable.isEmpty {
            pairs.append(DetailPair(
                "Not found on this Mac",
                "\(unplaceable.count) of these identities are background helpers or parts of macOS "
              + "that we could not locate. That is not evidence they were removed, so nothing is "
              + "claimed about them."))
        }

        if storesNotRead > 0 {
            pairs.append(DetailPair(
                "Part of the list is missing",
                "macOS keeps these permissions in two files. One of them is not where it has "
              + "always been, or is not the shape we know, so whatever it held is not above."))
        }

        if systemServicesUsingLocation > 0 {
            pairs.append(DetailPair(
                "Location — parts of macOS",
                "\(systemServicesUsingLocation) services built into macOS also use location. They "
              + "are not apps anybody installed and they are not listed above."))
        }

        return pairs
    }

    /// "3 apps — Zoom, FaceTime, Photo Booth".
    ///
    /// Capped, because a disclosure that unrolls forty names is a disclosure nobody reads. The list
    /// on screen is the full one; this is the summary line.
    private static func roster(_ holders: [Grant]) -> String {
        let names = holders.map(\.appName)
        let count = names.count
        let head = names.prefix(namesPerLine)
        var text = count == 1 ? "1 app — " : "\(count) apps — "
        text += head.joined(separator: ", ")
        if count > head.count { text += ", and \(count - head.count) more" }
        return text
    }

    private static let namesPerLine = 8

    /// "Zoom", "Zoom and Loom", "Zoom, Loom and OBS".
    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0:  return ""
        case 1:  return names[0]
        case 2:  return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and \(names[names.count - 1])"
        }
    }

    /// De-duplicated by `Grant.id`, then put in a fixed order: permission first, then app name.
    ///
    /// Two runs on an unchanged Mac must produce the same list in the same order. SQLite makes no
    /// promise about row order without an `ORDER BY`, and Apple Events writes one row per *target*
    /// app, so the same app can arrive several times for the same permission.
    static func tidy(_ grants: [Grant]) -> [Grant] {
        var seen = Set<String>()
        return grants
            .filter { seen.insert($0.id).inserted }
            .sorted { left, right in
                let a = left.permission.order, b = right.permission.order
                if a != b { return a < b }
                let byName = left.appName.localizedCaseInsensitiveCompare(right.appName)
                if byName != .orderedSame { return byName == .orderedAscending }
                return left.bundleID < right.bundleID
            }
    }

    // MARK: - The row, when we could not

    /// Full Disk Access refused. **The whole screen, not part of it.**
    static func refusedRow() -> SecurityRow {
        SecurityRow.unreadable(
            .whoCanWatch,
            .notPermitted,
            about: "Which apps can use the camera, the microphone and the screen",
            reason: "macOS keeps this list in a file that only an app with Full Disk Access may "
                  + "open. Without it we see none of the twelve permissions rather than some of "
                  + "them, so nothing is listed — including location, which we could have read. A "
                  + "part of this list would read as a short list, and it is not a short list.",
            details: [
                DetailPair("What this would list",
                           "Camera, microphone, screen recording, control of this Mac, keystrokes, "
                         + "Full Disk Access, location, contacts, calendars, reminders, photos, "
                         + "and control of other apps."),
                // ⚠️ Named in SECURITY-QUESTIONS.md as a way the app looks broken while being
                // right: macOS does not hand a fresh grant to a process that is already running.
                DetailPair("After you switch it on",
                           "macOS does not give a new permission to an app that is already "
                         + "running. Quit Wellkept and open it again, and this list appears."),
            ],
            remedy: Remedy(title: "Open Full Disk Access",
                           settingsPane: SystemSettingsPane.fullDiskAccess.rawValue)
        )
    }

    /// Why the store could not be understood. Three shapes, one sentence each — the difference
    /// matters to whoever reads the bug report on the day macOS 27 ships.
    enum StoreTrouble: Sendable, Hashable {
        /// The file is not where it has always been, or it would not open.
        case unopenable
        /// It opened, and it is not the shape we know.
        case schema
        /// It opened, it is the right shape, and it holds nothing — which cannot be true here.
        case empty
    }

    /// The store moved or changed. **`.notReported`, not `.notPermitted`**: we already have the one
    /// permission that exists, so there is no button and nothing for a person to do. The check
    /// stays complete and the row states plainly that we did not see it.
    static func unrecognisedStoreRow(reason: StoreTrouble) -> SecurityRow {
        let explanation: String
        switch reason {
        case .unopenable:
            explanation = "macOS keeps this list in a private file, and that file is no longer "
                        + "where it has always been. This is what a macOS update looks like from "
                        + "in here."
        case .schema:
            explanation = "macOS keeps this list in a private file whose shape it changed. Rather "
                        + "than guess at the new one and show a list that might be wrong, this "
                        + "says nothing."
        case .empty:
            explanation = "The list opened and came back with nothing in it. That cannot be true "
                        + "on this Mac — reading it at all needed a permission that is itself an "
                        + "entry — so the store has changed rather than emptied."
        }
        return SecurityRow.unreadable(
            .whoCanWatch,
            .notReported,
            about: "Which apps can use the camera, the microphone and the screen",
            reason: explanation + " Nothing here is a finding about your Mac, and there is nothing "
                  + "to switch on: it is Wellkept that needs updating.",
            details: [DetailPair("What happened", label(for: reason))]
        )
    }

    private static func label(for trouble: StoreTrouble) -> String {
        switch trouble {
        case .unopenable: "The file macOS keeps these permissions in could not be opened."
        case .schema:     "The file opened, and its columns are not the ones we know."
        case .empty:      "The file opened and held no permissions at all."
        }
    }

    // MARK: - Turning rows into grants

    /// Resolves each raw row into a `Grant`, remembering what it could not place.
    ///
    /// A struct with state rather than a free function because both the app lookup and the
    /// signature check are expensive and repeat heavily — one app typically holds four or five
    /// permissions, and verifying a large bundle's signature five times is five times the work for
    /// the same answer.
    struct Resolver {
        let lookups: Lookups
        let ourBundleID: String

        private var placements: [String: Placement] = [:]
        private var signatures: [String: SignatureStanding] = [:]

        /// Identities we could neither find nor rule out.
        private(set) var unplaceable: Set<String> = []

        init(lookups: Lookups, ourBundleID: String) {
            self.lookups = lookups
            self.ourBundleID = ourBundleID
        }

        mutating func grants(from rows: [RawRow]) -> [Grant] {
            rows.compactMap { grant(from: $0) }
        }

        mutating func grant(from row: RawRow) -> Grant? {
            guard row.isAllowed, let permission = Self.permissions[row.service] else { return nil }

            let identity = Identity(client: row.client, clientType: row.clientType)
            let placement = place(identity)

            if case .uncertain = placement { unplaceable.insert(identity.bundleID) }

            // ⚠️ The signature is only checked for the three that can watch you, because those are
            // the only ones where a changed signature is a concern at all — see
            // `Permission.watchesYou`. It is also the expensive call in this file, so not making it
            // twelve times per app is worth the one line of condition.
            var standing = SignatureStanding.unknown
            if permission.watchesYou, case let .found(url) = placement, let requirement = row.requirement {
                standing = signature(of: url, against: requirement)
            }

            return Grant(appName: placement.name(for: identity),
                         bundleID: identity.bundleID,
                         permission: permission,
                         stillInstalled: placement.stillInstalled,
                         signature: standing,
                         grantedAt: row.lastModified,
                         isWellkept: identity.bundleID == ourBundleID)
        }

        private mutating func place(_ identity: Identity) -> Placement {
            if let known = placements[identity.key] { return known }
            let found = Self.place(identity, lookups: lookups)
            placements[identity.key] = found
            return found
        }

        private mutating func signature(of url: URL, against requirement: Data) -> SignatureStanding {
            let key = "\(url.path)|\(requirement.hashValue)"
            if let known = signatures[key] { return known }
            let standing = lookups.signature(url, requirement)
            signatures[key] = standing
            return standing
        }

        /// ⚠️ **Where "no longer installed" is decided, and it is deliberately reluctant.**
        ///
        /// A grant recorded by path is easy: the file is there or it is not, and the file system
        /// does not have opinions. A grant recorded by bundle id is not. LaunchServices registers
        /// *applications*; it does not necessarily register a helper tool, an XPC service or a
        /// daemon that lives inside one — and those hold permissions too. Taking "LaunchServices
        /// has never heard of it" as "it was uninstalled" would raise concern 9, in amber, against
        /// software that is sitting on the disk being fine.
        ///
        /// So a bundle id we cannot resolve is `.missing` only when nothing suggests otherwise:
        ///
        /// - an identity under `com.apple.` is macOS's own plumbing, and this app does not accuse
        ///   Apple's daemons of being leftovers;
        /// - an identity whose parent resolves — `com.foo.bar.helper` where `com.foo.bar` is
        ///   installed — is a component of something that is still here.
        ///
        /// Everything else is `.uncertain`: counted, stated in Options, and never coloured.
        static func place(_ identity: Identity, lookups: Lookups) -> Placement {
            switch identity {
            case let .path(path):
                let url = URL(filePath: path)
                return lookups.fileExists(url) ? .found(Self.bundle(containing: url)) : .missing

            case let .bundle(id):
                if let url = lookups.applicationURL(id) { return .found(url) }
                if id.hasPrefix("com.apple.") { return .uncertain }
                var parent = Substring(id)
                while let dot = parent.lastIndex(of: ".") {
                    parent = parent[parent.startIndex..<dot]
                    if lookups.applicationURL(String(parent)) != nil { return .uncertain }
                }
                return .missing
            }
        }

        /// `/Applications/Zoom.app/Contents/MacOS/zoom.us` → `/Applications/Zoom.app`.
        ///
        /// The signature check wants the bundle, not the executable inside it: checking the inner
        /// binary against a requirement written for the bundle fails for a reason that has nothing
        /// to do with the app having changed.
        static func bundle(containing url: URL) -> URL {
            var candidate = url
            while candidate.pathComponents.count > 1 {
                if candidate.pathExtension == "app" { return candidate }
                candidate = candidate.deletingLastPathComponent()
            }
            return url
        }

        /// Apple's service names, and the twelve permissions this section lists.
        ///
        /// Anything macOS tracks that is not one of the twelve — the Desktop and Downloads folders,
        /// Bluetooth, motion, media library — is skipped rather than crammed in. The twelve are the
        /// contract, and a thirteenth row appearing because Apple added a service is a change
        /// nobody agreed to.
        static let permissions: [String: WellkeptCore.Permission] = [
            "kTCCServiceCamera":               .camera,
            "kTCCServiceMicrophone":           .microphone,
            "kTCCServiceScreenCapture":        .screenRecording,
            "kTCCServiceAccessibility":        .accessibility,
            "kTCCServiceListenEvent":          .inputMonitoring,
            "kTCCServiceSystemPolicyAllFiles": .fullDiskAccess,
            "kTCCServiceAddressBook":          .contacts,
            "kTCCServiceCalendar":             .calendars,
            "kTCCServiceReminders":            .reminders,
            "kTCCServicePhotos":               .photos,
            "kTCCServiceAppleEvents":          .appleEvents,
        ]
    }

    /// How macOS recorded who a permission belongs to.
    enum Identity: Sendable, Hashable {
        /// `client_type` 0 — a bundle identifier, which is what survives the app being deleted.
        case bundle(String)
        /// `client_type` 1 — an absolute path to an executable.
        case path(String)

        init(client: String, clientType: Int) {
            // The type column decides, and a value we do not recognise falls back to the shape of
            // the string itself rather than to a guess.
            switch clientType {
            case 0:  self = .bundle(client)
            case 1:  self = .path(client)
            default: self = client.hasPrefix("/") ? .path(client) : .bundle(client)
            }
        }

        /// What goes in `Grant.bundleID`. For a path grant that is inside an app bundle, the
        /// bundle's own identifier where it can be read — otherwise the path, which is at least
        /// the identity the permission was actually granted to.
        var bundleID: String {
            switch self {
            case let .bundle(id):
                return id
            case let .path(path):
                let bundle = Resolver.bundle(containing: URL(filePath: path))
                if bundle.pathExtension == "app",
                   let id = Bundle(url: bundle)?.bundleIdentifier {
                    return id
                }
                return path
            }
        }

        var key: String {
            switch self {
            case let .bundle(id): "b:\(id)"
            case let .path(path): "p:\(path)"
            }
        }

        /// The last resort for a name, when nothing on disk can supply one.
        var fallbackName: String {
            switch self {
            case let .bundle(id): id
            case let .path(path): URL(filePath: path).lastPathComponent
            }
        }
    }

    /// Whether the thing holding a permission is on this Mac.
    enum Placement: Sendable, Hashable {
        case found(URL)
        /// Certainly gone. **This is the only value that raises concern 9.**
        case missing
        /// We could not find it and we cannot say it is gone. Never coloured.
        case uncertain

        /// `Grant.stillInstalled` is a `Bool`, so uncertainty has to fall one way. It falls towards
        /// "installed", because the other direction is an amber accusation built on not knowing.
        var stillInstalled: Bool { self != .missing }

        func name(for identity: Identity) -> String {
            guard case let .found(url) = self else { return identity.fallbackName }
            return GrantReader.displayName(of: url) ?? identity.fallbackName
        }
    }

    // MARK: - Location, the one that needs no permission

    /// **The only three keys this reader takes out of `clients.plist`.**
    ///
    /// ⚠️ The file also records, per app, when it last received a location. Printing that would
    /// make a section about who is watching you into a thing that watches you. This set is the
    /// enforcement — the parser reads nothing else, and a test holds the set.
    static let locationFieldsRead: Set<String> = ["Authorized", "BundleId", "BundlePath"]

    struct LocationScan: Sendable, Hashable {
        var grants: [Grant] = []
        /// Frameworks and daemons inside macOS. Counted, never listed as apps.
        var systemServices: Int = 0
    }

    /// Who holds Location.
    ///
    /// This is `-rw-r--r--` on every Mac, so it reads with no permission at all — which is exactly
    /// why it is *not* shown when Full Disk Access is refused. See the header.
    static func locationGrants(at url: URL, lookups: Lookups) -> LocationScan {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                     format: nil) as? [String: Any]
        else { return LocationScan() }

        return locationGrants(from: plist, lookups: lookups)
    }

    static func locationGrants(from plist: [String: Any], lookups: Lookups) -> LocationScan {
        var scan = LocationScan()

        for (_, value) in plist {
            guard let client = value as? [String: Any] else { continue }
            guard client[field: "Authorized"] as? Bool == true else { continue }

            let bundleID = client[field: "BundleId"] as? String
            let bundlePath = client[field: "BundlePath"] as? String

            // An entry with no bundle id, or one whose path is a framework rather than an app, is
            // a part of macOS. It is real and it is not something the person chose, so it is
            // counted and named as such rather than listed beside their apps or dropped in silence.
            guard let bundleID, let bundlePath, bundlePath.hasSuffix(".app") else {
                scan.systemServices += 1
                continue
            }

            let url = URL(filePath: bundlePath)
            let present = lookups.fileExists(url)

            scan.grants.append(Grant(
                appName: (present ? displayName(of: url) : nil) ?? bundleID,
                bundleID: bundleID,
                permission: .location,
                // ⚠️ The path in this file can point into a disk image or a container that is
                // simply not mounted today, which is not the same as an app being uninstalled. So
                // absence here is resolved the same reluctant way as everywhere else, through
                // LaunchServices, and only then believed.
                stillInstalled: present || lookups.applicationURL(bundleID) != nil,
                signature: .unknown,
                grantedAt: nil,
                isWellkept: false
            ))
        }
        return scan
    }

    // MARK: - Reading one database

    /// One raw row of `access`, before anything has been decided about it.
    struct RawRow: Sendable, Hashable {
        let service: String
        let client: String
        let clientType: Int
        /// 2 is allowed and 3 is allowed-but-limited; 0 is denied and 1 is undecided.
        let authValue: Int
        /// The code requirement the grant was made against — Apple's `csreq` blob. `nil` on rows
        /// macOS wrote without one, which is ordinary.
        let requirement: Data?
        let lastModified: Date?

        /// ⚠️ A *denied* entry is not a grant and must never be listed as one. "Photos said no to
        /// Slack" appearing under "apps that hold Photos" would be the worst kind of wrong: true in
        /// the database and backwards on the screen.
        var isAllowed: Bool { authValue >= 2 }
    }

    /// What came back from one store.
    struct DatabaseScan: Sendable, Hashable {
        enum Outcome: Sendable, Hashable {
            case unopenable
            case unrecognisedSchema
            case read
        }
        let outcome: Outcome
        let rows: [RawRow]

        var wasUnderstood: Bool { outcome == .read }
        var wasUnopenable: Bool { outcome == .unopenable }
    }

    /// Open one `TCC.db`, prove its schema, and read the rows.
    ///
    /// Read-only, always, and by two mechanisms: `SQLITE_OPEN_READONLY`, and never issuing a
    /// statement that is not a `SELECT` or a `PRAGMA`. This app does not write to Apple's private
    /// stores, and a bug that made it try should fail rather than succeed.
    static func scan(_ url: URL) -> DatabaseScan {
        guard let database = open(url) else { return DatabaseScan(outcome: .unopenable, rows: []) }
        defer { sqlite3_close(database) }

        let columns = Set(columnNames(of: database))

        // ⚠️ The macOS 27 guard. We ask the database what it is rather than assuming, and a shape
        // we do not know produces a row that says so.
        guard columns.contains("service"), columns.contains("client"),
              columns.contains("client_type"),
              columns.contains("auth_value") || columns.contains("allowed")
        else { return DatabaseScan(outcome: .unrecognisedSchema, rows: []) }

        // Built from the columns that are actually there, so a store that has dropped `csreq` or
        // renamed `last_modified` still yields the four columns that matter instead of failing
        // whole.
        var selected = ["service", "client", "client_type"]
        selected.append(columns.contains("auth_value") ? "auth_value" : "allowed")
        let hasRequirement = columns.contains("csreq")
        let hasModified = columns.contains("last_modified")
        if hasRequirement { selected.append("csreq") }
        if hasModified { selected.append("last_modified") }

        var statement: OpaquePointer?
        let sql = "SELECT \(selected.joined(separator: ", ")) FROM access"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return DatabaseScan(outcome: .unrecognisedSchema, rows: []) }
        defer { sqlite3_finalize(statement) }

        var rows: [RawRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let service = text(statement, 0), let client = text(statement, 1) else { continue }

            var index: Int32 = 4
            var requirement: Data?
            if hasRequirement {
                requirement = blob(statement, index)
                index += 1
            }
            var modified: Date?
            if hasModified {
                let seconds = sqlite3_column_int64(statement, index)
                if seconds > 0 { modified = Date(timeIntervalSince1970: TimeInterval(seconds)) }
            }

            rows.append(RawRow(service: service,
                               client: client,
                               clientType: Int(sqlite3_column_int(statement, 2)),
                               authValue: Int(sqlite3_column_int(statement, 3)),
                               requirement: requirement,
                               lastModified: modified))
        }

        return DatabaseScan(outcome: .read, rows: rows)
    }

    /// Open read-only, with one retry.
    ///
    /// The retry is not superstition. A SQLite database in write-ahead-logging mode needs its
    /// `-shm` sidecar, and a reader who cannot write beside the file is refused the open entirely —
    /// so a store that switched journal modes in a macOS update would take this row from "here is
    /// your list" to "could not open" with nothing actually wrong. `immutable=1` says: treat this
    /// as a fixed file, do not go looking for a journal. It is only reached when the ordinary open
    /// has already failed.
    private static func open(_ url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            return database
        }
        sqlite3_close(database)
        database = nil

        let uri = url.absoluteString + "?immutable=1"
        if sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK {
            return database
        }
        sqlite3_close(database)
        return nil
    }

    /// The columns of `access`, or an empty list where there is no such table.
    private static func columnNames(of database: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(access)", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return [] }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, 1) { names.append(name) }
        }
        return names
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: raw)
    }

    private static func blob(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let raw = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: raw, count: count)
    }

    // MARK: - Asking the rest of the machine

    /// Where LaunchServices thinks this app is.
    ///
    /// `NSWorkspace` rather than the deprecated `LSCopyApplicationURLsForBundleIdentifier`, and it
    /// is safe off the main actor: nothing here touches the window server.
    static func registeredApplication(for bundleID: String) -> URL? {
        guard !bundleID.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// ⚠️ **Whether this app is still the app the permission was granted to.**
    ///
    /// `csreq` is the code requirement macOS recorded at the moment of the grant. Checking the app
    /// on disk against that requirement is the honest form of the question, and it is the only
    /// route to concern 8.
    ///
    /// Two deliberate choices:
    ///
    /// - **Resources are not hashed.** `kSecCSDoNotValidateResources` skips walking every file in
    ///   the bundle. The question is one of identity — is this the same signer, the same
    ///   identifier — not whether a help file was edited. Hashing a browser's entire bundle for
    ///   each of five permissions would make this the slowest thing in the app by a wide margin.
    /// - **Only `errSecCSReqFailed` means changed.** That is the system stating that the code does
    ///   not satisfy the requirement. Everything else — unreadable, unsigned, revoked, a resource
    ///   error, an app on an unmounted volume — is `.unknown`. An unchecked app is not an accused
    ///   one, and this is the concern where being wrong costs somebody an afternoon.
    static func standing(of appURL: URL, against requirement: Data) -> SignatureStanding {
        var parsed: SecRequirement?
        guard SecRequirementCreateWithData(requirement as CFData, [], &parsed) == errSecSuccess,
              let parsed
        else { return .unknown }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess,
              let code
        else { return .unknown }

        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        switch SecStaticCodeCheckValidity(code, flags, parsed) {
        case errSecSuccess:     return .matches
        case errSecCSReqFailed: return .changed
        default:                return .unknown
        }
    }

    /// What the app calls itself, from its own bundle. `nil` where nothing readable says.
    static func displayName(of url: URL) -> String? {
        if let bundle = Bundle(url: url),
           let info = bundle.infoDictionary {
            if let name = info["CFBundleDisplayName"] as? String, !name.isEmpty { return name }
            if let name = info["CFBundleName"] as? String, !name.isEmpty { return name }
        }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? nil : stem
    }
}

// MARK: - Small helpers

private extension Dictionary where Key == String, Value == Any {
    /// ⚠️ Reads a location field **only if it is one of the three we are allowed to read**. The
    /// restriction is here, at the single point of access, rather than in a comment above the
    /// parser — see `GrantReader.locationFieldsRead`.
    subscript(field name: String) -> Any? {
        GrantReader.locationFieldsRead.contains(name) ? self[name] : nil
    }
}

private extension WellkeptCore.Permission {
    /// Position in `allCases`, so the Options breakdown is drawn in the vocabulary's order rather
    /// than in whatever order the database happened to return.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
