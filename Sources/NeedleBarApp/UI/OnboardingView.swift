import SwiftUI
import NeedleBarCore

public struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var step: Int = 1
    @State private var testOutput: String?
    @State private var isTesting: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Step content
            switch step {
            case 1:
                stepOne
            case 2:
                stepTwo
            case 3:
                stepThree
            case 4:
                stepFour
            default:
                EmptyView()
            }

            Spacer()

            // Navigation bar
            HStack {
                if step > 1 {
                    Button("Back") {
                        step -= 1
                    }
                    .controlSize(.small)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                if step < 4 {
                    Button("Next") {
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Get Started") {
                        appState.dismissOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(minHeight: 280)
    }

    private var stepOne: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)

            Text("Welcome to NeedleBar")
                .font(.system(size: 16, weight: .bold))

            Text("NeedleBar is your native macOS automation assistant. Type naturally to launch applications, manage files, set timers, and search notes without leaving your keyboard.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var stepTwo: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)

            Text("100% Local & Private")
                .font(.system(size: 16, weight: .bold))

            Text("Powered by Needle 3 (a tiny 35 MB on-device foundation model). Every command is processed locally on Apple Silicon. No cloud APIs, no server dependencies, no data leaves your Mac.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var stepThree: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("Safe by Design")
                .font(.system(size: 16, weight: .bold))

            Text("Safe actions like opening apps or checking battery run immediately. Any action that moves files, alters reminders, or quits apps always prompts for your explicit confirmation first.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var stepFour: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 32))
                .foregroundColor(.yellow)

            Text("Try a Test Command")
                .font(.system(size: 16, weight: .bold))

            Text("Let's test Needle 3 with a safe query: 'What is my battery status?'")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: runQuickTest) {
                if isTesting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Run 'What is my battery status?'")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isTesting)

            if let out = testOutput {
                Text(out)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }
        }
    }

    private func runQuickTest() {
        isTesting = true
        Task {
            do {
                let resp = try await appState.needleClient.complete(prompt: "What is my battery status?", maxTokens: 128)
                let tool = resp.functionCalls?.first?.name ?? "none"
                testOutput = "✓ Needle selected tool: \(tool)"
            } catch {
                testOutput = "Result: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
