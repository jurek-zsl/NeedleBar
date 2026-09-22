import SwiftUI
import NeedleBarCore

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var modelPath: String = ""
    @State private var libraryPath: String = ""
    @State private var useMock: Bool = false
    @State private var telemetryEnabled: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var globalShortcut: String = "⌥Space"
    @State private var isTesting: Bool = false
    @State private var testResult: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Section 1: Privacy First Banner
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        Text("100% On-Device & Private")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text("NeedleBar executes all natural-language comprehension locally using Needle 3 (29M-121M quantized model). Your queries, documents, reminders, and notes never leave this Mac.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

                Divider()

                // Section 2: Needle 3 Engine & Model
                VStack(alignment: .leading, spacing: 10) {
                    Text("NEEDLE 3 ENGINE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Status:")
                            .font(.system(size: 12, weight: .medium))
                        StatusBadgeView(status: appState.engineStatus)
                        Spacer()

                        Button(action: runTest) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Test Needle 3")
                            }
                        }
                        .controlSize(.small)
                        .disabled(isTesting)
                    }

                    if let res = testResult {
                        Text(res)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                    }

                    Toggle("Use Mock Engine (Development / Testing Mode)", isOn: $useMock)
                        .font(.system(size: 12))
                        .onChange(of: useMock) { _, newValue in
                            appState.preferencesStore.useMockEngine = newValue
                            Task {
                                await appState.bootstrapEngine()
                            }
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model Weights (.cact):")
                            .font(.system(size: 11, weight: .medium))
                        TextField("Path to needle3.cact", text: $modelPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .onSubmit {
                                appState.preferencesStore.modelPath = modelPath
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Engine Dynamic Library (.dylib):")
                            .font(.system(size: 11, weight: .medium))
                        TextField("Path to libneedle3.dylib", text: $libraryPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .onSubmit {
                                appState.preferencesStore.libraryPath = libraryPath
                            }
                    }
                }

                Divider()

                // Section 3: System Permissions
                VStack(alignment: .leading, spacing: 10) {
                    Text("SYSTEM PERMISSIONS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    ForEach(PermissionType.allCases, id: \.rawValue) { perm in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(perm.title)
                                    .font(.system(size: 12, weight: .medium))
                                Text(perm.reasonDescription)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            Button("Configure") {
                                appState.permissionManager.openSystemSettings(for: perm)
                            }
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                // Section 4: General Preferences & Telemetry
                VStack(alignment: .leading, spacing: 10) {
                    Text("GENERAL & PRIVACY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    Toggle("Launch NeedleBar at Login", isOn: $launchAtLogin)
                        .font(.system(size: 12))
                        .onChange(of: launchAtLogin) { _, val in
                            appState.preferencesStore.launchAtLogin = val
                        }

                    Toggle("Anonymous Runtime Telemetry (Disabled by default)", isOn: $telemetryEnabled)
                        .font(.system(size: 12))
                        .onChange(of: telemetryEnabled) { _, val in
                            appState.preferencesStore.telemetryEnabled = val
                        }

                    Text("When disabled, NEEDLE_TELEMETRY=0 and DO_NOT_TRACK=1 are enforced.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Global Shortcut:")
                            .font(.system(size: 12))
                        Spacer()
                        TextField("Shortcut", text: $globalShortcut)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .onSubmit {
                                appState.preferencesStore.globalShortcut = globalShortcut
                            }
                    }

                    HStack {
                        Button("Clear Command History") {
                            appState.historyStore.clear()
                            appState.recentHistory = []
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.red)

                        Spacer()

                        Button("Re-run Onboarding") {
                            appState.showOnboarding = true
                            appState.selectedTab = .command
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.top, 4)
                }

                Divider()

                // Section 5: About
                VStack(alignment: .leading, spacing: 4) {
                    Text("NeedleBar 1.0.0 (Needle 3 Engine)")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Local-first macOS automation assistant. Powered by Cactus Compute Needle 3.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
        }
        .onAppear {
            self.modelPath = appState.preferencesStore.modelPath
            self.libraryPath = appState.preferencesStore.libraryPath
            self.useMock = appState.preferencesStore.useMockEngine
            self.telemetryEnabled = appState.preferencesStore.telemetryEnabled
            self.launchAtLogin = appState.preferencesStore.launchAtLogin
            self.globalShortcut = appState.preferencesStore.globalShortcut
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            let start = Date()
            do {
                let resp = try await appState.needleClient.complete(prompt: "What is my battery status?", maxTokens: 128)
                let elapsed = Date().timeIntervalSince(start)
                let calls = resp.functionCalls?.map { $0.name }.joined(separator: ", ") ?? "none"
                testResult = String(format: "✓ Engine test passed in %.2fs. Called: [%@]. Confidence: %.2f", elapsed, calls, resp.confidence ?? 1.0)
            } catch {
                testResult = "✗ Engine test failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
