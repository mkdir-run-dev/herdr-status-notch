import Foundation
import os
import SwiftUI

/// 폴링으로 스페이스·에이전트 상태를 유지하는 단일 상태 원본. 메뉴바 칩,
/// 노치 패널, 드롭다운이 모두 이 객체 하나를 본다.
@MainActor
final class SlotStore: ObservableObject {
    /// 메뉴바에 놓는 칩 상한. 초과분은 overflowCount로만 알린다.
    static let maxChips = 8
    /// 칩 폭 합계 예산(pt). 개수 상한과 병용해 어느 쪽이든 먼저 차면
    /// 그 칩부터는 드롭다운 스페이스 지도로 넘긴다. 라벨이 길어 개수만
    /// 세면 메뉴바를 물리적으로 넘칠 수 있어 폭도 잰다.
    static let maxChipsWidth: CGFloat = 480
    static let pollInterval: TimeInterval = 0.7
    static let notchPanelEnabledKey = "notchPanelEnabled"
    static let notchPanelWidthKey = "notchPanelWidth"
    static let appLanguageKey = "appLanguage"
    static let herdrModeKey = "herdrMode"
    /// 노치 패널 기본 폭. UserDefaults 기본값 등록과 첫 그리기에 쓴다.
    static let defaultPanelWidth: CGFloat = 320
    /// 반대 모드 실행 감지 주기. 정상일 때는 여유 있게, 오프라인이면 빠르게.
    static let otherModeProbeInterval: TimeInterval = 10
    static let otherModeProbeIntervalOffline: TimeInterval = 2

    private static let logger = Logger(subsystem: "local.herdr.statusnotch", category: "store")

