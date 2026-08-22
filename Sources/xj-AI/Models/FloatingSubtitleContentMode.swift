import Foundation

enum FloatingSubtitleContentMode: String, CaseIterable, Identifiable {
    case original
    case translation
    case bilingual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原文"
        case .translation: "译文"
        case .bilingual: "双语"
        }
    }

    var symbol: String {
        switch self {
        case .original: "text.quote"
        case .translation: "character.book.closed"
        case .bilingual: "character.bubble"
        }
    }

    var showsOriginal: Bool { self != .translation }
    var showsTranslation: Bool { self != .original }
}
