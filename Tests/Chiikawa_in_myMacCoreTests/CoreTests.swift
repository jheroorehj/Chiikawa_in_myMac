import Foundation
import Testing
@testable import Chiikawa_in_myMacCore

// 출력 예시는 실제 CLI 를 실행해 받은 것을 줄인 것이다 (2026-10-11: claude 2.1.296, agy 1.3.3, grok 1.0.50, codex 0.159.3).
// Codex 의 성공 응답(`item.completed`)은 한도 소진으로 받아 보지 못해 공개된 형식을 따랐다.
@Suite struct OutputParserTests {
    private func events(_ backend: Backend, _ output: String) -> [ChatEvent] {
        var parser = OutputParser(backend: backend)
        return output.split(separator: "\n").flatMap { parser.consume(line: String($0)) } + parser.finish()
    }

    @Test func claudeStream() {
        let output = #"""
        {"type":"system","subtype":"hook_started","hook_name":"SessionStart:startup","session_id":"3b38"}
        {"type":"system","subtype":"init","cwd":"/tmp/x","session_id":"3b38","tools":["Bash"]}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"안녕하세요!"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{}}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"읽었습니다."}]}}
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}
        {"type":"result","subtype":"success","is_error":false,"result":"읽었습니다.","session_id":"3b38"}
        """#
        #expect(events(.claude, output) == [
            .session("3b38"), .text("안녕하세요!"), .activity("Read"), .text("\n\n읽었습니다."),
        ])
    }

    @Test func claudeError() {
        let output = #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"한도 초과"}"#
        #expect(events(.claude, output) == [.failed("한도 초과")])
    }

    @Test func codexUsageLimit() {
        let output = #"""
        {"type":"thread.started","thread_id":"01a1"}
        {"type":"turn.started"}
        {"type":"error","message":"You’ve hit your usage limit."}
        {"type":"turn.failed","error":{"message":"You’ve hit your usage limit."}}
        """#
        #expect(events(.codex, output) == [.session("01a1"), .failed("You’ve hit your usage limit.")])
    }

    @Test func codexAnswer() {
        let output = #"""
        {"type":"thread.started","thread_id":"01a1"}
        {"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"ls"}}
        {"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"파일이 둘 있습니다."}}
        {"type":"turn.completed","usage":{"input_tokens":1}}
        """#
        #expect(events(.codex, output) == [.session("01a1"), .activity("ls"), .text("파일이 둘 있습니다.")])
    }

    @Test func geminiStream() {
        let output = #"""
        {"event":"init","conversation_id":"295d","init":{"cwd":"/tmp/x","tools":["ask_permission"]}}
        {"event":"step_update","step_update":{"conversation_id":"295d","step_index":0,"state":"DONE","step_type":"user_input"}}
        {"event":"step_update","step_update":{"step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"write_to_file"}}
        {"event":"step_update","step_update":{"step_index":2,"state":"DONE","step_type":"tool","tool_name":"write_to_file"}}
        {"event":"step_update","step_update":{"step_index":3,"state":"ACTIVE","step_type":"agent_response","text_delta":"계획을 "}}
        {"event":"step_update","step_update":{"step_index":3,"state":"DONE","step_type":"agent_response","text_delta":"세웠습니다.","usage":{}}}
        {"event":"result","result":{"conversation_id":"295d","status":"SUCCESS","response":"계획을 세웠습니다."}}
        """#
        #expect(events(.gemini, output) == [
            .session("295d"), .activity("write_to_file"), .text("계획을 "), .text("세웠습니다."),
        ])
    }

    @Test func grokJSON() {
        let output = """
        {
          "text": "안녕",
          "stopReason": "end_turn",
          "sessionId": "01a12811",
          "thought": "인사한다."
        }
        """
        #expect(events(.grok, output) == [.session("01a12811"), .text("안녕")])
    }

    @Test func grokPlainErrorIsReported() {
        #expect(events(.grok, "error: not logged in") == [.failed("error: not logged in")])
    }

    @Test func ignoresLinesThatAreNotJSON() {
        #expect(events(.claude, "Reading additional input from stdin...").isEmpty)
    }
}

@Suite struct InvocationTests {
    @Test func newClaudeChatIsReadOnlyByDefault() {
        let invocation = Invocation.make(backend: .claude, prompt: "안녕", session: nil, permission: .readOnly)
        #expect(invocation.tool == "claude")
        #expect(invocation.arguments == [
            "-p", "안녕", "--output-format", "stream-json", "--verbose", "--permission-mode", "dontAsk",
            "--settings", #"{"disableAllHooks":true}"#, "--strict-mcp-config",
        ])
    }

    @Test func resumesEachBackendWithItsOwnFlag() {
        func arguments(_ backend: Backend) -> [String] {
            Invocation.make(backend: backend, prompt: "계속", session: "abc", permission: .edit).arguments
        }
        #expect(arguments(.claude).suffix(2) == ["--resume", "abc"])
        #expect(arguments(.codex).prefix(3) == ["exec", "resume", "abc"])
        #expect(arguments(.codex).contains(#"sandbox_mode="workspace-write""#))
        #expect(arguments(.gemini).suffix(2) == ["--conversation", "abc"])
        #expect(arguments(.gemini).contains("accept-edits"))
        #expect(arguments(.grok).suffix(2) == ["--resume", "abc"])
    }

    @Test func promptStartingWithDashIsNotAnOption() {
        let invocation = Invocation.make(backend: .grok, prompt: "--help", session: nil, permission: .readOnly)
        #expect(invocation.arguments[1] == " --help")
    }
}

@Suite struct WorkspaceTests {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chiikawa_in_mymac-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func disabledBackendFallsBackButKeepsItsHistory() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var workspace = Workspace()
        workspace.backend = .grok
        workspace.setSession("s1", for: .grok)
        try workspace.save(to: folder)

        let loaded = Workspace.load(from: folder)
        #expect(loaded.backend == .claude)
        #expect(loaded.session(for: .grok) == "s1")
        #expect(Backend.available == [.claude, .codex])
    }

    @Test func savesInsideTheWorkFolder() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var workspace = Workspace()
        workspace.backend = .codex
        workspace.setSession("s1", for: .codex)
        workspace.messages = [ChatMessage(role: .user, backend: .codex, text: "안녕", date: Date(timeIntervalSince1970: 1_000))]
        try workspace.save(to: folder)

        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".chiikawa_in_mymac/session.json").path))
        #expect(Workspace.load(from: folder) == workspace)
    }

    @Test func missingOrBrokenFileStartsEmpty() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(Workspace.load(from: folder) == Workspace())
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".chiikawa_in_mymac"), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: Workspace.fileURL(in: folder))
        #expect(Workspace.load(from: folder) == Workspace())
    }

    @Test func oldConfigWithoutNewKeysKeepsItsValues() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"workFolder":"/tmp/x","petOrigin":[10,20]}"#.utf8).write(to: url)
        let config = AppConfig.load(from: url)
        #expect(config.workFolder == "/tmp/x")
        #expect(config.petOrigin == [10, 20])
        #expect(config.petScale == 0.6)
        #expect(config.showsMeaning == false)
        #expect(config.isMuted == false)
        #expect(config.mumbles == true)
        #expect(config.relaunchesOnNewBuild == true)
    }

    @Test func resetClearsSessionsButKeepsChoices() {
        var workspace = Workspace()
        workspace.backend = .codex
        workspace.permission = .edit
        workspace.setSession("s1", for: .codex)
        workspace.messages = [ChatMessage(role: .assistant, backend: .codex, text: "네")]
        workspace.reset()
        #expect(workspace.sessions.isEmpty)
        #expect(workspace.messages.isEmpty)
        #expect(workspace.backend == .codex)
        #expect(workspace.permission == .edit)
    }
}

@Suite struct ChatRunnerTests {
    @Test func reportsMissingTool() async {
        let runner = ChatRunner(environment: ShellEnvironment(path: "/nonexistent"))
        let stream = runner.run(backend: .claude, prompt: "안녕", session: nil, permission: .readOnly,
                                folder: FileManager.default.temporaryDirectory)
        await #expect(throws: ChatRunnerError.toolNotFound(.claude)) {
            for try await _ in stream {}
        }
    }

    @Test func errorSummaryKeepsTheLastLines() {
        #expect(ChatRunner.summary(of: "a\nb\n\nc\n  d  \n", status: 1) == "b\nc\nd")
        #expect(ChatRunner.summary(of: "", status: 55) == "CLI 가 오류로 끝났습니다 (종료 코드 55).")
    }
}

@Suite struct UsagiSpeechTests {
    /// 패키지의 `Resources/Voices` 폴더.
    private var voices: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Voices")
    }

    @Test func everyVoiceFileExistsAndIsUsed() throws {
        let speeches = UsagiPhrasebook.speeches
        let used = Set(speeches.compactMap(\.voice))
        for name in used {
            #expect(FileManager.default.fileExists(atPath: voices.appendingPathComponent(name).path), "음성 파일 없음: \(name)")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: voices.path).filter { $0.hasSuffix(".mp3") }
        #expect(Set(files) == used, "쓰이지 않는 음성 파일이 있다")
    }

    @Test func phrasebookListsEveryLine() {
        let listed = Set(UsagiPhrasebook.speeches.map(\.line))
        let everything = [UsagiSpeech.greeting, .sent, .answered, .failed, .cancelled, .reset, .moved]
            + UsagiMumble.openers.map(\.speech) + UsagiMumble.all.map(\.speech)
            + [UsagiMumble.treatAccepted.speech, UsagiMumble.treatDeclined.speech]
        for speech in everything {
            #expect(listed.contains(speech.line), "사전에 없는 말: \(speech.line)")
        }
        let ids = UsagiPhrasebook.sections.flatMap { $0.entries.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }

    @Test func songLyricsHaveATimeForEveryCharacter() throws {
        let song = try #require(UsagiMumble.all.first { $0.style == .song })
        #expect(song.speech.line == "우 우나나, 우나~ 우나나 야하 야하~ 부릿!")
        let timing = try #require(song.speech.timing)
        #expect(timing.count == song.speech.line.count)
        #expect(timing == timing.sorted())
        // "부릿!" 은 앞 소절이 끝난 뒤 한참 있다가 나온다.
        #expect(timing[timing.count - 3] == UsagiMumble.songFinaleTime)
        #expect(timing[timing.count - 3] - timing[timing.count - 4] > 1.5)
        #expect(song.motion == "song")
    }

    @Test func songMotionManifestMatchesItsSheet() throws {
        let folder = voices.deletingLastPathComponent().appendingPathComponent("Pets/usagi")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("song.json")))
        let manifest = try #require(object as? [String: Any])
        let times = try #require(manifest["times"] as? [Double])
        #expect(times == times.sorted())
        #expect(times.first == 0)
        let end = try #require(manifest["end"] as? Double)
        #expect(end > times.last ?? 0)
        // 다리를 꼬는 자세가 "부릿!"과 함께 나오고, 그 자세로 음성이 끝날 때까지 멈춰 있는다.
        #expect(times.contains { abs($0 - UsagiMumble.songFinaleTime) < 0.15 })
        #expect(end > 7.39)
    }

    @Test func everyMotionTheAppAsksForExists() throws {
        let folder = voices.deletingLastPathComponent().appendingPathComponent("Pets/usagi")
        func manifest(_ name: String) throws -> [String: Any] {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("\(name).json")))
            return try #require(object as? [String: Any])
        }
        // 혼잣말이 부르는 특수 모션.
        for name in Set(UsagiPhrasebook.sections.flatMap { $0.entries.compactMap(\.mumble.motion) }) {
            let sheet = try #require(try manifest(name)["spritesheetPath"] as? String)
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(sheet).path), "\(name) 의 시트 없음")
        }
        // pet.json 이 시트의 줄 대신 쓰라고 한 동작: 줄 이름이 맞고, 칸 크기가 평소 시트와 같아야 한다.
        let replacements = try #require(try manifest("pet")["motions"] as? [String: String])
        let rows = Set(PetAnimation.allCases.map(\.name))
        for (row, name) in replacements {
            #expect(rows.contains(row), "없는 줄 이름: \(row)")
            let motion = try manifest(name)
            #expect(motion["cellWidth"] as? Int == 192)
            #expect(motion["cellHeight"] as? Int == 208)
        }
        #expect(replacements["running"] == "lying")
        #expect(replacements["idle"] == nil)
    }

    @Test func everyVoicedLineHasASpecialMotion() {
        for speech in UsagiPhrasebook.speeches where speech.voice != nil {
            #expect(speech.motion != nil, "음성은 있는데 특수 모션이 없는 말: \(speech.line)")
        }
        #expect(UsagiSpeech.sent.motion == "jump")
        #expect(UsagiSpeech.answered.motion == "flip")
    }

    @Test func everyOpenerHasAVoice() {
        #expect(UsagiMumble.openers.count >= 2)
        for opener in UsagiMumble.openers {
            #expect(opener.speech.voice != nil, "음성 없는 여는 말: \(opener.speech.line)")
            // 대화 말풍선보다 먼저 보여 주는 특수 말풍선이라 입력란이 없는 종류여야 한다.
            #expect(opener.style == .shout || opener.style == .sticker)
        }
    }

    @Test func openerChangesEveryTime() {
        var previous: UsagiSpeech?
        for _ in 0..<50 {
            let next = UsagiMumble.opener(after: previous).speech
            #expect(next.line != previous?.line)
            previous = next
        }
    }

    @Test func mumblesFollowTheClock() {
        #expect(UsagiMumble.candidates(hour: 3).map(\.speech.line) == ["구우구우~"])
        #expect(UsagiMumble.candidates(hour: 12).contains { $0.speech.line == "쥬르리" })
        let afternoon = UsagiMumble.candidates(hour: 15).map(\.speech.line)
        #expect(!afternoon.contains("쥬르리"))
        #expect(!afternoon.contains("구우구우~"))
        #expect(afternoon.contains("우라라라라!!"))
    }

    @Test func mumblesUseEveryBubbleStyle() {
        let styles = UsagiMumble.all.map(\.style)
        for style in [UsagiMumble.Style.shout, .thought, .sticker, .whisper, .notice, .choice, .song] {
            #expect(styles.contains(style))
        }
    }
}
