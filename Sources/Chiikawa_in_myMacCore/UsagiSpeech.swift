import Foundation

/// 우사기의 말. 우사기는 사람 말을 하지 않으므로 말풍선에는 우사기 말을 크게 쓰고, 뜻은 켰을 때만 작은 괄호로 덧붙인다.
/// 말과 뜻은 말풍선 프로토타입의 "우사기 말 사전"을 따랐다. 사전에 없는 말은 따로 적었다.
public struct UsagiSpeech: Equatable, Sendable {
    public let line: String
    public let meaning: String
    /// 이 말을 할 때 재생할 음성 파일 (`Resources/Voices/` 안, 확장자 포함). 없으면 소리 없이 말한다.
    public let voice: String?
    /// 글자마다 나타나는 시각(음성 시작 기준, 초). 있으면 일정한 빠르기 대신 이 시각에 맞춰 한 글자씩 보여 준다.
    public let timing: [TimeInterval]?
    /// 이 말을 하는 동안 보여 줄 특수 모션의 이름 (펫 폴더의 `<이름>.json`). 음성이 있는 말에는 모두 붙인다.
    public let motion: String?

    public init(_ line: String, _ meaning: String, voice: String? = nil, motion: String? = nil) {
        self.line = line
        self.meaning = meaning
        self.voice = voice
        self.motion = motion
        timing = nil
    }

    /// 음성에 맞춘 가사: 조각마다 나타나는 시각을 준다. 조각 안의 글자는 함께 나온다.
    public init(lyrics: [(text: String, at: TimeInterval)], meaning: String, voice: String) {
        line = lyrics.map(\.text).joined()
        self.meaning = meaning
        self.voice = voice
        motion = "song"
        timing = lyrics.flatMap { piece in Array(repeating: piece.at, count: piece.text.count) }
    }

    /// 앱을 켰을 때.
    public static let greeting = UsagiSpeech("미야아아", "어서와! 환영해!")
    /// 질문을 AI 에게 보냈을 때.
    public static let sent = UsagiSpeech("우나!", "가자!", voice: "chiikawa-usagi---una.mp3", motion: "jump")
    /// AI 의 답이 왔을 때.
    public static let answered = UsagiSpeech("야하!", "찾았다! / 그렇지!", voice: "chiikawa-usagi---yaha.mp3", motion: "flip")
    public static let failed = UsagiSpeech("후와~망…", "망했다… / 큰일났다…")
    /// 진행 중인 질문을 멈췄을 때.
    public static let cancelled = UsagiSpeech("하?", "뭐라는 거야!?", voice: "chiikawa-usagi---huh.mp3", motion: "arms")
    /// 세션을 초기화했을 때.
    public static let reset = UsagiSpeech("푸루", "알겠어!")
    /// 작업 폴더를 바꿨을 때.
    public static let moved = UsagiSpeech("우라우라", "가보자고!")
}

/// 우사기의 혼잣말. 말풍선을 닫아 둔 동안 가끔 혼자 중얼거린다.
public struct UsagiMumble: Equatable, Sendable {
    /// 말풍선 종류 (프로토타입의 이름).
    public enum Style: Equatable, Sendable {
        /// 기본: 평상시 대사. 혼잣말에는 쓰지 않고 사전에서 들어 볼 때만 쓴다.
        case basic
        /// 귀 풍선: 인사. 사전에서 들어 볼 때만 쓴다.
        case ears
        /// 외침: 가시 돋친 모양으로 튕기듯 튀어나온다.
        case shout
        /// 생각: 구름 모양에 방울 꼬리.
        case thought
        /// 스티커: 기울어진 분홍 딱지.
        case sticker
        /// 속삭임: 점선에 작은 글씨.
        case whisper
        /// 알림: 머리띠와 닫기 버튼.
        case notice
        /// 선택지: 사람이 누르는 버튼이 붙는다.
        case choice
        /// 노래: 물결치는 테두리에 음표가 떠다니고, 가사가 노래 빠르기에 맞춰 나온다. (프로토타입에 없는 종류)
        case song
    }

    public let speech: UsagiSpeech
    public let style: Style
    /// 말하는 동안의 펫 동작.
    public let animation: PetAnimation
    /// 이 말을 하는 시간대(시, 0~23). nil 이면 아무 때나.
    public let hours: Set<Int>?
    /// 평소 동작 대신 보여 줄 특수 모션의 이름. 말에 붙은 것(`speech.motion`)이 있으면 그것, 없으면 이 혼잣말에만 쓰는 것.
    /// 없거나 읽지 못하면 `animation` 을 쓴다.
    public let motion: String?

    public init(_ speech: UsagiSpeech, style: Style, animation: PetAnimation, hours: Set<Int>? = nil, motion: String? = nil) {
        self.speech = speech
        self.style = style
        self.animation = animation
        self.hours = hours
        self.motion = speech.motion ?? motion
    }

    /// 끼니때.
    static let mealHours: Set<Int> = [11, 12, 13, 18, 19]
    /// 잘 시간.
    static let sleepHours: Set<Int> = [23, 0, 1, 2, 3, 4, 5]