    /// 전체 스페이스(잠든 스페이스 포함). 드롭다운 전체 목록용. number순.
    @Published private(set) var spaces: [SpaceChip] = []
    /// 메뉴바에 실제로 보이는 칩. worstRank 오름차순, 동률은 number순, 상한 8.
    @Published private(set) var chips: [SpaceChip] = []
    /// 보이는 스페이스 중 칩 상한을 넘은 개수. 드롭다운에 "+N more"로 표시한다.
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
    /// 노치 패널 폭. 리사이즈 제스처가 갱신하고 UserDefaults에 미러링해
    /// 앱 재시작에 유지한다.
    @Published var notchPanelWidth: CGFloat {
        didSet {
            guard oldValue != notchPanelWidth else { return }
            UserDefaults.standard.set(Double(notchPanelWidth), forKey: Self.notchPanelWidthKey)
        }
    }
    /// 인터페이스 언어. 바꾸면 폴링 없이 즉시 뷰가 다시 그려진다.
    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.appLanguageKey)
        }
    }
    /// 지켜보는 herdr 실행 형태. 드롭다운에서 고르고 재시작에 유지한다.
    @Published var mode: HerdrMode {
        didSet {
            modeDidChange(from: oldValue)
        }
    }
    /// 반대 모드가 실행 중임을 감지해 세션당 한 번만 띄우는 전환 제안. nil이면 팝업 없음.
    @Published private(set) var suggestedModeSwitch: HerdrMode?

    private let backends: [HerdrMode: any HerdrBackend]
    private let gitResolver = GitBranchResolver()
    private var timer: Timer?
    private var pollInFlight = false
    /// 모드를 바꿀 때마다 올라간다. 이전 모드의 늦은 응답이 새 모드를 덮어쓰지 못하게 한다.
    private var pollGeneration: UInt64 = 0
    /// 이번 실행 세션에서 제안을 묻지 않을 모드.
    private var promptedOtherModes: Set<HerdrMode> = []
    private var lastOtherModeProbeAt = Date.distantPast
    private var otherModeProbeInFlight = false

    init(backends: [HerdrMode: any HerdrBackend] = SlotStore.makeBackends()) {
        self.backends = backends
        // 기존 동작(패널 항상 표시)을 잇도록 기본값은 켠다.
        UserDefaults.standard.register(defaults: [
            Self.notchPanelEnabledKey: true,
            Self.notchPanelWidthKey: Double(Self.defaultPanelWidth),
            Self.appLanguageKey: AppLanguage.system.rawValue,
            Self.herdrModeKey: HerdrMode.tui.rawValue,
        ])
        notchPanelEnabled = UserDefaults.standard.bool(forKey: Self.notchPanelEnabledKey)
        let storedWidth = UserDefaults.standard.double(forKey: Self.notchPanelWidthKey)
        notchPanelWidth = storedWidth > 0 ? storedWidth : Self.defaultPanelWidth
        language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: Self.appLanguageKey) ?? ""
        ) ?? .system
        mode = HerdrMode(
            rawValue: UserDefaults.standard.string(forKey: Self.herdrModeKey) ?? ""
        ) ?? .tui
    }

    nonisolated private static func makeBackends() -> [HerdrMode: any HerdrBackend] {
        [.tui: HerdrTUIClient(), .app: HerdrAppClient()]
    }

    private var backend: any HerdrBackend {
        backends[mode]!
    }

    /// UI 문자 조회. 형식 인자를 받는 키는 포맷 문자에 그대로 대입한다.
    func t(_ key: AppText, _ args: CVarArg...) -> String {
        let format = key.text(in: language)
        return args.isEmpty ? format : String(format: format, arguments: args)
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

    /// 드롭다운 선택. 직접 고른 모드는 그 실행 세션 동안 반대 모드 제안으로 흔들지 않는다.
    func pickMode(_ newMode: HerdrMode) {
        promptedOtherModes.formUnion([newMode, newMode.opposite])
        mode = newMode
    }

    private func modeDidChange(from old: HerdrMode) {
        guard old != mode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: Self.herdrModeKey)
        Self.logger.notice("모드 전환: \(old.rawValue, privacy: .public) → \(self.mode.rawValue, privacy: .public)")
        // 진행 중이던 이전 모드 폴링 결과가 새 모드 상태를 덮어쓰지 못하게 한다.
        pollGeneration &+= 1
        pollInFlight = false
        lastOtherModeProbeAt = .distantPast
        suggestedModeSwitch = nil
        spaces = []
        chips = []
        idleAgents = []
        overflowCount = 0
        poll()
    }

    /// herdr 응답이 최대 2초까지 걸릴 수 있어 폴링 간격(0.7초)보다 느리면
    /// 다음 틱을 건너뛴다. 동시에 여러 herdr 프로세스를 띄우지 않기 위해서다.
    private func poll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        let generation = pollGeneration
        // 백엔드·resolver를 명시 캡처해 클로저에 self가 암묵적으로 묻어 들어가는
        // 것을 끊는다(안쪽 [weak self]와 소유권이 어긋나 경고가 난다).
        let backend = self.backend
        let gitResolver = self.gitResolver
        DispatchQueue.global(qos: .utility).async {
            let result = backend.snapshot()
            // 작업명 폴백용 브랜치는 살아 있는 snapshot의 신호 탭 소속
            // 에이전트만 읽는다. 잠든 탭까지 조회하면 폴링마다 git만 늘어난다.
            let signalTabIDs = Set(result.tabs.filter { $0.status != .idle }.map(\.tabId))
            let branches = result.connection == .ok
                ? gitResolver.gitBranches(
                    of: result.agents.filter { $0.tabId.map(signalTabIDs.contains) ?? false }
                )
                : [:]
            Task { @MainActor in
                // Store는 앱 델리게이트가 앱 생명주기 내내 보유해 weak 캡처가
                // 필요 없고, 폴링 한 틱짜리 강참조는 순환을 만들지 않는다.
                self.apply(result, branches: branches, generation: generation)
            }
        }
    }

    private func apply(
        _ result: HerdrSnapshotResult,
        branches: [String: String],
        generation: UInt64
    ) {
        // 모드를 바꾼 뒤 도착한 이전 모드의 응답은 버린다.
        guard generation == pollGeneration else { return }
        pollInFlight = false
        connection = result.connection
        maybeProbeOtherMode()

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
                        return TabChip(tab: tab, agents: tabMembers, branches: branches)
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
        // 주의도순(blocked → done → working)으로 채우며 개수·폭 예산 중 먼저 넘는 쪽에서 끊는다.
        // 폭 계산은 렌더링(ChipMetrics)과 같은 식으로, 잘린 라벨 기준으로
        // 잰다. 중간에 예산을 넘는 칩이 나오면 그대로 멈춘다(심각도가
        // 낮은 칩을 위해 높은 칩을 건너뛰지 않는다).
        var selected: [SpaceChip] = []
        var remaining = Self.maxChipsWidth
        for chip in visible where selected.count < Self.maxChips {
            let width = ChipMetrics.chipWidth(
                label: ChipMetrics.truncatedLabel(chip.workspace.label),
                hasDot: chip.worstStatus != nil
            )
            if width > remaining { break }
            selected.append(chip)
            remaining -= width
        }
        chips = selected
        overflowCount = visible.count - selected.count

        idleAgents = agents
            .filter { $0.status == .idle }
            .sorted { $0.displayName < $1.displayName }
    }

    /// 반대 모드가 실제로 응답하면 이번 실행 세션에서 한 번만 전환을 제안한다.
    private func maybeProbeOtherMode() {
        let other = mode.opposite
        let interval = connection == .offline
            ? Self.otherModeProbeIntervalOffline
            : Self.otherModeProbeInterval
        guard
            suggestedModeSwitch == nil,
            !otherModeProbeInFlight,
            !promptedOtherModes.contains(other),
            Date().timeIntervalSince(lastOtherModeProbeAt) >= interval
        else { return }
        lastOtherModeProbeAt = Date()
        otherModeProbeInFlight = true
        let generation = pollGeneration
        let backend = backends[other]
        DispatchQueue.global(qos: .utility).async {
            let reachable = backend?.isReachable() ?? false
            Task { @MainActor in
                self.finishOtherModeProbe(reachable: reachable, generation: generation)
            }
        }
    }

    private func finishOtherModeProbe(reachable: Bool, generation: UInt64) {
        otherModeProbeInFlight = false
        let other = mode.opposite
        // 보는 사이에 모드가 바뀌었으면 결과를 버린다.
        guard
            reachable,
            generation == pollGeneration,
            !promptedOtherModes.contains(other)
        else { return }
        // 양쪽 다 물었으니 반대 방향은 되묻지 않는다(전환 직후 되돌리라는 제안이 뜨는 일을 막는다).
        promptedOtherModes.formUnion([other, mode])
        Self.logger.notice("반대 모드 실행 감지: \(other.rawValue, privacy: .public) 전환 제안")
        suggestedModeSwitch = other
    }

    func acceptSuggestedModeSwitch() {
        guard let target = suggestedModeSwitch else { return }
        Self.logger.notice("전환 제안 수락: \(target.rawValue, privacy: .public)")
        suggestedModeSwitch = nil
        mode = target
    }

    func dismissSuggestedModeSwitch() {
        guard suggestedModeSwitch != nil else { return }
        Self.logger.notice("전환 제안 유지")
        suggestedModeSwitch = nil
    }

    /// 에이전트 터미널로 포커스를 옮긴다. 지목할 식별자가 없는 에이전트는
    /// 탭해도 아무 일도 하지 않는다.
    func focus(_ slot: AgentSlot) {
        launch { $0.focus(agent: slot) }
    }

    // focus 계열은 명령에 앞서 모드의 GUI를 앞으로 끌어온다. 창이 닫혀 있거나
    // 앱이 꺼져 있으면 포커스 명령이 소켓 전환으로만 끝나 아무 창도 보이지
    // 않기 때문이다.
    func focusWorkspace(_ id: String) {
        launch { $0.focus(workspaceID: id) }
    }

    func focusTab(_ id: String) {
        launch { $0.focus(tabID: id) }
    }

    private func launch(_ action: @escaping (any HerdrBackend) -> Void) {
        let backend = self.backend
        AppLauncher.bringToFront(mode: mode) {
            action(backend)
        }
    }
}
