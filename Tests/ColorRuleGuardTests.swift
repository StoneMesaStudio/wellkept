import Testing
import Foundation

/// ⭐ **The readability rule, enforced by something other than good intentions.**
///
/// `~/Sites/DESIGN.md` §3.5 states it, measured on macOS 26.6.2: AppKit's `secondaryLabelColor`
/// scores **3.95∶1** on white against Apple's own 4.5∶1 bar, and `tertiaryLabelColor` **1.88∶1** —
/// which fails even the 3∶1 large-text bar. Neither moves under the accessibility high-contrast
/// appearance. `Theme.textSecondary` (0.78 of `.primary`) and `Theme.textTertiary` (0.62) replace
/// them, and "every view uses these instead of the system pair" is the kind of sentence that lives
/// in a comment and drifts in a dozen places before anybody looks.
///
/// **This file exists before the view files it guards.** That is the whole point of writing it
/// now: in Lode it was written after the drift, and fixing what it found took longer than the
/// guard did. Here it is in place while `App/` holds six files, so the first violation is caught
/// the first time somebody types it.
///
/// Ported from `lode/Core/Tests/TesseraCoreTests/ColorRuleGuardTests.swift`, which is the only
/// thing that has ever stopped this rule from drifting in this house. The machinery is unchanged;
/// the paths, the roots and the exemptions are Wellkept's.
///
/// The whole difficulty of this guard is that **a bare `.secondary` is not by itself a defect.**
/// The same token is correct as a background wash behind a capsule, as a dashed border, as a chart
/// series colour, and as the swatch in a legend that has to match that series. Flagging those
/// would turn a readability guard into a generator of visual regressions — changing a chart line's
/// colour because a scanner could not tell a line from a label. So this file does not grep. It
/// reads the call, works out what the colour is *applied to*, and only then decides.
///
/// Three scans, in increasing order of how much they can catch and how much they can get wrong:
///
///  1. **Text foregrounds** — every `.foregroundStyle(…)` / `.foregroundColor(…)` argument, taken
///     with balanced-paren matching so a ternary (`ok ? Color.secondary : palette.attention`) is
///     read whole. Chart marks are exempt, structurally and by name.
///  2. **Shared-component defaults** — `var tint: Color = .secondary` on a type that then paints
///     it through `foregroundStyle`. A bad default is worse than a bad call site: it is one line
///     that makes every caller wrong at once.
///  3. **Colours handed over indirectly** — a `Color` put into a tuple or a local and applied
///     somewhere else entirely, which scan 1 sees at neither end.
///
/// ⚠️ **What this guard cannot see, stated rather than left to be discovered.** Scan 3 works out
/// what a colour *is* by reading the nearest enclosing declaration for the word `Color`. That is a
/// text heuristic, not type-checking. If a colour is passed through something it cannot read — a
/// `@State` property, a dictionary, an enum's `var color` — it will not be caught, and nobody
/// should read a green run here as proof that every supporting colour in the app is right.
@Suite struct ColorRuleGuardTests {

    // MARK: - Repo access

