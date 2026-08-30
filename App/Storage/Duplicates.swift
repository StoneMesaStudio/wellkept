// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  Duplicates.swift
//  Wellkept — App/Storage
//
//  ⭐ **Sold as tidiness, never as space, and we never nominate the original.**
//
//  ## Why this row is the smallest prize on the screen
//
//  Measured on one real Mac, 2026-08-28. In `~/Documents` the entire prize is **387 MB spread over 633
//  separate judgement calls** — about 600 KB per decision. Across the whole home folder there are
//  **12,021 groups, and 94% of them are inside project folders**, where the two files are not a
//  person's carelessness but a build system's output and deleting one breaks the build.
//
//  So this row is fourth of five, it never claims to make room, and its headline is a count of
//  decisions rather than a number of gigabytes.
//
//  ## ⚠️ Two APFS clones are one file, and nothing else can tell
//
//  Verified here on 2026-08-28 with a 3 MB file, a `cp -c` clone of it and a real copy:
//
//  | | `st_blocks` | `du` counts it | physical offset of block 0 |
//  |---|---|---|---|
//  | the original | 5,864 | yes | 308568457216 |
//  | the clone | 5,864 | yes | **308568457216** |
//  | a real copy | 5,864 | yes | 487262486528 |
//
//  **Every size reading in macOS reports a clone at its full size**, so a clone pair is
//  indistinguishable from a duplicate pair by size, by content, by hash and by `du`. The only thing
//  that separates them is where the blocks actually are, and `F_LOG2PHYS_EXT` is what asks. Without
//  it the headline figure on this row would be wrong by exactly one copy of every cloned file — a
//  number a person can disprove by deleting one and watching nothing happen. See `blockClasses`.
//
//  Hard links are the same problem arriving by an older door, and they are caught earlier, by the
//  inode. See `Candidate.identity`.
//
//  ## ⚠️ We never choose which copy is the original
//
//  Four real pairs on this Mac each defeat a different rule — including a photo whose dates a past
//  copy destroyed, so "keep the oldest" picks the wrong one. There is therefore no `keep` field on
//  `Group`, no `suggested`, and no sort that puts a preferred copy first. The words are
//  `ScanPolicy.Shape.aDuplicateWeWouldHaveToChooseBetween.why`, which is where every screen in the
//  section reads them from.
//
//  ## The order of work, and why it is that order
//
//  1. **Size**, from the walk. Free, and it eliminates almost everything.
//  2. **Identity**, one `lstat` per candidate. Two names for one inode are one file.
//  3. **A cheap hash** — the first and last 64 KB, plus the length. One seek each end.
//  4. **A full byte-for-byte compare.** Nothing is ever called identical without one.
//  5. **The physical block check**, on everything that survived step 4.
//
//  ⚠️ Steps 3 and 4 are the only place in this section that opens a file, and they run behind
//  `ScanPolicy.mayReadContents(...)` — which refuses on a thread that has not set the I/O policy, so
//  the guard is not "somebody remembered". A file that is in iCloud and not on this Mac is never
//  opened at all: during the research, comparing files pulled **524** of them down over somebody's
//  internet and turned a 36-second scan into over nine minutes.

// MARK: - Whether two copies are really two

/// ⚠️ **Whether the copies occupy separate blocks on the disk.** See the table in the file note.
enum BlockSharing: String, Sendable, Codable, CaseIterable {

    /// Different blocks. Removing one really does leave one copy's worth of room behind — subject,
    /// as always, to the snapshot.
    case separateCopies

    /// **One file wearing two names.** A clone or a hard link. Removing one returns nothing, and
    /// the pair is not a duplicate — so it never reaches a screen and never enters a total.
    case sameBlocks

    /// The disk would not say. Compressed files and some filesystems do not answer
    /// `F_LOG2PHYS_EXT`, and a "probably" is not a figure.
    case couldNotTell

    /// Whether the group's bytes may be added to the row's total.
    ///
    /// ⚠️ `.couldNotTell` says **no**, deliberately. The group is still shown — the files really are
    /// identical, and that is worth knowing — but a number nobody verified does not go into a
    /// headline.
    var mayBeCounted: Bool { self == .separateCopies }

