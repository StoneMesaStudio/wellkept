import Darwin
import Foundation
import WellkeptCore

//  SpeedTest.swift
//  Wellkept — App/Hardware
//
//  **How fast this drive reads and writes** — the one row in Hardware with a button that does
//  work rather than looks at something.
//
//  ## Why this is not part of the check
//
//  "Automatic means looking. Manual means touching." Every other reader in this section reads a
//  number the Mac was already keeping. This one *makes* the number, and making it costs writes to
//  somebody's SSD. macOS budgets a well-behaved app roughly **2 GB of writes a day** and files a
//  report against you for going over it — it filed one against the benchmark that produced the
//  figures this file is built on. A health check that quietly spent a tenth of a person's daily
//  write budget every time they opened the app would be doing a small version of the thing this
//  app exists to catch other software doing.
//
//  So: **its own button, inside Options, never on a schedule, never on launch.** The everyday
//  check draws `restingReading(history:)`, which measures nothing.
//
//  ## The two halves are not the same kind of number
//
//  | | How it is measured | How it is reported |
//  |---|---|---|
//  | **Read** | From files already on this drive, three times over. **Zero writes.** | A firm figure — best of three repeats to within 2%. |
//  | **Write** | One file, at most 256 MB, once, on a press. | **Approximate, and it says so.** The same test gave 1,500 and 3,200 MB/s on one Mac within an hour. |
//
//  Reporting the write figure to three digits would be inventing precision that the measurement
//  does not have. It is rounded to the nearest 50 MB/s and prefixed with "about", every time.
//
//  ## ⚠️ Three ways a disk benchmark lies, and what is done about each
//
//  1. **The file system cache.** Reading a file macOS already has in memory measures RAM.
//     Every descriptor here is put into `F_NOCACHE`, the buffer is page-aligned and the chunks
//     are 8 MB, which is what makes those reads and writes go to the device rather than through
//     the cache.
//  2. **APFS transparent compression.** Almost every file on the system volume is `decmpfs`-
//     compressed: fewer bytes come off the platter than the file claims to hold, so the
//     throughput comes out inflated and partly CPU-bound. Candidate files are rejected unless
//     they actually occupy their own size on disk — which rejects sparse files and clones in the
//     same test. The written file is filled with incompressible bytes for the same reason.
//  3. **Measuring a different drive.** `/Library/Developer/CoreSimulator/Volumes/…` is a mounted
//     disk image; an external boot drive is not the internal one. Every candidate's mount is
//     resolved back to the physical device and compared against the device `/` is on.
//
//  ## No table of expected speeds, ever
//
//  There is no shipped list of what a 2021 MacBook Pro "should" do. Such a table is a
//  manufacturer's claim, measured differently, and its only use on screen is to tell somebody
//  their working Mac is below par. **The only comparison made here is against this Mac's own
//  earlier readings**, from `ReadingHistory` — which is the reason that file is written from the
//  first launch.

// MARK: - What one run produced

/// One measured rate: the bytes, the seconds, and nothing derived that could disagree with them.
struct SpeedRate: Sendable, Hashable {
    /// Bytes actually transferred. Short reads and short writes are counted as what happened, not
    /// as what was asked for.
    let bytes: Int
    /// Seconds spent inside the read or write calls themselves. Opening, closing and looking for
    /// the file are not in here.
    let seconds: Double

    /// Megabytes per second, decimal — the unit every drive is sold and benchmarked in, and the
    /// same convention `MachineReader.capacityText` uses for capacity.
    var megabytesPerSecond: Double {
        guard seconds > 0 else { return 0 }
        return Double(bytes) / seconds / 1_000_000
    }
}

/// Everything one press of the speed button produced.
struct SpeedResult: Sendable, Hashable {
    /// `nil` when no suitable file could be found to read. See `SpeedTest.findReadSources`.
    let read: SpeedRate?
    /// How many existing files the read was spread across. `0` when there was no read.
    let readFileCount: Int
    /// `nil` when no write was asked for, or when one was refused.
    let write: SpeedRate?
    let ranAt: Date
    /// Why something is missing, in plain words. `nil` when nothing is missing.
    let note: String?

