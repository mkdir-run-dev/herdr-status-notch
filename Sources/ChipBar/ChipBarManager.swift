import AppKit
import Combine
import os

/// 메뉴바 칩 한 줄을 NSStatusItem '하나'에 통째로 그린다. 칩마다 항목을
/// 따로 만들면 구성이 바뀔 때마다 삭제·재생성이 일어나고, 새 항목의 위치는
/// 시스템이 정하기 때문에 다른 앱의 메뉴바 항목(oMLX·Tailscale 같은)이
/// 칩 사이에 끼어드는 일이 벌어진다. 항목이 하나면 배열은 그린 순서 그대로
/// 확정되고 순서 변화도 이미지 교체 한 번으로 끝난다. 클릭은 이벤트의
/// x좌표로 어느 칩인지 찾아 그 스페이스로 포커스를 보낸다.
@MainActor
final class ChipBarManager: NSObject {
    private let store: SlotStore
    private var item: NSStatusItem?
    /// 마지막으로 그린 칩 구성. 변화가 없으면 재렌더를 건너뛴다.
    private var lastChips: [SpaceChip] = []
    /// (id, x, 폭). 클릭 히트 테스트용이고 순서는 화면 순서와 같다.
    private var chipHitFrames: [(id: String, x: CGFloat, width: CGFloat)] = []
    /// 칩 사이 간격(pt).
    private static let gap: CGFloat = 6
    /// 메뉴바 위치 저장용 autosaveName. 이 이름으로 시스템이 위치 키를
    /// 만든다(NSStatusItem Preferred Position <이름>).
    private static let autosaveName = "local.herdr.statusnotch.chips"
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
        let chips = store.chips

        // 신호가 없으면 항목 자체를 내린다(메뉴바에 빈 자리가 남지 않게).
        guard !chips.isEmpty else {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
            lastChips = []
            chipHitFrames = []
            return
        }

        let item = self.item ?? makeItem()
        guard chips != lastChips else { return }
        lastChips = chips

        let appearance = item.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        var bitmaps: [(image: NSImage, x: CGFloat)] = []
        var hit: [(id: String, x: CGFloat, width: CGFloat)] = []
        var x: CGFloat = 0
        for chip in chips {
            let image = renderChip(chip, appearance: appearance)
            bitmaps.append((image, x))
            hit.append((chip.id, x, image.size.width))
            x += image.size.width + Self.gap
        }
        chipHitFrames = hit
        let total = x - Self.gap

        let composite = NSImage(
            size: NSSize(width: total, height: ChipMetrics.height),
            flipped: false
        ) { _ in
            // 이미지 캐싱으로 그리기 시점이 늦어져도 다크·라이트 색이 뒤바뀌지
            // 않게 그리기 클로저 안에서 모양을 고정한다.
            appearance.performAsCurrentDrawingAppearance {
                for (image, imageX) in bitmaps {
                    image.draw(at: NSPoint(x: imageX, y: 0), from: .zero,
                               operation: .sourceOver, fraction: 1)
                }
            }
            return true
        }
        if let button = item.button {
            button.image = composite
            button.imageScaling = .scaleNone
        }
        item.length = total
    }

    private func makeItem() -> NSStatusItem {
        // autosaveName을 주면 시스템이 메뉴바 위치를 기억·복원한다. 첫
        // 실행엔 왼쪽 끝(0)으로 심어 칩 스트립이 상태 항목 영역 맨 왼쪽에
        // 뜨게 하고, 이후 사용자가 ⌘-드래그로 직접 옮기면 그 값이 우선한다.
        let positionKey = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(0.0, forKey: positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        if let button = item.button {
            button.target = self
            button.action = #selector(stripClicked(_:))
        }
        self.item = item
        return item
    }

    /// 클릭 x좌표로 어느 칩인지 찾아 그 스페이스로 포커스를 옮긴다.
    /// 드롭다운을 거치면 클릭 한 번이 메뉴 열기 + 항목 선택 두 단계가
    /// 되므로 클릭 자체를 스페이스 포커스로 보낸다. NSApp.currentEvent는
    /// 액션 시점에 클릭이 아닌 이벤트를 주는 수가 있어(실측) 마우스의
    /// 전역 좌표를 읽어 창→버튼 순으로 변환해 쓴다.
    @objc private func stripClicked(_ sender: NSButton) {
        guard let button = item?.button, let window = button.window else { return }
        let point = button.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        Self.logger.notice("클릭: point.x=\(point.x, privacy: .public) frames=\(self.chipHitFrames.map { "\($0.id)@\($0.x)+\($0.width)" }.joined(separator: " "), privacy: .public)")
        for frame in chipHitFrames
        where point.x >= frame.x && point.x < frame.x + frame.width {
            store.focusWorkspace(frame.id)
            return
        }
    }

    private static let logger = Logger(subsystem: "local.herdr.statusnotch", category: "chip")

    /// 칩 하나를 캡슐 배경 + 대표 상태 점 1개 + 라벨 비트맵으로 그린다.
    /// 점은 worstStatus(주의도순 첫 신호 에이전트) 하나뿐이고 라벨은
    /// ChipMetrics 폭(예산 계산과 같은 값)으로 잘라 그린다.
    private func renderChip(_ chip: SpaceChip, appearance: NSAppearance) -> NSImage {
        let label = ChipMetrics.truncatedLabel(chip.workspace.label) as NSString
        let labelSize = label.size(withAttributes: ChipMetrics.labelAttributes)

        let dot = ChipMetrics.dot
        let innerGap = ChipMetrics.innerGap
        let hPadding = ChipMetrics.hPadding
        let height = ChipMetrics.height
        let hasDot = chip.worstStatus != nil
        let width = ChipMetrics.chipWidth(label: label as String, hasDot: hasDot)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
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
                    withAttributes: ChipMetrics.labelAttributes
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
