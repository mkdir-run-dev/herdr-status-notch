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

/// 워크스페이스 하나와 소속 에이전트 전원(idle 포함)을 묶은 메뉴바 칩 단위.
/// idle뿐인 스페이스는 신호가 없어 isVisible이 거짓이 되고 메뉴바에서 숨겨진다.
struct SpaceChip: Equatable, Identifiable {
    let workspace: WorkspaceInfo
    let agents: [AgentSlot]
    /// 신호가 끊긴 지 유예 시간 안이라는 표시. SlotStore의 판정 결과를
    /// 뷰까지 전달하기만 한다. let+기본값은 memberwise init에서 파라미터가
    /// 빠져 true 칩을 못 만들므로 var 기본값으로 노출한다.
    var inGrace: Bool = false

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
