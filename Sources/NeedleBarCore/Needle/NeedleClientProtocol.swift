import Foundation

public struct NeedleEngineStatus: Equatable, Sendable {
    public let isLoaded: Bool
    public let engineType: String
    public let modelPath: String?
    public let libraryPath: String?
    public let errorDescription: String?

    public init(
        isLoaded: Bool,
        engineType: String,
        modelPath: String? = nil,
        libraryPath: String? = nil,
        errorDescription: String? = nil
    ) {
        self.isLoaded = isLoaded
        self.engineType = engineType
        self.modelPath = modelPath
        self.libraryPath = libraryPath
        self.errorDescription = errorDescription
    }

    public static var notLoaded: NeedleEngineStatus {
        NeedleEngineStatus(isLoaded: false, engineType: "None", errorDescription: "Model weights not loaded.")
    }
}

public protocol NeedleClientProtocol: Sendable {
    func initialize(toolsJSON: String, systemPrompt: String?) async throws
    func complete(prompt: String, maxTokens: Int) async throws -> NeedleResponse
    func embed(text: String) async throws -> [Float]
    func reset() async
    func status() async -> NeedleEngineStatus
}
