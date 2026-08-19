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
struct CodegenBackendKotlinTextCaseAndComparisonEdgeCasesTests {

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

    @Test func testKotlinTextIfBlankEdgeCases() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifBlank { "fallback" }
        }

        fun main() {
            println("[" + "abc".ifBlank { "fallback" } + "]")
            println("[" + "   ".ifBlank { "fallback" } + "]")
            println("[" + "".ifBlank { "empty" } + "]")

            val cs: CharSequence = "   "
            println("[" + choose(cs) + "]")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIfBlankEdgeCases",
            expected:
                """
                [abc]
                [fallback]
                [empty]
                [fallback]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextIfEmptyEdgeCases() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifEmpty { "fallback" }
        }

        fun main() {
            println("[" + "abc".ifEmpty { "fallback" } + "]")
            println("[" + "   ".ifEmpty { "fallback" } + "]")
            println("[" + "".ifEmpty { "empty" } + "]")

            val cs: CharSequence = ""
            println("[" + choose(cs) + "]")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIfEmptyEdgeCases",
            expected:
                """
                [abc]
                [   ]
                [empty]
                [fallback]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextCharSequenceZipWithNextEdgeCases() throws {
        let source = """
        fun pairCount(value: CharSequence): Int {
            return value.zipWithNext().size
        }

        fun labels(value: CharSequence): List<String> {
            return value.zipWithNext { a, b -> "" + a + b }
        }

        fun main() {
            val cs: CharSequence = "abcd"
            val pairs = cs.zipWithNext()
            println(pairs.size)

            val transformed = cs.zipWithNext { a, b -> "" + a + b }
            println(transformed.size)
            println(transformed[0])
            println(transformed[2])

            println(pairCount("xy"))
            println(labels("xy")[0])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCharSequenceZipWithNextEdgeCases",
            expected:
                """
                3
                3
                ab
                cd
                1
                xy
                """
                + "\n"
        )
    }

    @Test func testKotlinTextCaseConversionEdgeCases() throws {
        let source = """
        fun main() {
            // lowercase
            println("Hello World".lowercase())
            println("".lowercase())
            println("123".lowercase())

            // uppercase
            println("Hello World".uppercase())
            println("".uppercase())

            // lowercase on already-lower
            println("hello".lowercase())

            // uppercase on already-upper
            println("HELLO".uppercase())

            // mixed with digits and symbols
            println("Abc123!".lowercase())
            println("Abc123!".uppercase())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCaseConversionEdgeCases",
            expected:
                """
                hello world

                123
                HELLO WORLD

                hello
                HELLO
                abc123!
                ABC123!
                """
                + "\n"
        )
    }

    @Test func testKotlinTextCaseInsensitiveOrderEdgeCases() throws {
        let source = """
        fun main() {
            println(String.CASE_INSENSITIVE_ORDER.compare("alpha", "ALPHA"))
            println(String.CASE_INSENSITIVE_ORDER.compare("apple", "banana") < 0)
            println(String.CASE_INSENSITIVE_ORDER.compare("Zoo", "apple") > 0)
            println(listOf("b", "A", "c", "a").sortedWith(String.CASE_INSENSITIVE_ORDER))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCaseInsensitiveOrderEdgeCases",
            expected:
                """
                0
                true
                true
                [A, a, b, c]
                """
                + "\n"
        )
    }

    // BUG-036/BUG-154: `String.CASE_INSENSITIVE_ORDER` is a companion `val` in
    // real Kotlin, so repeated reads must observe the same instance. It is now
    // backed by a module-init global (initialized once via
    // `kk_string_case_insensitive_order()`); the runtime also caches the
    // singleton handle, cleared on `kk_runtime_force_reset` for test isolation.
    @Test func testKotlinTextCaseInsensitiveOrderIsReferentiallyStable() throws {
        let source = """
        fun main() {
            val a = String.CASE_INSENSITIVE_ORDER
            val b = String.CASE_INSENSITIVE_ORDER
            println(a === b)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCaseInsensitiveOrderIsReferentiallyStable",
            expected:
                """
                true
                """
                + "\n"
        )
    }

    @Test func testKotlinTextCharSequenceZipEdgeCases() throws {
        let source = """
        fun merge(a: String, b: CharSequence): List<String> {
            return a.zip(b) { x, y -> "" + x + y }
        }

        fun main() {
            // String.zip: basic count
            println("abc".zip("xyz").size)

            // Truncation at shorter string
            println("ab".zip("xyz").size)
            println("xyz".zip("ab").size)

            // Empty source returns empty list
            println("".zip("xyz").size)

            // Transform variant
            val joined = "abc".zip("XYZ") { a, b -> "" + a + b }
            println(joined.size)
            println(joined[0])
            println(joined[2])

            // CharSequence receiver
            val cs: CharSequence = "hello"
            println(cs.zip("hi").size)
            val csJoined = cs.zip("HI") { a, b -> "" + a + b }
            println(csJoined[0])
            println(csJoined[1])

            // Via helper function
            println(merge("abc", "123")[1])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextCharSequenceZipEdgeCases",
            expected:
                """
                3
                2
                2
                0
                3
                aX
                cZ
                2
                hH
                eI
                b2
                """
                + "\n"
        )
    }
}
#endif
