import Chiikawa_in_myMacCore
import Observation
import SwiftUI

/// 말풍선 창의 배치. 펫의 위치에 따라 `PetController` 가 정한다.
@MainActor
@Observable
final class BubbleLayout {
    /// 말풍선을 그리는 투명한 창의 크기.
    nonisolated static let canvasWidth: CGFloat = 420
    nonisolated static let maxCanvasHeight: CGFloat = 620
    /// 입력란이 있는 말풍선의 폭.
    nonisolated static let bodyWidth: CGFloat = 340

    var canvasHeight: CGFloat = BubbleLayout.maxCanvasHeight
    /// 꼬리 끝의 가로 위치 (창 왼쪽 끝 기준). 펫의 머리를 가리킨다.
    var tailX: CGFloat = BubbleLayout.canvasWidth / 2
    /// 펫 위에 자리가 없으면 말풍선이 아래로 가고 꼬리가 위에 붙는다.
    var tailEdge: BubbleShape.TailEdge = .bottom
    /// 등장·퇴장 애니메이션용.
    var isPresented = false
}

/// 펫 머리 위에 뜨는 말풍선. 우사기 말(+뜻) 아래에 AI 의 답이 대사로 붙고, 그 아래에서 말을 건다.
/// 혼잣말일 때는 입력란 없이 종류별 말풍선만 뜬다.
struct BubbleView: View {
    @Bindable var model: ChatModel
    var layout: BubbleLayout
    var close: () -> Void

    @State private var draft = ""
    /// 대사 글의 실제 높이.
    @State private var lineHeight: CGFloat = 0
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsComposer: Bool { !model.phase.isAmbient }

    private var mumble: UsagiMumble? {
        if case .mumbling(let mumble) = model.phase { return mumble }
        return nil
    }

    /// 외침과 스티커는 튕기듯 튀어나온다.
    private var pops: Bool { mumble?.style == .shout || mumble?.style == .sticker }

