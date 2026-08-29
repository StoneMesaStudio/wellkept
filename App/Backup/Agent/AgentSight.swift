// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  AgentSight.swift
//  Wellkept — App/Backup/Agent
//
//  ⭐⛔ **THE LOAD-BEARING UNKNOWN, settled at run time instead of guessed at.**
//
//  ## The question, and why it is the dangerous one
//
//  Nobody has established whether an `SMAppService.agent` inherits the app's Full Disk Access. If
//  it does not, then every backup the background piece makes on a schedule contains **no mail, no
//  messages, no photos, no contacts, no Safari data and no Trash** — not a short version of them,
//  *none of them* — and **macOS reports no error whatsoever.** The run finishes. It says it worked.
//  The person would find out on the one day it mattered.
//
//  So this file does not assume either answer. It is a check the background piece runs **on itself,
//  in its own process, before it copies a single file**, and it refuses and says so when it cannot
//  see what the app can see.
//
//  ## ⚠️ Why "did the call return an error" is exactly the wrong test
//
//  The refusal is silent. Ask an unreadable protected folder for its contents and macOS hands back
//  an **empty listing and no error** — which is indistinguishable from a folder that is genuinely
//  empty. A check written the obvious way would report success on a Mac it could not see at all.
//
//  Hence two kinds of probe, and a third answer:
//
//  - **`readAByte`** — open a file that must be there and read one byte. Unambiguous: success is
//    proof of sight, failure is proof of refusal.
//  - **`listAndExpectContents`** — for places with no single reliable file. A non-empty listing is
//    proof; an **empty** listing proves nothing, and is reported as `.cannotTell` rather than
//    guessed at in either direction.
//
//  ⭐ `.cannotTell` is the point of the whole design. An empty Trash and a Trash macOS is hiding
//  look identical, and the honest answer is to say so.
//
//  ## How the comparison works
//
//  The app records what **it** could see, on the same Mac, with the same probes. The background
//  piece records what **it** could see. The verdict is the difference: a place the app read and the
//  agent did not is the failure this file exists to catch.
//
//  ⛔ **A good verdict is evidence for a human, not permission for the app.** It does not open
//  `RehearsalGate`, and it cannot: `RehearsalGate.agentHoldsFullDiskAccess` is a constant somebody
//  types after watching this happen. Code that could clear its own safety check is not a safety
//  check.

// MARK: - One probe, and what it found

/// What a single look at a protected place established.
///
/// ⚠️ **Named `PlaceReading` and not `Reading`, and it has to stay that way.**
/// `WellkeptCore.Reading` is the Hardware section's row type. A bare `Reading` declared at the top
/// level of the app module shadows it, and takes `HardwareModel` and `ReadingHistory` down with a
/// wall of errors that name neither this file nor the real cause.
enum PlaceReading: String, Codable, Sendable, Hashable, CaseIterable {

    /// Read real bytes, or listed real contents. Sight, demonstrated.
    case saw

    /// The thing is there and macOS would not let us have it.
    case refused

    /// There is nothing here to read on this Mac — no Mail account, an empty Trash's parent, no
    /// photo library. **Not a failure**, and never counted as one.
    case notThere

    /// ⚠️ **The honest third answer.** An empty listing from a place that may legitimately be
    /// empty. It is never treated as sight, and never treated as refusal.
    case cannotTell

    var label: String {
        switch self {
        case .saw:        "Could read it"
        case .refused:    "Was refused"
        case .notThere:   "Nothing there to read"
        case .cannotTell: "Could not tell"
        }
    }
}

/// What was looked at, and what came back.
struct Sighting: Codable, Sendable, Hashable, Identifiable {
    let place: ProtectedPlace
    /// The path actually probed, so a record from six months ago can be checked by hand.
    let path: String
    let reading: PlaceReading

    var id: String { place.rawValue }

    /// The line for the record and for Options.
    var sentence: String { "\(place.label): \(reading.label)." }
}

// MARK: - ⭐ What one process could see

/// Which half of Wellkept took the reading. Both use the same probes; the whole method is
/// comparing one to the other.
enum Watcher: String, Codable, Sendable, Hashable {
    case theApp
    case theBackgroundPiece

    var label: String {
        switch self {
        case .theApp:              "Wellkept's window"
        case .theBackgroundPiece:  "The background piece"
        }
    }
}

/// **One process's demonstrated sight of the six protected places.**
struct AgentSight: Codable, Sendable, Hashable {

    let takenBy: Watcher
    let takenOn: Date

    /// The executable that took it. ⚠️ Recorded because the whole argument for running the
    /// background piece out of the app's own binary is that it is the *same* executable — and a
    /// record that does not say which binary it was is a record that cannot check that claim.
    let executablePath: String

