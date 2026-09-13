import Foundation
@MainActor final class RepeatingUITimer {
    private var timer: Timer?
    var isRunning: Bool { timer != nil }
    func start(interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { body() } }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
