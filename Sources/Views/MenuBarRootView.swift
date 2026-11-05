import AppKit
import SwiftUI

/// 메뉴바 위젯 콘텐츠. 슬롯 목록, 초과분 안내, 오프라인 경고, 종료 항목.
/// window 스타일을 쓴 이유는 색 점과 빨간 오프라인 행 같은 커스텀 행이
/// 기본 NSMenu 스타일에서는 제대로 그려지지 않기 때문이다.
struct MenuBarRootView: View {
    @EnvironmentObject private var store: SlotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.connection == .offline {
                Label("herdr 오프라인", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(ConnectionState.offline.color)
            }

            ForEach(store.slots) { slot in
                MenuSlotRowView(slot: slot)
            }

            if store.overflowCount > 0 {
                Text("\(store.overflowCount) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }

            Divider()
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 6)
        .frame(width: 260)
    }
}

/// 메뉴바의 슬롯 행. 탭하면 해당 에이전트 터미널로 포커스가 옮겨진다.
private struct MenuSlotRowView: View {
    let slot: AgentSlot
    @EnvironmentObject private var store: SlotStore

    var body: some View {
        Button {
            store.focus(slot)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(slot.status.color)
                    .frame(width: 7, height: 7)
                Text(slot.displayName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let title = slot.terminalTitle {
                    Text(title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
