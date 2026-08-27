#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

@Suite(.serialized)
struct CodegenBackendKotlinTextSplittingEdgeCasesTests {

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test func testKotlinTextSplitEdgeCases() throws {
        let source = """
        fun main() {
            // empty string with single-char delimiter
            println("".split(","))

            // no delimiter in string
            println("hello".split(","))

            // single-char delimiter
            println("a,b,c".split(","))

            // multi-char delimiter
            println("aXXbXXc".split("XX"))

            // delimiter at start and end (trailing empty parts)
            println(",a,b,".split(","))

            // consecutive delimiters
            println("a,,b".split(","))

            // entire string is delimiter
            println(",".split(","))

            // empty delimiter returns list containing original string
            println("abc".split(""))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitEdgeCases",
            expected:
                """
                []
                [hello]
                [a, b, c]
                [a, b, c]
                [, a, b, ]
                [a, , b]
                [, ]
                [abc]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextSplitWithLimitEdgeCases() throws {
        let source = """
        fun main() {
            println("a,b,c,d".split(",", limit = 2))
            println("a,b,c".split(",", limit = 0))
            println("a,b,c".split(",", limit = -1))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitWithLimitEdgeCases",
            expected:
                """
                [a, b,c,d]
                [a, b, c]
                [a, b, c]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextSplitToSequenceEdgeCases() throws {
        let source = """
        fun main() {
            // empty string
            println("".splitToSequence(",").toList())

            // no delimiter present
            println("hello".splitToSequence(",").toList())

            // normal split
            println("a,b,c".splitToSequence(",").toList())

            // empty delimiter returns original string wrapped
            println("abc".splitToSequence("").toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSplitToSeqEdgeCases",
            expected:
                """
                []
                [hello]
                [a, b, c]
                [abc]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextChunkedEdgeCases() throws {
        let source = """
        fun main() {
            // normal chunked
            println("abcdef".chunked(2))

            // chunk size larger than string (returns one chunk)
            println("abc".chunked(10))

            // chunk size equals string length
            println("abc".chunked(3))

            // chunked on empty string
            println("".chunked(3))

            // chunk size of 1
            println("abc".chunked(1))

            // windowed: default (step=1)
            println("abcde".windowed(3))

            // windowed: step=2
            println("abcde".windowed(3, 2))

            // windowed: size > string (empty result)
            println("ab".windowed(5))

            // windowed on empty string
            println("".windowed(2))

            // windowed with partialWindows=true
            println("abcd".windowed(3, 2, partialWindows = true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedEdgeCases",
            expected:
                """
                [ab, cd, ef]
                [abc]
                [abc]
                []
                [a, b, c]
                [abc, bcd, cde]
                [abc, cde]
                []
                []
                [abc, cd]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextChunkedSequenceTransformEdgeCases() throws {
        let source = """
        fun main() {
            val lengths: kotlin.sequences.Sequence<Int> =
                "abcdef".chunkedSequence(2) { _: CharSequence -> 2 }
            println(lengths.toList())

            val text: CharSequence = "abcde"
            println(text.chunkedSequence(2) { _: CharSequence -> "chunk" }.toList())

            println("".chunkedSequence(3) { _: CharSequence -> 1 }.toList())
            println("abc".chunkedSequence(10) { _: CharSequence -> "single" }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedSequenceTransformEdgeCases",
            expected:
                """
                [2, 2, 2]
                [chunk, chunk, chunk]
                []
                [single]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextChunkedSequenceEdgeCases() throws {
        let source = """
        fun render(value: CharSequence, size: Int): List<String> {
            return value.chunkedSequence(size).toList()
        }

        fun renderTransform(value: CharSequence, size: Int): List<String> {
            return value.chunkedSequence(size) { chunk -> "" + chunk + "!" }.toList()
        }

        fun main() {
            println("abcdef".chunkedSequence(2).toList())

            val text: CharSequence = "abcde"
            val chunks: kotlin.sequences.Sequence<String> = text.chunkedSequence(2)
            println(chunks.toList())

            println("".chunkedSequence(3).toList())
            println("abc".chunkedSequence(10).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextChunkedSequenceEdgeCases",
            expected:
                """
                [ab, cd, ef]
                [ab, cd, e]
                []
                [abc]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextWindowedSequenceEdgeCases() throws {
        let source = """
        fun render(value: CharSequence, size: Int, step: Int, partial: Boolean): List<String> {
            return value.windowedSequence(size, step, partial).toList()
        }

        fun main() {
            println(render("abcdef", 3, 2, false))
            println(render("abcdef", 3, 2, true))
            println(render("ab", 5, 1, false))
            println(render("ab", 5, 1, true))
            println("hello".windowedSequence(2, 1, false).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextWindowedSequenceEdgeCases",
            expected:
                """
                [abc, cde]
                [abc, cde, ef]
                []
                [ab, b]
                [he, el, ll, lo]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextWindowedSequenceTransformEdgeCases() throws {
        let source = """
        fun lengths(value: CharSequence): List<Int> {
            return value.windowedSequence(3, 2, true) { it.length }.toList()
        }

        fun tagged(value: String): List<String> {
            return value.windowedSequence(size = 2, step = 1, partialWindows = false) { window -> "" + window + "!" }.toList()
        }

        fun main() {
            println(lengths("abcdef"))
            println("ab".windowedSequence(5, 1, true) { it.length }.toList())
            println(tagged("hello"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextWindowedSequenceTransformEdgeCases",
            expected:
                """
                [3, 3, 2]
                [2, 1]
                [he!, el!, ll!, lo!]
                """
                + "\n"
        )
    }

    @Test func testSourceIteratorCapturingStringPreservesIntElements() throws {
        let source = """
        class StringBackedIntSequence(private val source: String) : Sequence<Int> {
            override fun iterator(): Iterator<Int> {
                val capturedSource = source
                return object : Iterator<Int> {
                    private var index = 0

                    override fun hasNext(): Boolean = index < capturedSource.length

                    override fun next(): Int {
                        val value = index + 1
                        index++
                        return value
                    }
                }
            }
        }

        fun main() {
            println(StringBackedIntSequence("abc").toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBackedIntSequence",
            expected: "[1, 2, 3]\n"
        )
    }

    @Test func testKotlinTextLinesEdgeCases() throws {
        let source = """
        fun main() {
            // empty string
            println("".lines())

            // single line (no newline)
            println("hello".lines())

            // trailing newline — runtime includes trailing empty element
            println("hello\\n".lines())

            // CRLF line endings
            println("a\\r\\nb\\r\\nc".lines())

            // mixed line endings (\n and \r)
            println("a\\nb\\rc".lines())

            // only newlines
            println("\\n\\n".lines())

            // single newline
            println("\\n".lines())

            // Windows CRLF only
            println("\\r\\n".lines())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLinesEdgeCases",
            expected:
"[]\n" +
                "[hello]\n" +
                "[hello, ]\n" +
                "[a, b, c]\n" +
                "[a, b, c]\n" +
                "[, , ]\n" +
                "[, ]\n" +
                "[, ]\n"
        )
    }
}
#endif
