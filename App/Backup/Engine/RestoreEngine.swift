// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  RestoreEngine.swift
//  Wellkept — App/Backup/Engine
//
//  ⭐ **Getting files back: one file, a folder, or everything as it stood on a chosen day.**
//
//  ## ⚠️ A restore nobody has tested is not a restore
//
//  That sentence is the reason `RehearsalGate` exists, and it applies to this file more literally
//  than to any other. **Every entry point here asks the gate**, and the gate says no today, because
//  `RehearsalGate.performed` is `nil` and nobody has erased a drive and restored from it with this
//  code. The engine is built so the rehearsal is possible at all; it is not offered until the
//  rehearsal has been walked.
//
//  ⛔ **This is a file-level restore and it is never described as anything more.** Migration
//  Assistant accepting a data-only volume is **unverified**, with Apple's own string arguing against
//  it — *"Volume does not contain an installation of macOS or OS X."* — and a whole-Mac copy is
//  impossible unprivileged. What this does is put your files back where they were, or somewhere you
//  choose. It does not reinstall macOS and it is never `Backup.promiseWeDoNotMake`.
//
//  ## Three ways to ask for something back
//
//  1. **By name.** Search the backup for "invoice", get every copy of everything called that, with
//     its date. This is what people actually do.
//  2. **One file, as it stood on a day.** A document you changed and want the previous version of.
//     `versionAsOf` answers it out of the drive's own record.
//  3. **Everything, as it stood on a day.** The whole home folder as of a chosen run.
//
//  ## ⛔ Never over the top of something. Not once, not with a warning, not with a checkbox.
//
//  This is `Quarantine.restore`'s rule and it is the same rule for the same reason: between the
//  backup and the restore, the person may have re-saved the document or re-downloaded the
//  installer. Writing over it destroys the newer one — and they asked for the opposite of that.
//  `copyfile` is given `COPYFILE_EXCL`, so an occupied path comes back `EEXIST` and is reported as a
//  refusal with the path named. The person decides: put it somewhere else, or move the newer one out
//  of the way themselves.
//
//  ## What comes back with the file
//
//  The same four repairs `CopyOne` makes on the way out are made on the way in, because it is the
//  same function — there is deliberately no second copier in this engine. So a restored file has its
//  creation date, its download provenance, its sparseness and its hard links, rather than claiming
//  to have been created on the day of the restore.

// MARK: - What is in the backup

/// One thing that can be asked for back.
struct RestorableItem: Sendable, Equatable, Hashable, Identifiable {

    /// Where it lives in the home folder.
    let relativePath: String

    /// Where the copy is on the drive, relative to the backup folder.
    let onTheDriveAt: String

    /// When this copy stopped being the current one. `nil` means it is the current copy.
    let supersededOn: Date?

    /// Whether the file is gone from the Mac altogether, as opposed to having simply changed.
    let theFileIsGoneFromTheMac: Bool

    let bytes: Int64

    var id: String { onTheDriveAt }
    var name: String { (relativePath as NSString).lastPathComponent }
    var isTheCurrentCopy: Bool { supersededOn == nil }

    /// The line on the row. ⚠️ Dates, because a list of five copies of "Invoice.pdf" with no dates
    /// is a list a person cannot use.
    var sentence: String {
        guard let supersededOn else {
            return "The copy in your most recent backup."
        }
        let when = supersededOn.formatted(date: .abbreviated, time: .shortened)
        return theFileIsGoneFromTheMac
            ? "Kept from \(when), when this file was no longer on your Mac."
            : "The copy as it was until \(when)."
    }
}

// MARK: - Finding things

/// ⭐ **Search the drive.** Reads only — nothing here writes anything anywhere.
enum RestoreCatalogue {

    /// Everything in the backup that a person could ask for: the current copy of every file, plus
    /// every older copy that was kept.
    ///
    /// - Parameter mountPoint: the drive.
    static func everything(onDrive mountPoint: String) -> [RestorableItem] {
        current(onDrive: mountPoint) + older(onDrive: mountPoint)
    }

