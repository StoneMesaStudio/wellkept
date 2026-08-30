import Foundation

//  Storage.swift
//  WellkeptCore
//
//  **The words the Storage section agrees on, and the two numbers it is not allowed to confuse.**
//
//  Five agents compile against this file without seeing each other. Nothing here imports SwiftUI,
//  AppKit or Darwin: the vocabulary has to be testable without a window and without a disk, and a
//  scanner has to be replaceable without touching a view.
//
//  Same shape as `Hardware.swift`, `Security.swift` and `Apps.swift` — a fixed row set that never
//  re-sorts, a facts block that cannot carry a verdict, one row up to Overview. A person who has
//  learned one of those screens has learned this one.
//
//  ## ⭐ The law this file exists to keep
//
//  **Machine junk regenerates and may be pre-selected. A person's own files are revealed, sized and
//  sorted, and are NEVER pre-selected and never swept.** That single distinction is `Origin`, and
//  every ceremony, default and button in the section reads it. Nothing else in the section is
//  allowed to decide it.
//
//  ## ⚠️ The measurements this file is built around
//
//  Taken by hand on an M3 running macOS 26.6.2 on 2026-08-28, read-only. The whole survey is in
//  `STORAGE-QUESTIONS.md`; these are the findings that shaped the types below.
//
//  - **"How big is it" and "what would I get back" are different true numbers, up to 150× apart.**
//    one measured media folder reads 80 GB by name, **14.8 GB on disk**, and **0.5 GB comes back
//    today**. So there is no type here called `size`. There are two, they are different types, and
//    the compiler will not add one to the other. See `SizeOnDisk`, `Recoverable`, `Bytes`.
//  - **Free space has two answers, 68 GB apart.** Measured here: 109.8 GB actually free, 177.9 GB
//    printed by Finder. Finder's figure counts room macOS believes it *could* make under pressure —
//    a promise, not a count. Free 12 GB and it does not rise by 12. **It is not a number arithmetic
//    works on**, so it is a type with a private stored property and exactly one permitted
//    subtraction. See `FinderFigure`.
//  - **One stuck local snapshot, dated 25 August, means deleting anything older returns zero
//    bytes.** Recoverable-today therefore depends on a file's age, and the dependency is not a
//    curve — it is a line. See `SnapshotStanding.recoverable(onDisk:modifiedOn:)`.
//  - **15,593 files in the home folder look like 72 GB and occupy nothing** — they are in iCloud.
//    Sorting "largest" on the number a file *claims* puts files that are not here at the top. The
//    apparent figure appears in exactly one type in this file and is never printed as a size we
//    stand behind. See `CloudHolding`.
//  - **Without Full Disk Access, 54 folders in the home directory cannot be read**, including the
//    Trash and the Photos library — usually the two biggest wins. See `UnreadablePlaces`: it has no
//    way to express a zero.
//  - **The numbers will never add up.** Our scan totalled 244 GB of live files; macOS says 357 GB
//    is used. Every competitor invents an "Other" slice. `MeasuredGap` is computed inside
//    `StorageReport`'s initialiser from figures it already holds, so there is no argument to leave
//    out and no code path that produces a report without it.
//  - **"Last opened" is blank for 61% of large files**, and 123 files in one sample share a single
//    timestamp stamped by a batch job. It is a fact on a row. It is never a finding, and the
//    sentence "you have not opened this in seven years" is not in this app.
//  - **Duplicates are a tidiness finding, not a space finding**, and on APFS two "copies" may be
//    one clone sharing blocks — deleting one returns nothing, and such a pair is not a duplicate.
//    **There is no honest way to pick the original, so we never choose.**
//
//  ## The four rules that shape every type below
//
//  1. **Two numbers, never one.** `StorageRow.measure` is a `Bytes`, which cannot be built from a
//     single figure. A row that knows only how big something is cannot be constructed.
//  2. **Never report zero because we could not look.** A place we were refused becomes an
//     `UnreadablePlaces`, in the house sentence, and the row drops its figure.
//  3. **Origin decides the ceremony, and `.yours` is the default.** A classifier that is unsure
//     produces a person's own file, which is the branch where nothing is pre-ticked and nothing is
//     swept.
//  4. **Quarantine returns nothing.** No type here has a property that says space was recovered
//     after setting something aside, because it never is. What comes back is measured after a real
//     delete, by `App/Storage/FreeSpace.swift`, and reported as what was measured.

// MARK: - The five rows

/// The five things Storage reports, in the order they are drawn.
///
/// ⚠️ **`allCases` IS the row order, and this list never sorts.** Raw values are storage — they go
/// into the check history, the one record in this app that cannot be rebuilt — and the labels are
/// English. The two are allowed to drift apart for ever.
///
/// ## Why this order
///
/// It is the order of the questions a person actually asks, and it puts the press that needs no
/// judgement before the press that does.
///
/// 1. **What is using the space** — the question the section is named for. The shape of the disk,
///    before anything is offered. Nothing here is ticked, because nothing here is a proposal.
/// 2. **Machine junk** — the only list that may arrive pre-selected, because everything on it
///    regenerates. Second so that the one-press batch is finished before any judgement is asked
///    for. If it were below the person's own files, the first thing anyone met on this screen would
///    be a list of their own documents beside a button.
/// 3. **Your own large files** — revealed, sized, sorted. Third because it is the first place a
///    decision is required, and one is required per file.
/// 4. **Duplicates** — last of the findings because it is the smallest prize and the most work: on
///    this Mac, 387 MB across 633 separate judgement calls in one folder. It is tidiness, not
///    space, and it is never sold as space.
/// 5. **What is set aside** — the consequence of rows 2 and 3, and **the only place on this screen
///    where space actually comes back**. Last because that is where the sequence ends: set aside,
///    nothing changes size, empty, the room appears.
public enum StorageTopic: String, CaseIterable, Sendable, Identifiable, Codable, Hashable {

    /// Where the space went, largest first. A picture, not a proposal.
    case whatIsUsingSpace

    /// Files the machine made and will make again: caches an app rebuilds, logs, build output,
    /// downloaded installers, old updates.
    ///
    /// ⚠️ **This is the only topic that may arrive with anything ticked**, and even here the
    /// classifier decides per item rather than by location. A 1.3 GB audiobook is sitting in
    /// `~/Library/Caches` on this Mac right now, filed under a store number. Any cleaner that
    /// treats "Caches" as a category deletes somebody's audiobooks.
    case machineJunk

    /// The person's own large files and folders. Revealed and sorted. **Never ticked, never swept.**
    case yourOwnFiles

    /// Byte-identical copies, grouped. A tidiness finding.
    ///
    /// ⚠️ Two APFS clones are one file sharing blocks: deleting one returns nothing, and the pair
    /// is not a duplicate. And we never nominate an original — four real pairs on this Mac each
    /// defeat a different rule, including a photo whose dates a past copy destroyed, so "keep the
    /// oldest" picks the wrong one.
    case duplicates

    /// What is in quarantine now, how old the oldest is, and the one button that ends the sequence.
    ///
    /// ⚠️ **The only row on this screen where space actually comes back**, and it comes back at the
    /// second press, not the first. Setting 391 MB across 100,000 files aside moved free space by
    /// −8 KiB: a same-volume rename re-points an inode and no bytes go anywhere.
    case setAside

    public var id: String { rawValue }