    /// Whether this run measured anything at all.
    var measuredSomething: Bool { read != nil || write != nil }
}

// MARK: - The test

enum SpeedTest {

    // MARK: What it costs, in numbers and in words

    /// How much is read, at most. Zero writes.
    static let readSampleBytes = 256 * 1_000_000

    /// **How much is written, at most, per press.** One file, deleted in the same function that
    /// created it.
    static let writeSampleBytes = 256 * 1_000_000

    /// Below this the figure is noise rather than a measurement, and the run says so instead of
    /// printing it.
    static let smallestUsefulSample = 48 * 1_000_000

    /// **The line that sits beside the button.**
    ///
    /// It lives here rather than in the view for the same reason `RepairShopCopy` holds one
    /// string: a consequence sentence that is written twice is a consequence sentence that starts
    /// being true in only one of the two places. DESIGN §12.4 — say what a function does to the
    /// user's own disk, once, on the control that does it.
    static let writeNotice =
        "Writes a 256 MB test file to this drive, times it, and deletes it straight away. "
        + "Read speed is measured from files already here and writes nothing."

    /// The most write tests one launch of the app will perform.
    ///
    /// Four presses is one gigabyte — half the daily write budget macOS allows a well-behaved app,
    /// and far more than anybody needs to answer "is my drive slow". After that the button's own
    /// answer is that it has written enough for one sitting. This is a guard against a person
    /// idly pressing a button twenty times, not a policy anybody should ever meet.
    static let writeTestsPerLaunch = 4

    private static let lock = NSLock()
    private nonisolated(unsafe) static var writeTestsRun = 0

