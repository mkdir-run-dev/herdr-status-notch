import Foundation

/// herdr CLI 실행 래퍼. 실행과 JSON 디코드를 이 경계에서 끝내고,
/// 호출자에는 이미 정돈된 값만 넘긴다.
/// 상태가 전부 불변이거나 전용 serial queue 안에서만 바뀌어 크로스 스레드
/// 호출이 안전하다(SlotStore가 백그라운드에서 폴링한다).
final class HerdrClient: @unchecked Sendable {
    private let executableURL: URL
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "local.herdr.statusnotch.client", qos: .utility)

    init(timeout: TimeInterval = 2.0) {
        self.timeout = timeout
        self.executableURL = Self.resolveExecutable()
    }

    /// PATH를 순회하고 못 찾으면 실측 설치 경로(~/.local/bin/herdr)로 폴백한다.
    /// 앱은 GUI 런처로 뜨므로 셸 초기화 스크립트(~/.zshrc)의 PATH를 물려받지 못한다.
    private static func resolveExecutable() -> URL {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathEnv.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("herdr")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/herdr")
    }

    /// 프로세스를 실행해 stdout을 돌려준다. 실행 실패·타임아웃·exit code != 0은
    /// 전부 nil이며, 호출자는 nil을 offline으로 해석한다.
    private func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        // 출력을 버리되 파이프 버퍼가 차서 herdr가 멈추는 일만 막는다.
        process.standardError = FileHandle.nullDevice

        // stdout을 먼저 읽기 시작해야 파이프 버퍼(64KB)가 차도 교착하지 않는다.
        let readerGroup = DispatchGroup()
        readerGroup.enter()
        var output = Data()
        queue.async {
            output = stdout.fileHandleForReading.readDataToEndOfFile()
            readerGroup.leave()
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        // 응답이 느린 herdr가 폴링을 계속 붙잡지 않게 타임아웃에 맞춰 죽인다.
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        readerGroup.wait()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: output, encoding: .utf8)
    }

    /// `herdr api snapshot`을 실행한다. agents·workspaces·tabs를 한 번에 얻는다.
    /// offline이면 전부 비어 있다.
    func snapshot() -> (agents: [AgentSlot], workspaces: [WorkspaceInfo], tabs: [TabInfo], connection: ConnectionState) {
        guard
            let json = run(["api", "snapshot"]),
            let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(HerdrSnapshotResponse.self, from: data)
        else {
            // 실행 실패·exit != 0·JSON 구조 불일치를 모두 "herdr를 못 쓴다"로 묶는다.
            return ([], [], [], .offline)
        }
        return (
            decoded.result.snapshot.agents,
            decoded.result.snapshot.workspaces,
            decoded.result.snapshot.tabs ?? [],
            .ok
        )
    }

    /// `herdr agent focus <name>`으로 해당 에이전트 터미널에 포커스를 옮긴다.
    /// 결과 표시는 하지 않는다(위젯 범위 밖).
    func focus(agentNamed name: String) {
        spawn(["agent", "focus", name])
    }

    /// `herdr workspace focus <id>`로 워크스페이스에 포커스를 옮긴다.
    func focus(workspaceID: String) {
        spawn(["workspace", "focus", workspaceID])
    }

    /// `herdr tab focus <tab_id>`로 탭에 포커스를 옮긴다.
    func focus(tabID: String) {
        spawn(["tab", "focus", tabID])
    }

    /// 결과를 기다리지 않는 실행. 메뉴 클릭 응답성을 위해 백그라운드 큐에서만
    /// 실행하고 결과는 폴링이 다시 반영한다.
    private func spawn(_ arguments: [String]) {
        queue.async {
            let process = Process()
            process.executableURL = self.executableURL
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}
