import SwiftUI

@main
struct HerdrStatusNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(appDelegate.store)
        } label: {
            StatusIconLabel(store: appDelegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 메뉴바 앱 아이콘. 그리드 아이콘 + 대기(idle) 인원수 뱃지이며 herdr가
/// 오프라인이면 아이콘이 빨개진다.
private struct StatusIconLabel: View {
    @ObservedObject var store: SlotStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "circle.grid.2x2.fill")
                .foregroundStyle(store.connection == .offline ? Color.red : Color.primary)
            // 0명이면 숫자 없이 아이콘만 남는다. idle은 경보가 아니라 가용
            // 자원이므로 뱃지는 blocked 호박과 구분되는 중립 회색을 쓴다.
            if !store.idleAgents.isEmpty {
                Text("\(store.idleAgents.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(Color(nsColor: .systemGray)))
                    .offset(x: 7, y: -4)
            }
        }
    }
}

/// NSPanel과 NSStatusItem은 SwiftUI 장면 생명주기 밖이라 앱 델리게이트가
/// 관리한다. AppKit 델리게이트 생애주기는 전부 메인에서 돌아가므로
/// MainActor로 격리한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SlotStore()
    private var panelController: NotchPanelController?
    private var chipBar: ChipBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = NotchPanelController(store: store)
        chipBar = ChipBarManager(store: store)
        store.startPolling()
    }
}