    var body: some View {
        content
            .scaleEffect(layout.isPresented ? 1 : (pops ? 0.6 : 0.96), anchor: layout.tailEdge == .bottom ? .bottom : .top)
            .offset(y: layout.isPresented || pops ? 0 : (layout.tailEdge == .bottom ? 8 : -8))
            .opacity(layout.isPresented ? 1 : 0)
            .animation(
                reduceMotion ? nil : (layout.isPresented
                    ? (pops ? .timingCurve(0.34, 1.56, 0.64, 1, duration: BubbleToken.enter)
                            : .timingCurve(0.2, 0.8, 0.2, 1, duration: mumble?.style == .whisper ? 0.3 : BubbleToken.enter))
                    : .timingCurve(0.6, 0, 0.9, 0.4, duration: BubbleToken.exit)),
                value: layout.isPresented
            )
            .foregroundStyle(BubbleToken.ink)
            .tint(BubbleToken.ink)
            // 말풍선을 꼬리(펫) 쪽에 가운데 맞추되 창 밖으로 나가지 않게 한다.
            .alignmentGuide(.leading) { [tailX = layout.tailX] in -Self.minX(width: $0.width, tailX: tailX) }
            .frame(
                width: BubbleLayout.canvasWidth, height: layout.canvasHeight,
                alignment: layout.tailEdge == .bottom ? .bottomLeading : .topLeading
            )
            .onExitCommand(perform: close)
            .onChange(of: layout.isPresented) { _, presented in
                if presented, showsComposer { inputFocused = true }
            }
            .onChange(of: model.phase) { _, _ in
                if showsComposer { inputFocused = true }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let mumble {
            mumbleBubble(mumble)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("우사기 혼잣말")
        } else {
            chatBubble
                .accessibilityElement(children: .contain)
                .accessibilityLabel("우사기 말풍선")
        }
    }

    // MARK: - 대화

    private var chatBubble: some View {
        let variant: BubbleVariant = model.phase == .greeting ? .ears : (model.phase == .failed ? .whisper : .basic)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 2) {
                SpeechLine(speech: model.speech, showsMeaning: model.showsMeaning)
                if showsComposer {
                    Spacer(minLength: 4)
                    IconButton(
                        symbol: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: model.isMuted ? "음소거 풀기" : "음소거", action: model.toggleMute
                    )
                    IconButton(symbol: "xmark", label: "말풍선 닫기", action: close)
                }
            }
            if let line = model.line {
                dialogue(line)
            }
            if model.isRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.activity ?? "\(model.backend.displayName) 에게 물어보는 중…")
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BubbleToken.ink.opacity(0.7))
            }
            if showsComposer {
                composer
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: showsComposer ? BubbleLayout.bodyWidth : nil, alignment: .leading)
        .tailedBackground(variant, layout: layout)
        .padding(.top, variant == .ears ? 30 : 0)
    }

    /// AI 의 답. 우사기 말과 달리 사람 말 그대로, 말풍선의 대사로 보여 준다.
    private func dialogue(_ line: String) -> some View {
        let text = Text(Self.rendered(line))
            .font(BubbleToken.display(16))
            .lineSpacing(4)
            .foregroundStyle(model.phase == .failed ? BubbleToken.danger : BubbleToken.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        // 다른 내용(우사기 말, 입력란)의 자리를 빼고 남는 높이.
        let limit = max(120, layout.canvasHeight - 230)
        return VStack(alignment: .leading, spacing: 2) {
            if let backend = model.lineBackend, model.phase != .failed {
                Text(backend.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BubbleToken.ink.opacity(0.55))
            }
            // 짧으면 글 높이만큼, 길면 남는 높이까지만 차지하고 그 안에서 스크롤한다.
            ScrollView {
                text.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
            }
            .frame(height: min(max(lineHeight, 20), limit))
            .scrollDisabled(lineHeight <= limit)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                TextField(
                    "", text: $draft,
                    prompt: Text("\(model.backend.displayName) 에게 말 걸기").foregroundStyle(BubbleToken.ink.opacity(0.45)),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(BubbleToken.display(16))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
                .accessibilityLabel("\(model.backend.displayName) 에게 보낼 말")

                Button {
                    if model.isRunning { model.cancel() } else { send() }
                } label: {
                    Image(systemName: model.isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(BubbleToken.bubble)
                        .frame(width: 26, height: 26)
                        .background { Circle().fill(BubbleToken.ink) }
                }
                .buttonStyle(PressScale())
                .disabled(!model.isRunning && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(model.isRunning ? "멈추기" : "보내기")
                .accessibilityLabel(model.isRunning ? "멈추기" : "보내기")
            }
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BubbleToken.bubble) }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(inputFocused ? BubbleToken.focus : BubbleToken.ink, lineWidth: 2)
            }

            // 어느 AI 와 말하는지는 여기와 입력란 안내 글로만 보여 준다. 바꾸는 것은 메뉴에서 한다.
            Text("\(model.backend.displayName) · \(model.folder.lastPathComponent) · \(model.permission.displayName) · \(model.hasSession ? "대화 이어가는 중" : "새 대화")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BubbleToken.ink.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.folder.path)
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BubbleToken.danger)
            }
        }
        .padding(.top, 2)
    }

    private func send() {
        guard !model.isRunning else { return }
        model.send(draft)
        draft = ""
    }

    // MARK: - 혼잣말

    @ViewBuilder
    private func mumbleBubble(_ mumble: UsagiMumble) -> some View {
        let speech = mumble.speech
        switch mumble.style {
        case .basic, .ears:
            // 사전에서 들어 볼 때: 대화 말풍선과 같은 모양.
            SpeechLine(speech: speech, showsMeaning: model.showsMeaning)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .tailedBackground(mumble.style == .ears ? .ears : .basic, layout: layout)
                .padding(.top, mumble.style == .ears ? 30 : 0)
        case .shout:
            // 글자 1.4배, 꼬리 없이 가시 돋친 모양.
            SpeechLine(speech: speech, showsMeaning: model.showsMeaning, size: 28, centered: true)
                .padding(.horizontal, 56)
                .padding(.vertical, 42)
                .frame(minWidth: 182)
                .background {
                    BurstShape().fill(BubbleToken.bubble)
                    BurstShape().stroke(BubbleToken.ink, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
                }
                .padding(4)
        case .thought:
            SpeechLine(speech: speech, showsMeaning: model.showsMeaning, centered: true)
                .padding(.horizontal, 38)
                .padding(.vertical, 26)
                .frame(minWidth: 120)
                .background {
                    CloudShape().fill(BubbleToken.bubble)
                    CloudShape().stroke(BubbleToken.ink, style: StrokeStyle(lineWidth: BubbleToken.lineWidth, lineJoin: .round))
                }
                .padding(4)
                // 방울 꼬리 두 개가 펫 쪽으로 이어진다.
                .padding(layout.tailEdge == .bottom ? .bottom : .top, 26)
                .overlay(alignment: layout.tailEdge == .bottom ? .bottomLeading : .topLeading) {
                    GeometryReader { proxy in
                        let tail = layout.tailX - Self.minX(width: proxy.size.width, tailX: layout.tailX)
                        let down = layout.tailEdge == .bottom
                        ThoughtDot(size: 14).position(x: tail - 9, y: down ? proxy.size.height - 19 : 19)
                        ThoughtDot(size: 9).position(x: tail - 1.5, y: down ? proxy.size.height - 6 : 6)
                    }
                }
        case .sticker:
            // 글자 1.5배, 기울어진 분홍 딱지.
            SpeechLine(speech: speech, showsMeaning: model.showsMeaning, size: 30)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .tailedBackground(.sticker, layout: layout)
                .rotationEffect(.degrees(-5))
                .padding(6)
        case .whisper:
            // 글자 0.8배에 자간을 벌린다.
            SpeechLine(speech: speech, showsMeaning: model.showsMeaning, size: 16, tracking: 1.3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .tailedBackground(.whisper, layout: layout)
        case .notice:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "bell").font(.system(size: 14, weight: .bold))
                    Text("우사기 알림").font(BubbleToken.display(16)).lineLimit(1)
                    Spacer(minLength: 8)
                    IconButton(symbol: "xmark", label: "알림 닫기", size: 36, action: close)
                }
                .padding(.leading, 12)
                .background { UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(BubbleToken.butter) }
                Rectangle().fill(BubbleToken.ink).frame(height: 2)
                SpeechLine(speech: speech, showsMeaning: model.showsMeaning)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
            .frame(minWidth: 220)
            .fixedSize()
            // 머리띠가 외곽선 안쪽에 들어오게 한다.
            .padding(1.5)
            .tailedBackground(.notice, layout: layout)
        case .song:
            // 가사가 음성에 맞춰 나오고(`UsagiSpeech.timing`), 음표가 테두리 위에서 까딱거린다.
            SpeechLine(speech: speech, showsMeaning: model.showsMeaning, centered: true, maxWidth: 230)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(layout.tailEdge == .bottom ? .bottom : .top, BubbleToken.tailHeight)
            .background {
                GeometryReader { proxy in
                    let tail = layout.tailX - Self.minX(width: proxy.size.width, tailX: layout.tailX)
                    let shape = SongShape(tailX: tail, tailEdge: layout.tailEdge)
                    shape.fill(BubbleToken.ink.opacity(0.2)).offset(BubbleToken.shadowOffset)
                    shape.fill(BubbleToken.butter)
                    shape.stroke(BubbleToken.ink, style: StrokeStyle(lineWidth: BubbleToken.lineWidth, lineJoin: .round))
                }
            }
            .overlay(alignment: .topLeading) { SongNote(symbol: "music.note", delay: 0).offset(x: -6, y: -20) }
            .overlay(alignment: .top) { SongNote(symbol: "music.quarternote.3", delay: 0.2).offset(x: 14, y: -26) }
            .overlay(alignment: .topTrailing) { SongNote(symbol: "music.note", delay: 0.4).offset(x: 8, y: -14) }
            .padding(.bottom, 8)
            .padding(.top, 34)
            .padding(.horizontal, 12)
        case .choice:
            VStack(alignment: .leading, spacing: 12) {
                SpeechLine(speech: speech, showsMeaning: model.showsMeaning)
                // 사람이 누르는 버튼만 사람 말이다.
                HStack(spacing: 8) {
                    Button("간식 주기") { model.answerTreat(true) }
                        .buttonStyle(ChoiceStyle(primary: true))
                    Button("나중에") { model.answerTreat(false) }
                        .buttonStyle(ChoiceStyle(primary: false))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(minWidth: 220)
            .fixedSize()
            .tailedBackground(.basic, layout: layout)
        }
    }

    /// 창 안에서 말풍선의 왼쪽 끝. 그림자 몫으로 오른쪽에 조금 남긴다.
    fileprivate nonisolated static func minX(width: CGFloat, tailX: CGFloat) -> CGFloat {
        min(max(tailX - width / 2, 4), max(4, BubbleLayout.canvasWidth - width - 8))
    }

    /// 굵게·코드 같은 줄 안 마크다운만 꾸민다. 줄바꿈은 그대로 둔다.
    private static func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private extension View {
    /// 꼬리 달린 말풍선 바탕을 깐다. 꼬리와 그림자의 자리도 함께 잡는다.
    @MainActor
    func tailedBackground(_ variant: BubbleVariant, layout: BubbleLayout) -> some View {
        padding(layout.tailEdge == .bottom ? .bottom : .top, BubbleToken.tailHeight)
            .background {
                GeometryReader { proxy in
                    // 창 기준 꼬리 위치를 말풍선 기준으로 바꾼다.
                    let tail = layout.tailX - BubbleView.minX(width: proxy.size.width, tailX: layout.tailX)
                    BubbleBackground(variant: variant, tailX: tail, tailEdge: layout.tailEdge)
                }
            }
            // 그림자가 창 밖으로 잘리지 않을 여백.
            .padding(.bottom, 8)
            .padding(.top, 4)
    }
}

/// 노래 말풍선 위에서 까딱거리는 음표.
private struct SongNote: View {
    let symbol: String
    let delay: TimeInterval

    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(BubbleToken.ink)
            // 어두운 화면에서도 보이도록 음표 둘레에 크림색을 두른다.
            .shadow(color: BubbleToken.bubble, radius: 0.5, x: 1, y: 0)
            .shadow(color: BubbleToken.bubble, radius: 0.5, x: -1, y: 0)
            .shadow(color: BubbleToken.bubble, radius: 0.5, x: 0, y: 1)
            .shadow(color: BubbleToken.bubble, radius: 0.5, x: 0, y: -1)
            .rotationEffect(.degrees(up ? 10 : -10))
            .offset(y: up ? -5 : 3)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(delay)) { up = true }
            }
            .accessibilityHidden(true)
    }
}

