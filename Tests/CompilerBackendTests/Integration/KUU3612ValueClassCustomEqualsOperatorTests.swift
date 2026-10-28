@testable import CompilerCore
import Testing

@Suite(.serialized)
struct KUU3612ValueClassCustomEqualsOperatorTests {
    @Test(arguments: [0, 2])
    func customEqualsWorksWithEqualityOperators(optimization: Int) throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("RESERVED_MEMBER_INSIDE_VALUE_CLASS")
            @JvmInline
            value class Z(val data: Int) {
                override fun equals(other: Any?): Boolean =
                    other is Z && data % 256 == other.data % 256
            }

            fun main() {
                println(Z(0) != Z(256))
                println(Z(0) == Z(0))
            }
            """,
            expectedOutput: "false\ntrue\n",
            moduleName: "KUU3612ValueClassCustomEqualsOperator",
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
