@testable import CompilerTestSupport
import Foundation

func withTemporaryFile(
    contents: String,
    fileExtension: String = "kt",
    body: (String) throws -> Void
) throws {
    try CompilerTestSupport.withTemporaryFile(contents: contents, fileExtension: fileExtension, body: body)
}

func withTemporaryFiles(
    contents: [String],
    fileExtension: String = "kt",
    body: ([String]) throws -> Void
) throws {
    try CompilerTestSupport.withTemporaryFiles(contents: contents, fileExtension: fileExtension, body: body)
}

/// Load a fixture from `Scripts/diff_cases/<name>`, used by tests that pin
/// codegen output to the canonical kotlinc-diff regression case.
func diffCaseSource(_ name: String, file: StaticString = #filePath) throws -> String {
    let root = URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Codegen/
        .deletingLastPathComponent() // CompilerBackendTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // repo root
    let caseURL = root.appendingPathComponent(
        "Scripts/diff_cases/\(name)",
        isDirectory: false
    )
    return try String(contentsOf: caseURL, encoding: .utf8)
}
