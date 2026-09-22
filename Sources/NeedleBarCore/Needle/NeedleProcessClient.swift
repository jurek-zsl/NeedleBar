import Foundation

public actor NeedleProcessClient: NeedleClientProtocol {
    private let binaryPath: String
    private let modelPath: String
    private var toolsFilePath: String?
    private var isInitialized: Bool = false

    public init(
        binaryPath: String = "/tmp/needle-test/needle",
        modelPath: String = "/tmp/needle-test/needle3.cact"
    ) {
        self.binaryPath = binaryPath
        self.modelPath = modelPath
    }

    public func status() async -> NeedleEngineStatus {
        let binExists = FileManager.default.fileExists(atPath: binaryPath)
        let modelExists = FileManager.default.fileExists(atPath: modelPath)
        return NeedleEngineStatus(
            isLoaded: binExists && modelExists,
            engineType: "Subprocess CLI Runner (needle)",
            modelPath: modelPath,
            libraryPath: binaryPath,
            errorDescription: (!binExists || !modelExists) ? "Binary or weights missing." : nil
        )
    }

    public func initialize(toolsJSON: String, systemPrompt: String? = nil) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let toolsURL = tempDir.appendingPathComponent("needle_tools_\(UUID().uuidString).json")
        try toolsJSON.write(to: toolsURL, atomically: true, encoding: .utf8)
        self.toolsFilePath = toolsURL.path
        self.isInitialized = true
    }

    public func complete(prompt: String, maxTokens: Int = 512) async throws -> NeedleResponse {
        guard let toolsPath = toolsFilePath else {
            throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "NeedleProcessClient is not initialized with tool schemas."
            ])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "--model", modelPath,
            "--tools", toolsPath,
            "--prompt", prompt,
            "--max", "\(maxTokens)"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown process error"
            throw NSError(domain: "NeedleBar", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Needle process failed: \(errMsg)"
            ])
        }

        let decoder = JSONDecoder()
        return try decoder.decode(NeedleResponse.self, from: data)
    }

    public func embed(text: String) async throws -> [Float] {
        // Embeddings are primarily serviced by the in-process bridge or fallback
        return [Float](repeating: 0.0, count: 3072)
    }

    public func reset() async {}
}
