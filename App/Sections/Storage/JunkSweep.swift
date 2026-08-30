// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  JunkSweep.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **The one place `JunkClassifier` is actually asked a question, and the row it produces.**
//
//  `JunkClassifier` decides. It does not look. This walks a short list of places, hands each folder
//  and each file to `JunkClassifier.judge`, and stops the moment the answer is a category — because
//  a junk folder is junk whole, and descending into one counts the same bytes at four depths and
//  offers a person the same thing four times.
//
//  ## ⚠️ Location narrows where we look. It never convicts.
//
//  The starting points below are a search hint and nothing more. Every single thing found under
//  them is still judged on its own name and its own shape, which is why the 1.3 GB audiobook sitting
//  in `~/Library/Caches/com.apple.bookassetd` right now comes back `.yours` and is never ticked:
//  `Track 1.m4b` is a name a person can read, and one readable name spoils the whole folder. Delete
//  every path below and the classifier still answers correctly — it would just be slower.
//
//  ## ⚠️ The two numbers, per file, never per folder
//
//  A folder's size on disk is the sum of its files' allocated blocks. What would come back today is
//  the sum of its files' **own** answers to the snapshot arithmetic, computed one at a time by
//  `StorageWalk` and never by applying the folder's modification date to the whole. On one real Mac the
//  two are 30× apart for one measured media folder, and the worksheet has a 150× case.
//
//  ## ⛔ The simulator runtimes come in here and carry no button
//
//  They are not reachable by any walk in this section — they mount as separate sealed read-only
//  APFS volumes, so `ScanPolicy.descend` refuses them as another volume. `JunkClassifier` reads the
//  images behind those mounts by `lstat` instead, and every one of them arrives with
//  `Handling.cannot(...)`, which removes the button mechanically rather than by anybody remembering.

enum JunkSweep {

    // MARK: - Where to look

    /// A starting point, and what to call it while the scan is running.
    ///
    /// ⚠️ These are **hints**, not evidence. See the header. `~/Library/Caches` is on the list
    /// because caches are usually there, and the classifier convicts nothing for being there.
    struct Place: Sendable, Hashable {
        let relativePath: String
        let name: String
    }

    /// The places worth walking, under the home folder only.
    ///
    /// `/Library` and `/System` are absent because Wellkept ships no privileged helper: a move
    /// there fails with `EACCES`, and offering a button that cannot work is worse than not
    /// offering one. See `Reach.standard`.
    static let places: [Place] = [
        Place(relativePath: "Library/Caches", name: "your caches"),
        Place(relativePath: "Library/Developer", name: "Xcode's own folder"),
        Place(relativePath: "Library/Application Support", name: "Application Support"),
        Place(relativePath: "Library/Logs", name: "your logs"),
        Place(relativePath: "Downloads", name: "your Downloads folder"),
    ]

    /// How far under a starting point the sweep goes.
    ///
    /// Four levels reaches `Library/Developer/Xcode/DerivedData/<project>` — the shape of the
    /// largest honest win on one real Mac, 13 GB — without walking a million files. Anything deeper is
    /// somebody's own tree, and the classifier would say `.yours` about it anyway.
    static let howDeep = 4

    // MARK: - What one sweep produced

    struct Found: Sendable {
        /// Everything judged the machine's, largest on disk first.
        let junk: [JunkClassifier.Classified]
        /// Places the sweep was refused. **Never a zero** — see `UnreadablePlaces`.
        let refused: UnreadablePlaces
        /// How many things were looked at, for the audit trail.
        let considered: Int

        /// ⭐ Everything that may arrive ticked, and it is the classifier's answer intersected with
        /// `Item.mayBePreSelected`. Nothing here re-decides it.
        var ticked: [Item] { JunkClassifier.arrivingTicked(junk) }

        var items: [Item] { junk.map(\.item) }

        /// Both numbers for everything found. Summed from the items, so the row's figure and the
        /// list's figures cannot disagree.
        var total: Bytes { Bytes.sum(items.map(\.bytes)) }

        /// What the ticked things add up to — the figure the one press is about.
        var tickedTotal: Bytes { Bytes.sum(ticked.map(\.bytes)) }

        /// The things with a size and no button: the simulator runtimes, and anything the refusal
        /// list caught.
        var reportedOnly: [Item] { items.filter { !$0.handling.mayOfferAButton } }
    }

    // MARK: - Running it

