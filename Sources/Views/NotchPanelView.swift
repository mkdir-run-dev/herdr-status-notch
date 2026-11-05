import SwiftUI

/// 노치 아래 전체 에이전트 목록(잠든 스페이스 포함, idle 포함). 행을 탭하면
/// 해당 에이전트 터미널로 포커스가 옮겨진다. 보여 줄 에이전트가 없으면
/// NotchPanelController가 패널을 숨긴다.
struct NotchPanelView: View {
    @EnvironmentObject private var store: SlotStore

    /// 심각도(blocked → working → done → idle → unknown)순, 동률은 이름순.
    private var agents: [AgentSlot] {
        store.spaces
            .flatMap(\.agents)
            .sorted {
                $0.status.sortRank == $1.status.sortRank
                    ? $0.displayName < $1.displayName
                    : $0.status.sortRank < $1.status.sortRank
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("전체 에이전트 \(agents.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Divider()
            ForEach(agents) { slot in
                SlotRowView(slot: slot)
                    .contentShape(Rectangle())
                    .onTapGesture { store.focus(slot) }
            }
        }
        .padding(12)
        .frame(maxWidth: NotchPanelController.panelWidth - 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 한 슬롯 = 상태 색 점 + 이름 + 터미널 제목 한 줄.
struct SlotRowView: View {
    let slot: AgentSlot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(slot.status.color)
                .frame(width: 9, height: 9)
            Text(slot.displayName)
                .font(.system(size: 13, weight: .semibold))
            if let title = slot.terminalTitle {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }
}
