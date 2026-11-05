import Foundation

/// `herdr api snapshot` 응답의 agents 항목 하나. JSON 원문은 이 경계에서
/// 끝내고, 뷰는 계산 속성 status만 본다.
struct AgentSlot: Codable, Identifiable, Equatable {
    let name: String?
    let agent: String?
    /// agent_status 원문 문자열. 모르는 값도 그대로 보존해 디버깅에 쓴다.
    let agentStatus: String
    let cwd: String?
    let focused: Bool
    let terminalID: String?
    /// 식별자 최종 폴백. 없으면 빈 문자열로 수렴한다.
    let paneID: String
    let terminalTitle: String?
    /// 소속 워크스페이스. 스페이스 칩 그룹핑 키로 쓴다.
    let workspaceId: String?

    /// 실측에서 name 키 자체가 없는 항목이 있었다. 키 구성이 에이전트마다
    /// 가변이라 모든 필드를 decodeIfPresent로 읽는다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        agentStatus = try container.decodeIfPresent(String.self, forKey: .agentStatus) ?? ""
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        focused = try container.decodeIfPresent(Bool.self, forKey: .focused) ?? false
        terminalID = try container.decodeIfPresent(String.self, forKey: .terminalID)
        paneID = try container.decodeIfPresent(String.self, forKey: .paneID) ?? ""
        terminalTitle = try container.decodeIfPresent(String.self, forKey: .terminalTitle)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
    }

    /// name이 없는 항목은 terminal_id로, 그마저 없으면 pane_id로 식별한다.
    var id: String { name ?? terminalID ?? paneID }

    /// name → agent → "unnamed" 순으로 표시 이름을 정한다.
    var displayName: String { name ?? agent ?? "unnamed" }

    /// 모르는 agent_status 값은 unknown으로 폴백한다.
    var status: AgentStatus {
        AgentStatus(rawValue: agentStatus) ?? .unknown
    }

    enum CodingKeys: String, CodingKey {
        case name
        case agent
        case agentStatus = "agent_status"
        case cwd
        case focused
        case terminalID = "terminal_id"
        case paneID = "pane_id"
        case terminalTitle = "terminal_title"
        case workspaceId = "workspace_id"
    }
}

/// `herdr api snapshot` 응답 래퍼(id/result.snapshot). 필요한 경로의
/// agents·workspaces만 모델링하고 나머지 키는 Codable이 무시한다.
/// 디코드는 HerdrClient에서만 한다.
struct HerdrSnapshotResponse: Codable {
    struct Result: Codable {
        struct Snapshot: Codable {
            let agents: [AgentSlot]
            let workspaces: [WorkspaceInfo]
        }
        let snapshot: Snapshot
    }
    let id: String
    let result: Result
}
