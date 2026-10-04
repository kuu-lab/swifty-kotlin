@testable import CompilerCore
@testable import CompilerTestSupport

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
