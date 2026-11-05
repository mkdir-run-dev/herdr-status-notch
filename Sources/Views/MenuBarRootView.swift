import AppKit
import SwiftUI

/// 앱 아이콘 드롭다운 콘텐츠. offline 경고, 대기 중 에이전트, 전체 스페이스
/// 목록, 노치 패널 토글과 종료 순서다. window 스타일을 쓰는 이유는 색 점과
/// 빨간 offline 행 같은 커스텀 행이 기본 NSMenu 스타일에서는 제대로
/// 그려지지 않기 때문이다.
struct MenuBarRootView: View {
    @EnvironmentObject private var store: SlotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.connection == .offline {
                Label("herdr 오프라인", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(ConnectionState.offline.color)
            }

            if !store.idleAgents.isEmpty {
                sectionHeader("대기 중 에이전트 \(store.idleAgents.count)")
                ForEach(store.idleAgents) { slot in
                    IdleAgentRow(slot: slot)
                }
            }

            sectionHeader("스페이스")
            ForEach(store.spaces) { chip in
                SpaceRow(chip: chip)
            }
            if store.overflowCount > 0 {
                Text("\(store.overflowCount) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }

            Divider()
            Toggle("노치 패널", isOn: $store.notchPanelEnabled)
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 6)
        .frame(width: 280)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }
}

/// 대기(idle) 에이전트 행. 이름 · 프로젝트(cwd 마지막 컴포넌트) · 터미널 제목.
/// 탭하면 해당 에이전트 터미널로 포커스가 옮겨진다.
private struct IdleAgentRow: View {
    let slot: AgentSlot
    @EnvironmentObject private var store: SlotStore

    private var projectName: String? {
        slot.cwd.map { ($0 as NSString).lastPathComponent }
    }

    var body: some View {
        let content = HStack(spacing: 8) {
            Text(slot.displayName)
                .lineLimit(1)
            if let project = projectName {
                Text(project)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let title = slot.terminalTitle {
                Text(title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 6)

        // herdr agent focus는 name을 인자로 받는다. name 없는 에이전트는
        // 지목할 대상이 없어 눌리지 않는 행으로 나둔다.
        if let name = slot.name {
            Button {
                store.focusAgent(named: name)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
                .opacity(0.4)
        }
    }
}

/// 스페이스 행. 숨겨진 잠든 스페이스(idle뿐)는 흐리게 보여 준다.
/// 탭하면 herdr workspace focus로 그 스페이스에 포커스를 옮긴다.
private struct SpaceRow: View {
    let chip: SpaceChip
    @EnvironmentObject private var store: SlotStore

    var body: some View {
        Button {
            store.focusWorkspace(chip.workspace.workspaceId)
        } label: {
            HStack(spacing: 8) {
                Text("\(chip.workspace.number)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(chip.workspace.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(chip.isVisible ? 1 : 0.4)
        .padding(.horizontal, 6)
    }
}
