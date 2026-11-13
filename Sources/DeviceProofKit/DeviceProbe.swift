//
//  DeviceProbe.swift
//  DeviceProofKit
//
//  The accessibility elements a device-proof UI test reads to learn about the
//  app rather than to drive it, and the launch arguments that turn them on.
//  DEBUG builds only: a release build has no probe and no way to open one.
//

#if DEBUG
import Foundation

/// The accessibility elements a test reads to learn about the app, not to drive it.
public enum DeviceProbe: String, CaseIterable, Sendable {
    /// Carries a ``LayoutReport`` as its accessibility value.
    case layout
    /// The calibration pattern's root; its value is the colour scheme it was
    /// drawn in (``CalibrationPattern/Scheme``).
    case calibration

    /// The accessibility identifier of the probe element.
    public var identifier: String { "probe.\(rawValue)" }

    /// The launch argument that turns the layout probe on.
    public static let layoutArgument = "-DeviceProofLayoutProbe"
    /// The launch argument that replaces the app's root with the calibration
    /// pattern, followed by the scheme (`light` / `dark`).
    public static let calibrationArgument = "-DeviceProofCalibrationPattern"

    /// The launch arguments a UI test passes to open the calibration pattern
    /// with the layout probe on.
    public static func calibrationLaunchArguments(_ scheme: CalibrationPattern.Scheme) -> [String] {
        [layoutArgument, calibrationArgument, scheme.rawValue]
    }

    /// Whether `arguments` turn the layout probe on.
    public static func isLayoutProbeRequested(in arguments: [String]) -> Bool {
        arguments.contains(layoutArgument)
    }

    /// The scheme `arguments` ask the calibration pattern for, or nil when the
    /// pattern was not requested (or the scheme is not one).
    public static func requestedCalibration(in arguments: [String]) -> CalibrationPattern.Scheme? {
        guard let i = arguments.firstIndex(of: calibrationArgument), i + 1 < arguments.count else { return nil }
        return CalibrationPattern.Scheme(rawValue: arguments[i + 1])
    }
}
#endif
