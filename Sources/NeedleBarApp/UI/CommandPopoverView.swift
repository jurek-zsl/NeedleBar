import SwiftUI
import NeedleBarCore

public struct CommandPopoverView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "needle")
                        .rotationEffect(.degrees(45))
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14, weight: .bold))

                    Text("NeedleBar")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }

                StatusBadgeView(status: appState.engineStatus)

                Spacer()

                // Tab Switcher
                Picker("", selection: $appState.selectedTab) {
                    ForEach(AppTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .controlSize(.small)

                Button(action: {
                    if appState.isHelpPresented {
                        appState.dismissHelp()
                    } else {
                        appState.selectedTab = .command
                        appState.presentHelp()
                    }
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(appState.isHelpPresented ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Help & Command Examples")

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit NeedleBar")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Content Area
            VStack(spacing: 12) {
                if appState.showOnboarding {
                    OnboardingView(appState: appState)
                } else {
                    switch appState.selectedTab {
                    case .command:
                        commandTabContent
                    case .history:
                        HistoryView(appState: appState)
                    case .settings:
                        SettingsView(appState: appState)
                    }
                }
            }
            .padding(14)
            .frame(width: 440)

            Divider()

            // Footer
            HStack {
                if let status = appState.statusMessage {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Tip: ⏎ to execute • ⎋ to cancel")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 9))
                    Text("Local AI • No Cloud")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        }
        .frame(width: 440)
    }

    @ViewBuilder
    private var commandTabContent: some View {
        VStack(spacing: 12) {
            CommandInputView(appState: appState)

            // Help View
            if appState.isHelpPresented {
                HelpCatalogView(appState: appState)
            }

            // Quick Suggestions when idle
            if !appState.isHelpPresented && appState.currentPlan == nil && appState.confirmationPlan == nil && !appState.isProcessing {
                VStack(alignment: .leading, spacing: 6) {
                    Text("QUICK SUGGESTIONS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            suggestionButton("help")
                            suggestionButton("Open Safari")
                            suggestionButton("Start 25m focus session")
                            suggestionButton("What is my battery status?")
                            suggestionButton("Show system summary")
                        }
                    }
                }
                .padding(.top, 4)
            }

            // Error banner
            if let error = appState.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command Error")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button(action: { appState.errorMessage = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            // Confirmation View
            if let plan = appState.confirmationPlan {
                ConfirmationView(appState: appState, plan: plan)
            }
            // Execution Plan View
            else if let plan = appState.currentPlan {
                ExecutionPlanView(appState: appState, plan: plan, result: appState.activeResult)
            }
        }
    }

    private func suggestionButton(_ title: String) -> some View {
        Button(action: {
            appState.inputQuery = title
            Task {
                await appState.submitCommand(title)
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
