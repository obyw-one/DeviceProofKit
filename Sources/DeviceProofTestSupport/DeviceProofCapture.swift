//
//  DeviceProofCapture.swift
//  DeviceProofTestSupport
//

#if DEBUG && os(iOS)
import DeviceProofKit
import UIKit
import XCTest

/// The device-proof capture layer (operator direction, 2026-11-13): every
/// screen, in every orientation, captured upright at the size the screen
/// really has, with the checks that would have caught the first iPad proof
/// (screenshots sideways in a landscape buffer, a black band, a crop, and a
/// recording in another orientation).
///
/// Reusable by any UI test: `rotate` asks the device for an orientation and
/// waits until the APP reports it followed; `capture` takes the screenshot,
/// normalises it, checks it and attaches the evidence the post-run checker
/// (`Scripts/check.py`) compares against the screen recording.
@MainActor
public struct DeviceProofCapture {
    public let test: XCTestCase

    public init(test: XCTestCase) {
        self.test = test
    }

    // MARK: - Orientation

    /// The interface orientation the app must report for a device orientation.
    /// UIKit's convention: the device turned left shows the interface turned right.
    public static func expectedInterface(for device: UIDeviceOrientation) -> LayoutReport.InterfaceOrientation {
        switch device {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeRight
        case .landscapeRight: .landscapeLeft
        default: .unknown
        }
    }

    public static func name(_ device: UIDeviceOrientation) -> String {
        switch device {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        default: "unknown"
        }
    }

    /// The layout the app publishes through `DeviceProbe.layout`, or nil.
    public func layout(of app: XCUIApplication) -> LayoutReport? {
        let probe = app.descendants(matching: .any).matching(identifier: DeviceProbe.layout.identifier).firstMatch
        guard probe.exists, let value = probe.value as? String else { return nil }
        return LayoutReport(encoded: value)
    }

