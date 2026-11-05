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
    /// 소속 탭. 탭 행 그룹핑 키로 쓰는데, 없는 에이전트도 있어 옵셔널이다.
    let tabId: String?
    /// 메타데이터가 심어진 pane에만 존재하는 공식 작업명. 키 자체가 없는
    /// snapshot도 있어 통째로 옵셔널로 읽는다.
    let tokens: Tokens?

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
        tabId = try container.decodeIfPresent(String.self, forKey: .tabId)
        tokens = try container.decodeIfPresent(Tokens.self, forKey: .tokens)
    }

    /// name이 없는 항목은 terminal_id로, 그마저 없으면 pane_id로 식별한다.
    var id: String { name ?? terminalID ?? paneID }

    /// name → agent → "unnamed" 순으로 표시 이름을 정한다.
    var displayName: String { name ?? agent ?? "unnamed" }

    /// 모르는 agent_status 값은 unknown으로 폴백한다.
    var status: AgentStatus {
        AgentStatus(rawValue: agentStatus) ?? .unknown
    }

    /// 메타데이터의 summary가 공식 작업명이라 우선하고, 없는 에이전트는
    /// 제목 휴리스틱으로 폴백한다.
    var taskTitle: String? {
        if let summary = tokens?.summary?
            .trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        return heuristicTaskTitle
    }

    /// 터미널 제목에서 상태 글리프(✳ ◑ ◐ 등)를 떼어낸 작업명. 도구 이름
    /// 뿐이거나 비어 있으면 nil. herdr에 작업 설명 필드가 없어 제목에서
    /// 얻는 휴리스틱이다.
    private var heuristicTaskTitle: String? {
        let stripped = String(
            (terminalTitle ?? "").drop { !$0.isLetter && !$0.isNumber }
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        let lowered = stripped.lowercased()
        if Self.toolNameTitles.contains(lowered) { return nil }
        if let agent, lowered == agent.lowercased() { return nil }
        return stripped
    }

    /// 제목이 이 값뿐이면 작업 정보가 없어 taskTitle에서 걸러진다.
    private static let toolNameTitles: Set<String> = [
        "claude code", "codex", "gemini", "kimi", "opencode", "cursor",
    ]

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
        case tabId = "tab_id"
        case tokens
    }

    /// panes 항목의 tokens 객체. summary는 메타데이터가 심어졌을 때만
    /// 나타나므로 옵셔널로 읽는다.
    struct Tokens: Codable, Equatable {
        let summary: String?
    }
}

/// `herdr api snapshot` 응답 래퍼(id/result.snapshot). 필요한 경로의
/// agents·workspaces·tabs만 모델링하고 나머지 키는 Codable이 무시한다.
/// tabs는 오래된 herdr 응답엔 키 자체가 없을 수 있어 옵셔널로 읽는다.
/// 디코드는 HerdrClient에서만 한다.
struct HerdrSnapshotResponse: Codable {
    struct Result: Codable {
        struct Snapshot: Codable {
            let agents: [AgentSlot]
            let workspaces: [WorkspaceInfo]
            let tabs: [TabInfo]?
        }
        let snapshot: Snapshot
    }
    let id: String
    let result: Result
}
