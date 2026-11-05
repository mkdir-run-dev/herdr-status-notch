import AppKit
import Combine

/// 워크스페이스별 NSStatusItem로 메뉴바 칩을 띄운다. 폴링마다 항목을 새로
/// 만들지 않고 workspace id 기준으로 생성·삭제·내용 갱신만 해서 깜빡임과
/// 누수를 막는다. 칩 순서는 첫 등장 순서를 유지한다(재배치 없음).
@MainActor
final class ChipBarManager: NSObject {
    private let store: SlotStore
    private var items: [String: NSStatusItem] = [:]
    /// 마지막으로 그린 칩. 변화가 없으면 비트맵 재렌더를 건너뛴다.
    private var lastChips: [String: SpaceChip] = [:]
    private var cancellable: AnyCancellable?

    init(store: SlotStore) {
        self.store = store
        super.init()
        // @Published는 willSet 시점에 방출하므로 메인 런루프로 한 틱 미뤄
        // 갱신된 값을 읽는다.
        cancellable = store.$chips
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.apply() }
            }
    }

    private func apply() {
        var seen = Set<String>()
        for chip in store.chips {
            let id = chip.workspace.workspaceId
            seen.insert(id)
            let item = items[id] ?? makeItem(workspaceID: id)
            update(item: item, chip: chip)
        }
        let orphans = items.keys.filter { !seen.contains($0) }
        for id in orphans {
            lastChips.removeValue(forKey: id)
            if let item = items.removeValue(forKey: id) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
    }

    private func makeItem(workspaceID: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        items[workspaceID] = item
        // 드롭다운을 거치면 클릭 한 번이 메뉴 열기 + 항목 선택 두 단계가
        // 되므로 클릭 자체를 스페이스 포커스로 보낸다.
        if let button = item.button {
            button.identifier = NSUserInterfaceItemIdentifier(workspaceID)
            button.target = self
            button.action = #selector(chipClicked(_:))
        }
        return item
    }

    @objc private func chipClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        store.focusWorkspace(id)
    }

    private func update(item: NSStatusItem, chip: SpaceChip) {
        guard let button = item.button else { return }
        // 0.7초마다 비트맵을 다시 그리면 안정 상태에서도 메뉴바 이미지
        // 교체 churn이 계속되므로 칩 내용이 같으면 건너뛴다.
        if lastChips[chip.id] == chip { return }
        lastChips[chip.id] = chip
        button.image = renderChip(chip, appearance: button.effectiveAppearance)
        button.toolTip = chip.workspace.label
    }

    /// 칩 하나를 캡슐 배경 + 대표 상태 점 1개 + 라벨 비트맵으로 그린다.
    /// 점은 worstStatus(심각도순 첫 신호 에이전트) 하나뿐이다.
    private func renderChip(_ chip: SpaceChip, appearance: NSAppearance) -> NSImage {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let label = chip.workspace.label as NSString
        let labelSize = label.size(withAttributes: labelAttributes)

        let dot: CGFloat = 8
        let innerGap: CGFloat = 6
        let hPadding: CGFloat = 10
        let height: CGFloat = 18
        let hasDot = chip.worstStatus != nil
        let width = hPadding + (hasDot ? dot + innerGap : 0) + labelSize.width + hPadding

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { rect in
            // 이미지 캐싱으로 그리기 시점이 늦어져도 다크·라이트 색이 뒤바뀌지
            // 않게 그리기 클로저 안에서 모양을 고정한다.
            appearance.performAsCurrentDrawingAppearance {
                let capsule = NSBezierPath(
                    roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                    xRadius: rect.height / 2,
                    yRadius: rect.height / 2
                )
                NSColor.windowBackgroundColor.setFill()
                capsule.fill()
                NSColor.separatorColor.setStroke()
                capsule.lineWidth = 1
                capsule.stroke()

                if let status = chip.worstStatus {
                    status.nsColor.setFill()
                    NSBezierPath(
                        ovalIn: NSRect(x: hPadding, y: (height - dot) / 2, width: dot, height: dot)
                    ).fill()
                }

                let textX = hasDot ? hPadding + dot + innerGap : hPadding
                label.draw(
                    at: NSPoint(x: textX, y: (height - labelSize.height) / 2),
                    withAttributes: labelAttributes
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
