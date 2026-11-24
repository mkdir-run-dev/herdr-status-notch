import AppKit
import Darwin
import Foundation

/// Herdr.app 백엔드. 창이 열려 있으면 `herdr-app ls`(스페이스 > 탭 > 터미널)로
/// 계층을 얻고 코어(`hc ls`)가 cwd를 보강한다. 창이 닫혀도 코어는 터미널을
/// 계속 돌리므로 그때는 코어만 묻는다.
final class HerdrAppClient: @unchecked Sendable, HerdrBackend {
    let mode = HerdrMode.app

    /// 창(`herdr-app ls`·`do`)의 제어 소켓. HERDR_APP_HOME이 다른 창을 고른다.
    static var controlSocketPath: String {
        let home = ProcessInfo.processInfo.environment["HERDR_APP_HOME"] ?? ""
        let base = home.isEmpty ? NSHomeDirectory() + "/.config/herdr-app" : home
        return (base as NSString).expandingTildeInPath + "/herdr-app.sock"
    }

    /// 코어(`hc`) 기본 세션의 소켓.
    static var coreSocketPath: String {
        NSHomeDirectory() + "/.local/state/herdr-core/default/default.sock"
    }

    /// 축소 계층이 쓰는 가짜 ID의 접두사. 창이 주는 실제 ID와 겹치지 않는다.
    private static let fallbackIDPrefix = "where:"

    private let appURL: URL
    private let hcURL: URL
    private let queue = DispatchQueue(label: "local.herdr.statusnotch.appclient", qos: .utility)
    /// 포커스 명령은 재시도 루프라 폴링과 큐를 나눠 서로 붙잡지 않게 한다.
    private let commandQueue = DispatchQueue(
        label: "local.herdr.statusnotch.appcommand",
        qos: .userInitiated
    )
    /// 축소 계층(창이 닫혀 있던 폴링)의 ID → 대표 터미널 주소.
    private var fallbackTargets: [String: String] = [:]