    var sentence: String? {
        switch self {
        case .separateCopies: nil
        case .sameBlocks:     ScanPolicy.Shape.oneHalfOfAClone.why
        case .couldNotTell:
            "These files are identical, but this disk would not say whether they are sharing space. "
            + "They are listed and they are not counted."
        }
    }
}

// MARK: - ⭐ The finder

enum Duplicates {

    // MARK: The numbers that bound the work

    /// ⚠️ Nothing smaller than this is compared. Below a megabyte the group count runs into five
    /// figures and every one of them is a decision a person has to make about a 40 KB file; the
    /// whole `~/Documents` prize here averages 600 KB per decision as it is.
    static let smallestWorthComparing = SizeOnDisk(1_000_000)

    /// How many groups reach the screen. Beyond this it is not a list, it is a chore.
    static let howManyGroups = 50

    /// ⚠️ **A ceiling on how much is read, not on how much is found.** A Mac with 20 GB of genuine
    /// duplicates would otherwise read 40 GB to prove it, which is minutes of disk with nothing on
    /// the screen. When it runs out the run says so rather than quietly reporting less.
    static let mostBytesToRead: Int64 = 8_000_000_000

    /// How much of each end the cheap hash reads.
    static let cheapHashWindow = 64 * 1024

    // MARK: One group

    /// **A set of byte-for-byte identical files, presented and never resolved.**
    ///
    /// ⚠️ There is no `keep`, no `original`, no `suggested` and no ordering that implies one. See
    /// the file note.
    struct Group: Sendable, Hashable, Identifiable {

        /// Every copy, one per set of blocks. Clones and hard links have already been folded into
        /// their representative — they are not extra copies, they are the same file.
        let copies: [Item]

        /// Whether the copies occupy separate blocks.
        let sharing: BlockSharing

        /// How many names were folded away because they turned out to be one file.
        let sharedNamesFolded: Int

        /// Whether any copy sits inside a project folder. Those groups are not offered at all —
        /// see `Says.whyProjectsAreLeftOut`.
        let insideAProject: Bool

        var id: String { copies.map(\.id).joined(separator: "+") }

        /// How many decisions this group asks of a person: one per copy beyond the first.
        var judgementCalls: Int { max(0, copies.count - 1) }

        /// ⭐ **The extra copies' worth, under-promised on both numbers independently.**
        ///
        /// Whichever copy is kept, at least this much is duplicated: sort by size and drop the
        /// largest, sort by what comes back and drop the most generous. The two subsets can differ,
        /// and that is on purpose — each figure is separately the smallest true answer, and a
        /// coherent larger pair would be a promise the disk has not made.
        var extra: Bytes {
            guard copies.count > 1 else { return .zero }
            let sizes = copies.map(\.bytes.onDisk).sorted()
            let backs = copies.map(\.bytes.recoverableToday).sorted()
            return Bytes(onDisk: sizes.dropLast().reduce(SizeOnDisk.zero, +),
                         recoverableToday: backs.dropLast().reduce(Recoverable.nothing, +))
        }

        /// The row's own sentence: what these are, with no verb in it.
        var headline: String {
            let name = copies.first?.name ?? "these files"
            return copies.count == 2
                ? "Two copies of \(name)."
                : "\(copies.count) copies of \(name)."
        }

        /// ⭐ **The sentence that appears wherever this group does.** One spelling, kept beside
        /// everything else in the section that says no.
        static let weNeverChoose = ScanPolicy.Shape.aDuplicateWeWouldHaveToChooseBetween.why
    }

    // MARK: What one run produced

    struct Answer: Sendable, Hashable {

        /// The groups worth putting in front of somebody, largest extra first.
        let groups: [Group]

        /// ⭐ **The tidiness figure**, and it is only ever the groups whose blocks were confirmed
        /// separate.
        let tidiness: Bytes

        /// How many separate decisions the listed groups ask for. **The honest headline** — 633 in
        /// `~/Documents` on this Mac, for 387 MB.
        let judgementCalls: Int

        /// Groups left out because a copy is inside a project folder. 94% of them, here.
        let insideProjects: Int

        /// Sets that turned out to be one file sharing its blocks — an APFS clone. They are not
        /// duplicates and they are not in any total.
        let sharedBlocks: Int

