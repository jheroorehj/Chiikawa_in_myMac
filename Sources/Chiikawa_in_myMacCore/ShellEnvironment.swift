import Foundation

/// 사용자의 로그인 셸이 쓰는 PATH. Finder 에서 켠 앱은 PATH 가 짧아 CLI 를 찾지 못하므로 한 번 물어 온다.
public struct ShellEnvironment: Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    /// 로그인 셸을 한 번 실행해 PATH 를 읽는다. 실패하면 흔한 설치 위치로 대신한다.
    public static func load() -> ShellEnvironment {
        let marker = "__CHIIKAWA_PATH__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "echo \(marker)$PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        var found: String?
        if (try? process.run()) != nil {
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            // 셸 설정이 다른 글을 찍어도 표시한 줄만 읽는다.
            found = output.split(separator: "\n").last { $0.hasPrefix(marker) }.map { String($0.dropFirst(marker.count)) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallback = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return ShellEnvironment(path: found.flatMap { $0.isEmpty ? nil : $0 } ?? fallback)
    }

    /// PATH 에서 실행 파일을 찾는다.
    public func locate(_ tool: String) -> String? {
        path.split(separator: ":").lazy
            .map { "\($0)/\(tool)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 하위 프로세스에 넘길 환경. 지금 환경에 PATH 만 바꾼다.
    public var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        return environment
    }
}