    /// Turns the device and waits until the app reports the matching interface
    /// orientation, a screen of the matching shape and a window covering it.
    /// Fails naming what the app reported when it does not follow.
    @discardableResult
    public func rotate(_ app: XCUIApplication, to device: UIDeviceOrientation, timeout: TimeInterval = 10) -> LayoutReport? {
        XCUIDevice.shared.orientation = device
        let expected = Self.expectedInterface(for: device)
        let deadline = Date().addingTimeInterval(timeout)
        var last: LayoutReport?
        while Date() < deadline {
            last = layout(of: app)
            if let report = last, report.interfaceOrientation == expected, report.screenMatchesOrientation {
                return report
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("the app did not follow the device to \(Self.name(device)): expected interface \(expected.rawValue), app reported \(last?.encoded ?? "no layout probe")")
        return last
    }

    // MARK: - Capture

    /// One capture: the upright screenshot and what was measured on it.
    public struct Shot {
        public let upright: UIImage
        public let pixels: PixelReader
        public let layout: LayoutReport
        public let capturedAt: Date
    }

    /// One screenshot's place in the run, for the recording check.
    public struct Frame: Encodable, Sendable {
        public let name: String
        /// Seconds since 1970 when the screenshot was taken.
        public let capturedAt: Double
        public let layout: LayoutReport
    }

    /// Takes a screenshot of the whole screen, normalises it upright at the
    /// pixel size the app's screen has, runs the frame checks and attaches:
    /// `<name>` (upright PNG), `<name>.raw-screen` and `<name>.raw-app` (the
    /// buffers XCTest returned, for forensics) and `<name>.layout.json`.
    public func capture(_ name: String, _ app: XCUIApplication, layout: LayoutReport) -> Shot {
        let capturedAt = Date()
        let screen = XCUIScreen.main.screenshot()
        let appShot = app.screenshot()
        attachPNG(screen.pngRepresentation, name: "\(name).raw-screen")
        attachPNG(appShot.pngRepresentation, name: "\(name).raw-app")

        let width = layout.screenshotPixelWidth, height = layout.screenshotPixelHeight
        let upright = Self.upright(screen.image, width: width, height: height, scale: layout.scale)
        let pixels = PixelReader(upright)
        attachPNG(upright.pngData() ?? Data(), name: name)

        var notes: [String: String] = [
            "raw-screen.image.size": "\(screen.image.size.width)x\(screen.image.size.height) pt @\(screen.image.scale)",
            "raw-screen.image.orientation": "\(screen.image.imageOrientation.rawValue)",
            "raw-screen.cgImage": "\(screen.image.cgImage?.width ?? 0)x\(screen.image.cgImage?.height ?? 0) px",
            "raw-app.cgImage": "\(appShot.image.cgImage?.width ?? 0)x\(appShot.image.cgImage?.height ?? 0) px",
            "raw-app.image.orientation": "\(appShot.image.imageOrientation.rawValue)",
            "upright": "\(pixels.width)x\(pixels.height) px",
            "expected": "\(width)x\(height) px",
        ]

        // 1. The size the screen really has, in this orientation.
        XCTAssertEqual(pixels.width, width, "\(name): upright screenshot width")
        XCTAssertEqual(pixels.height, height, "\(name): upright screenshot height")
        // 2. The raw screen buffer has the same shape (else the capture is sideways).
        if let cg = screen.image.cgImage {
            let rawLandscape = cg.width > cg.height, screenLandscape = width > height
            let oriented = screen.image.imageOrientation == .up || screen.image.imageOrientation == .down
            let shownLandscape = oriented ? rawLandscape : !rawLandscape
            notes["raw-screen.shown-landscape"] = "\(shownLandscape)"
            XCTAssertEqual(shownLandscape, screenLandscape, "\(name): XCUIScreen returned a \(shownLandscape ? "landscape" : "portrait") image for a \(screenLandscape ? "landscape" : "portrait") screen")
        }
        // 3. No solid black band along an edge (a filler or a crop shows as one).
        let bands = pixels.blackBands()
        notes["black-bands"] = bands.isEmpty ? "none" : bands.joined(separator: ", ")
        XCTAssertTrue(bands.isEmpty, "\(name): black band(s) at \(bands.joined(separator: ", "))")
        // 4. The app's window covers the screen, as the app measures it and as the tree says.
        XCTAssertTrue(layout.windowCoversScreen, "\(name): app window \(layout.windowWidth)x\(layout.windowHeight) pt on a \(layout.screenWidth)x\(layout.screenHeight) pt screen")
        let frame = app.windows.firstMatch.frame
        notes["tree.window.frame"] = "\(frame)"
        XCTAssertEqual(frame.width, layout.screenWidth, accuracy: 1, "\(name): window width in the accessibility tree")
        XCTAssertEqual(frame.height, layout.screenHeight, accuracy: 1, "\(name): window height in the accessibility tree")

        attachJSON(notes, name: "\(name).capture-notes.json")
        attachJSON(layout, name: "\(name).layout.json")
        // What Scripts/check.py needs to find this screenshot's
        // frame in the screen recording and compare the two.
        attachJSON(Frame(name: name, capturedAt: capturedAt.timeIntervalSince1970, layout: layout), name: "\(name).frame.json")
        return Shot(upright: upright, pixels: pixels, layout: layout, capturedAt: capturedAt)
    }

    /// The screenshot drawn upright at `width`×`height` pixels. `UIImage.draw`
    /// applies the image's own orientation, so a buffer tagged as rotated is
    /// turned before it is measured.
    public static func upright(_ image: UIImage, width: Int, height: Int, scale: Double) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let size = CGSize(width: Double(width) / scale, height: Double(height) / scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Attachments

    public func attachPNG(_ data: Data, name: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    public func attachJSON<T: Encodable>(_ value: T, name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: (try? encoder.encode(value)) ?? Data(), uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
#endif
