import Foundation

/// Read a repository-relative source file from the checkout containing `file`.
func repositoryFileSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
    var root = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
        let parent = root.deletingLastPathComponent()
        guard parent != root else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: relativePath])
        }
        root = parent
    }
    return try String(
        contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
        encoding: .utf8
    )
}

/// Load a fixture from `Scripts/diff_cases/<name>`.
func diffCaseSource(_ name: String, file: StaticString = #filePath) throws -> String {
    try repositoryFileSource("Scripts/diff_cases/\(name)", file: file)
}

/// Write `contents` to a temporary file and run `body` with its path, cleaning
/// up the file afterward regardless of how `body` returns.
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

/// Write each of `contents` to its own temporary file and run `body` with
/// their paths, cleaning up all files afterward regardless of how `body`
/// returns.
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
