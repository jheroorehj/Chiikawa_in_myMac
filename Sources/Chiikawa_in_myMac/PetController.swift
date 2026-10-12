import AppKit
import SwiftUI
import Chiikawa_in_myMacCore

/// 펫 창과 말풍선 창을 띄우고 둘을 잇는다.
@MainActor
final class PetController: NSObject, NSMenuDelegate {
    private var config: AppConfig
    private let sheet: SpriteSheet
    private let model: ChatModel
    private let layout = BubbleLayout()
    private let petView: PetView
    private let petWindow: NSPanel
    private var bubbleWindow: ChatPanel?
    private var statusItem: NSStatusItem?
    private var phrasebookWindow: NSWindow?
    /// 인사 말풍선을 저절로 닫는 예약, 퇴장 애니메이션 뒤에 창을 내리는 예약.
    /// 여는 말(특수 말풍선) 뒤에 대화 말풍선을 여는 예약.
    private var pendingChat: DispatchWorkItem?
    private var autoHide: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    /// 다음 혼잣말 예약.
    private var nextMumble: DispatchWorkItem?
    private let voice = VoicePlayer()
    private let updater = AppUpdater()
    /// 특수 모션. 이름으로 찾고, 한 번 읽은 것은 다시 읽지 않는다.
    private var motions: [String: SpecialMotion] = [:]
    /// 특수 모션 동안 넓힌 펫 창을 되돌릴 크기.
    private var normalPetSize: CGSize?

    init(config: AppConfig, sheet: SpriteSheet, folder: URL, environment: ShellEnvironment) {
        self.config = config
        self.sheet = sheet
        model = ChatModel(folder: folder, runner: ChatRunner(environment: environment))
        model.showsMeaning = config.showsMeaning
        model.isMuted = config.isMuted
        petView = PetView(sheet: sheet)

        let size = CGSize(width: sheet.cellSize.width * config.petScale, height: sheet.cellSize.height * config.petScale)
        petWindow = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        super.init()

        petWindow.isOpaque = false
        petWindow.backgroundColor = .clear
        petWindow.hasShadow = false
        petWindow.level = .floating
        // 모든 데스크톱과 전체 화면 앱 위에서도 보인다.
        petWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        petWindow.contentView = petView
        petWindow.setFrameOrigin(initialOrigin(size: size))

        petView.onClick = { [weak self] in self?.petClicked() }
        petView.onMoved = { [weak self] in self?.petMoved() }
        petView.menuProvider = { [weak self] in self?.makeMenu() }
        voice.isMuted = config.isMuted
        model.onSpeak = { [weak self] speech in self?.spoke(speech) }
        model.onSettingsChanged = { [weak self] in self?.settingsChanged() }
        model.onStarted = { [weak self] in self?.questionStarted() }
        model.onFinished = { [weak self] outcome in self?.replyFinished(outcome) }
    }

    /// - Parameter openComposer: 인사 대신 바로 말을 걸 수 있게 연다.
    func start(openComposer: Bool) {
        // 새로 빌드하면 스스로 다시 시작한다. AI 가 답하는 중이면 답이 끝난 뒤에.
        updater.isAutomatic = config.relaunchesOnNewBuild
        updater.canRelaunchNow = { [weak self] in self?.model.isRunning != true }
        updater.start()
        petWindow.orderFrontRegardless()
        installStatusItem()
        if openComposer {
            openForInput()
        } else {
            // 인사: 귀 풍선으로 한마디 하고 저절로 닫힌다.
            petView.perform(.waving)
            showBubble(focus: false)
            scheduleAutoHide(after: BubbleToken.autoHide)
        }
    }

    /// 우사기가 혼자 띄운 말풍선(인사, 혼잣말)을 잠시 뒤에 닫는다.
    private func scheduleAutoHide(after delay: TimeInterval) {
        autoHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.phase.isAmbient else { return }
            self.hideBubble()
        }
        autoHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - 말과 혼잣말

