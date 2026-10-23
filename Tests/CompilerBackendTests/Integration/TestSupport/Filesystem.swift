@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation

/// Load a fixture from `Scripts/diff_cases/<name>` through shared test support.
func diffCaseSource(_ name: String, file: StaticString = #filePath) throws -> String {
    try CompilerTestSupport.diffCaseSource(name, file: file)
}

/// Fixture directories keep only `<name>.out` when `Scripts/diff_cases/<name>.kt`
/// already holds the same program, so the two copies cannot drift apart.
func fixtureOrDiffCaseSource(_ fixtures: URL, _ name: String, file: StaticString = #filePath) throws -> String {
    let local = fixtures.appendingPathComponent(name + ".kt")
    guard FileManager.default.fileExists(atPath: local.path) else {
        return try diffCaseSource(name + ".kt", file: file)
    }
    return try String(contentsOf: local, encoding: .utf8)
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
