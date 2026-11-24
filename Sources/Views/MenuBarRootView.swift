import AppKit
import SwiftUI

/// 앱 아이콘 드롭다운 콘텐츠. offline 경고, 스페이스 지도, 노치 패널·
/// 로그인 시 시작 토글과 종료 순서다. window 스타일을 쓰는 이유는 색 점과 빨간 offline
/// 행 같은 커스텀 행이 기본 NSMenu 스타일에서는 제대로 그려지지
/// 않기 때문이다.
struct MenuBarRootView: View {
    @EnvironmentObject private var store: SlotStore
    // 로그인 항목은 시스템 설정이 소유하는 값이라 뷰 상태로만 들고 온다.
    @State private var startsAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.connection == .offline {
                Label(store.t(.offlineMode, store.mode.displayName), systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(ConnectionState.offline.color)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 10))
                        Text(store.t(.spacesHeader, store.spaces.count))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    Text(store.t(.spacesHint))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
                .padding(.bottom, 2)

                if store.spaces.isEmpty {
                    Text(store.t(.noSpaces))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.spaces) { chip in
                        SpaceMapRow(chip: chip)
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 2) {
                // 라벨은 좌측, 스위치는 우측 끝('대기' 태그와 같은 결)에 둔다.
                // 시스템 스위치는 크기 조절이 없어 80%로 축소해 메뉴 글자
                // 크기와 균형을 맞춘다.
                HStack {
                    Text(store.t(.notchPanelToggle)).font(.system(size: 13))
                    Spacer(minLength: 8)
                    Toggle("", isOn: $store.notchPanelEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                }
                HStack {
                    Text(store.t(.startAtLoginToggle)).font(.system(size: 13))
                    Spacer(minLength: 8)
                    Toggle("", isOn: $startsAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                        .onAppear { startsAtLogin = LoginItemService.shared.isEnabled }
                        .onChange(of: startsAtLogin) { _, on in
                            LoginItemService.shared.setEnabled(on)
                        }
                }
                HStack {
                    Text(store.t(.modeLabel)).font(.system(size: 13))
                    Spacer(minLength: 8)
                    Picker("", selection: Binding(get: { store.mode }, set: { store.pickMode($0) })) {
                        ForEach(HerdrMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
                HStack {
                    Text(store.t(.languageLabel)).font(.system(size: 13))
                    Spacer(minLength: 8)
                    // 언어 이름 자체는 각 언어 표기(한국어·English)를 그대로
                    // 쓰고 시스템 옵션만 현재 언어로 적는다.
                    Picker("", selection: $store.language) {
                        Text(store.t(.languageSystemOption)).tag(AppLanguage.system)
                        Text("한국어").tag(AppLanguage.korean)
                        Text("English").tag(AppLanguage.english)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    // 누를 수 있는 행은 비활성 회색이 아니라 기본 색으로.
                    Text(store.t(.quit))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(RowButtonStyle())
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 8)
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

/// 스페이스 지도 행. 대표 상태 점(worstStatus) + 라벨, 잠든 스페이스는
/// 오른쪽 '대기' 태그로 구분한다. 탭하면 그 스페이스로 포커스가 옮겨진다.
private struct SpaceMapRow: View {
    let chip: SpaceChip
    @EnvironmentObject private var store: SlotStore

    var body: some View {
        Button {
            store.focusWorkspace(chip.id)
        } label: {
            HStack {
                if let status = chip.worstStatus {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                }
                Text(chip.workspace.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if chip.signalAgents.isEmpty {
                    Text(store.t(.idleTag))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.08))
                        )
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .opacity(chip.signalAgents.isEmpty ? 0.55 : 1)
    }
}
