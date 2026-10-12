import AppKit
import SwiftUI

// 말풍선 프로토타입(우사기 말풍선 UI 키트)의 토큰을 옮긴 것.
// - 모든 말풍선은 3px 잉크 선으로 닫는다. 흐린 그림자 대신 어긋난 단색 그림자를 쓴다.
// - 모서리 반경을 네 군데 다르게 줘서 손으로 그린 느낌을 낸다.
// - 말풍선 색은 라이트/다크와 상관없이 같다 (크림 바탕에 잉크 글자).
enum BubbleToken {
    static let ink = Color(red: 0x2B / 255, green: 0x1D / 255, blue: 0x14 / 255)
    static let bubble = Color(red: 0xFF / 255, green: 0xFD / 255, blue: 0xF6 / 255)
    static let butter = Color(red: 0xF7 / 255, green: 0xE3 / 255, blue: 0xA1 / 255)
    static let ear = Color(red: 0xF3 / 255, green: 0xA6 / 255, blue: 0xB8 / 255)
    /// 속삭임(시무룩·오류) 말풍선의 바탕.
    static let whisper = Color(red: 0xF6 / 255, green: 0xF4 / 255, blue: 0xEE / 255)
    static let danger = Color(red: 0xA3 / 255, green: 0x26 / 255, blue: 0x1F / 255)
    static let focus = Color(red: 0x1B / 255, green: 0x5F / 255, blue: 0xD1 / 255)

    static let lineWidth: CGFloat = 3
    static let shadowOffset = CGSize(width: 4, height: 5)
    static let tailHalfWidth: CGFloat = 12
    static let tailHeight: CGFloat = 12

    /// 등장 240ms, 퇴장 160ms.
    static let enter: TimeInterval = 0.24
    static let exit: TimeInterval = 0.16
    /// 우사기 말은 한 글자씩 나타난다.
    static let typeInterval: Duration = .milliseconds(40)
    /// 다 말하고 저절로 닫힐 때까지.
    static let autoHide: TimeInterval = 4

    /// 우사기 말과 대사에 쓰는 둥근 글꼴 (Jua). 등록에 실패하면 시스템 둥근 글꼴로 대신한다.
    @MainActor
    static func display(_ size: CGFloat) -> Font {
        BubbleFont.isRegistered ? .custom(BubbleFont.name, size: size) : .system(size: size, weight: .semibold, design: .rounded)
    }
}

enum BubbleFont {
    static let name = "Jua-Regular"
    @MainActor private(set) static var isRegistered = false

