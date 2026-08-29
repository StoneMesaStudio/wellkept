// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import CryptoKit
import Darwin
import Foundation
import WellkeptCore

//  Verification.swift
//  Wellkept — App/Backup/Engine
//
//  ⭐⭐ **The word "verified" is never used without reading the bytes back off the drive.**
//
//  That is the whole file, and it is one rule with an entire type built around it because the
//  alternative is the ordinary industry behaviour: a copy returns zero, the tool says "verified",
//  and the first person to find out otherwise is somebody restoring a photo library.
//
//  ## The three levels, and what each one honestly checked
//
//  | Level | The word it earns | What it actually did | What it does not prove |
//  |---|---|---|---|
//  | `.counted` | **counted** | The copy returned without an error and there is an entry on the drive | Nothing about the contents. A zero-byte file counts. |
//  | `.compared` | **checked** | Size, permissions, dates and the cloud flag read back off the drive and compared to the source | Nothing about the contents. Two files can match on all of that and differ in every byte. |
//  | `.readBack` | ⭐ **verified** | Every byte read back off the drive and hashed against the source | Only that the bytes matched at the moment they were read |
//
//  ⚠️ **`.compared` is where an honest tool is most tempted to lie**, because it feels thorough. It
//  is not: a truncated write that happens to land on a block boundary, a drive returning stale cache
//  contents, and a file the copy skipped and something else recreated all pass it. It is genuinely
//  useful — it is what catches the empty cloud file, which is the failure this section was built
//  around — and it is still not verification.
//
//  ## ⚠️ A sample is never "verified", it is "verified 500 of 586,642"
//
//  Reading back every byte of a home folder means reading the whole home folder twice. On a large
//  one that is the difference between a backup somebody runs and a backup somebody turns off. So a
//  sample is offered — and **the sentence always carries both numbers**. "Verified" with a figure
//  attached is a true statement about a sample; "verified" alone about a sample is the lie.
//
//  ## ⚠️ And the flag still outranks the hash
//
//  A cloud-only file that is genuinely zero bytes copies cleanly and hashes identically to its
//  source, because both are empty. **A matching hash is not evidence that the file was here.** So
//  the source's `SF_DATALESS` flag is read at check time as well, and a file that is a cloud
//  placeholder is reported as skipped rather than as verified, whatever the hash says. See
//  `Backup.whyTheReturnCodeIsNotEvidence`.
//
//  Nothing in this file writes. It opens files for reading on both sides. The writers take a
//  `RehearsalGate.Pass`.

// MARK: - The levels

/// How hard the check looked. ⭐ The word each level is allowed to use is a property of the level,
/// not a choice made at the call site.
enum VerificationLevel: String, Sendable, Equatable, CaseIterable, Codable, Comparable {

    /// The copy returned and something is there.
    case counted

    /// Size, permissions, dates and the cloud flag read back and compared.
    case compared

    /// ⭐ Every byte read back off the drive and hashed. **The only level that earns "verified".**
    case readBack

    /// ⭐ **The word.** There is no other place in the app that decides what to call a check.
    var word: String {
        switch self {
        case .counted:  "counted"
        case .compared: "checked"
        case .readBack: "verified"
        }
    }

    /// What this level actually did, said plainly, for the line under the result.
    var whatItChecked: String {
        switch self {
        case .counted:
            "Wellkept counted the files it copied and confirmed each one is on the drive."
        case .compared:
            "Wellkept read each file's size, permissions and dates back off the drive and compared "
            + "them with the ones on this Mac."
        case .readBack:
            "Wellkept read every byte back off the drive and compared it with the file on this Mac."
        }
    }

    /// ⚠️ What it does **not** prove. On the screen, next to the result, because a person told
    /// "checked" without this will hear "verified".
    var whatItDoesNotProve: String? {
        switch self {
        case .counted:
            "It did not look inside the files. A file of the right name and no contents passes this."
        case .compared:
            "It did not look inside the files. Two files can match on size and dates and differ in "
            + "every byte."
        case .readBack:
            nil
        }
    }

    /// ⭐ Whether this level may use the word "verified" at all.
    var mayUseTheWordVerified: Bool { self == .readBack }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (a: VerificationLevel, b: VerificationLevel) -> Bool { a.rank < b.rank }
}

