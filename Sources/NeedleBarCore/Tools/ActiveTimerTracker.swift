import Foundation
import Combine

@MainActor
public final class ActiveTimerTracker: ObservableObject {
    public static let shared = ActiveTimerTracker()

    @Published public private(set) var remainingSeconds: Int = 0
    @Published public private(set) var timerLabel: String?
    @Published public private(set) var isTimerActive: Bool = false

    private var countdownTask: Task<Void, Never>?

    public init() {}

    public func startCountdown(durationSeconds: Int, label: String?) {
        countdownTask?.cancel()
        self.remainingSeconds = durationSeconds
        self.timerLabel = label
        self.isTimerActive = true

        countdownTask = Task { @MainActor in
            while remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                remainingSeconds -= 1
            }
            if remainingSeconds <= 0 && isTimerActive {
                isTimerActive = false
                SoundFeedbackManager.shared.playTimerChime()
            }
        }
    }

    public func cancel() {
        countdownTask?.cancel()
        isTimerActive = false
        remainingSeconds = 0
    }
}
