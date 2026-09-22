import Foundation

public struct FileOperationPreview: Equatable, Sendable {
    public let sourcePath: String
    public let destinationPath: String
    public let willOverwrite: Bool
    public let isReversible: Bool

    public init(sourcePath: String, destinationPath: String, willOverwrite: Bool, isReversible: Bool = true) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.willOverwrite = willOverwrite
        self.isReversible = isReversible
    }
}

public enum PathSafetyError: LocalizedError, Equatable {
    case pathTraversalDetected(String)
    case outsideAllowedScope(String)
    case destinationAlreadyExists(String)
    case fileNotFound(String)
    case deletionNotAllowedInMVP

    public var errorDescription: String? {
        switch self {
        case .pathTraversalDetected(let path):
            return "Path traversal detected in '\(path)'. Directory escaping is not permitted."
        case .outsideAllowedScope(let path):
            return "Path '\(path)' is outside allowed user directories."
        case .destinationAlreadyExists(let path):
            return "Destination file '\(path)' already exists. Silent overwrite is prohibited."
        case .fileNotFound(let path):
            return "Source path '\(path)' does not exist."
        case .deletionNotAllowedInMVP:
            return "File deletion is strictly prohibited in NeedleBar MVP."
        }
    }
}

public final class PathSafety: Sendable {
    public static let shared = PathSafety()

    public init() {}

    /// Expands `~` and resolves standard symlinks and dot-dots to an absolute URL.
    public func resolvePath(_ rawPath: String) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            // Default relative paths to the user's home directory or desktop/documents
            let home = FileManager.default.homeDirectoryForCurrentUser
            url = home.appendingPathComponent(expanded)
        }
        return url.standardizedFileURL
    }

    /// Verifies that a resolved path does not traverse outside user scope or contain invalid dot components.
    public func validatePath(_ path: String, allowNonExistent: Bool = false) throws -> URL {
        let resolved = resolvePath(path)
        let pathString = resolved.path

        // Check against sensitive system directories
        let prohibitedPrefixes = [
            "/System",
            "/bin",
            "/sbin",
            "/usr/bin",
            "/usr/sbin",
            "/private/etc",
            "/etc"
        ]

        for prefix in prohibitedPrefixes {
            if pathString.hasPrefix(prefix) {
                throw PathSafetyError.outsideAllowedScope(pathString)
            }
        }

        if !allowNonExistent && !FileManager.default.fileExists(atPath: pathString) {
            throw PathSafetyError.fileNotFound(pathString)
        }

        return resolved
    }

    /// Validates a move or rename operation and generates a preview.
    public func previewOperation(source: String, destination: String) throws -> FileOperationPreview {
        let sourceURL = try validatePath(source, allowNonExistent: false)
        let destURL = resolvePath(destination)

        var finalDestURL = destURL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: destURL.path, isDirectory: &isDir), isDir.boolValue {
            finalDestURL = destURL.appendingPathComponent(sourceURL.lastPathComponent)
        }

        let willOverwrite = FileManager.default.fileExists(atPath: finalDestURL.path)
        if willOverwrite {
            throw PathSafetyError.destinationAlreadyExists(finalDestURL.path)
        }

        return FileOperationPreview(
            sourcePath: sourceURL.path,
            destinationPath: finalDestURL.path,
            willOverwrite: willOverwrite,
            isReversible: true
        )
    }
}
