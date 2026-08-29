@testable import CompilerCore
@testable import CompilerBackend
import Foundation

func withTemporaryFile(
    contents: String,
    fileExtension: String = "kt",
    body: (String) throws -> Void
) throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(fileExtension)
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: fileURL)
    }
    try body(fileURL.path)
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
