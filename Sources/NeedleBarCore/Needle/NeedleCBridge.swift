import Foundation

public final class NeedleCBridge: NeedleClientProtocol, @unchecked Sendable {
    private typealias NeedleInitFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    private typealias NeedleLastErrorFn = @convention(c) () -> UnsafePointer<CChar>?
    private typealias NeedleCompleteFn = @convention(c) (UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<CChar>?, Int32) -> Int32
    private typealias NeedleEmbedFn = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<Float>?, Int32) -> Int32
    private typealias NeedleResetFn = @convention(c) () -> Void
    private typealias NeedleLoadFn = @convention(c) (UnsafePointer<UInt8>?, UInt64) -> Int32

    private let lock = NSLock()
    private var dylibHandle: UnsafeMutableRawPointer?
    private var fnInit: NeedleInitFn?
    private var fnLastError: NeedleLastErrorFn?
    private var fnComplete: NeedleCompleteFn?
    private var fnEmbed: NeedleEmbedFn?
    private var fnReset: NeedleResetFn?
    private var fnLoad: NeedleLoadFn?

    private var isModelLoaded: Bool = false
    private var activeLibraryPath: String?
    private var activeModelPath: String?
    private var lastErrorDetail: String?

    private var currentToolsJSON: String = "[]"
    private var currentSystemPrompt: String = ""

    public init(libraryPath: String? = nil, modelPath: String? = nil) {
        self.activeLibraryPath = libraryPath
        self.activeModelPath = modelPath
    }

    deinit {
        if let handle = dylibHandle {
            dlclose(handle)
        }
    }

    public func status() async -> NeedleEngineStatus {
        lock.withLock {
            NeedleEngineStatus(
                isLoaded: isModelLoaded,
                engineType: "In-Process C Bridge (libneedle3.dylib)",
                modelPath: activeModelPath,
                libraryPath: activeLibraryPath,
                errorDescription: lastErrorDetail
            )
        }
    }

    public func initialize(toolsJSON: String, systemPrompt: String? = nil) async throws {
        try lock.withLock {
            self.currentToolsJSON = toolsJSON
            self.currentSystemPrompt = systemPrompt ?? defaultSystemPrompt()

            if dylibHandle == nil {
                try loadDylib()
            }

            if !isModelLoaded {
                try loadWeights()
            }

            try configureSession()
        }
    }

    public func complete(prompt: String, maxTokens: Int = 512) async throws -> NeedleResponse {
        try lock.withLock {
            guard isModelLoaded, let fnComplete = self.fnComplete else {
                throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Needle 3 engine is not loaded. Cannot execute prompt."
                ])
            }

            let bufferCapacity = 65536
            var buffer = [CChar](repeating: 0, count: bufferCapacity)

            let rc = prompt.withCString { promptPtr in
                fnComplete(promptPtr, Int32(maxTokens), &buffer, Int32(bufferCapacity))
            }

            guard rc >= 0 else {
                let err = currentLastError(fallback: "needle_complete failed with code \(rc)")
                self.lastErrorDetail = err
                throw NSError(domain: "NeedleBar", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: err])
            }

            let outputString = buffer.withUnsafeBufferPointer { ptr -> String in
                if let base = ptr.baseAddress {
                    return String(cString: base)
                }
                return ""
            }
            guard let data = outputString.data(using: .utf8) else {
                throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to decode Needle 3 JSON output."
                ])
            }

            let decoder = JSONDecoder()
            return try decoder.decode(NeedleResponse.self, from: data)
        }
    }

    public func embed(text: String) async throws -> [Float] {
        try lock.withLock {
            guard isModelLoaded, let fnEmbed = self.fnEmbed else {
                throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Needle 3 engine is not loaded for embeddings."
                ])
            }

            let dim = text.withCString { ptr in
                fnEmbed(ptr, nil, 0)
            }

            guard dim > 0 else {
                let err = currentLastError(fallback: "needle_embed query failed (dim \(dim))")
                throw NSError(domain: "NeedleBar", code: Int(dim), userInfo: [NSLocalizedDescriptionKey: err])
            }

            var vector = [Float](repeating: 0.0, count: Int(dim))
            let erc = text.withCString { ptr in
                fnEmbed(ptr, &vector, dim)
            }

            guard erc == dim else {
                throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "needle_embed failed to return full vector dimension."
                ])
            }

            return vector
        }
    }

    public func reset() async {
        lock.withLock {
            fnReset?()
        }
    }

    // MARK: - Private Loading Helpers

    private func loadDylib() throws {
        let path = try resolveLibraryPath()
        guard let handle = dlopen(path, RTLD_NOW) else {
            let err = String(cString: dlerror())
            self.lastErrorDetail = "dlopen failed for \(path): \(err)"
            throw NSError(domain: "NeedleBar", code: 500, userInfo: [NSLocalizedDescriptionKey: self.lastErrorDetail!])
        }

        self.dylibHandle = handle
        self.activeLibraryPath = path

        self.fnInit = unsafeBitCast(dlsym(handle, "needle_init"), to: NeedleInitFn?.self)
        self.fnLastError = unsafeBitCast(dlsym(handle, "needle_last_error"), to: NeedleLastErrorFn?.self)
        self.fnComplete = unsafeBitCast(dlsym(handle, "needle_complete"), to: NeedleCompleteFn?.self)
        self.fnEmbed = unsafeBitCast(dlsym(handle, "needle_embed"), to: NeedleEmbedFn?.self)
        self.fnReset = unsafeBitCast(dlsym(handle, "needle_reset"), to: NeedleResetFn?.self)
        self.fnLoad = unsafeBitCast(dlsym(handle, "needle_load"), to: NeedleLoadFn?.self)

        guard fnInit != nil, fnComplete != nil, fnLoad != nil else {
            throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Required Needle symbols missing from \(path)."
            ])
        }
    }

    private func loadWeights() throws {
        guard let fnLoad = self.fnLoad else {
            throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Cannot load weights: needle_load symbol is not bound."
            ])
        }

        let modelPath = try resolveModelPath()
        let modelURL = URL(fileURLWithPath: modelPath)
        let data = try Data(contentsOf: modelURL)

        let rc = data.withUnsafeBytes { rawBuffer -> Int32 in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return fnLoad(baseAddress, UInt64(data.count))
        }

        guard rc >= 0 else {
            let err = currentLastError(fallback: "needle_load failed (code \(rc))")
            self.lastErrorDetail = err
            throw NSError(domain: "NeedleBar", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: err])
        }

        self.isModelLoaded = true
        self.activeModelPath = modelPath
    }

    private func configureSession() throws {
        guard let fnInit = self.fnInit else { return }

        let rc = currentSystemPrompt.withCString { sysPtr in
            currentToolsJSON.withCString { toolsPtr in
                fnInit(sysPtr, toolsPtr, nil)
            }
        }

        guard rc >= 0 else {
            let err = currentLastError(fallback: "needle_init failed (code \(rc))")
            self.lastErrorDetail = err
            throw NSError(domain: "NeedleBar", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    private func currentLastError(fallback: String) -> String {
        if let fn = fnLastError, let ptr = fn() {
            return String(cString: ptr)
        }
        return fallback
    }

    private func resolveLibraryPath() throws -> String {
        if let explicit = activeLibraryPath, FileManager.default.fileExists(atPath: explicit) {
            return explicit
        }

        if let env = ProcessInfo.processInfo.environment["NEEDLE3_LIB_PATH"], FileManager.default.fileExists(atPath: env) {
            return env
        }

        let standardCandidates = [
            NSHomeDirectory() + "/.cache/cactus-needle/v3/3.0.1/libneedle3.dylib",
            NSHomeDirectory() + "/.cache/cactus-needle/v3/3.0.1/libneedle.dylib",
            "/tmp/needle-test/libneedle3.dylib",
            Bundle.main.bundlePath + "/Contents/Frameworks/libneedle3.dylib",
            Bundle.main.resourcePath.map { $0 + "/libneedle3.dylib" } ?? ""
        ]

        for cand in standardCandidates where !cand.isEmpty {
            if FileManager.default.fileExists(atPath: cand) {
                return cand
            }
        }

        throw NSError(domain: "NeedleBar", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "libneedle3.dylib not found. Run scripts/fetch_needle_engine.sh or configure in Settings."
        ])
    }

    private func resolveModelPath() throws -> String {
        if let explicit = activeModelPath, FileManager.default.fileExists(atPath: explicit) {
            return explicit
        }

        if let env = ProcessInfo.processInfo.environment["NEEDLE3_MODEL_PATH"], FileManager.default.fileExists(atPath: env) {
            return env
        }

        let standardCandidates = [
            NSHomeDirectory() + "/.cache/cactus-needle/v3/3.0.1/needle3.cact",
            "/tmp/needle-test/needle3.cact",
            Bundle.main.resourcePath.map { $0 + "/needle3.cact" } ?? ""
        ]

        for cand in standardCandidates where !cand.isEmpty {
            if FileManager.default.fileExists(atPath: cand) {
                return cand
            }
        }

        throw NSError(domain: "NeedleBar", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "needle3.cact model weights not found. Run scripts/fetch_needle_engine.sh or configure in Settings."
        ])
    }

    private func defaultSystemPrompt() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEE HH:mm"
        let dateStr = f.string(from: Date())
        return "date: \(dateStr); locale: en-US; device: mac"
    }
}
