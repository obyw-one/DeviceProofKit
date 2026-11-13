//
//  DeviceProofHook.swift
//  DeviceProofKit
//
//  The one line an app adds to take part in device proofs: `.deviceProof()`
//  on the root view of its scene.
//
//  - Launched with `DeviceProbe.calibrationArgument <light|dark>`, the root is
//    replaced by the calibration card, drawn in that colour scheme.
//  - Launched with `DeviceProbe.layoutArgument`, the layout probe is overlaid.
//  - Otherwise, and always in a release build, the root is returned as is: the
//    modifier compiles to the identity, so no probe, no card and no launch-
//    argument parsing ships.
//

import SwiftUI

public extension View {
    /// Hooks this scene root into device-proof UI tests (DEBUG builds only).
    @ViewBuilder
    func deviceProof(arguments: [String] = ProcessInfo.processInfo.arguments) -> some View {
        #if DEBUG
        if let scheme = DeviceProbe.requestedCalibration(in: arguments) {
            CalibrationPatternView(scheme: scheme)
                .preferredColorScheme(scheme == .dark ? .dark : .light)
                .overlay(alignment: .topLeading) { probe(arguments) }
        } else {
            overlay(alignment: .topLeading) { probe(arguments) }
        }
        #else
        self
        #endif
    }
}

#if DEBUG
@MainActor @ViewBuilder
private func probe(_ arguments: [String]) -> some View {
    if DeviceProbe.isLayoutProbeRequested(in: arguments) {
        LayoutProbe()
    }
}
#endif
