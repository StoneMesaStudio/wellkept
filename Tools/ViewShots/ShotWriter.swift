//
//  ShotWriter.swift
//  ViewShots
//
//  **Renders a real view to a PNG, at a real width, with no window — and refuses to write a blank
//  one.**
//
//  This is the only tool in the house that catches a build which compiles, passes every test, and
//  looks wrong. Waypoint built it on 2026-08-23 after a green build and 771 passing engine tests
//  said nothing at all about whether the day table LOOKED like what was agreed. It did not: the
//  columns had no ceiling, so what read correctly in a 680-point mockup put a row's buttons half a
//  screen from the town they acted on at 1900. Nothing in the suite could see that, and the first
//  person who did was somebody looking at the pictures.
//
//  Built into Wellkept now, while there is only a sidebar and seven faces to photograph, because
//  the harness is cheap to add to an empty app and expensive to retrofit onto a full one.
//
//  Run the whole set:
//
//      bin/make-shots.sh
//
//  Or one suite, by hand:
//
//      xcodebuild test -project Wellkept.xcodeproj -scheme Wellkept \
//          -only-testing:ViewShots/ShellShot 2>&1 | grep VIEWSHOT
//

import AppKit
import SwiftUI
import Testing

/// Somewhere to hang `Bundle(for:)` off. The asset catalog is compiled into THIS bundle, not the
/// app's, and `Color("PageGround")` reads `Bundle.main` — which under `xctest` is the test runner.
/// Anything that needs to look an asset up by hand goes through here.
final class ShotBundleAnchor: NSObject {}

@MainActor
enum ShotWriter {

    /// The bundle these tests are running out of — where `Assets.xcassets` actually landed.
    static var bundle: Bundle { Bundle(for: ShotBundleAnchor.self) }

    /// Where the PNGs go. `bin/make-shots.sh` sets `WELLKEPT_SHOTS_DIR`; by hand it is a temp
    /// folder, printed on every line so it is never a mystery which file was just written.
    static var outputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["WELLKEPT_SHOTS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("wellkept-viewshots", isDirectory: true)
    }

    /// Photograph a view and write it out.
    ///
    /// - Parameters:
    ///   - scheme: which appearance to draw in. Every face is worth having in both, because the
    ///     bronze is a different hex in each and only one of the two was ever judged by eye.
    ///
    /// Fails the test — rather than returning quietly — when nothing renders or when what rendered
    /// is blank. A shot harness that writes a blank PNG and reports success is worse than no
    /// harness: it converts "nobody looked" into "something checked it".
    @discardableResult
    static func write(_ view: some View,
                      width: CGFloat,
                      height: CGFloat,
                      name: String,
                      scheme: ColorScheme = .light) -> URL? {

        // The ground is painted underneath explicitly rather than relying on the view to bring its
        // own, so a face that forgets `.pageGround()` still photographs — the picture shows the
        // omission instead of failing as "blank".
        let backdrop = Color(hex: scheme == .dark ? Palette.darkGroundHex : Palette.lightGroundHex)

        let composed = ZStack {
            backdrop
            view
        }
        .frame(width: width, height: height)
        .environment(\.colorScheme, scheme)
        .environment(\.palette, Palette(level: .calm, scheme: scheme))

        guard let rep = render(composed, width: width, height: height, scheme: scheme),
              let png = rep.representation(using: .png, properties: [:])
        else {
            Issue.record(Comment(rawValue: "\(name): nothing rendered"))
            return nil
        }

        let colours = distinctColours(in: rep)
        // ⚠️ **The blank detector.** Several things decline to draw when the layout system has no
        // real window under it, and they do not error — they return a picture of the background.
        // Four distinct sampled colours is the floor: a painted ground plus its antialiasing can
        // reach three on its own, and any face with a word on it clears it by a wide margin.
        guard colours > 3 else {
            Issue.record(Comment(rawValue: """
                \(name): blank — only \(colours) distinct colours in the whole frame. The view did \
                not lay out. Something in it is waiting on a size the harness never gave it.
                """))
            return nil
        }

        do {
            let folder = outputDirectory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(name).png")
            try png.write(to: file)
            // `bin/make-shots.sh` greps for this exact prefix. Keep the shape.
            print("VIEWSHOT \(file.path) \(rep.pixelsWide)x\(rep.pixelsHigh) colours:\(colours)")
            return file
        } catch {
            Issue.record(Comment(rawValue: "\(name): couldn't write the PNG — \(error)"))
            return nil
        }
    }

