import Foundation

public actor MockNeedleClient: NeedleClientProtocol {
    private var customResponses: [String: NeedleResponse] = [:]
    public var simulatedConfidence: Double = 0.95
    public var shouldThrowError: Error?
    public var isInitialized: Bool = false

    public init(simulatedConfidence: Double = 0.95) {
        self.simulatedConfidence = simulatedConfidence
    }

    public func setSimulatedConfidence(_ conf: Double) {
        self.simulatedConfidence = conf
    }

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

        if lower.contains("safari") && (lower.contains("timer") || lower.contains("countdown") || lower.contains("focus")) {
            let minutes = 5
            let calls: [ToolCall]
            if lower.contains("after") && lower.hasPrefix("start timer") {
                // "start timer 5 min after opening Safari" -> open Safari first, then timer
                calls = [
                    ToolCall(name: "open_application", arguments: ["name": AnyCodable("Safari")]),
                    ToolCall(name: "start_timer", arguments: ["minutes": AnyCodable(minutes), "label": AnyCodable("Focus session")])
                ]
            } else {
                calls = [
                    ToolCall(name: "open_application", arguments: ["name": AnyCodable("Safari")]),
                    ToolCall(name: "start_timer", arguments: ["minutes": AnyCodable(minutes), "label": AnyCodable("Focus session")])
                ]
            }
            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: calls,
                reasoning: "Open Safari and start timer for \(minutes) minutes",
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

        if lower.contains("focus session") || lower.contains("timer") || lower.contains("countdown") || lower.contains("stopwatch") {
            let secondsPattern = #"(\d+)\s*(?:sec|second|seconds|s\b)"#
            if let regex = try? NSRegularExpression(pattern: secondsPattern),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let range = Range(match.range(at: 1), in: lower),
               let seconds = Int(lower[range]), seconds > 0 {
                return NeedleResponse(
                    type: "call",
                    success: true,
                    functionCalls: [
                        ToolCall(name: "start_timer", arguments: [
                            "seconds": AnyCodable(seconds),
                            "label": AnyCodable("Focus session")
                        ])
                    ],
                    reasoning: "Start focus timer for \(seconds) seconds",
                    confidence: simulatedConfidence
                )
            }

            var minutes = 15
            let pattern = #"(\d+)\s*(?:min|minute|minutes|m\b)?"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let range = Range(match.range(at: 1), in: lower),
               let parsed = Int(lower[range]), parsed > 0 {
                minutes = parsed
            } else if lower.contains("25") {
                minutes = 25
            } else if lower.contains("5") {
                minutes = 5
            }

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

        if (lower.contains("reminder") || lower.contains("remind") || lower.contains("todo")) && !lower.contains("timer") {
            let title = lower.replacingOccurrences(of: "create reminder", with: "")
                .replacingOccurrences(of: "reminder", with: "")
                .replacingOccurrences(of: "remind me to", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = title.isEmpty ? "Call Alex" : title.capitalized

            return NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "create_reminder", arguments: [
                        "title": AnyCodable(finalTitle),
                        "due_date": AnyCodable("tomorrow")
                    ])
                ],
                reasoning: "Create reminder: '\(finalTitle)'",
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