    /// **The whole sweep.** Blocking; belongs on a detached task. `nil` if it was cancelled.
    ///
    /// - Parameters:
    ///   - snapshots: the local Time Machine snapshots, which decide the second number on every
    ///     row. Read for real when not supplied.
    ///   - assetStore: where the simulator runtime images live. Injected so a test can point it at
    ///     a folder it made itself rather than at this Mac's.
    static func read(home: URL = StorageManifest.home(),
                     snapshots: SnapshotStanding? = nil,
                     assetStore: String = JunkClassifier.assetStore,
                     now: Date = Date(),
                     isCancelled: () -> Bool = { Task.isCancelled },
                     progress: (String) -> Void = { _ in }) -> Found? {

        // Per thread, not per process. Without it a read materialises a dataless file, which during
        // the research pulled 524 files down over somebody's internet.
        ScanPolicy.prepareThisThread()

        let held = snapshots ?? FreeSpace.localSnapshots(on: ScanPolicy.root(home: home))
        var found: [JunkClassifier.Classified] = []
        var considered = 0
        var refusedCount = 0
        var refusedNotable: [String] = []

        func noteRefusal(_ name: String) {
            refusedCount += 1
            if refusedNotable.count < 8, !refusedNotable.contains(name) {
                refusedNotable.append(name)
            }
        }

        for place in places {
            if isCancelled() { return nil }
            let root = home.appending(path: place.relativePath, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
                continue
            }
            progress(ScanPolicy.Running.at(place.name))

            let volume = Movable.volume(of: root.path(percentEncoded: false))
            guard ScanPolicy.descend(into: root, stayingOn: nil, home: home).isAllowed else {
                noteRefusal(place.name)
                continue
            }

            // Breadth-first, so the shallow answers — which are the big ones — land first and a
            // cancellation partway through has still looked at the places worth looking at.
            var queue: [(url: URL, depth: Int)] = [(root, 0)]
            while !queue.isEmpty {
                if isCancelled() { return nil }
                let (url, depth) = queue.removeFirst()

                let names: [String]
                do {
                    names = try FileManager.default
                        .contentsOfDirectory(atPath: url.path(percentEncoded: false))
                } catch {
                    noteRefusal(ScanPolicy.refusal(for: url.path(percentEncoded: false),
                                                   home: home)?.name
                                ?? url.lastPathComponent)
                    continue
                }

                for name in names {
                    if isCancelled() { return nil }
                    let child = url.appending(path: name, directoryHint: .notDirectory)
                    let childPath = child.path(percentEncoded: false)

                    // ⛔ Pure string work, before anything touches the child. For another app's
                    // sandboxed data macOS raises its dialog on the attempt, so even a `stat` is
                    // too late.
                    if ScanPolicy.isAnotherAppsData(childPath, home: home) { continue }

                    guard let subject = JunkClassifier.Subject.onDisk(child) else { continue }
                    considered += 1

                    let judgement = JunkClassifier.judge(subject, home: home, now: now)

                    // ⭐ A category is where the walk stops. Junk is junk whole.
                    if judgement.stopHere {
                        guard let identity = StorageWalk.identify(childPath) else { continue }
                        guard let bytes = measure(child,
                                                  isDirectory: subject.isDirectory,
                                                  home: home,
                                                  snapshots: held,
                                                  isCancelled: isCancelled)
                        else { continue }
                        guard !bytes.onDisk.isZero else { continue }

                        found.append(JunkClassifier.classify(
                            subject,
                            identity: identity,
                            bytes: bytes,
                            kind: StorageWalk.kind(for: name,
                                                   isDirectory: subject.isDirectory,
                                                   isPackage: false),
                            home: home,
                            now: now))
                        continue
                    }

                    guard subject.isDirectory, depth + 1 < howDeep else { continue }
                    guard ScanPolicy.descend(into: child, stayingOn: volume, home: home).isAllowed
                    else { continue }
                    // A place we will never offer to touch is not walked into looking for junk.
                    // Its size belongs to `BigFiles`, which reports it with no button at all.
                    guard ScanPolicy.refusal(for: childPath, home: home) == nil else { continue }
                    queue.append((child, depth + 1))
                }
            }
        }

        if isCancelled() { return nil }

        // ⛔ The runtimes, which no walk can reach. Reported, never offered.
        let runtimes = JunkClassifier.simulatorRuntimeItems(assetStore: assetStore)
            .map { JunkClassifier.Classified(item: $0,
                                             judgement: JunkClassifier.Judgement(
                                                verdict: .nothingCanMoveIt(
                                                    .simulatorRuntime,
                                                    why: JunkClassifier.whyARuntimeHasNoButton),
                                                arrivesTicked: false,
                                                notTickedBecause: JunkClassifier.whyARuntimeHasNoButton)) }

        let all = (found + runtimes).sorted { $0.item.bytes.onDisk > $1.item.bytes.onDisk }

        return Found(junk: all,
                     refused: refusedCount == 0
                        ? .sawEverything
                        : UnreadablePlaces(count: refusedCount, notable: refusedNotable),
                     considered: considered)
    }

