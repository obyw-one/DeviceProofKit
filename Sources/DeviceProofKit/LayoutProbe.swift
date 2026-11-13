//
//  LayoutProbe.swift
//  DeviceProofKit
//
//  Publishes what the app really renders — the scene's interface
//  orientation, the window and screen size, the scale — as one accessibility
//  element a device-proof UI test reads (`DeviceProbe.layout`). Without it a
//  test can rotate the device but cannot tell whether the app followed.
//
//  DEBUG builds only, and even there off unless the app is launched with
//  `DeviceProbe.layoutArgument`: no view and no timer otherwise.
//

#if DEBUG
import SwiftUI

#if os(iOS)
import UIKit

/// The probe, as a SwiftUI overlay. Renders nothing visible.
public struct LayoutProbe: View {
    public init() {}

    public var body: some View {
        LayoutProbeRepresentable()
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
    }
}

private struct LayoutProbeRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> LayoutProbeView { LayoutProbeView() }
    func updateUIView(_ uiView: LayoutProbeView, context: Context) { uiView.publish() }
}

/// A 1×1 pt view that is an accessibility element whose value is the
/// encoded ``LayoutReport``. Nearly transparent rather than hidden: a fully
/// transparent view is dropped from the accessibility tree.
final class LayoutProbeView: UIView {
    private var refresh: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = DeviceProbe.layout.identifier
        accessibilityLabel = DeviceProbe.layout.identifier
        backgroundColor = .black
        alpha = 0.02
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh?.invalidate()
        guard window != nil else { return }
        publish()
        // A rotation does not always re-lay-out a 1×1 view, so the report is
        // also refreshed on a short timer while the probe is on screen. Only
        // ever runs under the test launch argument.
        refresh = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publish()
    }

    func publish() {
        guard let window, let scene = window.windowScene else { return }
        let screen = scene.screen
        let report = LayoutReport(
            interfaceOrientation: Self.name(scene.interfaceOrientation),
            windowWidth: Double(window.bounds.width),
            windowHeight: Double(window.bounds.height),
            screenWidth: Double(screen.bounds.width),
            screenHeight: Double(screen.bounds.height),
            scale: Double(screen.scale),
            nativeWidth: Double(screen.nativeBounds.width),
            nativeHeight: Double(screen.nativeBounds.height)
        )
        let value = report.encoded
        if accessibilityValue != value { accessibilityValue = value }
    }

    private static func name(_ orientation: UIInterfaceOrientation) -> LayoutReport.InterfaceOrientation {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }
}
#else
/// macOS has no device orientation to probe.
public struct LayoutProbe: View {
    public init() {}
    public var body: some View { EmptyView() }
}
#endif
#endif
