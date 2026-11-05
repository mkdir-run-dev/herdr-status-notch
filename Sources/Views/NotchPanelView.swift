import SwiftUI

/// 노치 아래 스페이스별 에이전트 목록(잠든 스페이스 포함, idle 포함). 행을
/// 탭하면 해당 에이전트 터미널로 포커스가 옮겨진다. 보여 줄 에이전트가
/// 없으면 NotchPanelController가 패널을 숨긴다.
struct NotchPanelView: View {
    @EnvironmentObject private var store: SlotStore

    /// 심각도(blocked → working → done → idle → unknown)순, 동률은 이름순.
    private func sortedAgents(_ space: SpaceChip) -> [AgentSlot] {
        space.agents.sorted {
            $0.status.sortRank == $1.status.sortRank
                ? $0.displayName < $1.displayName
                : $0.status.sortRank < $1.status.sortRank
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("전체 스페이스 \(store.spaces.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Divider()
            ForEach(store.spaces) { space in
                VStack(alignment: .leading, spacing: 4) {
                    SpaceSectionHeader(space: space)
                    ForEach(sortedAgents(space)) { slot in
                        SlotRowView(slot: slot)
                            .contentShape(Rectangle())
                            .onTapGesture { store.focus(slot) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: NotchPanelController.panelWidth - 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 섹션 머리 = 에이전트 종류 요약 + 소속 신호 에이전트 상태 점들. 신호가
/// 없는 잠든 스페이스는 점이 없고 라벨만 옅게 남는다.
private struct SpaceSectionHeader: View {
    let space: SpaceChip

    var body: some View {
        HStack(spacing: 6) {
            Text(space.agentKindsLabel)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(space.signalAgents) { agent in
                    Circle()
                        .fill(agent.status.color)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .opacity(space.signalAgents.isEmpty ? 0.55 : 1)
    }
}

/// 한 슬롯 = 상태 색 점 + 이름 + 프로젝트 + 작업명 한 줄.
struct SlotRowView: View {
    let slot: AgentSlot

    private var projectName: String? {
        slot.cwd.map { ($0 as NSString).lastPathComponent }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(slot.status.color)
                .frame(width: 9, height: 9)
            Text(slot.displayName)
                .font(.system(size: 13, weight: .semibold))
            if let project = projectName {
                Text(project)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let task = slot.taskTitle {
                Text(task)
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