    /// Take one write test out of this launch's allowance, or refuse.
    ///
    /// Read and increment under one lock, so two presses landing together cannot both see the
    /// last slot and both take it.
    private static func claimWriteBudget() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard writeTestsRun < writeTestsPerLaunch else { return false }
        writeTestsRun += 1
        return true
    }

    // MARK: Running it

    /// Measure this drive, off the main thread.
    ///
    /// The whole thing takes a couple of seconds: it is blocking file I/O from first line to last,
    /// which is exactly what it is supposed to be, and so it never runs where a window is waiting
    /// to draw.
    static func run(includeWrite: Bool = true,
                    home: URL = StorageManifest.home()) async -> SpeedResult {
        await Task.detached(priority: .userInitiated) {
            measure(includeWrite: includeWrite, home: home)
        }.value
    }

    /// The blocking measurement. Public to the target so tests can call it without a task.
    static func measure(includeWrite: Bool = true,
                        home: URL = StorageManifest.home()) -> SpeedResult {
        let started = Date()
        var notes: [String] = []

        let sources = findReadSources()
        var read: SpeedRate?
        if sources.isEmpty {
            notes.append("Read speed needs a large file already on this drive to read, and none "
                         + "was found that could be measured honestly.")
        } else {
            read = measureRead(sources)
            if read == nil {
                notes.append("The files chosen to measure the read speed could not be read "
                             + "through to the end.")
            }
        }

        var write: SpeedRate?
        if includeWrite {
            switch measureWrite(home: home) {
            case .success(let rate):  write = rate
            case .failure(let why):   notes.append(why)
            }
        }

        return SpeedResult(read: read,
                           readFileCount: read == nil ? 0 : sources.count,
                           write: write,
                           ranAt: started,
                           note: notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    // MARK: - Read: zero writes

    /// One file, and how much of it to read.
    private struct ReadSource: Sendable, Hashable {
        let path: String
        let bytes: Int
    }

    /// How many times the read is repeated. **The fastest pass wins.**
    ///
    /// ⚠️ This is the whole reason the read figure is allowed to be called firm and the write
    /// figure is not. A single pass on this Mac gave 2,964, 2,326 and 2,972 MB/s — a 22% spread,
    /// caused by whatever else the machine happened to be doing during the slow one. The best of
    /// three gave 3,101, 3,092, 3,148 and 3,152 across four rounds: **under 2%.** Interference
    /// only ever makes a pass slower, so the fastest one is the closest to the truth about the
    /// drive.
    ///
    /// Repeating it is free because reading is free. The write test cannot do the same trick — a
    /// repeat there costs the user another 256 MB of their drive's life — and that asymmetry is
    /// exactly why one number is printed plainly and the other says "about".
    private static let readPasses = 3

    /// Read from files that are already here, in 8 MB chunks, with the cache switched off.
    ///
    /// The clock runs across the `read` calls only. Opening the files, and the walk that found
    /// them, are not the drive's fault and are not in the figure.
    private static func measureRead(_ sources: [ReadSource]) -> SpeedRate? {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkBytes, alignment: pageSize)
        defer { buffer.deallocate() }

        var best: SpeedRate?

        for _ in 0..<readPasses {
            var moved = 0
            var seconds = 0.0

            for source in sources {
                let descriptor = Darwin.open(source.path, O_RDONLY)
                guard descriptor >= 0 else { continue }
                defer { Darwin.close(descriptor) }
                // Straight from the device. Without this the second pass would measure memory.
                _ = fcntl(descriptor, F_NOCACHE, 1)

                var remaining = source.bytes
                while remaining > 0 {
                    let want = min(remaining, chunkBytes)
                    let start = ContinuousClock.now
                    let got = Darwin.read(descriptor, buffer, want)
                    seconds += elapsed(since: start)
                    guard got > 0 else { break }
                    moved += got
                    remaining -= got
                }
            }

            guard moved >= smallestUsefulSample, seconds > 0 else { continue }
            let pass = SpeedRate(bytes: moved, seconds: seconds)
            if pass.megabytesPerSecond > (best?.megabytesPerSecond ?? 0) { best = pass }
        }

        return best
    }

    /// The roots searched for something big enough to read, in the order they are tried.
    ///
    /// Shared locations first, the user's own cache folder last and only if the shared ones came
    /// up short. Nothing here reads anything in Documents, Desktop or Downloads: those need a
    /// privacy grant, and **nothing in Hardware needs Full Disk Access.** The bytes are read and
    /// thrown away — no file's contents are examined, kept, or reported.
    private static let readRoots = [
        "/Applications",
        "/System/Library/PrivateFrameworks",
        "/System/Applications",
        "/System/Library/Frameworks",
        "/System/Library/CoreServices",
        "/Library/Application Support",
        NSHomeDirectory() + "/Library/Caches",
    ]

    /// A file has to be at least this big to be worth timing. Below it, the open dominates.
    private static let smallestCandidate = 16 * 1_000_000

    /// No single file supplies more than this, so one enormous file cannot become the whole
    /// measurement.
    private static let mostFromOneFile = 128 * 1_000_000

    /// Find enough readable bytes on this drive to measure against.
    ///
    /// Bounded by a wall clock rather than by a file count: the roots below hold hundreds of
    /// thousands of entries on a normal Mac, and a walk that finished would sometimes take longer
    /// than the measurement it was preparing for. It stops at the budget, or as soon as it has
    /// comfortably more than it needs, and reports honestly when it found too little.
    private static func findReadSources(budget: Duration = .milliseconds(1500)) -> [ReadSource] {
        let deadline = ContinuousClock.now.advanced(by: budget)
        guard let bootDisk = physicalDisk(of: "/") else { return [] }

        var candidates: [(bytes: Int, path: String)] = []
        var pooled = 0
        let manager = FileManager.default

        for root in readRoots {
            guard pooled < readSampleBytes * 3, ContinuousClock.now < deadline else { break }
            // Package descendants are deliberately NOT skipped: on most Macs the only files big
            // enough to time are inside .app bundles.
            guard let walk = manager.enumerator(at: URL(fileURLWithPath: root, isDirectory: true),
                                                includingPropertiesForKeys: [.isRegularFileKey,
                                                                             .fileSizeKey],
                                                options: [.skipsHiddenFiles],
                                                errorHandler: { _, _ in true }) else { continue }

            var seen = 0
            for case let url as URL in walk {
                seen += 1
                // The clock is only consulted every so often: on this walk `ContinuousClock.now`
                // is a measurable share of the work.
                if seen % 2_048 == 0 {
                    if ContinuousClock.now >= deadline { break }
                    if pooled >= readSampleBytes * 3 { break }
                }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey,
                                                                     .fileSizeKey]),
                      values.isRegularFile == true,
                      let size = values.fileSize, size >= smallestCandidate else { continue }
                guard occupiesItsOwnBytes(url.path),
                      physicalDisk(of: url.path) == bootDisk else { continue }

                candidates.append((size, url.path))
                pooled += min(size, mostFromOneFile)
            }
        }

        // Biggest first, and ties broken by path, so the same Mac measures the same files from
        // one run to the next and its own history stays comparable.
        candidates.sort { $0.bytes == $1.bytes ? $0.path < $1.path : $0.bytes > $1.bytes }

        var chosen: [ReadSource] = []
        var budget = readSampleBytes
        for candidate in candidates where budget > 0 {
            let take = min(candidate.bytes, mostFromOneFile, budget)
            guard take >= 1_000_000 else { continue }
            chosen.append(ReadSource(path: candidate.path, bytes: take))
            budget -= take
        }
        return chosen.reduce(0) { $0 + $1.bytes } >= smallestUsefulSample ? chosen : []
    }

    /// Whether a file really occupies on disk the number of bytes it claims to hold.
    ///
    /// ⚠️ **This is the check that keeps the read figure honest.** Almost everything on the system
    /// volume is `decmpfs`-compressed: `read` hands back the full logical size, but far fewer
    /// bytes came off the drive and a processor did the rest of the work. Timing one of those
    /// produces a number two or three times the truth. A sparse file and an APFS clone fail the
    /// same arithmetic, which is why one test covers all three.
    private static func occupiesItsOwnBytes(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        if info.st_flags & UInt32(UF_COMPRESSED) != 0 { return false }
        let allocated = Double(info.st_blocks) * 512
        return allocated >= Double(info.st_size) * 0.95
    }

    // MARK: - Write: 256 MB, once, on a press

    /// The result of asking for a write measurement: a rate, or a sentence saying why not.
    private enum WriteOutcome {
        case success(SpeedRate)
        case failure(String)
    }

    /// Write one file, time it, and delete it — **in this function, every path out.**
    ///
    /// ## Where it is written, and why there
    ///
    /// `~/Library/Caches/studio.stonemesa.wellkept/` — which is a declared entry in
    /// `StorageManifest`, marked `.delete`. Application Support is deliberately not used: there is
    /// no catch-all entry for Wellkept's folder there (it holds the quarantine, and a recursive
    /// delete of it would take the user's own files), so a stray quarter-gigabyte left by a crash
    /// would survive an uninstall in a folder nobody would think to look in.
    ///
    /// A crash between the `open` and the `defer` still leaves the file behind — nothing in
    /// user space runs after a kill. So the next run removes any leftover before it starts, and
    /// macOS purges that folder under space pressure regardless.
    private static func measureWrite(home: URL) -> WriteOutcome {
        let folder = home.appending(path: "Library/Caches/\(StorageManifest.bundleIdentifier)")
        let file = folder.appending(path: "SpeedTest.tmp")
        let manager = FileManager.default

        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return .failure("Write speed could not be measured: Wellkept's own cache folder "
                            + "could not be opened.")
        }

        // A leftover from a run that was killed mid-test. Removed before, not only after.
        try? manager.removeItem(at: file)
        defer { try? manager.removeItem(at: file) }

        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard free > Int64(writeSampleBytes) * 4 else {
            return .failure("Write speed was not measured: there is not enough free space on "
                            + "this drive to write a 256 MB test file without crowding it.")
        }

        // ⚠️ Claimed here rather than at the top of the function: a run that turned back before
        // writing anything — no folder, no space — must not spend part of the allowance. Claimed
        // *before* the first byte rather than after the last, so two runs at once cannot both
        // read three-of-four and both proceed.
        guard claimWriteBudget() else {
            return .failure("Write speed has been measured \(writeTestsPerLaunch) times since "
                            + "Wellkept opened. That is a gigabyte written to test a drive, "
                            + "which is enough for one sitting — quit and reopen to measure it "
                            + "again.")
        }

        let descriptor = file.path.withCString { path in
            Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        }
        guard descriptor >= 0 else {
            return .failure("Write speed could not be measured: the test file could not be "
                            + "created.")
        }
        defer { Darwin.close(descriptor) }
        _ = fcntl(descriptor, F_NOCACHE, 1)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkBytes, alignment: pageSize)
        defer { buffer.deallocate() }
        fillIncompressible(buffer, bytes: chunkBytes)

        var written = 0
        let start = ContinuousClock.now
        while written < writeSampleBytes {
            let want = min(chunkBytes, writeSampleBytes - written)
            let put = Darwin.write(descriptor, buffer, want)
            guard put > 0 else { break }
            written += put
        }
        // Flush before the clock stops, so the figure is a write rather than a promise.
        //
        // ⚠️ `fsync`, deliberately, and **not** `F_FULLFSYNC`. The stronger call additionally
        // makes the drive empty its own internal cache, which is a different question and one no
        // other disk benchmark on macOS asks: measured here on the same file, `F_FULLFSYNC` gave
        // 832–2,043 MB/s where `fsync` gave 4,051–4,525. Shipping the lower pair would mean
        // telling somebody their drive writes at half the speed every other tool on their Mac
        // reports — the same failure as disagreeing with System Settings about the battery, and
        // it would read as us being broken rather than as us being strict.
        _ = fsync(descriptor)
        let seconds = elapsed(since: start)

        guard written >= smallestUsefulSample, seconds > 0 else {
            return .failure("Write speed could not be measured: the test file could not be "
                            + "written through to the end.")
        }
        return .success(SpeedRate(bytes: written, seconds: seconds))
    }

    /// Fill a buffer with bytes nothing can compress.
    ///
    /// A buffer of zeroes is the classic way to measure a drive as far faster than it is: APFS
    /// stores a run of zeroes as a note saying "zeroes". A cheap xorshift is used rather than the
    /// system random source because 8 MB of cryptographic randomness costs more time than the
    /// measurement it is preparing for, and nothing here needs the bytes to be unguessable — only
    /// to be incompressible.
    private static func fillIncompressible(_ buffer: UnsafeMutableRawPointer, bytes: Int) {
        var state = UInt64(0x2545_F491_4F6C_DD1D)
        let words = buffer.bindMemory(to: UInt64.self, capacity: bytes / 8)
        for index in 0..<(bytes / 8) {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            words[index] = state
        }
    }

    // MARK: - Shared plumbing

    /// 8 MB per call: large enough that the syscall is not the thing being timed, and a multiple
    /// of the page size, which is what `F_NOCACHE` needs to move data straight to the device.
    private static let chunkBytes = 8 * 1024 * 1024

    private static let pageSize = 4096

    /// Seconds since an instant, as a `Double`.
    ///
    /// `Duration` is a pair of integers — seconds and attoseconds — with no conversion to a
    /// floating-point count, because for most uses there should not be one. Here there has to be:
    /// the answer is bytes divided by time.
    private static func elapsed(since start: ContinuousClock.Instant) -> Double {
        let parts = (ContinuousClock.now - start).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    /// The physical disk a path lives on — "disk3" — or `nil` for anything not on a local disk.
    ///
    /// ⚠️ The volume is the wrong unit here. macOS splits the boot drive into a sealed system
    /// volume and a data volume, so `/System/Library` and `/Users` are on different volumes and
    /// the same piece of hardware. What matters is the device underneath, which is what this
    /// strips back to. A network mount has no `disk` name at all and drops out, and so does a
    /// mounted disk image — `/Library/Developer/CoreSimulator/Volumes/…` is a real place with
    /// large real files that is not this drive.
    private static func physicalDisk(of path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }

        let source = withUnsafeBytes(of: &info.f_mntfromname) { raw -> String in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        guard let name = source.split(separator: "/").last, name.hasPrefix("disk") else {
            return nil
        }
        let digits = name.dropFirst(4).prefix { $0.isNumber }
        return digits.isEmpty ? nil : "disk\(digits)"
    }

    // MARK: - Saying it

    /// "2,930 MB/s", or "about 2,400 MB/s".
    ///
    /// The read figure is rounded to the nearest 10 MB/s and the write figure to the nearest 50,
    /// because that is roughly how well each one repeats. Printing a write speed as "2,437 MB/s"
    /// claims a precision the measurement does not have — the same test on the same Mac produced
    /// 1,500 and 3,200 within an hour.
    static func rateText(_ megabytesPerSecond: Double, approximate: Bool) -> String {
        let step = approximate ? 50.0 : 10.0
        let rounded = max(step, (megabytesPerSecond / step).rounded() * step)
        let number = rounded.formatted(.number.precision(.fractionLength(0)))
        return approximate ? "about \(number) MB/s" : "\(number) MB/s"
    }

    /// "256 MB" — how much was moved, for the detail beside a rate.
    static func sampleText(_ bytes: Int) -> String {
        "\((Double(bytes) / 1_000_000).rounded().formatted(.number.precision(.fractionLength(0)))) MB"
    }
}

