//
//  CalibrationPatternView.swift
//  DeviceProofKit
//
//  Draws ``CalibrationPattern`` full screen: the test card the
//  device-proof checks sample. DEBUG builds only, opened by
//  `DeviceProbe.calibrationArgument <light|dark>` from a UI test through the
//  `.deviceProof()` hook; a release build has no way to show it.
//

#if DEBUG
import SwiftUI

/// The calibration test card, full screen, in `scheme`.
public struct CalibrationPatternView: View {
    public let scheme: CalibrationPattern.Scheme

    public init(scheme: CalibrationPattern.Scheme) {
        self.scheme = scheme
    }

    @Environment(\.displayScale) private var displayScale

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    draw(in: &context, width: Double(size.width), height: Double(size.height))
                }
                Text(caption(width: w, height: h))
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(8)
                    .background(Color.black)
                    .position(x: w / 2, y: h * 0.15)
                    .accessibilityIdentifier(DeviceProbe.calibration.identifier)
                    .accessibilityValue(scheme.rawValue)
            }
        }
        .ignoresSafeArea()
        .fullScreenChrome()
        .persistentSystemOverlays(.hidden)
    }

    private func caption(width w: Double, height h: Double) -> String {
        "pattern \(scheme.rawValue) · \(Int(w))×\(Int(h)) pt · @\(Int(displayScale))x · \(Int(w * displayScale))×\(Int(h * displayScale)) px"
    }

    private func color(_ rgb: CalibrationPattern.RGB) -> Color {
        Color(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255, opacity: 1)
    }

    private func draw(in context: inout GraphicsContext, width w: Double, height h: Double) {
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(color(CalibrationPattern.background)))

        // Grid every 100 pt, for a human reading coordinates off a capture.
        var grid = Path()
        for x in stride(from: 100.0, to: w, by: 100) { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: h)) }
        for y in stride(from: 100.0, to: h, by: 100) { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y)) }
        context.stroke(grid, with: .color(Color(.sRGB, white: 0.4, opacity: 1)), lineWidth: 1)

        for region in CalibrationPattern.regions(width: w, height: h) {
            let r = CGRect(x: region.rect.x, y: region.rect.y, width: region.rect.width, height: region.rect.height)
            let fill: Color
            if let rgb = region.color {
                fill = color(rgb)
            } else {
                #if os(iOS)
                fill = Color(uiColor: region.adaptive == .label ? .label : .systemBackground)
                #else
                fill = region.adaptive == .label ? Color.primary : Color(nsColor: .windowBackgroundColor)
                #endif
            }
            context.fill(path(for: region.shape, in: r), with: .color(fill))
        }

        // Two white lines exactly one device pixel wide, one pixel apart, on pixel centres.
        let field = CalibrationPattern.lineField(width: w, height: h)
        let (first, second) = CalibrationPattern.linePairColumns(width: w, height: h, scale: Double(displayScale))
        let onePixel = 1 / displayScale
        for column in [first, second] {
            let x = (Double(column) + 0.5) / displayScale
            var line = Path()
            line.move(to: CGPoint(x: x, y: field.y + 4))
            line.addLine(to: CGPoint(x: x, y: field.y + field.height - 4))
            context.stroke(line, with: .color(.white), lineWidth: onePixel)
        }
    }

    private func path(for shape: CalibrationPattern.Shape, in r: CGRect) -> Path {
        switch shape {
        case .rectangle:
            return Path(r)
        case .triangleTopRight:
            var p = Path()
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
            return p
        case .disc:
            return Path(ellipseIn: r.insetBy(dx: 2, dy: 2))
        case .ell:
            var p = Path(CGRect(x: r.minX, y: r.minY, width: 16, height: r.height))
            p.addRect(CGRect(x: r.minX, y: r.maxY - 16, width: r.width, height: 16))
            return p
        }
    }
}

private extension View {
    /// Hides the status bar where there is one (iOS); macOS has none.
    @ViewBuilder
    func fullScreenChrome() -> some View {
        #if os(iOS)
        statusBarHidden(true)
        #else
        self
        #endif
    }
}
#endif
