import Foundation

/// 스프라이트 시트의 줄. 한 줄이 동작 하나이고 칸은 가로 8개다 (Codex Pets 형식).
/// 각 줄의 설명은 우사기 시트에서 그 줄이 실제로 보여 주는 모습이다.
public enum PetAnimation: Int, CaseIterable, Sendable {
    /// 엎드려 쉬기
    case idle = 0
    /// 프로펠러 모자로 날기. 끌어서 옮길 때 쓰고, 이름과 반대로 **왼쪽**으로 끌 때 보여 준다.
    case runningRight
    /// 프로펠러 모자로 날기. **오른쪽**으로 끌 때 보여 준다.
    case runningLeft
    /// 신나서 손 모으기
    case waving
    /// 프로펠러 모자로 날기
    case jumping
    /// 털모자 쓰고 거꾸로 서기
    case failed
    /// 노란 응원 술 흔들기
    case waiting
    /// 엎드려 뒤돌아보기 (원래는 조르기였고, 사용자가 준 그림으로 바꿨다)
    case running
    /// 옆으로 서서 꼬리 흔들기
    case review
    /// 오른쪽 돌기. Codex Pets 문서의 9줄에는 없는 추가 줄.
    case turnRight
    /// 왼쪽 돌기
    case turnLeft

    /// Codex Pets 형식에서 이 줄을 부르는 이름. `pet.json` 의 `motions` 가 이 이름으로 줄을 다른 동작으로 바꾼다.
    public var name: String {
        switch self {
        case .idle: "idle"
        case .runningRight: "running-right"
        case .runningLeft: "running-left"
        case .waving: "waving"
        case .jumping: "jumping"
        case .failed: "failed"
        case .waiting: "waiting"
        case .running: "running"
        case .review: "review"
        case .turnRight: "turn-right"
        case .turnLeft: "turn-left"
        }
    }

    public static let columns = 8
    /// 시트에 있을 수 있는 줄 수. 9줄짜리(기존 Codex 형식) 시트도 받는다.
    public static let supportedRowCounts = [9, 11]

    /// 한 칸을 보여 주는 시간(초).
    public var frameDuration: TimeInterval { 0.125 }

    /// 한 번 보여 주고 지금 상태의 동작으로 돌아가는지.
    public var playsOnce: Bool {
        switch self {
        case .waving, .jumping, .turnRight, .turnLeft: true
        default: false
        }
    }
}

/// 펫이 지금 알리는 상태. 동작으로 바뀐다.
public enum PetMood: Equatable, Sendable {
    case idle
    /// 말풍선을 열고 사용자의 말을 기다린다.
    case listening
    /// AI 가 답을 만들고 있다.
    case working
    case failed

    public var animation: PetAnimation {
        switch self {
        case .idle: .idle
        // 시트의 8번째 줄. 원래의 조르기 그림은 사용자 요청으로 엎드려 뒤돌아보는 그림으로 바꿨다.
        case .listening: .running
        case .working: .review
        case .failed: .failed
        }
    }
}
