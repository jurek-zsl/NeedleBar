import Foundation

public struct StartTimerTool: ToolProtocol {
    private let productivityService: ProductivityServiceProtocol

    public init(productivityService: ProductivityServiceProtocol = DefaultProductivityService()) {
        self.productivityService = productivityService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "start_timer",
            description: "Start a countdown focus timer for a specified number of minutes.",
            parameters: ParametersSchema(
                properties: [
                    "minutes": PropertyDefinition(type: "integer", description: "Duration in minutes"),
                    "label": PropertyDefinition(type: "string", description: "Optional description or label for the timer")
                ],
                required: ["minutes"]
            )
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let minutes = arguments["minutes"]?.intValue, minutes > 0 else {
            return .failure(tool: definition.name, error: "Missing or invalid 'minutes' parameter.")
        }
        let label = arguments["label"]?.stringValue
        try await productivityService.startTimer(minutes: minutes, label: label)
        let labelText = label != nil ? " ('\(label!)')" : ""
        return .success(tool: definition.name, message: "Started \(minutes)-minute timer\(labelText).")
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
            description: "Create a reminder in Apple Reminders.",
            parameters: ParametersSchema(
                properties: [
                    "title": PropertyDefinition(type: "string", description: "Title or content of the reminder"),
                    "due_date": PropertyDefinition(type: "string", description: "Optional due date or time string, e.g. tomorrow, 2026-09-23")
                ],
                required: ["title"]
            )
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
