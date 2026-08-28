// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  QuarantineSandbox.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **A whole pretend home folder, thrown away at the end of every test.**
//
//  The quarantine engine is the one component in Wellkept that moves somebody's files. So the suite
//  that exercises it is not allowed anywhere near a real one, and this type is what makes that
//  structural rather than careful: every entry point in the engine takes `home:`, and every test
//  passes a directory it made itself thirty milliseconds earlier.
//
//  ⚠️ **The path is resolved through its symlinks on purpose.** `FileManager.temporaryDirectory` is
//  under `/var/folders/…`, and `/var` is a symlink to `/private/var`. Left unresolved, every single
//  file in this sandbox would be refused by `Movable` — correctly — for having a symbolic link in
//  its parent chain, and the suite would prove nothing except that the guard works on `/var`. That
//  is tested deliberately, once, with a link the test makes itself.

struct QuarantineSandbox {

    /// The pretend home folder. Everything the engine writes goes under here and nowhere else.
    let home: URL

    private let fileManager = FileManager.default

    init() throws {
        // ⚠️ `realpath`, not `URL.resolvingSymlinksInPath()`. Foundation's version does the
        // opposite of what is needed here: it *strips* a leading `/private`, so the temporary
        // directory keeps coming back as `/var/folders/…` — and `/var` is itself a symlink to
        // `/private/var`. Left that way, every file in the sandbox is refused for having a
        // symbolic link in its parent chain, which is correct behaviour proving nothing.
        home = URL(filePath: Self.canonical(FileManager.default.temporaryDirectory
                                                .path(percentEncoded: false)))
            .appending(path: "Wellkept-quarantine-tests")
            .appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    /// The path as the filesystem spells it, symlinks and all resolved.
    static func canonical(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return path }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                      as: UTF8.self)
    }

    /// Remove the whole sandbox. Called from every test's `defer`.
    func tearDown() {
        // A test that set an immutable flag and failed before clearing it would otherwise leave a
        // directory nothing can remove. Clearing flags on the way out costs nothing and keeps the
        // temporary folder from filling up over a hundred runs.
        if let walker = fileManager.enumerator(at: home, includingPropertiesForKeys: nil) {
            for case let url as URL in walker { chflags(url.path(percentEncoded: false), 0) }
        }
        try? fileManager.removeItem(at: home)
    }

    /// A file inside the sandbox, with its folders made for it.
    @discardableResult
    func file(_ relativePath: String, contents: String = "the contents") throws -> URL {
        let url = home.appending(path: relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @discardableResult
    func folder(_ relativePath: String) throws -> URL {
        let url = home.appending(path: relativePath)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A symbolic link inside the sandbox, for the tests that prove the engine refuses to act
    /// through one.
    @discardableResult
    func link(_ relativePath: String, to target: URL) throws -> URL {
        let url = home.appending(path: relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: url, withDestinationURL: target)
        return url
    }

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    func contents(of url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The inode, which is what a same-volume rename preserves and a copy does not.
    func inode(of url: URL) -> UInt64? {
        var status = stat()
        guard lstat(url.path(percentEncoded: false), &status) == 0 else { return nil }
        return UInt64(status.st_ino)
    }

    func mode(of url: URL) -> UInt16? {
        var status = stat()
        guard lstat(url.path(percentEncoded: false), &status) == 0 else { return nil }
        return UInt16(status.st_mode & 0o7777)
    }

    /// The reach the engine gets in these tests: this sandbox, and nothing else.
    var reach: Reach {
        Reach(allowed: [home.path(percentEncoded: false)],
              forbidden: [StorageManifest.quarantineDirectory(home: home)
                              .path(percentEncoded: false)])
    }

    var ledger: URL { StorageManifest.quarantineLedger(home: home) }
    var intent: URL { StorageManifest.quarantineIntent(home: home) }
    var store: URL { StorageManifest.quarantineDirectory(home: home) }

    /// A `UserDefaults` of its own, so a test cannot touch the real preferences.
    static func defaults(_ label: String) -> UserDefaults {
        UserDefaults(suiteName: "wellkept.quarantine.tests.\(label).\(UUID().uuidString)")!
    }

    static func forget(_ defaults: UserDefaults, named label: String) {
        for key in defaults.dictionaryRepresentation().keys { defaults.removeObject(forKey: key) }
    }
}