// MARK: - One file's check

/// What checking one file found.
struct FileCheck: Sendable, Equatable, Hashable {

    let relativePath: String
    let level: VerificationLevel
    let matched: Bool

    /// Why it did not match. `nil` when it did.
    let why: String?

    /// ⚠️ The source is a cloud placeholder, so there is nothing on this Mac to compare against.
    /// **Not a failure**, and not a pass either — it is the case the whole section exists to name.
    let sourceIsInTheCloud: Bool

    var isFailure: Bool { !matched && !sourceIsInTheCloud }
}

// MARK: - The whole check

/// What a verification pass found.
struct VerificationReport: Sendable, Equatable {

    /// The level that actually ran.
    let level: VerificationLevel

    /// How many files were checked.
    let checked: Int

    /// How many are in the backup altogether. ⚠️ Different from `checked` whenever a sample ran, and
    /// that difference is what stops the word "verified" standing alone.
    let inTheBackup: Int

    /// The ones that did not match.
    let failures: [FileCheck]

    /// Skipped because the source is in the cloud and not on this Mac.
    let cloudOnly: Int

    /// Whether only some of the backup was checked.
    var wasASample: Bool { checked < inTheBackup }

    var allMatched: Bool { failures.isEmpty }

    /// ⭐ **The sentence, and the one place the word is chosen.**
    ///
    /// ⚠️ Three rules, and they are all here rather than at any call site: the word comes from the
    /// level; a sample always carries both numbers; and a failure is stated before anything else,
    /// because a report that leads with how thorough it was and buries the mismatch has the emphasis
    /// exactly backwards.
    var sentence: String {
        if !allMatched {
            let count = failures.count == 1 ? "1 file" : "\(failures.count.formatted()) files"
            return "\(count) on the drive did not match the file on this Mac. "
                 + "This backup is not a copy you can rely on until that is sorted out."
        }

        let counted = checked.formatted()
        if wasASample {
            return "Wellkept \(level.word) \(counted) of the \(inTheBackup.formatted()) files in "
                 + "this backup, chosen at random, and they all matched."
        }
        return "Wellkept \(level.word) all \(counted) files in this backup, and they all matched."
    }

    /// The line underneath: what the level did, and what it did not.
    var linesUnderneath: [String] {
        var lines = [level.whatItChecked]
        if let caveat = level.whatItDoesNotProve { lines.append(caveat) }
        if cloudOnly > 0 {
            lines.append("\(cloudOnly.formatted()) files are in iCloud and not on this Mac, so "
                       + "there was nothing here to compare them with.")
        }
        return lines
    }

    var detailPairs: [DetailPair] {
        [DetailPair("How it was checked", level.word.capitalized),
         DetailPair("Files checked", "\(checked.formatted()) of \(inTheBackup.formatted())"),
         DetailPair("Did not match", failures.count.formatted())]
    }
}

// MARK: - Doing the checking

enum Verify {

    /// How much is read at a time when hashing. 1 MB — big enough that a large file is not a
    /// million syscalls, small enough that a 40 GB disk image does not need 40 GB of memory.
    static let chunk = 1 << 20

    /// ⭐ **Check one file at one level.**
    ///
    /// - Parameters:
    ///   - sourcePath: the file on this Mac.
    ///   - backupPath: the copy on the drive.
    ///   - relativePath: what to call it in the report.
    static func check(sourcePath: String,
                      backupPath: String,
                      relativePath: String,
                      level: VerificationLevel) -> FileCheck {

        ScanPolicy.prepareThisThread()

        // ⭐ The flag first, at every level. A cloud placeholder has nothing here to compare, and a
        // hash of two empty files is a match that means nothing.
        if SourceReader.isCloudOnly(sourcePath) {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: nil, sourceIsInTheCloud: true)
        }

