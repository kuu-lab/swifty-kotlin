#if canImport(Testing)
import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testGenericUByteRangeMembershipThroughSourceAndArtifact() throws {
        let source = """
        fun <T : UByte> contains(a: T?, b: T?, c: T): Boolean where T : Comparable<UByte> =
            a != null && b != null && c !in a..b

        fun main() {
            println(contains<UByte>(1u, 2u, 0u))
            println(contains<UByte>(1u, 2u, 1u))
            println(contains<UByte>(1u, 2u, 2u))
            println(contains<UByte>(1u, 2u, 3u))
        }
        """
        let expectedOutput = """
        true
        false
        false
        true

        """

        for allowDefaultStdlibLibrary in [false, true] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try compileAndRunKotlin(
                    source,
                    expectedOutput: expectedOutput,
                    moduleName: "GenericUByteRangeMembership",
                    allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
                    optLevel: optLevel
                )
            }
        }
    }

    @Test
    func testUIntRangeMembershipAndAggregatesExecuteThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val empty: UIntRange = 5u..1u
                println(empty.isEmpty())
                println(empty.firstOrNull())
                println(empty.lastOrNull())
                println(empty.sum())
                println(empty.count())
                println(empty.toList())
                println(empty.contains(3u))

                val range: UIntRange = 1u..5u
                println(range.isEmpty())
                println(range.first)
                println(range.last)
                println(range.firstOrNull())
                println(range.lastOrNull())
                println(range.count())
                println(range.sum())
                println(range.toList())
                println(range.contains(3u))
                println(range.contains(10u))
                println(range.reversed().toList())
                println(range.sorted())
                println((5u downTo 1u).sorted())

                val maxR: UIntRange = (UInt.MAX_VALUE - 2u)..UInt.MAX_VALUE
                println(maxR.count())
                println(maxR.last)
                println(maxR.contains(UInt.MAX_VALUE))
                println(maxR.sum())
                println(maxR.toList())
            }
            """,
            expectedOutput: """
            true
            null
            null
            0
            0
            []
            false
            false
            1
            5
            1
            5
            5
            15
            [1, 2, 3, 4, 5]
            true
            false
            [5, 4, 3, 2, 1]
            [1, 2, 3, 4, 5]
            [1, 2, 3, 4, 5]
            3
            4294967295
            true
            4294967290
            [4294967293, 4294967294, 4294967295]

            """,
            moduleName: "UIntRangeMembership"
        )
    }

    @Test
    func testInOperatorOnUnsignedRangesLinksThroughRangeBridge() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(3u in (1u..5u))
                println(7u in (1u..5u))
                println(7u !in (1u..5u))
                println(3uL in (1uL..5uL))
                println(7uL in (1uL..5uL))
                println(7uL !in (1uL..5uL))
                println(3 in (1..5))
                println(7 !in (1..5))
                println('c' in ('a'..'e'))
                println('z' in ('a'..'e'))
            }
            """,
            expectedOutput: """
            true
            false
            true
            true
            false
            true
            true
            true
            true
            false

            """,
            moduleName: "UnsignedRangeInOperator"
        )
    }
}
#endif