    /// The words on the row. Named for the question, not for the mechanism.
    public var label: String {
        switch self {
        case .whatIsUsingSpace: "What is using the space"
        case .machineJunk:      "Machine junk"
        case .yourOwnFiles:     "Your own large files"
        case .duplicates:       "Duplicates"
        case .setAside:         "What is set aside"
        }
    }

    /// One plain sentence saying what the row is, shown once, on the row.
    public var explanation: String {
        switch self {
        case .whatIsUsingSpace:
            "Where the space on this Mac has gone, largest first."
        case .machineJunk:
            "Files this Mac made and will make again. Setting these aside costs you nothing."
        case .yourOwnFiles:
            "Your own biggest files and folders. Nothing here is chosen for you."
        case .duplicates:
            "Files that are byte-for-byte the same. This is tidiness, not space."
        case .setAside:
            "Everything waiting in quarantine, and how long it has left."
        }
    }

    /// ⭐ **Whether a list on this row may arrive with anything already ticked.**
    ///
    /// True for exactly one topic, and the property exists so that no view has to remember which.
    /// A screen that reads this cannot pre-select a person's own files by accident, and a screen
    /// that ignores it is doing something a reviewer can see in one line.
    public var mayArrivePreSelected: Bool { self == .machineJunk }

    /// Which of the two ceremonies this row uses. See `Ceremony`.
    public var ceremony: Ceremony {
        switch self {
        case .machineJunk:  .batch
        default:            .oneAtATime
        }
    }

    /// Draw order, so two lists of rows read the same way twice.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - ⭐ The two numbers

/// **How much room a thing takes on the disk right now.** Allocated blocks, not the size in its
/// name.
///
/// ⚠️ **Apparent size — the number every other disk tool shows — is wrong by 56% on this Mac, and
/// unstable: it swung 11% between two runs minutes apart, where this reading moved 0.2%.** The
/// difference is compression, sparse files, clones sharing blocks, and files that are in iCloud and
/// not here at all. There is no initialiser on this type that takes an apparent size.
///
/// It is `AdditiveArithmetic` so a scan can total a folder, and it is deliberately **not**
/// `ExpressibleByIntegerLiteral`: `let big: SizeOnDisk = 80_000_000_000` will not compile, and the
/// bare `80_000_000_000` in somebody's head has to be given a meaning before it becomes a value.
public struct SizeOnDisk: Sendable, Hashable, Codable, Comparable, AdditiveArithmetic {

    public let bytes: Int64

    /// Negative sizes are not a thing. A caller handing one in has subtracted in the wrong
    /// direction, and a screen showing "−4.2 GB on disk" is a bug wearing a number.
    public init(_ bytes: Int64) { self.bytes = max(0, bytes) }

    public static let zero = SizeOnDisk(0)

    public static func + (a: SizeOnDisk, b: SizeOnDisk) -> SizeOnDisk { SizeOnDisk(a.bytes + b.bytes) }
    public static func - (a: SizeOnDisk, b: SizeOnDisk) -> SizeOnDisk { SizeOnDisk(a.bytes - b.bytes) }
    public static func < (a: SizeOnDisk, b: SizeOnDisk) -> Bool { a.bytes < b.bytes }

    /// The figure alone, formatted for a person: "14.8 GB".
    public var text: String { bytes.formatted(.byteCount(style: .file)) }

    /// The figure with its meaning attached, for anywhere the two numbers appear together.
    public var phrase: String { "\(text) on disk" }

    public var isZero: Bool { bytes == 0 }
}

/// **What deleting a thing would actually give back today.**
///
/// ⚠️ **This is a different number from `SizeOnDisk`, and on this Mac it is up to 150× smaller.**
/// one measured media folder occupies 14.8 GB and returns 0.5 GB, because a local Time Machine
/// snapshot dated 25 August still references the blocks of everything written before it. Printing
/// the first number where the second belongs is the single most misleading thing this section could
/// do, and it is why these are two types rather than two properties on one.
///
/// The only way to make one is `SnapshotStanding.recoverable(onDisk:modifiedOn:)` or the two named
/// constructors below, each of which states its assumption in its name.
public struct Recoverable: Sendable, Hashable, Codable, Comparable, AdditiveArithmetic {

    public let bytes: Int64

    /// Deliberately not public. A `Recoverable` is a **conclusion**, and it is reached in one place.
    init(unchecked bytes: Int64) { self.bytes = max(0, bytes) }

    public static let zero = Recoverable(unchecked: 0)

    /// Nothing comes back — the blocks are held by a snapshot, or the thing is not on this Mac.
    public static let nothing = Recoverable(unchecked: 0)

    /// All of it comes back. Only correct where there is no snapshot older than the file.
    public static func all(of size: SizeOnDisk) -> Recoverable { Recoverable(unchecked: size.bytes) }

    public static func + (a: Recoverable, b: Recoverable) -> Recoverable { Recoverable(unchecked: a.bytes + b.bytes) }
    public static func - (a: Recoverable, b: Recoverable) -> Recoverable { Recoverable(unchecked: a.bytes - b.bytes) }
    public static func < (a: Recoverable, b: Recoverable) -> Bool { a.bytes < b.bytes }

    /// The figure alone: "0.5 GB".
    public var text: String { bytes.formatted(.byteCount(style: .file)) }

    /// The figure as a sentence fragment, which is how it should nearly always appear. A bare
    /// "0.5 GB" beside a bare "14.8 GB" is two numbers a person has to guess between.
    public var phrase: String {
        isZero ? "nothing comes back today" : "\(text) comes back today"
    }

    public var isZero: Bool { bytes == 0 }
}

/// **The pair.** How big it is, and what you would get back — carried together, so that a row
/// cannot be built from one of them.
///
/// Every measure on every Storage row is one of these. `StorageRow.measure` has no other type, and
/// there is no initialiser here that takes a single figure, which is what stops a later screen
/// printing "14.8 GB" beside a button that would return half a gigabyte.
public struct Bytes: Sendable, Hashable, Codable {

    /// What it occupies now.
    public let onDisk: SizeOnDisk

    /// What deleting it would give back today. Never larger than `onDisk`.
    public let recoverableToday: Recoverable

    /// Clamped rather than trapped: a scanner that has summed a folder slightly differently from
    /// the way it summed the snapshot arithmetic should print a conservative number, not crash on
    /// somebody's Mac. The clamp is toward the smaller promise, always.
    public init(onDisk: SizeOnDisk, recoverableToday: Recoverable) {
        self.onDisk = onDisk
        self.recoverableToday = Recoverable(unchecked: min(recoverableToday.bytes, onDisk.bytes))
    }

    public static let zero = Bytes(onDisk: .zero, recoverableToday: .nothing)

    /// Every byte comes back. Correct only where nothing older is holding the blocks — a Mac with
    /// no local snapshots, or a file written after the newest one.
    public static func allOfIt(_ onDisk: SizeOnDisk) -> Bytes {
        Bytes(onDisk: onDisk, recoverableToday: .all(of: onDisk))
    }

    /// It occupies room and returns none of it today.
    public static func heldBackBySnapshot(_ onDisk: SizeOnDisk) -> Bytes {
        Bytes(onDisk: onDisk, recoverableToday: .nothing)
    }

    public static func + (a: Bytes, b: Bytes) -> Bytes {
        Bytes(onDisk: a.onDisk + b.onDisk, recoverableToday: a.recoverableToday + b.recoverableToday)
    }

