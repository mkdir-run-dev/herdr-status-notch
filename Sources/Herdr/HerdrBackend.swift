import Foundation

/// 백엔드 하나가 내놓는 폴링 한 틱의 결과. 표현 계층은 어느 백엔드에서 왔는지 모른다.
struct HerdrSnapshotResult: Sendable {
    let agents: [AgentSlot]
    let workspaces: [WorkspaceInfo]
    let tabs: [TabInfo]
    let connection: ConnectionState

    static let offline = Self(agents: [], workspaces: [], tabs: [], connection: .offline)
}

/// 모드별 데이터 수집·포커스 계층. SlotStore는 이 프로토콜만 본다.
protocol HerdrBackend: Sendable {
    var mode: HerdrMode { get }
    func snapshot() -> HerdrSnapshotResult
    /// 반대 모드 실행 감지용. 실제로 응답하는 상태일 때만 참.
    func isReachable() -> Bool
    func focus(workspaceID: String)
    func focus(tabID: String)
    func focus(agent: AgentSlot)
}

/// 외부 프로세스 실행 공용부. 셸 없이 인자 배열로만 실행한다.
enum ProcessRunner {
    private static let readerQueue = DispatchQueue(
        label: "local.herdr.statusnotch.reader",
        qos: .utility,
        attributes: .concurrent
    )

    /// stdout을 돌려준다. 실행 실패·타임아웃·exit code != 0은 전부 nil이다.
    static func run(_ executable: URL, arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        // 출력을 버리되 파이프 버퍼가 차서 프로세스가 멈추는 일만 막는다.
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // 자식이 실행된 뒤 부모 쪽 쓰기 끝을 닫아야 자식이 죽으면 읽기가 끝난다.
        try? stdout.fileHandleForWriting.close()

        // stdout을 곧바로 읽기 시작해야 파이프 버퍼(64KB)가 차도 교착하지 않는다.
        let readerGroup = DispatchGroup()
        readerGroup.enter()
        var output = Data()
        readerQueue.async {
            output = stdout.fileHandleForReading.readDataToEndOfFile()
            readerGroup.leave()
        }

        // 응답이 느린 프로세스가 폴링을 계속 붙잡지 않게 타임아웃에 맞춰 죽인다.
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        readerGroup.wait()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: output, encoding: .utf8)
    }

    /// 종료 코드를 기다려 돌려준다. 실행 실패·타임아웃은 nil이다.
    static func exitCode(_ executable: URL, arguments: [String], timeout: TimeInterval) -> Int32? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        return process.terminationStatus
    }
}

/// 작업명 폴백용 git 브랜치 조회. 어느 모드든 같다.
final class GitBranchResolver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.herdr.statusnotch.git", qos: .utility)

    /// 에이전트 id별로 agents[].cwd의 git 브랜치명을 읽는다. 같은 cwd의 중복
    /// 조회는 한 번만 하고 비저장소·실패한 cwd는 결과에서 빠진다.
    func gitBranches(of agents: [AgentSlot]) -> [String: String] {
        var branches: [String: String] = [:]
        var byCwd: [String: String] = [:]
        var failedCwds: Set<String> = []
        // serial queue에서 순차 실행해 폴링마다 git이 병렬로 쌓이지 않게 한다.
        queue.sync {
            for agent in agents {
                guard let cwd = agent.cwd else { continue }
                if let branch = byCwd[cwd] {
                    branches[agent.id] = branch
                } else if !failedCwds.contains(cwd) {
                    if let branch = gitBranch(in: cwd) {
                        byCwd[cwd] = branch
                        branches[agent.id] = branch
                    } else {
                        failedCwds.insert(cwd)
                    }
                }
            }
        }
        return branches
    }

    /// cwd 하나의 브랜치명. 1초를 넘기거나 비저장소면 nil.
    private func gitBranch(in cwd: String) -> String? {
        // herdr와 달리 PATH를 탐색하지 않고 시스템 표준 경로로 고정한다(공격 면 최소화).
        guard
            let branch = ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
                timeout: 1.0
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !branch.isEmpty
        else { return nil }
        // detached HEAD에서 rev-parse가 "HEAD"를 돌려주는데 작업명으로는 정보가 없다.
        return branch == "HEAD" ? nil : branch
    }
}

/// 실행 파일 탐색. 앱은 GUI 런처로 뜨므로 셸 초기화 스크립트(~/.zshrc)의 PATH를
/// 물려받지 못해 PATH를 순회한 뒤 실측 설치 경로로 폴백한다.
enum ExecutableLocator {
    /// PATH와 fallbacks에 모두 없으면 첫 폴백 경로를 그대로 돌려 실행이 실패하게 한다.
    static func resolve(name: String, fallbacks: [URL]) -> URL {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathEnv.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return fallbacks.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        } ?? fallbacks[0]
    }
}
