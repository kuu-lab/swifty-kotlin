@testable import CompilerCore
@testable import CompilerBackend
import Foundation

func withTemporaryFile(
    contents: String,
    fileExtension: String = "kt",
    body: (String) throws -> Void
) throws {
    try withTemporaryFiles(contents: [contents], fileExtension: fileExtension) { paths in
        try body(paths[0])
    }
}

func withTemporaryFiles(
    contents: [String],
    fileExtension: String = "kt",
    body: ([String]) throws -> Void
) throws {
    var urls: [URL] = []
    for source in contents {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        urls.append(fileURL)
    }
    defer {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
    try body(urls.map(\.path))
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
