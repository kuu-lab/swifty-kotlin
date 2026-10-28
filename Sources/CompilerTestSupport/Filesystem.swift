@testable import CompilerCore
import Foundation

func makeRange(file: FileID = FileID(rawValue: 0), start: Int = 0, end: Int = 1) -> SourceRange {
    SourceRange(
        start: SourceLocation(file: file, offset: start),
        end: SourceLocation(file: file, offset: end)
    )
}

func makeToken(
    kind: TokenKind,
    file: FileID = FileID(rawValue: 0),
    start: Int = 0,
    end: Int = 1,
    leadingTrivia: [TriviaPiece] = [],
    trailingTrivia: [TriviaPiece] = []
) -> Token {
    Token(
        kind: kind,
        range: makeRange(file: file, start: start, end: end),
        leadingTrivia: leadingTrivia,
        trailingTrivia: trailingTrivia
    )
}

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

func diffCaseSource(_ name: String, file: StaticString = #filePath) throws -> String {
    try repositoryFileSource("Scripts/diff_cases/\(name)", file: file)
}

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
