import Foundation

/// 노치가 지켜보는 herdr 실행 형태. 드롭다운에서 고르고 UserDefaults에 남는다.
enum HerdrMode: String, CaseIterable, Identifiable, Sendable {
    case tui
    case app

    var id: String { rawValue }

    /// 제품 고유명이라 언어 설정과 무관하게 그대로 표기한다.
    var displayName: String {
        switch self {
        case .tui: "Herdr TUI"
        case .app: "Herdr App"
        }
    }

    /// 클릭 시 앞으로 가져올 GUI. TUI 모드의 이동 대상은 Rex(herdr GUI)다.
    var targetBundleIdentifier: String {
        switch self {
        case .tui: "com.superlogical.rex"
        case .app: "dev.herdr.app"
        }
    }

    var opposite: HerdrMode {
        self == .tui ? .app : .tui
    }
}
