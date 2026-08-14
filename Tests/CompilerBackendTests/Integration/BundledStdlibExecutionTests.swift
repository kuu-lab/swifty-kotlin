@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// KSP-INF-006: bundled `.kt` 自己完結実行テストハーネス。
/// Kotlin ソースを executable までコンパイルし、実行後の stdout を期待値と比較する。
/// kotlinc を使わない第二 oracle として機能する。
@Suite
struct BundledStdlibExecutionTests {
    private struct ExecutionFailure: Error, CustomStringConvertible {
        let description: String
    }

    /// Compile `source` to an executable, run it, and assert stdout equals `expectedOutput`.
    private func compileAndRunKotlin(
        _ source: String,
        expectedOutput: String,
        moduleName: String = "ExecTest"
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? fm.removeItem(atPath: outputBase) }

            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let result = makeTestDriver().runForTesting(options: options)

            guard result.exitCode == 0 else {
                let diagnostics = result.diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: ", ")
                throw ExecutionFailure(
                    description: "Compilation failed. Diagnostics: \(diagnostics)"
                )
            }
            guard !result.diagnostics.contains(where: { $0.severity == .error }) else {
                let errors = result.diagnostics
                    .filter { $0.severity == .error }
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: ", ")
                throw ExecutionFailure(description: "Unexpected errors: \(errors)")
            }

            let runResult = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalized = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalized == expectedOutput,
                "Expected stdout '\(expectedOutput)' but got '\(normalized)'"
            )
        }
    }

    @Test
    func testHelloWorldPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println("hello")
            }
            """,
            expectedOutput: "hello\n"
        )
    }

    @Test
    func testForInRangePrintsSequence() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                for (i in 1..4) {
                    print(i)
                }
                println()
            }
            """,
            expectedOutput: "1234\n"
        )
    }

    @Test
    func testListFilterMapPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val result = listOf(1, 2, 3, 4)
                    .filter { it > 1 }
                    .map { it * 2 }
                    .joinToString("-")
                println(result)
            }
            """,
            expectedOutput: "4-6-8\n"
        )
    }

    @Test
    func testListSortedPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val result = listOf(3, 1, 4, 1, 5)
                    .sorted()
                    .joinToString(",")
                println(result)
            }
            """,
            expectedOutput: "1,1,3,4,5\n"
        )
    }

    // KSP-INF-011 regression: List<Int>.joinToString must render integers, not
    // fall back to the string-only runtime fast path and produce empty output.
    @Test
    func testListIntJoinToStringWithTransformPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(listOf(1, 2, 3).joinToString("-", "[", "]") { it.toString() })
            }
            """,
            expectedOutput: "[1-2-3]\n"
        )
    }

    // KSP-INF-011 regression: Array<Int>.joinToString must also render generic
    // element types through the guarded default overload.
    @Test
    func testArrayIntJoinToStringPrintsExpectedOutput() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(arrayOf(7, 8, 9).joinToString("-"))
            }
            """,
            expectedOutput: "7-8-9\n"
        )
    }

    // KSP-677 regression: a generic higher-order function `fun <T> f(action: () -> T): T`
    // must infer `T` from the lambda body, including a Unit-valued body. The type checker
    // previously pushed the unresolved type parameter down as the body's expected type,
    // which made a Unit-bodied lambda produce an error type and fail overload resolution.
    @Test
    func testGenericHigherOrderFunctionInfersUnitAndValueLambdaReturnType() throws {
        try compileAndRunKotlin(
            """
            class Box
            fun <T> Box.run2(action: () -> T): T = action()
            fun main() {
                Box().run2 { println("unit") }
                val n: Int = Box().run2 { 40 + 2 }
                println(n)
            }
            """,
            expectedOutput: "unit\n42\n"
        )
    }

    // KSP-677 regression: Mutex.withLock is bundled Kotlin source (a generic suspend
    // extension composing the c-soft lock/unlock kernel). Repeated Unit-bodied calls and
    // a value-returning call must all type-check and run.
    @Test
    func testMutexWithLockMigratedToKotlinSource() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.sync.Mutex
            import kotlinx.coroutines.sync.withLock
            fun main() = runBlocking {
                val m = Mutex()
                var counter = 0
                m.withLock { counter++ }
                m.withLock { counter++ }
                val label: String = m.withLock { "done" }
                println(counter)
                println(label)
            }
            """,
            expectedOutput: "2\ndone\n"
        )
    }

    // KSP-618 regression: kotlin.synchronized is bundled Kotlin source delegating to the
    // demoted __kk_synchronized bridge. The block reaches the wrapper as a boxed function
    // value, so the closure-thunk expansion must recover its (fnPtr, closureRaw) pair —
    // otherwise a capturing block either crashes or loses its captures.
    @Test
    func testSynchronizedMigratedToKotlinSource() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val lock = object {}
                var counter = 0
                val result = synchronized(lock) {
                    counter += 1
                    val nested = synchronized(lock) { counter + 40 }
                    nested + 1
                }
                println(result)
                println(counter)
                val text: String = synchronized(lock) { "hello" }
                println(text)
                try {
                    synchronized(lock) { throw IllegalStateException("boom") }
                } catch (e: Throwable) {
                    println(e.message ?: "missing")
                }
            }
            """,
            expectedOutput: "42\n1\nhello\nboom\n"
        )
    }

    // KSP-677 regression: Semaphore.withPermit is bundled Kotlin source (a generic suspend
    // extension composing the c-soft acquire/release kernel).
    @Test
    func testSemaphoreWithPermitMigratedToKotlinSource() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.sync.Semaphore
            import kotlinx.coroutines.sync.withPermit
            fun main() = runBlocking {
                val s = Semaphore(2)
                var n = 0
                s.withPermit { n += 10 }
                s.withPermit { n += 5 }
                println(n)
            }
            """,
            expectedOutput: "15\n"
        )
    }

    // KSP-612: DeepRecursiveFunction / DeepRecursiveScope は bundled Kotlin source。
    // block は receiver ラムダ `DeepRecursiveScope<T, R>.(T) -> R` として lower され、
    // 暗黙 `it` / 明示パラメータ / 外側変数キャプチャの3形とも runtime トランポリン経由で
    // 正しく再帰することを end-to-end で検証する。
    @Test
    func testDeepRecursiveFunctionMigratedToKotlinSource() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val sumTo = DeepRecursiveFunction<Int, Int> {
                    if (it <= 0) 0 else it + callRecursive(it - 1)
                }
                val factorial = DeepRecursiveFunction<Int, Int> { n ->
                    if (n <= 1) 1 else n * callRecursive(n - 1)
                }
                val step = 3
                val countDown = DeepRecursiveFunction<Int, Int> { n ->
                    if (n <= 0) 0 else callRecursive(n - step) + 1
                }
                println(sumTo(10))
                println(factorial(5))
                println(countDown(9))
            }
            """,
            expectedOutput: "55\n120\n3\n"
        )
    }

    // KSP-661: Char 判定系は bundled Kotlin (kotlin.text.CharPredicates) で実装され、
    // Unicode テーブル参照だけを __kk_char_* ブリッジ経由で行う。移行後の述語が
    // 実際にコンパイル・実行され正しい結果を返すことを end-to-end で検証する。
    @Test
    func testCharPredicatesExecuteThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println('A'.isLetter())
                println('1'.isDigit())
                println(' '.isWhitespace())
                println('\\t'.isWhitespace())
                println('7'.isLetterOrDigit())
                println('!'.isLetterOrDigit())
                println('A'.isUpperCase())
                println('a'.isLowerCase())
                println('\\u2160'.isUpperCase())
                println('\\u2170'.isLowerCase())
                println('A'.isDefined())
                println('\\u0378'.isDefined())
                println('\\uD800'.isDefined())
            }
            """,
            expectedOutput: """
            true
            true
            true
            true
            true
            false
            true
            true
            true
            true
            true
            false
            true

            """
        )
    }

    /// KSP-614: `print`/`println` are Kotlin declarations in
    /// `Stdlib/kotlin/io/Console.kt` on top of the single `__kk_print_raw`
    /// bridge; every overload (including the argument-less ones) must resolve
    /// and the newline must be appended on the Kotlin side.
    @Test
    func testConsolePrintOverloadsAreKotlinBacked() throws {
        try compileAndRunKotlin(
            """
            data class P(val a: Int)

            fun main() {
                println()
                print()
                print("a")
                print(1)
                println()
                println("b")
                println(2)
                println(null)
                println(P(3))
                println(listOf(1, 2))
            }
            """,
            expectedOutput: """

            a1
            b
            2
            null
            P(a=3)
            [1, 2]

            """
        )
    }

    // KSP-625: The public ArrayDeque surface is bundled Kotlin. Empty and bounds checks
    // and toString stay in Kotlin; only ring-buffer mutation crosses the __kk_arraydeque_* bridges.
    @Test
    func testArrayDequeMigratedToKotlinSource() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val deque = ArrayDeque<Int>()
                println(deque.isEmpty())
                deque.addLast(2)
                deque.addFirst(1)
                deque.addLast(3)
                println(deque.size)
                println(deque.first())
                println(deque.last())
                println(deque[1])
                println(deque)
                println(deque.removeFirst())
                println(deque.removeLast())
                println(deque)
                try {
                    ArrayDeque<Int>().first()
                } catch (e: NoSuchElementException) {
                    println(e.message)
                }
                try {
                    deque[5]
                } catch (e: IndexOutOfBoundsException) {
                    println(e.message)
                }
            }
            """,
            expectedOutput: """
            true
            3
            1
            3
            2
            [1, 2, 3]
            1
            3
            [2]
            ArrayDeque is empty.
            index: 5, size: 1

            """
        )
    }

    // KSP-662: Char conversions are bundled in kotlin.text.CharConversions.
    // Only Unicode case mapping and digit-table lookup cross the __kk_char_* bridges.
    @Test
    func testCharConversionsExecuteThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println('a'.uppercaseChar())
                println('A'.lowercaseChar())
                println('\\u00DF'.uppercaseChar())
                println('\\u01C6'.titlecaseChar())
                println('a'.uppercase())
                println('\\u00DF'.uppercase())
                println('\\u01C6'.titlecase())
                println('7'.digitToInt())
                println('f'.digitToInt(16))
                println('z'.digitToIntOrNull())
                println('g'.digitToIntOrNull(16))
                println(7.digitToChar())
                println(10.digitToChar(16))
                try {
                    '!'.digitToInt()
                } catch (e: IllegalArgumentException) {
                    println("invalid-digit")
                }
                try {
                    1.digitToChar(1)
                } catch (e: IllegalArgumentException) {
                    println("invalid-radix")
                }
            }
            """,
            expectedOutput: """
            A
            a
            \u{00DF}
            \u{01C5}
            A
            SS
            \u{01C5}
            7
            15
            null
            null
            7
            A
            invalid-digit
            invalid-radix

            """
        )
    }

    /// KSP-643: count* functions now execute through the bundled Kotlin implementation.
    /// This also covers BUG-015, where Long variants passed Sema but disappeared during KIR lowering.
    @Test
    func testBitCountFunctionsExecuteThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(255.countOneBits())
                println((-1).countOneBits())
                println(Int.MIN_VALUE.countLeadingZeroBits())
                println(1.countLeadingZeroBits())
                println(0.countTrailingZeroBits())
                println(1024.countTrailingZeroBits())
                println(255L.countOneBits())
                println(Long.MAX_VALUE.countOneBits())
                println(255L.countLeadingZeroBits())
                println(0L.countLeadingZeroBits())
                println(0L.countTrailingZeroBits())
                println(1024L.countTrailingZeroBits())
            }
            """,
            expectedOutput: """
            8
            32
            0
            31
            32
            10
            8
            63
            56
            64
            64
            10

            """
        )
    }

    /// KSP-635: Exercise the bundled Kotlin abs/sign/min/max and PI/E
    /// implementations across overflow, NaN, and signed-zero edge cases.
    @Test
    func testMathAbsSignMinMaxExecuteThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            import kotlin.math.*

            fun main() {
                println(abs(-4.5))
                println(abs(-3.5f))
                println(abs(-7))
                println(abs(Int.MIN_VALUE))
                println(abs(Long.MIN_VALUE))
                println((-4.5).absoluteValue)
                println(1.0 / abs(-0.0))
                println(abs(Double.NaN).isNaN())
                println(sign(-2.5))
                println(sign(0.0f))
                println((-9L).sign)
                println(sign(Double.NaN).isNaN())
                println(max(2, 3))
                println(min(-2L, 3L))
                println(max(1.5f, 2.5f))
                println(min(1u, 2u))
                println(max(1uL, 2uL))
                println(max(Double.NaN, 1.0).isNaN())
                println(1.0 / max(-0.0, 0.0))
                println(1.0 / min(-0.0, 0.0))
                println(PI)
                println(E)
            }
            """,
            expectedOutput: """
            4.5
            3.5
            7
            -2147483648
            -9223372036854775808
            4.5
            Infinity
            true
            -1.0
            0.0
            -1
            true
            3
            -2
            2.5
            1
            2
            true
            Infinity
            -Infinity
            3.141592653589793
            2.718281828459045

            """
        )
    }

    // KSP-472: measureTime / measureTimedValue が bundled Kotlin の inline 関数として
    // 展開され、ラムダ・関数参照・例外伝播のいずれでも正しく動くことを検証する。
    @Test
    func testMeasureTimeExecutesThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            import kotlin.time.measureTime
            import kotlin.time.measureTimedValue

            fun work(): Int {
                var sum = 0
                for (i in 1..1000) {
                    sum += i
                }
                return sum
            }

            fun noop() {
            }

            fun main() {
                println(measureTime { work() }.inWholeNanoseconds >= 0L)
                println(measureTime(::noop).inWholeNanoseconds >= 0L)

                val timed = measureTimedValue { work() }
                println(timed.value)
                println(timed.duration.inWholeNanoseconds >= 0L)

                try {
                    measureTime { throw RuntimeException("boom") }
                } catch (e: RuntimeException) {
                    println(e.message)
                }
            }
            """,
            expectedOutput: """
            true
            true
            500500
            true
            boom

            """
        )
    }

    // KSP-625 regression: implicit size/isEmpty reads on user classes must use their
    // declared properties rather than collection runtime shortcuts.
    @Test
    func testImplicitReceiverSizeReadsUserDefinedProperty() throws {
        try compileAndRunKotlin(
            """
            class Box {
                val size: Int
                    get() = 5
                val isEmpty: Boolean
                    get() = false
                fun readSize(): Int = size
                fun readIsEmpty(): Boolean = isEmpty
            }
            fun main() {
                val box = Box()
                println(box.readSize())
                println(box.size)
                println(box.readIsEmpty())
            }
            """,
            expectedOutput: "5\n5\nfalse\n"
        )
    }

    // KSP-642: rotateLeft / rotateRight は bundled Kotlin (kotlin.Numbers) で
    // shl / ushr / or だけを使って実装される。シフト量のマスク（Int は 5bit、
    // Long は 6bit）に依存するため、0 / 幅ちょうど / 幅超過 / 負値の境界を検証する。
    @Test
    func testRotateExecutesThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(1.rotateLeft(1))
                println(1.rotateLeft(31))
                println(1.rotateLeft(32))
                println(1.rotateLeft(-1))
                println((-1).rotateLeft(5))
                println(Int.MIN_VALUE.rotateLeft(1))
                println(1.rotateRight(1))
                println(1.rotateRight(32))
                println(0x12345678.rotateRight(8))
                println(1L.rotateLeft(63))
                println(1L.rotateLeft(64))
                println(1L.rotateRight(1))
                println(Long.MIN_VALUE.rotateRight(1))
                println(0x0F0F0F0F.rotateLeft(4).rotateRight(4))
            }
            """,
            expectedOutput: """
            2
            -2147483648
            1
            -2147483648
            -1
            1
            -2147483648
            1
            2014458966
            -9223372036854775808
            1
            -9223372036854775808
            4611686018427387904
            252645135

            """
        )
    }

    // KSP-496 regression: KClass.cast/safeCast are bundled Kotlin extensions
    // calling the throwing `__kk_kclass_cast` / non-throwing
    // `__kk_kclass_safeCast` runtime ABI, so both the success and the
    // ClassCastException paths must survive the ordinary call lowering.
    @Test
    func testKClassCastAndSafeCastExecuteThroughBundledExtensions() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KClass

            class Box(val value: Int)

            fun <T : Any> castVia(klass: KClass<T>, value: Any?): T = klass.cast(value)

            fun main() {
                println(String::class.cast("hello"))
                println(Int::class.cast(7))
                println(castVia(String::class, "generic"))
                println(String::class.safeCast(1))
                println(Box::class.safeCast(Box(3))?.value)
                val klass = String::class
                println(klass.cast("via local"))
                try {
                    Int::class.cast("nope")
                } catch (e: ClassCastException) {
                    println("caught")
                }
            }
            """,
            expectedOutput: """
            hello
            7
            generic
            null
            3
            via local
            caught

            """
        )
    }

    /// BUG-164: A callable reference passed to a `fun interface` parameter
    /// must be SAM-converted and the containing function must still be called.
    @Test
    func testCallableRefPassedToFunInterfaceParameterRuns() throws {
        try compileAndRunKotlin(
            """
            fun interface IntOp { fun apply(a: Int, b: Int): Int }

            fun useOp(o: IntOp): Int = o.apply(10, 4)

            fun myCompare(a: Int, b: Int): Int = a - b

            fun main() {
                println(useOp(::myCompare))
            }
            """,
            expectedOutput: "6\n"
        )
    }

    // KSP-646: Double/Float isNaN, isInfinite, and isFinite are implemented in
    // bundled Kotlin (kotlin/util/Numbers.kt) using IEEE 754 bit-pattern checks.
    // Verify signed zero, subnormal values, computed NaNs, and payload NaNs
    // end to end.
    @Test
    func testFloatingPointPredicatesExecuteThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(Double.NaN.isNaN())
                println((0.0 / 0.0).isNaN())
                println(Double.fromBits(0x7FF0000000000001L).isNaN())
                println(1.0.isNaN())
                println(Double.POSITIVE_INFINITY.isNaN())
                println(Double.POSITIVE_INFINITY.isInfinite())
                println(Double.NEGATIVE_INFINITY.isInfinite())
                println(Double.MAX_VALUE.isInfinite())
                println(Double.NaN.isInfinite())
                println((-0.0).isFinite())
                println(Double.MIN_VALUE.isFinite())
                println(Double.POSITIVE_INFINITY.isFinite())
                println(Double.NaN.isFinite())
                println(Float.NaN.isNaN())
                println(Float.fromBits(0x7F800001).isNaN())
                println(1.0f.isNaN())
                println(Float.POSITIVE_INFINITY.isInfinite())
                println(Float.MAX_VALUE.isInfinite())
                println((-0.0f).isFinite())
                println(Float.MIN_VALUE.isFinite())
                println(Float.NEGATIVE_INFINITY.isFinite())
            }
            """,
            expectedOutput: """
            true
            true
            true
            false
            false
            true
            true
            false
            false
            true
            true
            false
            false
            true
            true
            false
            true
            false
            true
            true
            false

            """
        )
    }


    // KSP-417: These APIs use private runtime bridges. This also guards the
    // flat-string return ABI for __kk_string_normalize_flat.
    @Test
    func testUnicodeNormalizationAndCodePointBridgesExecute() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val decomposed = "e\\u0301"
                val composed = decomposed.normalize(NormalizationForms.NFC)
                println(composed.length)
                println(composed == "\\u00e9")
                println(composed.normalize(NormalizationForms.NFD).length)
                println("\\ufb01".normalize(NormalizationForms.NFKC))
                println("\\ufb01".normalize(NormalizationForms.NFKD))
                println(composed.isNormalized(NormalizationForms.NFC))
                println(decomposed.isNormalized(NormalizationForms.NFC))
                println("abc".codePointCount())
                println("e\\u0301x".codePointCount(1))
                println("e\\u0301x".codePointCount(0, 2))
                val picked = "abc".random()
                println(picked == 'a' || picked == 'b' || picked == 'c')
            }
            """,
            expectedOutput: """
            1
            true
            2
            fi
            fi
            true
            false
            3
            2
            2
            true

            """
        )
    }

    // Runtime-produced flat strings store a Unicode scalar count in `length`
    // and the UTF-8 byte count separately in `byteCount`.
    @Test
    func testRuntimeProducedFlatStringsReportScalarLength() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println("\\u00c9".length)
                println("\\u00c9".lowercase().length)
                println("  \\u00e9\\u00e9  ".trim().length)
            }
            """,
            expectedOutput: """
            1
            1
            2

            """
        )
    }

    // Regression for a lambda-capture lowering bug: `let` / `?.let` blocks that
    // capture an outer variable must forward the lambda parameter (`it`)
    // correctly instead of shadowing it with the capture.
    @Test
    func testLetLambdaForwardsItWhenCapturingOuterVariable() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val outer = 10
                val s: String = "hi"
                val r = s.let { it + ":" + outer.toString() }
                println(r)

                val n: String? = "hello"
                val q = n?.let { it + ":" + outer.toString() }
                println(q ?: "null")
            }
            """,
            expectedOutput: "hi:10\nhello:10\n"
        )
    }

    // KSP-640 regression: UByte/UShort/UInt/ULong coerceIn/coerceAtLeast/coerceAtMost
    // are now bundled Kotlin source (RangeCoercion.kt) and should execute through the
    // normal extension-function path, including unsigned comparisons above Int.max.
    @Test
    func testUnsignedCoercionExecutesThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                // UByte / UShort
                println(5.toUByte().coerceIn(1.toUByte(), 10.toUByte()).toInt())
                println(0.toUByte().coerceIn(1.toUByte(), 10.toUByte()).toInt())
                println(15.toUByte().coerceIn(1.toUByte(), 10.toUByte()).toInt())
                println(5.toUByte().coerceAtLeast(10.toUByte()).toInt())
                println(15.toUByte().coerceAtMost(10.toUByte()).toInt())

                println(500.toUShort().coerceIn(100.toUShort(), 900.toUShort()).toInt())
                println(50.toUShort().coerceIn(100.toUShort(), 900.toUShort()).toInt())
                println(1000.toUShort().coerceIn(100.toUShort(), 900.toUShort()).toInt())
                println(50.toUShort().coerceAtLeast(100.toUShort()).toInt())
                println(1000.toUShort().coerceAtMost(900.toUShort()).toInt())

                // UInt / ULong with values above Int.max to exercise unsigned comparison.
                val lowerUInt = Int.MAX_VALUE.toUInt() + 10u
                val upperUInt = lowerUInt + 20u
                val middleUInt = lowerUInt + 7u
                println(middleUInt.coerceIn(lowerUInt, upperUInt) == middleUInt)
                println((lowerUInt - 1u).coerceIn(lowerUInt, upperUInt) == lowerUInt)
                println((upperUInt + 1u).coerceIn(lowerUInt, upperUInt) == upperUInt)
                println((lowerUInt - 1u).coerceAtLeast(lowerUInt) == lowerUInt)
                println((upperUInt + 1u).coerceAtMost(upperUInt) == upperUInt)

                val lowerULong = Long.MAX_VALUE.toULong() + 10uL
                val upperULong = lowerULong + 20uL
                val middleULong = lowerULong + 7uL
                println(middleULong.coerceIn(lowerULong, upperULong) == middleULong)
                println((lowerULong - 1uL).coerceIn(lowerULong, upperULong) == lowerULong)
                println((upperULong + 1uL).coerceIn(lowerULong, upperULong) == upperULong)
                println((lowerULong - 1uL).coerceAtLeast(lowerULong) == lowerULong)
                println((upperULong + 1uL).coerceAtMost(upperULong) == upperULong)

                // Range overloads for UInt / ULong.
                val uintRange = lowerUInt..upperUInt
                println(middleUInt.coerceIn(uintRange) == middleUInt)
                val ulongRange = lowerULong..upperULong
                println(middleULong.coerceIn(ulongRange) == middleULong)
            }
            """,
            expectedOutput: """
            5
            1
            10
            10
            10
            500
            100
            900
            100
            900
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true

            """
        )
    }

    // KSP-641 regression: generic Comparable coercion and the
    // ClosedFloatingPointRange overload must be source-backed and executable.
    @Test
    func testComparableCoercionExecutesThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            class Score(val value: Int) : Comparable<Score> {
                override fun compareTo(other: Score): Int = value.compareTo(other.value)
            }

            fun catchesIllegalArgument(action: () -> Unit): Boolean {
                return try {
                    action()
                    false
                } catch (e: IllegalArgumentException) {
                    true
                }
            }

            fun main() {
                println(Score(5).coerceIn(null, Score(3)).value)
                println(Score(5).coerceIn(Score(7), null).value)
                println(Score(5).coerceIn(null, null).value)
                println(Score(5).coerceIn(Score(1), Score(10)).value)
                println(catchesIllegalArgument { Score(5).coerceIn(Score(10), Score(1)) })

                println(9.9.coerceIn(1.0..10.0))
                println(0.0.coerceIn(1.0..10.0))
                println(10.0.coerceIn(1.0..10.0))
                println(Double.NaN.coerceIn(1.0..10.0).isNaN())
                println(catchesIllegalArgument { 9.9.coerceIn(1.0..Double.NaN) })
                println(catchesIllegalArgument { 9.9.coerceIn(10.0..1.0) })
                println(0.0f.coerceIn(1.0f..10.0f))
                println(Float.NaN.coerceIn(1.0f..10.0f).isNaN())
                println(catchesIllegalArgument { 9.9f.coerceIn(1.0f..Float.NaN) })
                println(catchesIllegalArgument { 9.9f.coerceIn(10.0f..1.0f) })
            }
            """,
            expectedOutput: """
            3
            7
            5
            5
            true
            9.9
            1.0
            10.0
            true
            true
            true
            1.0
            true
            true
            true

            """,
            moduleName: "ComparableCoercion"
        )
    }
}
