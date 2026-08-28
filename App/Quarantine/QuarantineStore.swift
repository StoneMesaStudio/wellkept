// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  QuarantineStore.swift
//  Wellkept — App/Quarantine
//
//  ⭐ **Where a set-aside file goes, and why it can only ever go to one place.**
//
//  ## There is exactly one safe move, and it decides this whole file
//
//  Measured 2026-08-28: a **rename on the same volume** is atomic, instant regardless of size, and
//  preserves everything — creation date, mode, ownership, ACLs, every extended attribute, the
//  resource fork, the BSD flags, compression, sparseness, and the inode itself.
//
//  **Every copy-based alternative loses something.** `clonefile` drops ACLs. `copyfile` loses the
//  creation date and launders the download-provenance attribute, which is the very thing that tells
//  macOS a file came off the internet. And a copy is not atomic: it can half-finish, it can run the
//  disk out of space in the middle, it inflates a sparse file six thousand times over, and it splits
//  hard links so that a "moved" file is silently two files.
//
//  Every one of those hazards exists only on the cross-volume path. So:
//
//  ⚠️ **The store lives on the same volume as the file, always. Cross-volume quarantine is not
//  supported, and this file refuses it in words rather than falling back to a copy.**
//
//  That is not a limitation waiting to be lifted. A "helpful" fallback to `copyItem` would be the
//  single most damaging line anybody could add to this app, because it would work — visibly, every
//  time — while quietly discarding the metadata that makes a restore a restore.
//
//  ## Where the store actually is
//
//  - **The boot disk**, which is everything in reach this round: `~/Library/Application
//    Support/Wellkept/Quarantine`, from `StorageManifest`. Your home folder and `/Applications` are
//    both firmlinked to the same Data volume, so one store serves both.
//  - **Any other volume**, if the home folder is ever on one: a folder at that volume's own root.
//    It gets a plain-text note saying what it is, because an unexplained hidden folder at a disk
//    root is precisely the shape of the accident that started this list — Adobe's updater deleted
//    the alphabetically-first hidden folder it found there.
//
//  ## Collision-proof naming
//
//  Each item goes in **its own folder, named by the record's UUID**, and keeps its own name inside:
//
//      …/Quarantine/9F2C…-… /Old Installer.dmg
//
//  Two consequences, both wanted. **Collisions are impossible** — a fresh UUID cannot already exist,
//  so `RENAME_EXCL` can never fire on a name clash and the destination never needs a "(2)" welded on
//  it. And **the file keeps its exact name**, byte for byte, including the ones that would not
//  survive being mangled into a flat filename. A person browsing the store in Finder sees their file
//  called what they call it.

/// One place set-aside files are held, on one volume.
struct QuarantineStore: Sendable, Equatable, Identifiable {

    /// The folder itself.
    let root: URL

    /// The volume it is on — read with `statfs`, so it is the same reading the file was checked
    /// against and not a second opinion.
    let volume: VolumeReading

    var id: String { root.path(percentEncoded: false) }

    var path: String { root.path(percentEncoded: false) }

    /// Where one item goes. Its own folder, its own name.
    func destination(for name: String, id: UUID) -> URL {
        root.appending(path: id.uuidString).appending(path: name)
    }

    /// The per-item folder, which is what `restore` and `delete` remove once the file is out.
    func holder(for id: UUID) -> URL {
        root.appending(path: id.uuidString)
    }
}

// MARK: - Why a store could not be had

/// The honest reason, when there is nowhere to put something.
///
/// ⚠️ **Never resolved by copying to another disk.** See the header: a copy is a different act with
/// different consequences, and calling it a move would be a lie told by the software rather than by
/// anybody in particular.
enum StoreRefusal: Sendable, Equatable, Error {

    /// The file's volume could not be read at all.
    case volumeUnreadable(path: String)

    /// The store folder could not be made on that volume.
    case couldNotMakeAPlace(volume: String, why: String)

    /// ⚠️ The last line of defence. The store exists, but `statfs` says it is on a **different
    /// volume** from the file — which happens when something in the path to it is a symlink or a
    /// mount. Refused rather than moved, because moving here would be the cross-volume copy this
    /// whole file exists to prevent.
    case wouldCrossVolumes(from: String, to: String)

    var sentence: String {
        switch self {
        case .volumeUnreadable(let path):
            "Wellkept could not work out which disk \(path) is on, so it will not move it."
        case .couldNotMakeAPlace(let volume, let why):
            "Wellkept could not make a place on \(volume) to set this aside: \(why). It only ever "
            + "sets a file aside on the disk the file is already on — moving it to another disk "
            + "would copy it, and a copy loses things the original has."
        case .wouldCrossVolumes(let from, let to):
            "This file is on \(from) and the place Wellkept would put it is on \(to). Wellkept only "
            + "sets a file aside on its own disk, because moving between disks copies the file — and "
            + "a copy loses its creation date and where it came from."
        }
    }