    init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        appURL = ExecutableLocator.resolve(
            name: "herdr-app",
            fallbacks: [
                home.appendingPathComponent(".local/bin/herdr-app"),
                URL(fileURLWithPath: "/Applications/Herdr.app/Contents/MacOS/Herdr"),
            ]
        )
        hcURL = ExecutableLocator.resolve(
            name: "hc",
            fallbacks: [
                home.appendingPathComponent(".local/bin/hc"),
                home.appendingPathComponent(".local/share/herdr-core/current/Contents/MacOS/herdr-core"),
            ]
        )
    }

    func snapshot() -> HerdrSnapshotResult {
        queue.sync {
            let core = coreByAddress()
            fallbackTargets = [:]
            if let window = windowList() {
                return Self.build(window: window, core: core ?? [:]) { terminalID in
                    self.terminalTitle(terminalID)
                }
            }
            guard let core else { return .offline }
            let fallback = Self.buildFallback(core: Array(core.values))
            fallbackTargets = fallback.targets
            return fallback.result
        }
    }

    func isReachable() -> Bool {
        guard
            FileManager.default.isExecutableFile(atPath: appURL.path),
            !NSRunningApplication
                .runningApplications(withBundleIdentifier: HerdrMode.app.targetBundleIdentifier)
                .isEmpty,
            FileManager.default.fileExists(atPath: Self.controlSocketPath)
        else { return false }
        return windowList() != nil
    }

    func focus(workspaceID: String) {
        if let address = fallbackTarget(for: workspaceID) {
            focusTerminal(address)
        } else {
            runDo(["space.select", "--id", workspaceID])
        }
    }

    func focus(tabID: String) {
        if let address = fallbackTarget(for: tabID) {
            focusTerminal(address)
        } else {
            runDo(["tab.select", "--id", tabID])
        }
    }

    /// address(t1)가 없는 에이전트는 지목할 대상이 없어 아무 일도 하지 않는다.
    func focus(agent: AgentSlot) {
        guard let address = agent.terminalID, !address.isEmpty else { return }
        focusTerminal(address)
    }

    private func fallbackTarget(for id: String) -> String? {
        queue.sync { fallbackTargets[id] }
    }

    private func focusTerminal(_ address: String) {
        runDo(["agent.focus", "--terminal", address])
    }

    /// `herdr-app do`. 창을 막 띄운 직후엔 창이 아직 소켓을 열지 못해 실패할 수
    /// 있어 짧게 재시도한다. 포커스 계열만 보내므로 재시도해도 안전하다.
    private func runDo(_ arguments: [String]) {
        commandQueue.async {
            let deadline = Date().addingTimeInterval(3.0)
            repeat {
                if ProcessRunner.exitCode(self.appURL, arguments: ["do"] + arguments, timeout: 1.0) == 0 {
                    return
                }
                Thread.sleep(forTimeInterval: 0.2)
            } while Date() < deadline
        }
    }

    private func windowList() -> WindowList? {
        guard
            let json = ProcessRunner.run(appURL, arguments: ["ls"], timeout: 1.0),
            let list = try? JSONDecoder().decode(WindowList.self, from: Data(json.utf8))
        else { return nil }
        return list
    }

    /// 코어가 듣고 있을 때만 hc를 실행한다. 코어가 없는 상태에서 hc를 돌리면
    /// 코어가 시작될 수 있어, 상태 앱이 코어를 띄우는 일을 막는다.
    private func coreByAddress() -> [String: CoreTerminal]? {
        guard
            Self.isListening(atPath: Self.coreSocketPath),
            let json = ProcessRunner.run(hcURL, arguments: ["ls", "--json"], timeout: 1.0),
            let list = try? JSONDecoder().decode(CoreList.self, from: Data(json.utf8)),
            let terminals = list.terminals
        else { return nil }
        return Dictionary(terminals.map { ($0.address, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func terminalTitle(_ address: String) -> String? {
        guard
            let json = ProcessRunner.run(hcURL, arguments: ["get", address, "--json"], timeout: 1.0),
            let detail = try? JSONDecoder().decode(TerminalDetail.self, from: Data(json.utf8))
        else { return nil }
        return detail.title
    }

    /// 소켓에 연결만 해 보고 끊는다. 듣는 프로세스가 없으면 즉시 실패한다.
    static func isListening(atPath path: String) -> Bool {
        let pathBytes = path.utf8CString
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            pathBytes.withUnsafeBufferPointer { source in
                memcpy(buffer.baseAddress, source.baseAddress, source.count)
            }
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                Darwin.connect(descriptor, sockaddr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    /// 창이 응답했을 때의 정규 계층. core는 address별 코어 레코드(cwd 출처)다.
    static func build(
        window: WindowList,
        core: [String: CoreTerminal],
        title: (String) -> String?
    ) -> HerdrSnapshotResult {
        var agents: [AgentSlot] = []
        var workspaces: [WorkspaceInfo] = []
        var tabs: [TabInfo] = []
        for (spaceIndex, space) in window.spaces.enumerated() {
            let isRemote = !(space.machine ?? "").isEmpty
            workspaces.append(WorkspaceInfo(
                workspaceId: space.id,
                label: spaceLabel(space),
                number: spaceIndex + 1
            ))
            for (tabIndex, tab) in (space.tabs ?? []).enumerated() {
                let refs = flatten(tab.terminals ?? [])
                let tabAgents = refs.compactMap {
                    agent($0, space: space, tab: tab, core: core, isRemote: isRemote, title: title)
                }
                tabs.append(TabInfo(
                    tabId: tab.id,
                    workspaceId: space.id,
                    label: tab.name ?? "",
                    number: tabIndex + 1,
                    paneCount: refs.count,
                    agentStatus: worstStatus(of: tabAgents).rawValue
                ))
                agents += tabAgents
            }
        }
        return HerdrSnapshotResult(agents: agents, workspaces: workspaces, tabs: tabs, connection: .ok)
    }

    /// 창이 닫혀 있을 때 코어 목록만으로 만드는 축소 계층. 코어는 스페이스·탭 ID를
    /// 주지 않아 `where` 라벨("스페이스명 / 탭명")으로 묶는다.
    static func buildFallback(core: [CoreTerminal]) -> (result: HerdrSnapshotResult, targets: [String: String]) {
        var spaceNumbers: [String: Int] = [:]
        var tabNumbers: [String: Int] = [:]
        var targets: [String: String] = [:]
        var agents: [AgentSlot] = []
        var workspaces: [WorkspaceInfo] = []
        var tabs: [TabInfo] = []

        for group in fallbackGroups(core) {
            // 라벨은 "스페이스명 / 탭명"이다. 구분자가 없으면 통째로 스페이스명이다.
            let parts = group.whereLabel.components(separatedBy: " / ")
            let spaceName = parts.count > 1
                ? parts.dropLast().joined(separator: " / ")
                : group.whereLabel
            let spaceID = fallbackIDPrefix + spaceName
            let tabID = fallbackIDPrefix + group.whereLabel
            if spaceNumbers[spaceName] == nil {
                workspaces.append(WorkspaceInfo(
                    workspaceId: spaceID,
                    label: spaceName,
                    number: workspaces.count + 1
                ))
                spaceNumbers[spaceName] = workspaces.count
            }
            let tabNumber = (tabNumbers[spaceName] ?? 0) + 1
            tabNumbers[spaceName] = tabNumber
            let tabAgents = group.terminals.map {
                AgentSlot(
                    name: nil,
                    agent: $0.agent,
                    agentStatus: $0.status ?? "",
                    cwd: $0.cwd,
                    focused: false,
                    terminalID: $0.address,
                    paneID: "",
                    terminalTitle: nil,
                    workspaceId: spaceID,
                    tabId: tabID,
                    tokens: nil
                )
            }
            tabs.append(TabInfo(
                tabId: tabID,
                workspaceId: spaceID,
                label: parts.last ?? group.whereLabel,
                number: tabNumber,
                paneCount: tabAgents.count,
                agentStatus: worstStatus(of: tabAgents).rawValue
            ))
            agents += tabAgents
            // 축소 계층에는 스페이스·탭의 실제 ID가 없어 대표 에이전트 하나로 이동한다.
            let lead = tabAgents
                .sorted { $0.status.sortRank < $1.status.sortRank }
                .first?.terminalID
            if let lead {
                if targets[spaceID] == nil { targets[spaceID] = lead }
                targets[tabID] = lead
            }
        }
        return (
            HerdrSnapshotResult(agents: agents, workspaces: workspaces, tabs: tabs, connection: .ok),
            targets
        )
    }

    private static func agent(
        _ ref: TerminalRef,
        space: Space,
        tab: Tab,
        core: [String: CoreTerminal],
        isRemote: Bool,
        title: (String) -> String?
    ) -> AgentSlot? {
        // 에이전트가 아닌 일반 셸은 status가 없다. 두면 unknown으로 오판돼 빈 셸에 칩이 뜬다.
        guard let status = ref.status, !status.isEmpty else { return nil }
        let name = ref.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (name ?? "").isEmpty ? nil : name
        // 원격 스페이스의 경로는 로컬 파일시스템이 아니라 로컬 git을 돌리면 안 된다.
        let needsTitle = summary == nil && !isRemote && status != AgentStatus.idle.rawValue
        return AgentSlot(
            name: summary,
            agent: ref.app,
            agentStatus: status,
            cwd: isRemote ? nil : core[ref.terminal]?.cwd,
            focused: (space.active ?? false) && (tab.active ?? false),
            terminalID: ref.terminal,
            paneID: ref.pane ?? "",
            terminalTitle: needsTitle ? title(ref.terminal) : nil,
            workspaceId: space.id,
            tabId: tab.id,
            tokens: summary.map { AgentSlot.Tokens(summary: $0) }
        )
    }

    private static func spaceLabel(_ space: Space) -> String {
        if let name = space.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let folder = space.folder, !folder.isEmpty, folder != "/" {
            return (folder as NSString).lastPathComponent
        }
        return space.id
    }

    /// 탭의 터미널과 그 서브에이전트를 차례로 펼친다.
    private static func flatten(_ refs: [TerminalRef]) -> [TerminalRef] {
        refs.flatMap { [$0] + flatten($0.subAgents ?? []) }
    }

    private static func fallbackGroups(_ core: [CoreTerminal]) -> [FallbackGroup] {
        var groups: [FallbackGroup] = []
        let ordered = core.sorted {
            ($0.whereLabel ?? "", $0.address) < ($1.whereLabel ?? "", $1.address)
        }
        for terminal in ordered {
            guard
                let status = terminal.status, !status.isEmpty,
                terminal.state != "finished",
                let whereLabel = terminal.whereLabel, !whereLabel.isEmpty
            else { continue }
            if let index = groups.firstIndex(where: { $0.whereLabel == whereLabel }) {
                groups[index].terminals.append(terminal)
            } else {
                groups.append(FallbackGroup(whereLabel: whereLabel, terminals: [terminal]))
            }
        }
        return groups
    }

    /// 탭 대표 상태. 주의도순(blocked → done → working → idle → unknown) 첫 값.
    private static func worstStatus(of agents: [AgentSlot]) -> AgentStatus {
        agents.map(\.status).min { $0.sortRank < $1.sortRank } ?? .idle
    }

    private struct FallbackGroup {
        var whereLabel: String
        var terminals: [CoreTerminal]
    }

    struct WindowList: Decodable {
        let spaces: [Space]
    }

    struct Space: Decodable {
        let id: String
        let name: String?
        let folder: String?
        let machine: String?
        let active: Bool?
        let tabs: [Tab]?
    }

    struct Tab: Decodable {
        let id: String
        let name: String?
        let active: Bool?
        let terminals: [TerminalRef]?
    }

    struct TerminalRef: Decodable {
        let terminal: String
        let pane: String?
        let status: String?
        let app: String?
        let name: String?
        let subAgents: [TerminalRef]?

        enum CodingKeys: String, CodingKey {
            case terminal
            case pane
            case status
            case app
            case name
            case subAgents = "sub_agents"
        }
    }

    struct CoreList: Decodable {
        let terminals: [CoreTerminal]?
    }

    struct CoreTerminal: Decodable {
        let address: String
        let agent: String?
        let cwd: String?
        let state: String?
        let status: String?
        let whereLabel: String?

        enum CodingKeys: String, CodingKey {
            case address
            case agent
            case cwd
            case state
            case status
            case whereLabel = "where"
        }
    }

    struct TerminalDetail: Decodable {
        let title: String?
    }
}
