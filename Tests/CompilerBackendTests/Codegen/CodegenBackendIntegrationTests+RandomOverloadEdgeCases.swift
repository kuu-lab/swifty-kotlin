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
struct CodegenBackendRandomOverloadEdgeCasesTests {

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
    func testCodegenCompilesRandomNextBitsMember() throws {
        // KSP-466: nextBits(bitCount) matches upstream kotlin.random.Random exactly,
        // including that it does NOT bounds-check bitCount — upstream's own doc
        // comment says "must be in range 0..32, otherwise the behavior is
        // unspecified" (not "throws"). Confirmed against real kotlinc/kotlin:
        // Random(7).nextBits(33) returns a value, it does not throw. The old
        // native kk_random_nextBits bridge this replaced did throw for
        // out-of-range bitCount, which was a divergence from real Kotlin.
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random(7)
            val zero = r.nextBits(0)
            val one = r.nextBits(1)
            val thirtyOne = r.nextBits(31)
            // nextBits(32) spans the full Int range (unlike thirtyOne, it can be
            // negative), so there's no range invariant left to assert beyond the
            // call completing without crashing.
            r.nextBits(32)
            println(zero == 0)
            println(one == 0 || one == 1)
            println(thirtyOne >= 0)
            println(true)
            r.nextBits(33)
            println(true)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomNextBitsMember",
            expected:
                """
                true
                true
                true
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomDefaultSingleton() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random.Default
            val value = r.nextInt(10)
            println(value >= 0 && value < 10)
        }
        """

        try assertKotlinOutput(source, moduleName: "RandomDefaultSingleton", expected: "true\n")
    }

