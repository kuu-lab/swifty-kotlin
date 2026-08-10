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
}
