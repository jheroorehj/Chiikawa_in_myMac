import Foundation

/// 우사기가 하는 모든 말을 쓰는 때별로 묶은 사전. 앱의 "우사기 말 모두 보기"가 이것을 보여 준다.
public enum UsagiPhrasebook {
    public struct Entry: Equatable, Sendable, Identifiable {
        /// 말과, 눌러서 들어 볼 때 쓸 말풍선·동작.
        public let mumble: UsagiMumble
        /// 이 말을 하는 때.
        public let occasion: String
        public let id: String

        init(_ mumble: UsagiMumble, _ occasion: String, section: String) {
            self.mumble = mumble
            self.occasion = occasion
            id = "\(section)/\(mumble.speech.line)/\(occasion)"
        }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public let title: String
        public let entries: [Entry]
        public var id: String { title }
    }

    public static let sections: [Section] = [
        section("대화할 때", [
            (UsagiMumble(.greeting, style: .ears, animation: .waving), "앱을 켰을 때"),
            (UsagiMumble(.sent, style: .basic, animation: .review), "질문을 보냈을 때"),
            (UsagiMumble(.answered, style: .basic, animation: .jumping), "답이 왔을 때"),
            (UsagiMumble(.failed, style: .whisper, animation: .failed), "오류가 났을 때"),
            (UsagiMumble(.cancelled, style: .basic, animation: .running), "멈췄을 때"),
            (UsagiMumble(.reset, style: .basic, animation: .running), "세션을 초기화했을 때"),
            (UsagiMumble(.moved, style: .basic, animation: .running), "작업 폴더를 바꿨을 때"),
        ]),
        section("말풍선을 열 때", UsagiMumble.openers.map { ($0, "열 때마다 하나") }),
        section("혼잣말", UsagiMumble.all.map { ($0, occasion(of: $0)) } + [
            (UsagiMumble.treatAccepted, "\"간식 주기\"를 눌렀을 때"),
            (UsagiMumble.treatDeclined, "\"나중에\"를 눌렀을 때"),
        ]),
    ]

    /// 사전에 실린 모든 말.
    public static var speeches: [UsagiSpeech] {
        sections.flatMap { $0.entries.map(\.mumble.speech) }
    }

    private static func section(_ title: String, _ entries: [(UsagiMumble, String)]) -> Section {
        Section(title: title, entries: entries.map { Entry($0.0, $0.1, section: title) })
    }

    private static func occasion(of mumble: UsagiMumble) -> String {
        switch mumble.hours {
        case UsagiMumble.sleepHours: "밤 11시 ~ 새벽 5시"
        case UsagiMumble.mealHours: "끼니때"
        default: "아무 때나"
        }
    }
}
