#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-FN-017: Reader.forEachLine { line -> Unit }
//
// Verifies that `kotlin.io.Reader.forEachLine(action)` resolves against our synthetic
// `java.io.BufferedReader` declarations so that user code calling
// `reader.forEachLine { line -> ... }` compiles and type-checks. Unlike `useLines`,
// `forEachLine` does not close the reader — the lambda parameter is `String` and
// the call returns `Unit`.

@Suite
struct ReaderForEachLineFunctionTests {

    // MARK: - Direct forEachLine call resolves without errors

    @Test func testBufferedReaderForEachLineResolves() throws {
        let source = """
        import java.io.File

        fun main() {
            val reader = File("/dev/null").bufferedReader()
            reader.forEachLine { line ->
                println(line)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "BufferedReader.forEachLine should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
            )
        }
    }

    // MARK: - Lambda parameter is typed as String

    @Test func testBufferedReaderForEachLineLambdaParameterIsString() throws {
        let source = """
        import java.io.File

        fun main() {
            val reader = File("/tmp/test.txt").bufferedReader()
            reader.forEachLine { line ->
                val len: Int = line.length
                println(len)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "forEachLine lambda parameter should be typed as String (line.length should resolve): \(ctx.diagnostics.diagnostics.map(\.message))")
            )
        }
    }

    // MARK: - Call returns Unit

    @Test func testBufferedReaderForEachLineReturnsUnit() throws {
        let source = """
        import java.io.File

        fun processLines(file: File): Unit {
            val reader = file.bufferedReader()
            val result: Unit = reader.forEachLine { line ->
                println(line)
            }
            return result
        }

        fun main() {
            processLines(File("/dev/null"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "BufferedReader.forEachLine should return Unit: \(ctx.diagnostics.diagnostics.map(\.message))")
            )
        }
    }
}
#endif