    public static func sum(_ parts: [Bytes]) -> Bytes { parts.reduce(.zero, +) }

    /// ⚠️ **The two numbers agree only when nothing is holding the blocks.** Where they differ, a
    /// row that prints one of them is lying by omission, so `text` prints both.
    public var agree: Bool { onDisk.bytes == recoverableToday.bytes }

    /// What a row shows. One figure where the two agree, both where they do not.
    public var text: String {
        agree ? onDisk.text : "\(onDisk.text) — \(recoverableToday.phrase)"
    }

    /// The long form, for a detail line or a sheet.
    public var sentence: String {
        agree
            ? "\(onDisk.phrase), and all of it comes back."
            : "\(onDisk.phrase). Delete it today and \(recoverableToday.text) comes back — the rest is held by a snapshot."
    }

    public var isZero: Bool { onDisk.isZero }
}

/// **Finder's free-space figure**, kept in a type that cannot do arithmetic.
///
/// ⚠️ Measured 2026-08-28: Finder says 177.9 GB free where 109.8 GB is actually free. Finder is not
/// wrong — it is answering a different question. `volumeAvailableCapacityForImportantUsage` counts
/// room macOS believes it *could* make under pressure: iCloud files it would evict, caches it would
/// purge, snapshots it would thin. **It is a promise, not a count, and it does not behave like a
/// number.** Delete 12 GB and it does not rise by 12, because the purgeable pool moves underneath.
///
/// So the byte count is `private`. There is no `+`, no `<`, and no way out except `text` and one
/// named subtraction. The ruling on 2026-08-28: the real number leads, this one is printed
/// underneath, and one line says what the difference is. We are not contradicting Finder, we are
/// explaining it — which is the one thing no other tool on this Mac does.
public struct FinderFigure: Sendable, Hashable, Codable {

    private let bytes: Int64

    public init(_ bytes: Int64) { self.bytes = max(0, bytes) }

    /// The figure, formatted. The only way to see it.
    public var text: String { bytes.formatted(.byteCount(style: .file)) }

    /// **The one permitted subtraction**, named so that its result cannot be mistaken for a
    /// quantity of anything. The answer is how much of Finder's figure is a promise rather than
    /// room: 68.1 GB on this Mac.
    public func promiseBeyond(_ real: SizeOnDisk) -> SizeOnDisk {
        SizeOnDisk(bytes - real.bytes)
    }

    /// Whether it is worth printing at all. Where the two agree there is nothing to explain, and a
    /// second identical number on the screen is clutter.
    public func differsFrom(_ real: SizeOnDisk) -> Bool {
        !promiseBeyond(real).isZero
    }
}

// MARK: - ⭐ Junk versus content

/// **Whose file this is.** The one flag that decides the entire ceremony.
///
/// Machine junk regenerates: an app rebuilds its cache, Xcode rebuilds its derived data, a
/// downloaded installer can be downloaded again. Losing it costs time, and only once. A person's
/// own files cost what they cost, and nobody but the person can price them.
///
/// ⚠️ **`.yours` is the default in every initialiser here, and a classifier that is not sure must
/// return it.** Every documented catastrophe in this field shares one shape: something was
/// classified as disposable by inference. Adobe's updater deleted the alphabetically-first hidden
/// folder at the disk root. Pearcleaner's orphan detector matched vendor names and flagged live
/// data. Apple Music deleted 122 GB of local originals because a cloud copy was inferred. And on
/// one measured Mac, `~/Library/Application Support/Herd` has no app, no receipt, no Spotlight
/// entry and has not been touched in four and a half months — every orphan heuristic fires at once,
/// and it is a working PHP install.
///
/// **Identity, never absence of evidence. Location is never evidence.**
public enum Origin: String, Sendable, Codable, CaseIterable, Identifiable {

    /// This Mac made it and this Mac will make it again.
    case machineJunk

    /// The person's own. **The default whenever the answer is not certain.**
    case yours

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .machineJunk: "Made by this Mac"
        case .yours:       "Yours"
        }
    }

    /// ⭐ **Whether a list may arrive with this ticked.** Read this rather than re-deriving it.
    public var mayBePreSelected: Bool { self == .machineJunk }

    /// ⭐ **Whether a batch sweep may include this. Never true for a person's own files.**
    public var maySweep: Bool { self == .machineJunk }

    /// Which ceremony a press on this uses.
    public var ceremony: Ceremony {
        switch self {
        case .machineJunk: .batch
        case .yours:       .oneAtATime
        }
    }
}

/// **The two ceremonies, 2026-08-28: same four verbs, different weight.**
///
/// > *"Junk: tick a batch, one press, done, and the row afterwards says 13 GB set aside. A person's
/// > own file: one at a time, never pre-ticked, with a sheet stating the arithmetic before the
/// > press, and both buttons on that sheet."*
public enum Ceremony: String, Sendable, Codable, CaseIterable, Identifiable {

    /// Tick a batch, one press, done. Afterwards the row says how much is set aside.
    case batch

    /// One at a time, never pre-ticked, with a sheet that states the arithmetic before the press.
    case oneAtATime

    public var id: String { rawValue }

    /// Whether more than one thing may be acted on in a single press.
    public var allowsMultipleSelection: Bool { self == .batch }

    /// Whether a sheet stating the arithmetic must appear before the press.
    ///
    /// ⚠️ This is not a confirmation dialog and it is not a scare. It exists because the arithmetic
    /// is genuinely counter-intuitive: setting a 12 GB video aside does not make the Mac emptier
    /// today, and a person who does not know that will check About This Mac and conclude the app is
    /// broken. The sentence is in `Sheet.arithmetic(for:)`.
    public var statesTheArithmeticFirst: Bool { self == .oneAtATime }
}

// MARK: - Identity

/// **What a thing is, as opposed to what it is called.**
///
/// ⚠️ A path is not an identity here. This filesystem folds case *and* Unicode normalisation:
/// `CaseTest.txt` is found at `casetest.TXT`, and an NFD spelling opens the NFC file. A record
/// holding only a path is a record that can act on a different file than the one a person saw.
///
/// The same three readings as `FileIdentity` in `App/Quarantine/Ledger.swift`, which is where the
/// engine's own copy lives. They are separate types because `WellkeptCore` compiles without Darwin
/// and the engine's copy is built straight from a `statfs`; the app layer bridges between them. If
/// a third copy of these three fields ever appears, that is the moment to move one of them.
public struct ItemIdentity: Sendable, Hashable, Codable {

    /// The volume's own UUID, when it has one. Survives unmounting, remounting and renaming.
    public let volumeUUID: String?

    /// `f_mntfromname`. ⚠️ The only reading that separates the sealed System volume from the Data
    /// volume — they share a device number and a display name, even for `/System/Library`.
    public let volumeDevice: String

    /// `st_ino`. Unchanged by a same-volume rename, which is the only move the engine makes.
    public let inode: UInt64

    public init(volumeUUID: String?, volumeDevice: String, inode: UInt64) {
        self.volumeUUID = volumeUUID
        self.volumeDevice = volumeDevice
        self.inode = inode
    }

