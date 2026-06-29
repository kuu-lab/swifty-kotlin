#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-FN-040: Reader.useLines { lines -> T }
//
// Verifies that `kotlin.io.Reader.useLines(block)` resolves against our synthetic
// `java.io.BufferedReader` declarations so that user code calling
// `reader.useLines { lines -> ... }` (the common shape for the Reader-flavour
// `useLines`) compiles and type-checks against the same `(List<String>) -> T`
// surface as `File.useLines`.

@Suite
struct ReaderUseLinesFunctionTests {

    // MARK: - Direct useLines call resolves and infers the block return type

    @Test func testBufferedReaderUseLinesReturnsListThroughBlock() throws {
        let source = """
        import java.io.File

        fun main() {
            val reader = File("/dev/null").bufferedReader()
            val count: Int = reader.useLines { lines ->
                lines.size
            }
            println(count)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "BufferedReader.useLines should resolve with List<String> lambda parameter: \(ctx.diagnostics.diagnostics.map(\.message))")
            )
        }
    }

    // MARK: - Block accesses List<String> members on the parameter

    @Test func testBufferedReaderUseLinesBlockSeesListMembers() throws {
        let source = """
        import java.io.File

        fun firstOrEmpty(file: File): String {
            val reader = file.bufferedReader()
            return reader.useLines { lines ->
                if (lines.isEmpty()) "" else lines[0]
            }
        }

        fun main() {
            println(firstOrEmpty(File("/dev/null")))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "useLines lambda parameter should expose List<String> members: \(ctx.diagnostics.diagnostics.map(\.message))")
            )
        }
    }

    // MARK: - Return type follows the block, supporting non-String results

    @Test func testBufferedReaderUseLinesPropagatesBlockReturnType() throws {
        let source = """
        import java.io.File

        fun loadJoined(file: File): String {
            val reader = file.bufferedReader()
            val joined: String = reader.useLines { lines ->
                lines.joinToString("\\n")
            }
            return joined
        }

        fun main() {
            println(loadJoined(File("/dev/null")))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "useLines block return type should flow back to the call site: \(ctx.diagnostics.diagnostics.map(\.message))")
            )
        }
    }
}
#endif
