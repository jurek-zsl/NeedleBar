import Foundation

public final class CommandHistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var cachedRecords: [HistoryRecord] = []

    public init(storageURL: URL? = nil) {
        if let custom = storageURL {
            self.fileURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent("NeedleBar", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.fileURL = appDir.appendingPathComponent("history.json")
        }
        load()
    }

    public func append(_ record: HistoryRecord) {
        lock.lock()
        defer { lock.unlock() }
        cachedRecords.insert(record, at: 0)
        if cachedRecords.count > 500 {
            cachedRecords = Array(cachedRecords.prefix(500))
        }
        persist()
    }

    public func allRecords() -> [HistoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return cachedRecords
    }

    public func search(query: String) -> [HistoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        let q = query.lowercased()
        return cachedRecords.filter {
            $0.query.lowercased().contains(q) || $0.summary.lowercased().contains(q)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cachedRecords.removeAll()
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            cachedRecords = try decoder.decode([HistoryRecord].self, from: data)
        } catch {
            cachedRecords = []
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(cachedRecords)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silently fail or log in debug
        }
    }
}
