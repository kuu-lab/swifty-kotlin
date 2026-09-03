@testable import CompilerCore
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

/// Writes a minimal manifest.json plus a hand-authored metadata.bin to a
/// temporary ".kklib" directory and passes its path to `body`, cleaning up
/// afterward.
func withKklibFixture(
    moduleName: String,
    metadata: String,
    body: (String) throws -> Void
) throws {
    let fm = FileManager.default
    let libDir = fm.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("kklib")
    defer { try? fm.removeItem(at: libDir) }
    try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
    let manifest = """
    {
      "formatVersion": 1,
      "moduleName": "\(moduleName)",
      "metadata": "metadata.bin"
    }
    """
    try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
    try body(libDir.path)
}

func withKklibFixture(
    moduleName: String,
    records: [MetadataRecord],
    body: (String) throws -> Void
) throws {
    try withKklibFixture(
        moduleName: moduleName,
        metadata: MetadataEncoder().serialize(records),
        body: body
    )
}