    // 음성 파일에서 온 말. 사전에 없어서 파일 이름의 소리를 한글로 옮겼고, 뜻은 짐작해서 붙였다.
    /// 노래의 마지막 외침만 따로. 음성은 노래 파일의 그 부분을 잘라 낸 것이고, 동작도 노래의 마무리(다리 꼬기)다.
    static let burit = UsagiSpeech("부릿!", "으쌰!", voice: "usagi---burit.mp3", motion: "burit")
    static let puriyaha = UsagiSpeech("푸리야하~ 이하!", "신난다!", voice: "chiikawa-usagi---puriyaha-yiha.mp3", motion: "jump")
    /// 노래. 시각은 음성 파일의 소리가 시작되는 지점을 분석해 맞췄다 (소리 덩어리의 시작과 그 안의 음절 경계).
    /// 마지막 "부릿!"은 앞 소절이 끝나고 1.7초쯤 뒤, 원작에서 얼굴이 크게 잡힐 때 나온다.
    static let song = UsagiSpeech(
        lyrics: [
            ("우 ", 0.40),
            ("우", 1.18), ("나", 1.55), ("나, ", 1.93),
            ("우", 2.33), ("나", 2.50), ("~ ", 2.75),
            ("우", 3.36), ("나", 3.60), ("나 ", 3.90),
            ("야", 4.37), ("하 ", 4.52),
            ("야", 4.75), ("하", 4.88), ("~ ", 5.05),
            ("부", songFinaleTime), ("릿", 6.93), ("!", 7.00),
        ],
        meaning: "흥얼흥얼~ 노래", voice: "usagi---u-una-na-ya-ha.mp3"
    )
    /// 노래의 마지막 외침 "부릿!"이 나오는 시각.
    public static let songFinaleTime: TimeInterval = 6.85

    /// 펫을 눌러 말풍선을 열 때 먼저 하는 말. 음성이 있는 말만 두고, 혼잣말과 같은 특수 말풍선으로 보여 준 뒤에 대화 말풍선을 연다.
    public static let openers: [UsagiMumble] = [
        UsagiMumble(.sent, style: .shout, animation: .jumping),
        UsagiMumble(.answered, style: .shout, animation: .jumping),
        UsagiMumble(.cancelled, style: .sticker, animation: .turnRight),
        UsagiMumble(burit, style: .sticker, animation: .turnLeft),
        UsagiMumble(puriyaha, style: .shout, animation: .jumping),
    ]

    /// 방금 한 말과 다른 여는 말을 하나 고른다.
    public static func opener(after previous: UsagiSpeech?) -> UsagiMumble {
        openers.filter { $0.speech.line != previous?.line }.randomElement() ?? openers[0]
    }

    public static let all: [UsagiMumble] = [
        UsagiMumble(UsagiSpeech("우라라라라!!", "기분 좋아!!"), style: .shout, animation: .jumping),
        UsagiMumble(puriyaha, style: .shout, animation: .jumping),
        UsagiMumble(UsagiSpeech("우~이~", "모르겠어.."), style: .thought, animation: .review, motion: "flip"),
        UsagiMumble(UsagiSpeech("후웅?", "그래? / 그런가?"), style: .thought, animation: .review),
        UsagiMumble(song, style: .song, animation: .waiting),
        UsagiMumble(.cancelled, style: .sticker, animation: .turnRight),
        UsagiMumble(burit, style: .sticker, animation: .turnLeft),
        UsagiMumble(UsagiSpeech("푸루루루", "신나 / 행복해"), style: .sticker, animation: .waving),
        UsagiMumble(UsagiSpeech("우~라~", "엄청 크다! / 대박!"), style: .sticker, animation: .waving, motion: "shades"),
        UsagiMumble(UsagiSpeech("이~", "이거 봐봐!"), style: .shout, animation: .jumping, motion: "glow"),
        UsagiMumble(UsagiSpeech("구우구우~", "드르렁 쿨쿨"), style: .whisper, animation: .idle, hours: sleepHours),
        UsagiMumble(UsagiSpeech("푸루야", "같이 하자! / 힘내!"), style: .notice, animation: .waiting),
        UsagiMumble(UsagiSpeech("쥬르리", "츄릅… 배고파…"), style: .choice, animation: .running, hours: mealHours),
    ]

    /// 지금 시각에 할 수 있는 혼잣말.
    public static func candidates(hour: Int) -> [UsagiMumble] {
        // 잘 시간에는 코 고는 소리만 낸다.
        if sleepHours.contains(hour) { return all.filter { $0.hours == sleepHours } }
        return all.filter { $0.hours?.contains(hour) ?? true }
    }

    /// 선택지에서 "간식 주기"를 눌렀을 때.
    public static let treatAccepted = UsagiMumble(UsagiSpeech("우라라라라!!", "기분 좋아!!"), style: .shout, animation: .jumping)
    /// 선택지에서 "나중에"를 눌렀을 때.
    public static let treatDeclined = UsagiMumble(UsagiSpeech("후와~망…", "망했다… / 큰일났다…"), style: .whisper, animation: .failed)
}
