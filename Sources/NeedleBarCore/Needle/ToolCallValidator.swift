import Foundation

public enum ValidationError: LocalizedError, Equatable {
    case unsupportedRequest(String)
    case unknownTool(String)
    case missingRequiredArgument(tool: String, argument: String)
    case invalidArgumentType(tool: String, argument: String, expected: String)
    case lowConfidence(confidence: Double, reasoning: String)
    case engineError(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRequest(let reason):
            return "NeedleBar cannot perform this request: \(reason)"
        case .unknownTool(let name):
            return "Model requested an unknown tool '\(name)'."
        case .missingRequiredArgument(let tool, let arg):
            return "Tool '\(tool)' requires parameter '\(arg)', which was not found."
        case .invalidArgumentType(let tool, let arg, let expected):
            return "Tool '\(tool)' parameter '\(arg)' must be of type \(expected)."
        case .lowConfidence(let conf, let reason):
            return "Low confidence (\(Int(conf * 100))%): \(reason)"
        case .engineError(let err):
            return "Engine error: \(err)"
        }
    }
}

public final class ToolCallValidator: Sendable {
    private let toolRegistry: ToolRegistry
    private let confirmationPolicy: ConfirmationPolicy

    public init(
        toolRegistry: ToolRegistry,
        confirmationPolicy: ConfirmationPolicy = ConfirmationPolicy()
    ) {
        self.toolRegistry = toolRegistry
        self.confirmationPolicy = confirmationPolicy
    }

    public func validateAndBuildPlan(query: String, response: NeedleResponse) throws -> ExecutionPlan {
        if let err = response.error, !err.isEmpty {
            throw ValidationError.engineError(err)
        }

        // Check if calls are empty or suppressed
        let functionCalls = response.functionCalls ?? []
        let suppressedCalls = response.suppressedCalls ?? []

        if functionCalls.isEmpty && suppressedCalls.isEmpty {
            let reason = response.reasoning ?? "No matching automation tool was found for your command."
            throw ValidationError.unsupportedRequest(reason)
        }

        // Check confidence gating
        let confidence = response.confidence
        if let conf = confidence, conf < confirmationPolicy.mediumConfidenceThreshold {
            let reason = response.reasoning ?? "Could not interpret command with sufficient confidence."
            throw ValidationError.lowConfidence(confidence: conf, reasoning: reason)
        }

        let callsToProcess = !functionCalls.isEmpty ? functionCalls : suppressedCalls
        var steps: [ExecutionStep] = []
        var overallRisk: RiskLevel = .safe
        var planRequiresConfirmation = false

        for (index, call) in callsToProcess.enumerated() {
            guard let tool = toolRegistry.tool(named: call.name) else {
                throw ValidationError.unknownTool(call.name)
            }

            // Validate required parameters
            let def = tool.definition
            if let required = def.parameters.required {
                for req in required {
                    guard let val = call.arguments[req], val.value.base is NSNull == false else {
                        throw ValidationError.missingRequiredArgument(tool: call.name, argument: req)
                    }
                }
            }

            // Evaluate step risk and confirmation requirement
            let stepRisk = tool.riskLevel
            if stepRisk > overallRisk {
                overallRisk = stepRisk
            }

            let decision = confirmationPolicy.evaluate(
                toolName: call.name,
                riskLevel: stepRisk,
                confidence: confidence,
                reasoning: response.reasoning,
                hasSuppressedCalls: response.hasSuppressedCalls
            )

            let stepRequiresConfirmation: Bool
            switch decision {
            case .executeAutomatically:
                stepRequiresConfirmation = false
            case .requiresConfirmation:
                stepRequiresConfirmation = true
                planRequiresConfirmation = true
            case .needsClarification(let q):
                throw ValidationError.lowConfidence(confidence: confidence ?? 0.5, reasoning: q)
            case .unsupported(let u):
                throw ValidationError.unsupportedRequest(u)
            }

            let desc = formatStepDescription(toolName: call.name, arguments: call.arguments)
            let affected = extractAffectedItems(toolName: call.name, arguments: call.arguments)

            let step = ExecutionStep(
                index: index + 1,
                toolCall: call,
                riskLevel: stepRisk,
                requiresConfirmation: stepRequiresConfirmation,
                description: desc,
                affectedItems: affected
            )
            steps.append(step)
        }

        return ExecutionPlan(
            query: query,
            confidence: confidence,
            reasoning: response.reasoning,
            steps: steps,
            requiresConfirmation: planRequiresConfirmation,
            overallRisk: overallRisk,
            status: planRequiresConfirmation ? .awaitingConfirmation : .pending
        )
    }

