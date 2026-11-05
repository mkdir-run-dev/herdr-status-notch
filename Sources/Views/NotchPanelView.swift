import SwiftUI

/// 노치 아래 스페이스별 두 줄 행 평탄 목록(잠든 스페이스 포함). 행을 탭하면
/// 해당 스페이스로 포커스가 옮겨진다. 개별 에이전트 포커스는 칩 메뉴가
/// 담당한다. 보여 줄 스페이스가 없으면 NotchPanelController가 패널을 숨긴다.
struct NotchPanelView: View {
    @EnvironmentObject private var store: SlotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("전체 스페이스 \(store.spaces.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(store.spaces) { space in
                    SpaceRowView(space: space)
                        .contentShape(Rectangle())
                        .onTapGesture { store.focusWorkspace(space.id) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: NotchPanelController.panelWidth - 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 스페이스 하나 = 1호선(대표 상태 점·스페이스명·종류 요약) + 2호선(작업요약).
/// 신호가 없는 스페이스는 점·요약이 없어 이름만 남고 옅게 표시한다.
private struct SpaceRowView: View {
    let space: SpaceChip

    private var isAsleep: Bool {
        space.signalAgents.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let status = space.worstStatus {
                    Circle()
                        .fill(status.color)
                        .frame(width: 9, height: 9)
                }
                Text(space.workspace.label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Text(space.agentKindsLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let summary = space.signalTaskSummary {
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 15)
            }
        }
        .opacity(isAsleep ? 0.55 : 1)
    }
}
