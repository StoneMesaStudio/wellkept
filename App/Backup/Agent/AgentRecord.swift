// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  AgentRecord.swift
//  Wellkept — App/Backup/Agent
//
//  ⭐ **What the background piece found, written down where a person can read it.**
//
//  John's condition was that the code establish at run time whether the background piece inherits
//  Full Disk Access **and record what it found**. This is the record. It holds three things:
//
//  1. What **the app** could see, taken when the window was open.
//  2. What **the background piece** could see, taken in its own process with the window closed.
//  3. A short dated list of what it actually did, in plain sentences — including every time it
//     refused, and why.
//
//  ## ⚠️ This is the evidence a human uses to open the gate, and it is not the gate
//
//  Nothing here can grant anything. `RehearsalGate.agentHoldsFullDiskAccess` is a constant somebody
//  types after reading this file and believing it. Code that could clear its own safety check is
//  not a safety check — see `RehearsalGate.swift`, which holds the only `Pass` initialiser in the
//  app and keeps it `fileprivate`.
//
//  ## What this file writes, and what it never writes
//
//  It writes one small JSON file in Wellkept's own folder — **Wellkept's bookkeeping, never a
//  person's files.** The copier that writes somebody's documents to a drive lives elsewhere and
//  takes a `RehearsalGate.Pass` it cannot manufacture.
//
//  Two processes can write this file, and they do not coordinate. That is deliberate: a lock
//  between an app and its login item is a way for one of them to hang, and the cost of losing this
//  race is one lost diagnostic line. Each write is atomic, so a crash mid-write leaves the previous
//  record whole rather than half a file.

struct AgentRecord: Codable, Sendable, Hashable {

    /// What Wellkept's own window could see, last time it looked.
    var app: AgentSight?

    /// What the background piece could see, last time it woke up.
    var backgroundPiece: AgentSight?

    /// What it did, newest last. Capped — see `keepAtMost`.
    var runs: [Run] = []

    /// ⭐ When a backup — Time Machine's or Wellkept's — last actually worked.
    ///
    /// ⚠️ **Written by whichever half of the app last read it, and read by the background piece.**
    /// This is the seam that lets the third job work without the login item having to know how to
    /// read Time Machine: the window looks, records the date here, and the background piece does
    /// the arithmetic. A background piece that had its own reader would be a second answer about
    /// one Mac.
    var lastSuccessfulBackup: Date?

    /// When the background piece last began a run. `nil` if it never has. The hourly schedule is
    /// measured from this and not from the last *success*, so a run that fails does not put the
    /// Mac into a loop of retries.
    var lastRunStarted: Date?

    /// One dated line. The words are what a person reads; there is no code in here.
    struct Run: Codable, Sendable, Hashable, Identifiable {
        let happenedOn: Date
        let what: String
        var id: Date { happenedOn }

        var sentence: String {
            "\(happenedOn.formatted(date: .abbreviated, time: .shortened)) — \(what)"
        }
    }

    // MARK: ── ⚠️ Lenient decoding, on purpose ───────────────────────────────────────────────────

    /// A record written by an older build is missing keys a newer one expects, and Swift's own
    /// decoder treats a missing non-optional key as a failure. That would make this whole file
    /// unreadable after an update — so the background piece would lose the app's sighting, and the
    /// comparison that is the entire point of the record would quietly stop happening. Every field
    /// is read as "if it is there", and absence is the empty answer.
    init(app: AgentSight? = nil,
         backgroundPiece: AgentSight? = nil,
         runs: [Run] = [],
         lastSuccessfulBackup: Date? = nil,
         lastRunStarted: Date? = nil) {
        self.app = app
        self.backgroundPiece = backgroundPiece
        self.runs = runs
        self.lastSuccessfulBackup = lastSuccessfulBackup
        self.lastRunStarted = lastRunStarted
    }