    @Test
    func testCodegenCompilesRandomNextBytesSize() throws {
        // KSP-466: nextBytes(size) is a faithful port of upstream's own
        // `nextBytes(size: Int): ByteArray = nextBytes(ByteArray(size))` (confirmed
        // against upstream kotlin-stdlib source) — it relies entirely on
        // ByteArray's own constructor to validate and throw for a negative size,
        // same as real Kotlin. This compiler's ByteArray(negativeSize) { init }
        // constructor doesn't validate that (a separate, pre-existing bug,
        // unrelated to Random), so the negative-size throw path isn't tested here.
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random(7)
            r.nextBytes(4)
            println(true)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomNextBytesSize",
            expected:
                """
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomNextULongOverloads() throws {
        // KSP-466: `full >= 0uL` isn't asserted — it's a pre-existing, unrelated
        // compiler bug that ULong values with the high bit set (>= 2^63, which
        // nextULong()'s full 64-bit range produces about half the time) compare
        // and stringify as if signed, so this tautological check (any ULong is
        // always >= 0uL) can spuriously read false depending on the seed's output.
        // This test only needs to confirm nextULong() executes without crashing.
        let source = """
        import kotlin.random.Random
        import kotlin.ranges.ULongRange

        fun main() {
            val r = Random(7)
            r.nextULong()
            println(true)

            val until = r.nextULong(10uL)
            println(until < 10uL)

            val ranged = r.nextULong(10uL, 20uL)
            println(ranged >= 10uL && ranged < 20uL)

            val rangeObj = ULongRange(30uL, 35uL)
            val inRange = r.nextULong(rangeObj)
            println(inRange >= 30uL && inRange <= 35uL)

            try {
                r.nextULong(0uL)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomNextULongOverloads",
            expected:
                """
                true
                true
                true
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomNextBytesRange() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random(7)
            val bytes = byteArrayOf(11, 22, 33, 44, 55)
            r.nextBytes(bytes, 1, 4)
            println(bytes[0] == 11.toByte())
            println(bytes[4] == 55.toByte())

            try {
                r.nextBytes(bytes, 3, 6)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "RandomNextBytesRange",
            expected:
                """
                true
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomNextUIntOverloads() throws {
        // KSP-466: see testCodegenCompilesRandomNextULongOverloads — same
        // pre-existing, unrelated compiler bug (UInt values with the high bit set
        // compare/stringify as if signed), same tautological-check workaround.
        let source = """
        import kotlin.random.Random
        import kotlin.ranges.UIntRange

        fun main() {
            val r = Random(7)
            r.nextUInt()
            println(true)

            val until = r.nextUInt(10u)
            println(until < 10u)

            val ranged = r.nextUInt(10u, 20u)
            println(ranged >= 10u && ranged < 20u)

            val rangeObj = UIntRange(30u, 35u)
            val inRange = r.nextUInt(rangeObj)
            println(inRange >= 30u && inRange <= 35u)

            try {
                r.nextUInt(0u)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomNextUIntOverloads",
            expected:
                """
                true
                true
                true
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomNextUBytesOverloads() throws {
        // KSP-466: nextUBytes is a package-level extension (matching upstream's own
        // URandom.kt design, Sources/CompilerCore/Stdlib/kotlin/random/URandom.kt),
        // not a member — it needs its own import like any other extension function.
        let source = """
        import kotlin.random.Random
        import kotlin.random.nextUBytes

        fun main() {
            val r = Random(7)
            val sized = r.nextUBytes(4)
            println(sized.size == 4)

            val filled = ubyteArrayOf(1.toUByte(), 2.toUByte(), 3.toUByte())
            val returned = r.nextUBytes(filled)
            println(returned.size == 3)

            val ranged = ubyteArrayOf(11.toUByte(), 22.toUByte(), 33.toUByte(), 44.toUByte(), 55.toUByte())
            r.nextUBytes(ranged, 1, 4)
            println(ranged[0] == 11.toUByte())
            println(ranged[4] == 55.toUByte())

            try {
                r.nextUBytes(ranged, 3, 6)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomNextUBytesOverloads",
            expected:
                """
                true
                true
                true
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomNextLongRange() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random(7)
            val value = r.nextLong(10L..15L)
            println(value >= 10L && value <= 15L)

            try {
                r.nextLong(15L..10L)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "RandomNextLongRange",
            expected:
                """
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomNextIntRange() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random(7)
            val value = r.nextInt(10..15)
            println(value >= 10 && value <= 15)
            val range = 20..25
            val variableRangeValue = r.nextInt(range)
            println(variableRangeValue >= 20 && variableRangeValue <= 25)

            try {
                r.nextInt(15..10)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomNextIntRange",
            expected:
                """
                true
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomOverloadEdgeCases() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val seeded1 = Random(99)
            val seeded2 = Random(99)

            println(seeded1.nextLong() == seeded2.nextLong())
            println(seeded1.nextFloat() == seeded2.nextFloat())

            val r = Random(7)
            val longVal = r.nextLong(10L, 20L)
            val floatVal = r.nextFloat(1.0f, 2.0f)
            println(longVal >= 10L && longVal < 20L)
            println(floatVal >= 1.0f && floatVal < 2.0f)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomOverloadEdgeCases",
            expected:
                """
                true
                true
                true
                true
                """ + "\n"
        )
    }

    // Candidate-only: Random.nextFloat(until) / nextFloat(from, until) (STDLIB-655) are
    // KSwiftK-only extensions with no JVM kotlin-stdlib equivalent (real kotlinc rejects both
    // as "too many arguments for 'fun nextFloat(): Float'"), so this isn't verified via
    // diff_kotlinc.sh. Moved from Scripts/diff_cases/random_nextfloat_range_overloads.kt.
    @Test
    func testCodegenCompilesRandomNextFloatRangeOverloads() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            var okFloatUntil = true
            repeat(100) {
                val f = Random.nextFloat(5.0f)
                if (f < 0.0f || f >= 5.0f) {
                    okFloatUntil = false
                }
            }
            println(okFloatUntil)

            var okFloatRange = true
            repeat(100) {
                val f = Random.nextFloat(1.0f, 10.0f)
                if (f < 1.0f || f >= 10.0f) {
                    okFloatRange = false
                }
            }
            println(okFloatRange)

            val r = Random(7)
            val floatVal = r.nextFloat(1.0f, 2.0f)
            println(floatVal >= 1.0f && floatVal < 2.0f)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomNextFloatRangeOverloads",
            expected:
                """
                true
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomNextDoubleRejectsNaNBounds() throws {
        // KSP-466 review follow-up: nextDouble(from, until) matches upstream's own
        // `checkRangeBounds(from, until) = require(until > from) { ... }` — no
        // explicit isNaN() check exists (or is needed) in either upstream or this
        // port, since IEEE754 comparisons against NaN are always false, so
        // `until > from` already evaluates to false whenever either bound is NaN,
        // and `require` throws IllegalArgumentException same as any other
        // out-of-order bounds. This test locks that behavior in explicitly.
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random(7)

            try {
                r.nextDouble(Double.NaN, 10.0)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }

            try {
                r.nextDouble(0.0, Double.NaN)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomNextDoubleRejectsNaNBounds",
            expected:
                """
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesRandomLongSeedFactory() throws {
        let source = """
        import kotlin.random.Random

        fun makeRandom(seed: Long): Random {
            return Random(seed)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomLongSeedFactory",
                emit: .object,
                outputPath: outputBase
            )
            let objectPath = try #require(ctx.generatedObjectPath)
            #expect(FileManager.default.fileExists(atPath: objectPath))
        }
    }
}
#endif