        /// Names folded away because two of them were the same inode. A hard link is not a second
        /// copy.
        let hardLinksFolded: Int

        let filesCompared: Int
        let bytesRead: Int64

        /// Whether the reading budget ran out before every candidate had been proved.
        let stoppedEarly: Bool

        let refused: UnreadablePlaces
        let row: StorageRow
    }

    // MARK: The words

    enum Says {

        /// ⚠️ **Never a space claim.** This row is fourth of five because it is the smallest prize
        /// and the most work.
        static let tidinessNotSpace =
            "This is tidiness, not space. Removing one copy of each would leave about "

        static let whyNothingIsChosen = Group.weNeverChoose

        static let whyProjectsAreLeftOut =
            "Most identical files on a Mac are inside project folders, where a build system made "
            + "the second copy on purpose and removing it breaks the build. Those are not listed."

        static let nothingFound = "No identical copies worth listing."

        static func headline(groups: Int, calls: Int) -> String {
            guard groups > 0 else { return nothingFound }
            let sets = groups == 1 ? "One set" : "\(groups.formatted()) sets"
            let decisions = calls == 1 ? "one decision" : "\(calls.formatted()) separate decisions"
            return "\(sets) of identical files, and \(decisions) to make."
        }

        static func reason(_ tidiness: Bytes, stoppedEarly: Bool) -> String {
            var line = tidinessNotSpace + "\(tidiness.onDisk.text) less on the disk. "
                     + whyNothingIsChosen
            if stoppedEarly {
                line += " We stopped comparing after \(SizeOnDisk(mostBytesToRead).text) of reading, "
                      + "so there may be more."
            }
            return line
        }

        static func copyReason(of count: Int) -> String {
            "One of \(count) files that are byte-for-byte the same. Which one anything else depends "
            + "on is not something we can see."
        }
    }

    // MARK: - Running it

