//
//  DeviceProbeTests.swift
//  DeviceProofKitTests
//

import Testing
@testable import DeviceProofKit

@Suite("DeviceProbe")
struct DeviceProbeTests {
    @Test("the calibration launch arguments are what the hook reads back", arguments: CalibrationPattern.Scheme.allCases)
    func launchArgumentsRoundTrip(scheme: CalibrationPattern.Scheme) {
        let arguments = ["/path/to/App"] + DeviceProbe.calibrationLaunchArguments(scheme)
        #expect(DeviceProbe.requestedCalibration(in: arguments) == scheme)
        #expect(DeviceProbe.isLayoutProbeRequested(in: arguments))
    }

    @Test("a plain launch requests nothing")
    func plainLaunch() {
        #expect(DeviceProbe.requestedCalibration(in: ["/path/to/App"]) == nil)
        #expect(!DeviceProbe.isLayoutProbeRequested(in: ["/path/to/App"]))
    }

    @Test("a missing or unknown scheme opens no card")
    func malformedScheme() {
        #expect(DeviceProbe.requestedCalibration(in: [DeviceProbe.calibrationArgument]) == nil)
        #expect(DeviceProbe.requestedCalibration(in: [DeviceProbe.calibrationArgument, "sepia"]) == nil)
    }
}
