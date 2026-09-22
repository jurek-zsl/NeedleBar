import Foundation
import SwiftUI
import Combine

public enum AppTab: String, CaseIterable, Identifiable {
    public var id: String { rawValue }
    case command = "Command"
    case history = "History"
    case settings = "Settings"
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var inputQuery: String = ""
    @Published public var isProcessing: Bool = false
    @Published public var currentPlan: ExecutionPlan?
    @Published public var confirmationPlan: ExecutionPlan?
    @Published public var activeResult: ExecutionResult?
    @Published public var errorMessage: String?
    @Published public var engineStatus: NeedleEngineStatus = .notLoaded
    @Published public var recentHistory: [HistoryRecord] = []
    @Published public var selectedTab: AppTab = .command
    @Published public var showOnboarding: Bool = false
    @Published public var statusMessage: String?

    public let needleClient: any NeedleClientProtocol
    public let toolRegistry: ToolRegistry
    public let toolValidator: ToolCallValidator
    public let historyStore: CommandHistoryStore
    public let preferencesStore: PreferencesStore
    public let embeddingIndex: EmbeddingIndex
    public let permissionManager: PermissionManager

    public init(
        needleClient: (any NeedleClientProtocol)? = nil,
        toolRegistry: ToolRegistry? = nil,
        historyStore: CommandHistoryStore? = nil,
        preferencesStore: PreferencesStore = .shared,
        permissionManager: PermissionManager = .shared
    ) {
        let prefs = preferencesStore
        self.preferencesStore = prefs
        self.historyStore = historyStore ?? CommandHistoryStore()
        self.permissionManager = permissionManager

        // Configure engine client
        let client: any NeedleClientProtocol
        if let customClient = needleClient {
            client = customClient
        } else if prefs.useMockEngine {
            client = MockNeedleClient()
        } else {
            // Attempt in-process C bridge first, with fallback to Mock if files not yet present
            let cBridge = NeedleCBridge(
                libraryPath: prefs.libraryPath,
                modelPath: prefs.modelPath
            )
            client = cBridge
        }
        self.needleClient = client

        self.embeddingIndex = EmbeddingIndex(client: client)

        // Configure tool registry
        let histStore = self.historyStore
        let registry = toolRegistry ?? ToolRegistry.createDefaultRegistry(
            historySearch: { query in
                histStore.search(query: query)
            }
        )
        self.toolRegistry = registry
        self.toolValidator = ToolCallValidator(toolRegistry: registry)

        self.recentHistory = self.historyStore.allRecords()
        self.showOnboarding = !prefs.hasCompletedOnboarding

        Task {
            await self.bootstrapEngine()
        }
    }

    public func bootstrapEngine() async {
        do {
            let toolsJSON = try toolRegistry.generateSchemasJSON()
            try await needleClient.initialize(toolsJSON: toolsJSON, systemPrompt: nil)
            self.engineStatus = await needleClient.status()
        } catch {
            self.engineStatus = NeedleEngineStatus(
                isLoaded: false,
                engineType: "In-Process C Bridge",
                errorDescription: error.localizedDescription
            )
        }
    }

    public func submitCommand(_ query: String? = nil) async {
        let text = (query ?? inputQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        self.isProcessing = true
        self.errorMessage = nil
        self.activeResult = nil
        self.confirmationPlan = nil
        self.statusMessage = "Analyzing with Needle 3..."

        let startTime = Date()

        do {
            let response = try await needleClient.complete(prompt: text, maxTokens: 512)
            let plan = try toolValidator.validateAndBuildPlan(query: text, response: response)

            self.currentPlan = plan

            if plan.requiresConfirmation {
                self.confirmationPlan = plan
                self.isProcessing = false
                self.statusMessage = "Confirmation required."
                return
            }

            // Execute automatically
            await executePlan(plan, startTime: startTime)

        } catch {
            self.errorMessage = error.localizedDescription
            self.isProcessing = false
            self.statusMessage = nil

            let record = HistoryRecord(
                query: text,
                toolNames: [],
                success: false,
                summary: error.localizedDescription,
                confidence: nil,
                riskLevel: .safe
            )
            self.historyStore.append(record)
            self.recentHistory = self.historyStore.allRecords()
        }
    }

    public func confirmPlan() async {
        guard let plan = confirmationPlan else { return }
        self.confirmationPlan = nil
        self.isProcessing = true
        let startTime = Date()
        await executePlan(plan, startTime: startTime)
    }

    public func cancelPlan() {
        if let plan = confirmationPlan {
            let record = HistoryRecord(
                query: plan.query,
                toolNames: plan.steps.map { $0.toolCall.name },
                success: false,
                summary: "User cancelled action.",
                confidence: plan.confidence,
                riskLevel: plan.overallRisk
            )
            historyStore.append(record)
            recentHistory = historyStore.allRecords()
        }
        self.confirmationPlan = nil
        self.currentPlan = nil
        self.isProcessing = false
        self.statusMessage = "Action cancelled."
    }

    private func executePlan(_ plan: ExecutionPlan, startTime: Date) async {
        var updatedSteps = plan.steps
        var results: [ToolResult] = []
        var allSucceeded = true

        for i in 0..<updatedSteps.count {
            updatedSteps[i].status = .running
            self.currentPlan?.steps = updatedSteps
            self.statusMessage = "Executing: \(updatedSteps[i].description)..."

            let call = updatedSteps[i].toolCall
            guard let tool = toolRegistry.tool(named: call.name) else {
                let err = ToolResult.failure(tool: call.name, error: "Tool '\(call.name)' not found.")
                results.append(err)
                updatedSteps[i].status = .failed
                updatedSteps[i].result = err
                allSucceeded = false
                break
            }

            do {
                let res = try await tool.execute(arguments: call.arguments)
                results.append(res)
                updatedSteps[i].status = res.success ? .succeeded : .failed
                updatedSteps[i].result = res
                if !res.success {
                    allSucceeded = false
                    break
                }
            } catch {
                let err = ToolResult.failure(tool: call.name, error: error.localizedDescription)
                results.append(err)
                updatedSteps[i].status = .failed
                updatedSteps[i].result = err
                allSucceeded = false
                break
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let summary = results.map { $0.message }.joined(separator: "\n")
        let execResult = ExecutionResult(
            query: plan.query,
            success: allSucceeded,
            results: results,
            summary: summary,
            duration: duration
        )

        self.activeResult = execResult
        self.isProcessing = false
        self.statusMessage = allSucceeded ? "Completed successfully." : "Execution failed."

        var finishedPlan = plan
        finishedPlan.steps = updatedSteps
        finishedPlan.status = allSucceeded ? .completed : .failed
        self.currentPlan = finishedPlan

        let record = HistoryRecord(
            query: plan.query,
            toolNames: plan.steps.map { $0.toolCall.name },
            success: allSucceeded,
            summary: summary,
            confidence: plan.confidence,
            riskLevel: plan.overallRisk
        )
        self.historyStore.append(record)
        self.recentHistory = self.historyStore.allRecords()

        // Index in local embedding store
        await self.embeddingIndex.addItem(
            text: plan.query,
            category: "command",
            metadata: ["summary": summary]
        )

        self.inputQuery = ""
    }

    public func clearCurrentResult() {
        self.currentPlan = nil
        self.activeResult = nil
        self.errorMessage = nil
        self.statusMessage = nil
    }

    public func dismissOnboarding() {
        self.showOnboarding = false
        self.preferencesStore.hasCompletedOnboarding = true
    }

    public func testEngine() async {
        self.statusMessage = "Testing Needle 3 engine..."
        await submitCommand("What is my battery status?")
    }
}