// MARK: - The row

extension SpeedTest {

    /// **The Speed row on an everyday check, where nothing was measured.**
    ///
    /// Marked `.notReported`, which reads oddly for a second and is right: the contract on
    /// `Unreadable` is that `.notReported` means the machine did not hand us this number, carries
    /// no button, and **leaves the check complete**. All three hold. A drive does not report its
    /// own speed; the speed has to be made, and making it writes to the drive.
    ///
    /// ⚠️ It carries **no number, ever** — `Reading.init` guarantees that once `unreadable` is
    /// set. That is load-bearing rather than tidy: `ReadingHistory` records every reading of every
    /// launch, so a resting row that repeated the last measured figure would file a fresh sample
    /// of a measurement nobody took, dozens of times, and the comparison this whole file is built
    /// on would end up being a comparison against itself.
    static func restingReading(history: [ReadingSample] = ReadingHistory.samples(of: .speed))
    -> Reading {
        let previous = history.last { $0.value != nil }
        let headline: String
        if let previous, let measure = previous.measure {
            headline = "Not measured this time — \(measure) when it was last checked, on "
                + previous.takenAt.formatted(date: .abbreviated, time: .omitted) + "."
        } else {
            headline = "Not measured yet."
        }

        return Reading(topic: .speed,
                       headline: headline,
                       severity: .information,
                       reason: writeNotice,
                       details: comparisonDetails(history: history),
                       unreadable: .notReported)
    }