    /// The current copy of everything, walked off the drive itself rather than out of the record.
    ///
    /// ⚠️ **The drive is the truth, not the record.** A record that has drifted from the files on
    /// the drive would hide something that is really there, and a person searching for a file they
    /// can see in the Finder and being told it is not in the backup would be right to distrust the
    /// whole thing.
    static func current(onDrive mountPoint: String) -> [RestorableItem] {
        let root = BackupCatalogue.files(onDrive: mountPoint)
        let base = root.path(percentEncoded: false)
        guard let walker = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: [.isRegularFileKey,
                                                                                       .totalFileAllocatedSizeKey])
        else { return [] }

        var found: [RestorableItem] = []
        for case let url as URL in walker {
            let path = url.path(percentEncoded: false)
            guard path.count > base.count + 1 else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey,
                                                           .totalFileAllocatedSizeKey])
            guard values?.isRegularFile == true else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            found.append(RestorableItem(relativePath: relative,
                                        onTheDriveAt: BackupCatalogue.filesFolderName + "/" + relative,
                                        supersededOn: nil,
                                        theFileIsGoneFromTheMac: false,
                                        bytes: Int64(values?.totalFileAllocatedSize ?? 0)))
        }
        return found
    }

    /// Every older copy, out of the drive's own record.
    static func older(onDrive mountPoint: String) -> [RestorableItem] {
        BackupCatalogue.keptVersions(onDrive: mountPoint).map {
            RestorableItem(relativePath: $0.relativePath,
                           onTheDriveAt: $0.keptAt,
                           supersededOn: $0.supersededOn,
                           theFileIsGoneFromTheMac: $0.theFileIsGoneFromTheMac,
                           bytes: $0.bytes)
        }
    }

    /// ⭐ **Search by name.** What people actually do.
    ///
    /// Case- and diacritic-insensitive, matched against the whole path so "Documents/2025" works as
    /// well as "invoice". Newest first, and the current copy of a file always comes before its older
    /// ones.
    static func search(_ text: String, in items: [RestorableItem]) -> [RestorableItem] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return items
            .filter { $0.relativePath.localizedStandardContains(needle) }
            .sorted { left, right in
                if left.relativePath != right.relativePath { return left.relativePath < right.relativePath }
                // The current copy first, then the older ones newest first.
                switch (left.supersededOn, right.supersededOn) {
                case (nil, _):                    return true
                case (_, nil):                    return false
                case (let a?, let b?):            return a > b
                }
            }
    }

    /// ⭐ **What one file looked like on a given day.**
    ///
    /// The copy that was current at that moment is the oldest kept copy that was superseded *after*
    /// it; if nothing was superseded after it, the current copy is the answer.
    static func versionAsOf(_ when: Date,
                            of relativePath: String,
                            in items: [RestorableItem]) -> RestorableItem? {
        let mine = items.filter { $0.relativePath == relativePath }
        let superseded = mine
            .compactMap { item -> (Date, RestorableItem)? in
                guard let date = item.supersededOn, date > when else { return nil }
                return (date, item)
            }
            .sorted { $0.0 < $1.0 }
        if let first = superseded.first { return first.1 }
        return mine.first { $0.isTheCurrentCopy }
    }

    /// ⭐ **The whole home folder as it stood on a day** — one entry per path.
    static func everythingAsOf(_ when: Date, in items: [RestorableItem]) -> [RestorableItem] {
        let paths = Set(items.map(\.relativePath))
        return paths.compactMap { versionAsOf(when, of: $0, in: items) }
            .sorted { $0.relativePath < $1.relativePath }
    }

    /// The days a person can choose between: the runs the drive has a record of.
    static func pointsInTime(onDrive mountPoint: String) -> [Date] {
        BackupCatalogue.runs(onDrive: mountPoint).map(\.finishedOn)
    }
}

// MARK: - Putting things back

/// What happened to one restored item.
struct RestoreOutcome: Sendable, Equatable {

    let item: RestorableItem

    /// Where it went. `nil` when it did not go anywhere.
    let landedAt: String?

    /// Why it did not. `nil` when it did.
    let refusal: RestoreRefusal?

    var restored: Bool { landedAt != nil }
}

/// Why one item could not be put back.
enum RestoreRefusal: Sendable, Equatable, Hashable {

    /// ⛔ Something is already at the destination. **Never overwritten.**
    case somethingIsAlreadyThere(path: String)

    /// The copy is not on the drive any more.
    case itIsNotOnTheDrive(path: String)

    /// The drive is not plugged in.
    case theDriveIsNotConnected(name: String)