    /// **The whole search.** Blocking, and the only part of Storage that opens a file. `nil` if it
    /// was cancelled.
    ///
    /// - Parameters:
    ///   - roots: what to walk. The home folder by default.
    ///   - snapshots: decides the second number on every copy. Read for real when not supplied.
    ///   - smallest: the floor. See `smallestWorthComparing`.
    ///   - budget: how many bytes the full comparisons may read before the run stops and says so.
    static func find(roots: [URL]? = nil,
                     home: URL = StorageManifest.home(),
                     snapshots: SnapshotStanding? = nil,
                     smallest: SizeOnDisk = smallestWorthComparing,
                     listing: Int = howManyGroups,
                     budget: Int64 = mostBytesToRead,
                     isCancelled: () -> Bool = { Task.isCancelled },
                     progress: (String) -> Void = { _ in }) -> Answer? {

        ScanPolicy.prepareThisThread()

        let held = snapshots ?? FreeSpace.localSnapshots(on: ScanPolicy.root(home: home))
        let starts = roots ?? [home]

        // 1 ── Size. Free, from the one walk, and it eliminates almost everything.
        var bySize: [Int64: [StorageWalk.Entry]] = [:]
        guard let outcome = StorageWalk.walk(from: starts,
                                             home: home,
                                             snapshots: held,
                                             folderDepth: 0,
                                             isCancelled: isCancelled,
                                             progress: progress,
                                             visit: { entry in
            guard entry.kind == .file || entry.kind == .diskImage, !entry.isRefused else { return }
            guard entry.cloudStanding.occupiesSpaceHere else { return }
            guard entry.onDisk >= smallest, entry.apparentBytes > 0 else { return }
            // ⚠️ Bucketed on the **content length**, not on the size on disk: one of two identical
            // files may be compressed and the other not, and they would never meet.
            bySize[entry.apparentBytes, default: []].append(entry)
        }) else { return nil }

        var groups: [Group] = []
        var insideProjects = 0
        var sharedBlocks = 0
        var hardLinksFolded = 0
        var filesCompared = 0
        var bytesRead: Int64 = 0
        var stoppedEarly = false
        var projects = ProjectMemo(home: home)

        for (length, entries) in bySize.sorted(by: { $0.key > $1.key }) {
            guard entries.count > 1 else { continue }
            if isCancelled() { return nil }

            // 2 ── Identity. Two names for one inode are one file, not two.
            var seen: [String: Candidate] = [:]
            var candidates: [Candidate] = []
            for entry in entries {
                guard let candidate = Candidate(entry) else { continue }
                let key = candidate.identityKey
                if seen[key] != nil {
                    // ⚠️ Two names, one inode. A hard link is not a second copy and removing one
                    // of them returns nothing.
                    hardLinksFolded += 1
                    continue
                }
                seen[key] = candidate
                candidates.append(candidate)
            }
            guard candidates.count > 1 else { continue }

            // 3 ── The cheap hash. One seek at each end.
            var byHash: [UInt64: [Candidate]] = [:]
            for candidate in candidates {
                guard ScanPolicy.mayReadContents(ofSize: candidate.entry.onDisk,
                                                 cloudStanding: candidate.entry.cloudStanding,
                                                 forDuplicateComparison: true),
                      let hash = cheapHash(of: candidate.entry.path, length: length)
                else { continue }
                byHash[hash, default: []].append(candidate)
            }

            // 4 ── The full compare. Nothing is called identical without one.
            for bucket in byHash.values where bucket.count > 1 {
                if bytesRead >= budget { stoppedEarly = true; break }
                for set in exactSets(bucket, length: length, bytesRead: &bytesRead, budget: budget,
                                     stoppedEarly: &stoppedEarly) {
                    filesCompared += set.count
                    guard set.count > 1 else { continue }

                    // 5 ── ⚠️ The block check. A clone pair is one file, and is dropped here.
                    let (classes, sharing) = blockClasses(set, length: length)
                    let folded = set.count - classes.count
                    if classes.count < 2 {
                        sharedBlocks += 1
                        continue
                    }

                    // ⚠️ Asked before the copies are built: 94% of the groups on this Mac are
                    // inside project folders, and building an `Item` costs a Spotlight lookup.
                    if classes.contains(where: { projects.isInsideAProject($0.entry.path) }) {
                        insideProjects += 1
                        continue
                    }

                    let copies = classes.compactMap { item(for: $0, snapshots: held,
                                                           count: classes.count) }
                    guard copies.count > 1 else { continue }

                    groups.append(Group(copies: copies,
                                        sharing: sharing,
                                        sharedNamesFolded: folded,
                                        insideAProject: false))
                }
                if stoppedEarly { break }
            }
            if stoppedEarly { break }
        }

        groups.sort { $0.extra.onDisk > $1.extra.onDisk }
        if groups.count > listing { groups.removeSubrange(listing...) }

        let tidiness = Bytes.sum(groups.filter { $0.sharing.mayBeCounted }.map(\.extra))
        let calls = groups.reduce(0) { $0 + $1.judgementCalls }

        return Answer(groups: groups,
                      tidiness: tidiness,
                      judgementCalls: calls,
                      insideProjects: insideProjects,
                      sharedBlocks: sharedBlocks,
                      hardLinksFolded: hardLinksFolded,
                      filesCompared: filesCompared,
                      bytesRead: bytesRead,
                      stoppedEarly: stoppedEarly,
                      refused: outcome.refused,
                      row: row(groups: groups,
                               tidiness: tidiness,
                               judgementCalls: calls,
                               insideProjects: insideProjects,
                               sharedBlocks: sharedBlocks,
                               hardLinksFolded: hardLinksFolded,
                               stoppedEarly: stoppedEarly,
                               refused: outcome.refused))
    }

    // MARK: One candidate

    /// A file that might have a twin, with the one reading that settles hard links.
    ///
    /// A reference type only so that a hard link found later can be counted against the first name
    /// without rebuilding the array.
    final class Candidate {
        let entry: StorageWalk.Entry
        let identity: ItemIdentity

        init?(_ entry: StorageWalk.Entry) {
            guard let identity = StorageWalk.identify(entry.path) else { return nil }
            self.entry = entry
            self.identity = identity
        }

        /// ⚠️ Volume **and** inode. Inode numbers are handed out per volume and they start small,
        /// so a fresh file on a plugged-in drive routinely carries the same number as one at home.
        var identityKey: String {
            "\(identity.volumeUUID ?? identity.volumeDevice)#\(identity.inode)"
        }
    }

