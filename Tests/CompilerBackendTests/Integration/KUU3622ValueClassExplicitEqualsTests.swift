@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3622ValueClassExplicitEqualsTests {
    @Test(arguments: [0, 2])
    func longBackedValueClassExplicitEqualsMatchesItsPayload(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            value class FL(val x: Long)
            value class FI(val x: Int)

            fun main() {
                println(FL(42L).equals(FL(42L)))
                println(FL(42L).equals(FL(43L)))
                println(FI(42).equals(FI(42)))
                println(FL(42L) == FL(42L))
                val nullable: FL? = FL(42L)
                println(nullable?.equals(FL(42L)))
            }
            """,
            expectedOutput: "true\nfalse\ntrue\ntrue\ntrue\n",
            moduleName: "KUU3622ValueClassExplicitEquals",
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
