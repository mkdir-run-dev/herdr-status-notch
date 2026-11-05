import AppKit
import Combine
import SwiftUI

/// 노치 아래에 뜨는 플로팅 패널. 앱 활성화를 빼앗지 않는다(borderless·nonactivating).
final class NotchPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
        contentView = content
    }

    // nonactivating 패널은 키 창이 될 필요가 없다. 탭 처리는 SwiftUI 제스처로 충분하다.
    override var canBecomeKey: Bool { false }
}

/// 패널 생애주기와 위치를 SlotStore 상태에 맞춘다. 슬롯이 0개면 패널을 숨긴다.
/// NSPanel 조작은 메인에서만 하므로 MainActor로 격리한다.
@MainActor
final class NotchPanelController {
    static let panelWidth: CGFloat = 320

    private let store: SlotStore
    private let panel: NotchPanel
    private let hostingView: NSHostingView<AnyView>
    private var cancellable: AnyCancellable?

    init(store: SlotStore) {
        self.store = store
        hostingView = NSHostingView(
            rootView: AnyView(NotchPanelView().environmentObject(store))
        )
        panel = NotchPanel(content: hostingView)

        // $slots는 willSet 시점에 방출하므로 메인 액터로 한 틱 미뤄
        // 갱신된 값을 읽는다.
        cancellable = store.$slots
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.syncPanel() }
            }
        syncPanel()
    }

    private func syncPanel() {
        if store.slots.isEmpty {
            panel.orderOut(nil)
            return
        }
        layout()
        panel.orderFrontRegardless()
    }

    private func layout() {
        hostingView.frame.size.width = Self.panelWidth
        let contentHeight = hostingView.fittingSize.height

        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - Self.panelWidth / 2,
            y: visible.maxY - contentHeight - 6,
            width: Self.panelWidth,
            height: contentHeight
        )
        panel.setFrame(frame, display: true)

        // TODO: 노치가 있는 맥에서는 screen.auxiliaryTopLeftArea와
        // auxiliaryTopRightArea로 실제 노치 영역 폭을 잡아 그 아래 중앙에
        // 배치한다. 지금은 보이는 화면 기준 상단 중앙 고정이다.
    }
}
