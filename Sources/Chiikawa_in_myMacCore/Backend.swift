import Foundation

/// 펫이 말을 전할 수 있는 AI. 각자의 CLI 를 화면 없이 한 번씩 실행한다.
public enum Backend: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude, codex, gemini, grok

    public var id: String { rawValue }

    /// 지금 쓸 수 있게 열어 둔 AI. Gemini 와 Grok 은 실행·해석 코드는 그대로 두고 꺼 두었다 (사용자 요청).
    public static let available: [Backend] = [.claude, .codex]

    public var isAvailable: Bool { Self.available.contains(self) }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .grok: "Grok"
        }
    }

    /// 실행 파일 이름. Gemini 는 Antigravity CLI 를 쓴다 (기존 Gemini CLI 는 개인 계정 지원이 끝났다).
    public var tool: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .gemini: "agy"
        case .grok: "grok"
        }
    }
}

/// AI 가 작업 폴더에서 할 수 있는 일의 범위.
public enum Permission: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 읽기만. 파일 수정과 명령 실행은 거절된다.
    case readOnly
    /// 작업 폴더 안의 파일을 고칠 수 있다.
    case edit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .readOnly: "읽기 전용"
        case .edit: "파일 수정 허용"
        }
    }
}

/// CLI 한 번 실행에 넘길 인자.
public struct Invocation: Equatable, Sendable {
    public let tool: String
    public let arguments: [String]

    /// - Parameter session: 이어 갈 세션 ID. 없으면 새 대화.
    public static func make(backend: Backend, prompt: String, session: String?, permission: Permission) -> Invocation {
        // "-" 로 시작하는 글이 옵션으로 읽히지 않게 한다.
        let prompt = prompt.hasPrefix("-") ? " " + prompt : prompt
        var arguments: [String]
        switch backend {
        case .claude:
            arguments = ["-p", prompt, "--output-format", "stream-json", "--verbose",
                         "--permission-mode", permission == .edit ? "acceptEdits" : "dontAsk",
                         // 사용자의 Claude 설정에 걸린 훅과 외부 도구(MCP) 서버를 건너뛴다. 터미널용으로 걸어 둔 훅이
                         // 이 앱 밑에서는 끝나지 않아 답이 영영 오지 않은 적이 있고, 건너뛰면 시작도 빠르다.
                         "--settings", #"{"disableAllHooks":true}"#, "--strict-mcp-config"]
            if let session { arguments += ["--resume", session] }
        case .codex:
            arguments = ["exec"]
            if let session { arguments += ["resume", session] }
            // `exec resume` 에는 -s 가 없어 설정 값으로 넘긴다.
            arguments += ["--json", "--skip-git-repo-check",
                          "-c", "sandbox_mode=\"\(permission == .edit ? "workspace-write" : "read-only")\"",
                          prompt]
        case .gemini:
            arguments = ["-p", prompt, "--output-format", "stream-json"]
            if permission == .edit { arguments += ["--mode", "accept-edits"] }
            if let session { arguments += ["--conversation", session] }
        case .grok:
            arguments = ["-p", prompt, "--output-format", "json",
                         "--permission-mode", permission == .edit ? "acceptEdits" : "dontAsk"]
            if let session { arguments += ["--resume", session] }
        }
        return Invocation(tool: backend.tool, arguments: arguments)
    }
}
