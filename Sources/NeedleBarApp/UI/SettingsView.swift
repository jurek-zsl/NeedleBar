import AppKit
import ServiceManagement
import SwiftUI
import NeedleBarCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case intelligence = "Intelligence"
    case permissions = "Permissions"
    case about = "About"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .intelligence: return "sparkles"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Behavior and history"
        case .intelligence: return "Needle 3 engine"
        case .permissions: return "Feature access"
        case .about: return "App information"
        }
    }
}

public struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appState: AppState

    @State private var selectedSection: SettingsSection = .general
    @State private var modelPath = ""
    @State private var libraryPath = ""
    @State private var useMock = false
    @State private var launchAtLogin = false
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var settingsNotice: SettingsNotice?
    @State private var permissionStatuses: [PermissionType: PermissionStatus] = [:]
    @State private var requestingPermission: PermissionType?
    @State private var showClearHistoryConfirmation = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            SettingsBackdrop(colorScheme: colorScheme)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 196)

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1)
                    .padding(.vertical, 18)

                detail
            }
        }
        .fontDesign(.rounded)
        .frame(minWidth: 760, minHeight: 600)
        .onAppear(perform: loadSettings)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
            refreshLaunchAtLogin()
        }
        .confirmationDialog(
            "Clear command history?",
            isPresented: $showClearHistoryConfirmation
        ) {
            Button("Clear history", role: .destructive, action: clearHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local list of past NeedleBar commands. It does not change files, reminders, events, or notes.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .liquidGlassChip(isInteractive: false)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("NeedleBar")
                        .font(.headline.weight(.semibold))
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            AdaptiveGlassContainer(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(SettingsSection.allCases) { section in
                        sidebarButton(for: section)
                    }
                }
            }

            Spacer()

            Label("Processed on this Mac", systemImage: "lock.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
        }
        .padding(.top, 26)
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }

    private func sidebarButton(for section: SettingsSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? selectedSystemImage(for: section) : section.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.rawValue)
                        .font(.subheadline.weight(.medium))
                    Text(section.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .liquidGlassChip(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Shows \(section.rawValue.lowercased()) settings")
    }

    private func selectedSystemImage(for section: SettingsSection) -> String {
        switch section {
        case .general: return "slider.horizontal.3"
        case .intelligence: return "sparkles"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHeader

                if let settingsNotice {
                    noticeView(settingsNotice)
                        .transition(.opacity)
                }

                AdaptiveGlassContainer(spacing: 18) {
                    sectionContent
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIndicators(.hidden)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedSection.rawValue)
                .font(.system(.title, design: .rounded, weight: .bold))
            Text(headerDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var headerDescription: String {
        switch selectedSection {
        case .general:
            return "Choose how NeedleBar behaves and manage local history."
        case .intelligence:
            return "Inspect and configure the on-device Needle 3 engine."
        case .permissions:
            return "Grant access only to the macOS features you want to use."
        case .about:
            return "Version, privacy, and implementation details."
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:
            generalSection
        case .intelligence:
            intelligenceSection
        case .permissions:
            permissionsSection
        case .about:
            aboutSection
        }
    }

    private var generalSection: some View {
        VStack(spacing: 18) {
            SettingsCard(
                title: "Local by design",
                subtitle: "Commands are interpreted by the bundled Needle 3 engine.",
                systemImage: "lock.shield.fill",
                tint: .green
            ) {
                Text("NeedleBar does not need an account or a cloud model. It contacts other apps only when a command explicitly uses them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(
                title: "App behavior",
                subtitle: "Controls that affect how NeedleBar starts and opens.",
                systemImage: "switch.2",
                tint: .blue
            ) {
                VStack(spacing: 16) {
                    Toggle(isOn: $launchAtLogin) {
                        SettingLabel(
                            title: "Open at login",
                            detail: "Keep NeedleBar available from the menu bar after you sign in."
                        )
                    }
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, value in
                        updateLaunchAtLogin(value)
                    }

                    subtleDivider

                    HStack(spacing: 12) {
                        SettingLabel(
                            title: "Keyboard shortcut",
                            detail: "Show or hide the floating command bar."
                        )
                        Spacer()
                        Text("⌃⌥N")
                            .font(.system(.callout, design: .monospaced, weight: .semibold))
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .liquidGlassChip(isInteractive: false)
                            .accessibilityLabel("Control Option N")
                    }
                }
            }

            SettingsCard(
                title: "Local data",
                subtitle: "History is stored on this Mac.",
                systemImage: "clock.arrow.circlepath",
                tint: .orange
            ) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(appState.recentHistory.count) saved command\(appState.recentHistory.count == 1 ? "" : "s")")
                            .font(.callout.weight(.medium))
                        Text("Clear the list without affecting anything created by those commands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Clear history") {
                        showClearHistoryConfirmation = true
                    }
                    .adaptiveGlassButtonStyle()
                    .disabled(appState.recentHistory.isEmpty)
                }

                subtleDivider

                HStack {
                    SettingLabel(
                        title: "Onboarding",
                        detail: "Review NeedleBar’s core workflow again."
                    )
                    Spacer()
                    Button("Show onboarding") {
                        appState.showOnboarding = true
                        appState.selectedTab = .command
                        FloatingBarWindowController.shared.show()
                    }
                    .adaptiveGlassButtonStyle()
                }
            }
        }
    }

    private var intelligenceSection: some View {
        VStack(spacing: 18) {
            SettingsCard(
                title: "Needle 3",
                subtitle: "Local natural-language routing and tool selection.",
                systemImage: "cpu",
                tint: .purple
            ) {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        StatusBadgeView(status: appState.engineStatus)
                        Spacer()
                        Button {
                            runTest()
                        } label: {
                            HStack(spacing: 7) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "waveform.path.ecg")
                                        .accessibilityHidden(true)
                                }
                                Text(isTesting ? "Testing…" : "Test engine")
                            }
                        }
                        .adaptiveGlassButtonStyle(prominent: true)
                        .disabled(isTesting)
                    }

                    if let testResult {
                        TestResultView(result: testResult)
                            .transition(.opacity)
                    }

                    subtleDivider

                    Toggle(isOn: $useMock) {
                        SettingLabel(
                            title: "Use mock engine",
                            detail: "Development mode that skips the local model runtime."
                        )
                    }
                    .toggleStyle(.switch)
                    .onChange(of: useMock) { _, newValue in
                        appState.preferencesStore.useMockEngine = newValue
                        Task { await appState.bootstrapEngine() }
                    }
                }
            }

            SettingsCard(
                title: "Engine files",
                subtitle: "Advanced paths for the local runtime and model weights.",
                systemImage: "folder.badge.gearshape",
                tint: .blue
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    GlassTextField(
                        title: "Model weights",
                        placeholder: "/path/to/needle3.cact",
                        text: $modelPath
                    )

                    GlassTextField(
                        title: "Dynamic library",
                        placeholder: "/path/to/libneedle3.dylib",
                        text: $libraryPath
                    )

                    HStack {
                        Text("Changes take effect when the engine reloads.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save paths", action: saveEnginePaths)
                            .adaptiveGlassButtonStyle(prominent: true)
                    }
                }
            }
        }
    }

    private var permissionsSection: some View {
        VStack(spacing: 18) {
            SettingsCard(
                title: "Permission principles",
                subtitle: "No blanket access and no permission is required for basic commands.",
                systemImage: "hand.raised.fill",
                tint: .green
            ) {
                Text("Opening apps, checking battery status, using the global shortcut, and managing unprotected files work without these permissions. NeedleBar asks only when you enable a feature below or use it for the first time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(
                title: "Feature access",
                subtitle: "Each permission maps to one specific NeedleBar capability.",
                systemImage: "checkmark.shield",
                tint: .blue
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(PermissionType.allCases.enumerated()), id: \.element.rawValue) { index, permission in
                        permissionRow(permission)
                        if index < PermissionType.allCases.count - 1 {
                            subtleDivider
                                .padding(.vertical, 14)
                        }
                    }
                }
            }
        }
    }

    private func permissionRow(_ permission: PermissionType) -> some View {
        let status = permissionStatuses[permission] ?? appState.permissionManager.status(for: permission)
        let isRequesting = requestingPermission == permission

        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(permissionTint(for: status))
                .frame(width: 34, height: 34)
                .background(permissionTint(for: status).opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(permission.title)
                        .font(.callout.weight(.semibold))
                    PermissionStatusBadge(status: status)
                }
                Text(permission.reasonDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 14)

            permissionAction(permission: permission, status: status, isRequesting: isRequesting)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func permissionAction(
        permission: PermissionType,
        status: PermissionStatus,
        isRequesting: Bool
    ) -> some View {
        switch status {
        case .authorized:
            EmptyView()

        case .notDetermined:
            Button {
                requestPermission(permission)
            } label: {
                HStack(spacing: 7) {
                    if isRequesting {
                        ProgressView().controlSize(.small)
                    }
                    Text(isRequesting ? "Requesting…" : "Allow")
                }
            }
            .adaptiveGlassButtonStyle(prominent: true)
            .disabled(requestingPermission != nil)
            .accessibilityHint("Shows the macOS permission request for \(permission.title.lowercased())")

        case .denied, .restricted:
            Button("Open settings") {
                appState.permissionManager.openSystemSettings(for: permission)
            }
            .adaptiveGlassButtonStyle()
            .accessibilityHint("Opens the relevant Privacy and Security settings")
        }
    }

    private var aboutSection: some View {
        VStack(spacing: 18) {
            SettingsCard(
                title: "NeedleBar 1.0.0",
                subtitle: "A local-first macOS automation assistant.",
                systemImage: "sparkles",
                tint: .purple
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    AboutRow(label: "Engine", value: "Needle 3")
                    subtleDivider
                    AboutRow(label: "Processing", value: "On-device")
                    subtleDivider
                    AboutRow(label: "Interface", value: "SwiftUI + Liquid Glass")
                    subtleDivider
                    AboutRow(label: "Minimum macOS", value: "14.0")
                }
            }

            SettingsCard(
                title: "Privacy",
                subtitle: "Designed to keep command interpretation local.",
                systemImage: "hand.raised.fill",
                tint: .green
            ) {
                Text("NeedleBar stores preferences and command history locally. Access to Clock, Reminders, Calendar, and Notes is handled by macOS and can be revoked at any time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtleDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func noticeView(_ notice: SettingsNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? .orange : .green)
                .accessibilityHidden(true)
            Text(notice.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                settingsNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 18, tint: notice.isError ? .orange.opacity(0.3) : .green.opacity(0.25))
        .accessibilityElement(children: .contain)
    }

    private func permissionTint(for status: PermissionStatus) -> Color {
        switch status {
        case .authorized: return .green
        case .notDetermined: return .secondary
        case .denied: return .orange
        case .restricted: return .red
        }
    }

    private func loadSettings() {
        modelPath = appState.preferencesStore.modelPath
        libraryPath = appState.preferencesStore.libraryPath
        useMock = appState.preferencesStore.useMockEngine
        refreshLaunchAtLogin()
        refreshPermissions()
    }

    private func refreshPermissions() {
        permissionStatuses = Dictionary(uniqueKeysWithValues: PermissionType.allCases.map {
            ($0, appState.permissionManager.status(for: $0))
        })
    }

    private func requestPermission(_ permission: PermissionType) {
        requestingPermission = permission
        settingsNotice = nil

        Task {
            let granted = await appState.permissionManager.requestPermission(for: permission)
            refreshPermissions()
            requestingPermission = nil

            if granted {
                settingsNotice = SettingsNotice(message: "\(permission.title) access is ready.", isError: false)
            } else if permission == .accessibility {
                settingsNotice = SettingsNotice(
                    message: "Turn on NeedleBar in Accessibility settings. If it is already enabled but still shows Not allowed, remove the old entry, add this copy again, and relaunch NeedleBar.",
                    isError: true
                )
            } else {
                settingsNotice = SettingsNotice(
                    message: "\(permission.title) access was not granted. You can change it in System Settings.",
                    isError: true
                )
            }
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func updateLaunchAtLogin(_ shouldLaunch: Bool) {
        do {
            if shouldLaunch {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refreshLaunchAtLogin()
            if shouldLaunch, SMAppService.mainApp.status == .requiresApproval {
                settingsNotice = SettingsNotice(
                    message: "Approve NeedleBar in System Settings > General > Login Items to finish enabling launch at login.",
                    isError: true
                )
            } else {
                settingsNotice = SettingsNotice(
                    message: shouldLaunch ? "NeedleBar will open at login." : "NeedleBar will no longer open at login.",
                    isError: false
                )
            }
        } catch {
            refreshLaunchAtLogin()
            settingsNotice = SettingsNotice(
                message: "Unable to update launch at login: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    private func saveEnginePaths() {
        let trimmedModelPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLibraryPath = libraryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelPath.isEmpty, !trimmedLibraryPath.isEmpty else {
            settingsNotice = SettingsNotice(message: "Choose both engine file paths before saving.", isError: true)
            return
        }

        appState.preferencesStore.modelPath = trimmedModelPath
        appState.preferencesStore.libraryPath = trimmedLibraryPath
        Task {
            await appState.bootstrapEngine()
            settingsNotice = SettingsNotice(message: "Engine paths saved and reloaded.", isError: false)
        }
    }

    private func clearHistory() {
        appState.historyStore.clear()
        appState.recentHistory = []
        settingsNotice = SettingsNotice(message: "Command history cleared.", isError: false)
    }

    private func runTest() {
        isTesting = true
        testResult = nil

        Task {
            let start = Date()
            do {
                let response = try await appState.needleClient.complete(
                    prompt: "What is my battery status?",
                    maxTokens: 128
                )
                let elapsed = Date().timeIntervalSince(start)
                let calls = response.functionCalls?.map(\.name).joined(separator: ", ") ?? "No tool"
                testResult = TestResult(
                    message: String(format: "Passed in %.2f seconds · %@", elapsed, calls),
                    isSuccess: true
                )
            } catch {
                testResult = TestResult(
                    message: "Test failed: \(error.localizedDescription)",
                    isSuccess: false
                )
            }
            isTesting = false
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 24, tint: tint.opacity(0.12))
    }
}

private struct SettingLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GlassTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
        }
    }
}

private struct PermissionStatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("Status: \(label)")
    }

    private var label: String {
        switch status {
        case .authorized: return "Granted"
        case .notDetermined: return "Not requested"
        case .denied: return "Not allowed"
        case .restricted: return "Unavailable"
        }
    }

    private var systemImage: String {
        switch status {
        case .authorized: return "checkmark.circle.fill"
        case .notDetermined: return "circle.dashed"
        case .denied: return "exclamationmark.circle.fill"
        case .restricted: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .authorized: return .green
        case .notDetermined: return .secondary
        case .denied: return .orange
        case .restricted: return .red
        }
    }
}

private struct TestResultView: View {
    let result: TestResult

    var body: some View {
        Label(
            result.message,
            systemImage: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(result.isSuccess ? .green : .orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct AboutRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsBackdrop: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.055, green: 0.055, blue: 0.07), Color(red: 0.085, green: 0.08, blue: 0.11)]
                    : [Color(white: 0.97), Color(red: 0.93, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.10 : 0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 250, y: -260)

            Circle()
                .fill(Color.purple.opacity(colorScheme == .dark ? 0.08 : 0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -310, y: 300)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct TestResult: Equatable {
    let message: String
    let isSuccess: Bool
}

private struct SettingsNotice: Equatable {
    let message: String
    let isError: Bool
}
