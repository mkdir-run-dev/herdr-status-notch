import AppKit

/// 칩 폭·라벨 잘림 계산의 단일 출처. SlotStore의 폭 예산 선정과
/// ChipBarManager의 렌더링이 같은 식을 쓰게 한다(두 계산이 어긋나면
/// 예산이 맞아도 실제 칩이 넘친다).
enum ChipMetrics {
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    /// 라벨 그리기·측정 공용 속성. 폰트가 같아야 폭 계산이 유효하다.
    static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.labelColor,
    ]

    static let dot: CGFloat = 8
    static let innerGap: CGFloat = 6
    static let hPadding: CGFloat = 10
    static let height: CGFloat = 18
    /// 라벨 최대폭(pt). 넘는 라벨은 "…"로 잘라 칩 하나의 폭 상한을
    /// 보장한다. 잘리지 않은 전체 라벨은 칩 tooltip에서 본다.
    static let maxLabelWidth: CGFloat = 110

    /// 라벨의 측정 폭.
    static func width(of label: String) -> CGFloat {
        ceil((label as NSString).size(withAttributes: labelAttributes).width)
    }

    /// 라벨을 maxLabelWidth 안에 들어가게 끝을 "…"로 자른 값.
    /// 이미 들어가면 그대로 돌려준다.
    static func truncatedLabel(_ label: String) -> String {
        guard width(of: label) > maxLabelWidth else { return label }
        var head = label
        while !head.isEmpty {
            head.removeLast()
            if width(of: head + "…") <= maxLabelWidth { return head + "…" }
        }
        return "…"
    }

    /// 칩 전체 폭. 좌우 패딩 + (점이 있으면 점·간격) + 라벨.
    /// renderChip의 이미지 폭과 정확히 같은 식이어야 한다.
    static func chipWidth(label: String, hasDot: Bool) -> CGFloat {
        ceil(hPadding + (hasDot ? dot + innerGap : 0) + width(of: label) + hPadding)
    }
}