    /// ⚠️ **An inode number alone is not an identity.** They are handed out per volume and they
    /// start small, so a freshly made file on a plugged-in drive routinely carries the same number
    /// as one in the home folder. The volume has to be part of every comparison.
    ///
    /// The UUID is preferred and the device is only the fallback, because devices renumber:
    /// `/dev/disk3s5` can come back as `/dev/disk4s5` after a reboot with a drive plugged in.
    public func isTheSameThing(as other: ItemIdentity) -> Bool {
        guard inode == other.inode else { return false }
        if let mine = volumeUUID, let theirs = other.volumeUUID { return mine == theirs }
        return volumeDevice == other.volumeDevice
    }
}

// MARK: - What kind of thing

/// What a thing structurally is. Deliberately short, and deliberately **not** a taxonomy of
/// purpose: "cache", "log" and "installer" are judgements about a file, and judgements live in
/// `Origin` and in the classifier, where they can be argued with.
public enum ItemKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case file
    case folder
    /// A bundle the Finder shows as one thing — an app, a Photos library, a Logic project.
    case bundle
    /// A `.dmg` or a `.sparsebundle`. Called out because the 30 GB of iOS simulator runtimes on
    /// this Mac are read-only images that cannot be set aside at all.
    case diskImage
    /// A symbolic link. Moving one moves the link, never its target.
    case link

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .file:      "File"
        case .folder:    "Folder"
        case .bundle:    "Package"
        case .diskImage: "Disk image"
        case .link:      "Shortcut"
        }
    }
}

// MARK: - iCloud

/// Whether the bytes are actually on this Mac, and what a person needs to be told before pressing
/// anything.
///
/// ⚠️ **15,593 files in this home folder look like 72 GB and occupy nothing** — they are
/// placeholders for files that live in iCloud. A "largest first" list built on what a file claims
/// puts things that are not here at the top of the screen.
public enum CloudStanding: String, Sendable, Codable, CaseIterable, Identifiable {

    /// Here, and nowhere else. Deleting it deletes it.
    case onThisMac

    /// `SF_DATALESS` — a placeholder. The bytes are in iCloud and **occupy nothing here**, so there
    /// is no space to be had from it and no button on its row.
    case inTheCloudOnly

    /// Downloaded here **and** synced. It occupies real room, and setting it aside takes it off the
    /// person's other devices for the whole thirty days while still occupying that room here.
    case bothPlaces

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .onThisMac:      "On this Mac"
        case .inTheCloudOnly: "In iCloud, not on this Mac"
        case .bothPlaces:     "On this Mac and in iCloud"
        }
    }

    /// Whether it is using room here at all.
    public var occupiesSpaceHere: Bool { self != .inTheCloudOnly }

    /// **The settled line, 2026-08-28, used verbatim or not at all.**
    ///
    /// The engine's copy is `Movable.iCloudWarning`; this one is for a row that has not been
    /// through the engine yet. They must stay identical, and `Tools/AppTests` asserts it.
    public static let alsoRemovesItFromYourDevices = "This also removes it from your iPhone and iPad."

    /// The one line to show before a press, or `nil` where there is nothing extra to say.
    public var warning: String? {
        self == .bothPlaces ? Self.alsoRemovesItFromYourDevices : nil
    }
}

// MARK: - Can it be set aside at all

/// Whether the quarantine engine can hold this, decided **before** a button is drawn.
///
/// ⚠️ **30 GB of iOS simulator runtimes on this Mac cannot be quarantined at all** — they are
/// root-owned, read-only disk images, so no thirty-day undo is possible for them. They are reported
/// and no button is offered. A button that fails when pressed is worse than no button: it teaches a
/// person that this app's buttons are decorative.
public struct Handling: Sendable, Hashable, Codable {

    public enum Standing: String, Sendable, Codable, CaseIterable {
        /// The engine checked, and it can hold this.
        case canBeSetAside
        /// The engine checked, and it cannot. `why` says so in words.
        case cannotBeSetAside
        /// Not checked yet. A full check is a syscall per item and a scan finds thousands, so it
        /// runs at press time for most rows.
        case notCheckedYet
    }

    public let standing: Standing

    /// The engine's own sentence, from `MoveRefusal.sentence`. Present whenever the answer is no.
    public let why: String?

    public init(standing: Standing, why: String? = nil) {
        self.standing = standing
        self.why = standing == .cannotBeSetAside ? (why ?? "This cannot be set aside.") : nil
    }

    public static let canBeSetAside = Handling(standing: .canBeSetAside)
    public static let notCheckedYet = Handling(standing: .notCheckedYet)
    public static func cannot(_ why: String) -> Handling {
        Handling(standing: .cannotBeSetAside, why: why)
    }

    /// ⚠️ **Whether a row may carry a button at all.** `.notCheckedYet` says yes, because the check
    /// runs when the button is pressed and refuses in place; `.cannotBeSetAside` says no, because
    /// the answer is already known and it is no.
    public var mayOfferAButton: Bool { standing != .cannotBeSetAside }
}

// MARK: - One thing found

/// One thing the scan found: what it is, where it is, how big, what would come back, and — the
/// field everything else reads — **whose it is**.
public struct Item: Sendable, Hashable, Codable, Identifiable {

    /// ⭐ Volume plus inode. See `ItemIdentity`: a path alone is not an identity on this filesystem.
    public let identity: ItemIdentity

    /// Where it is, **as the filesystem itself spells it** — from `F_GETPATH`, not from the
    /// caller's typing. Shown on the row and used to reveal it in the Finder. It is not the
    /// identity, and nothing acts on it without checking `identity` first.
    public let path: String

    /// The last component, for the row's heading.
    public let name: String

    /// ⭐ Both numbers. See `Bytes`.
    public let bytes: Bytes

    public let kind: ItemKind

    /// ⭐ **Junk or the person's own.** Decides the ceremony, the pre-selection and the sweep.
    public let origin: Origin

    public let cloudStanding: CloudStanding

    /// Whether the engine can hold it, and why not where it cannot.
    public let handling: Handling

    /// Last changed. The date the recoverable arithmetic is done against.
    public let modifiedOn: Date?

    /// ⚠️ **A fact on a row. Never a finding.** It is blank for 61% of large files on one real Mac,
    /// and 123 files in one sample share a single timestamp a batch job stamped on them. The
    /// sentence "you have not opened this in seven years" is not in this app, at any threshold.
    ///
    /// ⚠️ **This is `kMDItemLastUsedDate`, never the filesystem's access time.** Our own research
    /// scan rewrote 2,012 access times by reading the files, which is exactly why that field can
    /// never be evidence of anything here.
    public let lastOpenedOn: Date?

    /// **Why this is on the screen**, in plain words. Always present, always shown on the row,
    /// never behind a disclosure. A listed item with no reason is an accusation; the reason is what
    /// lets a person disagree with us.
    public let reason: String

    public var id: String { "\(identity.volumeDevice)#\(identity.inode)" }

    /// ⚠️ **`origin` defaults to `.yours`.** A classifier that is unsure, a test fixture written in
    /// a hurry, and a future scanner that forgets the argument all produce a file that is never
    /// pre-ticked and never swept. That is the safe direction, and it is the default on purpose.
    public init(identity: ItemIdentity,
                path: String,
                name: String? = nil,
                bytes: Bytes,
                kind: ItemKind,
                origin: Origin = .yours,
                cloudStanding: CloudStanding = .onThisMac,
                handling: Handling = .notCheckedYet,
                modifiedOn: Date? = nil,
                lastOpenedOn: Date? = nil,
                reason: String) {
        self.identity = identity
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.bytes = bytes
        self.kind = kind
        self.origin = origin
        self.cloudStanding = cloudStanding
        self.handling = handling
        self.modifiedOn = modifiedOn
        self.lastOpenedOn = lastOpenedOn
        self.reason = reason
    }

