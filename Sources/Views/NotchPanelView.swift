import SwiftUI

/// 노치 아래 스페이스 섹션 평탄 목록(잠든 스페이스 포함). 섹션 헤더를 탭하면
/// 해당 스페이스로, 탭 행을 탭하면 해당 탭으로 포커스가 옮겨진다. 개별
/// 에이전트 포커스는 칩 메뉴가 담당한다. 보여 줄 스페이스가 없으면
/// NotchPanelController가 패널을 숨긴다.
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
                    SpaceSectionView(space: space)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: NotchPanelController.panelWidth - 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 스페이스 하나 = 헤더 줄(대표 상태 점·스페이스명·종류 요약) + 탭 행들.
/// 탭 키가 없는 snapshot이면 헤더만 남는다. 신호가 없는 스페이스는 헤더에
/// 점이 없고 섹션 전체를 옅게 표시한다.
private struct SpaceSectionView: View {
    @EnvironmentObject private var store: SlotStore
    let space: SpaceChip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
            .contentShape(Rectangle())
            .onTapGesture { store.focusWorkspace(space.id) }
            ForEach(space.tabs) { tab in
                TabRowView(tab: tab)
                    .padding(.leading, 8)
            }
        }
        .opacity(isAsleep ? 0.55 : 1)
    }

    private var isAsleep: Bool {
        space.signalAgents.isEmpty
    }
}

/// 탭 행: 상태 점·탭명·작업요약·모델 종류 한 줄. 탭을 탭하면 그 탭으로 포커스.
private struct TabRowView: View {
    @EnvironmentObject private var store: SlotStore
    let tab: TabChip

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(tab.tab.displayName)
                .font(.system(size: 12, weight: .semibold))
            if let summary = tab.taskSummary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if let models = tab.modelLabel {
                Text(models)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.focusTab(tab.id) }
    }

    /// idle의 상태 색(흰색)은 활성 신호처럼 읽혀 탭 점은 회색으로 낮춘다.
    private var dotColor: Color {
        tab.status == .idle ? .secondary : tab.status.color
    }
}