        var source = stat()
        var copy = stat()
        guard lstat(sourcePath, &source) == 0 else {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "the file is no longer on this Mac", sourceIsInTheCloud: false)
        }
        guard lstat(backupPath, &copy) == 0 else {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "it is not on the drive", sourceIsInTheCloud: false)
        }

        if level == .counted {
            return FileCheck(relativePath: relativePath, level: level, matched: true,
                             why: nil, sourceIsInTheCloud: false)
        }

        // ── .compared ────────────────────────────────────────────────────────────────────────────
        if source.st_size != copy.st_size {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "it is \(copy.st_size.formatted()) bytes on the drive and "
                                + "\(source.st_size.formatted()) bytes here",
                             sourceIsInTheCloud: false)
        }
        if (source.st_mode & 0o7777) != (copy.st_mode & 0o7777) {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "what it is allowed to do is different on the drive",
                             sourceIsInTheCloud: false)
        }
        if source.st_mtimespec.tv_sec != copy.st_mtimespec.tv_sec {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "the date it was last changed is different on the drive",
                             sourceIsInTheCloud: false)
        }
        // ⚠️ Repair 1's own check. A copy whose creation date was not put back is still the right
        // contents, so this is a mismatch worth naming and is reported as one.
        if source.st_birthtimespec.tv_sec != copy.st_birthtimespec.tv_sec {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "the date it was created is different on the drive",
                             sourceIsInTheCloud: false)
        }

        if level == .compared {
            return FileCheck(relativePath: relativePath, level: level, matched: true,
                             why: nil, sourceIsInTheCloud: false)
        }

        // ── ⭐ .readBack — the only level that earns the word ─────────────────────────────────────
        guard (source.st_mode & S_IFMT) == S_IFREG else {
            // A folder or a symbolic link has no bytes to read back. Its metadata was compared
            // above, and saying more than that would be the overclaim this file exists to prevent.
            return FileCheck(relativePath: relativePath, level: level, matched: true,
                             why: nil, sourceIsInTheCloud: false)
        }
        guard let here = digest(of: sourcePath) else {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "the file on this Mac could not be read", sourceIsInTheCloud: false)
        }
        guard let there = digest(of: backupPath) else {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "the copy on the drive could not be read", sourceIsInTheCloud: false)
        }
        guard here == there else {
            return FileCheck(relativePath: relativePath, level: level, matched: false,
                             why: "the contents on the drive are not the contents on this Mac",
                             sourceIsInTheCloud: false)
        }
        return FileCheck(relativePath: relativePath, level: level, matched: true,
                         why: nil, sourceIsInTheCloud: false)
    }

    /// ⭐ **Check a whole backup**, at one level, over a list of files.
    ///
    /// - Parameters:
    ///   - files: what to check, as paths relative to the backup folder.
    ///   - sample: how many to check. `nil` checks everything. ⚠️ Whatever this is, the report
    ///     carries both numbers and the sentence says so.
    static func run(_ files: [String],
                    home: URL,
                    backupFiles: URL,
                    level: VerificationLevel,
                    sample: Int? = nil,
                    randomness: (Int) -> [String] = { _ in [] }) -> VerificationReport {

        let chosen: [String]
        if let sample, sample < files.count {
            // Random rather than the first N: the first N of a sorted list is the top of somebody's
            // home folder, and a fault that only affects large files or a late folder would never
            // be seen. A caller may hand in its own choosing for a test.
            let supplied = randomness(sample)
            chosen = supplied.isEmpty ? Array(files.shuffled().prefix(sample)) : supplied
        } else {
            chosen = files
        }

        var failures: [FileCheck] = []
        var cloudOnly = 0
        var checked = 0

        for relative in chosen {
            let result = check(sourcePath: home.appending(path: relative).path(percentEncoded: false),
                               backupPath: backupFiles.appending(path: relative).path(percentEncoded: false),
                               relativePath: relative,
                               level: level)
            if result.sourceIsInTheCloud { cloudOnly += 1; continue }
            checked += 1
            if result.isFailure { failures.append(result) }
        }

        return VerificationReport(level: level,
                                  checked: checked,
                                  inTheBackup: files.count,
                                  failures: failures,
                                  cloudOnly: cloudOnly)
    }

    /// SHA-256 of a file, read a megabyte at a time.
    ///
    /// The hash is never shown to anybody and never stored — it exists for the length of one
    /// comparison. A backup that recorded a hash per file would be a second index to keep correct,
    /// and a stale one would fail files that are fine.
    static func digest(of path: String) -> SHA256Digest? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            guard let piece = try? handle.read(upToCount: chunk), !piece.isEmpty else { break }
            hasher.update(data: piece)
        }
        return hasher.finalize()
    }
}
