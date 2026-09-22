import XCTest
@testable import NeedleBarCore

final class PathSafetyTests: XCTestCase {
    let safety = PathSafety.shared

    func testResolveTildePath() {
        let path = "~/Documents"
        let resolved = safety.resolvePath(path)
        XCTAssertTrue(resolved.path.hasPrefix("/Users/"))
        XCTAssertTrue(resolved.path.hasSuffix("/Documents"))
    }

    func testRejectSystemDirectory() {
        let prohibited = ["/System/Library", "/bin/sh", "/private/etc/passwd"]
        for p in prohibited {
            XCTAssertThrowsError(try safety.validatePath(p, allowNonExistent: true)) { error in
                guard case PathSafetyError.outsideAllowedScope = error else {
                    return XCTFail("Expected outsideAllowedScope for \(p), got \(error)")
                }
            }
        }
    }

    func testDetectDestinationCollision() throws {
        // Create two temporary files
        let tmpDir = FileManager.default.temporaryDirectory
        let fileA = tmpDir.appendingPathComponent("test_src_\(UUID().uuidString).txt")
        let fileB = tmpDir.appendingPathComponent("test_dst_\(UUID().uuidString).txt")

        try "src".write(to: fileA, atomically: true, encoding: .utf8)
        try "dst".write(to: fileB, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: fileA)
            try? FileManager.default.removeItem(at: fileB)
        }

        XCTAssertThrowsError(try safety.previewOperation(source: fileA.path, destination: fileB.path)) { error in
            guard case PathSafetyError.destinationAlreadyExists = error else {
                return XCTFail("Expected destinationAlreadyExists error, got \(error)")
            }
        }
    }

    func testPreviewMoveOperation() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileA = tmpDir.appendingPathComponent("test_valid_\(UUID().uuidString).txt")
        let destPath = tmpDir.appendingPathComponent("test_valid_dst_\(UUID().uuidString).txt").path

        try "data".write(to: fileA, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileA) }

        let preview = try safety.previewOperation(source: fileA.path, destination: destPath)
        XCTAssertEqual(preview.sourcePath, fileA.path)
        XCTAssertEqual(preview.destinationPath, destPath)
        XCTAssertFalse(preview.willOverwrite)
        XCTAssertTrue(preview.isReversible)
    }

    func testRejectNonExistentSourceFile() {
        let nonExistent = "/Users/nonexistent_path_123456/sample.txt"
        XCTAssertThrowsError(try safety.validatePath(nonExistent, allowNonExistent: false)) { error in
            guard case PathSafetyError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound error, got \(error)")
            }
        }
    }
}