/// 생각 말풍선의 방울 꼬리.
private struct ThoughtDot: View {
    let size: CGFloat

    var body: some View {
        Circle().fill(BubbleToken.bubble)
            .overlay { Circle().strokeBorder(BubbleToken.ink, lineWidth: BubbleToken.lineWidth) }
            .frame(width: size, height: size)
    }
}

/// 우사기 말을 한 글자씩 보여 주고, 뜻 보기를 켰으면 다 말한 뒤에 뜻을 작은 괄호로 붙인다.
private struct SpeechLine: View {
    let speech: UsagiSpeech
    let showsMeaning: Bool
    var size: CGFloat = 20
    var centered = false
    var tracking: CGFloat = 0
    /// 이 폭을 넘으면 줄을 바꾼다. nil 이면 한 줄.
    var maxWidth: CGFloat?

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let characters = Array(speech.line)
        let count = min(shown, characters.count)
        VStack(alignment: centered ? .center : .leading, spacing: 4) {
            // 전체 문장의 자리를 미리 잡아 두고 보이는 부분만 늘려서 크기가 흔들리지 않게 한다.
            (Text(String(characters[..<count])) + Text(String(characters[count...])).foregroundStyle(.clear))
                .font(BubbleToken.display(size))
                .tracking(tracking)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineSpacing(4)
                .frame(maxWidth: maxWidth)
                .fixedSize(horizontal: maxWidth == nil, vertical: true)
            if showsMeaning {
                Text("(=\(speech.meaning))")
                    .font(.system(size: max(14, size * 0.7), weight: .semibold))
                    .fixedSize()
                    .opacity(count == characters.count ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("우사기: \(speech.line) (뜻: \(speech.meaning))")
        .task(id: speech) {
            guard !reduceMotion else {
                shown = characters.count
                return
            }
            shown = 0
            if let timing = speech.timing, timing.count == characters.count {
                // 음성에 맞춘 가사: 말을 꺼낸 때로부터 정해진 시각에 글자를 보여 준다 (밀림이 쌓이지 않는다).
                let start = ContinuousClock.now
                for index in characters.indices {
                    try? await Task.sleep(until: start + .seconds(timing[index]), clock: .continuous)
                    if Task.isCancelled { return }
                    shown = index + 1
                }
                return
            }
            for index in 1...max(1, characters.count) {
                try? await Task.sleep(for: BubbleToken.typeInterval)
                if Task.isCancelled { return }
                shown = index
            }
        }
    }
}

/// 말풍선 머리의 작은 아이콘 버튼 (음소거, 닫기).
private struct IconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 선택지 말풍선의 알약 버튼. 주된 답은 잉크 바탕.
private struct ChoiceStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BubbleToken.display(16))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .foregroundStyle(primary ? BubbleToken.bubble : BubbleToken.ink)
            .background { Capsule().fill(primary ? BubbleToken.ink : BubbleToken.bubble) }
            .overlay { Capsule().strokeBorder(BubbleToken.ink, lineWidth: 2) }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// 누르면 살짝 줄어드는 버튼.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