    /// **The Speed row after the button was pressed.**
    ///
    /// `number` is the *read* figure, deliberately. One number goes into the history, and it has
    /// to be the one worth comparing: the read repeats to within about two percent, and the write
    /// swings by a factor of two on an idle machine. A history of write speeds would be a history
    /// of noise, and every sentence built on it would be wrong about half the time.
    static func reading(_ result: SpeedResult,
                        history: [ReadingSample] = ReadingHistory.samples(of: .speed)) -> Reading {
        guard result.measuredSomething else {
            return Reading(topic: .speed,
                           headline: "Speed could not be measured.",
                           severity: .information,
                           reason: result.note,
                           details: comparisonDetails(history: history),
                           unreadable: .notReported)
        }

        var details: [DetailPair] = []
        if let read = result.read {
            details.append(DetailPair(
                "Read",
                "\(rateText(read.megabytesPerSecond, approximate: false)), the fastest of three "
                + "passes over \(sampleText(read.bytes)) from \(result.readFileCount) "
                + (result.readFileCount == 1 ? "file" : "files")
                + " already on this drive. Nothing was written."))
        }
        if let write = result.write {
            details.append(DetailPair(
                "Write",
                "\(rateText(write.megabytesPerSecond, approximate: true)), measured by writing "
                + "\(sampleText(write.bytes)) once and deleting it"))
        } else {
            details.append(DetailPair("Write", "Not measured this time"))
        }
        details.append(DetailPair("Measured", ShortDate.stamp(result.ranAt)))
        details.append(contentsOf: comparisonDetails(history: history))

        let verdict = slowdown(result.read?.megabytesPerSecond, history: history)

        return Reading(topic: .speed,
                       headline: headline(result),
                       measure: result.read.map { rateText($0.megabytesPerSecond,
                                                           approximate: false) },
                       number: result.read.map { ReadingNumber($0.megabytesPerSecond,
                                                              ReadingNumber.megabytesPerSecond) },
                       severity: verdict == nil ? .information : .attention,
                       reason: verdict ?? result.note,
                       details: details)
    }

