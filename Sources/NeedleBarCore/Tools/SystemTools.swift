import Foundation

public struct GetBatteryStatusTool: ToolProtocol {
    private let systemInfoService: SystemInfoServiceProtocol

    public init(systemInfoService: SystemInfoServiceProtocol = DefaultSystemInfoService()) {
        self.systemInfoService = systemInfoService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "get_battery_status",
            description: "Get macOS battery percentage, power source, and charging state.",
            parameters: ParametersSchema(),
            triggers: ["\\b(battery|power|charge|percentage)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let (pct, isCharging, powerSource) = systemInfoService.getBatteryStatus()
        let chargingState = isCharging ? "Charging" : "Not Charging"
        let msg = "Battery is at \(pct)%, \(chargingState) via \(powerSource)."
        return .success(
            tool: definition.name,
            message: msg,
            data: [
                "percentage": AnyCodable(pct),
                "is_charging": AnyCodable(isCharging),
                "power_source": AnyCodable(powerSource)
            ]
        )
    }
}

public struct GetFrontmostApplicationTool: ToolProtocol {
    private let workspaceService: WorkspaceServiceProtocol

    public init(workspaceService: WorkspaceServiceProtocol = DefaultWorkspaceService()) {
        self.workspaceService = workspaceService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "get_frontmost_application",
            description: "Get the active frontmost macOS application and its bundle identifier.",
            parameters: ParametersSchema()
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let (name, bundleId) = workspaceService.getFrontmostApplication() else {
            return .failure(tool: definition.name, error: "Could not identify frontmost application.")
        }
        return .success(
            tool: definition.name,
            message: "Frontmost application is \(name) (\(bundleId)).",
            data: ["name": AnyCodable(name), "bundle_id": AnyCodable(bundleId)]
        )
    }
}

public struct GetSystemSummaryTool: ToolProtocol {
    private let systemInfoService: SystemInfoServiceProtocol

    public init(systemInfoService: SystemInfoServiceProtocol = DefaultSystemInfoService()) {
        self.systemInfoService = systemInfoService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "get_system_summary",
            description: "Get an overview of macOS system version, hostname, memory, and uptime.",
            parameters: ParametersSchema()
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let (osVersion, hostName, memory, uptime) = systemInfoService.getSystemSummary()
        let msg = "macOS \(osVersion) on \(hostName), \(memory), Uptime: \(uptime)."
        return .success(
            tool: definition.name,
            message: msg,
            data: [
                "os_version": AnyCodable(osVersion),
                "hostname": AnyCodable(hostName),
                "memory": AnyCodable(memory),
                "uptime": AnyCodable(uptime)
            ]
        )
    }
}
