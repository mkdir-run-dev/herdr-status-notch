import AppKit
import SwiftUI

/// herdr가 보고하는 개별 에이전트 상태. 모르는 문자열은 unknown으로 폴백한다.
enum AgentStatus: String, CaseIterable {
    case idle
    case working
    case done
    case blocked
    case unknown

    /// 정렬 우선순위 표. 숫자가 작을수록 패널 위쪽. 기준은 '심각도'가 아니라
    /// '사용자를 기다리는 정도'다 — 지금 입력을 기다리는 blocked, 확인을
    /// 기다리는 done, 아무것도 안 기다리는 working 순. idle은 신호가 아니라
    /// 맨 아래로 보낸다.
    private static let sortRanks: [AgentStatus: Int] = [
        .blocked: 0,
        .done: 1,
        .working: 2,
        .idle: 3,
        .unknown: 4,
    ]

    var sortRank: Int {
        Self.sortRanks[self] ?? Self.sortRanks[.unknown]!
    }

    /// 상태별 색 표. 브랜드 색이 아니라 macOS 시맨틱 색을 그대로 쓴다.
    var color: Color {
        switch self {
        case .idle: .white
        case .working: .blue
        case .done: .green
        case .blocked: .orange
        case .unknown: .secondary
        }
    }

    /// NSStatusItem 비트맵 칩용 색 표. Color.secondary를 NSColor로 변환하면
    /// 시맨틱이 보장되지 않아 AppKit 색을 직접 지정한다.
    var nsColor: NSColor {
        switch self {
        case .idle: .labelColor
        case .working: .systemBlue
        case .done: .systemGreen
        case .blocked: .systemOrange
        case .unknown: .secondaryLabelColor
        }
    }
}

/// herdr CLI 실행 자체의 접속 상태. 개별 에이전트 상태(AgentStatus)와는
/// 섞지 않는 별개 축이다. offline이면 어느 슬롯 정보도 신뢰할 수 없다.
enum ConnectionState {
    case ok
    case offline

    var color: Color {
        switch self {
        case .ok: .green
        case .offline: .red
        }
    }
}
