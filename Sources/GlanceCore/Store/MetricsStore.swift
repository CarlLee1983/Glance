import Foundation
import Combine

/// 反應式狀態中樞:計時器定期取樣,發佈最新 snapshot 與歷史。供 SwiftUI 觀察。
public final class MetricsStore: ObservableObject {
    @Published public private(set) var snapshot: SystemSnapshot?
    @Published public private(set) var history: MetricHistory

    private let sampler: SystemSampling
    private var timer: DispatchSourceTimer?

    public init(sampler: SystemSampling, historyCapacity: Int = 90) {
        self.sampler = sampler
        self.history = MetricHistory(capacity: historyCapacity)
    }

    /// 取樣一次並更新狀態(同步;測試可直接呼叫)。
    public func tick() {
        apply(sampler.sample())
    }

    func apply(_ snap: SystemSnapshot) {
        snapshot = snap
        history.record(snap)
    }

    /// 啟動定期取樣。取樣在背景佇列、發佈切回主執行緒。重複呼叫會先停舊計時器。
    public func start(interval: TimeInterval) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let snap = self.sampler.sample()
            DispatchQueue.main.async { self.apply(snap) }
        }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }
}
