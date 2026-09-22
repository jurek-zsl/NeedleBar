import Foundation

public actor MockNeedleClient: NeedleClientProtocol {
    private var customResponses: [String: NeedleResponse] = [:]
    public var simulatedConfidence: Double = 0.95
    public var shouldThrowError: Error?
    public var isInitialized: Bool = false

    public init() {}

    public func setCustomResponse(for query: String, response: NeedleResponse) {
        customResponses[query.lowercased()] = response
    }

    public func status() async -> NeedleEngineStatus {
        NeedleEngineStatus(
            isLoaded: true,
            engineType: "Mock Client (Development & Testing)",
            modelPath: "mock://needle3.cact",
            libraryPath: "mock://libneedle3.dylib"
        )
    }

    public func initialize(toolsJSON: String, systemPrompt: String? = nil) async throws {
        isInitialized = true
    }

    public func complete(prompt: String, maxTokens: Int = 512) async throws -> NeedleResponse {
        if let err = shouldThrowError {
            throw err
        }

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if let canned = customResponses[lower] {
            return canned
        }

        // Multiple calls check
        if lower.contains("open xcode and terminal") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "open_application", arguments: ["name": AnyCodable("Xcode")]),
                    ToolCall(name: "open_application", arguments: ["name": AnyCodable("Terminal")])
                ],
                reasoning: "Open multiple applications: Xcode and Terminal",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("safari") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "open_application", arguments: ["name": AnyCodable("Safari")])
                ],
                reasoning: "'Safari' -> open_application name 'Safari'",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("focus session") || lower.contains("timer") {
            let minutes = lower.contains("25") ? 25 : 15
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "start_timer", arguments: [
                        "minutes": AnyCodable(minutes),
                        "label": AnyCodable("Focus session")
                    ])
                ],
                reasoning: "Start focus timer for \(minutes) minutes",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("battery") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "get_battery_status", arguments: [:])
                ],
                reasoning: "Query battery status",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("system") || lower.contains("uptime") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "get_system_summary", arguments: [:])
                ],
                reasoning: "Query system summary",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("move screenshot") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "move_file", arguments: [
                        "source": AnyCodable("~/Downloads/screenshot.png"),
                        "destination": AnyCodable("~/Screenshots")
                    ])
                ],
                reasoning: "Move file from Downloads to Screenshots",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("reminder") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "create_reminder", arguments: [
                        "title": AnyCodable("Call Alex"),
                        "due_date": AnyCodable("tomorrow")
                    ])
                ],
                reasoning: "Create reminder to call Alex tomorrow",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("calendar") || lower.contains("meeting") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "create_calendar_event", arguments: [
                        "title": AnyCodable("Team Sync"),
                        "start": AnyCodable("tomorrow 10:00")
                    ])
                ],
                reasoning: "Schedule calendar event",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("search") && lower.contains("notes") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "search_notes", arguments: ["query": AnyCodable("deployment")])
                ],
                reasoning: "Search Apple Notes",
                confidence: simulatedConfidence
            )
        }

        if lower.contains("search") && lower.contains("file") {
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "search_files", arguments: [
                        "query": AnyCodable("invoice"),
                        "directory": AnyCodable("~/Documents")
                    ])
                ],
                reasoning: "Search files in Documents",
                confidence: simulatedConfidence
            )
        }

        // Empty response for unknown or unsupported query
        return NeedleResponse(
            type: "call",
            success: true,
            functionCalls: [],
            suppressedCalls: [],
            reasoning: "No tool available for this query.",
            confidence: simulatedConfidence
        )
    }

    public func embed(text: String) async throws -> [Float] {
        // Generate a deterministic 3072-dimensional embedding based on string hash
        var vector = [Float](repeating: 0.0, count: 3072)
        var hasher = Hasher()
        hasher.combine(text)
        let hash = abs(hasher.finalize())

        for i in 0..<3072 {
            let seed = Float((hash + i) % 1000) / 1000.0
            vector[i] = seed
        }
        return vector
    }

    public func reset() async {}
}
