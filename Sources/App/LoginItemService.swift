import Foundation
import ServiceManagement

/// 로그인 시 자동 실행 등록. 로그인 항목은 시스템 설정이 관리하므로
/// 상태 조회·등록 해제만 하고 결과를 앱 상태로 보관하지 않는다.
@MainActor
final class LoginItemService {
    static let shared = LoginItemService()

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 응용 프로그램 폴더 밖 실행 등으로 등록이 거부돼도 앱 동작에는
            // 지장이 없으므로 콘솔 로그만 남긴다.
            NSLog("로그인 항목 전환 실패: \(error.localizedDescription)")
        }
    }
}
