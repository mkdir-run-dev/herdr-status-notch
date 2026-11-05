import Foundation
import SwiftUI

/// 폴링으로 스페이스·에이전트 상태를 유지하는 단일 상태 원본. 메뉴바 칩,
/// 노치 패널, 드롭다운이 모두 이 객체 하나를 본다.
@MainActor
final class SlotStore: ObservableObject {
    /// 메뉴바에 놓는 칩 상한. 초과분은 overflowCount로만 알린다.
    static let maxChips = 8
    static let pollInterval: TimeInterval = 0.7
    static let notchPanelEnabledKey = "notchPanelEnabled"

    /// 전체 스페이스(잠든 스페이스 포함). 드롭다운 전체 목록용. number순.
    @Published private(set) var spaces: [SpaceChip] = []
    /// 메뉴바에 실제로 보이는 칩. worstRank 오름차순, 동률은 number순, 상한 8.
    @Published private(set) var chips: [SpaceChip] = []
    /// 보이는 스페이스 중 칩 상한을 넘은 개수. 드롭다운에 "+N more"로 표시.
    @Published private(set) var overflowCount = 0
    /// 전체 idle 에이전트 평탄 목록. 드롭다운 대기 섹션용.
    @Published private(set) var idleAgents: [AgentSlot] = []
    @Published private(set) var connection: ConnectionState = .ok
    /// 노치 패널 표시 여부. UserDefaults에 그대로 미러링해 앱 재시작에 유지한다.
    @Published var notchPanelEnabled: Bool {
        didSet {
            guard oldValue != notchPanelEnabled else { return }
            UserDefaults.standard.set(notchPanelEnabled, forKey: Self.notchPanelEnabledKey)
        }
    }

    private let client: HerdrClient
    private var timer: Timer?
    private var pollInFlight = false

    init(client: HerdrClient = HerdrClient()) {
        self.client = client
        // 기존 동작(패널 항상 표시)을 잇도록 기본값은 켠다.
        UserDefaults.standard.register(defaults: [Self.notchPanelEnabledKey: true])
        notchPanelEnabled = UserDefaults.standard.bool(forKey: Self.notchPanelEnabledKey)
    }

    func startPolling() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// herdr 응답이 최대 2초까지 걸릴 수 있어 폴링 간격(0.7초)보다 느리면
    /// 다음 틱을 건너뛴다. 동시에 여러 herdr 프로세스를 띄우지 않기 위해서다.
    private func poll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        // 클라이언트를 명시 캡처해 클로저에 self가 암묵적으로 묻어 들어가는
        // 것을 끊는다(안쪽 [weak self]와 소유권이 어긋나 경고가 난다).
        DispatchQueue.global(qos: .utility).async { [client] in
            let result = client.snapshot()
            Task { @MainActor in
                // Store는 앱 델리게이트가 앱 생명주기 내내 보유해 weak 캡처가
                // 필요 없고, 폴링 한 틱짜리 강참조는 순환을 만들지 않는다.
                self.apply(result)
            }
        }
    }

    private func apply(
        _ result: (agents: [AgentSlot], workspaces: [WorkspaceInfo], tabs: [TabInfo], connection: ConnectionState)
    ) {
        pollInFlight = false
        connection = result.connection

        if result.connection == .offline {
            // 오프라인에서는 마지막 상태를 믿을 수 없어 버린다. 칩이 0이 되면
            // 메뉴바엔 앱 아이콘만 남고 드롭다운 첫 행에 빨간 경고가 뜬다.
            spaces = []
            chips = []
            idleAgents = []
            overflowCount = 0
            return
        }

        let agents = result.agents
        // workspaces가 그룹핑의 진실 원본이라 여기에 없는 workspace_id의
        // 에이전트는 칩에 못 들어간다. idle이면 대기 목록에라도 남는다.
        // 클로저 인자를 이름으로 쓰는 이유는 중첩 클로저의 $0가 안쪽
        // AgentSlot을 가리켜 workspace.id와 비교하게 되는 버그를 막는 것이다.
        spaces = result.workspaces
            .sorted { $0.number < $1.number }
            .map { workspace -> SpaceChip in
                let members = agents.filter { $0.workspaceId == workspace.id }
                let tabs = result.tabs
                    .filter { $0.workspaceId == workspace.id }
                    .sorted { $0.number < $1.number }
                    .map { tab -> TabChip in
                        // tab_id 없는 에이전트는 탭 행에 넣지 않고 스페이스에만 남긴다.
                        let tabMembers = members.filter { $0.tabId == tab.tabId }
                        return TabChip(tab: tab, agents: tabMembers)
                    }
                return SpaceChip(workspace: workspace, agents: members, tabs: tabs)
            }

        let visible = spaces
            .filter { $0.isVisible }
            .sorted {
                $0.worstRank == $1.worstRank
                    ? $0.workspace.number < $1.workspace.number
                    : $0.worstRank < $1.worstRank
            }
        chips = Array(visible.prefix(Self.maxChips))
        overflowCount = max(0, visible.count - Self.maxChips)

        idleAgents = agents
            .filter { $0.status == .idle }
            .sorted { $0.displayName < $1.displayName }
    }

    /// 에이전트 터미널로 포커스를 옮긴다. name 없는 에이전트는 지목할
    /// 대상이 없어 탭해도 아무 일도 하지 않는다.
    func focus(_ slot: AgentSlot) {
        guard let name = slot.name else { return }
        focusAgent(named: name)
    }

    func focusAgent(named name: String) {
        client.focus(agentNamed: name)
    }

    func focusWorkspace(_ id: String) {
        client.focus(workspaceID: id)
    }

    func focusTab(_ id: String) {
        client.focus(tabID: id)
    }
}
