import AppKit
import Combine
import SwiftUI

/// 반대 모드가 실행 중일 때 한 번만 띄우는 전환 제안. 노치 패널과 같은 비활성화
/// 플로팅 창이라 폴링·메뉴바를 막지 않고 포커스도 빼앗지 않는다.
@MainActor
final class ModeSwitchPromptController {
    private let store: SlotStore
    private var panel: PromptPanel?
    private var cancellables = Set<AnyCancellable>()

    init(store: SlotStore) {
        self.store = store

        // @Published는 willSet 시점에 방출하므로 메인 런루프로 한 틱 미뤄
        // 갱신된 값을 읽는다.
        store.$suggestedModeSwitch
            .receive(on: RunLoop.main)
            .sink { [weak self] suggested in
                Task { @MainActor in self?.sync(suggested) }
            }
            .store(in: &cancellables)
    }

    private func sync(_ suggested: HerdrMode?) {
        dismiss()
        guard let suggested else { return }

        let hosting = NSHostingView(
            rootView: ModeSwitchPromptView(target: suggested).environmentObject(store)
        )
        let size = hosting.fittingSize
        let panel = PromptPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.contentView = hosting
        // 노치 패널(상단 중앙)과 겹치지 않도록 보이는 화면의 오른쪽 위에 둔다.
        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - 12,
                y: visible.maxY - size.height - 8
            ))
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// 키 창이 되지 않는 플로팅 패널. 활성 앱의 키보드 포커스를 그대로 둔다.
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

private struct ModeSwitchPromptView: View {
    @EnvironmentObject private var store: SlotStore
    let target: HerdrMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t(.otherModePromptTitle, target.displayName))
                .font(.system(size: 12, weight: .semibold))
            Text(store.t(.otherModePromptMessage, store.mode.displayName, target.displayName))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                button(store.t(.otherModePromptKeep), prominent: false) {
                    store.dismissSuggestedModeSwitch()
                }
                Spacer(minLength: 0)
                button(store.t(.otherModePromptSwitch, target.displayName), prominent: true) {
                    store.acceptSuggestedModeSwitch()
                }
            }
        }
        .padding(12)
        .frame(width: 272)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 키 창이 아닌 패널이라 Button 대신 탭 제스처로 눌림을 받는다.
    private func button(
        _ title: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(prominent ? Color.accentColor : Color.primary.opacity(0.1))
            )
            .fixedSize()
            .contentShape(Capsule())
            .onTapGesture(perform: action)
    }
}
