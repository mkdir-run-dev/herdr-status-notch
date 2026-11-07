import AppKit
import Combine
import SwiftUI

/// 노치 아래에 뜨는 플로팅 패널. 앱 활성화를 빼앗지 않는다(borderless·nonactivating).
/// borderless 창은 기본 이동·리사이즈가 없어 mouseDown/mouseDragged로
/// 본문 드래그 이동과 좌우 가장자리 폭 리사이즈를 직접 처리한다.
final class NotchPanel: NSPanel {
    /// 제스처 종료 시 최종 창 원점을 컨트롤러에 넘긴다(UserDefaults 저장용).
    var onDragEnd: ((NSPoint) -> Void)?
    /// 리사이즈로 폭이 확정될 때마다 컨트롤러에 넘긴다.
    var onResize: ((CGFloat) -> Void)?

    /// 창 가장자리를 리사이즈로 판정하는 폭(포인트). 행 콘텐츠가 좌우 8pt
    /// 안쪽에서 시작해 이 스트립과 겹치지 않는다.
    static let edgeHitSlop: CGFloat = 6
    /// 리사이즈 폭 상하한. 컨트롤러 상수로 초기화된다.
    var minWidth: CGFloat = 220
    var maxWidth: CGFloat = 600

    /// 진행 중 마우스 제스처. move는 잡은 지점 오프셋을, resizeLeft는
    /// 고정해 둘 우측 가장자리 x를 들고 다닌다.
    private enum Gesture: Equatable {
        case none
        case move(offset: NSPoint)
        case resizeLeft(rightEdgeX: CGFloat)
        case resizeRight
    }
    private var gesture: Gesture = .none

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

    /// 이동·리사이즈 중이면 참. 컨트롤러가 폴링 틱 재배치를 건너뛴다.
    var isBusy: Bool {
        if case .none = gesture { return false }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        // 우측 판정을 먼저 해 모서리 겹침에서 우측 리사이즈가 이긴다.
        if frame.maxX - mouse.x <= Self.edgeHitSlop {
            gesture = .resizeRight
        } else if mouse.x - frame.minX <= Self.edgeHitSlop {
            gesture = .resizeLeft(rightEdgeX: frame.maxX)
        } else {
            gesture = .move(
                offset: NSPoint(x: mouse.x - frame.origin.x, y: mouse.y - frame.origin.y)
            )
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        switch gesture {
        case .none:
            return
        case .move(let offset):
            // 드래그 중 잡은 지점을 그대로 붙잡게 오프셋을 뺀 원점으로 옮긴다.
            setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
        case .resizeRight:
            // 좌측 가장자리를 고정하고 우측을 마우스를 따라 늘린다.
            let width = clamped(mouse.x - frame.origin.x)
            setFrame(
                NSRect(x: frame.origin.x, y: frame.origin.y, width: width, height: frame.height),
                display: true
            )
            onResize?(width)
        case .resizeLeft(let rightEdgeX):
            // 우측 가장자리를 고정하고 좌측을 마우스를 따라 늘린다.
            let width = clamped(rightEdgeX - mouse.x)
            setFrame(
                NSRect(x: rightEdgeX - width, y: frame.origin.y, width: width, height: frame.height),
                display: true
            )
            onResize?(width)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isBusy else { return }
        gesture = .none
        onDragEnd?(frame.origin)
    }

    private func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }
}

/// 좌우 가장자리 호버에 좌우 리사이즈 커서를 띄우는 호스팅 뷰. 커서
/// 사각형은 창 폭을 따라 바뀌므로 폭이 바뀔 때마다 다시 계산하게 한다.
final class PanelHostingView: NSHostingView<AnyView> {
    override func resetCursorRects() {
        super.resetCursorRects()
        let slop = NotchPanel.edgeHitSlop
        addCursorRect(
            NSRect(x: 0, y: 0, width: slop, height: bounds.height),
            cursor: .resizeLeftRight
        )
        addCursorRect(
            NSRect(x: bounds.width - slop, y: 0, width: slop, height: bounds.height),
            cursor: .resizeLeftRight
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if window != nil {
            window?.invalidateCursorRects(for: self)
        }
    }
}

/// 패널 생명주기와 위치를 SlotStore 상태에 맞춘다. 노치 패널 토글이 꺼져
/// 있으면 패널을 만들지도 않고, 보여줄 에이전트가 없으면 숨긴다.
/// 크기는 SwiftUI(NotchPanelView)가 폭=store.notchPanelWidth·높이=내용
/// 맞춤으로 정하고 NSHostingView가 창에 반영하므로, 이 컨트롤러와
/// NotchPanel 제스처는 위치(원점)만 소유한다.
/// NSPanel 조작은 메인에서만 하므로 MainActor로 격리한다.
@MainActor
final class NotchPanelController {
    static let minPanelWidth: CGFloat = 220
    static let maxPanelWidth: CGFloat = 600
    static let notchPanelOriginKey = "notchPanelOrigin"

