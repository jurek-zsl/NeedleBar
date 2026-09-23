import Foundation
import AppKit

public final class SoundFeedbackManager: @unchecked Sendable {
    public static let shared = SoundFeedbackManager()

    public var isSoundEnabled: Bool = true

    public init() {}

    public func playSuccess() {
        guard isSoundEnabled else { return }
        NSSound(named: "Tink")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    public func playFailure() {
        guard isSoundEnabled else { return }
        NSSound(named: "Basso")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    public func playConfirmationPrompt() {
        guard isSoundEnabled else { return }
        NSSound(named: "Blow")?.play()
    }

    public func playTimerChime() {
        guard isSoundEnabled else { return }
        NSSound(named: "Glass")?.play()
    }
}
