import AppKit
import Chiikawa_in_myMacCore

/// 펫 그림. 동작을 재생하고, 끌어서 옮기기와 눌러서 채팅 열기를 받는다.
@MainActor
final class PetView: NSView {
    var onClick: () -> Void = {}
    var onMoved: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }

    /// 지금 알리는 상태. 한 번짜리 동작이 끝나면 이 상태의 동작으로 돌아간다.
    var mood: PetMood = .idle {
        didSet {
            guard mood != oldValue else { return }
            acting = nil
            play(mood.animation)
        }
    }

    /// 상태와 상관없이 잠깐 보여 주는 동작 (혼잣말). nil 로 되돌리면 상태의 동작으로 돌아간다.
    var acting: PetAnimation? {
        didSet { if acting != oldValue { play(acting ?? mood.animation) } }
    }

    private let sheet: SpriteSheet
    private var animation: PetAnimation = .idle
    private var frames: [CGImage] = []
    private var index = 0
    private var timer: Timer?
    /// 재생 중인 특수 모션과 시작한 때, 끝났을 때 부를 것.
    private var special: (motion: SpecialMotion, start: Date, index: Int, onEnd: () -> Void)?
    /// 시트의 줄 대신 재생 중인 동작과 시작한 때.
    private var clip: (motion: SpecialMotion, start: Date, index: Int)?
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var didDrag = false

    init(sheet: SpriteSheet) {
        self.sheet = sheet
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("우사기 — 눌러서 채팅 열기")
        play(.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 는 쓰지 않는다") }

    /// 한 번짜리 동작(인사·점프)을 보여 준다.
    func perform(_ animation: PetAnimation) {
        play(animation)
    }

    /// 특수 모션을 처음부터 한 번 보여 준다. 칸은 시작한 때로부터의 시각에 맞춰 바뀐다 (음성과 함께 시작할 것).
    /// 다른 동작이 끼어들거나 끝까지 가면 `onEnd` 를 부른다.
    func playSpecial(_ motion: SpecialMotion, onEnd: @escaping () -> Void) {
        stopSpecial()
        timer?.invalidate()
        clip = nil
        special = (motion, Date(), -1, onEnd)
        tickSpecial()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickSpecial() }
        }
    }

    /// 특수 모션을 그만둔다.
    func stopSpecial() {
        guard let special else { return }
        self.special = nil
        timer?.invalidate()
        special.onEnd()
        play(acting ?? mood.animation)
    }

    private func tickSpecial() {
        guard let special else { return }
        var elapsed = Date().timeIntervalSince(special.start)
        if special.motion.loops {
            elapsed = elapsed.truncatingRemainder(dividingBy: special.motion.end)
        } else if elapsed >= special.motion.end {
            stopSpecial()
            return
        }
        let index = special.motion.frameIndex(at: elapsed)
        guard index != special.index else { return }
        self.special?.index = index
        show(special.motion.frames[index])
    }

    /// 시트의 줄을 대신하는 동작을 한 칸 진행한다. 반복하는 동작은 다른 동작으로 바뀔 때까지 계속 돌고
    /// (기본 모습으로 돌아가지 않는다), 한 번짜리면 끝에서 평소 흐름으로 돌아간다.
    private func tickClip() {
        guard let clip else { return }
        var elapsed = Date().timeIntervalSince(clip.start)
        if elapsed >= clip.motion.end {
            if !clip.motion.loops, animation.playsOnce {
                self.clip = nil
                timer?.invalidate()
                finishOnce()
                return
            }
            elapsed = elapsed.truncatingRemainder(dividingBy: clip.motion.end)
        }
        let index = clip.motion.frameIndex(at: elapsed)
        guard index != clip.index else { return }
        self.clip?.index = index
        show(clip.motion.frames[index])
    }

    private func show(_ image: CGImage) {
        // 칸이 바뀔 때 흐려지며 섞이지 않게 한다.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
    }

    /// 한 번짜리 동작이 끝났다. 연기하던 중(혼잣말)이면 그 장면이 끝날 때까지 같은 동작을 되풀이하고,
    /// 아니면 지금 상태의 동작으로 돌아간다.
    private func finishOnce() {
        if acting == animation {
            play(animation)
        } else {
            play(acting ?? mood.animation)
        }
    }

    private func play(_ animation: PetAnimation) {
        if special != nil {
            // 특수 모션 중에 다른 동작이 끼어들면 특수 모션을 끝낸다 (끝내면서 이 동작을 다시 부른다).
            let onEnd = special?.onEnd
            special = nil
            timer?.invalidate()
            onEnd?()
        }
        self.animation = animation
        clip = nil
        timer?.invalidate()
        if let motion = sheet.clips[animation] {
            // 이 줄은 받은 GIF 로 만든 동작으로 대신한다. 칸은 시작한 때로부터의 시각에 맞춰 바뀐다.
            clip = (motion, Date(), 0)
            show(motion.frames[0])
            // 한 장짜리(가만히 엎드린 모습)이거나 동작 줄이기가 켜져 있으면 첫 칸만 보여 준다.
            guard motion.frames.count > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tickClip() }
            }
            return
        }
        frames = sheet.frames(for: animation)
        index = 0
        show()
        schedule(after: animation.frameDuration)
    }

    private func show() {
        guard frames.indices.contains(index) else { return }
        show(frames[index])
    }

    private func schedule(after delay: TimeInterval) {
        timer?.invalidate()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    private func advance() {
        index += 1
        if index < frames.count {
            show()
            schedule(after: animation.frameDuration)
            return
        }
        // 한 바퀴 끝.
        if animation.playsOnce {
            finishOnce()
        } else {
            index = 0
            show()
            // 가만히 있을 때는 잠깐 쉬었다가 다시 깜빡인다.
            schedule(after: animation == .idle ? .random(in: 1.5...4) : animation.frameDuration)
        }
    }

    // MARK: - 마우스

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let windowStart, let window else { return }
        let location = NSEvent.mouseLocation
        let delta = NSPoint(x: location.x - dragStart.x, y: location.y - dragStart.y)
        if !didDrag, abs(delta.x) < 3, abs(delta.y) < 3 { return }
        didDrag = true
        window.setFrameOrigin(NSPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y))
        // 시트의 두 줄이 이름과 반대 방향으로 그려져 있어 바꿔서 쓴다 (사용자 요청): 왼쪽으로 끌면 running-right 줄.
        let direction: PetAnimation = event.deltaX < 0 ? .runningRight : .runningLeft
        if animation != direction, abs(event.deltaX) > 0.5 || !(animation == .runningLeft || animation == .runningRight) {
            play(direction)
        }
        onMoved()
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        if didDrag {
            play(acting ?? mood.animation)
            onMoved()
        } else {
            onClick()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider()
    }
}
