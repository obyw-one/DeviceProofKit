//
//  CalibrationPattern.swift
//  DeviceProofKit
//
//  A test card ("mire de barres") that is the oracle of the device-proof
//  capture checks (operator direction, 2026-11-13). The app DRAWS these
//  regions and the checker SAMPLES the same regions, so one value decides both:
//
//  - colour bars across the full width, and patches touching each edge, so a
//    crop or a black filler band shows as a wrong colour at a known place;
//  - four different corner markers (red square, green triangle, blue disc,
//    yellow "L"), so a 90° rotation or a mirror cannot match;
//  - a pair of 1-pixel lines, so resampling or a wrong scale blurs them;
//  - two patches in adaptive system colours, so light vs dark mode is a pixel
//    value, not a guess.
//
//  Geometry is in points of the screen the app is given (current orientation),
//  sample points in pixels of an upright screenshot of that screen.
//

#if DEBUG
import Foundation

public enum CalibrationPattern {

    /// The colour scheme the pattern is drawn in.
    public enum Scheme: String, Codable, CaseIterable, Sendable {
        case light, dark
    }

    /// An sRGB colour, 0–255 per channel.
    public struct RGB: Codable, Equatable, Sendable {
        public var r: Int, g: Int, b: Int
        public init(_ r: Int, _ g: Int, _ b: Int) { self.r = r; self.g = g; self.b = b }
        public static let white = RGB(255, 255, 255)
        public static let black = RGB(0, 0, 0)
        public static let gray = RGB(128, 128, 128)
    }

    /// A rectangle in points.
    public struct Rect: Codable, Equatable, Sendable {
        public var x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    /// What a region is drawn as.
    public enum Shape: String, Codable, Sendable {
        case rectangle
        /// A right triangle with its right angle at the rect's top-right corner.
        case triangleTopRight
        /// A disc inscribed in the rect.
        case disc
        /// An "L": a vertical bar on the left edge and a horizontal bar on the bottom edge.
        case ell
    }

    /// The system colours the adaptive patches use: their pixel value is what
    /// tells light from dark mode.
    public enum Adaptive: String, Codable, CaseIterable, Sendable {
        case label
        case systemBackground
    }

    /// One drawn region.
    public struct Region: Codable, Equatable, Sendable {
        public var name: String
        public var rect: Rect
        public var shape: Shape
        /// The exact colour, or nil when the region uses an adaptive system
        /// colour (see ``adaptive``).
        public var color: RGB?
        /// The system colour of an adaptive patch.
        public var adaptive: Adaptive?
    }

    /// A point the checker samples, in pixels of the upright screenshot, and
    /// the colour it must have.
    public struct Sample: Codable, Equatable, Sendable {
        public var name: String
        public var x: Int
        public var y: Int
        public var expected: RGB
        /// Large solid areas are checked in the video too; 1-pixel features
        /// only in the screenshot (video compression blurs them by design).
        public var checkInVideo: Bool
    }

    public static let background = RGB.gray

    /// The bar colours, left to right.
    public static let bars: [(String, RGB)] = [
        ("bar.white", .white), ("bar.yellow", RGB(255, 255, 0)), ("bar.cyan", RGB(0, 255, 255)),
        ("bar.green", RGB(0, 255, 0)), ("bar.magenta", RGB(255, 0, 255)), ("bar.red", RGB(255, 0, 0)),
        ("bar.blue", RGB(0, 0, 255)), ("bar.black", .black),
    ]

    public static let edgeThickness = 24.0
    public static let edgeLength = 120.0
    public static let cornerSize = 64.0

    /// The regions, for a screen of `width` × `height` points.
    public static func regions(width w: Double, height h: Double) -> [Region] {
        var out: [Region] = []
        let barTop = (h * 0.35).rounded(), barHeight = (h * 0.25).rounded()
        let barWidth = w / Double(bars.count)
        for (i, bar) in bars.enumerated() {
            out.append(Region(name: bar.0, rect: Rect(x: Double(i) * barWidth, y: barTop, width: barWidth, height: barHeight),
                              shape: .rectangle, color: bar.1, adaptive: nil))
        }
        let t = edgeThickness, l = edgeLength
        out.append(Region(name: "edge.top", rect: Rect(x: w / 2 - l / 2, y: 0, width: l, height: t), shape: .rectangle, color: RGB(255, 128, 0), adaptive: nil))
        out.append(Region(name: "edge.bottom", rect: Rect(x: w / 2 - l / 2, y: h - t, width: l, height: t), shape: .rectangle, color: RGB(128, 0, 255), adaptive: nil))
        out.append(Region(name: "edge.left", rect: Rect(x: 0, y: h * 0.2, width: t, height: l), shape: .rectangle, color: RGB(0, 128, 128), adaptive: nil))
        out.append(Region(name: "edge.right", rect: Rect(x: w - t, y: h * 0.2, width: t, height: l), shape: .rectangle, color: RGB(255, 0, 128), adaptive: nil))
        let c = cornerSize
        out.append(Region(name: "corner.topLeft", rect: Rect(x: 0, y: 0, width: c, height: c), shape: .rectangle, color: RGB(255, 0, 0), adaptive: nil))
        out.append(Region(name: "corner.topRight", rect: Rect(x: w - c, y: 0, width: c, height: c), shape: .triangleTopRight, color: RGB(0, 255, 0), adaptive: nil))
        out.append(Region(name: "corner.bottomRight", rect: Rect(x: w - c, y: h - c, width: c, height: c), shape: .disc, color: RGB(0, 0, 255), adaptive: nil))
        out.append(Region(name: "corner.bottomLeft", rect: Rect(x: 0, y: h - c, width: c, height: c), shape: .ell, color: RGB(255, 255, 0), adaptive: nil))
        // A black patch carrying the 1-pixel line pair (drawn by the view).
        out.append(Region(name: "linepair.field", rect: lineField(width: w, height: h), shape: .rectangle, color: .black, adaptive: nil))
        out.append(Region(name: "adaptive.label", rect: Rect(x: w * 0.6, y: h * 0.7, width: 80, height: 40), shape: .rectangle, color: nil, adaptive: .label))
        out.append(Region(name: "adaptive.systemBackground", rect: Rect(x: w * 0.6 + 100, y: h * 0.7, width: 80, height: 40), shape: .rectangle, color: nil, adaptive: .systemBackground))
        return out
    }