    /// 앱에 들어 있는 글꼴 파일을 이 프로세스에서만 쓸 수 있게 등록한다.
    @MainActor
    static func register() {
        guard let url = PetLocator.fontURL() else { return }
        isRegistered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// 말풍선 외곽: 모서리마다 반경이 다른 몸통에 꼬리가 하나 붙는다.
struct BubbleShape: Shape {
    enum TailEdge { case bottom, top }

    /// 꼬리 끝의 가로 위치 (말풍선 왼쪽 끝 기준). nil 이면 꼬리가 없다.
    var tailX: CGFloat?
    var tailEdge: TailEdge = .bottom

    /// 모서리 반경 (왼쪽 위부터 시계 방향, 가로/세로).
    var radii: [CGSize] = BubbleShape.wobbly

    /// CSS `border-radius: 26px 32px 28px 34px / 30px 26px 32px 28px`.
    static let wobbly: [CGSize] = [
        CGSize(width: 26, height: 30), CGSize(width: 32, height: 26),
        CGSize(width: 28, height: 32), CGSize(width: 34, height: 28),
    ]
    /// 스티커: `14px 18px 12px 20px`.
    static let sticker: [CGSize] = [14, 18, 12, 20].map { CGSize(width: $0, height: $0) }
    /// 알림: 네 모서리 모두 18px.
    static let notice: [CGSize] = Array(repeating: CGSize(width: 18, height: 18), count: 4)

    /// 꼬리를 뺀 몸통 영역.
    static func body(in rect: CGRect, tailEdge: TailEdge, hasTail: Bool) -> CGRect {
        guard hasTail else { return rect }
        var body = rect
        body.size.height -= BubbleToken.tailHeight
        if tailEdge == .top { body.origin.y += BubbleToken.tailHeight }
        return body
    }

    func path(in rect: CGRect) -> Path {
        let body = Self.body(in: rect, tailEdge: tailEdge, hasTail: tailX != nil)
        // 작은 말풍선에서는 반경이 겹치지 않게 줄인다.
        let scale = min(1, body.width / 68, body.height / 64)
        let r = radii.map { CGSize(width: $0.width * scale, height: $0.height * scale) }
        let half = BubbleToken.tailHalfWidth
        // 꼬리가 둥근 모서리에 걸치지 않게 한다.
        let tail = tailX.map { min(max($0, body.minX + r[3].width + half), body.maxX - r[2].width - half) }
        // 원의 4분의 1을 3차 곡선으로 그릴 때의 조절점 비율.
        let k: CGFloat = 0.5523

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r[0].width, y: body.minY))
        if let tail, tailEdge == .top {
            path.addLine(to: CGPoint(x: tail - half, y: body.minY))
            path.addLine(to: CGPoint(x: tail, y: body.minY - BubbleToken.tailHeight))
            path.addLine(to: CGPoint(x: tail + half, y: body.minY))
        }
        path.addLine(to: CGPoint(x: body.maxX - r[1].width, y: body.minY))
        path.addCurve(
            to: CGPoint(x: body.maxX, y: body.minY + r[1].height),
            control1: CGPoint(x: body.maxX - r[1].width * (1 - k), y: body.minY),
            control2: CGPoint(x: body.maxX, y: body.minY + r[1].height * (1 - k))
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r[2].height))
        path.addCurve(
            to: CGPoint(x: body.maxX - r[2].width, y: body.maxY),
            control1: CGPoint(x: body.maxX, y: body.maxY - r[2].height * (1 - k)),
            control2: CGPoint(x: body.maxX - r[2].width * (1 - k), y: body.maxY)
        )
        if let tail, tailEdge == .bottom {
            path.addLine(to: CGPoint(x: tail + half, y: body.maxY))
            path.addLine(to: CGPoint(x: tail, y: body.maxY + BubbleToken.tailHeight))
            path.addLine(to: CGPoint(x: tail - half, y: body.maxY))
        }
        path.addLine(to: CGPoint(x: body.minX + r[3].width, y: body.maxY))
        path.addCurve(
            to: CGPoint(x: body.minX, y: body.maxY - r[3].height),
            control1: CGPoint(x: body.minX + r[3].width * (1 - k), y: body.maxY),
            control2: CGPoint(x: body.minX, y: body.maxY - r[3].height * (1 - k))
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r[0].height))
        path.addCurve(
            to: CGPoint(x: body.minX + r[0].width, y: body.minY),
            control1: CGPoint(x: body.minX, y: body.minY + r[0].height * (1 - k)),
            control2: CGPoint(x: body.minX + r[0].width * (1 - k), y: body.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// 꼬리 달린 말풍선의 종류 (프로토타입의 이름). 외침과 생각은 모양이 달라 `BurstShape` · `CloudShape` 로 따로 그린다.
enum BubbleVariant {
    /// 평상시 대사.
    case basic
    /// 인사와 첫 등장: 버터색 바탕에 우사기 귀가 솟는다.
    case ears
    /// 시무룩할 때: 점선에 그림자 없음.
    case whisper
    /// 한두 글자 반응: 기울어진 분홍 딱지.
    case sticker
    /// 리마인더: 머리띠가 붙는 반듯한 모서리.
    case notice

    var fill: Color {
        switch self {
        case .basic, .notice: BubbleToken.bubble
        case .ears: BubbleToken.butter
        case .whisper: BubbleToken.whisper
        case .sticker: BubbleToken.ear
        }
    }

    var radii: [CGSize] {
        switch self {
        case .sticker: BubbleShape.sticker
        case .notice: BubbleShape.notice
        default: BubbleShape.wobbly
        }
    }

    var stroke: StrokeStyle {
        switch self {
        case .whisper: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [6, 4])
        case .sticker: StrokeStyle(lineWidth: 4, lineJoin: .round)
        default: StrokeStyle(lineWidth: BubbleToken.lineWidth, lineJoin: .round)
        }
    }
}

/// 말풍선 바탕: 어긋난 그림자 → 귀 → 몸통과 외곽선.
struct BubbleBackground: View {
    let variant: BubbleVariant
    var tailX: CGFloat?
    var tailEdge: BubbleShape.TailEdge = .bottom

    var body: some View {
        let shape = BubbleShape(tailX: tailX, tailEdge: tailEdge, radii: variant.radii)
        ZStack(alignment: .topLeading) {
            if variant != .whisper {
                shape.fill(BubbleToken.ink.opacity(0.2))
                    .offset(BubbleToken.shadowOffset)
            }
            if variant == .ears {
                HStack(spacing: 6) {
                    BubbleEar().rotationEffect(.degrees(-8), anchor: .bottom)
                    BubbleEar().rotationEffect(.degrees(7), anchor: .bottom)
                }
                .offset(x: 26, y: -30 + (tailEdge == .top && tailX != nil ? BubbleToken.tailHeight : 0))
            }
            shape.fill(variant.fill)
            shape.stroke(BubbleToken.ink, style: variant.stroke)
        }
        .accessibilityHidden(true)
    }
}

/// 노래 말풍선의 외곽: 위아래 테두리가 가락처럼 물결치고 아래에 꼬리가 붙는다.
struct SongShape: Shape {
    /// 꼬리 끝의 가로 위치 (말풍선 왼쪽 끝 기준).
    var tailX: CGFloat
    var tailEdge: BubbleShape.TailEdge = .bottom

    private static let radius: CGFloat = 22
    private static let amplitude: CGFloat = 3.5
    private static let wavelength: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let body = BubbleShape.body(in: rect, tailEdge: tailEdge, hasTail: true)
        let r = min(Self.radius, body.width / 2, body.height / 2)
        let half = BubbleToken.tailHalfWidth
        let tail = min(max(tailX, body.minX + r + half), body.maxX - r - half)
        let left = body.minX + r
        let right = body.maxX - r
        // 물결이 양 끝에서 0 으로 끝나도록 칸 수를 맞춘다.
        let waves = max(1, ((right - left) / Self.wavelength).rounded())
        func wave(_ x: CGFloat) -> CGFloat { Self.amplitude * sin((x - left) / (right - left) * waves * 2 * .pi) }

        /// 한쪽 가로 테두리를 그린다. 꼬리가 붙는 쪽은 꼬리 둘레를 평평하게 두고 꼬리를 낸다.
        func edge(_ path: inout Path, y: CGFloat, from start: CGFloat, to end: CGFloat, tailTip: CGFloat?) {
            let step: CGFloat = start < end ? 2 : -2
            var x = start
            var tailDrawn = false
            while (step > 0 && x < end) || (step < 0 && x > end) {
                if let tailTip, !tailDrawn, abs(x - tail) <= half {
                    // 꼬리: 들어가는 쪽 → 끝 → 나가는 쪽.
                    path.addLine(to: CGPoint(x: tail - half * (step > 0 ? 1 : -1), y: y))
                    path.addLine(to: CGPoint(x: tail, y: tailTip))
                    path.addLine(to: CGPoint(x: tail + half * (step > 0 ? 1 : -1), y: y))
                    x = tail + half * (step > 0 ? 1 : -1)
                    tailDrawn = true
                } else {
                    path.addLine(to: CGPoint(x: x, y: y + wave(x)))
                    x += step
                }
            }
            path.addLine(to: CGPoint(x: end, y: y))
        }

        var path = Path()
        path.move(to: CGPoint(x: left, y: body.minY))
        edge(&path, y: body.minY, from: left, to: right, tailTip: tailEdge == .top ? body.minY - BubbleToken.tailHeight : nil)
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + r), control: CGPoint(x: body.maxX, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addQuadCurve(to: CGPoint(x: right, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        edge(&path, y: body.maxY, from: right, to: left, tailTip: tailEdge == .bottom ? body.maxY + BubbleToken.tailHeight : nil)
        path.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - r), control: CGPoint(x: body.minX, y: body.maxY))
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addQuadCurve(to: CGPoint(x: left, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        path.closeSubpath()
        return path
    }
}

/// 외침 말풍선의 가시 돋친 외곽. 프로토타입의 BURST_D 를 그대로 옮겼다 (100×100 격자를 영역에 맞춰 늘림).
struct BurstShape: Shape {
    private static let jitter: [CGFloat] = [0, 2, -1, 3, 0, -2, 1, 2, -1, 0, 3, -2, 1, 0, -1, 2]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<32 {
            let radius: CGFloat = index.isMultiple(of: 2)
                ? 49 - abs(Self.jitter[(index / 2) % 16])
                : 39 + Self.jitter[((index - 1) / 2) % 16] * 0.5
            let point = BlobGeometry.point(angle: CGFloat(index) * .pi / 16 + 0.1, radius: radius, exponent: 0.5, in: rect)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// 생각 말풍선의 구름 외곽. 프로토타입의 CLOUD_D.
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bumps = 11
        let step = 2 * CGFloat.pi / CGFloat(bumps)
        var path = Path()
        path.move(to: BlobGeometry.point(angle: 0, radius: 42, exponent: 0.62, in: rect))
        for index in 0..<bumps {
            path.addQuadCurve(
                to: BlobGeometry.point(angle: CGFloat(index + 1) * step, radius: 42, exponent: 0.62, in: rect),
                control: BlobGeometry.point(angle: (CGFloat(index) + 0.5) * step, radius: 57, exponent: 0.62, in: rect)
            )
        }
        path.closeSubpath()
        return path
    }
}

private enum BlobGeometry {
    /// 원을 네모에 가깝게 부풀린 곡선 위의 점 (100×100 격자 기준)을 `rect` 로 옮긴다.
    static func point(angle: CGFloat, radius: CGFloat, exponent: CGFloat, in rect: CGRect) -> CGPoint {
        func squash(_ value: CGFloat) -> CGFloat { (value < 0 ? -1 : 1) * pow(abs(value), exponent) }
        let x = 50 + radius * squash(cos(angle))
        let y = 50 + radius * squash(sin(angle))
        return CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100)
    }
}

/// 귀 풍선의 귀 한 짝: 분홍 속에 버터색 띠, 잉크 외곽선.
private struct BubbleEar: View {
    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 8.5, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 8.5, style: .continuous
        )
        shape.fill(BubbleToken.ear)
            .overlay { shape.inset(by: 4.5).stroke(BubbleToken.butter, lineWidth: 3) }
            .overlay { shape.inset(by: 1.5).stroke(BubbleToken.ink, lineWidth: BubbleToken.lineWidth) }
            .frame(width: 17, height: 42)
    }
}