    /// What the app's own Full Disk Access probe said in this process. A second, independent
    /// signal: `FullDiskAccess.isGranted` reads the privacy databases, the sightings below read the
    /// things a person would actually miss.
    let fullDiskAccessProbe: Bool

    let sightings: [Sighting]

    // MARK: What it adds up to

    var placesSeen: Set<ProtectedPlace> {
        Set(sightings.filter { $0.reading == .saw }.map(\.place))
    }

    var placesRefused: Set<ProtectedPlace> {
        Set(sightings.filter { $0.reading == .refused }.map(\.place))
    }

    var placesUnclear: Set<ProtectedPlace> {
        Set(sightings.filter { $0.reading == .cannotTell }.map(\.place))
    }

    var detailPairs: [DetailPair] {
        [DetailPair("Taken by", takenBy.label),
         DetailPair("Taken", takenOn.formatted(date: .abbreviated, time: .shortened)),
         DetailPair("Executable", executablePath),
         DetailPair("Full Disk Access probe", fullDiskAccessProbe ? "Read a protected file" : "Refused")]
        + sightings.map { DetailPair($0.place.label, $0.reading.label) }
    }

    // MARK: ── Taking one ────────────────────────────────────────────────────────────────────────

    /// Look at all six places and report what came back.
    ///
    /// ⚠️ Reads one byte at most, and lists at most one directory level. It opens nothing it does
    /// not close and writes nothing anywhere.
    static func take(as watcher: Watcher,
                     home: URL = StorageManifest.home(),
                     fileManager: FileManager = .default) -> AgentSight {
        AgentSight(
            takenBy: watcher,
            takenOn: Date(),
            executablePath: Bundle.main.executableURL?.path(percentEncoded: false)
                ?? CommandLine.arguments.first ?? "unknown",
            fullDiskAccessProbe: FullDiskAccess.isGranted,
            sightings: ProtectedPlace.allCases.map {
                Sighting(place: $0,
                         path: Self.probe(for: $0, home: home, fileManager: fileManager)?.url
                             .path(percentEncoded: false) ?? "—",
                         reading: Self.read($0, home: home, fileManager: fileManager))
            })
    }

    // MARK: ── The probes ────────────────────────────────────────────────────────────────────────

    /// How one place is looked at.
    struct Probe: Sendable, Hashable {
        enum Kind: Sendable, Hashable {
            /// Open it and read one byte. Unambiguous in both directions.
            case readAByte
            /// List it. Non-empty proves sight; **empty proves nothing.**
            case listAndExpectContents
        }
        let kind: Kind
        let url: URL
    }

    /// The candidates for each place, strongest first. The first one that exists is used.
    ///
    /// ⚠️ **Nothing here reaches into `~/Library/Containers` or a Group Container.** Those are other
    /// apps' data and touching them raises a privacy dialog with Wellkept's name on it — see
    /// `ContainerGuardTests`. Every path below is either the person's own Library or their own home.
    static func candidates(for place: ProtectedPlace, home: URL) -> [Probe] {
        switch place {
        case .mail:
            // No single file is guaranteed — the folder is versioned (`V10`, `V11`, …) and the
            // message stores below it are named per account. So the folder, listed.
            [Probe(kind: .listAndExpectContents, url: home.appending(path: "Library/Mail"))]
        case .messages:
            [Probe(kind: .readAByte, url: home.appending(path: "Library/Messages/chat.db")),
             Probe(kind: .listAndExpectContents, url: home.appending(path: "Library/Messages"))]
        case .photos:
            photoLibraries(home: home).map {
                Probe(kind: .readAByte, url: $0.appending(path: "database/Photos.sqlite"))
            }
            + [Probe(kind: .listAndExpectContents, url: home.appending(path: "Pictures"))]
        case .contacts:
            [Probe(kind: .listAndExpectContents,
                   url: home.appending(path: "Library/Application Support/AddressBook"))]
        case .safari:
            [Probe(kind: .readAByte, url: home.appending(path: "Library/Safari/Bookmarks.plist")),
             Probe(kind: .listAndExpectContents, url: home.appending(path: "Library/Safari"))]
        case .trash:
            // ⚠️ The one place where `.cannotTell` is the ordinary answer rather than the odd one:
            // a Mac with an empty Trash and a Mac hiding its Trash from us look identical.
            [Probe(kind: .listAndExpectContents, url: home.appending(path: ".Trash"))]
        }
    }