    private func formatStepDescription(toolName: String, arguments: [String: AnyCodable]) -> String {
        switch toolName {
        case "open_application":
            let name = arguments["name"]?.stringValue ?? "App"
            return "Open application '\(name)'"
        case "quit_application":
            let name = arguments["name"]?.stringValue ?? "App"
            return "Quit application '\(name)'"
        case "open_url":
            let url = arguments["url"]?.stringValue ?? ""
            return "Open web page '\(url)'"
        case "open_folder":
            let path = arguments["path"]?.stringValue ?? ""
            return "Reveal folder '\(path)' in Finder"
        case "search_files":
            let q = arguments["query"]?.stringValue ?? ""
            return "Search files for '\(q)'"
        case "list_recent_files":
            let d = arguments["directory"]?.stringValue ?? "Downloads"
            return "List recent files in '\(d)'"
        case "create_folder":
            let p = arguments["path"]?.stringValue ?? ""
            return "Create new folder at '\(p)'"
        case "move_file":
            let s = arguments["source"]?.stringValue ?? ""
            let d = arguments["destination"]?.stringValue ?? ""
            return "Move '\(s)' to '\(d)'"
        case "rename_file":
            let p = arguments["path"]?.stringValue ?? ""
            let n = arguments["new_name"]?.stringValue ?? ""
            return "Rename '\(p)' to '\(n)'"
        case "start_timer":
            let m = arguments["minutes"]?.intValue ?? 25
            let l = arguments["label"]?.stringValue
            let labelText = l != nil ? " (\(l!))" : ""
            return "Start \(m)-minute focus timer\(labelText)"
        case "create_reminder":
            let t = arguments["title"]?.stringValue ?? ""
            return "Create reminder: '\(t)'"
        case "create_calendar_event":
            let t = arguments["title"]?.stringValue ?? ""
            return "Schedule calendar event: '\(t)'"
        case "get_battery_status":
            return "Query battery percentage and power status"
        case "get_frontmost_application":
            return "Identify current active application"
        case "get_system_summary":
            return "Retrieve system summary and uptime"
        case "search_notes":
            let q = arguments["query"]?.stringValue ?? ""
            return "Search Apple Notes for '\(q)'"
        case "search_command_history":
            let q = arguments["query"]?.stringValue ?? ""
            return "Search command history for '\(q)'"
        default:
            return "Execute \(toolName)"
        }
    }

    private func extractAffectedItems(toolName: String, arguments: [String: AnyCodable]) -> [String] {
        switch toolName {
        case "open_application", "quit_application":
            if let name = arguments["name"]?.stringValue { return [name] }
        case "open_folder":
            if let path = arguments["path"]?.stringValue { return [path] }
        case "move_file":
            var items: [String] = []
            if let s = arguments["source"]?.stringValue { items.append("Source: \(s)") }
            if let d = arguments["destination"]?.stringValue { items.append("Destination: \(d)") }
            return items
        case "rename_file":
            var items: [String] = []
            if let p = arguments["path"]?.stringValue { items.append("Target: \(p)") }
            if let n = arguments["new_name"]?.stringValue { items.append("New Name: \(n)") }
            return items
        case "create_folder":
            if let path = arguments["path"]?.stringValue { return [path] }
        case "create_reminder":
            if let title = arguments["title"]?.stringValue { return ["Reminder: \(title)"] }
        case "create_calendar_event":
            if let title = arguments["title"]?.stringValue { return ["Event: \(title)"] }
        default:
            break
        }
        return []
    }
}
