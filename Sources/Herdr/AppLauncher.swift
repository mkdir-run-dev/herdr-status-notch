import AppKit
import Foundation

/// 모드의 GUI 창을 앞으로 끌어오는 헬퍼. focus는 소켓으로 '무엇을 볼지'만 바꾸는
/// 명령이라 창이 없으면 클릭이 조용히 무시된다. 그래서 focus 계열 명령을
/// 쏘기 전에 항상 GUI를 띄운다.
enum AppLauncher {
    /// `open -b` 하나로 상태 세 가지를 모두 처리한다 — 실행 중이면 활성화(창이
    /// 전부 닫혀 있으면 Dock 클릭과 같은 reopen), 숨김·최소화면 드러내기, 꺼져
    /// 있으면 실행. GUI가 설치되지 않은 환경에서는 open이 실패하고 action만 실행된다.
    static func bringToFront(mode: HerdrMode, then action: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let bundleIdentifier = mode.targetBundleIdentifier
            let wasRunning = !NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .isEmpty
            // Herdr.app은 창을 닫으면(Cmd+W) 프로세스는 살아 있지만 소켓이 사라진다.
            let wasReady = mode != .app
                || FileManager.default.fileExists(atPath: HerdrAppClient.controlSocketPath)

            let open = Process()
            // git과 같은 이유로 PATH를 탐색하지 않고 고정 경로를 쓴다.
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-b", bundleIdentifier]
            open.standardOutput = FileHandle.nullDevice
            open.standardError = FileHandle.nullDevice
            try? open.run()
            open.waitUntilExit()

            // 새로 띄우는 중이면 GUI가 소켓에 붙어 첫 화면을 그릴 때까지 기다린다.
            // focus를 너무 일찍 쏘면 아직 붙지 않은 GUI가 전환 이벤트를 놓친다.
            if !(wasRunning && wasReady) {
                let deadline = Date().addingTimeInterval(5)
                while Date() < deadline, !isReady(bundleIdentifier: bundleIdentifier, mode: mode) {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
            action()
        }
    }

    private static func isReady(bundleIdentifier: String, mode: HerdrMode) -> Bool {
        guard
            !NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .isEmpty
        else { return false }
        return mode != .app
            || FileManager.default.fileExists(atPath: HerdrAppClient.controlSocketPath)
    }
}
