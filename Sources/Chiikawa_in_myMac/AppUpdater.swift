import AppKit

/// 실행 중인 앱 번들이 새로 빌드되면(`scripts/build-app.sh`) 알아채고 다시 시작한다.
///
/// 배포 서버에서 내려받는 업데이트가 아니라, **디스크의 앱이 지금 실행 중인 것보다 새것인지**만 본다.
/// (QuotaBar 의 같은 기능을 옮긴 것)
@MainActor
final class AppUpdater {
    /// 새 빌드가 생기면 바로 다시 시작할지. 끄면 메뉴의 "새 빌드로 다시 시작"으로만 한다.
    var isAutomatic = true {
        didSet { if isAutomatic { relaunchIfReady() } }
    }

    /// 디스크의 앱이 실행 중인 것과 달라졌다.
    private(set) var hasNewBuild = false

    /// 지금 다시 시작해도 되는지 (AI 가 답하는 중이면 끝날 때까지 미룬다).
    var canRelaunchNow: () -> Bool = { true }

    private let bundleURL = Bundle.main.bundleURL
    private let executableURL = Bundle.main.executableURL
    private var launchedStamp: Date?
    private var candidateStamp: Date?
    private var timer: Timer?

    /// `.app` 번들로 실행했을 때만 동작한다. (`swift run` 은 다시 열 번들이 없다)
    var isAvailable: Bool { bundleURL.pathExtension == "app" && executableURL != nil }

    func start() {
        guard isAvailable, timer == nil else { return }
        launchedStamp = executableStamp()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // 정확한 시각이 필요 없다. 허용 오차를 주면 시스템이 다른 타이머와 묶어 깨워 전력을 덜 쓴다.
        timer.tolerance = 1
        self.timer = timer
    }

    private func check() {
        if hasNewBuild {
            relaunchIfReady()
            return
        }
        // 빌드 중에는 번들이 지워졌다가 다시 만들어진다. 실행 파일이 없으면 기다린다.
        guard let stamp = executableStamp(), stamp != launchedStamp else {
            candidateStamp = nil
            return
        }
        // 두 번 연속 같은 시각이고 서명까지 끝난 뒤에만 새 빌드로 본다 (복사·서명 도중에 다시 열지 않도록).
        guard stamp == candidateStamp, isSigned(after: stamp) else {
            candidateStamp = stamp
            return
        }
        hasNewBuild = true
        relaunchIfReady()
    }

    private func relaunchIfReady() {
        if hasNewBuild, isAutomatic, canRelaunchNow() { relaunch() }
    }

    /// 지금 앱을 끄고 디스크의 앱을 다시 연다.
    func relaunch() {
        guard isAvailable else { return }
        // 이 프로세스가 끝나기를 기다렸다가 번들을 다시 연다 (먼저 열면 "이미 켜져 있음"으로 바로 꺼진다).
        let path = "'" + bundleURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done
        # 방금 꺼진 앱을 시스템이 정리하는 동안에는 열기가 실패할 수 있어 몇 번 다시 해 본다.
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
          sleep 0.3
          /usr/bin/open \(path) && exit 0
        done
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
        } catch {
            NSSound.beep()
            return
        }
        timer?.invalidate()
        NSApp.terminate(nil)
    }

    private func executableStamp() -> Date? {
        guard let path = executableURL?.path else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func isSigned(after stamp: Date) -> Bool {
        let seal = bundleURL.appendingPathComponent("Contents/_CodeSignature/CodeResources").path
        guard let signed = (try? FileManager.default.attributesOfItem(atPath: seal))?[.modificationDate] as? Date else {
            return false
        }
        // codesign 은 서명 목록을 쓴 뒤 실행 파일에 서명을 넣으므로 실행 파일 시각이 조금 더 늦다.
        return signed >= stamp.addingTimeInterval(-30)
    }
}
