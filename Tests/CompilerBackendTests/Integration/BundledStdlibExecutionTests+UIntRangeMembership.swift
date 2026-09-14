#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    // KSP-1523 (stdlib-pipeline.md §13-4 dual oracle, second leg): UIntRange's
    // property/membership/aggregate members are now bundled Kotlin source
    // (RangeHOF.kt) instead of synthetic Swift stubs. `average()`/`toUIntArray()`
    // were investigated and dropped instead of migrated — neither exists on
    // UIntRange in real Kotlin (see RangeHOF.kt and TODO.md's BUG-255).
    // This exercises the remaining 11 members end to end, including the empty-range
    // shape and the UInt.MAX_VALUE boundary that used to overflow `sum()` through a
    // native Int64 accumulator instead of wrapping at 32 bits.
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
}
#endif
