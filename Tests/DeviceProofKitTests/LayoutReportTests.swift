//
//  LayoutReportTests.swift
//  DeviceProofKitTests
//

import Foundation
import Testing
@testable import DeviceProofKit

@Suite("LayoutReport")
struct LayoutReportTests {
    private func makeSUT(
        _ orientation: LayoutReport.InterfaceOrientation = .landscapeRight,
        window: (Double, Double) = (1590, 1192),
        screen: (Double, Double) = (1590, 1192),
        scale: Double = 2
    ) -> LayoutReport {
        LayoutReport(
            interfaceOrientation: orientation, windowWidth: window.0, windowHeight: window.1,
            screenWidth: screen.0, screenHeight: screen.1, scale: scale, nativeWidth: 2048, nativeHeight: 2732
        )
    }

    @Test("the screenshot size is points × scale, not the native panel")
    func screenshotSizeFromPoints() {
        // iPad Pro 12.9" in "More Space": 3180×2384, measured 2026-11-13.
        let sut = makeSUT()
        #expect(sut.screenshotPixelWidth == 3180)
        #expect(sut.screenshotPixelHeight == 2384)
    }

    @Test("a portrait window inside a landscape screen does not cover it")
    func windowCoverage() {
        #expect(makeSUT().windowCoversScreen)
        #expect(!makeSUT(window: (1192, 1590)).windowCoversScreen)
    }

    @Test("the screen shape must agree with the interface orientation")
    func shapeMatchesOrientation() {
        #expect(makeSUT(.landscapeLeft).screenMatchesOrientation)
        #expect(!makeSUT(.portrait).screenMatchesOrientation)
        #expect(makeSUT(.portrait, screen: (1192, 1590)).screenMatchesOrientation)
        #expect(!makeSUT(.unknown).screenMatchesOrientation)
    }

    @Test("the probe value round-trips, and garbage is nil")
    func encodedRoundTrip() {
        let sut = makeSUT()
        #expect(LayoutReport(encoded: sut.encoded) == sut)
        #expect(LayoutReport(encoded: "not a report") == nil)
    }
}
