import SwiftUI
import NeedleBarCore

public struct LiquidGlassPillBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var appState: AppState
    @FocusState private var isInputFocused: Bool
    @State private var hoveredPillIndex: Int? = nil
    @Namespace private var glassNamespace
    var onDismiss: (() -> Void)?

    public init(appState: AppState, onDismiss: (() -> Void)? = nil) {
        self.appState = appState
        self.onDismiss = onDismiss
    }

    public var body: some View {
        AdaptiveGlassContainer(spacing: 12) {
            VStack(spacing: 8) {
                // 1. Main Minimalist Command Pill
                mainInputPill
                    .frame(width: 560, height: 52)
                    .liquidGlassPill(
                        cornerRadius: 26,
                        isHighlighted: isInputFocused,
                        glowAccent: appState.isProcessing ? Color.white.opacity(0.35) : nil
                    )
                    .adaptiveGlassID("mainInputPill", in: glassNamespace)

                // 2. Smaller Pills for Previous Questions & Suggestions
                previousQuestionsPillsRow
                    .frame(maxWidth: 560)

                // 3. Collapsible Glass Card for Results / Confirmation / Errors
                if shouldShowExpansionCard {
                    expansionCard
                        .frame(width: 560)
                        .adaptiveGlassID("expansionCard", in: glassNamespace)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: shouldShowExpansionCard)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: appState.confirmationPlan != nil)
        .animation(.spring(response: 0.30, dampingFraction: 0.84), value: appState.isHelpPresented)
        .onAppear {
            isInputFocused = true
        }
        .onChange(of: appState.confirmationPlan != nil) { _, isConfirming in
            if isConfirming {
                isInputFocused = false
            } else {
                isInputFocused = true
            }
        }
    }

    // MARK: - Main Input Pill
    private var mainInputPill: some View {
        HStack(spacing: 12) {
            // Borderless text input
            TextField("Ask NeedleBar anything...", text: $appState.inputQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .padding(.leading, 18)
                .focused($isInputFocused)
                .onSubmit {
                    submitCurrentQuery()
                }
                .disabled(appState.isProcessing)

            // Trailing actions & indicators
            HStack(spacing: 8) {
                if !appState.inputQuery.isEmpty {
                    Button(action: {
                        appState.inputQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                }

                if appState.isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                } else {
                    // Send Pill Button
                    if appState.confirmationPlan == nil {
                        Button(action: submitCurrentQuery) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Send")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(
                                Capsule()
                                    .fill(isQueryEmpty ? Color.primary.opacity(0.07) : Color.primary)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isQueryEmpty ? Color.primary.opacity(0.08) : Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .foregroundColor(
                                isQueryEmpty
                                    ? Color.secondary.opacity(0.4)
                                    : (colorScheme == .dark ? Color.black : Color.white)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isQueryEmpty)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button(action: {
                            Task {
                                await appState.confirmPlan()
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Send")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                            .foregroundColor(Color.secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                    }
                }

                // Help Pill Button
                Button(action: {
                    if appState.isHelpPresented {
                        appState.dismissHelp()
                    } else {
                        appState.presentHelp()
                    }
                }) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(
                            Capsule()
                                .fill(appState.isHelpPresented ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(appState.isHelpPresented ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                        .foregroundColor(appState.isHelpPresented ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(appState.isHelpPresented ? "Close Help (Escape)" : "NeedleBar Help & Examples")

                // Esc Pill Button
                Button(action: {
                    if appState.confirmationPlan != nil {
                        appState.cancelPlan()
                    } else if appState.isHelpPresented {
                        appState.dismissHelp()
                    } else if let dismiss = onDismiss {
                        dismiss()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("esc")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(appState.confirmationPlan != nil ? "Cancel confirmation (Escape)" : (appState.isHelpPresented ? "Close Help (Escape)" : "Close NeedleBar (Escape)"))
            }
            .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
    }

    private var isQueryEmpty: Bool {
        appState.inputQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Previous Questions & Suggestions (Smaller Pills)
    private var previousQuestionsPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            AdaptiveGlassContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Array(displayPills.enumerated()), id: \.offset) { index, item in
                        pillChip(item: item, index: index)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func pillChip(item: PillItem, index: Int) -> some View {
        Button(action: {
            runPill(item)
        }) {
            HStack(spacing: 6) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text(item.text)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .liquidGlassChip(isSelected: hoveredPillIndex == index)
            .adaptiveGlassID("pill_\(index)", in: glassNamespace)
            .scaleEffect(hoveredPillIndex == index ? 1.04 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hoveredPillIndex == index)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredPillIndex = isHovered ? index : nil
        }
    }

    private func runPill(_ item: PillItem) {
        appState.inputQuery = item.text
        Task {
            await appState.submitCommand(item.text)
        }
    }

    private func submitCurrentQuery() {
        if appState.confirmationPlan != nil {
            Task {
                await appState.confirmPlan()
            }
            return
        }
        guard !isQueryEmpty else { return }
        Task {
            await appState.submitCommand()
        }
    }

    // MARK: - Collapsible Expansion Card
    private var shouldShowExpansionCard: Bool {
        appState.isHelpPresented ||
        appState.confirmationPlan != nil ||
        appState.currentPlan != nil ||
        appState.activeResult != nil ||
        appState.errorMessage != nil
    }

    @ViewBuilder
    private var expansionCard: some View {
        VStack(spacing: 12) {
            if appState.isHelpPresented {
                HelpCatalogView(appState: appState)
            } else if let confirmation = appState.confirmationPlan {
                ConfirmationView(appState: appState, plan: confirmation)
            } else if let result = appState.activeResult {
                resultSummaryView(result)
            } else if let plan = appState.currentPlan {
                ExecutionPlanView(appState: appState, plan: plan)
            } else if let error = appState.errorMessage {
                errorBannerView(error)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 28)
    }

    private func resultSummaryView(_ result: ExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.success ? .green : .red)
                    .font(.system(size: 18))

                Text(result.success ? "Completed Successfully" : "Execution Finished with Errors")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Spacer()

                Button(action: {
                    appState.activeResult = nil
                    appState.currentPlan = nil
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            Text(result.summary)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if !result.results.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(result.results.enumerated()), id: \.offset) { _, res in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(res.success ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            Text(res.message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    private func errorBannerView(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))

            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            Button("Dismiss") {
                appState.errorMessage = nil
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Pill Items Computation
    private struct PillItem: Hashable {
        let text: String
        let icon: String?
    }

    private var displayPills: [PillItem] {
        var items: [PillItem] = []

        // Add up to 5 previous questions from history
        for record in appState.recentHistory.prefix(5) {
            let icon = iconForTool(record.toolNames.first)
            items.append(PillItem(text: record.query, icon: icon))
        }

        // Add standard suggestions if fewer than 4 items
        let defaults: [PillItem] = [
            PillItem(text: "help", icon: "questionmark.circle.fill"),
            PillItem(text: "start timer 5 min", icon: "timer"),
            PillItem(text: "Open Safari", icon: "safari"),
            PillItem(text: "Battery status", icon: "battery.100"),
            PillItem(text: "Open Downloads folder", icon: "folder"),
            PillItem(text: "System summary", icon: "macbook.and.iphone")
        ]

        for d in defaults {
            if !items.contains(where: { $0.text.lowercased() == d.text.lowercased() }) {
                items.append(d)
            }
        }

        return Array(items.prefix(8))
    }

    private func iconForTool(_ name: String?) -> String? {
        guard let name = name else { return "clock.arrow.circlepath" }
        switch name {
        case "start_timer": return "timer"
        case "create_reminder": return "checklist"
        case "create_calendar_event": return "calendar"
        case "open_application": return "app.fill"
        case "quit_application": return "xmark.app"
        case "open_url": return "safari"
        case "open_folder": return "folder"
        case "get_battery_status": return "battery.100"
        case "get_system_summary": return "cpu"
        case "search_notes": return "note.text"
        default: return "clock.arrow.circlepath"
        }
    }
}
