import XCTest
@testable import xj_AI

final class FloatingSubtitleContentModeTests: XCTestCase {
    func testOriginalModeOnlyShowsOriginal() {
        XCTAssertTrue(FloatingSubtitleContentMode.original.showsOriginal)
        XCTAssertFalse(FloatingSubtitleContentMode.original.showsTranslation)
    }

    func testTranslationModeOnlyShowsTranslation() {
        XCTAssertFalse(FloatingSubtitleContentMode.translation.showsOriginal)
        XCTAssertTrue(FloatingSubtitleContentMode.translation.showsTranslation)
    }

    func testBilingualModeShowsBothLanguages() {
        XCTAssertTrue(FloatingSubtitleContentMode.bilingual.showsOriginal)
        XCTAssertTrue(FloatingSubtitleContentMode.bilingual.showsTranslation)
    }
}
