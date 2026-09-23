import Foundation

public final class PreferencesStore: @unchecked Sendable {
    public static let shared = PreferencesStore()

    private let defaults: UserDefaults
    private let lock = NSLock()

    private enum Keys {
        static let modelPath = "NeedleBar.modelPath"
        static let libraryPath = "NeedleBar.libraryPath"
        static let globalShortcut = "NeedleBar.globalShortcut"
        static let launchAtLogin = "NeedleBar.launchAtLogin"
        static let telemetryEnabled = "NeedleBar.telemetryEnabled"
        static let indexedDirectories = "NeedleBar.indexedDirectories"
        static let hasCompletedOnboarding = "NeedleBar.hasCompletedOnboarding"
        static let useMockEngine = "NeedleBar.useMockEngine"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var modelPath: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.string(forKey: Keys.modelPath) ?? (NSHomeDirectory() + "/.cache/cactus-needle/v3/3.0.1/needle3.cact")
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.modelPath)
        }
    }

    public var libraryPath: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.string(forKey: Keys.libraryPath) ?? (NSHomeDirectory() + "/.cache/cactus-needle/v3/3.0.1/libneedle3.dylib")
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.libraryPath)
        }
    }

    public var globalShortcut: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.string(forKey: Keys.globalShortcut) ?? "⌘Escape"
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.globalShortcut)
        }
    }

    public var launchAtLogin: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.bool(forKey: Keys.launchAtLogin)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.launchAtLogin)
        }
    }

    public var telemetryEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.bool(forKey: Keys.telemetryEnabled)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.telemetryEnabled)
        }
    }

    public var indexedDirectories: [String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.stringArray(forKey: Keys.indexedDirectories) ?? ["~/Documents", "~/Downloads", "~/Desktop"]
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.indexedDirectories)
        }
    }

    public var hasCompletedOnboarding: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.bool(forKey: Keys.hasCompletedOnboarding)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.hasCompletedOnboarding)
        }
    }

    public var useMockEngine: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.bool(forKey: Keys.useMockEngine)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.useMockEngine)
        }
    }
}