    /// One candidate turned into a row on a screen.
    static func item(for candidate: Candidate, snapshots: SnapshotStanding, count: Int) -> Item? {
        let entry = candidate.entry
        return Item(identity: candidate.identity,
                    path: entry.path,
                    name: entry.name,
                    bytes: snapshots.bytes(onDisk: entry.onDisk, modifiedOn: entry.modifiedOn),
                    kind: entry.kind,
                    // ⭐ A person's own file, so: one at a time, never ticked, never swept.
                    origin: .yours,
                    cloudStanding: entry.cloudStanding,
                    handling: .notCheckedYet,
                    modifiedOn: entry.modifiedOn,
                    lastOpenedOn: BigFiles.lastOpened(entry.path),
                    reason: Says.copyReason(of: count))
    }

    // MARK: - Step 3: the cheap hash

    /// The first and last 64 KB, mixed with the length. FNV-1a, because this is a bucketing device
    /// and not a claim — **nothing is called identical on the strength of a hash.**
    static func cheapHash(of path: String, length: Int64) -> UInt64? {
        let descriptor = openForReading(path)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ bytes: [UInt8]) {
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        withUnsafeBytes(of: length.littleEndian) { mix(Array($0)) }

        let window = min(Int64(cheapHashWindow), length)
        guard let head = readBlock(descriptor, at: 0, count: Int(window)) else { return nil }
        mix(head)

        if length > window {
            guard let tail = readBlock(descriptor, at: length - window, count: Int(window)) else {
                return nil
            }
            mix(tail)
        }
        return hash
    }

    // MARK: - Step 4: the full compare

    /// Splits a bucket of same-size, same-hash files into sets that are byte-for-byte identical.
    ///
    /// The first file of each set is only a comparison anchor. ⚠️ **It is not the original**, it is
    /// not marked, and nothing downstream may treat position in this array as a recommendation.
    static func exactSets(_ bucket: [Candidate],
                          length: Int64,
                          bytesRead: inout Int64,
                          budget: Int64,
                          stoppedEarly: inout Bool) -> [[Candidate]] {
        var sets: [[Candidate]] = []
        var remaining = bucket

        while remaining.count > 1 {
            let anchor = remaining.removeFirst()
            var matched = [anchor]
            var unmatched: [Candidate] = []

            for other in remaining {
                if bytesRead >= budget {
                    stoppedEarly = true
                    unmatched.append(other)
                    continue
                }
                if identical(anchor.entry.path, other.entry.path,
                             length: length, bytesRead: &bytesRead) {
                    matched.append(other)
                } else {
                    unmatched.append(other)
                }
            }

            if matched.count > 1 { sets.append(matched) }
            remaining = unmatched
        }
        return sets
    }

    /// Byte for byte, in 1 MB chunks.
    ///
    /// ⚠️ `F_NOCACHE` on both descriptors: a comparison can read gigabytes, and without it the
    /// person's own working set is evicted from memory by a tidy-up they ran in the background.
    static func identical(_ first: String, _ second: String,
                          length: Int64, bytesRead: inout Int64) -> Bool {
        let a = openForReading(first)
        guard a >= 0 else { return false }
        defer { close(a) }
        let b = openForReading(second)
        guard b >= 0 else { return false }
        defer { close(b) }

        let chunk = 1024 * 1024
        var offset: Int64 = 0
        var left = [UInt8](repeating: 0, count: chunk)
        var right = [UInt8](repeating: 0, count: chunk)

        while offset < length {
            let want = Int(min(Int64(chunk), length - offset))
            let readA = left.withUnsafeMutableBytes { pread(a, $0.baseAddress, want, off_t(offset)) }
            let readB = right.withUnsafeMutableBytes { pread(b, $0.baseAddress, want, off_t(offset)) }
            guard readA == want, readB == want else { return false }
            bytesRead += Int64(want) * 2

            let same = left.withUnsafeBytes { lhs in
                right.withUnsafeBytes { rhs in
                    memcmp(lhs.baseAddress!, rhs.baseAddress!, want) == 0
                }
            }
            guard same else { return false }
            offset += Int64(want)
        }
        return true
    }

    // MARK: - Step 5: ⚠️ the block check

