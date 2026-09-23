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

    public func validateAndBuildPlan(
        query: String,
        response: NeedleResponse,
        allowLowConfidenceWithConfirmation: Bool = false
    ) throws -> ExecutionPlan {
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

        let rawCalls = !functionCalls.isEmpty ? functionCalls : suppressedCalls

        // Check confidence gating
        let confidence = response.confidence

        // Absolute minimum confidence floor: reject complete hallucinations (< 0.40)
        let minConfidenceFloor: Double = 0.40
        if let conf = confidence, conf < minConfidenceFloor {
            let reason = response.reasoning ?? "NeedleBar could not interpret this command with sufficient confidence."
            throw ValidationError.lowConfidence(confidence: conf, reasoning: reason)
        }

        var planRequiresConfirmation = false
        if let conf = confidence, conf < confirmationPolicy.mediumConfidenceThreshold {
            if allowLowConfidenceWithConfirmation && !rawCalls.isEmpty {
                // Route low-confidence tool calls to user confirmation instead of dropping/failing
                planRequiresConfirmation = true
            } else {
                let reason = response.reasoning ?? "Could not interpret command with sufficient confidence."
                throw ValidationError.lowConfidence(confidence: conf, reasoning: reason)
            }
        }

        // Heal misclassified tool calls (e.g. open_application on URLs or folders)
        let callsToProcess = rawCalls.map { healToolCall($0, query: query) }

        var steps: [ExecutionStep] = []
        var overallRisk: RiskLevel = planRequiresConfirmation ? .requiresConfirmation : .safe

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
                stepRequiresConfirmation = planRequiresConfirmation ? true : false
            case .requiresConfirmation:
                stepRequiresConfirmation = true
                planRequiresConfirmation = true
            case .needsClarification(let q):
                if allowLowConfidenceWithConfirmation {
                    stepRequiresConfirmation = true
                    planRequiresConfirmation = true
                } else {
                    throw ValidationError.lowConfidence(confidence: confidence ?? 0.5, reasoning: q)
                }
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
            let m = arguments["minutes"]?.intValue ?? 0
            let s = arguments["seconds"]?.intValue ?? 0
            let l = arguments["label"]?.stringValue
            let labelText = l != nil ? " (\(l!))" : ""
            let durationText: String
            if m > 0, s > 0 {
                durationText = "\(m) minute\(m == 1 ? "" : "s") \(s) second\(s == 1 ? "" : "s")"
            } else if s > 0 {
                durationText = "\(s) second\(s == 1 ? "" : "s")"
            } else {
                let minutes = m > 0 ? m : 15
                durationText = "\(minutes) minute\(minutes == 1 ? "" : "s")"
            }
            return "Start Clock timer for \(durationText)\(labelText)"
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

    // MARK: - Smart Intent Healing

    public func healToolCall(_ call: ToolCall, query: String) -> ToolCall {
        let lowerQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Healing for open_application
        if call.name == "open_application" {
            let name = call.arguments["name"]?.stringValue ?? ""
            let lowerName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            // A. URL check
            let isURL = lowerName.hasPrefix("http://") ||
                        lowerName.hasPrefix("https://") ||
                        lowerName.hasPrefix("www.") ||
                        ["com", "org", "net", "io", "app", "dev", "edu", "co", "ai", "xyz", "de", "uk", "ca"]
                            .contains(where: { lowerName.hasSuffix("." + $0) || lowerName.contains("." + $0 + "/") })
            if isURL {
                var url = name
                if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
                    url = "https://" + url
                }
                return ToolCall(name: "open_url", arguments: ["url": AnyCodable(url)])
            }

            // B. Folder check
            let folderMappings: [String: String] = [
                "downloads": "~/Downloads",
                "downloads folder": "~/Downloads",
                "download": "~/Downloads",
                "documents": "~/Documents",
                "documents folder": "~/Documents",
                "document": "~/Documents",
                "desktop": "~/Desktop",
                "desktop folder": "~/Desktop",
                "movies": "~/Movies",
                "music": "~/Music",
                "pictures": "~/Pictures",
                "home": "~",
                "applications": "/Applications"
            ]
            if let targetFolder = folderMappings[lowerName] {
                return ToolCall(name: "open_folder", arguments: ["path": AnyCodable(targetFolder)])
            }
            if lowerName.hasPrefix("~/") || lowerName.hasPrefix("/") {
                return ToolCall(name: "open_folder", arguments: ["path": AnyCodable(name)])
            }
            if lowerName.hasSuffix(" folder") {
                let stripped = String(lowerName.dropLast(7)).trimmingCharacters(in: .whitespaces)
                if let mapped = folderMappings[stripped] {
                    return ToolCall(name: "open_folder", arguments: ["path": AnyCodable(mapped)])
                }
            }

            // C. Timer check
            if lowerName.contains("timer") || lowerName.contains("countdown") || lowerName.contains("stopwatch") {
                let m = extractMinutes(from: query)
                let s = extractSeconds(from: query)
                var args: [String: AnyCodable] = [:]
                if m > 0 { args["minutes"] = AnyCodable(m) }
                if s > 0 { args["seconds"] = AnyCodable(s) }
                if args.isEmpty { args["minutes"] = AnyCodable(15) }
                return ToolCall(name: "start_timer", arguments: args)
            }

            // D. Battery check
            if lowerName.contains("battery") || lowerName.contains("charge") || lowerName.contains("power source") {
                return ToolCall(name: "get_battery_status", arguments: [:])
            }

            // E. System summary check
            if lowerName.contains("system summary") || lowerName.contains("system info") || lowerName == "ram" || lowerName == "uptime" {
                return ToolCall(name: "get_system_summary", arguments: [:])
            }
        }

        // 2. Healing for misclassified create_calendar_event
        if call.name == "create_calendar_event" {
            // Misclassified file search?
            if lowerQuery.hasPrefix("find ") || lowerQuery.hasPrefix("search ") ||
               lowerQuery.contains(".pdf") || lowerQuery.contains(".txt") || lowerQuery.contains(".png") || lowerQuery.contains(".jpg") {
                let searchTerm = extractSearchTerm(from: query)
                return ToolCall(name: "search_files", arguments: ["query": AnyCodable(searchTerm)])
            }
            // Misclassified battery?
            if lowerQuery.contains("battery") || lowerQuery.contains("charge") {
                return ToolCall(name: "get_battery_status", arguments: [:])
            }
            // Misclassified system summary?
            if lowerQuery.contains("ram") || lowerQuery.contains("system") || lowerQuery.contains("uptime") {
                return ToolCall(name: "get_system_summary", arguments: [:])
            }
        }

        // 3. Healing for misclassified search_files
        if call.name == "search_files" {
            if lowerQuery.contains("battery") || lowerQuery.contains("charge") {
                return ToolCall(name: "get_battery_status", arguments: [:])
            }
            if lowerQuery.contains("ram") || lowerQuery.contains("system") || lowerQuery.contains("uptime") {
                return ToolCall(name: "get_system_summary", arguments: [:])
            }
            if (lowerQuery.contains("search notes") || lowerQuery.contains("notes for")) && !lowerQuery.contains("file") {
                let q = call.arguments["query"]?.stringValue ?? ""
                return ToolCall(name: "search_notes", arguments: ["query": AnyCodable(q)])
            }
        }

        return call
    }

    private func extractMinutes(from text: String) -> Int {
        let pattern = #"(\d+)\s*(?:min|minute|minutes|m\b)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let m = Int(text[range]) {
            return m
        }
        return 0
    }

    private func extractSeconds(from text: String) -> Int {
        let pattern = #"(\d+)\s*(?:sec|second|seconds|s\b)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let s = Int(text[range]) {
            return s
        }
        return 0
    }

    private func extractSearchTerm(from text: String) -> String {
        var clean = text
        let prefixes = ["search files for ", "search file for ", "search for ", "find files ", "find file ", "find "]
        for prefix in prefixes {
            if clean.lowercased().hasPrefix(prefix) {
                clean = String(clean.dropFirst(prefix.count))
                break
            }
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
