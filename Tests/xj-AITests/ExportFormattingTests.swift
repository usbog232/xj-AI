import XCTest
@testable import xj_AI

final class ExportFormattingTests: XCTestCase {
    func testClockFormatting() {
        XCTAssertEqual(TimeFormatters.clock(3_661), "01:01:01")
    }

    func testSubtitleFormatting() {
        XCTAssertEqual(TimeFormatters.subtitle(62.345), "00:01:02,345")
        XCTAssertEqual(TimeFormatters.subtitle(62.345, separator: "."), "00:01:02.345")
    }
}
