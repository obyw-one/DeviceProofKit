//
//  ScreenIdentifier.swift
//  DeviceProofKit
//
//  A UI test finds a screen by an identifier that comes from the app's
//  Coordinator navigation enum, never by the text a screen shows (operator
//  direction, 2026-11-13: a proof failed after 53 s because a test looked for a
//  button labelled "Continue" whose copy had become "Continue to model
//  selection"). The navigation enum conforms once; the Presenter applies the
//  identifier to each screen's root; the UI test reads the same enum. Neither
//  side can misspell it, and copy changes never break a test.
//
//  Available in every build configuration: accessibility identifiers are not
//  user-visible, and the navigation enum lives in production code.
//

import SwiftUI

/// A value naming a screen (or a control) that UI tests locate by identifier.
///
/// Conform the Coordinator's navigation enum — page and sheet cases alike:
///
/// ```swift
/// enum Page: Hashable, ScreenIdentifier {
///     case home, settings, detail(id: UUID)
///     var screenName: String {
///         switch self {
///         case .home: "home"
///         case .settings: "settings"
///         case .detail: "detail"   // the case, never its payload
///         }
///     }
/// }
/// ```
///
/// A `String`-backed enum gets `screenName` from its raw value for free.
/// Controls use their own enum with `namespace` set to `"control"`.
public protocol ScreenIdentifier: Sendable {
    /// A stable name for the case, without its associated values.
    var screenName: String { get }
    /// The identifier family: `screen` by default, `control` for sub-components.
    static var namespace: String { get }
}

public extension ScreenIdentifier {
    static var namespace: String { "screen" }

    /// The accessibility identifier the app sets and the UI test queries.
    var accessibilityID: String { "\(Self.namespace).\(screenName)" }
}

public extension ScreenIdentifier where Self: RawRepresentable, RawValue == String {
    var screenName: String { rawValue }
}

public extension View {
    /// Marks this view as the root of `screen` (or as the control it names)
    /// for UI tests. The Presenter applies it once per screen.
    func screenID(_ screen: some ScreenIdentifier) -> some View {
        accessibilityIdentifier(screen.accessibilityID)
    }
}