    /// The photo libraries in `~/Pictures`. Listing `~/Pictures` needs no grant; opening what is
    /// inside one does.
    private static func photoLibraries(home: URL, fileManager: FileManager = .default) -> [URL] {
        let pictures = home.appending(path: "Pictures")
        let names = (try? fileManager.contentsOfDirectory(atPath: pictures.path)) ?? []
        return names.filter { $0.hasSuffix(".photoslibrary") }.sorted()
            .map { pictures.appending(path: $0) }
    }

    /// The probe that will actually be used — the first candidate that is there at all.
    static func probe(for place: ProtectedPlace,
                      home: URL,
                      fileManager: FileManager = .default) -> Probe? {
        candidates(for: place, home: home)
            .first { fileManager.fileExists(atPath: $0.url.path) }
    }

    /// ⭐ Look at one place and answer honestly, including "I could not tell".
    static func read(_ place: ProtectedPlace,
                     home: URL,
                     fileManager: FileManager = .default) -> PlaceReading {
        guard let probe = probe(for: place, home: home, fileManager: fileManager) else {
            return .notThere
        }
        switch probe.kind {
        case .readAByte:
            // Opening can succeed where reading does not, so take a byte before believing it —
            // the same rule `FullDiskAccess.canRead` follows, for the same reason.
            guard let handle = try? FileHandle(forReadingFrom: probe.url) else { return .refused }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: 1)) != nil ? .saw : .refused
        case .listAndExpectContents:
            guard let contents = try? fileManager.contentsOfDirectory(atPath: probe.url.path) else {
                return .refused
            }
            // ⚠️ Here is the silent refusal: an empty array, no error, and no way to tell it from
            // an empty folder. Anything that resolved this to a yes or a no would be inventing it.
            return contents.isEmpty ? .cannotTell : .saw
        }
    }
}

// MARK: - ⭐ The verdict

/// **Whether the background piece may be believed about what it copied.**
///
/// ⛔ Only `.sawEverythingTheAppSaw` permits a copy, and even then only if `RehearsalGate` grants a
/// pass — which today it does not, and will not until a human has written down that they watched
/// this happen.
enum AgentVerdict: Sendable, Hashable {

    /// Every place the app could read, the background piece could read too.
    case sawEverythingTheAppSaw

    /// ⛔ **The failure this file exists to catch.** The app read these and the background piece
    /// did not, which means a scheduled backup would silently contain none of them.
    case blind(missing: [ProtectedPlace])

    /// The app has never recorded what it could see, so there is nothing to compare against.
    /// Not a failure and not a pass — an absence.
    case nothingToCompareWith

    /// The comparison came out even, but on places where one side could not tell. Honest, and not
    /// good enough to copy on.
    case inconclusive(unclear: [ProtectedPlace])

    /// ⭐ **The only case that is a yes.**
    var isProof: Bool { self == .sawEverythingTheAppSaw }

    /// What it says, in a sentence somebody can act on.
    var sentence: String {
        switch self {
        case .sawEverythingTheAppSaw:
            return "The background piece could read everything Wellkept's window could read."
        case .blind(let missing):
            let names = missing.map(\.label).formatted(.list(type: .and))
            return "The background piece could not read \(names), and Wellkept's window could. "
                + "A backup it made on a schedule would contain none of that, and macOS would "
                + "report no error. It will not copy anything."
        case .nothingToCompareWith:
            return "Wellkept has not yet recorded what its own window can read, so there is "
                + "nothing to compare the background piece against."
        case .inconclusive(let unclear):
            let names = unclear.map(\.label).formatted(.list(type: .and))
            return "It could not be established whether the background piece can read \(names). "
                + "An empty folder and a folder macOS is hiding look the same, so this is not "
                + "being called a pass."
        }
    }

    /// ⭐ **Compare the two readings.** The app's sighting is the yardstick, because the app is the
    /// half whose grant a person actually gave.
    static func compare(app: AgentSight?, agent: AgentSight) -> AgentVerdict {
        guard let app else { return .nothingToCompareWith }

        let missing = app.placesSeen.subtracting(agent.placesSeen).sorted { $0.rawValue < $1.rawValue }
        if !missing.isEmpty { return .blind(missing: missing) }

        // ⚠️ A place the app saw and the agent could only shrug at is already caught above, because
        // `.cannotTell` is not in `placesSeen`. What is left is the case where NEITHER of them saw
        // anything worth comparing — every place unclear or absent. That is not proof of sight.
        if app.placesSeen.isEmpty {
            let unclear = (app.placesUnclear.union(agent.placesUnclear))
                .sorted { $0.rawValue < $1.rawValue }
            return unclear.isEmpty
                ? .nothingToCompareWith
                : .inconclusive(unclear: unclear)
        }
        return .sawEverythingTheAppSaw
    }
}
