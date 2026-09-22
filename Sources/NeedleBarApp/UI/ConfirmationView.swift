import SwiftUI
import NeedleBarCore

public struct ConfirmationView: View {
    @ObservedObject var appState: AppState
    let plan: ExecutionPlan

    public init(appState: AppState, plan: ExecutionPlan) {
        self.appState = appState
        self.plan = plan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: plan.overallRisk.iconName)
                    .foregroundColor(plan.overallRisk == .destructive ? .red : .orange)
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.overallRisk == .destructive ? "Destructive Action Confirmation" : "Action Requires Confirmation")
                        .font(.system(size: 14, weight: .bold))
                    Text("NeedleBar will not make system changes without your explicit approval.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            Divider()

            // Request box
            VStack(alignment: .leading, spacing: 4) {
                Text("USER COMMAND")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("\"\(plan.query)\"")
                    .font(.system(size: 13, weight: .medium))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }

            // Steps & Arguments breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("PLANNED ACTIONS (\(plan.steps.count))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plan.steps) { step in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(step.index). \(step.description)")
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Text(step.toolCall.name)
                                        .font(.system(size: 10, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(4)
                                }

                                if !step.affectedItems.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(step.affectedItems, id: \.self) { item in
                                            Text("• \(item)")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.primary)
                                        }
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(NSColor.windowBackgroundColor))
                                    .cornerRadius(4)
                                }

                                // Detailed arguments
                                if !step.toolCall.arguments.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Arguments:")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                        ForEach(Array(step.toolCall.arguments.keys.sorted()), id: \.self) { key in
                                            if let val = step.toolCall.arguments[key]?.stringValue {
                                                HStack(alignment: .top, spacing: 4) {
                                                    Text("\(key):")
                                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                        .foregroundColor(.secondary)
                                                    Text(val)
                                                        .font(.system(size: 11, design: .monospaced))
                                                        .foregroundColor(.primary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            // Reasoning note if available
            if let reasoning = plan.reasoning, !reasoning.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Text("Model reasoning: \(reasoning)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    appState.cancelPlan()
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    Task {
                        await appState.confirmPlan()
                    }
                }) {
                    Text("Confirm & Execute")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(plan.overallRisk == .destructive ? .red : .accentColor)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(plan.overallRisk == .destructive ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
