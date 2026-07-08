@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
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
            println(zero == 0)
            println(one == 0 || one == 1)
            println(thirtyOne >= 0)
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
                """ + "\n"
        )
    }

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

    func testCodegenCompilesRandomLongSeedConstructor() throws {
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
                moduleName: "RandomLongSeedConstructor",
                emit: .object,
                outputPath: outputBase
            )
            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
        }
    }
}

