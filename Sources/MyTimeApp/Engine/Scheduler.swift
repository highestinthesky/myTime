import Foundation
import MyTimeCore
@MainActor final class Scheduler {
    var onFire: (() -> Void)?
    private var timer: Timer?
    func schedule(_ wake: WakeUp?, trustedNow: Date) {
        timer?.invalidate()
        timer = nil
        guard let wake else { return }
        let timer = Timer(timeInterval: max(0.05, wake.date.timeIntervalSince(trustedNow)), repeats: false) {
            [weak self] _ in MainActor.assumeIsolated { self?.onFire?() }
        }
        timer.tolerance = wake.critical ? Constants.criticalWakeTolerance : Constants.normalWakeTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
