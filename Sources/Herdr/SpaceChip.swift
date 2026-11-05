import Foundation

/// `herdr api snapshot`의 workspaces 항목 하나. 디코드 경계에서 칩에 필요한
/// 필드만 읽는다(active_tab_id·pane_count 등 나머지 키는 무시).
struct WorkspaceInfo: Codable, Equatable, Identifiable {
    let workspaceId: String
    let label: String
    let number: Int

    var id: String { workspaceId }

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case label
        case number
    }
}

/// `herdr api snapshot`의 tabs 항목 하나. herdr 위계(스페이스 > 탭 > 패널)의
/// 중간 단위로 탭 하나가 패널 여럿을 품는다.
struct TabInfo: Codable, Equatable, Identifiable {
    let tabId: String
    let workspaceId: String
    let label: String
    let number: Int
    let paneCount: Int
    /// agent_status 원문 문자열. 모르는 값도 그대로 보존해 디버깅에 쓴다.
    let agentStatus: String

    var id: String { tabId }

    /// label을 안 정한 탭은 빈 문자열로 오는데, 행에 빈 칸을 보이는 대신
    /// 탭 번호 문자열로 폴백한다.
    var displayName: String {
        label.isEmpty ? String(number) : label
    }

    /// 모르는 agent_status 값은 unknown으로 폴백한다.
    var status: AgentStatus {
        AgentStatus(rawValue: agentStatus) ?? .unknown
    }

    /// 탭마다 키 구성이 가변이라 optional 필드는 전부 기본값으로 읽는다.
    /// tab_id·workspace_id가 없는 항목은 그룹핑·포커스 대상이 될 수 없어
    /// 아예 디코드를 실패시킨다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabId = try container.decode(String.self, forKey: .tabId)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        paneCount = try container.decodeIfPresent(Int.self, forKey: .paneCount) ?? 0
        agentStatus = try container.decodeIfPresent(String.self, forKey: .agentStatus) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case workspaceId = "workspace_id"
        case label
        case number
        case paneCount = "pane_count"
        case agentStatus = "agent_status"
    }
}

/// 탭 하나와 소속 에이전트를 묶은 노치 패널 행 단위. 탭이 패널 여럿을 품어
/// 에이전트도 여럿일 수 있다.
struct TabChip: Equatable, Identifiable {
    let tab: TabInfo
    let agents: [AgentSlot]

    var id: String { tab.tabId }

    var status: AgentStatus { tab.status }

    /// 탭 안 작업요약을 심각도순, 동률은 표시 이름순으로 " · "로 잇는다.
    /// 요약이 하나도 없으면 nil.
    var taskSummary: String? {
        let titles = agents
            .sorted {
                $0.status.sortRank == $1.status.sortRank
                    ? $0.displayName < $1.displayName
                    : $0.status.sortRank < $1.status.sortRank
            }
            .compactMap(\.taskTitle)
        return titles.isEmpty ? nil : titles.joined(separator: " · ")
    }

    /// 탭 안 에이전트 종류 요약. 첫 등장 순 그대로 " · "로 잇고
    /// 에이전트가 없으면 nil.
    var modelLabel: String? {
        var seen: Set<String> = []
        var kinds: [String] = []
        for agent in agents {
            guard let kind = agent.agent, !kind.isEmpty else { continue }
            if seen.insert(kind).inserted { kinds.append(kind) }
        }
        return kinds.isEmpty ? nil : kinds.joined(separator: " · ")
    }
}

/// 워크스페이스 하나와 소속 에이전트 전원(idle 포함)을 묶은 메뉴바 칩 단위.
/// idle뿐인 스페이스는 신호가 없어 isVisible이 거짓이 되고 메뉴바에서 숨겨진다.
struct SpaceChip: Equatable, Identifiable {
    let workspace: WorkspaceInfo
    let agents: [AgentSlot]
    /// 스페이스 안 탭 행들(number순). 탭 키가 없는 snapshot에서는 빈 배열.
    var tabs: [TabChip] = []

    var id: String { workspace.id }

    /// idle을 제외한 신호 에이전트. 심각도(blocked → working → done → unknown)순,
    /// 동률은 표시 이름순. sortRank는 idle(3)이 unknown(4)보다 앞지만 여기엔
    /// idle이 없어 그대로 심각도 표로 쓴다.
    var signalAgents: [AgentSlot] {
        agents
            .filter { $0.status != .idle }
            .sorted {
                $0.status.sortRank == $1.status.sortRank
                    ? $0.displayName < $1.displayName
                    : $0.status.sortRank < $1.status.sortRank
            }
    }

    var idleAgents: [AgentSlot] {
        agents.filter { $0.status == .idle }
    }

    /// 신호가 없으면 Int.max라 정렬에서 맨 뒤로 간다.
    var worstRank: Int {
        signalAgents.first?.status.sortRank ?? Int.max
    }

    /// 스페이스 대표 상태. 심각도순 첫 신호 에이전트의 상태. 신호가 없으면 nil.
    var worstStatus: AgentStatus? {
        signalAgents.first?.status
    }

    var isVisible: Bool { !signalAgents.isEmpty }

    /// 스페이스 안 에이전트 종류 요약. 첫 등장 순 그대로 " · "로 잇고
    /// 개수는 세지 않는다. 종류를 모르면 "?".
    var agentKindsLabel: String {
        let known = agents.compactMap { $0.agent }.filter { !$0.isEmpty }
        var seen: Set<String> = []
        var kinds: [String] = []
        for kind in known where seen.insert(kind).inserted {
            kinds.append(kind)
        }
        guard !kinds.isEmpty else { return "?" }
        return kinds.joined(separator: " · ")
    }

    /// 신호 에이전트의 작업요약을 심각도순으로 " · "로 결합한 한 줄.
    /// 요약이 하나도 없으면 nil.
    var signalTaskSummary: String? {
        let titles = signalAgents.compactMap(\.taskTitle)
        return titles.isEmpty ? nil : titles.joined(separator: " · ")
    }
}
