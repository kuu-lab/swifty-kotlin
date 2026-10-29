#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

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

    @Test(arguments: [true, false])
    func testCodegenThrowableSuppressedArrayProperty(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("kuu1326_throwable_suppressed_array.kt")

        try assertKotlinOutput(
            source,
            moduleName: "ThrowableSuppressedArrayProperty",
            expected: "0\n1\ntrue\nfirst\n1\n2\nsecond\n2\n2\n0\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testCodegenJVMCompatibleRuntimeExceptionConstructorHonorsFlags() throws {
        let source = """
        class Return(val value:Int):RuntimeException(null,null,false,false)
        class KotloxReturn(val value: Any?) : RuntimeException(null, null, false, false)
        class DisabledSuppression(message: String?, cause: Throwable?) :
            RuntimeException(message, cause, false, true)
        class DisabledStackTrace(message: String?, cause: Throwable?) :
            RuntimeException(message, cause, true, false)
        class EnabledOptions(message: String?, cause: Throwable?) :
            RuntimeException(message, cause, true, true)
        class CauseOnly(cause: Throwable?) : RuntimeException(cause)
        class TwoArgument(message: String?, cause: Throwable?) : RuntimeException(message, cause)

        fun main() {
            try {
                throw Return(3)
            } catch (e: Return) {
                println(e.value)
                println(e.message)
            }

            try {
                throw KotloxReturn(3)
            } catch (e: KotloxReturn) {
                println(e.value)
                println(e.message)
            }

            val cause = IllegalArgumentException("root cause")
            val disabledSuppression = DisabledSuppression("disabled", cause)
            disabledSuppression.addSuppressed(IllegalStateException("ignored"))
            println(disabledSuppression.message)
            println(disabledSuppression.cause === cause)
            println(disabledSuppression.getSuppressed().size)
            println(disabledSuppression.getStackTrace().size > 0)

            val disabledStackTrace = DisabledStackTrace("no stack", cause)
            disabledStackTrace.addSuppressed(IllegalStateException("kept"))
            println(disabledStackTrace.message)
            println(disabledStackTrace.cause === cause)
            println(disabledStackTrace.getSuppressed().size)
            println(disabledStackTrace.getStackTrace().size)

            val enabledOptions = EnabledOptions("enabled", cause)
            enabledOptions.addSuppressed(IllegalStateException("kept"))
            println(enabledOptions.message)
            println(enabledOptions.getSuppressed().size)
            println(enabledOptions.getStackTrace().size > 0)

            val causeOnly = CauseOnly(cause)
            println(causeOnly.message == cause.toString())
            println(causeOnly.cause === cause)

            val twoArgument = TwoArgument("two argument", cause)
            println(twoArgument.message)
            println(twoArgument.cause === cause)
        }
        """
        let expected = """
        3
        null
        3
        null
        disabled
        true
        0
        true
        no stack
        true
        1
        0
        enabled
        1
        true
        true
        true
        two argument
        true
        """ + "\n"
        let modes: [(allowDefaultStdlibLibrary: Bool, optLevel: OptimizationLevel)] = [
            (false, .O0),
            (false, .O2),
            (true, .O0),
            (true, .O2),
        ]

        let inputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        try source.write(toFile: inputPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: inputPath) }

        func assertMode(_ mode: (allowDefaultStdlibLibrary: Bool, optLevel: OptimizationLevel), index: Int) throws {
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }

            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "RuntimeExceptionFourArgumentOptions\(index)",
                outputPath: outputBase,
                optLevel: mode.optLevel,
                allowDefaultStdlibLibrary: mode.allowDefaultStdlibLibrary
            )
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
            #expect(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        for (index, mode) in modes.enumerated() {
            try assertMode(mode, index: index)
        }
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
                interp existing: java.lang.IllegalStateException: existing type test
                plus existing: java.lang.IllegalStateException: existing type test
                java.lang.IllegalStateException: existing type test
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
                interp arith: java.lang.ArithmeticException: / by zero
                plus arith: java.lang.ArithmeticException: / by zero
                java.lang.ArithmeticException: / by zero
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
}
#endif
