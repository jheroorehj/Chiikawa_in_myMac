import Foundation

public struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant, error }

    public var id: UUID
    public var role: Role
    /// 답한 AI. 사용자가 쓴 글이면 질문을 받은 AI.
    public var backend: Backend
    public var text: String
    public var date: Date

    public init(id: UUID = UUID(), role: Role, backend: Backend, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.backend = backend
        self.text = text
        self.date = date
    }
}

/// 작업 폴더 하나의 대화 상태. 폴더 안 `.chiikawa_in_mymac/session.json` 에 저장해 폴더를 옮겨도 따라간다.
/// (각 CLI 가 따로 남기는 대화 기록은 각자의 홈 폴더에 있다)
public struct Workspace: Codable, Equatable, Sendable {
    public var backend: Backend = .claude
    public var permission: Permission = .readOnly
    /// AI 별로 이어 갈 세션 ID. 없으면 다음 질문이 새 대화가 된다.
    public var sessions: [String: String] = [:]
    public var messages: [ChatMessage] = []

    public init() {}

    public func session(for backend: Backend) -> String? {
        sessions[backend.rawValue]
    }

    public mutating func setSession(_ id: String?, for backend: Backend) {
        sessions[backend.rawValue] = id
    }

    /// 세션 초기화: 모든 AI 의 세션과 화면의 대화를 비운다. 선택한 AI 와 권한은 그대로 둔다.
    public mutating func reset() {
        sessions = [:]
        messages = []
    }

    public static func fileURL(in folder: URL) -> URL {
        folder.appendingPathComponent(".chiikawa_in_mymac/session.json")
    }

    /// 파일이 없거나 읽을 수 없으면 빈 상태로 시작한다.
    public static func load(from folder: URL) -> Workspace {
        guard let data = try? Data(contentsOf: fileURL(in: folder)) else { return Workspace() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var workspace = (try? decoder.decode(Workspace.self, from: data)) ?? Workspace()
        // 꺼 둔 AI 를 고른 채로 저장돼 있으면 쓸 수 있는 것으로 바꾼다. 그 AI 와의 지난 대화와 세션은 남겨 둔다.
        if !workspace.backend.isAvailable { workspace.backend = Backend.available[0] }
        return workspace
    }

    public func save(to folder: URL) throws {
        let url = Self.fileURL(in: folder)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// 앱 전체 설정 (`~/.config/chiikawa_in_mymac/config.json`): 작업 폴더와 펫의 위치·크기.
public struct AppConfig: Codable, Equatable, Sendable {
    public var workFolder: String?
    public var petOrigin: [Double]?
    public var petScale: Double = 0.6
    /// 우사기 말 아래에 뜻("(=가자!)")을 함께 보여 줄지. 평소에는 끈다.
    public var showsMeaning = false
    /// 우사기 음성을 끌지.
    public var isMuted = false
    /// 말풍선을 닫아 둔 동안 가끔 혼잣말을 할지.
    public var mumbles = true
    /// 앱을 새로 빌드하면 켜져 있던 앱이 스스로 다시 시작할지.
    public var relaunchesOnNewBuild = true

    public init() {}

    /// 예전 설정 파일에 없는 항목은 기본값으로 둔다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workFolder = try container.decodeIfPresent(String.self, forKey: .workFolder)
        petOrigin = try container.decodeIfPresent([Double].self, forKey: .petOrigin)
        petScale = try container.decodeIfPresent(Double.self, forKey: .petScale) ?? 0.6
        showsMeaning = try container.decodeIfPresent(Bool.self, forKey: .showsMeaning) ?? false
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        mumbles = try container.decodeIfPresent(Bool.self, forKey: .mumbles) ?? true
        relaunchesOnNewBuild = try container.decodeIfPresent(Bool.self, forKey: .relaunchesOnNewBuild) ?? true
    }

    /// `CHIIKAWA_CONFIG_FILE` 로 다른 파일을 가리킬 수 있다 (시험용).
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["CHIIKAWA_CONFIG_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/chiikawa_in_mymac/config.json")
    }

    public static func load(from url: URL = defaultURL) -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return AppConfig() }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
