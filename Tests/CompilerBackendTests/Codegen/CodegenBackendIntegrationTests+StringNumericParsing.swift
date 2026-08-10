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

@Suite
struct CodegenBackendStringNumericParsingTests {

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

    @Test
    func testStringToByteAndToByteOrNullExecution() throws {
        let source = """
        fun main() {
            println("42".toByte())
            println("-42".toByte())
            println("+42".toByte())
            println("42".toByteOrNull())
            println("+42".toByteOrNull())
            println("127".toByteOrNull())
            println("128".toByteOrNull())
            println("abc".toByteOrNull())
            println(" 42 ".toByteOrNull())
            try { "999".toByte() } catch (e: Throwable) { println("overflow") }
            try { "abc".toByte() } catch (e: Throwable) { println("invalid") }
            try { " 42 ".toByte() } catch (e: Throwable) { println("whitespace") }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToByteExecution",
            expected:
                """
                42
                -42
                42
                42
                42
                127
                null
                null
                null
                overflow
                invalid
                whitespace
                """
                + "\n"
        )
    }

    @Test
    func testStringToShortAndToShortOrNullExecution() throws {
        let source = """
        fun main() {
            println("1000".toShort())
            println("-1000".toShort())
            println("+1000".toShort())
            println("32767".toShortOrNull())
            println("-32768".toShortOrNull())
            println("32768".toShortOrNull())
            println("40000".toShortOrNull())
            println("abc".toShortOrNull())
            println(" 1000 ".toShortOrNull())
            try { "40000".toShort() } catch (e: Throwable) { println("overflow") }
            try { "abc".toShort() } catch (e: Throwable) { println("invalid") }
            try { " 1000 ".toShort() } catch (e: Throwable) { println("whitespace") }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToShortExecution",
            expected:
                """
                1000
                -1000
                1000
                32767
                -32768
                null
                null
                null
                null
                overflow
                invalid
                whitespace
                """
                + "\n"
        )
    }

    @Test
    func testStringToLongAndToLongOrNullExecution() throws {
        let source = """
        fun main() {
            println("9999999999".toLong())
            println("-9999999999".toLong())
            println("+9999999999".toLong())
            println("9999999999".toLongOrNull())
            println("99999999999999999999".toLongOrNull())
            println("abc".toLongOrNull())
            println(" 9999999999 ".toLongOrNull())
            try { "99999999999999999999".toLong() } catch (e: Throwable) { println("overflow") }
            try { "abc".toLong() } catch (e: Throwable) { println("invalid") }
            try { " 9999999999 ".toLong() } catch (e: Throwable) { println("whitespace") }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToLongExecution",
            expected:
                """
                9999999999
                -9999999999
                9999999999
                9999999999
                null
                null
                null
                overflow
                invalid
                whitespace
                """
                + "\n"
        )
    }

    @Test
    func testStringToUnsignedAndToUnsignedOrNullExecution() throws {
        let source = """
        fun main() {
            println("255".toUByteOrNull())
            println("256".toUByteOrNull())
            println("65535".toUShortOrNull())
            println("65536".toUShortOrNull())
            println("4294967295".toUIntOrNull())
            println("4294967296".toUIntOrNull())
            // Compare ULong values by equality so we do not depend on signed raw rendering.
            println("18446744073709551615".toULongOrNull() == ULong.MAX_VALUE)
            println("18446744073709551616".toULongOrNull() == null)
            println(" 255 ".toUByteOrNull())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToUnsignedExecution",
            expected:
                """
                255
                null
                65535
                null
                4294967295
                null
                true
                true
                null
                """
                + "\n"
        )
    }

    @Test
    func testStringToFloatAndToFloatOrNullExecution() throws {
        let source = """
        fun main() {
            println("0.5".toFloat())
            println("-2.0".toFloat())
            println("+1.5".toFloat())
            println(" 0.5 ".toFloat())
            println("NaN".toFloat())
            println("Infinity".toFloat())
            println("0.5".toFloatOrNull())
            println("abc".toFloatOrNull())
            println(" ".toFloatOrNull())
            try { "abc".toFloat() } catch (e: Throwable) { println("invalid") }
            try { "  ".toFloat() } catch (e: Throwable) { println("empty") }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToFloatExecution",
            expected:
                """
                0.5
                -2.0
                1.5
                0.5
                NaN
                Infinity
                0.5
                null
                null
                invalid
                empty
                """
                + "\n"
        )
    }

    @Test
    func testStringToBooleanExecution() throws {
        let source = """
        fun main() {
            println("true".toBoolean())
            println("TRUE".toBoolean())
            println("True".toBoolean())
            println("false".toBoolean())
            println("False".toBoolean())
            println("yes".toBoolean())
            println("1".toBoolean())
            println("".toBoolean())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToBooleanExecution",
            expected:
                """
                true
                true
                true
                false
                false
                false
                false
                false
                """
                + "\n"
        )
    }

    @Test
    func testStringToBooleanStrictExecution() throws {
        let source = """
        fun main() {
            println("true".toBooleanStrict())
            println("false".toBooleanStrict())
            try { "True".toBooleanStrict() } catch (e: Throwable) { println("mixed-case") }
            try { "FALSE".toBooleanStrict() } catch (e: Throwable) { println("uppercase") }
            try { "yes".toBooleanStrict() } catch (e: Throwable) { println("non-boolean") }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToBooleanStrictExecution",
            expected:
                """
                true
                false
                mixed-case
                uppercase
                non-boolean
                """
                + "\n"
        )
    }

    @Test
    func testStringToBooleanStrictOrNullExecution() throws {
        let source = """
        fun main() {
            println("true".toBooleanStrictOrNull())
            println("false".toBooleanStrictOrNull())
            println("True".toBooleanStrictOrNull())
            println("FALSE".toBooleanStrictOrNull())
            println("yes".toBooleanStrictOrNull())
            println("".toBooleanStrictOrNull())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToBooleanStrictOrNullExecution",
            expected:
                """
                true
                false
                null
                null
                null
                null
                """
                + "\n"
        )
    }
}
#endif
