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
            // Header with glowing risk badge
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            plan.overallRisk == .destructive
                                ? Color.red.opacity(0.2)
                                : Color.orange.opacity(0.2)
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: plan.overallRisk.iconName)
                        .foregroundColor(plan.overallRisk == .destructive ? .red : .orange)
                        .font(.system(size: 16, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.overallRisk == .destructive ? "Destructive Action Requires Confirmation" : "Action Requires Confirmation")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("NeedleBar will not perform system changes without your explicit approval.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Command preview card
            VStack(alignment: .leading, spacing: 6) {
                Text("USER COMMAND")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                HStack {
                    Text("\"\(plan.query)\"")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
            }

            // Steps breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("PLANNED ACTIONS (\(plan.steps.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plan.steps) { step in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(step.index). \(step.description)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text(step.toolCall.name)
                                        .font(.system(size: 10, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                                        .foregroundColor(.primary)
                                }

                                if !step.affectedItems.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(step.affectedItems, id: \.self) { item in
                                            Text("• \(item)")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
                                }

                                if !step.toolCall.arguments.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("PARAMETERS")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.secondary.opacity(0.8))

                                        ForEach(Array(step.toolCall.arguments.keys.sorted()), id: \.self) { key in
                                            HStack(spacing: 8) {
                                                Text(key)
                                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .frame(minWidth: 50, alignment: .trailing)

                                                TextField(
                                                    key,
                                                    text: Binding(
                                                        get: {
                                                            step.toolCall.arguments[key]?.stringValue ?? "\(step.toolCall.arguments[key]?.value.base ?? "")"
                                                        },
                                                        set: { newVal in
                                                            appState.updatePlanArgument(stepId: step.id, key: key, value: newVal)
                                                        }
                                                    )
                                                )
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.primary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                                                .onSubmit {
                                                    Task {
                                                        await appState.confirmPlan()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.02)))
                                }
                            }
                            .padding(10)
                            .liquidGlassCard(cornerRadius: 16)
                        }
                    }
                }
                .frame(height: plannedActionsHeight)
                .scrollIndicators(.visible)
            }

            // Action Buttons
            AdaptiveGlassContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if #available(macOS 26, iOS 26, *) {
                        Button(action: {
                            appState.cancelPlan()
                        }) {
                            HStack {
                                Text("Cancel")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                Text("⎋")
                                    .font(.system(size: 10, weight: .bold))
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 42)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("Cancels the planned actions")

                        Button(action: {
                            Task {
                                await appState.confirmPlan()
                            }
                        }) {
                            HStack {
                                Text("Confirm & Execute")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("⏎")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 42)
                            .glassEffect(
                                .regular
                                    .tint(plan.overallRisk == .destructive ? .red : .accentColor)
                                    .interactive(),
                                in: .capsule
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("Runs the planned actions")
                    } else {
                        // Fallback
                        Button(action: {
                            appState.cancelPlan()
                        }) {
                            HStack {
                                Text("Cancel")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                Text("⎋")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 42)
                            .liquidGlassChip()
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("Cancels the planned actions")

                        Button(action: {
                            Task {
                                await appState.confirmPlan()
                            }
                        }) {
                            HStack {
                                Text("Confirm & Execute")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("⏎")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 42)
                            .background(
                                ZStack {
                                    Capsule(style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: plan.overallRisk == .destructive
                                                    ? [Color.red.opacity(0.9), Color.red.opacity(0.7)]
                                                    : [Color.primary.opacity(0.85), Color.primary.opacity(0.70)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                }
                            )
                            .shadow(
                                color: (plan.overallRisk == .destructive ? Color.red : Color.primary).opacity(0.25),
                                radius: 8,
                                x: 0,
                                y: 3
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("Runs the planned actions")
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var plannedActionsHeight: CGFloat {
        min(max(CGFloat(plan.steps.count) * 90, 80), 220)
    }
}