    /// The black field the 1-pixel line pair is drawn in.
    public static func lineField(width w: Double, height h: Double) -> Rect {
        Rect(x: (w * 0.1).rounded(), y: (h * 0.7).rounded(), width: 40, height: 40)
    }

    /// The pixel columns of the two 1-pixel white lines: one pixel apart, a
    /// black pixel between them.
    public static func linePairColumns(width w: Double, height h: Double, scale: Double) -> (Int, Int) {
        let field = lineField(width: w, height: h)
        let first = Int(((field.x + 12) * scale).rounded())
        return (first, first + 2)
    }

    /// The colour an adaptive patch resolves to in a scheme.
    public static func adaptiveColor(_ adaptive: Adaptive, scheme: Scheme) -> RGB {
        switch (adaptive, scheme) {
        case (.label, .light), (.systemBackground, .dark): .black
        case (.label, .dark), (.systemBackground, .light): .white
        }
    }

    /// The points the checker samples, in pixels of an upright screenshot of
    /// a `width` × `height` pt screen at `scale`.
    public static func samples(width w: Double, height h: Double, scale s: Double, scheme: Scheme) -> [Sample] {
        func px(_ v: Double) -> Int { Int((v * s).rounded(.down)) }
        var out: [Sample] = []
        for region in regions(width: w, height: h) {
            let r = region.rect
            let colour = region.color ?? region.adaptive.map { adaptiveColor($0, scheme: scheme) } ?? background
            switch region.shape {
            case .rectangle:
                out.append(Sample(name: region.name, x: px(r.x + r.width / 2), y: px(r.y + r.height / 2), expected: colour, checkInVideo: true))
            case .triangleTopRight:
                // Near the right angle: inside the triangle.
                out.append(Sample(name: region.name, x: px(r.x + r.width - 10), y: px(r.y + 10), expected: colour, checkInVideo: true))
                // The opposite corner of its square stays background: a mirror fails here.
                out.append(Sample(name: region.name + ".outside", x: px(r.x + 10), y: px(r.y + r.height - 10), expected: background, checkInVideo: true))
            case .disc:
                out.append(Sample(name: region.name, x: px(r.x + r.width / 2), y: px(r.y + r.height / 2), expected: colour, checkInVideo: true))
            case .ell:
                out.append(Sample(name: region.name + ".vertical", x: px(r.x + 8), y: px(r.y + 20), expected: colour, checkInVideo: true))
                out.append(Sample(name: region.name + ".horizontal", x: px(r.x + 44), y: px(r.y + r.height - 8), expected: colour, checkInVideo: true))
                out.append(Sample(name: region.name + ".inside", x: px(r.x + 44), y: px(r.y + 20), expected: background, checkInVideo: true))
            }
        }
        // The 1-pixel line pair: white, black, white on consecutive pixels.
        let field = lineField(width: w, height: h)
        let (first, second) = linePairColumns(width: w, height: h, scale: s)
        let lineY = px(field.y + field.height / 2)
        out.append(Sample(name: "linepair.first", x: first, y: lineY, expected: .white, checkInVideo: false))
        out.append(Sample(name: "linepair.gap", x: first + 1, y: lineY, expected: .black, checkInVideo: false))
        out.append(Sample(name: "linepair.second", x: second, y: lineY, expected: .white, checkInVideo: false))
        // The background between regions, so a filler of another colour shows.
        out.append(Sample(name: "background", x: px(w * 0.5), y: px(h * 0.85), expected: background, checkInVideo: true))
        return out
    }

    /// Everything the checker needs for one capture, as one JSON attachment.
    public struct Capture: Codable, Sendable {
        public var combination: String
        public var scheme: Scheme
        public var layout: LayoutReport
        /// Seconds since 1970 when the screenshot was taken.
        public var capturedAt: Double
        public var samples: [Sample]

        public init(combination: String, scheme: Scheme, layout: LayoutReport, capturedAt: Double, samples: [Sample]) {
            self.combination = combination; self.scheme = scheme; self.layout = layout
            self.capturedAt = capturedAt; self.samples = samples
        }
    }
}
#endif
