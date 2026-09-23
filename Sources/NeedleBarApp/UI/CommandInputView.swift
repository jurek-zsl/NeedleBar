import SwiftUI
import NeedleBarCore

public struct CommandInputView: View {
    @ObservedObject var appState: AppState
    @FocusState private var isFocused: Bool

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundColor(.accentColor)
                .font(.system(size: 16))

            TextField("Ask NeedleBar... (e.g. Open Safari, Start 25m timer)", text: $appState.inputQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
                .onSubmit {
                    submit()
                }
                .disabled(appState.isProcessing)

            if !appState.inputQuery.isEmpty {
                Button(action: {
                    appState.inputQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            if appState.isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else if appState.confirmationPlan == nil {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(appState.inputQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary.opacity(0.4) : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(appState.inputQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(action: submit) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Confirm & Execute")
            }
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }

    private func submit() {
        if appState.confirmationPlan != nil {
            Task {
                await appState.confirmPlan()
            }
            return
        }
        Task {
            await appState.submitCommand()
        }
    }
}