    private let store: SlotStore
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    /// 상단 가장자리 고정 앵커. 콘텐츠 높이가 변해도 패널이 아래로만 자라게
    /// 한다. 노치 바로 아래 배치의 핵심 불변식이다.
    private var topAnchor: CGFloat?
    private var resizeObserver: NSObjectProtocol?

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
        // 이동·리사이즈 중 재배치하면 창이 손가락 밖으로 튄다.
        if let panel, panel.isBusy { return }
        layout()
        panel?.orderFrontRegardless()
    }

    /// 토글이 켜진 첫 순간에만 패널을 만든다. 끄고 있는 동안엔 창이 없다.
    private func ensurePanel() -> NotchPanel {
        if let panel { return panel }
        let hostingView = PanelHostingView(
            rootView: AnyView(NotchPanelView().environmentObject(store))
        )
        let panel = NotchPanel(content: hostingView)
        panel.minWidth = Self.minPanelWidth
        panel.maxWidth = Self.maxPanelWidth
        panel.onResize = { [weak self] width in
            // 폭만 Store에 반영하면 SwiftUI가 창 폭을 따라 바꾼다.
            // 원점은 패널 제스처가 이미 정했다.
            self?.store.notchPanelWidth = width
        }
        panel.onDragEnd = { [weak self] origin in
            // 이동·리사이즈로 확정된 위치만 저장한다(기본 상단 중앙 배치는
            // 저장 안 함). 좌측 리사이즈는 원점이 움직이므로 여기서 같이 저장된다.
            UserDefaults.standard.set(
                NSStringFromPoint(origin),
                forKey: Self.notchPanelOriginKey
            )
            self?.topAnchor = origin.y + (self?.panel?.frame.height ?? 0)
        }
        // 콘텐츠 크기 변화(SwiftUI가 창 크기를 바꾼 시점)에 상단 가장자리를
        // 도로 붙잡아 패널이 아래로만 자라게 한다.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.anchorToTop() }
        }
        self.panel = panel
        return panel
    }

    /// 패널 위치를 정한다. 명시된 원점(제스처 직후) > 저장된 원점 > 상단 중앙.
    /// 높이는 아직 SwiftUI가 정하기 전일 수 있어 didResize 앵커가 마저 맞춘다.
    private func layout(using explicitOrigin: NSPoint? = nil) {
        let panel = ensurePanel()
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin: NSPoint
        if let explicitOrigin {
            origin = explicitOrigin
        } else if let saved = savedOrigin {
            origin = saved
        } else {
            origin = NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.maxY - 6 - panel.frame.height
            )
        }
        panel.setFrameOrigin(origin)
        topAnchor = origin.y + panel.frame.height

        // TODO: 노치가 있는 맥에서는 screen.auxiliaryTopLeftArea와
        // auxiliaryTopRightArea로 실제 노치 영역 폭을 잡아 그 아래 중앙에
        // 배치한다. 지금은 저장 위치가 없으면 보이는 화면 기준 상단 중앙 고정이다.
    }

    /// didResize에서 상단 고정. 제스처 중에는 제스처가 위치를 소유한다.
    private func anchorToTop() {
        guard
            let panel, !panel.isBusy,
            let top = topAnchor,
            abs(panel.frame.maxY - top) > 0.5
        else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x, y: top - panel.frame.height))
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
