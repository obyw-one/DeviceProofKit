//
//  XCUIElement+ScreenIdentifier.swift
//  DeviceProofTestSupport
//
//  Walk the app's accessibility tree by the identifiers its Coordinator enum
//  declares — the way a web test walks the DOM — never by visible copy.
//

#if DEBUG && os(iOS)
import DeviceProofKit
import XCTest

public extension XCUIElement {
    /// The first descendant marked with `id` (`.screenID(_:)` in the app).
    func element(_ id: some ScreenIdentifier) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id.accessibilityID).firstMatch
    }

    /// Waits for the screen (or control) `id` and fails, naming it, when it
    /// never appears. Returns the element so a test can keep walking from it.
    @discardableResult
    func waitFor(
        _ id: some ScreenIdentifier,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let found = element(id)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "\(id.accessibilityID) never appeared", file: file, line: line)
        return found
    }
}
#endif
