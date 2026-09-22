import SwiftUI
import NeedleBarCore

public struct StatusBadgeView: View {
    public let status: NeedleEngineStatus

    public init(status: NeedleEngineStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .help(status.errorDescription ?? status.engineType)
    }

    private var statusColor: Color {
        if status.isLoaded {
            if status.engineType.contains("Mock") {
                return .orange
            }
            return .green
        }
        return .red
    }

    private var statusLabel: String {
        if status.isLoaded {
            if status.engineType.contains("Mock") {
                return "Needle 3 (Mock)"
            }
            return "Needle 3 (Local)"
        }
        return "Engine Offline"
    }
}
