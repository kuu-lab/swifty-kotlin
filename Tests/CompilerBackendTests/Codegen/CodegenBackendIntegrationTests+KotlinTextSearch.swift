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
struct CodegenBackendKotlinTextSearchEdgeCasesTests {

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

    @Test func testKotlinTextStringSearchDefaultArgumentsAndImplicitReceiver() throws {
        let source = """
        fun String.findDelimiter(delimiter: String): Int = indexOf(delimiter)

        fun main() {
            println("hello".findDelimiter("ll"))
            println("hello".lastIndexOf('l'))
            println("hello".lastIndexOf('l', 2))
            println("hello".lastIndexOf('x'))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextStringSearchDefaultArgumentsAndImplicitReceiver",
            expected:
                """
                2
                3
                2
                -1
                """
                + "\n"
        )
    }

    @Test func testKotlinTextIndexOfEdgeCases() throws {
        let source = """
        fun main() {
            // indexOf: found
            println("hello world".indexOf("world"))

            // indexOf: not found
            println("hello".indexOf("xyz"))

            // indexOf: empty string target (always returns 0)
            println("hello".indexOf(""))

            // indexOf: empty source
            println("".indexOf("x"))

            // indexOf with startIndex
            println("abcabc".indexOf("a", 1))

            // indexOf with startIndex at end
            println("abc".indexOf("c", 3))

            // lastIndexOf: found
            println("abcabc".lastIndexOf("a"))

            // lastIndexOf: not found
            println("hello".lastIndexOf("x"))

            // lastIndexOf: empty target with default startIndex (returns lastIndex,
            // i.e. length - 1, matching kotlinc's default `startIndex = lastIndex`)
            println("hello".lastIndexOf(""))

            // lastIndexOf on empty source
            println("".lastIndexOf("x"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfEdgeCases",
            expected:
                """
                6
                -1
                0
                -1
                3
                -1
                3
                -1
                4
                -1
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase (positional 3-arg API)
    @Test func testKotlinTextIndexOfIgnoreCaseEdgeCases() throws {
        let source = """
        fun main() {
            println("Hello".indexOf("hello", 0, true))
            println("Hello".lastIndexOf("LO", 4, true))
            println("Hello".indexOf("xyz", 0, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfIgnoreCaseEdgeCases",
            expected:
                """
                0
                3
                -1
                """
                + "\n"
        )
    }

    @Test func testKotlinTextLastIndexOfCharEdgeCases() throws {
        let source = """
        fun main() {
            val text: CharSequence = "Kotlin"
            println(text.lastIndexOf('o', 5, false))
            println(text.lastIndexOf('k', 5, true))
            println("hello".lastIndexOf('l', 4, false))
            println("hello".lastIndexOf('l', 2, false))
            println("hello".lastIndexOf('l', 1, false))
            println("hello".lastIndexOf('x', 4, false))
            println("hello".lastIndexOf('H', 4, true))
            println("".lastIndexOf('a', 0, false))
            println("abc".lastIndexOf('a', -1, false))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLastIndexOfCharEdgeCases",
            expected:
                """
                1
                0
                3
                2
                -1
                -1
                0
                -1
                -1
                """
                + "\n"
        )
    }

    @Test func testKotlinTextIndexOfFirstPredicateEdgeCases() throws {
        let source = """
        fun findInParam(s: String): Int {
            return s.indexOfFirst { it == 'l' }
        }

        fun main() {
            // first matching char found
            println("hello".indexOfFirst { it == 'l' })

            // no match returns -1
            println("hello".indexOfFirst { it == 'z' })

            // first char matches: returns 0
            println("abc".indexOfFirst { it == 'a' })

            // last char matches: returns length - 1
            println("abc".indexOfFirst { it == 'c' })

            // empty string: returns -1
            println("".indexOfFirst { it == 'x' })

            // via function parameter (CharSequence receiver)
            println(findInParam("hello world"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfFirstPredicateEdgeCases",
            expected:
                """
                2
                -1
                0
                2
                -1
                2
                """
                + "\n"
        )
    }

    @Test func testKotlinTextIndexOfAnyCharsEdgeCases() throws {
        let source = """
        fun firstAny(value: CharSequence, chars: CharArray, start: Int, ignore: Boolean): Int {
            return value.indexOfAny(chars, start, ignore)
        }

        fun main() {
            println(firstAny("Kotlin", charArrayOf('t', 'x'), 0, false))
            println(firstAny("Kotlin", charArrayOf('k'), 0, true))
            println(firstAny("abc", charArrayOf('x'), 0, false))
            println(firstAny("abc", charArrayOf('a'), 5, false))
            println("abc".indexOfAny(charArrayOf('B'), 0, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfAnyCharsEdgeCases",
            expected:
                """
                2
                0
                -1
                -1
                1
                """
                + "\n"
        )
    }

    @Test func testKotlinTextIndexOfAnyStringsEdgeCases() throws {
        let source = """
        fun firstAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Int {
            return value.indexOfAny(strings, start, ignore)
        }

        fun main() {
            println(firstAny("Kotlin", listOf("lin", "zz"), 0, false))
            println(firstAny("Kotlin", listOf("ko"), 0, true))
            println("abc".indexOfAny(listOf("x", "bc"), 0, false))
            println("abc".indexOfAny(listOf(""), 2, false))
            println("abc".indexOfAny(listOf("a"), 5, false))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextIndexOfAnyStringsEdgeCases",
            expected:
                """
                3
                0
                1
                2
                -1
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-FN-021: indexOfAny with default arguments (startIndex=0, ignoreCase=false)
    @Test func testKotlinTextIndexOfAnyDefaultArgs() throws {
        let source = """
        fun main() {
            val text = "Kotlin"
            println(text.indexOfAny(charArrayOf('t', 'K')))
            println(text.indexOfAny(charArrayOf('t', 'K'), 2))
            println(text.indexOfAny(listOf("otl", "zz")))
            println(text.indexOfAny(listOf("otl"), 2))
            println("abc".indexOfAny(charArrayOf('x')))
            println("abc".indexOfAny(listOf("bc")))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextIndexOfAnyDefaultArgs",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            let expected =
                """
                0
                2
                1
                -1
                -1
                1
                """
                + "\n"
            #expect(out == expected)
        }
    }

    @Test func testKotlinTextLastIndexOfAnyCharsEdgeCases() throws {
        let source = """
        fun lastAny(value: CharSequence, chars: CharArray, start: Int, ignore: Boolean): Int {
            return value.lastIndexOfAny(chars, start, ignore)
        }

        fun main() {
            println(lastAny("Kotlin", charArrayOf('t', 'o'), 5, false))
            println(lastAny("Kotlin", charArrayOf('k'), 5, true))
            println("abca".lastIndexOfAny(charArrayOf('a'), 2, false))
            println("abc".lastIndexOfAny(charArrayOf('x'), 2, false))
            println("abc".lastIndexOfAny(charArrayOf('C'), 2, true))
            println("abc".lastIndexOfAny(charArrayOf('a'), -1, false))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLastIndexOfAnyCharsEdgeCases",
            expected:
                """
                2
                0
                0
                -1
                2
                -1
                """
                + "\n"
        )
    }

    @Test func testKotlinTextLastIndexOfAnyStringsEdgeCases() throws {
        let source = """
        fun lastAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Int {
            return value.lastIndexOfAny(strings, start, ignore)
        }

        fun main() {
            println(lastAny("Kotlin", listOf("ot", "li"), 5, false))
            println(lastAny("Kotlin", listOf("KO"), 5, true))
            println("abc".lastIndexOfAny(listOf("x", "bc"), 2, false))
            println("abc".lastIndexOfAny(listOf(""), 5, false))
            println("abc".lastIndexOfAny(listOf(""), 2, false))
            println("abc".lastIndexOfAny(listOf("a"), -1, false))
            println("abc".lastIndexOfAny(listOf("C"), 2, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextLastIndexOfAnyStringsEdgeCases",
            expected:
                """
                3
                0
                1
                3
                2
                -1
                2
                """
                + "\n"
        )
    }

    @Test func testKotlinTextFindAnyOfStringsEdgeCases() throws {
        let source = """
        fun findAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Pair<Int, String>? {
            return value.findAnyOf(strings, start, ignore)
        }

        fun render(match: Pair<Int, String>?): String {
            if (match == null) return "null"
            return match.first.toString() + ":" + match.second
        }

        fun main() {
            println(render(findAny("Kotlin", listOf("lin", "ot"), 0, false)))
            println(render(findAny("Kotlin", listOf("KO"), 0, true)))
            println(render("abc".findAnyOf(listOf("x", "bc"), 0, false)))
            println(render("abc".findAnyOf(listOf(""), 5, false)))
            println(render("abc".findAnyOf(listOf("a"), 5, false)))
            println(render("abc".findAnyOf(listOf("bc", "b"), 0, false)))
            println(render("abc".findAnyOf(listOf("a"), -1, false)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextFindAnyOfStringsEdgeCases",
            expected:
                """
                1:ot
                0:KO
                1:bc
                3:
                null
                1:bc
                0:a
                """
                + "\n"
        )
    }

    @Test func testKotlinTextFindLastAnyOfStringsEdgeCases() throws {
        let source = """
        fun findLastAny(value: CharSequence, strings: Collection<String>, start: Int, ignore: Boolean): Pair<Int, String>? {
            return value.findLastAnyOf(strings, start, ignore)
        }

        fun render(match: Pair<Int, String>?): String {
            if (match == null) return "null"
            return match.first.toString() + ":" + match.second
        }

        fun main() {
            println(render(findLastAny("Kotlin", listOf("ot", "li"), 5, false)))
            println(render(findLastAny("Kotlin", listOf("KO"), 5, true)))
            println(render("abc".findLastAnyOf(listOf("x", "bc"), 2, false)))
            println(render("abc".findLastAnyOf(listOf(""), 5, false)))
            println(render("abc".findLastAnyOf(listOf(""), 2, false)))
            println(render("abc".findLastAnyOf(listOf("a"), -1, false)))
            println(render("abc".findLastAnyOf(listOf("C"), 2, true)))
            println(render("abc".findLastAnyOf(listOf("bc", "b"), 2, false)))
            println(render("abc".findLastAnyOf(listOf("a"), 5, false)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextFindLastAnyOfStringsEdgeCases",
            expected:
                """
                3:li
                0:KO
                1:bc
                3:
                2:
                null
                2:C
                1:bc
                0:a
                """
                + "\n"
        )
    }
}
#endif
