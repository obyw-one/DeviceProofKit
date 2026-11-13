// swift-tools-version: 6.0

import PackageDescription

// DeviceProofKit — prove every screen of a native app in every orientation and
// colour scheme, with captures that are checked before anyone calls them
// evidence. Extracted from shikki-client's device-proof layer (#33,
// 2026-11-13) so every fleet app, and every app the shi-agency scaffold
// generates, gets the same calibration card and the same checks.
//
// Two products, two sides of one contract:
// - `DeviceProofKit` links into the APP. Its probes, its calibration card and
//   the launch-argument hook exist only in DEBUG builds; a release build keeps
//   the screen-identifier protocol and an identity `.deviceProof()` modifier.
// - `DeviceProofTestSupport` links into an XCUITest target (iOS): capture,
//   upright normalisation, the frame checks and the calibration test case.
// The post-run checker and the XcodeGen scheme fix live in `Scripts/`.
let package = Package(
    name: "DeviceProofKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DeviceProofKit", targets: ["DeviceProofKit"]),
        .library(name: "DeviceProofTestSupport", targets: ["DeviceProofTestSupport"]),
    ],
    targets: [
        .target(name: "DeviceProofKit"),
        .target(name: "DeviceProofTestSupport", dependencies: ["DeviceProofKit"]),
        .testTarget(name: "DeviceProofKitTests", dependencies: ["DeviceProofKit"]),
    ]
)
