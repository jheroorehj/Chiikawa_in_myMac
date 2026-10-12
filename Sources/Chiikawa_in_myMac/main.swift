import AppKit
import Chiikawa_in_myMacCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let url = PetLocator.spritesheetURL(), let sheet = SpriteSheet.load(from: url) else {
            fail("펫 그림(스프라이트 시트)을 찾거나 읽을 수 없습니다.")
            return
        }
        var config = AppConfig.load()
        guard let folder = workFolder(config: &config) else {
            NSApp.terminate(nil)
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let controller = PetController(config: config, sheet: sheet, folder: folder, environment: .load())
        BubbleFont.register()
        // 처음 켰을 때는 무엇을 하는 앱인지 보이도록 바로 말을 걸 수 있게 연다. `CHIIKAWA_OPEN_CHAT=1` 은 화면 확인용.
        controller.start(openComposer: isFirstLaunch || environment["CHIIKAWA_OPEN_CHAT"] == "1")
        self.controller = controller
        // `CHIIKAWA_PHRASEBOOK=1` 은 켜자마자 우사기 말 사전을 연다 (화면 확인용).
        if environment["CHIIKAWA_PHRASEBOOK"] == "1" { controller.showPhrasebook() }
        // `CHIIKAWA_SEND=<글>` 은 켜자마자 질문을 보낸다 (창을 열지 않고 응답 흐름을 확인하는 용도).
        if let prompt = environment["CHIIKAWA_SEND"], !prompt.isEmpty { controller.send(prompt) }
    }

    private var isFirstLaunch = false

    /// 저장한 작업 폴더를 쓰고, 없으면 처음 한 번 고르게 한다.
    private func workFolder(config: inout AppConfig) -> URL? {
        var isDirectory: ObjCBool = false
        if let path = config.workFolder, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return URL(fileURLWithPath: path)
        }
        isFirstLaunch = true
        guard let url = FolderPicker.choose(current: nil) else { return nil }
        config.workFolder = url.path
        try? config.save()
        return url
    }

    private func fail(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "우사기를 시작할 수 없습니다"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}

// 이미 켜져 있으면 하나만 둔다.
// 다시 시작할 때는 방금 꺼진 앱이 시스템 목록에 잠깐 남아 있을 수 있어, 꺼지는 중인 것은 세지 않고 조금 기다려 다시 본다.
if let bundleID = Bundle.main.bundleIdentifier {
    func otherIsRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { $0 != .current && !$0.isTerminated }
    }
    var attempts = 0
    while otherIsRunning(), attempts < 10 {
        Thread.sleep(forTimeInterval: 0.3)
        attempts += 1
    }
    if otherIsRunning() { exit(0) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Dock 아이콘 없이 펫과 메뉴바 아이콘만 둔다.
app.setActivationPolicy(.accessory)
app.run()
