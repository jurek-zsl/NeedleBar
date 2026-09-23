import Foundation

public struct StartTimerTool: ToolProtocol {
    private let productivityService: ProductivityServiceProtocol

    public init(productivityService: ProductivityServiceProtocol = DefaultProductivityService()) {
        self.productivityService = productivityService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "start_timer",
            description: "Start a countdown timer or focus timer. Use for timers, countdowns, and focus sessions.",
            parameters: ParametersSchema(
                properties: [
                    "minutes": PropertyDefinition(type: "integer", description: "Whole minutes in the duration."),
                    "seconds": PropertyDefinition(type: "integer", description: "Seconds in the duration. Can be used alone or with minutes."),
                    "label": PropertyDefinition(type: "string", description: "Optional description or label for the timer")
                ],
                required: []
            ),
            triggers: ["\\b(timer|countdown|stopwatch|focus session)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }
    public var requiredPermission: PermissionType? { .accessibility }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let hasExplicitDuration = arguments["minutes"] != nil || arguments["seconds"] != nil
        let minutes = arguments["minutes"]?.intValue ?? (hasExplicitDuration ? 0 : 15)
        let seconds = arguments["seconds"]?.intValue ?? 0

        guard minutes >= 0, seconds >= 0 else {
            return .failure(tool: definition.name, error: "Timer duration cannot be negative.")
        }

        let (minuteSeconds, overflowed) = minutes.multipliedReportingOverflow(by: 60)
        guard !overflowed else {
            return .failure(tool: definition.name, error: ClockTimerError.invalidDuration.localizedDescription)
        }
        let (durationSeconds, additionOverflowed) = minuteSeconds.addingReportingOverflow(seconds)
        guard !additionOverflowed,
              let duration = try? TimerDuration(totalSeconds: durationSeconds) else {
            return .failure(tool: definition.name, error: ClockTimerError.invalidDuration.localizedDescription)
        }

        let label = arguments["label"]?.stringValue
        try await productivityService.startTimer(durationSeconds: duration.totalSeconds, label: label)
        let labelText = label != nil ? " ('\(label!)')" : ""
        let timerText: String
        if duration.seconds == 0, duration.hours == 0 {
            timerText = "\(duration.minutes)-minute timer"
        } else if duration.seconds == 0, duration.minutes == 0 {
            timerText = "\(duration.hours)-hour timer"
        } else if duration.hours == 0, duration.minutes == 0 {
            timerText = "\(duration.seconds)-second timer"
        } else {
            timerText = "timer for \(duration.displayText)"
        }
        return .success(tool: definition.name, message: "Started \(timerText)\(labelText) in Clock.")
    }
}

public struct CreateReminderTool: ToolProtocol {
    private let productivityService: ProductivityServiceProtocol

    public init(productivityService: ProductivityServiceProtocol = DefaultProductivityService()) {
        self.productivityService = productivityService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "create_reminder",
            description: "Create a reminder or task in Apple Reminders. Do NOT use for countdown timers or focus timers (use start_timer instead).",
            parameters: ParametersSchema(
                properties: [
                    "title": PropertyDefinition(type: "string", description: "Title or content of the reminder"),
                    "due_date": PropertyDefinition(type: "string", description: "Optional due date or time string, e.g. tomorrow, 2026-09-23")
                ],
                required: ["title"]
            ),
            triggers: ["\\b(remind|reminder|to-do|todo)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .requiresConfirmation }
    public var requiredPermission: PermissionType? { .reminders }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let title = arguments["title"]?.stringValue, !title.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'title' argument for reminder.")
        }

        var parsedDate: Date?
        if let dueStr = arguments["due_date"]?.stringValue, !dueStr.isEmpty {
            parsedDate = parseDateString(dueStr)
        }

        try await productivityService.createReminder(title: title, dueDate: parsedDate)
        let dateMsg = parsedDate != nil ? " due on \(formattedDate(parsedDate!))" : ""
        return .success(tool: definition.name, message: "Created reminder: '\(title)'\(dateMsg).")
    }

    private func parseDateString(_ str: String) -> Date? {
        let lower = str.lowercased()
        let cal = Calendar.current
        if lower.contains("tomorrow") {
            return cal.date(byAdding: .day, value: 1, to: Date())
        }
        if lower.contains("today") {
            return Date()
        }
        let formatter = ISO8601DateFormatter()
        if let d = formatter.date(from: str) { return d }
        let standard = DateFormatter()
        standard.dateFormat = "yyyy-MM-dd"
        return standard.date(from: str)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

public struct CreateCalendarEventTool: ToolProtocol {
    private let productivityService: ProductivityServiceProtocol

    public init(productivityService: ProductivityServiceProtocol = DefaultProductivityService()) {
        self.productivityService = productivityService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "create_calendar_event",
            description: "Create an event in Apple Calendar.",
            parameters: ParametersSchema(
                properties: [
                    "title": PropertyDefinition(type: "string", description: "Title of the calendar event"),
                    "start": PropertyDefinition(type: "string", description: "Start date/time string"),
                    "end": PropertyDefinition(type: "string", description: "Optional end date/time string"),
                    "location": PropertyDefinition(type: "string", description: "Optional location for the event")
                ],
                required: ["title", "start"]
            )
        )
    }

    public var riskLevel: RiskLevel { .requiresConfirmation }
    public var requiredPermission: PermissionType? { .calendar }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let title = arguments["title"]?.stringValue, !title.isEmpty,
              let startStr = arguments["start"]?.stringValue, !startStr.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'title' or 'start' argument.")
        }

        let startDate = parseDate(startStr) ?? Date()
        let endDate: Date
        if let endStr = arguments["end"]?.stringValue, let parsed = parseDate(endStr) {
            endDate = parsed
        } else {
            endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
        }

        let location = arguments["location"]?.stringValue
        try await productivityService.createCalendarEvent(title: title, start: startDate, end: endDate, location: location)
        return .success(tool: definition.name, message: "Scheduled event '\(title)' for \(startDate.description).")
    }

    private func parseDate(_ str: String) -> Date? {
        let lower = str.lowercased()
        let cal = Calendar.current
        if lower.contains("tomorrow") {
            return cal.date(byAdding: .day, value: 1, to: Date())
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: str) { return d }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: str)
    }
}
