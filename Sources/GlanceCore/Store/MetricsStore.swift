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

    /// 取樣一次並更新狀態(同步)。
    /// 執行緒契約:**必須在主執行緒呼叫**——它會同步改動 `@Published`,供 SwiftUI 觀察。
    /// 僅作為測試掛勾(XCTest 預設在主執行緒執行);正式運作請改用 `start(interval:)`,
    /// 其計時器路徑會在背景取樣、再切回主執行緒發佈。
    func tick() {
        apply(sampler.sample())
    }

    /// 在主執行緒套用一次 snapshot。所有 `@Published` 變更皆經由此處,
    /// 由 `tick()`(主執行緒)或 `start()` 的 `DispatchQueue.main.async` 呼叫。
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
