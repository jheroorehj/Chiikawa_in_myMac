import Foundation

/// CLI 출력에서 읽어 낸 일.
public enum ChatEvent: Equatable, Sendable {
    /// 이 대화의 세션 ID. 다음 질문에서 이어 가는 데 쓴다.
    case session(String)
    /// 답변 글 조각. 받은 순서대로 이어 붙인다.
    case text(String)
    /// 도구 사용 등 진행 상황 (예: "Bash").
    case activity(String)
    case failed(String)
}

/// CLI 의 표준 출력을 한 줄씩 받아 `ChatEvent` 로 바꾼다.
public struct OutputParser: Sendable {
    public let backend: Backend
    private var hasText = false
    /// Grok 은 여러 줄짜리 JSON 하나를 내므로 끝까지 모았다가 읽는다.
    private var buffered = ""

    public init(backend: Backend) {
        self.backend = backend
    }

    public mutating func consume(line: String) -> [ChatEvent] {
        if backend == .grok {
            buffered += line + "\n"
            return []
        }
        guard let object = Self.object(line) else { return [] }
        switch backend {
        case .claude: return claude(object)
        case .codex: return codex(object)
        case .gemini: return gemini(object)
        case .grok: return []
        }
    }

    /// 출력이 끝났을 때 한 번 부른다.
    public mutating func finish() -> [ChatEvent] {
        guard backend == .grok else { return [] }
        let raw = buffered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        guard let object = Self.object(raw) else { return [.failed(raw)] }
        var events: [ChatEvent] = []
        if let session = object["sessionId"] as? String { events.append(.session(session)) }
        if let text = object["text"] as? String, !text.isEmpty {
            events.append(.text(text))
        } else if let error = object["error"] as? String ?? (object["error"] as? [String: Any])?["message"] as? String {
            events.append(.failed(error))
        }
        return events
    }

    // MARK: - 서비스별 형식

    private mutating func claude(_ object: [String: Any]) -> [ChatEvent] {
        switch object["type"] as? String {
        case "system":
            guard object["subtype"] as? String == "init", let session = object["session_id"] as? String else { return [] }
            return [.session(session)]
        case "assistant":
            let blocks = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return blocks.flatMap { block -> [ChatEvent] in
                switch block["type"] as? String {
                case "text": paragraph(block["text"] as? String)
                case "tool_use": (block["name"] as? String).map { [.activity($0)] } ?? []
                default: []
                }
            }
        case "result":
            guard object["is_error"] as? Bool == true else { return [] }
            return [.failed(object["result"] as? String ?? "Claude 가 오류로 끝났습니다.")]
        default:
            return []
        }
    }

    private mutating func codex(_ object: [String: Any]) -> [ChatEvent] {
        let item = object["item"] as? [String: Any]
        switch object["type"] as? String {
        case "thread.started":
            return (object["thread_id"] as? String).map { [.session($0)] } ?? []
        case "item.started":
            guard item?["type"] as? String == "command_execution" else { return [] }
            return [.activity(item?["command"] as? String ?? "명령 실행")]
        case "item.completed":
            guard item?["type"] as? String == "agent_message" else { return [] }
            return paragraph(item?["text"] as? String)
        case "turn.failed":
            return [.failed((object["error"] as? [String: Any])?["message"] as? String ?? "Codex 가 오류로 끝났습니다.")]
        default:
            // "error" 는 바로 뒤의 "turn.failed" 와 같은 내용이라 한 번만 알린다.
            return []
        }
    }

    private mutating func gemini(_ object: [String: Any]) -> [ChatEvent] {
        switch object["event"] as? String {
        case "init":
            return (object["conversation_id"] as? String).map { [.session($0)] } ?? []
        case "step_update":
            let step = object["step_update"] as? [String: Any] ?? [:]
            switch step["step_type"] as? String {
            case "agent_response":
                guard let delta = step["text_delta"] as? String, !delta.isEmpty else { return [] }
                hasText = true
                return [.text(delta)]
            case "tool":
                guard step["state"] as? String == "ACTIVE", let name = step["tool_name"] as? String else { return [] }
                return [.activity(name)]
            default:
                return []
            }
        case "result":
            let result = object["result"] as? [String: Any] ?? [:]
            guard let status = result["status"] as? String, status != "SUCCESS" else { return [] }
            return [.failed(result["response"] as? String ?? "Gemini 가 \(status) 상태로 끝났습니다.")]
        default:
            return []
        }
    }

    /// 한 덩어리로 오는 답변 글. 앞선 글이 있으면 문단을 띄운다.
    private mutating func paragraph(_ text: String?) -> [ChatEvent] {
        guard let text, !text.isEmpty else { return [] }
        defer { hasText = true }
        return [.text(hasText ? "\n\n" + text : text)]
    }

    private static func object(_ text: String) -> [String: Any]? {
        guard text.first == "{" else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}
