//
//  CalibrationPatternTests.swift
//  DeviceProofKitTests
//
//  The card is the oracle of every capture check, so its own geometry is
//  pinned here: every sample lands on the screen, the four corners cannot be
//  confused under a rotation or a mirror, the line pair is three consecutive
//  pixels, and light and dark resolve the adaptive patches differently.
//

import Foundation
import Testing
@testable import DeviceProofKit

@Suite("CalibrationPattern")
struct CalibrationPatternTests {
    /// Screens the fleet runs on, in points at their scale, both orientations:
    /// iPhone 17 Pro, iPad Pro 12.9" in "More Space" (the 2026-11-13 proof),
    /// iPad Pro 12.9" default, and a Mac window.
    struct Screen: Sendable {
        let w: Double, h: Double, s: Double
    }

    static let screens: [Screen] = [
        Screen(w: 402, h: 874, s: 3), Screen(w: 874, h: 402, s: 3),
        Screen(w: 1192, h: 1590, s: 2), Screen(w: 1590, h: 1192, s: 2),
        Screen(w: 1024, h: 1366, s: 2), Screen(w: 1366, h: 1024, s: 2),
        Screen(w: 1280, h: 800, s: 1),
    ]

    @Test("every sample lands inside the screenshot", arguments: Self.screens.indices)
    func samplesInsideScreenshot(index: Int) {
        let screen = Self.screens[index]
        let width = Int(screen.w * screen.s), height = Int(screen.h * screen.s)
        for scheme in CalibrationPattern.Scheme.allCases {
            for sample in CalibrationPattern.samples(width: screen.w, height: screen.h, scale: screen.s, scheme: scheme) {
                #expect((0..<width).contains(sample.x), "\(sample.name) x \(sample.x) outside 0..<\(width)")
                #expect((0..<height).contains(sample.y), "\(sample.name) y \(sample.y) outside 0..<\(height)")
            }
        }
    }

    @Test("sample names are unique, so a mismatch names one place")
    func uniqueSampleNames() {
        let names = CalibrationPattern.samples(width: 402, height: 874, scale: 3, scheme: .light).map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test("the four corner markers differ in colour and shape")
    func cornersDistinct() {
        let corners = CalibrationPattern.regions(width: 1590, height: 1192).filter { $0.name.hasPrefix("corner.") }
        #expect(corners.count == 4)
        #expect(Set(corners.compactMap { $0.color.map { "\($0.r),\($0.g),\($0.b)" } }).count == 4)
        #expect(Set(corners.map(\.shape.rawValue)).count == 4)
    }

    @Test("the line pair is white, black, white on consecutive pixels")
    func linePair() {
        let (first, second) = CalibrationPattern.linePairColumns(width: 402, height: 874, scale: 3)
        #expect(second == first + 2)
        let samples = CalibrationPattern.samples(width: 402, height: 874, scale: 3, scheme: .dark)
        let pair = samples.filter { $0.name.hasPrefix("linepair.") && $0.name != "linepair.field" }
        #expect(pair.map(\.x) == [first, first + 1, second])
        #expect(pair.map(\.expected) == [.white, .black, .white])
        // A blurred 1-pixel line is not a video defect: never sampled there.
        #expect(pair.allSatisfy { !$0.checkInVideo })
    }

    @Test("light and dark resolve the adaptive patches to opposite colours")
    func adaptiveBySchemes() {
        for adaptive in CalibrationPattern.Adaptive.allCases {
            #expect(CalibrationPattern.adaptiveColor(adaptive, scheme: .light) != CalibrationPattern.adaptiveColor(adaptive, scheme: .dark))
        }
        let light = CalibrationPattern.samples(width: 402, height: 874, scale: 3, scheme: .light)
        let dark = CalibrationPattern.samples(width: 402, height: 874, scale: 3, scheme: .dark)
        let differing = zip(light, dark).filter { $0.expected != $1.expected }.map(\.0.name)
        #expect(differing == ["adaptive.label", "adaptive.systemBackground"])
    }

    @Test("a capture round-trips through the JSON the checker reads")
    func captureRoundTrip() throws {
        let layout = LayoutReport(
            interfaceOrientation: .landscapeRight, windowWidth: 1590, windowHeight: 1192,
            screenWidth: 1590, screenHeight: 1192, scale: 2, nativeWidth: 2048, nativeHeight: 2732
        )
        let capture = CalibrationPattern.Capture(
            combination: "pattern-landscapeLeft-dark", scheme: .dark, layout: layout, capturedAt: 1_000,
            samples: CalibrationPattern.samples(width: 1590, height: 1192, scale: 2, scheme: .dark)
        )
        let data = try JSONEncoder().encode(capture)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // check.py reads these keys; renaming one silently disables the video check.
        #expect(Set(object.keys) == ["combination", "scheme", "layout", "capturedAt", "samples"])
        let first = try #require((object["samples"] as? [[String: Any]])?.first)
        #expect(Set(first.keys) == ["name", "x", "y", "expected", "checkInVideo"])
    }
}