    private static func headline(_ result: SpeedResult) -> String {
        switch (result.read, result.write) {
        case let (read?, write?):
            "This drive reads at \(rateText(read.megabytesPerSecond, approximate: false)) and "
            + "writes at \(rateText(write.megabytesPerSecond, approximate: true))."
        case let (read?, nil):
            "This drive reads at \(rateText(read.megabytesPerSecond, approximate: false))."
        case let (nil, write?):
            "This drive writes at \(rateText(write.megabytesPerSecond, approximate: true))."
        case (nil, nil):
            "Speed could not be measured."
        }
    }

    /// What this Mac has measured before — the only yardstick this file has, and the only one it
    /// is ever going to get.
    private static func comparisonDetails(history: [ReadingSample]) -> [DetailPair] {
        let past = history.compactMap(\.value).filter { $0 > 0 }
        guard !past.isEmpty else {
            return [DetailPair("Compared with",
                               "Nothing yet. Wellkept compares a drive only against its own "
                               + "earlier readings, so this becomes useful the second time.")]
        }
        let recent = past.suffix(10)
        let best = recent.max() ?? 0
        return [DetailPair("Compared with",
                           "\(recent.count) earlier "
                           + (recent.count == 1 ? "reading" : "readings")
                           + ", typically \(rateText(median(Array(recent)), approximate: false))"
                           + ", best \(rateText(best, approximate: false))")]
    }

    /// A sentence when this drive has genuinely fallen behind itself, and `nil` the rest of the
    /// time.
    ///
    /// ⚠️ **Deliberately hard to trigger, and it can never be a problem.** It needs three earlier
    /// readings and a drop of more than 40% against their middle value. A drive is measured on a
    /// machine that is also doing other things: a run that lands while Spotlight is reindexing is
    /// slower for a reason that has nothing to do with the drive, and an app that says "your drive
    /// is failing" on that evidence has taught its user to ignore the next thing it says. Worn but
    /// working is never a problem.
    private static func slowdown(_ nowMBps: Double?, history: [ReadingSample]) -> String? {
        guard let nowMBps, nowMBps > 0 else { return nil }
        let past = history.compactMap(\.value).filter { $0 > 0 }.suffix(10)
        guard past.count >= 3 else { return nil }

        let usual = median(Array(past))
        guard usual > 0, nowMBps < usual * 0.6 else { return nil }

        return "This reading is well below the \(rateText(usual, approximate: false)) this drive "
            + "usually manages. One slow run often just means the Mac was busy — measure it again "
            + "when it is idle before reading anything into it."
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