    /// Draw a view into a bitmap, **through a real off-screen window**.
    ///
    /// ⚠️ **`ImageRenderer` is not enough for this app, and the reason is worth the paragraph.**
    /// It lays out with no window at all, and `GeometryReader` reports nothing under it. Every one
    /// of Wellkept's panes is a `StableScrollView`, whose whole mechanism is a `GeometryReader`
    /// measuring the width *outside* the scroll view to break the scroll-bar feedback loop. Under
    /// `ImageRenderer` that measurement comes back empty, the content is pinned to nothing, and the
    /// entire pane photographs as a flat rectangle of ground.
    ///
    /// That is what the first version of this harness did on 2026-08-26: it reported every section
    /// face blank, and the app was fine. **A harness that cannot photograph the app's real screens
    /// is a harness that gets pointed at imitations of them instead** — which is exactly the
    /// failure mode it exists to prevent, arrived at from the other side.
    ///
    /// An `NSWindow` costs a few lines and makes the layout real: `GeometryReader` gets a size,
    /// `ScrollView` gets a clip view, `.bar` and the other materials resolve against a window that
    /// actually has an appearance. It is never ordered on screen, so nothing appears on the Mac.
    static func render(_ view: some View,
                       width: CGFloat,
                       height: CGFloat,
                       scheme: ColorScheme) -> NSBitmapImageRep? {

        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        // Both halves, as DESIGN §3.4 requires: SwiftUI's `\.colorScheme` is set by the caller, and
        // AppKit's appearance is set here. Without the second, AppKit-drawn chrome — the sidebar's
        // `.bar` material, dividers, focus rings — draws in the wrong appearance.
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)

        // `.borderless` and far off-screen. The window is never ordered front and never joins the
        // Dock or the window list; it exists so that layout has something to measure against.
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        host.appearance = appearance

        // SwiftUI settles asynchronously. `layoutSubtreeIfNeeded` alone leaves a GeometryReader's
        // children one pass behind — the symptom is a picture with the chrome drawn and the content
        // missing, which reads exactly like the blank this is here to avoid.
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        return rep
    }

    /// How many distinct colours appear in a vertical strip of the image, given as fractions of
    /// its width.
    ///
    /// Used to ask a question a whole-frame colour count cannot: **is this part of the picture
    /// empty?** A page whose content spreads to fill a 34-inch monitor and a page whose content
    /// stays in the 700-point readable column produce identically busy frames; they differ only in
    /// what is happening near the right edge.
    static func distinctColours(in rep: NSBitmapImageRep,
                                fromFraction: Double,
                                toFraction: Double) -> Int {
        var seen = Set<String>()
        let x0 = Int(Double(rep.pixelsWide) * fromFraction)
        let x1 = min(Int(Double(rep.pixelsWide) * toFraction), rep.pixelsWide - 1)
        guard x1 > x0 else { return 0 }
        let yStep = max(rep.pixelsHigh / 60, 1)
        for x in stride(from: x0, to: x1, by: max((x1 - x0) / 20, 1)) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: yStep) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                seen.insert(String(format: "%.2f,%.2f,%.2f",
                                   colour.redComponent, colour.greenComponent, colour.blueComponent))
            }
        }
        return seen.count
    }

    /// How many distinct colours a 40 × 40 sample of the image contains.
    ///
    /// Sampled rather than exhaustive: a 1800 × 2000 pixel buffer read in full is slow enough to
    /// matter when this runs inside the build gate, and the question — "did anything draw at all?"
    /// — does not need every pixel to answer it. Rounded to two decimals so gradient banding does
    /// not read as content.
    static func distinctColours(in rep: NSBitmapImageRep) -> Int {
        var seen = Set<String>()
        let xStep = max(rep.pixelsWide / 40, 1)
        let yStep = max(rep.pixelsHigh / 40, 1)
        for x in stride(from: 0, to: rep.pixelsWide, by: xStep) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: yStep) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                seen.insert(String(format: "%.2f,%.2f,%.2f",
                                   colour.redComponent, colour.greenComponent, colour.blueComponent))
            }
        }
        return seen.count
    }
}

// MARK: - The harness has to be proved before anything is proved with it

/// ⚠️ **A shot harness nobody checks is a harness that quietly stops working.**
///
/// Every test below is about the tool, not the app: it depends on no Wellkept view, so it keeps
/// passing while the seven faces are being built and it fails the moment `ImageRenderer` changes
/// under a new macOS. The negative control matters as much as the positive one — a blank detector
/// that never fires is indistinguishable from one that is switched off.
@Suite("View shots — the harness itself")
@MainActor
struct ShotHarnessTests {

    @Test("A plain view photographs")
    func aPlainViewPhotographs() {
        let file = ShotWriter.write(
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    Text("Row \(i)").font(.appTitle3)
                    Divider()
                }
            }
            .padding(24),
            width: 260, height: 300, name: "00-harness-control")
        #expect(file != nil)
    }

    /// The negative control. One flat colour and nothing else is exactly what a view that failed to
    /// lay out returns, and the detector must call it blank.
    @Test("An empty frame is detected as blank")
    func anEmptyFrameIsBlank() {
        guard let rep = ShotWriter.render(Color.white, width: 200, height: 200, scheme: .light) else {
            Issue.record("nothing rendered for the negative control")
            return
        }
        #expect(ShotWriter.distinctColours(in: rep) <= 3,
                "A flat white square reported as having content — the blank detector is dead.")
    }

    /// ⚠️ `Color("PageGround")` resolves against `Bundle.main`, which under `xctest` is the runner,
    /// not this bundle. This test is what turns "the shots came out grey" into a named failure.
    @Test("The page-ground asset is in the built product")
    func groundAssetExists() {
        #expect(NSColor(named: "PageGround", bundle: ShotWriter.bundle) != nil,
                """
                PageGround.colorset didn't compile into the bundle. Palette.ground paints the \
                asset, so every face would draw on nothing.
                """)
    }
}
