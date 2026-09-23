import Foundation
import AppKit

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let content: String
    public let timestamp: Date

    public init(id: UUID = UUID(), content: String, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }
}

public actor ClipboardService {
    public static let shared = ClipboardService()

    private var history: [ClipboardItem] = []
    private var lastChangeCount: Int
    private let maxItems: Int
    private let monitorSystemPasteboard: Bool

    public init(maxItems: Int = 50, monitorSystemPasteboard: Bool = true) {
        self.maxItems = maxItems
        self.monitorSystemPasteboard = monitorSystemPasteboard
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    public func pollPasteboard() {
        guard monitorSystemPasteboard else { return }
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            record(text: text)
        }
    }

    public func record(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Deduplicate if same as most recent
        if let first = history.first, first.content == trimmed {
            return
        }

        let item = ClipboardItem(content: trimmed)
        history.insert(item, at: 0)

        if history.count > maxItems {
            history.removeLast(history.count - maxItems)
        }
    }

    public func getRecent(limit: Int = 10) -> [ClipboardItem] {
        pollPasteboard()
        return Array(history.prefix(max(1, limit)))
    }

    public func copyToPasteboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        record(text: text)
    }

    public func clear() {
        history.removeAll()
    }
}
