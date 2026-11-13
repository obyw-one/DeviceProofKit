//
//  CalibrationPatternTestCase.swift
//  DeviceProofTestSupport
//
//  The capture layer's oracle (operator direction, 2026-11-13): the app shows
//  the calibration test card (`CalibrationPattern`) and every combination of
//  orientation × colour scheme on the same device is captured and sampled. A
//  wrong orientation, a mirror, a crop, a black filler, a wrong scale or the
//  wrong mode each turns a known sample into a wrong colour, named with
//  expected vs measured. The screen recording is checked after the run by
//  `Scripts/check.py`, from the `<combination>.pattern.json` attachment each
//  test writes.
//
//  Orientation is a parameter of the CLASS, turned in `class setUp`: the iOS
//  screen recorder fixes its canvas from the device orientation when a test
//  starts and SCALES the screen into it afterwards (measured 2026-11-13: a
//  landscape screen recorded on a portrait canvas came out stretched 1.78x,
//  and a portrait test run right after a landscape one was stored turned 90°).
//  Turning the device before any test of the class starts gives every
//  recording the right canvas. A UI-test target therefore declares one
//  subclass per orientation:
//
//  ```swift
//  import DeviceProofTestSupport
//  import XCTest
//
//  final class CalibrationPortraitTests: CalibrationPatternTestCase {
//      override class var orientation: UIDeviceOrientation { .portrait }
//  }
//  final class CalibrationLandscapeTests: CalibrationPatternTestCase {
//      override class var orientation: UIDeviceOrientation { .landscapeLeft }
//  }
//  ```
//
//  Each subclass inherits `test_pattern_light` and `test_pattern_dark`. The
//  base class itself runs nothing (its default suite is empty).
//

#if DEBUG && os(iOS)
import DeviceProofKit
import UIKit
import XCTest

open class CalibrationPatternTestCase: XCTestCase {
    /// The device orientation every test of the subclass runs in.
    open class var orientation: UIDeviceOrientation { .portrait }

    /// Per-channel tolerance on the upright screenshot (colour-space rounding).
    open class var screenshotTolerance: Int { 10 }

    /// The application under test: the UI-test target's host app by default.
    @MainActor
    open func makeApplication() -> XCUIApplication { XCUIApplication() }

    /// The abstract base contributes no tests of its own.
    override open class var defaultTestSuite: XCTestSuite {
        self == CalibrationPatternTestCase.self
            ? XCTestSuite(name: "CalibrationPatternTestCase (abstract)")
            : super.defaultTestSuite
    }

    override open class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = orientation
        }
        // Let the rotation settle before the first test (and its recording) starts.
        Thread.sleep(forTimeInterval: 2)
    }

    override open func setUp() {
        super.setUp()
        continueAfterFailure = true
        executionTimeAllowance = 600
    }

    @MainActor
    func test_pattern_light() { runCalibration(.light) }

    @MainActor
    func test_pattern_dark() { runCalibration(.dark) }

    /// Opens the card in `scheme`, turns the device to the class orientation,
    /// captures the screen and samples it; attaches `<combination>.measured.json`
    /// and `<combination>.pattern.json` for `Scripts/check.py`.
    @MainActor
    public func runCalibration(_ scheme: CalibrationPattern.Scheme) {
        let device = Self.orientation
        let capture = DeviceProofCapture(test: self)
        let combination = "pattern-\(DeviceProofCapture.name(device))-\(scheme.rawValue)"

        XCUIDevice.shared.orientation = device
        let app = makeApplication()
        app.launchArguments += DeviceProbe.calibrationLaunchArguments(scheme)
        app.launch()

        let card = app.descendants(matching: .any).matching(identifier: DeviceProbe.calibration.identifier).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "\(combination): calibration pattern never shown")
        XCTAssertEqual(card.value as? String, scheme.rawValue, "\(combination): the pattern was drawn in another scheme")

        guard let layout = capture.rotate(app, to: device) else { return }
        // Let the rotation animation finish before the screen is captured.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let shot = capture.capture(combination, app, layout: layout)

        let samples = CalibrationPattern.samples(
            width: layout.screenWidth, height: layout.screenHeight, scale: layout.scale, scheme: scheme
        )
        var mismatches: [String] = []
        var measured: [String: String] = [:]
        for sample in samples {
            let got = shot.pixels.color(x: sample.x, y: sample.y)
            measured[sample.name] = "(\(got.r),\(got.g),\(got.b)) at \(sample.x),\(sample.y)"
            let off = max(abs(got.r - sample.expected.r), abs(got.g - sample.expected.g), abs(got.b - sample.expected.b))
            if off > Self.screenshotTolerance {
                mismatches.append(
                    "\(sample.name) at (\(sample.x),\(sample.y)): expected (\(sample.expected.r),\(sample.expected.g),\(sample.expected.b)), measured (\(got.r),\(got.g),\(got.b))"
                )
            }
        }
        capture.attachJSON(measured, name: "\(combination).measured.json")
        capture.attachJSON(
            CalibrationPattern.Capture(
                combination: combination, scheme: scheme, layout: layout,
                capturedAt: shot.capturedAt.timeIntervalSince1970, samples: samples
            ),
            name: "\(combination).pattern.json"
        )
        XCTAssertTrue(mismatches.isEmpty, "\(combination): \(mismatches.count) sample(s) off:\n" + mismatches.joined(separator: "\n"))
    }
}
#endif
