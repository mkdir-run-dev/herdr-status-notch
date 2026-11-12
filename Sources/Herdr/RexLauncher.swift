import AppKit
import Foundation

/// herdr GUI(Rex, com.superlogical.rex) 창을 앞으로 끌어오는 헬퍼.
/// workspace/tab focus는 소켓으로 '어떤 스페이스를 볼지'만 바꾸는 명령이라
/// Rex가 꺼져 있거나 창이 전부 닫혀 있으면 보여 줄 창 자체가 없어 클릭이
/// 조용히 무시된다. 그래서 focus 계열 명령을 쏘기 전에 항상 Rex를 띄운다.
enum RexLauncher {
    static let bundleIdentifier = "com.superlogical.rex"

    /// Rex를 앞으로 끌어온 뒤 action을 실행한다. `open -b` 하나로 상태
    /// 세 가지를 모두 처리한다 — 실행 중이면 활성화(창이 전부 닫혀 있으면
    /// Dock 클릭과 같은 reopen), 숨김·최소화면 드러내기, 꺼져 있으면 실행.
    /// Rex가 설치되지 않은 환경에서는 open이 실패하고 action만 예전처럼
    /// 실행된다.
    static func bringToFrontThen(run action: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let wasRunning = !NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .isEmpty

            let open = Process()
            // git과 같은 이유로 PATH를 탐색하지 않고 고정 경로를 쓴다.
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-b", bundleIdentifier]
            open.standardOutput = FileHandle.nullDevice
            open.standardError = FileHandle.nullDevice
            try? open.run()
            open.waitUntilExit()

            guard !wasRunning else {
                action()
                return
            }
            // 새로 띄우는 중이면 프로세스가 나타날 때까지 기다렸다가 GUI가
            // 소켓에 붙어 첫 화면을 그릴 틈을 준다. focus를 너무 일찍 쏘면
            // 아직 붙지 않은 GUI가 전환 이벤트를 놓친다.
            let deadline = Date().addingTimeInterval(5)
            while NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .isEmpty, Date() < deadline
            {
                Thread.sleep(forTimeInterval: 0.05)
            }
            Thread.sleep(forTimeInterval: 0.4)
            action()
        }
    }
}