    init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        app = try box.decodeIfPresent(AgentSight.self, forKey: .app)
        backgroundPiece = try box.decodeIfPresent(AgentSight.self, forKey: .backgroundPiece)
        runs = try box.decodeIfPresent([Run].self, forKey: .runs) ?? []
        lastSuccessfulBackup = try box.decodeIfPresent(Date.self, forKey: .lastSuccessfulBackup)
        lastRunStarted = try box.decodeIfPresent(Date.self, forKey: .lastRunStarted)
    }

    /// ⚠️ A log with no ceiling is a file that grows for years in somebody's Library. Fifty lines
    /// is a few weeks of an hourly job's interesting moments, and the uninstaller declares the file
    /// either way.
    static let keepAtMost = 50

    // MARK: ── What it adds up to ────────────────────────────────────────────────────────────────

    /// ⭐ The comparison, from whatever has been recorded so far.
    var verdict: AgentVerdict {
        guard let backgroundPiece else { return .nothingToCompareWith }
        return AgentVerdict.compare(app: app, agent: backgroundPiece)
    }

    /// Whether the record contains the evidence a human would need to fill in
    /// `RehearsalGate.agentHoldsFullDiskAccess`.
    ///
    /// ⛔ **Whether the evidence exists, not whether it has been accepted.** The gate stays shut
    /// until a person writes in it.
    var holdsTheEvidence: Bool { verdict.isProof }

    /// The sentence to put in `RehearsalGate.Proof.how`, ready to copy, so the person recording it
    /// writes down what actually happened rather than a summary of it.
    var proofSentence: String? {
        guard let backgroundPiece, holdsTheEvidence else { return nil }
        let places = backgroundPiece.placesSeen.map(\.label).sorted().formatted(.list(type: .and))
        return "The background piece ran as \(backgroundPiece.executablePath) on "
            + "\(backgroundPiece.takenOn.formatted(date: .abbreviated, time: .shortened)) and read "
            + "\(places) — everything Wellkept's own window could read."
    }

    var detailPairs: [DetailPair] {
        [DetailPair("What the background piece found", verdict.sentence)]
        + (backgroundPiece?.detailPairs ?? [DetailPair("The background piece", "Has not run yet")])
    }

    // MARK: ── Reading and writing ───────────────────────────────────────────────────────────────

    /// Read the record. A missing or unreadable file is an empty record, never an error: this is a
    /// diagnostic, and a background piece that refused to start because its own log would not parse
    /// would be a worse thing than the log.
    static func read(at url: URL = StorageManifest.backgroundPieceRecord()) -> AgentRecord {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder.wellkept.decode(AgentRecord.self, from: data)
        else { return AgentRecord() }
        return record
    }

    /// Write it, atomically, in Wellkept's own folder.
    ///
    /// ⚠️ `RehearsalGate` is deliberately named here so nobody has to wonder: **this write is not
    /// gated and does not need to be.** The gate protects writes to somebody's drive; this is a
    /// 2 KB JSON file in `~/Library/Application Support/Wellkept`, and refusing to write it would
    /// remove the only record of why the background piece refused.
    @discardableResult
    func write(to url: URL = StorageManifest.backgroundPieceRecord()) -> Bool {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.wellkeptPretty.encode(self) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: ── Adding to it ──────────────────────────────────────────────────────────────────────

    /// Record a sighting, replacing whatever that half of the app last reported.
    mutating func noted(_ sight: AgentSight) {
        switch sight.takenBy {
        case .theApp:             app = sight
        case .theBackgroundPiece: backgroundPiece = sight
        }
    }

    /// Record one plain line about what happened, oldest dropped past the ceiling.
    mutating func noted(_ what: String, on date: Date = Date()) {
        runs.append(Run(happenedOn: date, what: what))
        if runs.count > Self.keepAtMost { runs.removeFirst(runs.count - Self.keepAtMost) }
    }

    /// ⭐ Take a sighting for this process, file it, and write the record — the whole job in one
    /// call, so neither half of the app can do half of it.
    @discardableResult
    static func recordSight(as watcher: Watcher,
                            saying what: String? = nil,
                            home: URL = StorageManifest.home(),
                            at url: URL = StorageManifest.backgroundPieceRecord()) -> AgentRecord {
        var record = read(at: url)
        record.noted(AgentSight.take(as: watcher, home: home))
        if let what { record.noted(what) }
        record.write(to: url)
        return record
    }
}

// MARK: - The coders

/// ISO dates, so a record written by the app and a record written by the background piece can be
/// read by either — and by a person with a text editor, which is the point of a diagnostic.
extension JSONDecoder {
    static var wellkept: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var wellkeptPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