    /// The folder it came out of could not be made again.
    case theFolderCouldNotBeMade(why: String)

    /// The copy itself failed.
    case itCouldNotBeCopied(why: String)

    var sentence: String {
        switch self {
        case .somethingIsAlreadyThere(let path):
            "There is already a file at \(path). Wellkept will not write over it — it may be newer "
            + "than the one in the backup. Move it out of the way, or restore to somewhere else."
        case .itIsNotOnTheDrive(let path):
            "That copy is not on the drive any more (\(path))."
        case .theDriveIsNotConnected(let name):
            "\(name) is not connected. Plug it in and try again."
        case .theFolderCouldNotBeMade(let why):
            "The folder this file came out of could not be made again: \(why)."
        case .itCouldNotBeCopied(let why):
            "It could not be copied back: \(why)."
        }
    }
}

/// What a whole restore did.
struct RestoreReport: Sendable {
    let outcomes: [RestoreOutcome]

    var restored: [RestoreOutcome] { outcomes.filter(\.restored) }
    var refused: [RestoreOutcome] { outcomes.filter { !$0.restored } }

    /// ⚠️ Never a claim about anything that did not land. A count of what came back, and a count of
    /// what did not, is the honest shape.
    var sentence: String {
        let back = restored.count
        guard back > 0 else {
            return refused.count == 1
                ? (refused[0].refusal?.sentence ?? "Nothing was put back.")
                : "Nothing was put back."
        }
        let items = back == 1 ? "1 file" : "\(back.formatted()) files"
        var line = "Put \(items) back."
        if !refused.isEmpty {
            line += " \(refused.count.formatted()) could not be, and are named below."
        }
        return line
    }
}

/// How a restore ended, including the way it ends before it starts.
///
/// ⚠️ A `Result` would need `RehearsalGate.Refusal` to be an `Error`, and it is deliberately not
/// one: the gate refusing is not a fault, it is the app doing exactly what it was built to do until
/// somebody has walked the rehearsal.
enum RestoreAnswer: Sendable {

    /// ⛔ The gate said no. Nothing was read and nothing was written.
    case refusedByTheGate(RehearsalGate.Refusal)

    case finished(RestoreReport)

    var report: RestoreReport? { if case .finished(let report) = self { return report }; return nil }

    var sentence: String {
        switch self {
        case .refusedByTheGate(let refusal): refusal.sentence
        case .finished(let report):          report.sentence
        }
    }
}

/// ⭐ **Putting files back. Every entry point asks the gate.**
enum Restore {

    /// ⭐ **The app's entry point.** Asks `RehearsalGate` and hands back its refusal when it says no.
    ///
    /// ⚠️ It asks about the *destination on this Mac*, not about the drive, because this is the
    /// direction that writes into somebody's home folder — the one place in this app where a wrong
    /// write costs the thing the app exists to protect.
    static func start(_ items: [RestorableItem],
                      fromDrive mountPoint: String,
                      to destinationRoot: URL) -> RestoreAnswer {
        switch RehearsalGate.permissionToWrite(to: destinationRoot.lastPathComponent) {
        case .refused(let refusal):
            return .refusedByTheGate(refusal)
        case .granted(let pass):
            return .finished(run(items, fromDrive: mountPoint, to: destinationRoot, permittedBy: pass))
        }
    }