    /// **Which of these identical files are actually separate files.**
    ///
    /// Verified on this Mac: a `cp -c` clone and its original report the same physical offset for
    /// the same logical block, and every size reading in macOS reports both at full size. So this
    /// is the only reading that can tell a duplicate from one file wearing two names.
    ///
    /// Three offsets are sampled rather than one, because a clone that was partly rewritten shares
    /// some blocks and not others; **any** shared sample is enough to fold two names together, which
    /// is the cautious direction.
    ///
    /// - Returns: one representative per set of blocks, and how sure we are.
    static func blockClasses(_ set: [Candidate], length: Int64) -> ([Candidate], BlockSharing) {
        var fingerprints: [[off_t]] = []
        var everyoneAnswered = true

        for candidate in set {
            guard let print = physicalFingerprint(of: candidate.entry.path, length: length) else {
                everyoneAnswered = false
                fingerprints.append([])
                continue
            }
            fingerprints.append(print)
        }

        var representatives: [Candidate] = []
        var claimed: Set<off_t> = []

        for (index, candidate) in set.enumerated() {
            let print = fingerprints[index]
            if print.isEmpty {
                // We could not read this one's blocks, so we cannot fold it into anything. It stands
                // as its own copy and the group is marked `.couldNotTell`.
                representatives.append(candidate)
                continue
            }
            if print.contains(where: { claimed.contains($0) }) { continue }
            for offset in print { claimed.insert(offset) }
            representatives.append(candidate)
        }

        let sharing: BlockSharing
        if !everyoneAnswered {
            sharing = .couldNotTell
        } else if representatives.count < 2 {
            sharing = .sameBlocks
        } else {
            sharing = .separateCopies
        }
        return (representatives, sharing)
    }

    /// Where a file's blocks physically are, sampled at the start, the middle and the end.
    ///
    /// `nil` when the disk will not say — a compressed file keeps its data in an extended attribute
    /// and has no blocks to report, and not every filesystem implements the call. A `nil` is
    /// `.couldNotTell`, never an assumption either way.
    static func physicalFingerprint(of path: String, length: Int64) -> [off_t]? {
        let descriptor = openForReading(path)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        let block: off_t = 4096
        var offsets: [off_t] = [0]
        if length > block * 2 { offsets.append(off_t(length / 2) / block * block) }
        if length > block { offsets.append(off_t(length - block) / block * block) }

        var found: [off_t] = []
        for offset in offsets {
            guard let physical = physicalOffset(descriptor, at: offset, length: block),
                  // ⚠️ Zero is not an answer. Device block 0 is the volume's own header and is
                  // never a file's data, so a zero here means a hole — and two files that are both
                  // sparse at the same offset would otherwise be folded together as clones.
                  physical > 0
            else { return nil }
            found.append(physical)
        }
        return found
    }

    /// `F_LOG2PHYS_EXT`: the device offset of the blocks backing a logical offset.
    static func physicalOffset(_ descriptor: Int32, at offset: off_t, length: off_t) -> off_t? {
        var mapping = log2phys()
        mapping.l2p_flags = 0
        mapping.l2p_contigbytes = length
        mapping.l2p_devoffset = offset
        let answered = withUnsafeMutablePointer(to: &mapping) {
            fcntl(descriptor, F_LOG2PHYS_EXT, UnsafeMutableRawPointer($0))
        }
        guard answered == 0 else { return nil }
        return mapping.l2p_devoffset
    }

    // MARK: - Project folders

    /// ⚠️ **94% of the identical files on this Mac are inside project folders**, where the second
    /// copy is a build system's output and removing it breaks the build. Those groups are left out
    /// of the offer entirely, and the row says so.
    ///
    /// Two readings, cheapest first: a component of the path that only ever appears inside a
    /// project, and — memoised per folder — a marker file in any folder above it. A false positive
    /// costs somebody a group we declined to list, which is the direction this whole section errs
    /// in; a false negative costs somebody a build.
    struct ProjectMemo {
        let home: URL
        private var answers: [String: Bool] = [:]

        init(home: URL) { self.home = home }