    /// 우사기가 새로 말을 꺼냈다: 음성을 내고, 혼잣말이면 말풍선과 동작을 맞춘다.
    private func spoke(_ speech: UsagiSpeech) {
        voice.play(speech.voice)
        var mumble: UsagiMumble?
        if case .mumbling(let current) = model.phase { mumble = current }
        // 말(또는 혼잣말)에 붙은 특수 모션이 있으면 그것을, 없으면 혼잣말의 평소 동작을 한다.
        if let name = mumble?.motion ?? speech.motion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let motion = motion(named: name) {
            playSpecial(motion)
        } else if let mumble {
            petView.acting = mumble.animation
        }
        guard let mumble else { return }
        showBubble(focus: false)
        let base: TimeInterval = switch mumble.style {
        // 누르거나 닫을 시간을 넉넉히 준다.
        case .choice: 15
        case .notice: 10
        default: BubbleToken.autoHide
        }
        // 음성이 길면 끝날 때까지 띄워 둔다.
        scheduleAutoHide(after: max(base, voice.duration(of: speech.voice) + 1))
    }

    private func motion(named name: String) -> SpecialMotion? {
        if let loaded = motions[name] { return loaded }
        guard let folder = PetLocator.petFolder()?.folder, let motion = SpecialMotion.load(named: name, in: folder) else { return nil }
        motions[name] = motion
        return motion
    }

    /// 특수 모션을 보여 준다. 칸이 평소보다 넓어서 그동안 펫 창을 제자리에서 넓힌다 (발 위치는 그대로).
    private func playSpecial(_ motion: SpecialMotion) {
        endSpecial()
        let pet = petWindow.frame
        normalPetSize = pet.size
        let size = CGSize(width: motion.cellSize.width * config.petScale, height: motion.cellSize.height * config.petScale)
        petWindow.setFrame(CGRect(x: pet.midX - size.width / 2, y: pet.minY, width: size.width, height: size.height), display: true)
        petView.playSpecial(motion) { [weak self] in
            guard let self else { return }
            self.restorePetSize()
            // 춤이 끝나고 노래가 이어지는 동안은 엎드리지 않고 혼잣말의 동작으로 서 있는다.
            if case .mumbling(let mumble) = self.model.phase, mumble.motion != nil, self.isBubbleVisible {
                self.petView.acting = mumble.animation
            }
        }
    }

    /// 재생 중인 특수 모션을 그만두고 펫 창을 되돌린다.
    private func endSpecial() {
        petView.stopSpecial()
    }

