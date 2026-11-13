//
//  LayoutReport.swift
//  DeviceProofKit
//
//  What the app REALLY renders, reported to a UI test (device-proof capture
//  layer, operator direction 2026-11-13). A test that rotates the device must
//  know whether the app followed: the interface orientation the scene is in,
//  the window and screen size in points, the scale, and so the pixel size a
//  screenshot of this screen has to be. The app publishes it through one
//  accessibility element (`DeviceProbe.layout`); the test decodes it with the
//  same type, so neither side spells a key.
//
//  Measured on the first iPad proof (iPad Pro 12.9" 6th gen, 2026-11-13): the
//  screenshots were 3180×2384 — 1590×1192 pt at @2x, the iPad's "More Space"
//  display zoom, not the 2732×2048 physical panel — so the expected size is
//  derived from the screen the app is given (points × scale), never from a
//  per-model table of panel sizes.
//

#if DEBUG
import Foundation

/// The layout the app's scene is in, as the app itself measures it.
public struct LayoutReport: Codable, Equatable, Sendable {

    /// The scene's interface orientation (`UIInterfaceOrientation`), by name.
    public enum InterfaceOrientation: String, Codable, CaseIterable, Sendable {
        case portrait
        case portraitUpsideDown
        case landscapeLeft
        case landscapeRight
        case unknown

        public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
        public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
    }

    public var interfaceOrientation: InterfaceOrientation
    /// The app window's bounds, in points.
    public var windowWidth: Double
    public var windowHeight: Double
    /// The screen's bounds in the current interface orientation, in points.
    public var screenWidth: Double
    public var screenHeight: Double
    /// Points to pixels for screenshots of this screen (`UIScreen.scale`).
    public var scale: Double
    /// The physical panel in pixels, always portrait (`UIScreen.nativeBounds`).
    public var nativeWidth: Double
    public var nativeHeight: Double

    public init(
        interfaceOrientation: InterfaceOrientation,
        windowWidth: Double, windowHeight: Double,
        screenWidth: Double, screenHeight: Double,
        scale: Double,
        nativeWidth: Double, nativeHeight: Double
    ) {
        self.interfaceOrientation = interfaceOrientation
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.scale = scale
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
    }

    /// The pixel size an upright screenshot of this screen has: the screen in
    /// points, in the current orientation, times the scale.
    public var screenshotPixelWidth: Int { Int((screenWidth * scale).rounded()) }
    public var screenshotPixelHeight: Int { Int((screenHeight * scale).rounded()) }

    /// Whether the app window covers the whole screen (no letterbox, no
    /// portrait window left inside a landscape screen).
    public var windowCoversScreen: Bool {
        abs(windowWidth - screenWidth) < 1 && abs(windowHeight - screenHeight) < 1
    }

    /// Whether the screen's shape agrees with the interface orientation.
    public var screenMatchesOrientation: Bool {
        switch interfaceOrientation {
        case .landscapeLeft, .landscapeRight: screenWidth > screenHeight
        case .portrait, .portraitUpsideDown: screenHeight > screenWidth
        case .unknown: false
        }
    }

    /// The accessibility value the probe publishes.
    public var encoded: String {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    /// The report a probe published, or nil when the value is not one.
    public init?(encoded: String) {
        guard let data = encoded.data(using: .utf8),
              let report = try? JSONDecoder().decode(LayoutReport.self, from: data)
        else { return nil }
        self = report
    }
}
#endif