    /// ⭐ Whether this may arrive with its checkbox ticked. **Both halves must agree**: it has to be
    /// machine junk, and it has to be something the engine can actually hold.
    public var mayBePreSelected: Bool {
        origin.mayBePreSelected && handling.mayOfferAButton && cloudStanding.occupiesSpaceHere
    }

    /// Which ceremony a press on this uses.
    public var ceremony: Ceremony { origin.ceremony }

    /// The one warning line before a press, if there is one.
    public var warning: String? { cloudStanding.warning }

    /// The plain facts for the row, in order, each already formatted. Any that could not be read is
    /// absent rather than rendered as a dash — a blank is not a value.
    public var lineFacts: [String] {
        var facts: [String] = [kind.label, bytes.text]
        if cloudStanding != .onThisMac { facts.append(cloudStanding.label) }
        if let modifiedOn {
            facts.append("Last changed \(modifiedOn.formatted(date: .abbreviated, time: .omitted))")
        }
        // ⚠️ Stated flatly, with no adjective and no elapsed time. See the note on `lastOpenedOn`.
        if let lastOpenedOn {
            facts.append("Last opened \(lastOpenedOn.formatted(date: .abbreviated, time: .omitted))")
        }
        return facts
    }
}

// MARK: - The snapshot, and the arithmetic that hangs off it

/// One local Time Machine snapshot.
public struct LocalSnapshot: Sendable, Hashable, Codable, Identifiable {
    /// `com.apple.TimeMachine.2026-08-25-062503.local`
    public let name: String
    public let takenOn: Date

    public var id: String { name }

    public init(name: String, takenOn: Date) {
        self.name = name
        self.takenOn = takenOn
    }
}

/// **What the local snapshots are holding, and the arithmetic every recoverable figure comes from.**
///
/// ⚠️ **This is the reason Wellkept's numbers look pessimistic beside everyone else's, and it is
/// the reason they are right.** Time Machine could not reach the backup drive, so one snapshot
/// from 25 August is stuck. Deleting any file older than that returns **zero bytes** — the blocks
/// are still referenced. Measured on one real Mac: a file written today returns 98% of itself,
/// yesterday 74%, May 12%, a July video folder 3.6%.
///
/// ## The model, and why it is a line rather than a curve
///
/// Those four percentages are folders, and each is a mix of files. **Per file the rule is binary:**
/// a file whose blocks were written after the oldest snapshot is not referenced by it and comes
/// back whole; a file written before it is referenced and comes back not at all. Sum that over a
/// folder and you get 98%, 74%, 12% and 3.6% without a curve anywhere. The simple rule explains
/// every measurement, so it is the rule.
///
/// It errs toward the smaller promise in all three unknowns — no reading, no date, no snapshot
/// state — because a figure that turns out larger is a pleasant surprise and a figure that turns
/// out smaller is the app caught lying.
public struct SnapshotStanding: Sendable, Hashable, Codable {

    /// Every local snapshot, newest last. Empty means there are none.
    public let snapshots: [LocalSnapshot]

    /// `false` when the listing itself failed — a different thing from "there are none", and the
    /// difference decides whether we may promise anything at all.
    public let wasRead: Bool

    public init(snapshots: [LocalSnapshot], wasRead: Bool = true) {
        self.snapshots = snapshots.sorted { $0.takenOn < $1.takenOn }
        self.wasRead = wasRead
    }

    /// Nothing is holding anything: no snapshots exist. Every delete returns the whole file.
    public static let none = SnapshotStanding(snapshots: [], wasRead: true)

    /// The listing failed. Nothing may be promised — see `recoverable(onDisk:modifiedOn:)`.
    public static let couldNotBeRead = SnapshotStanding(snapshots: [], wasRead: false)

    public var oldest: LocalSnapshot? { snapshots.first }
    public var newest: LocalSnapshot? { snapshots.last }
    public var isEmpty: Bool { snapshots.isEmpty }

    /// How many days old the oldest one is, as of `now`.
    public func ageInDays(now: Date = Date()) -> Int? {
        guard let oldest else { return nil }
        return Calendar.current.dateComponents([.day], from: oldest.takenOn, to: now).day
    }

    /// ⚠️ **A snapshot older than a week means Time Machine has not been able to run.** macOS thins
    /// local snapshots on its own within about 24 hours when backups are working; one that is still
    /// there a week later is stuck, and everything on the disk older than it is unreturnable.
    ///
    /// Seven days is a judgement, not a measurement, and it is named here so it can be argued with
    /// in one place.
    public static let stuckAfterDays = 7

    public func isStuck(now: Date = Date()) -> Bool {
        guard let days = ageInDays(now: now) else { return false }
        return days >= Self.stuckAfterDays
    }

    /// ⭐ **The whole arithmetic, in one function.**
    ///
    /// - A file changed **after** the oldest snapshot: no snapshot references its blocks, so all of
    ///   it comes back.
    /// - A file changed **before** it: the snapshot holds those blocks, so none of it comes back
    ///   while the snapshot exists.
    /// - **No date** — we could not read when it changed: nothing is promised. Under-promising a
    ///   figure is recoverable; over-promising it is the app caught lying.
    /// - **The listing failed**: nothing is promised, for the same reason.
    public func recoverable(onDisk: SizeOnDisk, modifiedOn: Date?) -> Recoverable {
        guard wasRead else { return .nothing }
        guard let oldest else { return .all(of: onDisk) }
        guard let modifiedOn else { return .nothing }
        return modifiedOn > oldest.takenOn ? .all(of: onDisk) : .nothing
    }

    /// The pair, built in one step, which is how a scanner should build every one of them.
    public func bytes(onDisk: SizeOnDisk, modifiedOn: Date?) -> Bytes {
        Bytes(onDisk: onDisk, recoverableToday: recoverable(onDisk: onDisk, modifiedOn: modifiedOn))
    }

    /// ⚠️ **The ruling, 2026-08-28: Storage says this out loud, on the face, as one flat line
    /// with no button.** Backup does not exist yet, and there is nothing here for a person to
    /// press — but it is the reason almost nothing on this screen returns space, so leaving it out
    /// would make our own numbers look broken.
    ///
    /// `nil` when there is nothing to say: no snapshots, or a recent one that macOS will thin by
    /// itself.
    public func line(now: Date = Date()) -> String? {
        guard wasRead else {
            return "We could not tell whether Time Machine is holding space on this disk, so every figure below is the smaller of the two possible answers."
        }
        guard let oldest, isStuck(now: now) else { return nil }
        let date = oldest.takenOn.formatted(date: .abbreviated, time: .omitted)
        return "Time Machine has a snapshot on this disk from \(date) that it has not been able to hand to a backup drive. Until it can, deleting anything older than that date returns no space at all."
    }
}

// MARK: - What is in iCloud and not here

/// **The files that look enormous and occupy nothing.**
///
/// ⚠️ **This is the only type in the file that holds an apparent size, and it may only ever be
/// printed as what the files "look like" — never as a size we stand behind.** Measured here: 15,593
/// files, 72 GB by name, zero bytes on this disk. A "largest first" list that reads the claimed
/// size puts every one of them above the things actually filling the drive.
public struct CloudHolding: Sendable, Hashable, Codable {