    private func restorePetSize() {
        guard let size = normalPetSize else { return }
        normalPetSize = nil
        let frame = petWindow.frame
        petWindow.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.minY, width: size.width, height: size.height), display: true)
    }

    /// 다음 혼잣말을 예약한다. 말풍선이 닫혀 있고 AI 가 일하지 않을 때만 실제로 말한다.
    private func scheduleMumble() {
        nextMumble?.cancel()
        guard config.mumbles else { return }
        let environment = ProcessInfo.processInfo.environment
        // `CHIIKAWA_MUMBLE_SECONDS` 는 간격을 고정한다 (화면 확인용). 평소에는 4~10분 사이.
        let delay = environment["CHIIKAWA_MUMBLE_SECONDS"].flatMap(TimeInterval.init) ?? .random(in: 240...600)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.config.mumbles, !self.isBubbleVisible, !self.model.isRunning {
                let hour = Calendar.current.component(.hour, from: Date())
                // `CHIIKAWA_MUMBLE=<우사기 말>` 은 그 말만 하게 한다 (화면 확인용).
                let forced = environment["CHIIKAWA_MUMBLE"].flatMap { line in UsagiMumble.all.first { $0.speech.line == line } }
                if let mumble = forced ?? UsagiMumble.candidates(hour: hour).randomElement() {
                    self.model.mumble(mumble)
                    return
                }
            }
            self.scheduleMumble()
        }
        nextMumble = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 우사기 말 사전을 연다. 말을 누르면 펫이 그 말을 해 보인다.
    func showPhrasebook() {
        if phrasebookWindow == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 560),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false
            )
            window.title = "우사기 말 사전"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentMinSize = CGSize(width: 340, height: 320)
            window.contentView = NSHostingView(rootView: PhrasebookView(model: model) { [weak self] entry in
                self?.model.mumble(entry.mumble)
            })
            window.center()
            phrasebookWindow = window
        }
        NSApp.activate()
        phrasebookWindow?.makeKeyAndOrderFront(nil)
        phrasebookWindow?.orderFrontRegardless()
    }

    private func settingsChanged() {
        voice.isMuted = model.isMuted
        if model.isMuted { voice.stop() }
        config.isMuted = model.isMuted
        try? config.save()
    }

    func send(_ prompt: String) {
        model.beginListening()
        model.send(prompt)
    }

    // MARK: - 펫

    private func initialOrigin(size: CGSize) -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        if let saved = config.petOrigin, saved.count == 2 {
            let origin = NSPoint(x: saved[0], y: saved[1])
            // 저장한 자리가 지금 화면 안일 때만 쓴다 (모니터를 뗐을 수 있다).
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(CGRect(origin: origin, size: size)) }) {
                return origin
            }
        }
        return NSPoint(x: visible.maxX - size.width - 40, y: visible.minY + 40)
    }

    private func petMoved() {
        positionBubble()
        config.petOrigin = [petWindow.frame.origin.x, petWindow.frame.origin.y]
        try? config.save()
    }

    private func petClicked() {
        // 인사 중에 누르면 닫지 않고 바로 말을 걸 수 있게 한다.
        if isBubbleVisible, !model.phase.isAmbient { hideBubble() } else { openForInput() }
    }

    private func questionStarted() {
        petView.mood = .working
        showBubble(focus: false)
    }

    private func replyFinished(_ outcome: ChatModel.Outcome) {
        // 말풍선을 닫아 둔 사이에 답이 와도 우사기가 말을 꺼낸다.
        showBubble(focus: false)
        switch outcome {
        case .failed:
            petView.mood = .failed
        case .answered:
            // 동작은 이어서 나오는 "야하!"의 특수 모션이 맡는다.
            petView.mood = .listening
        case .cancelled:
            petView.mood = .listening
        }
    }

    // MARK: - 말풍선

    private var isBubbleVisible: Bool { bubbleWindow?.isVisible == true && layout.isPresented }

    /// 사용자가 말풍선을 열었다. 우사기가 여는 말을 꺼낸다.
    private func openForInput() {
        // 여는 말을 하던 중에 또 누르면 기다리지 않고 바로 대화 말풍선을 연다.
        if pendingChat != nil {
            openChat()
            return
        }
        settlePose()
        guard model.canPlayOpener else {
            model.beginListening()
            showBubble(focus: true)
            return
        }
        // 먼저 혼잣말처럼 특수 말풍선으로 여는 말을 하고(음성·특수 모션), 말이 끝나면 대화 말풍선을 연다.
        let opener = UsagiMumble.opener(after: model.speech)
        model.mumble(opener)
        autoHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.openChat() }
        pendingChat = work
        let wait = max(1.0, voice.duration(of: opener.speech.voice) + 0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// 여는 말을 마치고 대화 말풍선을 연다. 하던 특수 모션은 그대로 이어진다.
    private func openChat() {
        pendingChat?.cancel()
        pendingChat = nil
        autoHide?.cancel()
        model.finishOpener()
        showBubble(focus: true)
    }

    /// 말풍선을 입력할 수 있게 띄운다 (우사기 말은 바꾸지 않는다).
    private func presentForInput() {
        pendingChat?.cancel()
        pendingChat = nil
        settlePose()
        showBubble(focus: true)
    }

    /// 하던 특수 모션과 연기를 그만두고 말풍선을 열어 둔 동안의 자세로 간다.
    private func settlePose() {
        endSpecial()
        petView.acting = nil
        if !model.isRunning, model.phase != .failed { petView.mood = .listening }
    }

    private func showBubble(focus: Bool) {
        pendingClose?.cancel()
        if !model.phase.isAmbient { autoHide?.cancel() }
        nextMumble?.cancel()
        let window = bubbleWindow ?? makeBubbleWindow()
        bubbleWindow = window
        positionBubble()
        if focus {
            // 글자를 입력받으려면 앱이 활성이어야 한다.
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        layout.isPresented = true
    }

    private func hideBubble() {
        autoHide?.cancel()
        pendingChat?.cancel()
        pendingChat = nil
        layout.isPresented = false
        endSpecial()
        petView.acting = nil
        if !model.isRunning { petView.mood = .idle }
        scheduleMumble()
        // 퇴장 애니메이션이 끝난 뒤에 창을 내린다.
        let work = DispatchWorkItem { [weak self] in self?.bubbleWindow?.orderOut(nil) }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + BubbleToken.exit, execute: work)
    }

    private func makeBubbleWindow() -> ChatPanel {
        let window = ChatPanel(
            contentRect: CGRect(x: 0, y: 0, width: BubbleLayout.canvasWidth, height: BubbleLayout.maxCanvasHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        // 그림자는 말풍선이 직접 그린다 (어긋난 단색 그림자).
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 말풍선은 다크 모드에서도 크림 바탕에 잉크 글자다.
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: BubbleView(
            model: model, layout: layout, close: { [weak self] in self?.hideBubble() }
        ))
        return window
    }

    /// 말풍선 창을 펫 머리 위에 두고 꼬리가 펫을 가리키게 한다. 위에 자리가 없으면 아래로 보낸다.
    private func positionBubble() {
        guard let bubbleWindow else { return }
        let pet = petWindow.frame
        let visible = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? pet
        let width = BubbleLayout.canvasWidth
        // 그림 칸의 위쪽 빈 곳만큼 겹쳐서 꼬리가 귀 가까이 오게 한다.
        let overlap = pet.height * 0.12
        let above = visible.maxY - (pet.maxY - overlap)
        let below = (pet.minY + overlap) - visible.minY
        let goesAbove = above >= 300 || above >= below

        let height = min(BubbleLayout.maxCanvasHeight, max(200, goesAbove ? above : below))
        var origin = NSPoint(x: pet.midX - width / 2, y: goesAbove ? pet.maxY - overlap : pet.minY + overlap - height)
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - width))
        layout.canvasHeight = height
        layout.tailEdge = goesAbove ? .bottom : .top
        layout.tailX = pet.midX - origin.x
        bubbleWindow.setFrame(CGRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
    }

    // MARK: - 작업 폴더

    private func chooseFolder() {
        guard let url = FolderPicker.choose(current: model.folder) else { return }
        model.changeFolder(to: url)
        config.workFolder = url.path
        try? config.save()
        presentForInput()
    }

    private func revealFolder() {
        NSWorkspace.shared.open(model.folder)
    }

    // MARK: - 메뉴

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let height: CGFloat = 18
        if let url = PetLocator.menuIconURL(), let image = NSImage(contentsOf: url), image.size.height > 0 {
            // 색이 있는 그림이라 템플릿으로 바꾸지 않고 그대로 보여 준다.
            image.size = NSSize(width: height * image.size.width / image.size.height, height: height)
            item.button?.image = image
        } else if let frame = sheet.frames(for: .idle).first {
            item.button?.image = NSImage(cgImage: frame, size: NSSize(width: height * sheet.cellSize.width / sheet.cellSize.height, height: height))
        } else {
            item.button?.title = "우사기"
        }
        item.button?.setAccessibilityLabel("우사기")
        let menu = NSMenu()
        // 열 때마다 지금 상태(권한 체크 표시)로 다시 채운다.
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("말풍선 열기/닫기", #selector(toggleBubbleFromMenu)))
        menu.addItem(item("새 대화 (세션 초기화)", #selector(resetSession)))
        menu.addItem(.separator())
        // AI 고르기. 말풍선에는 고르는 버튼을 두지 않는다.
        for backend in Backend.available {
            let entry = item("\(backend.displayName) 와 대화", #selector(chooseBackend(_:)))
            entry.representedObject = backend.rawValue
            entry.state = backend == model.backend ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        for permission in Permission.allCases {
            let entry = item(permission.displayName, #selector(choosePermission(_:)))
            entry.representedObject = permission.rawValue
            entry.state = permission == model.permission ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let meaning = item("우사기 말 뜻 보기", #selector(toggleMeaning))
        meaning.state = model.showsMeaning ? .on : .off
        menu.addItem(meaning)
        menu.addItem(item("우사기 말 모두 보기…", #selector(showPhrasebookFromMenu)))
        let mumbles = item("혼잣말 하기", #selector(toggleMumbles))
        mumbles.state = config.mumbles ? .on : .off
        menu.addItem(mumbles)
        let mute = item("음소거", #selector(toggleMute))
        mute.state = model.isMuted ? .on : .off
        menu.addItem(mute)
        menu.addItem(.separator())
        menu.addItem(item("작업 폴더 바꾸기…", #selector(chooseFolderFromMenu)))
        menu.addItem(item("Finder 에서 작업 폴더 열기", #selector(revealFolderFromMenu)))
        menu.addItem(.separator())
        menu.addItem(item("펫을 화면 구석으로 데려오기", #selector(bringPetBack)))
        if updater.isAvailable {
            menu.addItem(.separator())
            let automatic = item("새 빌드가 생기면 자동으로 다시 시작", #selector(toggleAutoRelaunch))
            automatic.state = updater.isAutomatic ? .on : .off
            menu.addItem(automatic)
            menu.addItem(item(updater.hasNewBuild ? "새 빌드로 다시 시작" : "다시 시작", #selector(relaunch)))
        }
        menu.addItem(.separator())
        menu.addItem(item("우사기 종료", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleBubbleFromMenu() { petClicked() }
    @objc private func chooseFolderFromMenu() { chooseFolder() }
    @objc private func revealFolderFromMenu() { revealFolder() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func resetSession() {
        model.reset()
        presentForInput()
    }

    @objc private func chooseBackend(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let backend = Backend(rawValue: raw), !model.isRunning else { return }
        model.backend = backend
    }

    @objc private func choosePermission(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let permission = Permission(rawValue: raw) else { return }
        model.permission = permission
    }

    @objc private func toggleMeaning() {
        model.showsMeaning.toggle()
        config.showsMeaning = model.showsMeaning
        try? config.save()
    }

    @objc private func toggleMute() { model.toggleMute() }
    @objc private func relaunch() { updater.relaunch() }

    @objc private func toggleAutoRelaunch() {
        config.relaunchesOnNewBuild.toggle()
        try? config.save()
        updater.isAutomatic = config.relaunchesOnNewBuild
    }
    @objc private func showPhrasebookFromMenu() { showPhrasebook() }

    @objc private func toggleMumbles() {
        config.mumbles.toggle()
        try? config.save()
        if config.mumbles { scheduleMumble() } else { nextMumble?.cancel() }
    }

    @objc private func bringPetBack() {
        config.petOrigin = nil
        petWindow.setFrameOrigin(initialOrigin(size: petWindow.frame.size))
        petWindow.orderFrontRegardless()
        petMoved()
    }
}

/// 테두리 없는 창은 기본으로 키 입력을 받지 못하므로 받도록 한다.
final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

enum FolderPicker {
    /// 작업 폴더를 고르게 한다. 취소하면 nil.
    @MainActor
    static func choose(current: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        panel.prompt = "이 폴더에서 작업"
        panel.message = "우사기가 AI 와 함께 작업할 폴더를 고르세요. AI 는 이 폴더 안에서 파일을 읽고(허용하면) 고칩니다."
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
}