    /// The repository root, from this file's own path. Stable in a checkout, which is where tests
    /// run.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)            // …/Tests/<this file>
            .deletingLastPathComponent()           // …/Tests
            .deletingLastPathComponent()           // …/  (repo root)
    }

    /// Every Swift file that can paint something.
    ///
    /// `Tools` is scanned as well as `App`, and deliberately: the ViewShots harness assembles real
    /// screens out of the same vocabulary, and a shot that draws its own labels in a colour the app
    /// forbids would photograph a screen nobody is going to ship.
    private static let scannedRoots = ["App", "Tools"]

    private static func swiftFiles(under roots: [String] = ColorRuleGuardTests.scannedRoots) -> [URL] {
        roots.flatMap { relative -> [URL] in
            let root = repoRoot.appendingPathComponent(relative)
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else { return [] }
            return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }.sorted { $0.path < $1.path }
    }

    // MARK: - Reading source

    /// The file's lines with comments removed and the line structure kept.
    ///
    /// Walks characters rather than reaching for a regex, for two reasons: a `//` inside a string
    /// is not a comment (this codebase is full of `https://` literals and of hex colours), and an
    /// escaped quote does not end a literal. Line structure is preserved because every scan below
    /// reports a line number and walks backwards through the modifier chain.
    ///
    /// ⚠️ **Comments are stripped rather than searched, and that is load-bearing.** This codebase
    /// documents its defects in comments — `Palette.swift` line 429 spells out the banned token in
    /// prose to explain why it is banned. A guard that read comments would fail on its own paper
    /// trail, and the paper trail would then be deleted to make it pass. That is the worst outcome
    /// available here.
    static func codeLines(of source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let chars = Array(line)
            var out = "", i = 0, inString = false
            while i < chars.count {
                let c = chars[i]
                if inString {
                    if c == "\\", i + 1 < chars.count { out.append(c); out.append(chars[i + 1]); i += 2; continue }
                    if c == "\"" { inString = false }
                    out.append(c); i += 1; continue
                }
                if c == "\"" { inString = true; out.append(c); i += 1; continue }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "/" { break }   // line comment
                out.append(c); i += 1
            }
            return out
        }
    }

    /// The argument of a call, given the index of its opening `(`.
    ///
    /// ⚠️ **Balanced, and string-aware.** Stopping at the first `)` would read
    /// `.foregroundStyle(color(tone))` as `color(tone` and, far worse, would read
    /// `.foregroundStyle(ok ? Color.secondary : palette.attention)` correctly only by luck — the
    /// real failure is `.foregroundStyle(x.map { f($0) } ?? .secondary)`, where the token that
    /// matters is past the first close paren. A ternary is a genuine text use and has to be caught
    /// whole.
    static func balancedArgument(_ chars: [Character], openParenAt open: Int) -> String? {
        var depth = 0, i = open, inString = false
        var out = ""
        while i < chars.count {
            let c = chars[i]
            if inString {
                if c == "\\", i + 1 < chars.count { out.append(c); out.append(chars[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                out.append(c); i += 1; continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "(" {
                depth += 1
                if depth == 1 { i += 1; continue }        // don't include the opening paren itself
            }
            if c == ")" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c); i += 1
        }
        return nil   // unbalanced to end of window — the caller widens or gives up
    }

    // MARK: - What counts as "a bare system supporting colour"

    private static let styleNames = ["secondary", "tertiary"]

    /// The identifiers a `.secondary` may be hanging off and still be **the system style**.
    ///
    /// ⚠️ Allow-listed rather than deny-listed, and the difference is `.background.secondary` — the
    /// AppKit *material*, which is a legitimate surface. Its token is spelled identically to the
    /// text style and is told apart only by what precedes the dot. Anything with a prefix that is
    /// not on this list (`palette.`, some future style bag) is left alone: the scan would rather
    /// miss a novel spelling than repaint a background it did not understand.
    private static let systemStylePrefixes: Set<String> = ["", "Color", "ShapeStyle", "HierarchicalShapeStyle"]

    /// Every bare `.secondary` / `.tertiary` in a fragment of code.
    ///
    /// `Theme.textSecondary` does not match and cannot: the needle is lower-case `.secondary`, and
    /// the replacement spells it `textSecondary` with a capital S. That is a happy accident of
    /// naming rather than a design, so it is written down here in case somebody proposes
    /// `Theme.secondary`.
    static func bareSupportingStyles(in fragment: String) -> [String] {
        let chars = Array(fragment)
        var found: [String] = []
        for name in styleNames {
            let needle = Array(".\(name)")
            var i = 0
            while i + needle.count <= chars.count {
                defer { i += 1 }
                guard Array(chars[i..<(i + needle.count)]) == needle else { continue }
                // A word boundary after, so `.secondaryLabel` and `.tertiarySystemFill` are not this.
                let after = i + needle.count
                if after < chars.count, chars[after].isLetter || chars[after].isNumber || chars[after] == "_" { continue }
                // The identifier immediately before the dot, if any.
                var j = i - 1, prefix = ""
                while j >= 0, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" {
                    prefix.insert(chars[j], at: prefix.startIndex); j -= 1
                }
                if systemStylePrefixes.contains(prefix) { found.append(".\(name)") }
            }
        }
        return found
    }

    // MARK: - The exemption: chart marks

    /// Swift Charts marks. **The legitimate exemption, written out rather than left implicit.**
    ///
    /// DESIGN.md §14.2 gives charts their own rules and exempts chart colour from the colour dial
    /// at every level, because twenty-five near-greys are twenty-five indistinguishable greys. A
    /// `LineMark` or a `RuleMark` tinted `.secondary` is a series or a gridline. None of them is
    /// text.
    ///
    /// Wellkept has no charts yet. The exemption is here anyway, because the day the first one
    /// arrives is the day somebody would otherwise "fix" a gridline into `Theme.textSecondary` and
    /// wonder why the chart went muddy.
    ///
    /// ⚠️ **A legend swatch is exempt for a second and stronger reason.** A legend chip passes the
    /// same colour into `Circle().fill(…)` while its *label* is already `Theme.textSecondary`.
    /// Repainting the swatch would make the legend disagree with the line it identifies — a worse
    /// defect than the one being fixed, and one no test would catch. Those sites are not
    /// `foregroundStyle` calls at all, so no scan below reaches them; this note exists so the next
    /// person to widen the scan knows to leave them alone.
    private static let chartMarks = [
        "LineMark(", "PointMark(", "AreaMark(", "RuleMark(", "BarMark(",
        "RectangleMark(", "SectorMark(",
    ]

    /// The **head of the modifier chain** a `foregroundStyle` sits on — i.e. what is being painted.
    ///
    /// ⚠️ This is the part that has to be right, and a fixed look-back window is not good enough.
    /// A chart mark's own tint and the text inside its `.annotation { }` closure are three lines
    /// apart:
    ///
    ///     RuleMark(x: .value("Threshold", 0.9))               ← head for the line below
    ///         .foregroundStyle(Color.secondary.opacity(0.5))  ← exempt: a gridline
    ///         .lineStyle(…)
    ///         .annotation(position: .top) {
    ///             Text("90% full").foregroundStyle(…)         ← head is `Text(` — NOT exempt
    ///         }
    ///
    /// So it walks back over lines that are pure chain continuations (a leading `.`), then keeps
    /// absorbing lines while the parentheses are still open, because a wrapped argument list leaves
    /// the head one line further up.
    ///
    /// The walk is bounded, and **a walk that runs out of budget returns what it has** rather than
    /// giving up — so a confused scan flags rather than silently exempts. A false positive is a
    /// line somebody reads; a false exemption is the defect this file exists to stop.
    static func chainHead(_ lines: [String], at index: Int) -> String {
        var j = index
        while j > 0, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix(".") { j -= 1 }
        var head = j
        var balance = parenBalance(lines[j])
        var budget = 8
        while head > 0, balance < 0, budget > 0 {
            head -= 1; budget -= 1
            balance += parenBalance(lines[head])
        }
        return lines[head...j].joined(separator: " ")
    }

    /// `(` minus `)` on a line, ignoring both string contents and comments (already stripped).
    private static func parenBalance(_ line: String) -> Int {
        var depth = 0, inString = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inString {
                if c == "\\" { i = line.index(i, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex; continue }
                if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            i = line.index(after: i)
        }
        return depth
    }

    // MARK: - The allow-list
    //
    // ⚠️ **Exemptions are listed with a reason, never taken by omission.** A site that is fine on
    // purpose and a site nobody looked at are indistinguishable once one of them is simply absent,
    // and the second kind is how three of the defects the Lode original fixed survived a
    // readability pass.
    //
    // Keyed by file name and scoped to ONE scan, so an entry cannot quietly excuse a different
    // violation that appears in the same file later.

    /// Scan 1 (text foregrounds). Empty, and expected to stay that way — every legitimate case is
    /// exempted structurally by `chainHead` rather than by naming a file.
    private static let textForegroundExemptions: [String: String] = [:]

    /// Scan 3 (colours handed over indirectly). Empty.
    private static let indirectColorExemptions: [String: String] = [:]

    // MARK: - Scan 1: a bare supporting colour used as a TEXT foreground

    @Test func noBareSystemColourPaintsText() throws {
        var offences: [String] = []
        for file in Self.swiftFiles() {
            let name = file.lastPathComponent
            if Self.textForegroundExemptions[name] != nil { continue }
            let lines = Self.codeLines(of: try String(contentsOf: file, encoding: .utf8))
            for (i, line) in lines.enumerated() {
                for call in [".foregroundStyle(", ".foregroundColor("] {
                    var search = line.startIndex
                    while let r = line.range(of: call, range: search..<line.endIndex) {
                        search = r.upperBound
                        // The argument can wrap, so match against this line plus the next few.
                        let window = lines[i...min(i + 4, lines.count - 1)].joined(separator: "\n")
                        let openOffset = line.distance(from: line.startIndex, to: r.upperBound) - 1
                        guard let arg = Self.balancedArgument(Array(window), openParenAt: openOffset),
                              !Self.bareSupportingStyles(in: arg).isEmpty else { continue }
                        let head = Self.chainHead(lines, at: i)
                        if Self.chartMarks.contains(where: { head.contains($0) }) { continue }
                        offences.append("\(name):\(i + 1) — \(arg.trimmingCharacters(in: .whitespaces).prefix(90))")
                    }
                }
            }
        }
        #expect(offences.isEmpty, """
            A bare `.secondary` / `.tertiary` is painting TEXT: \(offences.joined(separator: "\n  ")).
            Use `Theme.textSecondary` (0.78 of .primary) or `Theme.textTertiary` (0.62). Measured on \
            macOS 26.6.2, AppKit's pair scores 3.95∶1 and 1.88∶1 on white against Apple's own 4.5∶1 \
            bar, and neither moves under high contrast. If the site is genuinely a chart mark or a \
            legend swatch, say so in `textForegroundExemptions` with a reason; do NOT fix it by \
            deleting the call.
            """)
    }

    // MARK: - Scan 2: a shared component whose DEFAULT is a bare supporting colour

    /// ⚠️ **A bad default is worse than a bad call site.** One line makes every caller that did not
    /// override it wrong, which is exactly the shape a per-call-site scan reports as "no violations
    /// here".
    @Test func noSharedComponentDefaultsToABareSystemColour() throws {
        var offences: [String] = []
        for file in Self.swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let lines = Self.codeLines(of: source)
            let paints = lines.contains { $0.contains("foregroundStyle(") || $0.contains("foregroundColor(") }
            guard paints else { continue }
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.contains("var "), t.contains(": Color"), let eq = t.range(of: "= ") else { continue }
                let defaultValue = String(t[eq.upperBound...])
                guard !Self.bareSupportingStyles(in: defaultValue).isEmpty else { continue }
                // Only a default that the type actually PAINTS is a readability defect. A property
                // used solely as a fill is a background, and the same rule as everywhere else
                // applies.
                let property = t.range(of: "var ").map { String(t[$0.upperBound...].prefix(while: { $0 != ":" })) }?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                let painted = lines.contains {
                    ($0.contains("foregroundStyle(") || $0.contains("foregroundColor(")) && $0.contains(property)
                }
                if painted {
                    offences.append("\(file.lastPathComponent):\(i + 1) — \(t.prefix(80))")
                }
            }
        }
        #expect(offences.isEmpty, """
            A shared view's colour DEFAULT is a bare system style, and the view paints it as text: \
            \(offences.joined(separator: "\n  ")).
            Default it to `Theme.textSecondary` instead. ⚠️ If the same property is also used as a \
            capsule fill, read the note on that property before changing it — the wash moves with \
            the label.
            """)
    }

    // MARK: - Scan 3: a Color handed over indirectly, painted somewhere else

    /// ⚠️ **The call site and the `foregroundStyle` are in different places.** A function that
    /// returns `("—", .secondary)` as a `(text: String, color: Color)` tuple, painted seventy lines
    /// further down by `.foregroundStyle(row.color)`, is invisible to scan 1: the tuple has no
    /// `foregroundStyle`, and the `foregroundStyle` has no `.secondary`.
    ///
    /// So this scan reads the nearest enclosing declaration and asks whether the thing being built
    /// is a `Color`. Two deliberate exclusions keep it honest:
    ///
    ///  - **`case ` lines are skipped.** An enum whose cases are literally named `.secondary`, with
    ///    `case .secondary: Theme.textSecondary` inside a `func … -> Color`, would otherwise be
    ///    reported — that is, the fix reported as the bug.
    ///  - **Lines already covered by scan 1 are skipped**, so one defect is not reported twice.
    @Test func noBareSystemColourIsHandedOverAsAColorValue() throws {
        var offences: [String] = []
        for file in Self.swiftFiles() {
            let name = file.lastPathComponent
            if Self.indirectColorExemptions[name] != nil { continue }
            let lines = Self.codeLines(of: try String(contentsOf: file, encoding: .utf8))
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("case ") { continue }                     // a switch pattern, not a value
                if line.contains("foregroundStyle(") || line.contains("foregroundColor(") { continue }
                guard !Self.bareSupportingStyles(in: line).isEmpty else { continue }
                guard let decl = Self.enclosingDeclaration(lines, at: i), decl.contains("Color") else { continue }
                offences.append("\(name):\(i + 1) — \(t.prefix(90))")
            }
        }
        #expect(offences.isEmpty, """
            A bare `.secondary` / `.tertiary` is being stored as a `Color` and painted elsewhere: \
            \(offences.joined(separator: "\n  ")).
            Follow it to the `foregroundStyle` that applies it. If it lands on text, use \
            `Theme.textSecondary`; if it lands on a chart swatch that must match a series, add the \
            file to `indirectColorExemptions` and say which series.
            """)
    }

    /// The nearest preceding declaration — what the value on this line is being built into.
    ///
    /// ⚠️ **An optional binding is not a declaration**, and reading it as one produced the Lode
    /// scan's only false positive: `if let v = valueAt(date) { calloutRow("Current",
    /// Color.secondary, v) }` matched itself on `" let "`, and because the *rest* of that same line
    /// contains the word `Color`, a legend swatch was reported as a text defect. `if` / `guard` /
    /// `while` are excluded for that reason.
    ///
    /// Bounded at 80 lines, and `nil` past that: a colour whose declaration is that far away is not
    /// something this heuristic can honestly claim to have read, and saying nothing is better than
    /// asserting.
    static func enclosingDeclaration(_ lines: [String], at index: Int) -> String? {
        var j = index
        while j >= 0, index - j <= 80 {
            let t = lines[j].trimmingCharacters(in: .whitespaces)
            let isBinding = t.hasPrefix("if ") || t.hasPrefix("guard ") || t.hasPrefix("while ")
            if !isBinding,
               t.contains("func ") || t.hasPrefix("var ") || t.contains(" var ")
                || t.hasPrefix("let ") || t.contains(" let ") {
                return t
            }
            j -= 1
        }
        return nil
    }

    // MARK: - The allow-list has to stay honest

    /// **An exemption for a file that no longer exists is a comment pretending to be a rule.**
    @Test func everyExemptionStillPointsAtARealFile() {
        let names = Set(Self.swiftFiles().map(\.lastPathComponent))
        var stale: [String] = []
        for file in Self.textForegroundExemptions.keys where !names.contains(file) { stale.append(file) }
        for file in Self.indirectColorExemptions.keys where !names.contains(file) { stale.append(file) }
        #expect(stale.isEmpty, "Exemption(s) for files that are gone — delete the entry: \(stale)")
    }

    // MARK: - The scanner has to actually work

    /// ⚠️ **A guard that finds no files passes vacuously.** That is not a theoretical worry: this
    /// suite ships in a repo whose `App/` folder is nearly empty, so "no violations found" and "no
    /// files found" look identical from the outside. The anchor is a named file rather than a count
    /// alone — a count floor has to be raised as the app grows, and a floor nobody raises is a floor
    /// that stops meaning anything.
    @Test func theScannerReadsTheRepository() {
        let names = Set(Self.swiftFiles().map(\.lastPathComponent))
        #expect(names.contains("Palette.swift"),
                """
                The scan did not find App/Support/Palette.swift — it is looking in the wrong place, \
                and every test above is passing vacuously.
                """)
        #expect(names.contains("Scrolling.swift"))
        #expect(Self.swiftFiles().count >= 6,
                "Only \(Self.swiftFiles().count) Swift files found under \(Self.scannedRoots).")
    }

    /// The scan proved on a fixture containing one of every shape this file had to tell apart.
    ///
    /// **The fixture asserts the NEGATIVES as hard as the positive**, because getting a background
    /// or a chart line wrong here ships a visual regression nobody would catch without running the
    /// app.
    @Test func theScannerTellsTextFromBackground() {
        let sample = """
        struct Fixture: View {
            var tint: Color = .secondary                     // line 2: a shared default
            var body: some View {
                Text("a").foregroundStyle(ok ? Color.secondary : palette.attention)  // 4: TEXT
                Text("b").foregroundStyle(Theme.textSecondary)                      // 5: correct
                Text("c").background(Color.secondary.opacity(0.08), in: Capsule())  // 6: wash
                Text("d").background(.background.secondary)                         // 7: material
                Circle().fill(Color.secondary)                                      // 8: swatch
                Text("e").foregroundStyle(.tertiarySystemFill)                      // 9: not us
                LineMark(x: .value("x", 1), y: .value("y", 2),
                         series: .value("s", "Current"))
                    .foregroundStyle(Color.secondary)                               // 12: chart
                RuleMark(x: .value("r", 3))
                    .foregroundStyle(.secondary.opacity(0.5))                       // 14: chart
                    .annotation(position: .top) {
                        Text("f").foregroundStyle(.secondary)                       // 16: TEXT
                    }
                let url = "https://x/y"                      // a // in a string is not a comment
            }
        }
        """
        let lines = Self.codeLines(of: sample)

        // Comments are gone, but the URL survives — the reason this walks characters.
        #expect(lines.contains { $0.contains("https://x/y") })
        #expect(!lines.contains { $0.contains("a shared default") })

        // Token discrimination.
        #expect(Self.bareSupportingStyles(in: ".background.secondary").isEmpty)
        #expect(Self.bareSupportingStyles(in: "Theme.textSecondary").isEmpty)
        #expect(Self.bareSupportingStyles(in: ".tertiarySystemFill").isEmpty)
        #expect(!Self.bareSupportingStyles(in: "ok ? Color.secondary : palette.attention").isEmpty)
        #expect(!Self.bareSupportingStyles(in: "AnyShapeStyle(.secondary)").isEmpty)

        // Balanced-paren extraction reaches past a nested close paren.
        let ternary = Array("foregroundStyle(x.map { f($0) } ?? .secondary).font(.body)")
        let arg = Self.balancedArgument(ternary, openParenAt: 15)
        #expect(arg == "x.map { f($0) } ?? .secondary")

        // The chain head: a wrapped chart mark is found, the Text inside its annotation is not.
        #expect(Self.chartMarks.contains { Self.chainHead(lines, at: 11).contains($0) })   // after LineMark
        #expect(Self.chartMarks.contains { Self.chainHead(lines, at: 13).contains($0) })   // after RuleMark
        #expect(!Self.chartMarks.contains { Self.chainHead(lines, at: 15).contains($0) })  // Text in .annotation

        // And the whole scan-1 pipeline on the fixture: exactly the two TEXT lines, nothing else.
        var flagged: [Int] = []
        for (i, line) in lines.enumerated() {
            guard let r = line.range(of: ".foregroundStyle(") else { continue }
            let window = lines[i...min(i + 4, lines.count - 1)].joined(separator: "\n")
            let openOffset = line.distance(from: line.startIndex, to: r.upperBound) - 1
            guard let a = Self.balancedArgument(Array(window), openParenAt: openOffset),
                  !Self.bareSupportingStyles(in: a).isEmpty else { continue }
            if Self.chartMarks.contains(where: { Self.chainHead(lines, at: i).contains($0) }) { continue }
            flagged.append(i)
        }
        #expect(flagged == [3, 15], "Expected only the two text foregrounds, got lines \(flagged.map { $0 + 1 })")
    }
}