    /// Both numbers for one thing. A folder is summed by `StorageWalk`, which does the snapshot
    /// arithmetic per file inside it; a file is read directly.
    ///
    /// ⚠️ **Allocated blocks, never the apparent size.** The number every other disk tool shows is
    /// wrong by 56% on this Mac and moved 11% between two runs minutes apart.
    static func measure(_ url: URL,
                        isDirectory: Bool,
                        home: URL,
                        snapshots: SnapshotStanding,
                        isCancelled: () -> Bool = { Task.isCancelled }) -> Bytes? {
        if isDirectory {
            return StorageWalk.total(of: url, home: home, snapshots: snapshots,
                                     isCancelled: isCancelled)
        }
        guard let values = try? url.resourceValues(forKeys: ScanPolicy.resourceKeys) else {
            return nil
        }
        let onDisk = SizeOnDisk(Int64(values.totalFileAllocatedSize
                                      ?? values.fileAllocatedSize ?? 0))
        return Bytes(onDisk: onDisk,
                     recoverableToday: snapshots.recoverable(
                        onDisk: onDisk, modifiedOn: values.contentModificationDate))
    }

    // MARK: - The words

    enum Says {

        /// ⚠️ The reason on the row, and it is the only reason there is: **this Mac made it and
        /// this Mac makes it again.** Not "old", not "unused", not "safe to remove".
        static let whyTheseAreOffered =
            "Each of these was written by a program on this Mac, and that program writes it again "
            + "when it needs it. Nothing of yours is on this list."

        static let nothingFound =
            "No machine junk worth showing you. Whatever this Mac has cached is small enough that "
            + "moving it would gain you nothing."

        /// What the tick actually means, said once, above the list.
        static let whyTheseArriveTicked =
            "These arrive ticked because losing one costs you a rebuild or a re-download, and "
            + "nothing else. Untick anything you would rather keep."

        static func headline(_ found: Found) -> String {
            let ticked = found.ticked
            guard !ticked.isEmpty else {
                let others = found.items
                guard let biggest = others.first else { return nothingFound }
                return "\(biggest.name) is the largest thing this Mac made, at "
                     + "\(biggest.bytes.onDisk.text) on disk."
            }
            let total = found.tickedTotal
            let count = ticked.count == 1 ? "1 thing" : "\(ticked.count) things"
            return "\(count) this Mac made and will make again, \(total.onDisk.text) on disk."
        }
    }

    // MARK: - The row

    /// The `.machineJunk` row, built from a sweep.
    ///
    /// ⚠️ Nothing here decides what may be ticked. `StorageRow.preSelected` filters the items it is
    /// given through `StorageTopic.mayArrivePreSelected` and `Item.mayBePreSelected`, both of which
    /// would have to be changed in `WellkeptCore` — in front of a reviewer — before a person's own
    /// file could arrive selected on this screen.
    static func row(_ found: Found) -> StorageRow {
        var details: [DetailPair] = []

        for category in JunkClassifier.Category.allCases {
            let mine = found.items.filter { $0.reason.hasPrefix(category.whatItIs) }
            guard !mine.isEmpty else { continue }
            details.append(DetailPair(category.label,
                                      "\(Bytes.sum(mine.map(\.bytes)).onDisk.text) — "
                                      + category.howItComesBack))
        }

        details.append(DetailPair("Things looked at", found.considered.formatted()))
        details.append(DetailPair("If a category is wrong",
                                  JunkClassifier.Category.contentAddressedCache.ifWeAreWrong))

        let unmovable = found.reportedOnly
        if !unmovable.isEmpty {
            details.append(DetailPair("Reported with no button",
                                      "\(Bytes.sum(unmovable.map(\.bytes)).onDisk.text). "
                                      + JunkClassifier.whyARuntimeHasNoButton))
        }

        return StorageRow(topic: .machineJunk,
                          headline: Says.headline(found),
                          measure: found.items.isEmpty ? nil : found.total,
                          count: found.items.isEmpty ? nil : found.items.count,
                          reason: found.items.isEmpty ? nil : Says.whyTheseAreOffered,
                          items: found.items,
                          details: details,
                          refused: found.refused)
    }
}
