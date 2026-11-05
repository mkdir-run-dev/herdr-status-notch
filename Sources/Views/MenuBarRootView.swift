import AppKit
import SwiftUI

/// 앱 아이콘 드롭다운 콘텐츠. offline 경고, 대기 중 에이전트, 노치 패널
/// 토글과 종료 순서다. window 스타일을 쓰는 이유는 색 점과 빨간 offline
/// 행 같은 커스텀 행이 기본 NSMenu 스타일에서는 제대로 그려지지
/// 않기 때문이다.
struct MenuBarRootView: View {
    @EnvironmentObject private var store: SlotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.connection == .offline {
                Label("herdr 오프라인", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(ConnectionState.offline.color)
            } else if store.idleAgents.isEmpty {
                Label("대기 없음 — 전원 가동 중", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                        Text("대기 중 에이전트 \(store.idleAgents.count)")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    Text("클릭하면 해당 터미널로 이동")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
                .padding(.bottom, 2)

                ForEach(store.idleAgents) { slot in
                    IdleAgentRow(slot: slot)
                }
            }

            Divider()
            Toggle("노치 패널", isOn: $store.notchPanelEnabled)
                .toggleStyle(.switch)
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 300)
    }
}

/// 드롭다운 행 공용 피드백. 호버는 옅은 배경, 눌림은 더 진한 배경을
/// RoundedRectangle 6으로 채운다. Color.primary 비율이라 라이트·다크
/// 모드 모두 대비가 유지된다.
private struct RowButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovered ? 0.08 : 0))
            )
            .onHover { hovered = $0 }
    }
}

/// 대기(idle) 에이전트 행. 이름 왼쪽, 프로젝트(cwd 마지막 컴포넌트)
/// 오른쪽. 탭하면 해당 에이전트 터미널로 포커스가 옮겨진다.
private struct IdleAgentRow: View {
    let slot: AgentSlot
    @EnvironmentObject private var store: SlotStore

    private var projectName: String? {
        slot.cwd.map { ($0 as NSString).lastPathComponent }
    }

    private var row: some View {
        HStack {
            Text(slot.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let project = projectName {
                Text(project)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    var body: some View {
        // herdr agent focus는 name을 인자로 받는다. name 없는 에이전트는
        // 지목할 대상이 없어 눌리지 않는 행으로 나둔다.
        if let name = slot.name {
            Button {
                store.focusAgent(named: name)
            } label: {
                row
            }
            .buttonStyle(RowButtonStyle())
        } else {
            row
                .opacity(0.4)
        }
    }
}