        /// Folder names that only ever appear inside somebody's project.
        static let insideAProject: Set<String> = [
            "node_modules", "pods", ".build", "build", "deriveddata", "vendor", ".venv", "venv",
            "target", ".gradle", "carthage", ".git", ".svn", ".hg", "__pycache__", ".next", "dist",
            ".terraform", "bower_components", "site-packages", ".stack-work", ".tox", "obj",
        ]

        /// Files whose presence in a folder means that folder is the root of a project.
        static let rootMarkers = [
            "Package.swift", "package.json", "Cargo.toml", "composer.json", "Gemfile", "go.mod",
            "pom.xml", "build.gradle", "requirements.txt", "Podfile", "project.yml", "Makefile",
            "CMakeLists.txt", "pyproject.toml", ".git",
        ]

        mutating func isInsideAProject(_ path: String) -> Bool {
            let parts = path.precomposedStringWithCanonicalMapping
                .split(separator: "/")
                .map { $0.lowercased() }
            if parts.dropLast().contains(where: { Self.insideAProject.contains($0) }) { return true }
            if parts.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
                return true
            }
            return hasAMarkerAbove((path as NSString).deletingLastPathComponent)
        }

        private mutating func hasAMarkerAbove(_ directory: String) -> Bool {
            let ceiling = home.path(percentEncoded: false)
            var current = directory
            var walked: [String] = []
            var answer = false

            while current.count >= ceiling.count, current != "/" {
                if let known = answers[current] { answer = known; break }
                walked.append(current)
                if Self.rootMarkers.contains(where: {
                    access("\(current)/\($0)", F_OK) == 0
                }) {
                    answer = true
                    break
                }
                let parent = (current as NSString).deletingLastPathComponent
                if parent == current { break }
                current = parent
            }

            for folder in walked { answers[folder] = answer }
            return answer
        }
    }

    // MARK: - Opening a file

    /// ⚠️ **`O_NOFOLLOW`**, so a symbolic link is never opened as if it were its target, and
    /// **`F_NOCACHE`**, so a comparison that reads gigabytes does not evict the person's own working
    /// set from memory.
    static func openForReading(_ path: String) -> Int32 {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return descriptor }
        _ = fcntl(descriptor, F_NOCACHE, 1)
        return descriptor
    }

    static func readBlock(_ descriptor: Int32, at offset: Int64, count: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: count)
        let got = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, count, off_t(offset)) }
        guard got == count else { return nil }
        return buffer
    }

    // MARK: - The row

    static func row(groups: [Group],
                    tidiness: Bytes,
                    judgementCalls: Int,
                    insideProjects: Int,
                    sharedBlocks: Int,
                    hardLinksFolded: Int,
                    stoppedEarly: Bool,
                    refused: UnreadablePlaces) -> StorageRow {

        var details: [DetailPair] = []
        if insideProjects > 0 {
            details.append(DetailPair("Left out of this list",
                                      "\(insideProjects.formatted()) sets inside project folders. "
                                      + Says.whyProjectsAreLeftOut))
        }
        let notReallyTwo = sharedBlocks + hardLinksFolded
        if notReallyTwo > 0 {
            details.append(DetailPair("Not duplicates after all",
                                      "\(notReallyTwo.formatted()) turned out to be one file under "
                                      + "two names. " + ScanPolicy.Shape.oneHalfOfAClone.why))
        }
        if let unsure = groups.first(where: { $0.sharing == .couldNotTell })?.sharing.sentence {
            details.append(DetailPair("Listed but not counted", unsure))
        }
        details.append(DetailPair("Smallest file compared", smallestWorthComparing.text))
        details.append(DetailPair("Which copy to keep", Says.whyNothingIsChosen))

        return StorageRow(topic: .duplicates,
                          headline: Says.headline(groups: groups.count, calls: judgementCalls),
                          measure: groups.isEmpty ? nil : tidiness,
                          count: groups.isEmpty ? nil : groups.count,
                          reason: groups.isEmpty
                              ? Says.whyProjectsAreLeftOut
                              : Says.reason(tidiness, stoppedEarly: stoppedEarly),
                          // ⭐ Every copy, flattened, group by group. `StorageRow.preSelected`
                          // returns [] for `.duplicates` whatever these claim, and every one of
                          // them is `.yours` besides.
                          items: groups.flatMap(\.copies),
                          details: details,
                          refused: refused)
    }
}
