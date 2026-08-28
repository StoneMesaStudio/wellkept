// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  ProvingGround.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The fixture that cannot be pointed at somebody's real files, and the snapshot that decides
//  whether a round trip lost anything.**
//
//  `QuarantineSandbox` gives the engine a pretend home folder. This adds the two things a *proof*
//  needs on top of that:
//
//  1. **A fixture that refuses to operate outside itself.** Every path a test asks for goes through
//     `inside(_:)`, which throws rather than returning a URL that escapes the sandbox. An absolute
//     path throws. A `..` component throws. A symlink that would land the write outside the root
//     throws, because the check is made on the *resolved* path and not on the string. That last one
//     is not paranoia: the whole reason this file exists is that a symlinked parent component is
//     the failure class that ends a product, and a test harness that can be walked through one is
//     a harness that can destroy the machine it is proving.
//
//  2. **`FileFacts` — everything a same-volume rename is supposed to preserve, read in one pass.**
//     Content, name bytes, mode, owner, group, BSD flags, link count, size, allocated blocks,
//     inode, creation and modification time to the nanosecond, every extended attribute, the
//     resource fork, and the access control list. The round-trip proof takes one before and one
//     after and compares the whole struct. It does not compare a chosen list of fields, because a
//     chosen list is a list somebody forgot to add to.
//
//  ⚠️ **Nothing in this file touches anything it did not create.** There is no code path here that
//  writes, changes a flag, or removes anything whose path did not come out of `inside(_:)`.

// MARK: - Escaping the sandbox is an error, not a warning

/// Thrown when a test asks the fixture for a path outside its own temporary directory.
///
/// A thrown error and not a `precondition`: a test that trips this should fail as a test, with its
/// message on the report, rather than take the whole runner down and leave the sandbox behind.
struct SandboxEscape: Error, CustomStringConvertible {
    let asked: String
    let why: String
    var description: String {
        "the fixture refused to operate outside its sandbox: \(asked) — \(why)"
    }
}

// MARK: - The fixture

/// A temporary directory that owns everything inside it and will not act outside it.
struct ProvingGround: Sendable {

    /// The pretend home folder handed to every engine call as `home:`.
    let home: URL

    /// The sandbox root as the filesystem itself spells it, symlinks resolved. Every guard compares
    /// against this and never against the string the test typed.
    let rootPath: String

    init() throws {
        // ⚠️ `realpath`, for the reason `QuarantineSandbox` documents: the temporary directory is
        // under `/var/folders/…`, `/var` is a symlink to `/private/var`, and left unresolved every
        // file in here would be refused — correctly — for having a symbolic link in its parent
        // chain. That refusal is proved once, deliberately, with a link the test makes itself.
        let base = QuarantineSandbox.canonical(
            FileManager.default.temporaryDirectory.path(percentEncoded: false))
        home = URL(filePath: base)
            .appending(path: "Wellkept-proof")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        rootPath = QuarantineSandbox.canonical(home.path(percentEncoded: false))
    }

    // MARK: The guard

    /// A URL inside the sandbox, or an error.
    ///
    /// Three checks, in order of how cheaply they catch the mistake:
    /// 1. an absolute path is a typo for a relative one, and it is refused outright;
    /// 2. a `..` component is refused before it is ever resolved;
    /// 3. the resolved parent must still be inside the root — which is what catches a path that
    ///    reaches outside through a symbolic link somebody made earlier in the same test.
    func inside(_ relative: String) throws -> URL {
        guard !relative.hasPrefix("/") else {
            throw SandboxEscape(asked: relative, why: "an absolute path is never inside a sandbox")
        }
        guard !relative.split(separator: "/").contains("..") else {
            throw SandboxEscape(asked: relative, why: "a \"..\" component climbs out of the root")
        }
        let url = home.appending(path: relative)
        let parent = url.deletingLastPathComponent().path(percentEncoded: false)
        // The parent may not exist yet, which is fine — `canonical` hands back what it was given
        // when there is nothing to resolve, and the prefix check still holds.
        let resolvedParent = QuarantineSandbox.canonical(parent)
        guard Movable.isInside(resolvedParent, any: [rootPath]) else {
            throw SandboxEscape(asked: relative,
                                why: "it resolves to \(resolvedParent), which is outside "
                                   + "\(rootPath)")
        }
        return url
    }

