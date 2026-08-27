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

@Suite
struct CodegenBackendThrowableEdgeCasesTests {

    @Test
    func testCodegenThrowableSuppressedExceptionsProperty() throws {
        let source = """
        fun main() {
            val primary = RuntimeException("primary")
            primary.addSuppressed(IllegalStateException("suppressed1"))
            primary.addSuppressed(IllegalArgumentException("suppressed2"))

            val suppressed = primary.suppressedExceptions
            println(suppressed.size)
            println(suppressed[0].message)
            println(suppressed[1].message)
        }
        """

        try assertKotlinOutput(source, moduleName: "ThrowableSuppressedExceptionsRuntime", expected: "2\nsuppressed1\nsuppressed2\n")
    }

    // Regression test: string template interpolation ("$e") and the `+` concatenation
    // operator lower to kk_any_to_string, which used to fall through to printing the
    // raw pointer bit pattern for a caught Throwable instead of matching println(e)'s
    // output, because runtimeElementToString (unlike runtimeRenderAnyForPrint, used by
    // println) had no RuntimeThrowableBox case.
    //
    // Constructing IllegalStateException(...) now routes through its type-specific
    // constructor bridge, so the typed RuntimeThrowableBox adds the exception name
    // to rendered output. What this test guards is that all three conversions ($e,
    // +, println) stay in lockstep and none of them regresses to printing a raw pointer.
    @Test
    func testCodegenCaughtThrowableStringConversionMatchesPrintln() throws {
        let source = """
        fun main() {
            try {
                throw IllegalStateException("existing type test")
            } catch (e: IllegalStateException) {
                println("interp existing: $e")
                println("plus existing: " + e)
                println(e)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ThrowableStringTemplateConcatIllegalState",
            expected:
                """
                interp existing: Throwable(IllegalStateException: existing type test)
                plus existing: Throwable(IllegalStateException: existing type test)
                Throwable(IllegalStateException: existing type test)
                """ + "\n"
        )
    }

    // Same regression as above, exercised through a different pre-existing exception
    // type (ArithmeticException raised by integer division by zero) to confirm the
    // fix is general and not tied to IllegalStateException specifically.
    @Test
    func testCodegenCaughtArithmeticExceptionStringConversionMatchesPrintln() throws {
        let source = """
        fun main() {
            val n = 1
            val zero = 0
            try {
                println(n / zero)
            } catch (e: ArithmeticException) {
                println("interp arith: $e")
                println("plus arith: " + e)
                println(e)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ThrowableStringTemplateConcatArithmetic",
            expected:
                """
                interp arith: Throwable(ArithmeticException: / by zero)
                plus arith: Throwable(ArithmeticException: / by zero)
                Throwable(ArithmeticException: / by zero)
                """ + "\n"
        )
    }

    // KSP-1242: InvalidMutabilityException(message) must allocate the typed
    // runtime box so both its message property and RuntimeException catch
    // dispatch remain observable after construction.
    @Test
    func testCodegenInvalidMutabilityExceptionConstructorAndCatch() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.concurrent.InvalidMutabilityException

        fun main() {
            try {
                throw InvalidMutabilityException("mutation blocked")
            } catch (e: InvalidMutabilityException) {
                println(e.message)
                println(e.cause == null)
                println(e is RuntimeException)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "InvalidMutabilityExceptionConstructorAndCatch",
            expected: "mutation blocked\ntrue\ntrue\n"
        )
    }

    // KSP-616: TODO() is a bundled Kotlin declaration throwing NotImplementedError,
    // which must stay catchable both as its own type and as its Error supertype.
    func testCodegenTodoThrowsCatchableNotImplementedError() throws {
        let source = """
        fun main() {
            try {
                TODO()
            } catch (e: NotImplementedError) {
                println(e.message)
            }
            try {
                TODO("later")
            } catch (e: Error) {
                println(e.message)
            }
            try {
                TODO("rendered")
            } catch (e: Throwable) {
                println(e)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TodoNotImplementedError",
            expected:
                """
                An operation is not implemented.
                An operation is not implemented: later
                Throwable(NotImplementedError: An operation is not implemented: rendered)
                """ + "\n"
        )
    }
}
#endif