    public let files: Int

    /// What they add up to **by name**. Never a `SizeOnDisk`, because they occupy none.
    public let apparentBytes: Int64

    public init(files: Int, apparentBytes: Int64) {
        self.files = files
        self.apparentBytes = max(0, apparentBytes)
    }

    public var isEmpty: Bool { files == 0 }

    /// The one sentence. Note the verb: they *look like*. They are not that big here, and there is
    /// no space to be had from them.
    public var sentence: String {
        let size = apparentBytes.formatted(.byteCount(style: .file))
        let count = files.formatted()
        return files == 1
            ? "One file looks like \(size) and is using no space here — it is in iCloud."
            : "\(count) files look like \(size) and are using no space here — they are in iCloud."
    }

    public var detailPair: DetailPair {
        DetailPair("In iCloud, not on this Mac", sentence)
    }
}

// MARK: - What we were not allowed to see

/// **The places the scan could not read.**
///
/// ⚠️ **Without Full Disk Access, 54 folders in this home directory cannot be read** — including
/// the Trash and the Photos library, which are usually the two biggest wins on any Mac. The rule
/// this type exists to keep: **say "I was not allowed to look". Never a zero.**
///
/// There is no initialiser that produces an empty one silently — use `sawEverything`, which says so
/// in its name.
public struct UnreadablePlaces: Sendable, Hashable, Codable {

    /// How many places were refused.
    public let count: Int

    /// The ones worth naming, in the person's words: "your Trash", "your Photos library".
    /// Named rather than counted, because a count of 54 means nothing and "your Photos library"
    /// means everything.
    public let notable: [String]

    public let why: Unreadable

    public init(count: Int, notable: [String] = [], why: Unreadable = .notPermitted) {
        self.count = max(0, count)
        self.notable = notable
        self.why = why
    }

    /// Nothing was refused. Spelled out, so that a caller writing `UnreadablePlaces(count: 0)`
    /// meaning "I did not check" reads differently from one that genuinely saw everything.
    public static let sawEverything = UnreadablePlaces(count: 0, notable: [], why: .notReported)

    public var isEmpty: Bool { count == 0 }

    /// Whether a run containing this may still call itself complete. Only a refusal a person can
    /// lift makes a run incomplete — see the table on `Unreadable`.
    public var stillComplete: Bool { isEmpty || why.stillComplete }

    /// The line on the face. Never a zero, never a shrug.
    ///
    /// - Parameter namingThem: whether to list the notable folders. **The names belong to whichever
    ///   place on the screen says this FIRST, and to nothing below it.** Rendered with both, the
    ///   free-space card and the row beneath it printed the same sentence and the same five folder
    ///   names an inch apart — caught in the 2026-08-28 pictures, not by a test. The house rule is
    ///   that the container is the answer and what sits inside it does not repeat it.
    public func sentence(namingThem: Bool = true) -> String? {
        guard !isEmpty else { return nil }
        let places = count == 1 ? "one folder" : "\(count.formatted()) folders"
        let named = (notable.isEmpty || !namingThem) ? "" : " Among them: \(Self.list(notable))."
        switch why {
        case .notPermitted:
            return "\(places.capitalizedFirst) could not be read, so this total is smaller than the truth. Full Disk Access would let us see them.\(named)"
        case .notGrantable, .notReported:
            return "\(places.capitalizedFirst) could not be read, so this total is smaller than the truth. \(why.sentence)\(named)"
        }
    }

    /// The full form, naming the folders. Use this where the caveat is said for the first time.
    public var sentence: String? { sentence(namingThem: true) }

    /// The short form for anywhere the names have already been given above.
    public var sentenceWithoutNames: String? { sentence(namingThem: false) }

    /// The button, on the one refusal a person can lift.
    public var remedy: Remedy? {
        guard !isEmpty, why.mayOfferRemedy else { return nil }
        // ⚠️ A pane NAME, never a URL. `x-apple.systempreferences:` anchors are Apple internals
        // that get renamed; they live in `App/Settings/SystemSettingsPane.swift` and nowhere else.
        // This string is the raw value of that enum's `fullDiskAccess` case, and a test in
        // `Tools/AppTests` asserts the two still match.
        return Remedy(title: "Open Full Disk Access", settingsPane: "fullDiskAccess")
    }

