import Chiikawa_in_myMacCore
import Foundation
import Observation

/// 말풍선의 상태: 작업 폴더의 대화, 진행 중인 질문, 우사기가 지금 하는 말.
@MainActor
@Observable
final class ChatModel {
    /// 말풍선이 지금 어떤 장면인지.
    enum Phase: Equatable {
        /// 켰을 때의 인사. 입력란 없이 잠깐 보였다 사라진다.
        case greeting
        /// 사용자의 말을 기다린다.
        case listening
        case working
        case answered
        case failed
        /// 말풍선을 닫아 둔 동안의 혼잣말. 입력란 없이 잠깐 보였다 사라진다.
        case mumbling(UsagiMumble)

        /// 사용자가 연 것이 아니라 우사기가 혼자 띄운 장면인지.
        var isAmbient: Bool {
            switch self {
            case .greeting, .mumbling: true
            default: false
            }
        }
    }

    enum Outcome { case answered, failed, cancelled }

    private(set) var folder: URL
    private(set) var workspace: Workspace
    private(set) var phase: Phase = .greeting
    /// 우사기 말과 그 뜻. AI 의 답은 이 아래에 대사로 붙는다.
    private(set) var speech: UsagiSpeech = .greeting
    /// 우사기 말 아래에 뜻을 함께 보여 줄지.
    var showsMeaning = false
    /// 우사기 음성을 끌지.
    var isMuted = false
    /// 진행 중에 보여 줄 한 줄 (예: "Read 사용 중").
    private(set) var activity: String?
    /// 저장 실패 등 대화 밖의 문제.
    private(set) var notice: String?

    /// 우사기가 새로 말을 꺼낼 때 부른다 (음성 재생용). 말풍선을 다시 여는 것만으로는 부르지 않는다.
    @ObservationIgnored var onSpeak: (UsagiSpeech) -> Void = { _ in }
    /// 말풍선 안에서 설정(음소거)을 바꿨을 때 부른다.
    @ObservationIgnored var onSettingsChanged: () -> Void = {}
    @ObservationIgnored var onStarted: () -> Void = {}
    @ObservationIgnored var onFinished: (Outcome) -> Void = { _ in }

    @ObservationIgnored private let runner: ChatRunner
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 말풍선에 보여 주는 답변.
    private var replyID: UUID?
    private var errorText: String?
    /// 혼잣말이 덮기 전의 장면. 말풍선을 다시 열면 여기로 돌아온다.
    private var resume: (phase: Phase, speech: UsagiSpeech)?

    init(folder: URL, runner: ChatRunner) {
        self.folder = folder
        self.runner = runner
        workspace = Workspace.load(from: folder)
    }

    var isRunning: Bool { phase == .working }

    var backend: Backend {
        get { workspace.backend }
        set { workspace.backend = newValue; save() }
    }

    var permission: Permission {
        get { workspace.permission }
        set { workspace.permission = newValue; save() }
    }

    /// 지금 고른 AI 와 이어 가는 대화가 있는지.
    var hasSession: Bool { workspace.session(for: backend) != nil }

    /// 말풍선에 대사로 보여 줄 글: AI 의 답(받는 중이면 받은 데까지) 또는 오류.
    var line: String? {
        if phase == .failed { return errorText }
        guard let replyID, let text = workspace.messages.last(where: { $0.id == replyID })?.text, !text.isEmpty else { return nil }
        return text
    }

    /// 대사를 한 AI.
    var lineBackend: Backend? {
        guard let replyID else { return nil }
        return workspace.messages.last { $0.id == replyID }?.backend
    }

    /// 여는 말을 할 수 있는 장면인지. 답을 기다리는 중이거나 오류를 알리는 중이면 그 말을 그대로 둔다.
    var canPlayOpener: Bool {
        if phase.isAmbient { return resume.map { $0.phase == .listening || $0.phase == .answered } ?? true }
        return phase == .listening || phase == .answered
    }

    /// 여는 말(특수 말풍선)을 마치고 대화 말풍선으로 넘어간다. 여는 말은 머리글에 그대로 남고, 보던 답이 있으면 다시 보인다.
    func finishOpener() {
        guard phase.isAmbient else { return }
        phase = resume?.phase ?? .listening
        resume = nil
    }

    /// 인사나 혼잣말을 마치고 사용자와 말하는 장면으로 넘어간다.
    func beginListening() {
        guard phase.isAmbient else { return }
        phase = resume?.phase ?? .listening
        if let resume { speech = resume.speech }
        resume = nil
    }

