import Foundation
import SwiftUI

/// 폴링으로 슬롯 상태를 유지하는 단일 상태 원본. 노치 패널과 메뉴바 위젯이
/// 모두 이 객체 하나를 본다.
@MainActor
final class SlotStore: ObservableObject {
    /// 한 번에 보여 주는 슬롯 상한. 초과분은 overflowCount로만 알린다.
    static let maxSlots = 8
    static let pollInterval: TimeInterval = 0.7

    @Published private(set) var slots: [AgentSlot] = []
    @Published private(set) var connection: ConnectionState = .ok
    /// 9번째부터의 개수. 메뉴바에 "N more"로 표시된다.
    @Published private(set) var overflowCount = 0

    private let client: HerdrClient
    private var timer: Timer?
    private var pollInFlight = false

    init(client: HerdrClient = HerdrClient()) {
        self.client = client
    }

    func startPolling() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// herdr 응답이 최대 2초까지 걸릴 수 있어 폴링 간격(0.7초)보다 느리면
    /// 다음 틱을 건너뛴다. 동시에 여러 herdr 프로세스를 띄우지 않기 위해서다.
    private func poll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        let client = client
        DispatchQueue.global(qos: .utility).async {
            let result = client.listAgents()
            DispatchQueue.main.async { [weak self] in
                self?.apply(result)
            }
        }
    }

    private func apply(_ result: (slots: [AgentSlot], connection: ConnectionState)) {
        pollInFlight = false
        connection = result.connection

        if result.connection == .offline {
            // 오프라인에서는 마지막 상태를 믿을 수 없어 버린다.
            // 슬롯이 0이 되면 노치 패널은 숨겨지고 메뉴바에는 빨간 오프라인 행만 남는다.
            slots = []
            overflowCount = 0
            return
        }

        let sorted = result.slots.sorted { lhs, rhs in
            let left = lhs.status.sortRank
            let right = rhs.status.sortRank
            return left == right ? lhs.displayName < rhs.displayName : left < right
        }
        slots = Array(sorted.prefix(Self.maxSlots))
        overflowCount = max(0, sorted.count - Self.maxSlots)
    }

    func focus(_ slot: AgentSlot) {
        // herdr agent focus는 name을 인자로 받는다. name 없는 슬롯은
        // 지목할 대상이 없어 탭해도 아무 일도 하지 않는다.
        guard let name = slot.name else { return }
        client.focus(agentNamed: name)
    }
}
