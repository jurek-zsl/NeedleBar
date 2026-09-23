import Foundation
import PDFKit

public struct DocumentSearchResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let filePath: String
    public let fileName: String
    public let snippet: String
    public let score: Float

    public init(id: UUID = UUID(), filePath: String, fileName: String, snippet: String, score: Float) {
        self.id = id
        self.filePath = filePath
        self.fileName = fileName
        self.snippet = snippet
        self.score = score
    }
}

public actor LocalDocumentIndexer {
    public static let shared = LocalDocumentIndexer()

    private let index: EmbeddingIndex
    private var indexedPaths: Set<String> = []
    private var hasInitialIndexed: Bool = false
    private let autoIndexCommonDirectories: Bool

    public init(client: (any NeedleClientProtocol)? = nil, autoIndexCommonDirectories: Bool = true) {
        self.index = EmbeddingIndex(client: client)
        self.autoIndexCommonDirectories = autoIndexCommonDirectories
    }

    public func indexFile(at url: URL) async {
        let path = url.path
        guard !indexedPaths.contains(path) else { return }
        indexedPaths.insert(path)

        guard let text = extractText(from: url), !text.isEmpty else { return }

        // Take the first 3000 chars for semantic indexing
        let snippet = String(text.prefix(3000))
        await index.addItem(
            text: snippet,
            category: "document",
            metadata: [
                "path": path,
                "fileName": url.lastPathComponent
            ]
        )
    }

    public func indexCommonDirectories(limitPerDir: Int = 30) async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let targetDirs = [
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop")
        ]

        let extensions: Set<String> = ["txt", "md", "markdown", "pdf", "rtf", "swift", "py", "json", "csv"]

        for dir in targetDirs {
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            var count = 0
            while let fileURL = enumerator.nextObject() as? URL {
                if extensions.contains(fileURL.pathExtension.lowercased()) {
                    await indexFile(at: fileURL)
                    count += 1
                    if count >= limitPerDir { break }
                }
            }
        }
        hasInitialIndexed = true
    }

    public func search(query: String, topK: Int = 5) async -> [DocumentSearchResult] {
        if autoIndexCommonDirectories && !hasInitialIndexed {
            await indexCommonDirectories(limitPerDir: 20)
        }

        let matches = await index.search(query: query, topK: topK)
        return matches.map { match in
            DocumentSearchResult(
                id: match.id,
                filePath: match.item.metadata["path"] ?? "",
                fileName: match.item.metadata["fileName"] ?? "Unknown",
                snippet: match.item.text,
                score: match.score
            )
        }
    }

    private func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { return nil }
            var result = ""
            let maxPages = min(pdf.pageCount, 5)
            for i in 0..<maxPages {
                if let page = pdf.page(at: i), let pageStr = page.string {
                    result += pageStr + "\n"
                }
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let str = try? String(contentsOf: url, encoding: .utf8) {
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }
}
