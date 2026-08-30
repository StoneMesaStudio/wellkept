import Foundation

//  VirtualMachine.swift
//  Wellkept — App/Hardware
//
//  **Is this a real Mac, or a Mac-shaped file on somebody's disk?**
//
//  ## Why the Hardware section has to ask
//
//  Every reading in this section is fiction inside a virtual machine, and the fiction is
//  convincing. A VM reports a model identifier, a chip, a memory size and a drive; Parallels and
//  VMware will happily report a *battery*, invented, at a percentage that never moves. The
//  failure this file prevents is Wellkept printing a confident verdict — "the battery is at 100%,
//  everything is fine" — about a battery that does not exist. One screenshot of that costs more
//  credibility than the whole section earns.
//
//  It also matters for the honest reason: the app's permission and helper flows are meant to be
//  tested on a clean VM rather than on an already-upgraded M3. That is exactly the machine where the
//  readings are least real, so the app has to say so on screen rather than in a release note.
//
//  ## How it decides, cheapest first
//
//  All read-only, all without a permission, all without IOKit:
//
//  1. **`kern.hv_vmm_present`** — the kernel's own answer, macOS 11 and later. It says whether
//     this copy of macOS is running as a guest, not whether a hypervisor is installed: Docker or
//     a VM running *on* this Mac leaves it at zero. This is the reliable one.
//  2. **`hw.model`** — the identifier itself names the host on every product that matters:
//     Apple's own Virtualization framework reports `VirtualMac2,1`, VMware reports `VMware20,1`,
//     Parallels and VirtualBox say so in words.
//  3. **`machdep.cpu.features` containing `VMM`** — Intel only, and the fallback for a guest old
//     enough to predate the first check.
//
//  ⚠️ **Two directions of wrongness, and they are not equal.** Missing a VM prints a confident
//  lie. Falsely calling a real Mac a VM prints a caveat on a machine that does not need one,
//  which is annoying and visibly wrong to the person reading it. Both are bad, so nothing here
//  guesses from something ambiguous — no "the serial number looks odd", no timing tricks. Three
//  checks, each of which is either true or absent, and the evidence is kept so the row can say
//  which one fired.

struct VirtualMachine: Sendable, Hashable {

    /// Who is running the guest, where the machine says so.
    enum Host: String, Sendable, Hashable, CaseIterable {
        case appleVirtualization
        case parallels
        case vmware
        case virtualBox
        case qemu
        /// Something said this is a guest, but nothing said what kind. Still a VM.
        case unknown

        var label: String {
            switch self {
            case .appleVirtualization: "Apple's Virtualization framework"
            case .parallels:           "Parallels"
            case .vmware:              "VMware"
            case .virtualBox:          "VirtualBox"
            case .qemu:                "QEMU"
            case .unknown:             "a virtual machine"
            }
        }
    }

    let isVirtual: Bool
    /// `nil` on real hardware.
    let host: Host?
    /// Whatever `hw.model` returned, kept verbatim. On a real Mac this is the identifier the rest
    /// of the section looks up; inside a guest it is usually the thing that gave the guest away.
    let hardwareModel: String
    /// Which checks fired, in the words of the check. Shown behind **Options**, so a person who
    /// disagrees with the verdict can see what it was based on.
    let evidence: [String]

    /// The line for the "what this Mac is" block. Empty on real hardware — a real Mac gets no
    /// sentence saying it is real.
    var sentence: String {
        guard isVirtual else { return "" }
        let who = host?.label ?? Host.unknown.label
        return "This is a virtual machine running under \(who). The hardware readings below "
             + "describe what the virtual machine claims, not a physical Mac."
    }

    /// The answer for this process, worked out once.
    ///
    /// Nothing about it can change while the app is running: a process does not move between a
    /// guest and real hardware. Computed lazily on first use so an app that never opens Hardware
    /// never runs a single `sysctl`.
    static let current: VirtualMachine = detect()

    // MARK: - Detection

    /// Run the checks. Public so a test can call it without going through the cached value.
    static func detect() -> VirtualMachine {
        let model = sysctlString("hw.model") ?? ""
        var evidence: [String] = []
        var host: Host?

        // 1. The kernel's own answer.
        if let present = sysctlInt("kern.hv_vmm_present"), present != 0 {
            evidence.append("The kernel reports that macOS is running as a guest.")
        }

        // 2. The model identifier, which names the host on everything that matters.
        if let named = hostNamed(by: model) {
            host = named
            evidence.append("The model identifier is “\(model)”.")
        }

        // 3. Intel's CPU feature flag, for a guest older than the first check.
        if let features = sysctlString("machdep.cpu.features"),
           features.split(separator: " ").contains("VMM") {
            evidence.append("The processor reports that it is virtualised.")
        }

        return VirtualMachine(isVirtual: !evidence.isEmpty,
                              host: evidence.isEmpty ? nil : (host ?? .unknown),
                              hardwareModel: model,
                              evidence: evidence)
    }

    /// The host a model identifier names, or `nil` for a string that names no host.
    ///
    /// ⚠️ Matched case-insensitively and by prefix, never by equality: `VMware20,1` and
    /// `VMware7,1` are the same product, and the number will keep going up.
    static func hostNamed(by model: String) -> Host? {
        let lowered = model.lowercased()
        // Apple's own guest identifier. It is deliberately Mac-shaped, which is exactly why it has
        // to be recognised here — nothing else about the machine will admit to being virtual.
        if lowered.hasPrefix("virtualmac") { return .appleVirtualization }
        if lowered.contains("vmware")      { return .vmware }
        if lowered.contains("parallels")   { return .parallels }
        if lowered.contains("virtualbox")  { return .virtualBox }
        if lowered.contains("qemu")        { return .qemu }
        return nil
    }

    // MARK: - sysctl

    /// A `sysctl` string, or `nil` where the name does not exist on this kernel.
    ///
    /// Two calls: one to learn the length, one to read it. Sized from the kernel rather than from
    /// a fixed buffer, because `machdep.cpu.features` is a few hundred bytes on some Intel parts
    /// and a truncated feature list would silently drop the flag being looked for.
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        // Stop at the terminator rather than decoding the whole buffer: the trailing NUL would
        // otherwise become a character in the string, and a model identifier with an invisible
        // extra character matches nothing in `MacModels`.
        let text = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A `sysctl` integer, or `nil` where the name does not exist.
    ///
    /// `kern.hv_vmm_present` is a 32-bit int, and asking for a differently sized value is how this
    /// kind of call returns a plausible number made of adjacent memory. The size the kernel
    /// reports is checked against what is being read rather than assumed.
    static func sysctlInt(_ name: String) -> Int? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }

        if size == MemoryLayout<Int32>.size {
            var value: Int32 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return Int(value)
        }
        if size == MemoryLayout<Int64>.size {
            var value: Int64 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return Int(value)
        }
        return nil
    }
}
