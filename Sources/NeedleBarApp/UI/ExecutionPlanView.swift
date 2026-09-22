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
        VStack(alignment: .leading, spacing: 12) {
            // Header with query & status
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.query)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)

                    if let conf = plan.confidence {
                        Text("Needle 3 Confidence: \(Int(conf * 100))%")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let res = result {
                    HStack(spacing: 4) {
                        Image(systemName: res.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(res.success ? .green : .red)
                        Text(res.success ? "Success" : "Failed")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(res.success ? .green : .red)
                    }
                }
            }

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.steps) { step in
                    HStack(spacing: 8) {
                        stepIcon(for: step.status)
                            .frame(width: 16)

                        Text(step.description)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)

                        Spacer()

                        if let res = step.result, !res.success {
                            Text(res.error ?? "Error")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Output summary
            if let res = result {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RESULT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(res.summary)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                HStack {
                    Text(String(format: "Execution took %.2fs", res.duration))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Done") {
                        appState.clearCurrentResult()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
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
