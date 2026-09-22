import Foundation

public enum RiskLevel: String, Codable, Equatable, Comparable, Sendable {
    case safe = "safe"
    case requiresConfirmation = "requires_confirmation"
    case destructive = "destructive"

    private var priority: Int {
        switch self {
        case .safe: return 0
        case .requiresConfirmation: return 1
        case .destructive: return 2
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.priority < rhs.priority
    }

    public var title: String {
        switch self {
        case .safe: return "Safe"
        case .requiresConfirmation: return "Requires Confirmation"
        case .destructive: return "Destructive Action"
        }
    }

    public var iconName: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .requiresConfirmation: return "exclamationmark.shield.fill"
        case .destructive: return "xmark.shield.fill"
        }
    }
}
