import SwiftUI
import NeedleBarCore

public struct ExecutionPlanView: View {
    @ObservedObject var appState: AppState
    let plan: ExecutionPlan
    let result: ExecutionResult?

    public init(appState: AppState, plan: ExecutionPlan, result: ExecutionResult? = nil) {
        self.appState = appState
        self.plan = plan
        self.result = result
    }

    public var body: some View {
        AdaptiveGlassContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with query & status
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.query)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                            .foregroundColor(.primary)

                        if let conf = plan.confidence {
                            Text("Needle 3 Confidence: \(Int(conf * 100))%")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if let res = result {
                        HStack(spacing: 5) {
                            Image(systemName: res.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(res.success ? .green : .red)
                                .font(.system(size: 12))
                            Text(res.success ? "Success" : "Failed")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(res.success ? .green : .red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill((res.success ? Color.green : Color.red).opacity(0.12)))
                    }
                }

                // Steps list
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.steps) { step in
                        HStack(spacing: 8) {
                            stepIcon(for: step.status)
                                .frame(width: 16)

                            Text(step.description)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.primary)

                            Spacer()

                            if let res = step.result, !res.success {
                                Text(res.error ?? "Error")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .liquidGlassCard(cornerRadius: 14)
                    }
                }

                // Output summary
                if let res = result {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RESULT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Text(res.summary)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }

                    HStack {
                        Text(String(format: "Execution took %.2fs", res.duration))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Spacer()

                        if #available(macOS 26, iOS 26, *) {
                            Button("Done") {
                                appState.clearCurrentResult()
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        } else {
                            Button("Done") {
                                appState.clearCurrentResult()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .liquidGlassChip()
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: 28)
        }
    }

    @ViewBuilder
    private func stepIcon(for status: ExecutionStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 12))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 12))
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
        }
    }
}