    /// The same guard for a URL the test already has in hand — used before every change.
    func owned(_ url: URL) throws -> String {
        let path = url.path(percentEncoded: false)
        let resolvedParent = QuarantineSandbox.canonical(
            url.deletingLastPathComponent().path(percentEncoded: false))
        guard Movable.isInside(resolvedParent, any: [rootPath]) else {
            throw SandboxEscape(asked: path, why: "it is not inside \(rootPath)")
        }
        return path
    }

    // MARK: Making things

    @discardableResult
    func file(_ relative: String, bytes: Data) throws -> URL {
        let url = try inside(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url
    }

    @discardableResult
    func file(_ relative: String, _ contents: String = "the contents") throws -> URL {
        try file(relative, bytes: Data(contents.utf8))
    }

    /// A file whose name lands on the disk as **exactly** these UTF-8 bytes.
    ///
    /// ⚠️ **Foundation decomposes and APFS does not.** `Data.write(to: URL)` with an NFC name
    /// creates an NFD one, and `URL.path` hands back NFD whatever went in — so every fixture built
    /// the ordinary way has an NFD name, and a suite made only of those is blind to the NFC half of
    /// the problem. APFS keeps whichever bytes it was handed, so the only way to put an NFC name on
    /// the disk is to give `open(2)` the bytes itself.
    ///
    /// Returns the path as a `String`, not a `URL`, for the same reason: a `URL` would decompose it
    /// again on the way back out.
    @discardableResult
    func fileNamed(exactly nameBytes: [UInt8], inFolder relative: String,
                   contents: String = "exactly named") throws -> String {
        let folder = try folder(relative)
        let path = folder.path(percentEncoded: false) + "/"
                 + String(decoding: nameBytes, as: UTF8.self)
        let descriptor = path.withCString { open($0, O_CREAT | O_WRONLY | O_TRUNC, 0o644) }
        guard descriptor >= 0 else {
            throw SandboxEscape(asked: path,
                                why: "could not create: \(String(cString: strerror(errno)))")
        }
        defer { close(descriptor) }
        let bytes = Array(contents.utf8)
        write(descriptor, bytes, bytes.count)
        return path
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let url = try inside(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A symbolic link. The destination is free-form on purpose — a link pointing at nothing, or at
    /// somewhere outside, is a thing that exists on real Macs and the engine has to survive both.
    /// Only the link *itself* is written, and only inside the sandbox.
    @discardableResult
    func link(_ relative: String, to destination: String) throws -> URL {
        let url = try inside(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path(percentEncoded: false),
                                                   withDestinationPath: destination)
        return url
    }

    /// A second name for the same inode, which is what makes hard-link splitting visible.
    @discardableResult
    func hardLink(_ relative: String, to existing: URL) throws -> URL {
        let url = try inside(relative)
        let target = try owned(existing)
        guard Darwin.link(target, url.path(percentEncoded: false)) == 0 else {
            throw SandboxEscape(asked: relative,
                                why: "link(2) failed: \(String(cString: strerror(errno)))")
        }
        return url
    }

    // MARK: Changing things — each one guarded

    func setFlags(_ flags: UInt32, on url: URL) throws {
        let path = try owned(url)
        guard chflags(path, flags) == 0 else {
            throw SandboxEscape(asked: path,
                                why: "chflags failed: \(String(cString: strerror(errno)))")
        }
    }

    func setMode(_ mode: UInt16, on url: URL) throws {
        let path = try owned(url)
        guard chmod(path, mode_t(mode)) == 0 else {
            throw SandboxEscape(asked: path,
                                why: "chmod failed: \(String(cString: strerror(errno)))")
        }
    }

    func setExtendedAttribute(_ name: String, to value: Data, on url: URL) throws {
        let path = try owned(url)
        let result = value.withUnsafeBytes {
            setxattr(path, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW)
        }
        guard result == 0 else {
            throw SandboxEscape(asked: path,
                                why: "setxattr \(name) failed: \(String(cString: strerror(errno)))")
        }
    }

    /// Write a resource fork the way the filesystem exposes one — a second stream at
    /// `…/..namedfork/rsrc`. This is the real thing and not an extended attribute pretending.
    func setResourceFork(_ bytes: Data, on url: URL) throws {
        let path = try owned(url)
        let descriptor = open(path + "/..namedfork/rsrc", O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else {
            throw SandboxEscape(asked: path,
                                why: "the resource fork would not open: "
                                   + String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, bytes.count) }
        guard written == bytes.count else {
            throw SandboxEscape(asked: path, why: "the resource fork was written short")
        }
    }

    /// Add an access control entry, using the tool macOS ships for it. `chmod +a` needs no
    /// privilege for a file this user owns and puts up no dialog.
    func addAccessControlEntry(_ entry: String, on url: URL) throws {
        let path = try owned(url)
        try run("/bin/chmod", ["+a", entry, path])
    }

    /// A file macOS itself has compressed. `ditto --hfsCompression` is the only way to make one
    /// without a third-party tool, and it does work on APFS — measured, not assumed.
    @discardableResult
    func compressedCopy(of source: URL, at relative: String) throws -> URL {
        let destination = try inside(relative)
        try run("/usr/bin/ditto", ["--hfsCompression",
                                   try owned(source),
                                   destination.path(percentEncoded: false)])
        return destination
    }

    /// A file with a very large logical size and almost no blocks behind it. A copy inflates one of
    /// these thousands of times over; a rename does not touch it.
    @discardableResult
    func sparseFile(_ relative: String, logicalBytes: Int64, tail: String = "tail") throws -> URL {
        let url = try inside(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else {
            throw SandboxEscape(asked: relative,
                                why: "could not create: \(String(cString: strerror(errno)))")
        }
        defer { close(descriptor) }
        guard ftruncate(descriptor, off_t(logicalBytes)) == 0 else {
            throw SandboxEscape(asked: relative,
                                why: "ftruncate failed: \(String(cString: strerror(errno)))")
        }
        let bytes = Array(tail.utf8)
        lseek(descriptor, off_t(logicalBytes) - off_t(bytes.count), SEEK_SET)
        write(descriptor, bytes, bytes.count)
        return url
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SandboxEscape(asked: arguments.last ?? tool,
                                why: "\(tool) exited \(process.terminationStatus)")
        }
    }

    // MARK: Looking

    /// Exists as the filesystem means it — `lstat`, so a symbolic link pointing at nothing still
    /// counts as a thing that is there. `FileManager.fileExists` follows the link and says no.
    func exists(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path(percentEncoded: false), &status) == 0
    }

    func contents(of url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    func inode(of url: URL) -> UInt64? {
        var status = stat()
        guard lstat(url.path(percentEncoded: false), &status) == 0 else { return nil }
        return UInt64(status.st_ino)
    }

    // MARK: The engine's view of this sandbox

    var reach: Reach {
        Reach(allowed: [rootPath],
              forbidden: [StorageManifest.quarantineDirectory(home: home)
                              .path(percentEncoded: false)])
    }

    var ledger: URL { StorageManifest.quarantineLedger(home: home) }
    var intent: URL { StorageManifest.quarantineIntent(home: home) }
    var store: URL { StorageManifest.quarantineDirectory(home: home) }

    // MARK: Going away again

    /// Remove the whole sandbox, whatever state a failing test left it in.
    ///
    /// Flags are cleared on the way out because a test that set `UF_IMMUTABLE` and then failed
    /// would otherwise leave a directory nothing can remove, and a hundred runs of that fills the
    /// temporary folder. The walk only ever visits paths under `rootPath`.
    func tearDown() {
        if let walker = FileManager.default.enumerator(atPath: rootPath) {
            for case let relative as String in walker {
                chflags(rootPath + "/" + relative, 0)
            }
        }
        chflags(rootPath, 0)
        try? FileManager.default.removeItem(atPath: rootPath)
    }
}

// MARK: - Everything a rename is supposed to preserve

/// The whole of a file, as far as the filesystem is concerned.
///
/// ⚠️ **Compared as one value, not field by field.** A test that asserts on a hand-written list of
/// properties proves only that the properties somebody thought of survived. This is `Equatable`, so
/// the round-trip proof is `after == before` and anything added here is covered from that moment.
struct FileFacts: Equatable, Sendable {

    /// What is actually in the thing.
    enum Content: Equatable, Sendable {
        /// A file small enough to hold in memory, byte for byte.
        case bytes([UInt8])
        /// A file too large to hold — its size, and the two ends of it. Used for the sparse file,
        /// where reading 200 MB into the test runner would be silly and the allocated block count
        /// is the reading that matters anyway.
        case largeFile(size: Int64, head: [UInt8], tail: [UInt8])
        /// A symbolic link, and exactly where it points.
        case link(String)
        /// A folder, as relative path → bytes, sorted by the dictionary.
        case tree([String: [UInt8]])
        case unreadable(String)
    }

    /// ⚠️ The exact UTF-8 of the last path component. Not a `String` compared with `==`, which
    /// would call an NFD spelling equal to its NFC twin — and telling those apart is the whole
    /// point on a filesystem that folds normalisation.
    var nameBytes: [UInt8]

    var mode: UInt16
    var ownerID: UInt32
    var groupID: UInt32
    var flags: UInt32
    var linkCount: UInt16
    var size: Int64
    /// 512-byte blocks actually allocated. This is what makes sparseness visible: a 200 MB sparse
    /// file has 32 of these, and a copy of it has 409,600.
    var allocatedBlocks: Int64
    var inode: UInt64

    var createdSeconds: Int64
    var createdNanoseconds: Int64
    var modifiedSeconds: Int64
    var modifiedNanoseconds: Int64

    /// Every extended attribute, by name. Read with `XATTR_SHOWCOMPRESSION`, or a compressed file
    /// hides `com.apple.decmpfs` and its resource fork and the comparison passes for the wrong
    /// reason.
    var extendedAttributes: [String: [UInt8]]

    /// The second stream at `…/..namedfork/rsrc`, when there is one.
    var resourceFork: [UInt8]?

    /// `acl_to_text` of the extended ACL, or `nil` when there is none.
    var accessControlList: String?

    var content: Content

    // MARK: Taking one

    /// Read everything about `url` in one pass. `lstat` throughout: a symbolic link is a thing in
    /// its own right and following it here would describe the wrong file.
    static func take(of url: URL) -> FileFacts? {
        let path = url.path(percentEncoded: false)
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }

        let isDirectory = (status.st_mode & S_IFMT) == S_IFDIR
        let isLink = (status.st_mode & S_IFMT) == S_IFLNK

        return FileFacts(
            nameBytes: Array(url.lastPathComponent.utf8),
            mode: UInt16(status.st_mode & 0o7777),
            ownerID: status.st_uid,
            groupID: status.st_gid,
            flags: status.st_flags,
            linkCount: status.st_nlink,
            size: Int64(status.st_size),
            allocatedBlocks: Int64(status.st_blocks),
            inode: UInt64(status.st_ino),
            createdSeconds: Int64(status.st_birthtimespec.tv_sec),
            createdNanoseconds: Int64(status.st_birthtimespec.tv_nsec),
            modifiedSeconds: Int64(status.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(status.st_mtimespec.tv_nsec),
            extendedAttributes: extendedAttributes(at: path),
            resourceFork: resourceFork(at: path),
            accessControlList: accessControlList(at: path),
            content: content(at: url, status: status,
                             isDirectory: isDirectory, isLink: isLink))
    }

    /// The facts that must be identical after a move, with the ones that are *allowed* to differ
    /// removed. Only the name may differ, and only when the caller says so — a restore puts the
    /// file back under its own name, so even that is normally compared.
    func ignoringName() -> FileFacts {
        var copy = self
        copy.nameBytes = []
        return copy
    }

    /// What is different between two readings, named one by one.
    ///
    /// `Equatable` decides whether the round trip lost something; this decides what the failure
    /// message says. "the creation date changed" and "2 extended attributes were lost" are worth a
    /// great deal more to whoever reads a red test than two four-hundred-line struct dumps.
    ///
    /// ⚠️ `st_ctime` is deliberately not among the facts. A rename legitimately bumps the inode
    /// change time — that is what it means — and asserting on it would fail every honest move.
    func differences(from other: FileFacts) -> [String] {
        var found: [String] = []
        func check(_ label: String, _ same: Bool) { if !same { found.append(label) } }

        check("the name", nameBytes == other.nameBytes)
        check("the permissions", mode == other.mode)
        check("the owner", ownerID == other.ownerID)
        check("the group", groupID == other.groupID)
        check("the BSD flags (compression lives here)", flags == other.flags)
        check("the number of hard links", linkCount == other.linkCount)
        check("the size", size == other.size)
        check("the allocated blocks (sparseness lives here)",
              allocatedBlocks == other.allocatedBlocks)
        check("the inode — this was a copy, not a move", inode == other.inode)
        check("the creation date",
              createdSeconds == other.createdSeconds
                  && createdNanoseconds == other.createdNanoseconds)
        check("the modification date",
              modifiedSeconds == other.modifiedSeconds
                  && modifiedNanoseconds == other.modifiedNanoseconds)
        check("the access control list", accessControlList == other.accessControlList)
        check("the resource fork", resourceFork == other.resourceFork)
        check("the contents", content == other.content)

        let lost = Set(other.extendedAttributes.keys).subtracting(extendedAttributes.keys)
        let gained = Set(extendedAttributes.keys).subtracting(other.extendedAttributes.keys)
        let changed = extendedAttributes.keys.filter {
            other.extendedAttributes[$0] != nil && other.extendedAttributes[$0] != extendedAttributes[$0]
        }
        if !lost.isEmpty { found.append("extended attributes lost: \(lost.sorted())") }
        if !gained.isEmpty { found.append("extended attributes appeared: \(gained.sorted())") }
        if !changed.isEmpty { found.append("extended attributes changed: \(changed.sorted())") }

        return found
    }

    // MARK: The readings

    private static func extendedAttributes(at path: String) -> [String: [UInt8]] {
        let options = XATTR_NOFOLLOW | XATTR_SHOWCOMPRESSION
        let listSize = listxattr(path, nil, 0, options)
        guard listSize > 0 else { return [:] }

        var raw = [CChar](repeating: 0, count: listSize)
        guard listxattr(path, &raw, listSize, options) == listSize else { return [:] }

        let names = raw.map { UInt8(bitPattern: $0) }
            .split(separator: 0)
            .map { String(decoding: $0, as: UTF8.self) }

        var found: [String: [UInt8]] = [:]
        for name in names {
            let size = getxattr(path, name, nil, 0, 0, options)
            guard size >= 0 else { continue }
            var value = [UInt8](repeating: 0, count: size)
            if size == 0 { found[name] = []; continue }
            guard getxattr(path, name, &value, size, 0, options) == size else { continue }
            found[name] = value
        }
        return found
    }

    private static func resourceFork(at path: String) -> [UInt8]? {
        let descriptor = open(path + "/..namedfork/rsrc", O_RDONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let read = Darwin.read(descriptor, &buffer, buffer.count)
            if read <= 0 { break }
            bytes.append(contentsOf: buffer[0..<read])
        }
        return bytes.isEmpty ? nil : bytes
    }

    /// ⚠️ `acl_get_link_np` and not `acl_get_file`: the latter follows a symbolic link and would
    /// report the target's ACL as the link's.
    private static func accessControlList(at path: String) -> String? {
        guard let acl = acl_get_link_np(path, ACL_TYPE_EXTENDED) else { return nil }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var length: ssize_t = 0
        guard let text = acl_to_text(acl, &length) else { return nil }
        defer { acl_free(UnsafeMutableRawPointer(mutating: text)) }
        return String(cString: text)
    }

    private static func content(at url: URL, status: stat,
                                isDirectory: Bool, isLink: Bool) -> Content {
        let path = url.path(percentEncoded: false)

        if isLink {
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            let length = readlink(path, &buffer, buffer.count)
            guard length > 0 else { return .unreadable("readlink failed") }
            return .link(String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) },
                                as: UTF8.self))
        }

        if isDirectory {
            var tree: [String: [UInt8]] = [:]
            guard let walker = FileManager.default.enumerator(atPath: path) else {
                return .unreadable("the folder could not be walked")
            }
            for case let relative as String in walker {
                let child = path + "/" + relative
                var childStatus = stat()
                guard lstat(child, &childStatus) == 0 else { continue }
                if (childStatus.st_mode & S_IFMT) == S_IFDIR { tree[relative + "/"] = []; continue }
                tree[relative] = Array((try? Data(contentsOf: URL(filePath: child))) ?? Data())
            }
            return .tree(tree)
        }

        let size = Int64(status.st_size)
        // A megabyte is the line between "hold the whole thing and compare it" and "compare the
        // ends and the block count". The only fixture above it is the sparse file, which is
        // deliberately 200 MB of nothing.
        guard size <= 1_048_576 else {
            let descriptor = open(path, O_RDONLY)
            guard descriptor >= 0 else { return .unreadable("could not open") }
            defer { close(descriptor) }
            var head = [UInt8](repeating: 0, count: 4096)
            var tail = [UInt8](repeating: 0, count: 4096)
            _ = pread(descriptor, &head, head.count, 0)
            _ = pread(descriptor, &tail, tail.count, off_t(size) - off_t(tail.count))
            return .largeFile(size: size, head: head, tail: tail)
        }

        guard let data = try? Data(contentsOf: url) else { return .unreadable("could not read") }
        return .bytes(Array(data))
    }
}
