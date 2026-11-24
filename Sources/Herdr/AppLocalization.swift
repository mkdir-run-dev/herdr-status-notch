import Foundation

/// 인터페이스 언어. 드롭다운에서 고르고 UserDefaults(appLanguage)에 저장한다.
/// system은 조회 시점마다 시스템 선호 언어를 다시 읽어 결정한다.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case korean
    case english

    var id: String { rawValue }

    /// system이 실제로 쓸 언어. 선호 언어 첫 항목이 ko로 시작하면 한국어,
    /// 아니면 영어다.
    var resolved: Self {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ko") ? .korean : .english
    }
}

/// UI 문자 키. 새 문구는 키와 표 항목을 짝으로 추가한다.
enum AppText: CaseIterable {
    case offlineMode
    case spacesHeader
    case spacesHint
    case noSpaces
    case allSpacesHeader
    case idleTag
    case notchPanelToggle
    case startAtLoginToggle
    case languageLabel
    case languageSystemOption
    case quit
    case modeLabel
    case otherModePromptTitle
    case otherModePromptMessage
    case otherModePromptSwitch
    case otherModePromptKeep

    /// 언어별 문자 표. 형식 문자(%lld)는 String(format:)에 그대로 쓴다.
    private static let table: [AppText: (ko: String, en: String)] = [
        .offlineMode: ("%@ 오프라인", "%@ offline"),
        .spacesHeader: ("스페이스 %lld", "Spaces %lld"),
        .spacesHint: ("클릭하면 해당 스페이스로 이동", "Click a space to focus it"),
        .noSpaces: ("스페이스 없음", "No spaces"),
        .allSpacesHeader: ("전체 스페이스 %lld", "All spaces %lld"),
        .idleTag: ("대기", "Idle"),
        .notchPanelToggle: ("노치 패널", "Notch panel"),
        .startAtLoginToggle: ("로그인 시 시작", "Start at login"),
        .languageLabel: ("언어", "Language"),
        .languageSystemOption: ("시스템 따름", "Match system"),
        .quit: ("종료", "Quit"),
        .modeLabel: ("모드", "Mode"),
        .otherModePromptTitle: ("%@ 실행 감지", "%@ detected"),
        .otherModePromptMessage: (
            "지금은 %@ 모드입니다. %@ 실행이 감지되었습니다. 전환할까요?",
            "Currently in %@ mode, but %@ is running. Switch now?",
        ),
        .otherModePromptSwitch: ("%@ 모드로 전환", "Switch to %@"),
        .otherModePromptKeep: ("유지", "Keep current"),
    ]

    /// 이 언어로 쓸 문자. 표에 빠진 키는 즉시 눈에 보이는 빈 문자로 실패한다.
    func text(in language: AppLanguage) -> String {
        guard let entry = Self.table[self] else { return "" }
        return language.resolved == .korean ? entry.ko : entry.en
    }
}
