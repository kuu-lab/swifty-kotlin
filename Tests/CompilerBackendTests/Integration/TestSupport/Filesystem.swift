@testable import CompilerTestSupport

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