    /// 혼잣말을 한다.
    func mumble(_ mumble: UsagiMumble) {
        guard !isRunning else { return }
        if !phase.isAmbient { resume = (phase, speech) }
        phase = .mumbling(mumble)
        speak(mumble.speech)
    }

    /// 선택지 말풍선("쥬르리")에 답한다.
    func answerTreat(_ accepted: Bool) {
        mumble(accepted ? .treatAccepted : .treatDeclined)
    }

    func toggleMute() {
        isMuted.toggle()
        onSettingsChanged()
    }

    private func speak(_ speech: UsagiSpeech) {
        self.speech = speech
        onSpeak(speech)
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning else { return }
        let backend = workspace.backend
        workspace.messages.append(ChatMessage(role: .user, backend: backend, text: prompt))
        let reply = ChatMessage(role: .assistant, backend: backend, text: "")
        workspace.messages.append(reply)
        save()
        replyID = reply.id
        errorText = nil
        activity = nil
        resume = nil
        phase = .working
        // 펫의 상태를 먼저 바꾸고 말을 꺼낸다 (말에 붙은 특수 모션이 상태의 동작에 덮이지 않도록).
        onStarted()
        speak(.sent)

        let stream = runner.run(
            backend: backend, prompt: prompt, session: workspace.session(for: backend),
            permission: workspace.permission, folder: folder
        )
        task = Task { [weak self] in
            var failure: String?
            do {
                for try await event in stream {
                    guard let self else { return }
                    switch event {
                    case .session(let id): self.workspace.setSession(id, for: backend)
                    case .text(let chunk): self.append(chunk, to: reply.id)
                    case .activity(let name): self.activity = "\(name) 사용 중"
                    case .failed(let message): failure = message
                    }
                }
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
            }
            self?.finish(reply: reply.id, backend: backend, failure: failure, cancelled: Task.isCancelled)
        }
    }

    /// 진행 중인 질문을 멈춘다. 받은 데까지는 남긴다.
    func cancel() {
        task?.cancel()
    }

    /// 세션 초기화: 모든 AI 가 다음 질문부터 새 대화로 시작한다.
    func reset() {
        cancel()
        workspace.reset()
        save()
        say(.reset)
    }

    func changeFolder(to url: URL) {
        cancel()
        folder = url
        workspace = Workspace.load(from: url)
        notice = nil
        say(.moved)
    }

    /// 대사 없이 우사기 말만 하고 사용자의 말을 기다린다.
    private func say(_ speech: UsagiSpeech) {
        replyID = nil
        errorText = nil
        activity = nil
        resume = nil
        phase = .listening
        speak(speech)
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let index = workspace.messages.lastIndex(where: { $0.id == id }) else { return }
        workspace.messages[index].text += chunk
    }

    private func finish(reply id: UUID, backend: Backend, failure: String?, cancelled: Bool) {
        // 이 답변을 기다리는 동안 세션 초기화나 폴더 변경이 있었으면 장면을 건드리지 않는다.
        let isCurrent = replyID == id
        var hasText = false
        if let index = workspace.messages.lastIndex(where: { $0.id == id }) {
            let text = workspace.messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            // 답이 한 글자도 오지 않았으면 빈 답변을 남기지 않는다.
            if text.isEmpty {
                workspace.messages.remove(at: index)
            } else {
                workspace.messages[index].text = text
                hasText = true
            }
        }
        let failure = cancelled ? nil : failure
        if let failure {
            workspace.messages.append(ChatMessage(role: .error, backend: backend, text: failure))
        }
        task = nil
        save()
        guard isCurrent else { return }
        activity = nil
        let outcome: Outcome
        let speech: UsagiSpeech
        if let failure {
            errorText = failure
            phase = .failed
            (outcome, speech) = (.failed, .failed)
        } else if cancelled {
            phase = hasText ? .answered : .listening
            (outcome, speech) = (.cancelled, .cancelled)
        } else {
            phase = .answered
            (outcome, speech) = (.answered, .answered)
        }
        // 펫의 상태를 먼저 바꾸고 말을 꺼낸다 (말에 붙은 특수 모션이 상태의 동작에 덮이지 않도록).
        onFinished(outcome)
        speak(speech)
    }

    private func save() {
        do {
            try workspace.save(to: folder)
            notice = nil
        } catch {
            notice = "대화를 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }
}