    /// ⭐ **Put the named copies back.**
    ///
    /// - Parameters:
    ///   - destinationRoot: where they land. The home folder puts them back where they were; any
    ///     other folder puts them somewhere safe to look at first, which is what a cautious person
    ///     does and what the screen should offer by default.
    ///   - pass: permission from `RehearsalGate`. Only the gate can make one.
    static func run(_ items: [RestorableItem],
                    fromDrive mountPoint: String,
                    to destinationRoot: URL,
                    permittedBy pass: RehearsalGate.Pass) -> RestoreReport {

        ScanPolicy.prepareThisThread()

        let backupRoot = BackupCatalogue.root(onDrive: mountPoint)
        let driveName = (mountPoint as NSString).lastPathComponent

        guard Movable.exists(mountPoint) else {
            return RestoreReport(outcomes: items.map {
                RestoreOutcome(item: $0, landedAt: nil,
                               refusal: .theDriveIsNotConnected(name: driveName))
            })
        }

        // ⚠️ The rules are built around the BACKUP as the source, so `relativePath` comes out
        // relative to the drive's own `Your files`. The same reader, the same copier — there is no
        // second copy path in this engine and there must never be one.
        let onTheDrive = BackupCatalogue.files(onDrive: mountPoint)
        let links = HardLinkLedger()

        var outcomes: [RestoreOutcome] = []
        for item in items {
            let source = backupRoot.appending(path: item.onTheDriveAt).path(percentEncoded: false)
            guard Movable.exists(source) else {
                outcomes.append(RestoreOutcome(item: item, landedAt: nil,
                                               refusal: .itIsNotOnTheDrive(path: item.onTheDriveAt)))
                continue
            }

            let landing = destinationRoot.appending(path: item.relativePath)
            let landingPath = landing.path(percentEncoded: false)

            // ⛔ Never over the top of something. Checked here so the row can say so in words, and
            // guaranteed by `COPYFILE_EXCL` inside `CopyOne` even if something appears in between.
            if Movable.exists(landingPath) {
                outcomes.append(RestoreOutcome(item: item, landedAt: nil,
                                               refusal: .somethingIsAlreadyThere(path: landingPath)))
                continue
            }

            do {
                try FileManager.default.createDirectory(at: landing.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
            } catch {
                outcomes.append(RestoreOutcome(item: item, landedAt: nil,
                                               refusal: .theFolderCouldNotBeMade(why: error.localizedDescription)))
                continue
            }

            // The item, read off the drive, with its path relative to where it will land.
            let rules = SourceRules(home: onTheDrive)
            guard var reading = SourceReader.read(source, rules: rules) else {
                outcomes.append(RestoreOutcome(item: item, landedAt: nil,
                                               refusal: .itIsNotOnTheDrive(path: item.onTheDriveAt)))
                continue
            }
            // An older copy lives under `Previous versions/…`, so its own relative path is not where
            // it belongs. The record knows where it belongs; use that.
            reading = reading.at(relativePath: item.relativePath)

            switch CopyOne.run(reading, into: destinationRoot, links: links, permittedBy: pass) {
            case .copied:
                outcomes.append(RestoreOutcome(item: item, landedAt: landingPath, refusal: nil))
            case .skipped(let exclusion):
                outcomes.append(RestoreOutcome(item: item, landedAt: nil,
                                               refusal: .itCouldNotBeCopied(why: exclusion.sentence)))
            case .failed(let failure):
                outcomes.append(RestoreOutcome(
                    item: item, landedAt: nil,
                    refusal: failure.code == EEXIST
                        ? .somethingIsAlreadyThere(path: landingPath)
                        : .itCouldNotBeCopied(why: failure.why)))
            }
        }

        return RestoreReport(outcomes: outcomes)
    }

    /// ⚠️ **Where a cautious restore should land by default**, and the reason it is not the home
    /// folder.
    ///
    /// Restoring on top of a live home folder is the moment a person is most likely to lose
    /// something: they are already upset, they are in a hurry, and the thing they are restoring over
    /// may be the good copy. A folder on the Desktop costs one drag afterwards and cannot destroy
    /// anything.
    static func somewhereSafe(home: URL = StorageManifest.home(), on date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return home.appending(path: "Desktop/Restored by Wellkept \(formatter.string(from: date))")
    }

    static let whyNotStraightBack = """
        Wellkept puts restored files in a new folder on your Desktop rather than back on top of what \
        is there now. The copy on your Mac may be the newer one, and once it is written over it is \
        gone. Dragging them into place afterwards takes a moment and cannot cost you anything.
        """
}

// MARK: - Small helpers

extension SourceItem {
    /// The same reading, filed under a different relative path.
    ///
    /// Used by the restore: a kept older copy sits under `Previous versions/…` on the drive, and its
    /// own path is not where it belongs on the Mac. The record knows where it belongs.
    func at(relativePath: String) -> SourceItem {
        SourceItem(path: path,
                   relativePath: relativePath,
                   isDirectory: isDirectory,
                   isSymbolicLink: isSymbolicLink,
                   isCloudOnly: isCloudOnly,
                   apparentBytes: apparentBytes,
                   allocatedBytes: allocatedBytes,
                   linkCount: linkCount,
                   device: device,
                   inode: inode,
                   mode: mode,
                   createdOn: createdOn,
                   modifiedOn: modifiedOn)
    }
}
