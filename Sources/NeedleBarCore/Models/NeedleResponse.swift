import Foundation

public struct NeedleValidation: Codable, Equatable, Sendable {
    public let ungrounded: [String]?
    public let negation: Bool?

    public init(ungrounded: [String]? = nil, negation: Bool? = nil) {
        self.ungrounded = ungrounded
        self.negation = negation
    }
}

public struct NeedleResponse: Codable, Equatable, Sendable {
    public let type: String?
    public let success: Bool?
    public let error: String?
    public let errorCode: String?
    public let reason: String?
    public let functionCalls: [ToolCall]?
    public let suppressedCalls: [ToolCall]?
    public let reasoning: String?
    public let confidence: Double?
    public let prefillTps: Double?
    public let decodeTps: Double?
    public let peakRamMb: Double?
    public let validation: NeedleValidation?

    enum CodingKeys: String, CodingKey {
        case type
        case success
        case error
        case errorCode = "error_code"
        case reason
        case functionCalls = "function_calls"
        case suppressedCalls = "suppressed_calls"
        case reasoning
        case confidence
        case prefillTps = "prefill_tps"
        case decodeTps = "decode_tps"
        case peakRamMb = "peak_ram_mb"
        case validation
    }

    public init(
        type: String? = "call",
        success: Bool? = true,
        error: String? = nil,
        errorCode: String? = nil,
        reason: String? = nil,
        functionCalls: [ToolCall]? = [],
        suppressedCalls: [ToolCall]? = [],
        reasoning: String? = nil,
        confidence: Double? = 1.0,
        prefillTps: Double? = nil,
        decodeTps: Double? = nil,
        peakRamMb: Double? = nil,
        validation: NeedleValidation? = nil
    ) {
        self.type = type
        self.success = success
        self.error = error
        self.errorCode = errorCode
        self.reason = reason
        self.functionCalls = functionCalls
        self.suppressedCalls = suppressedCalls
        self.reasoning = reasoning
        self.confidence = confidence
        self.prefillTps = prefillTps
        self.decodeTps = decodeTps
        self.peakRamMb = peakRamMb
        self.validation = validation
    }

    public var effectiveCalls: [ToolCall] {
        if let calls = functionCalls, !calls.isEmpty {
            return calls
        }
        return []
    }

    public var hasSuppressedCalls: Bool {
        guard let suppressed = suppressedCalls else { return false }
        return !suppressed.isEmpty
    }
}
