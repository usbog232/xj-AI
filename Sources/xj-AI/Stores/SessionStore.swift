import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SessionRecord]
    @Published var selectedSessionID: UUID?

    private let persistence: SessionPersistence
    var persistenceEnabled = true

    init(persistence: SessionPersistence = SessionPersistence()) {
        self.persistence = persistence
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            let demo = Self.demoSessions
            self.sessions = demo
            self.selectedSessionID = demo.first?.id
        } else {
            let loaded = persistence.loadSessions()
            let initial = loaded
            self.sessions = initial
            self.selectedSessionID = initial.first?.id
        }
    }

    var selectedSession: SessionRecord? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == selectedSessionID })
    }

    @discardableResult
    func createLiveSession(
        id: UUID = UUID(),
        source: AudioSource,
        sourceLanguage: String,
        targetLanguage: String,
        model: String
    ) -> UUID {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        let session = SessionRecord(
            id: id,
            title: "实时翻译 · \(formatter.string(from: Date()))",
            source: source,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            translationModel: model
        )
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        if persistenceEnabled { try? persistence.save(session) }
        return session.id
    }

    func addSegment(_ segment: TranscriptSegment, to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].segments.append(segment)
        save(index: index)
    }

    func updateTranslation(_ translation: String, segmentID: UUID, sessionID: UUID) {
        guard
            let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
            let segmentIndex = sessions[sessionIndex].segments.firstIndex(where: { $0.id == segmentID })
        else { return }
        sessions[sessionIndex].segments[segmentIndex].translation = translation
        sessions[sessionIndex].segments[segmentIndex].isTranslationPending = false
        save(index: sessionIndex)
    }

    func finalize(sessionID: UUID, duration: TimeInterval, audioFileName: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].duration = duration
        sessions[index].audioFileName = audioFileName
        save(index: index)
    }

    func renameSelected(to title: String) {
        guard let selectedSessionID, let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessions[index].title = trimmed
        save(index: index)
    }

    func persistSelected() {
        guard let selectedSession, !ProcessInfo.processInfo.arguments.contains("--demo") else { return }
        try? persistence.save(selectedSession)
    }

    func records(withIDs ids: Set<UUID>) -> [SessionRecord] {
        sessions.filter { ids.contains($0.id) }
    }

    @discardableResult
    func deleteSessions(withIDs ids: Set<UUID>) throws -> Int {
        let targets = records(withIDs: ids)
        var deletedIDs = Set<UUID>()
        var firstError: Error?

        for session in targets {
            do {
                try persistence.delete(session)
                deletedIDs.insert(session.id)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        sessions.removeAll { deletedIDs.contains($0.id) }
        if let selectedSessionID, deletedIDs.contains(selectedSessionID) {
            self.selectedSessionID = sessions.first?.id
        }
        if let firstError { throw firstError }
        return deletedIDs.count
    }

    private func save(index: Int) {
        let demoIDs = Set(Self.demoSessions.map(\.id))
        guard persistenceEnabled, !ProcessInfo.processInfo.arguments.contains("--demo"), !demoIDs.contains(sessions[index].id) else { return }
        try? persistence.save(sessions[index])
    }

    private static let demoSessions: [SessionRecord] = {
        let live = SessionRecord(
            title: "实时翻译",
            createdAt: Date(),
            duration: 138,
            source: .systemAudio,
            sourceLanguage: "en-US",
            targetLanguage: "zh-CN",
            translationModel: "qwen3:4b",
            segments: [
                TranscriptSegment(startTime: 5, endTime: 11, original: "Good morning, everyone. Thanks for joining this product interview.", translation: "大家早上好，感谢大家参加这次产品访谈。", isTranslationPending: false),
                TranscriptSegment(startTime: 12, endTime: 23, original: "Could you briefly introduce your role and the team you're working with?", translation: "你能简单介绍一下你的角色以及所在的团队吗？", isTranslationPending: false),
                TranscriptSegment(startTime: 24, endTime: 41, original: "Sure. I'm the product manager, and I lead a team of five engineers, one designer, and one QA.", translation: "当然。我是产品经理，带领一个由五名工程师、一名设计师和一名测试组成的团队。", isTranslationPending: false),
                TranscriptSegment(startTime: 42, endTime: 61, original: "What are the main challenges you're facing in your current workflow?", translation: "你们当前工作流程中面临的主要挑战是什么？", isTranslationPending: false),
                TranscriptSegment(startTime: 62, endTime: 82, original: "The biggest challenge is information fragmentation across tools.", translation: "最大的挑战是信息分散在不同工具中。", isTranslationPending: false)
            ]
        )
        return [
            live,
            SessionRecord(title: "产品访谈", createdAt: Date().addingTimeInterval(-3_600), duration: 2_892),
            SessionRecord(title: "英文课程", createdAt: Date().addingTimeInterval(-86_400), duration: 2_207),
            SessionRecord(title: "周会记录", createdAt: Date().addingTimeInterval(-172_800), duration: 1_635),
            SessionRecord(title: "技术分享会", createdAt: Date().addingTimeInterval(-260_000), duration: 3_753)
        ]
    }()
}
