//
//  ScreenIdentifierTests.swift
//  DeviceProofKitTests
//

import DeviceProofKit
import Foundation
import Testing

@Suite("ScreenIdentifier")
struct ScreenIdentifierTests {
    /// A Coordinator navigation enum with a payload-carrying case.
    enum Page: Hashable, ScreenIdentifier {
        case home
        case detail(id: UUID)

        var screenName: String {
            switch self {
            case .home: "home"
            case .detail: "detail"
            }
        }
    }

    enum Control: String, ScreenIdentifier {
        case continueButton
        static var namespace: String { "control" }
    }

    @Test("the identifier names the case, never its payload")
    func payloadFree() {
        #expect(Page.detail(id: UUID()).accessibilityID == Page.detail(id: UUID()).accessibilityID)
        #expect(Page.detail(id: UUID()).accessibilityID == "screen.detail")
        #expect(Page.home.accessibilityID == "screen.home")
    }

    @Test("a String-backed enum uses its raw value in its own namespace")
    func rawValueNamespace() {
        #expect(Control.continueButton.accessibilityID == "control.continueButton")
    }
}