    var code: String {
        switch self {
        case .volumeUnreadable:   "volumeUnreadable"
        case .couldNotMakeAPlace: "couldNotMakeAPlace"
        case .wouldCrossVolumes:  "wouldCrossVolumes"
        }
    }
}

// MARK: - Finding and making one

extension QuarantineStore {

    /// The folder name used at the root of any volume that is not the one carrying Application
    /// Support. Dot-prefixed so Finder does not show it to somebody who did not ask.
    static let rootFolderName = ".Wellkept Quarantine"

    /// The store for a file, made if it does not exist yet.
    ///
    /// ⚠️ **Ends with a `statfs` on the store itself and compares devices.** Deriving the store from
    /// the file's volume is not enough: `~/Library/Application Support` could be a symlink onto
    /// another disk, and then everything above would be correct and the result still wrong. The
    /// check costs one syscall and it is the only thing standing between a correct design and a
    /// silent copy.
    static func forItem(on volume: VolumeReading,
                        home: URL = StorageManifest.home(),
                        fileManager: FileManager = .default) -> Result<QuarantineStore, StoreRefusal> {

        let candidate = location(for: volume, home: home)

        do {
            try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
        } catch {
            return .failure(.couldNotMakeAPlace(volume: Movable.friendlyVolumeName(volume),
                                                why: error.localizedDescription))
        }

        guard let storeVolume = Movable.volume(of: candidate.path(percentEncoded: false)) else {
            return .failure(.volumeUnreadable(path: candidate.path(percentEncoded: false)))
        }

        guard storeVolume.isSameVolume(as: volume) else {
            return .failure(.wouldCrossVolumes(from: Movable.friendlyVolumeName(volume),
                                               to: Movable.friendlyVolumeName(storeVolume)))
        }

        if candidate != StorageManifest.quarantineDirectory(home: home) {
            leaveANote(in: candidate, fileManager: fileManager)
        }

        return .success(QuarantineStore(root: candidate, volume: storeVolume))
    }

    /// Where the store for a volume belongs. Pure — makes nothing, reads nothing.
    ///
    /// Separated from `forItem` so the decision can be tested without a disk.
    static func location(for volume: VolumeReading, home: URL = StorageManifest.home()) -> URL {
        let support = StorageManifest.quarantineDirectory(home: home)
        if let supportVolume = Movable.volume(of: home.path(percentEncoded: false)),
           supportVolume.isSameVolume(as: volume) {
            return support
        }
        return URL(filePath: volume.mountPoint).appending(path: rootFolderName)
    }

    // ⚠️ **There is deliberately no `all()` that walks every mounted volume looking for stores.**
    // It existed, nothing called it, and its own comment named two callers that did not exist —
    // which is how a function that walks disks looking for folders by name gets trusted by somebody
    // later. Every store that matters is already named by `storeRoot` on the records themselves, so
    // the list comes from the ledger, which is a statement of what Wellkept actually did. Finding
    // folders by name is the failure mode on the list; reading the record is not.

    /// A plain sentence in a plain file, for a folder somebody may find on a disk root with no idea
    /// what put it there.
    ///
    /// ⚠️ Written **only** outside Application Support. Inside it the uninstaller already asks about
    /// the quarantine by name, and a note there would be a file that never goes away — it would keep
    /// `tidyEmptyFolders` from ever clearing an emptied store, and litter that outlives the app is
    /// the thing that folder policy exists to prevent.
    private static func leaveANote(in store: URL, fileManager: FileManager) {
        let note = store.appending(path: "What is this folder.txt")
        guard !fileManager.fileExists(atPath: note.path(percentEncoded: false)) else { return }
        let words = """
            These are files Wellkept set aside for you on this disk.

            Nothing here has been deleted. Each file is in a folder of its own, under the name it \
            had, exactly as it was. Open Wellkept and go to Storage to put any of them back, or to \
            remove them for good.

            They are on this disk and not on your startup disk because Wellkept only ever sets a \
            file aside on the disk it already lives on. Moving a file between disks copies it, and \
            a copy loses things the original has.

            If Wellkept is gone and you want these files back, drag them out. They are ordinary \
            files in ordinary folders.
            """
        try? Data(words.utf8).write(to: note, options: .atomic)
    }
}
