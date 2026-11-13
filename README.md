# DeviceProofKit

Prove every screen of a native app in every orientation and colour scheme, with captures that pass checks before anyone calls them evidence.

It was extracted from the shikki-client device-proof layer (shikki-client#33). The reason: on 2026-11-13 an iPad proof shipped screenshots that were portrait UIs sideways in a landscape buffer, with a black band and a cropped side, plus a recording stretched 1.78×, and no check caught any of it.

## What is in it

| Part | Links into | What it does |
|---|---|---|
| `DeviceProofKit` | the **app** | `ScreenIdentifier` (screen ids from the Coordinator enum) and `.screenID(_:)`. `.deviceProof()` is the launch-argument hook. Behind `#if DEBUG`: `LayoutReport` + the `LayoutProbe` overlay, and `CalibrationPattern` + `CalibrationPatternView` (the test card, a "mire de barres"). |
| `DeviceProofTestSupport` | an **XCUITest** target (iOS) | `DeviceProofCapture`: rotate and wait for the app to follow, then capture via `XCUIScreen`, normalise upright and check size, raw-buffer shape, black bands and window coverage. `CalibrationPatternTestCase`: orientation is a class parameter. `XCUIElement.element(_:)` and `waitFor(_:)` walk the tree by `ScreenIdentifier`. |
| `Scripts/check.py` | after a run | Exports the `.xcresult` attachments. It checks the screen recording's frame at each screenshot's timestamp against the screenshot (rotation by pixel error, SSIM) and checks the card's colour samples in the video. It writes `<test>.upright.mp4` and `check-report.{md,json}`. |
| `Scripts/keep-attachments.py` | XcodeGen `postGenCommand` | Sets `systemAttachmentLifetime = "keepAlways"` on the scheme's TestAction, so a passing run keeps its recording. XcodeGen 2.46 cannot write it. |

### Debug and test only, by construction

In a release build:

- the probe, the card, `DeviceProbe`, `LayoutReport` and the launch-argument parsing do not exist;
- `.deviceProof()` compiles to the identity.

Only `ScreenIdentifier` remains. Accessibility identifiers are not user-visible, and the navigation enum lives in production code. `DeviceProofTestSupport` is likewise `#if DEBUG && os(iOS)`.

## Adopt it in an app (XcodeGen)

```yaml
packages:
  DeviceProofKit:
    url: https://github.com/obyw-one/DeviceProofKit
    from: 0.1.0
options:
  postGenCommand: python3 scripts/device-proof/keep-attachments.py MyApp.xcodeproj MyApp
targets:
  MyApp:
    dependencies:
      - package: DeviceProofKit
  MyAppDeviceProof:
    type: bundle.ui-testing
    platform: iOS
    sources: [DeviceProof]
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: MyApp
      - package: DeviceProofKit
        product: DeviceProofTestSupport
schemes:
  MyApp:
    build: { targets: { MyApp: all } }
    test: { targets: [MyAppDeviceProof] }
```

Copy `Scripts/check.py` and `Scripts/keep-attachments.py` into `scripts/device-proof/`, because `postGenCommand` runs before packages resolve. The shi-agency scaffold does all of this for you.

In the app, add the hook to the scene root and an identifier to each screen:

```swift
WindowGroup {
    RootView().deviceProof()
}

enum Page: String, ScreenIdentifier { case home, settings }
// Presenter: HomeView().screenID(Page.home)
```

In the UI-test target, add one class per orientation; each inherits `test_pattern_light` and `test_pattern_dark`:

```swift
import DeviceProofTestSupport
import XCTest

final class CalibrationPortraitTests: CalibrationPatternTestCase {
    override class var orientation: UIDeviceOrientation { .portrait }
}
final class CalibrationLandscapeTests: CalibrationPatternTestCase {
    override class var orientation: UIDeviceOrientation { .landscapeLeft }
}
```

Orientation is a class parameter, rotated in `class setUp`, because the iOS screen recorder fixes its canvas when a test starts.

## Run a proof

```sh
xcodebuild test -project MyApp.xcodeproj -scheme MyApp \
  -destination 'platform=iOS,name=<device>' -resultBundlePath run.xcresult
python3 scripts/device-proof/check.py run.xcresult proof-out   # exit 0 = every capture passes
```

`check.py` needs `ffmpeg`/`ffprobe` (Homebrew) and `xcrun xcresulttool`; it uses no Python packages.

Report two things separately:

- what the test assertions prove;
- whether the media passed `check.py`.

Media rotated or cropped by hand is not evidence.

## Tests

`kagami test --scope DeviceProofKit` covers:

- the card geometry and the JSON contract `check.py` reads;
- the layout report;
- launch arguments;
- screen identifiers.

The capture side runs in a consuming app's UI-test target on a simulator or device.

## License

Apache-2.0 (see `LICENSE` and `NOTICE`), © OBYW.one. Apps link this library, so it carries the same license as the other fleet kits (ChatKit, CMSKit, AuthKit).
