import SwiftUI

@main
struct HerdrStatusNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Herdr", systemImage: "circle.grid.2x2.fill") {
            MenuBarRootView()
                .environmentObject(appDelegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// NSPanel은 SwiftUI 장면 생명주기 밖이라 앱 델리게이트가 관리한다.
/// AppKit 델리게이트 생애주기는 전부 메인에서 돌아가므로 MainActor로 격리한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SlotStore()
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = NotchPanelController(store: store)
        store.startPolling()
    }
}
