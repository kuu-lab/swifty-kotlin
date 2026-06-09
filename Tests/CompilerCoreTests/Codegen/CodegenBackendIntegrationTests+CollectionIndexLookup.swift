import XCTest
@testable import CompilerCore

extension CodegenBackendIntegrationTests {
    func testCodegenListIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 10)
            println(values.indexOf(10))
            println(values.indexOf(20))
            println(values.indexOf(30))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListIndexOfRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0\n1\n-1\n")
        }
    }

    /// Regression: the `[]` index operator on a `List<Char>` must route to the List `get`
    /// member, NOT the String runtime entry `kk_string_get`. A `List<Char>` element type is
    /// `Char`, which previously tricked the char-element heuristic into reinterpreting the List
    /// handle as a string handle, panicking at runtime with
    /// `runtimeStringScalars(_:) received invalid string handle`.
    func testCodegenListOfCharIndexOperatorUsesListGet() throws {
        let source = """
        fun main() {
            val chars = listOf('h', 'i')
            println(chars[0])
            println(chars[1])
            // A List<Char> obtained via String.toList() must behave the same.
            println("hi".toList()[0])
            // The member forms already worked and must keep working alongside the operator.
            println(chars.get(0))
            println(chars.first())
            println(chars.last())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListOfCharIndexOperator",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "h\ni\nh\nh\nh\ni\n")
        }
    }

    /// Companion to `testCodegenListOfCharIndexOperatorUsesListGet`: the `[]` operator on a
    /// genuine `String` receiver must keep routing to `kk_string_get`. This guards against the
    /// List<Char> fix over-tightening the heuristic and breaking real String indexing.
    func testCodegenStringIndexOperatorUsesStringGet() throws {
        let source = """
        fun main() {
            val s = "hello"
            println(s[0])
            println(s[4])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringIndexOperator",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "h\no\n")
        }
    }
}
