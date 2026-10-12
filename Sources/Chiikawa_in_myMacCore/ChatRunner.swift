import Foundation

public enum ChatRunnerError: LocalizedError, Equatable {
    case toolNotFound(Backend)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let backend):
            "\(backend.displayName) CLI(`\(backend.tool)`)를 찾을 수 없습니다. 설치하고 로그인한 뒤 다시 시도하세요."
        }
    }
}

/// CLI 를 한 번 실행하고 출력을 `ChatEvent` 로 흘려보낸다.
public struct ChatRunner: Sendable {
    public let environment: ShellEnvironment

    public init(environment: ShellEnvironment) {
        self.environment = environment
    }

    /// 스트림을 그만 읽으면(작업 취소) 실행 중인 CLI 도 끝낸다.
    public func run(
        backend: Backend, prompt: String, session: String?, permission: Permission, folder: URL
    ) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let executable = environment.locate(backend.tool) else {
                continuation.finish(throwing: ChatRunnerError.toolNotFound(backend))
                return
            }
            let invocation = Invocation.make(backend: backend, prompt: prompt, session: session, permission: permission)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = invocation.arguments
            process.currentDirectoryURL = folder
            process.environment = environment.processEnvironment
            // 입력을 기다리며 멈추지 않게 한다.
            process.standardInput = FileHandle.nullDevice
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors

            let task = Task.detached {
                var parser = OutputParser(backend: backend)
                var failed = false
                func emit(_ events: [ChatEvent]) {
                    for event in events {
                        if case .failed = event { failed = true }
                        continuation.yield(event)
                    }
                }
                do {
                    try process.run()
                    // 오류 출력은 따로 읽어 둔다. 읽지 않으면 버퍼가 차서 CLI 가 멈출 수 있다.
                    async let errorText = Self.readAll(errors.fileHandleForReading)
                    for try await line in output.fileHandleForReading.bytes.lines {
                        emit(parser.consume(line: line))
                    }
                    emit(parser.finish())
                    process.waitUntilExit()
                    let stderr = await errorText
                    if process.terminationStatus != 0, !failed, !Task.isCancelled {
                        emit([.failed(Self.summary(of: stderr, status: process.terminationStatus))])
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }

    private static func readAll(_ handle: FileHandle) async -> String {
        await Task.detached { String(decoding: handle.readDataToEndOfFile(), as: UTF8.self) }.value
    }

    /// 오류 출력의 마지막 몇 줄만 보여 준다 (스택 추적 전체는 말풍선에 너무 길다).
    static func summary(of stderr: String, status: Int32) -> String {
        let lines = stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "CLI 가 오류로 끝났습니다 (종료 코드 \(status))." }
        return lines.suffix(3).joined(separator: "\n")
    }
}
