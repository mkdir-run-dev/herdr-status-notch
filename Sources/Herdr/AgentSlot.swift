import Foundation

/// `herdr agent list` 응답의 agents 항목 하나. JSON 원문은 이 경계에서
/// 끝내고, 뷰는 계산 속성 status만 본다.
struct AgentSlot: Codable, Identifiable, Equatable {
    let name: String
    /// agent_status 원문 문자열. 모르는 값도 그대로 보존해 디버깅에 쓴다.
    let agentStatus: String
    let cwd: String?
    let focused: Bool
    let terminalTitle: String?

    var id: String { name }

    /// 모르는 agent_status 값은 unknown으로 폴백한다.
    var status: AgentStatus {
        AgentStatus(rawValue: agentStatus) ?? .unknown
    }

    enum CodingKeys: String, CodingKey {
        case name
        case agentStatus = "agent_status"
        case cwd
        case focused
        case terminalTitle = "terminal_title"
    }
}

/// `herdr agent list` 응답 래퍼(id/result/agents). 디코드는 HerdrClient에서만.
struct HerdrAgentListResponse: Codable {
    struct Result: Codable {
        let agents: [AgentSlot]
    }
    let id: String
    let result: Result
}
