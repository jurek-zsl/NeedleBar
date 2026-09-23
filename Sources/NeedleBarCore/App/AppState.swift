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
    @Published public var isHelpPresented: Bool = false

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

        // Connect HelpTool to present interactive help catalog
        registry.register(tool: HelpTool(onPresentHelp: { [weak self] in
            Task { @MainActor [weak self] in
                self?.presentHelp()
            }
        }))

        self.recentHistory = self.historyStore.allRecords()
        self.showOnboarding = !prefs.hasCompletedOnboarding

        Task {
            await self.bootstrapEngine()
        }
    }

    public func presentHelp() {
        self.isHelpPresented = true
        self.errorMessage = nil
        self.activeResult = nil
        self.confirmationPlan = nil
        self.currentPlan = nil
    }

    public func dismissHelp() {
        self.isHelpPresented = false
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

        let normalized = text.lowercased()
        if normalized == "help" || normalized == "/help" || normalized == "?" || normalized == "help me" || normalized == "commands" || normalized == "show help" || normalized == "what can you do" || normalized == "what can i ask" {
            self.presentHelp()
            self.isProcessing = false
            self.statusMessage = nil
            return
        }

        self.isHelpPresented = false
        self.isProcessing = true
        self.errorMessage = nil
        self.activeResult = nil
        self.confirmationPlan = nil
        self.statusMessage = "Analyzing with Needle 3..."

        let startTime = Date()

        // Reset engine conversation buffer to prevent attention pollution from prior commands
        await needleClient.reset()

        do {
            let response = try await resolveNeedleResponse(for: text)
            let plan = try toolValidator.validateAndBuildPlan(
                query: text,
                response: response,
                allowLowConfidenceWithConfirmation: true
            )

            self.currentPlan = plan

            if plan.requiresConfirmation {
                self.confirmationPlan = plan
                self.isProcessing = false
                SoundFeedbackManager.shared.playConfirmationPrompt()
                let confStr = plan.confidence.map { " (confidence: \(Int($0 * 100))%)" } ?? ""
                self.statusMessage = "Confirmation required\(confStr)."
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

    public func resolveNeedleResponse(for text: String) async throws -> NeedleResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Fast-path intent matching for unambiguous deterministic user queries
        if let fastResponse = fastPathResponse(for: trimmed) {
            return fastResponse
        }

        if let chainedClauses = parseChainedClauses(from: trimmed), chainedClauses.count > 1 {
            var combinedCalls: [ToolCall] = []
            var combinedSuppressed: [ToolCall] = []
            var reasonings: [String] = []
            var confidences: [Double] = []

            for clause in chainedClauses {
                let subResponse = try await needleClient.complete(prompt: clause, maxTokens: 256)
                if let calls = subResponse.functionCalls, !calls.isEmpty {
                    combinedCalls.append(contentsOf: calls)
                }
                if let suppressed = subResponse.suppressedCalls, !suppressed.isEmpty {
                    combinedSuppressed.append(contentsOf: suppressed)
                }
                if let reason = subResponse.reasoning, !reason.isEmpty {
                    reasonings.append(reason)
                }
                if let conf = subResponse.confidence {
                    confidences.append(conf)
                }
            }

            if !combinedCalls.isEmpty || !combinedSuppressed.isEmpty {
                let minConf = confidences.min() ?? 0.90
                let combinedReason = reasonings.isEmpty
                    ? "Sequential plan for: \(trimmed)"
                    : reasonings.joined(separator: "; ")
                return NeedleResponse(
                    type: "call",
                    success: true,
                    functionCalls: combinedCalls,
                    suppressedCalls: combinedSuppressed,
                    reasoning: combinedReason,
                    confidence: minConf
                )
            }
        }

        // Fallback or single clause: execute standard inference
        return try await needleClient.complete(prompt: trimmed, maxTokens: 512)
    }

    public func parseChainedClauses(from text: String) -> [String]? {
        let lower = text.lowercased()

        // 1. "after" / "once" connector: reverse order because "A after B" means B then A
        if lower.contains(" after ") {
            let parts = text.components(separatedBy: " after ")
            if parts.count == 2 {
                let first = normalizeActionClause(parts[1])
                let second = normalizeActionClause(parts[0])
                if !first.isEmpty && !second.isEmpty {
                    return [first, second]
                }
            }
        }

        if lower.contains(" once ") {
            let parts = text.components(separatedBy: " once ")
            if parts.count == 2 {
                let first = normalizeActionClause(parts[1])
                let second = normalizeActionClause(parts[0])
                if !first.isEmpty && !second.isEmpty {
                    return [first, second]
                }
            }
        }

        // 2. Sequential forward connectors: "and then", ", then", " then ", "; "
        let sequentialDelimiters = [" and then ", ", then ", " then ", "; "]
        for delim in sequentialDelimiters {
            if lower.contains(delim) {
                let parts = text.components(separatedBy: delim)
                let cleaned = parts.map { normalizeActionClause($0) }.filter { !$0.isEmpty }
                if cleaned.count >= 2 {
                    return cleaned
                }
            }
        }

        // 3. " and " between distinct action verbs
        if lower.contains(" and ") {
            let parts = text.components(separatedBy: " and ")
            if parts.count == 2 {
                let secondLower = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let actionVerbs = ["open", "start", "set", "create", "close", "quit", "search", "list", "move", "mute", "turn", "play", "get", "check"]
                let hasActionVerb = actionVerbs.contains(where: { secondLower.hasPrefix($0 + " ") || secondLower == $0 })
                if hasActionVerb {
                    let first = normalizeActionClause(parts[0])
                    let second = normalizeActionClause(parts[1])
                    if !first.isEmpty && !second.isEmpty {
                        return [first, second]
                    }
                }
            }
        }

        return nil
    }

    private func normalizeActionClause(_ clause: String) -> String {
        var trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(",") { trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if trimmed.hasSuffix(",") || trimmed.hasSuffix(".") { trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) }

        // Normalize gerunds (e.g. "opening Safari" -> "open Safari")
        let gerundReplacements: [(String, String)] = [
            ("opening ", "open "),
            ("starting ", "start "),
            ("closing ", "close "),
            ("quitting ", "quit "),
            ("setting ", "set "),
            ("creating ", "create "),
            ("searching ", "search "),
            ("listing ", "list "),
            ("moving ", "move "),
            ("muting ", "mute "),
            ("checking ", "check "),
            ("turning ", "turn "),
            ("playing ", "play "),
            ("getting ", "get ")
        ]

        let lower = trimmed.lowercased()
        for (gerund, replacement) in gerundReplacements {
            if lower.hasPrefix(gerund) {
                let suffix = trimmed.dropFirst(gerund.count)
                return replacement + suffix
            }
        }
        return trimmed
    }

    public func fastPathResponse(for text: String) -> NeedleResponse? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Direct Web URLs
        // e.g. "open youtube.com in Safari", "open google.com", "open https://apple.com", "google.com"
        var urlCandidate: String?
        let tlds = [".com", ".org", ".net", ".io", ".app", ".dev", ".edu", ".co", ".ai", ".xyz", ".de", ".uk", ".ca"]

        if lower.hasPrefix("open http://") || lower.hasPrefix("open https://") {
            let rest = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            urlCandidate = rest.components(separatedBy: .whitespaces).first
        } else if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            urlCandidate = trimmed.components(separatedBy: .whitespaces).first
        } else if lower.hasPrefix("open www.") {
            let rest = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let domain = rest.components(separatedBy: .whitespaces).first ?? rest
            urlCandidate = "https://" + domain
        } else if lower.hasPrefix("www.") {
            let domain = trimmed.components(separatedBy: .whitespaces).first ?? trimmed
            urlCandidate = "https://" + domain
        } else {
            // Check if any word or token in the query looks like a domain name:
            // e.g. "open youtube.com in Safari" -> finds "youtube.com"
            let tokens = trimmed.components(separatedBy: .whitespaces)
            for token in tokens {
                let lowerToken = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;()\"'"))
                if tlds.contains(where: { lowerToken.hasSuffix($0) || lowerToken.contains($0 + "/") }) {
                    urlCandidate = lowerToken.hasPrefix("http://") || lowerToken.hasPrefix("https://") ? lowerToken : "https://" + lowerToken
                    break
                }
            }
        }

        if let finalURL = urlCandidate, !finalURL.isEmpty {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [ToolCall(name: "open_url", arguments: ["url": AnyCodable(finalURL)])],
                reasoning: "Fast-path: open URL '\(finalURL)'",
                confidence: 1.0
            )
        }

        // 2. Direct Folders
        let folderKeywords: [(String, String)] = [
            ("open downloads", "~/Downloads"),
            ("open downloads folder", "~/Downloads"),
            ("downloads folder", "~/Downloads"),
            ("open documents", "~/Documents"),
            ("open documents folder", "~/Documents"),
            ("documents folder", "~/Documents"),
            ("open desktop", "~/Desktop"),
            ("open desktop folder", "~/Desktop"),
            ("desktop folder", "~/Desktop"),
            ("open home folder", "~"),
            ("open home", "~"),
            ("open applications", "/Applications"),
            ("open applications folder", "/Applications")
        ]
        for (pattern, path) in folderKeywords {
            if lower == pattern {
                return NeedleResponse(
                    type: "call",
                    success: true,
                    functionCalls: [ToolCall(name: "open_folder", arguments: ["path": AnyCodable(path)])],
                    reasoning: "Fast-path: reveal folder '\(path)' in Finder",
                    confidence: 1.0
                )
            }
        }

        // 3. Direct Battery Queries
        let batteryPatterns = [
            "battery status", "what is my battery status", "battery percentage",
            "battery", "how much battery", "check battery", "battery level"
        ]
        if batteryPatterns.contains(lower) {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [ToolCall(name: "get_battery_status", arguments: [:])],
                reasoning: "Fast-path: query battery status",
                confidence: 1.0
            )
        }

        // 4. Direct System Summary Queries
        let systemPatterns = [
            "system summary", "what is my system summary", "system info",
            "mac specs", "system status", "system overview"
        ]
        if systemPatterns.contains(lower) {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [ToolCall(name: "get_system_summary", arguments: [:])],
                reasoning: "Fast-path: query system summary",
                confidence: 1.0
            )
        }

        return nil
    }

    public func updateConfirmationPlan(_ plan: ExecutionPlan) {
        self.confirmationPlan = plan
        self.currentPlan = plan
    }

    public func updatePlanArgument(stepId: UUID, key: String, value: String) {
        guard var plan = confirmationPlan else { return }
        guard let stepIndex = plan.steps.firstIndex(where: { $0.id == stepId }) else { return }

        var step = plan.steps[stepIndex]
        var args = step.toolCall.arguments

        if let _ = args[key]?.intValue, let intVal = Int(value) {
            args[key] = AnyCodable(intVal)
        } else if let _ = args[key]?.boolValue {
            args[key] = AnyCodable(value.lowercased() == "true")
        } else {
            args[key] = AnyCodable(value)
        }

        let updatedToolCall = ToolCall(name: step.toolCall.name, arguments: args)
        step = ExecutionStep(
            id: step.id,
            index: step.index,
            toolCall: updatedToolCall,
            riskLevel: step.riskLevel,
            requiresConfirmation: step.requiresConfirmation,
            description: step.description,
            affectedItems: step.affectedItems,
            status: step.status,
            result: step.result
        )

        plan.steps[stepIndex] = step
        self.confirmationPlan = plan
        self.currentPlan = plan
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
        if allSucceeded {
            SoundFeedbackManager.shared.playSuccess()
        } else {
            SoundFeedbackManager.shared.playFailure()
        }

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