    static func list(_ parts: [String]) -> String {
        switch parts.count {
        case 0:  return ""
        case 1:  return parts[0]
        case 2:  return "\(parts[0]) and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }
}

extension String {
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

// MARK: - ⭐ The gap we name instead of hiding

/// **The difference between what our scan accounted for and what macOS says is used.**
///
/// ⚠️ Measured 2026-08-28: our scan of live files totalled **244 GB**; macOS reports **357 GB**
/// used. The missing 113 GB is the local snapshot, the folders we were not allowed to read, and the
/// filesystem's own bookkeeping. **Every competitor invents an "Other" slice to hide this.** A
/// slice labelled Other is a number with no explanation attached, which is the same as no number.
///
/// This type cannot be omitted from a report: `StorageReport` computes it in its initialiser, from
/// figures it already holds, and there is no argument for it to leave out.
public struct MeasuredGap: Sendable, Hashable, Codable {

    /// What macOS says is used on the volume.
    public let used: SizeOnDisk

    /// What the scan actually walked and added up.
    public let measured: SizeOnDisk

    /// How many places were refused, so the sentence can name that as one of the causes.
    public let placesRefused: Int

    /// Whether a local snapshot is holding blocks, so the sentence can name that too.
    public let hasSnapshot: Bool

    public init(used: SizeOnDisk, measured: SizeOnDisk, placesRefused: Int, hasSnapshot: Bool) {
        self.used = used
        self.measured = measured
        self.placesRefused = max(0, placesRefused)
        self.hasSnapshot = hasSnapshot
    }

    /// The size of the gap. Clamped at zero: a scan that came out larger than the volume's used
    /// figure has counted something twice, and the honest answer then is "no gap", not a negative.
    public var difference: SizeOnDisk { used - measured }

    /// Whether it is worth a sentence. A gap under this is bookkeeping and saying so is clutter.
    ///
    /// 1 GB is a judgement, named here so it lives in one place.
    public static let worthExplainingBytes: Int64 = 1_000_000_000

    public var worthExplaining: Bool { difference.bytes >= Self.worthExplainingBytes }

    /// **The sentence. It names the gap and then names what is in it.**
    ///
    /// Never "Other". If we cannot say what is in the gap, we say that we cannot, which is still
    /// more than a coloured slice with a shrug on it.
    public var sentence: String {
        guard worthExplaining else {
            return "Everything macOS reports as used is accounted for above."
        }
        var causes: [String] = []
        if hasSnapshot { causes.append("a Time Machine snapshot holding old blocks") }
        if placesRefused > 0 {
            causes.append(placesRefused == 1
                          ? "one folder we were not allowed to read"
                          : "\(placesRefused.formatted()) folders we were not allowed to read")
        }
        causes.append("the filesystem's own bookkeeping")

        return "macOS reports \(used.text) used. The list above accounts for \(measured.text). "
             + "The other \(difference.text) is \(UnreadablePlaces.list(causes))."
    }

    public var detailPairs: [DetailPair] {
        [DetailPair("macOS reports used", used.text),
         DetailPair("This scan accounted for", measured.text),
         DetailPair("Not accounted for", difference.text)]
    }
}

// MARK: - How full the disk is

/// How much room is left, in the three words the section uses about it.
///
/// ⚠️ The thresholds below are **judgement, not measurement**, and they are named so there is one
/// place to argue with them. `nearlyFull` is the one state in Storage that is a `.problem`: macOS
/// needs working room, and below it apps genuinely begin failing to save. Everything else in this
/// section is `.information`, because a large folder is not a problem — it is large.
public enum DiskPressure: String, Sendable, Codable, CaseIterable, Identifiable {
    case comfortable
    case gettingFull
    case nearlyFull

    public var id: String { rawValue }

    /// Below this share of the disk left, it is getting full.
    public static let gettingFullBelowShare = 0.15
    /// Below this share, or below `nearlyFullBelowBytes`, it is a problem.
    public static let nearlyFullBelowShare = 0.05
    /// A floor in bytes as well as a share, because 5% of a 4 TB disk is 200 GB and 5% of a 256 GB
    /// disk is 12 GB — the same percentage is two very different situations.
    public static let nearlyFullBelowBytes: Int64 = 10_000_000_000

    public static func measuring(free: SizeOnDisk, capacity: SizeOnDisk) -> DiskPressure {
        guard capacity.bytes > 0 else { return .comfortable }
        let share = Double(free.bytes) / Double(capacity.bytes)
        if share < nearlyFullBelowShare || free.bytes < nearlyFullBelowBytes { return .nearlyFull }
        if share < gettingFullBelowShare { return .gettingFull }
        return .comfortable
    }

    public var label: String {
        switch self {
        case .comfortable: "There is room"
        case .gettingFull: "Getting full"
        case .nearlyFull:  "Nearly full"
        }
    }

    public var severity: Severity {
        switch self {
        case .comfortable: .information
        case .gettingFull: .attention
        case .nearlyFull:  .problem
        }
    }

    /// Why it says what it says. `nil` where nothing is wrong and there is nothing to explain.
    public var reason: String? {
        switch self {
        case .comfortable: nil
        case .gettingFull: "macOS needs working room. It is worth looking at this before it becomes urgent."
        case .nearlyFull:  "macOS needs working room of its own. This low, apps start failing to save."
        }
    }
}

// MARK: - The free-space picture

/// **The two answers to "how much room is left", and the one line that explains the difference.**
///
/// The ruling, 2026-08-28: the real number leads, Finder's is printed underneath, and one line
/// says what the gap is. Measured on one real Mac — 109.8 GB actually free, 177.9 GB in Finder,
/// 68.1 GB apart.
///
/// The reading is taken by `App/Storage/FreeSpace.swift`; this type is the answer it hands back.
public struct FreeSpacePicture: Sendable, Hashable, Codable {

    public let capacity: SizeOnDisk

    /// ⭐ **The number that leads, and the only one arithmetic is done on.**
    /// `volumeAvailableCapacityKey` — bytes that are genuinely not in use.
    public let actuallyFree: SizeOnDisk

    /// Finder's figure, in a type that cannot be added to anything. `nil` where macOS did not
    /// report it. See `FinderFigure`.
    public let finderShows: FinderFigure?

    /// What the snapshots are holding, and the arithmetic that hangs off it.
    public let snapshots: SnapshotStanding

    /// Which volume this is about, in a person's words: "this Mac's disk".
    public let volumeName: String

    public init(capacity: SizeOnDisk,
                actuallyFree: SizeOnDisk,
                finderShows: FinderFigure? = nil,
                snapshots: SnapshotStanding = .none,
                volumeName: String = "this Mac's disk") {
        self.capacity = capacity
        self.actuallyFree = actuallyFree
        self.finderShows = finderShows
        self.snapshots = snapshots
        self.volumeName = volumeName
    }

    /// What macOS considers used. Derived, so it can never disagree with the two figures above it.
    public var used: SizeOnDisk { capacity - actuallyFree }

    public var pressure: DiskPressure { .measuring(free: actuallyFree, capacity: capacity) }

    /// The big number at the top of the section.
    public var headline: String { "\(actuallyFree.text) free of \(capacity.text)" }

    /// Finder's figure, printed underneath — or `nil` when it agrees, in which case there is
    /// nothing to explain and a second identical number is clutter.
    public var finderLine: String? {
        guard let finderShows, finderShows.differsFrom(actuallyFree) else { return nil }
        return "Finder says \(finderShows.text)."
    }

    /// ⭐ **The one line that explains the difference.** This is the sentence asked for, and
    /// the thing no other tool on this Mac does: we are not contradicting Finder, we are saying
    /// what its number counts.
    public var differenceLine: String? {
        guard let finderShows, finderShows.differsFrom(actuallyFree) else { return nil }
        let promise = finderShows.promiseBeyond(actuallyFree)
        return "That figure includes \(promise.text) macOS believes it could make room for under pressure — files it would remove from this Mac and keep in iCloud, caches it would empty. It is a promise rather than a count, and it does not go up by what you delete. Ours does."
    }

    public var detailPairs: [DetailPair] {
        var pairs = [DetailPair("Capacity", capacity.text),
                     DetailPair("Actually free", actuallyFree.text)]
        if let finderShows { pairs.append(DetailPair("Finder shows", finderShows.text)) }
        pairs.append(DetailPair("In use", used.text))
        if let oldest = snapshots.oldest {
            pairs.append(DetailPair("Oldest local snapshot",
                                    oldest.takenOn.formatted(date: .abbreviated, time: .shortened)))
        }
        return pairs
    }
}

// MARK: - One row's result

/// What one topic found. Same three facts, the same `Options` details and the same house sentence
/// for a refusal as every other section in the app.
///
/// ⚠️ **`severity` is a computed constant.** Revealing a person's files is never a fault, and a
/// large folder is not a problem — it is large. The one thing in this section that may be worse
/// than `.information` is how full the disk is, and that lives on `DiskPressure`, reached only
/// through `StorageReport`. There is no argument anywhere on this type that could carry a colour.
public struct StorageRow: Sendable, Hashable, Identifiable, Codable {

    public let topic: StorageTopic

    /// The row's own sentence, in plain words. **Fact one of three.**
    public let headline: String

    /// ⭐ **Both numbers, or none.** There is no way to give a row a single figure.
    /// **Fact two of three.**
    public let measure: Bytes?

    /// How many things are behind the row. `nil` where a count would mean nothing.
    public let count: Int?

    /// Why it says what it says, in plain words. Shown on the row, never behind a disclosure.
    /// **Fact three of three.**
    public let reason: String?

    /// What was found, in the order the row draws them. Largest first is the caller's business.
    public let items: [Item]

    /// Everything more exact, behind **Options**.
    public let details: [DetailPair]

    /// Set when this could not be read at all.
    public let unreadable: Unreadable?

    /// Places inside this row's territory that were refused. Kept separately from `unreadable`,
    /// because a row that read most of the disk and was refused the Trash is **not** a row that
    /// could not be read — and reporting it as one would throw away everything it did find.
    public let refused: UnreadablePlaces

    /// The button on a `.notPermitted` row.
    public let remedy: Remedy?

    public var id: StorageTopic { topic }

    /// ⚠️ Always `.information`. See the type note.
    public var severity: Severity { Self.severityCeiling }

    /// The one severity a Storage row may produce, named so a test can hold it.
    public static let severityCeiling: Severity = .information

    /// The row's status chip. **Never `.needsAttention`** — the only two answers a row here has are
    /// "we looked" and "we could not look".
    public var status: SectionStatus { unreadable == nil ? .good : .notChecked }

    /// Whether this row leaves the run able to call itself complete.
    public var complete: Bool {
        (unreadable?.stillComplete ?? true) && refused.stillComplete
    }

    /// ⭐ Which ceremony this row's buttons use.
    public var ceremony: Ceremony { topic.ceremony }

    /// ⭐ **The items that may arrive ticked. Empty for every topic but machine junk**, and empty
    /// even there for anything the engine cannot hold.
    public var preSelected: [Item] {
        guard topic.mayArrivePreSelected else { return [] }
        return items.filter(\.mayBePreSelected)
    }

    /// The three facts, in order, for a view that wants them as a list.
    public var facts: [String] {
        [headline, measure?.text, reason].compactMap { $0 }
    }

    public init(topic: StorageTopic,
                headline: String,
                measure: Bytes? = nil,
                count: Int? = nil,
                reason: String? = nil,
                items: [Item] = [],
                details: [DetailPair] = [],
                unreadable: Unreadable? = nil,
                refused: UnreadablePlaces = .sawEverything,
                remedy: Remedy? = nil) {
        self.topic = topic
        self.headline = headline
        // ⚠️ Never report a figure for something we could not read. A zero here is the one number a
        // person would act on and the one number we have no right to.
        self.measure = unreadable == nil ? measure : nil
        self.count = unreadable == nil ? count : nil
        self.reason = reason
        self.items = unreadable == nil ? items : []
        self.details = details
        self.unreadable = unreadable
        self.refused = refused
        self.remedy = remedy ?? refused.remedy
    }

    /// A row we could not read at all, in the house sentence.
    public static func unreadable(_ topic: StorageTopic,
                                  _ why: Unreadable,
                                  about thing: String? = nil,
                                  reason: String? = nil,
                                  details: [DetailPair] = [],
                                  remedy: Remedy? = nil) -> StorageRow {
        StorageRow(topic: topic,
                   headline: why.sentence(about: thing ?? topic.label),
                   reason: reason,
                   details: details,
                   unreadable: why,
                   remedy: (why.mayOfferRemedy ? remedy : nil))
    }
}

// MARK: - The whole section's answer

/// Everything one run of the Storage scan produced.
///
/// ⭐ **The gap is not a parameter.** It is computed here, from the free-space picture and the
/// figure the scan actually accounted for, so there is no code path anywhere that produces a
/// Storage report without naming the difference between the two.
public struct StorageReport: Sendable, Hashable {

    /// The two free-space numbers and the line explaining them. Leads the face.
    public let freeSpace: FreeSpacePicture

    /// Always in `StorageTopic` order, whatever order the scanners finished in. Duplicates dropped,
    /// first one wins.
    public let rows: [StorageRow]

    /// What the scan walked and added up. Required — see the type note.
    public let measured: SizeOnDisk

    /// Everywhere the scan was refused, gathered once for the face to say once rather than five
    /// times.
    public let refused: UnreadablePlaces

    /// The files that look enormous and are not here. `nil` when there are none.
    public let cloudHolding: CloudHolding?

    public let ranAt: Date

    /// ⭐ **Computed, never passed in.**
    public let gap: MeasuredGap

    /// ⚠️ **The ruling: one flat line on the face, no button.** `nil` when there is nothing to
    /// say.
    public let snapshotLine: String?

    /// The single row Storage sends up to Overview, or `nil` when there is nothing to say.
    ///
    /// ⚠️ **One row, not one per finding.** And it is about how full the disk is — never about how
    /// large somebody's folders are. Revealing a person's own files is not something that needs
    /// them.
    public let overviewFinding: Finding?

    public init(freeSpace: FreeSpacePicture,
                rows: [StorageRow],
                measured: SizeOnDisk,
                refused: UnreadablePlaces = .sawEverything,
                cloudHolding: CloudHolding? = nil,
                ranAt: Date = Date()) {
        self.freeSpace = freeSpace

        var seen = Set<StorageTopic>()
        self.rows = rows
            .filter { seen.insert($0.topic).inserted }
            .sorted { $0.topic.order < $1.topic.order }

        self.measured = measured
        self.refused = refused
        self.cloudHolding = cloudHolding.flatMap { $0.isEmpty ? nil : $0 }
        self.ranAt = ranAt

        self.gap = MeasuredGap(used: freeSpace.used,
                               measured: measured,
                               placesRefused: refused.count,
                               hasSnapshot: !freeSpace.snapshots.isEmpty)
        self.snapshotLine = freeSpace.snapshots.line(now: ranAt)
        self.overviewFinding = Self.summarise(freeSpace: freeSpace)
    }

    /// The section's status chip. The only thing here that can need attention is how full the disk
    /// is; nothing about the size of somebody's files ever can.
    public var status: SectionStatus {
        guard !rows.isEmpty else { return .notChecked }
        return freeSpace.pressure == .comfortable ? .good : .needsAttention
    }

    /// Whether this run saw everything it set out to see.
    public var complete: Bool { rows.allSatisfy(\.complete) && refused.stillComplete }

    public var record: CheckRecord {
        CheckRecord(section: .storage, ranAt: ranAt, status: status, complete: complete)
    }

    public func row(_ topic: StorageTopic) -> StorageRow? {
        rows.first { $0.topic == topic }
    }

    /// ⭐ **What the section says under its headline, in order, with nothing optional missing.**
    ///
    /// The gap sentence is in this list unconditionally, which is the point: there is no draw of
    /// this section that shows totals without saying what they do not cover.
    public var linesUnderTheHeadline: [String] {
        [freeSpace.finderLine,
         freeSpace.differenceLine,
         snapshotLine,
         refused.sentence,
         cloudHolding?.sentence,
         gap.worthExplaining ? gap.sentence : nil].compactMap { $0 }
    }

    /// Everything this run could not read at all, with the reason.
    public var unreadableTopics: [(topic: StorageTopic, why: Unreadable)] {
        rows.compactMap { row in row.unreadable.map { (row.topic, $0) } }
    }

    /// The section's own sentence at the top of its face.
    public var summary: String {
        guard !rows.isEmpty else { return "Nothing has been scanned yet." }
        return freeSpace.headline
    }

    // MARK: The one row for Overview

    /// ⚠️ **The only thing Storage may raise on Overview is a disk with no room left.** Not a large
    /// folder, not a pile of duplicates, not a cache. Those are things we revealed; raising them
    /// would be the app telling somebody their own files are a fault, which is the entire category
    /// this product exists to not be.
    private static func summarise(freeSpace: FreeSpacePicture) -> Finding? {
        let pressure = freeSpace.pressure
        guard pressure != .comfortable, let reason = pressure.reason else { return nil }
        return Finding(section: .storage,
                       title: "\(freeSpace.volumeName.capitalizedFirst) is \(pressure.label.lowercased())",
                       reason: reason,
                       severity: pressure.severity,
                       measure: "\(freeSpace.actuallyFree.text) free",
                       verb: SectionID.storage.verb)
    }
}
