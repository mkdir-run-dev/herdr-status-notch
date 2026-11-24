import Foundation

/// herdr CLI(TUI) 백엔드. 실행과 JSON 디코딩을 이 경계에서 끝내고,
/// 호출자에는 이미 정돈된 값만 넘긴다.
final class HerdrTUIClient: HerdrBackend {
    let mode = HerdrMode.tui
    private let executableURL: URL
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 2.0) {
        self.timeout = timeout
        self.executableURL = ExecutableLocator.resolve(
            name: "herdr",
            fallbacks: [URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/herdr")]
        )
    }

    /// `herdr api snapshot`을 실행한다. agents·workspaces·tabs를 한 번에 얻는다.
    /// offline이면 전부 비어 있다.
    func snapshot() -> HerdrSnapshotResult {
        fetch(timeout: timeout)
    }

    func isReachable() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { return false }
        return fetch(timeout: 1.0).connection == .ok
    }

    /// 결과를 표시하지 않는 포커스 명령. 화면은 다음 폴링이 다시 반영한다.
    func focus(workspaceID: String) {
        spawn(["workspace", "focus", workspaceID])
    }

    func focus(tabID: String) {
        spawn(["tab", "focus", tabID])
    }

    /// name 없는 에이전트는 지목할 대상이 없어 아무 일도 하지 않는다.
    func focus(agent: AgentSlot) {
        guard let name = agent.name else { return }
        spawn(["agent", "focus", name])
    }

    private func fetch(timeout: TimeInterval) -> HerdrSnapshotResult {
        guard
            let json = ProcessRunner.run(executableURL, arguments: ["api", "snapshot"], timeout: timeout),
            let decoded = try? JSONDecoder().decode(HerdrSnapshotResponse.self, from: Data(json.utf8))
        else {
            // 실행 실패·exit != 0·JSON 구조 불일치를 모두 "herdr를 못 쓴다"로 묶는다.
            return .offline
        }
        return HerdrSnapshotResult(
            agents: decoded.result.snapshot.agents,
            workspaces: decoded.result.snapshot.workspaces,
            tabs: decoded.result.snapshot.tabs ?? [],
            connection: .ok
        )
    }

    private func spawn(_ arguments: [String]) {
        DispatchQueue.global(qos: .utility).async {
            _ = ProcessRunner.exitCode(self.executableURL, arguments: arguments, timeout: self.timeout)
        }
    }
}
