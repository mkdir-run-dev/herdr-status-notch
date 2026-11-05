import AppKit
import Combine
import SwiftUI

/// 노치 아래에 뜨는 플로팅 패널. 앱 활성화를 빼앗지 않는다(borderless·nonactivating).
/// borderless 창은 기본 드래그가 없어 mouseDown/mouseDragged로 직접 옮긴다.
final class NotchPanel: NSPanel {
    /// 드래그 종료 시 최종 창 원점을 컨트롤러에 넘긴다(UserDefaults 저장용).
    var onDragEnd: ((NSPoint) -> Void)?

    /// mouseDown 시점의 마우스 위치 - 창 원점. 드래그 중 잡은 지점을 그대로
    /// 붙잡게 하는 오프셋이다.
    private var dragOffset: NSPoint?

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

    var isDragging: Bool { dragOffset != nil }

    override func mouseDown(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        dragOffset = NSPoint(x: mouse.x - frame.origin.x, y: mouse.y - frame.origin.y)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let offset = dragOffset else { return }
        let mouse = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragOffset != nil else { return }
        dragOffset = nil
        onDragEnd?(frame.origin)
    }
}

/// 패널 생애주기와 위치를 SlotStore 상태에 맞춘다. 노치 패널 토글이 꺼져
/// 있으면 패널을 만들지도 않고, 보여줄 에이전트가 없으면 숨긴다.
/// NSPanel 조작은 메인에서만 하므로 MainActor로 격리한다.
@MainActor
final class NotchPanelController {
    static let panelWidth: CGFloat = 320
    static let notchPanelOriginKey = "notchPanelOrigin"

    private let store: SlotStore
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()

    init(store: SlotStore) {
        self.store = store

        // @Published는 willSet 시점에 방출하므로 메인 런루프로 한 틱 미뤄
        // 갱신된 값을 읽는다.
        store.$spaces
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in self?.syncPanel() } }
            .store(in: &cancellables)
        store.$notchPanelEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in self?.syncPanel() } }
            .store(in: &cancellables)
        syncPanel()
    }

    /// 에이전트 단위 전체 목록(idle 포함). 패널은 잠든 스페이스도 보여 준다.
    private var allAgents: [AgentSlot] {
        store.spaces.flatMap(\.agents)
    }

    private func syncPanel() {
        guard store.notchPanelEnabled, !allAgents.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        layout()
        panel?.orderFrontRegardless()
    }

    /// 토글이 켜진 첫 순간에만 패널을 만든다. 끄고 있는 동안엔 창이 없다.
    private func ensurePanel() -> NotchPanel {
        if let panel { return panel }
        let hostingView = NSHostingView(
            rootView: AnyView(NotchPanelView().environmentObject(store))
        )
        let panel = NotchPanel(content: hostingView)
        panel.onDragEnd = { origin in
            // 드래그로 옮긴 위치만 저장한다(기본 상단 중앙 배치는 저장 안 함).
            UserDefaults.standard.set(
                NSStringFromPoint(origin),
                forKey: Self.notchPanelOriginKey
            )
        }
        self.panel = panel
        return panel
    }

    private func layout() {
        let panel = ensurePanel()
        guard let hostingView = panel.contentView as? NSHostingView<AnyView> else { return }
        // 드래그 중 재배치하면 창이 손가락 밖으로 튄다.
        guard !panel.isDragging else { return }

        hostingView.frame.size.width = Self.panelWidth
        let contentHeight = hostingView.fittingSize.height

        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = NSPoint(
            x: visible.midX - Self.panelWidth / 2,
            y: visible.maxY - contentHeight - 6
        )
        if let saved = savedOrigin {
            origin = saved
        }
        panel.setFrame(
            NSRect(x: origin.x, y: origin.y, width: Self.panelWidth, height: contentHeight),
            display: true
        )

        // TODO: 노치가 있는 맥에서는 screen.auxiliaryTopLeftArea와
        // auxiliaryTopRightArea로 실제 노치 영역 폭을 잡아 그 아래 중앙에
        // 배치한다. 지금은 저장 위치가 없으면 보이는 화면 기준 상단 중앙 고정이다.
    }

    /// 저장된 드래그 위치. (0,0)은 스크린 좌표계에서 유효하지 않은 위치라
    /// 파싱 실패와 함께 없는 값으로 취급한다.
    private var savedOrigin: NSPoint? {
        guard
            let saved = UserDefaults.standard.string(forKey: Self.notchPanelOriginKey)
        else { return nil }
        let point = NSPointFromString(saved)
        return point.x > 0 && point.y > 0 ? point : nil
    }
}
