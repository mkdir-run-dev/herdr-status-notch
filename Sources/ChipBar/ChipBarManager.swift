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
        // 메뉴 내용은 여는 시점에 최신 상태로 구성한다(menuNeedsUpdate).
        // 폴링마다 NSMenu를 다시 만들면 열려 있는 메뉴가 닫힌다.
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.identifier = NSUserInterfaceItemIdentifier(workspaceID)
        item.menu = menu
        items[workspaceID] = item
        return item
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

    /// 칩 하나를 캡슐 배경 + 상태 점들(7pt) + 라벨(12pt medium) 비트맵으로 그린다.
    /// idle은 신호가 아니라 점에서 제외된다(signalAgents가 이미 걸렀다).
    private func renderChip(_ chip: SpaceChip, appearance: NSAppearance) -> NSImage {
        let signals = chip.signalAgents
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let label = chip.workspace.label as NSString
        let labelSize = label.size(withAttributes: labelAttributes)

        let dot: CGFloat = 7
        let dotGap: CGFloat = 4
        let innerGap: CGFloat = 6
        let hPadding: CGFloat = 9
        let height: CGFloat = 16
        let dotsWidth = signals.isEmpty
            ? 0
            : CGFloat(signals.count) * (dot + dotGap) - dotGap
        let width = hPadding + dotsWidth + (signals.isEmpty ? 0 : innerGap) + labelSize.width + hPadding

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

                var x = hPadding
                for agent in signals {
                    agent.status.nsColor.setFill()
                    NSBezierPath(
                        ovalIn: NSRect(x: x, y: (height - dot) / 2, width: dot, height: dot)
                    ).fill()
                    x += dot + dotGap
                }

                let textX = signals.isEmpty ? hPadding : hPadding + dotsWidth + innerGap
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

extension ChipBarManager: NSMenuDelegate {
    /// 칩 클릭으로 열리는 스페이스 전용 메뉴. 소속 에이전트 전원(idle 포함)과
    /// 스페이스 포커스 항목을 채운다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard
            let id = menu.identifier?.rawValue,
            let chip = store.spaces.first(where: { $0.workspace.workspaceId == id })
        else { return }

        menu.removeAllItems()
        for agent in chip.agents {
            let title = agent.terminalTitle.map { "\(agent.displayName) - \($0)" } ?? agent.displayName
            let item = NSMenuItem(
                title: title,
                action: #selector(focusAgentAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = agent.name != nil
            item.representedObject = agent.name
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let workspaceItem = NSMenuItem(
            title: "스페이스 포커스",
            action: #selector(focusWorkspaceAction(_:)),
            keyEquivalent: ""
        )
        workspaceItem.target = self
        workspaceItem.representedObject = chip.workspace.workspaceId
        menu.addItem(workspaceItem)
    }

    @objc private func focusAgentAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.focusAgent(named: name)
    }

    @objc private func focusWorkspaceAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.focusWorkspace(id)
    }
}
