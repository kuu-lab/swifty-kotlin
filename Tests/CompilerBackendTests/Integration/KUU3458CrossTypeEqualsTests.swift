@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3458CrossTypeEqualsTests {
    @Test(arguments: [0, 2])
    func primitiveEqualsRequiresMatchingRuntimeTypes(optimization: Int) throws {
        TestStdlibCache.shared.prepare()

        try compileAndRunKotlin(
            """
            fun main() {
                println(1.equals(1L))
                println(1L.equals(1))
                println(1.equals('1'))
                println('1'.equals(49))
                println(1.0.equals(1L))
                println(1.toByte().equals(1))
                println(1.toShort().equals(1))
                println(1u.equals(1))
                println(1.equals(1))
                println(1L.equals(1L))
                println('1'.equals('1'))
                println(1.0.equals(1.0))
            }
            """,
            expectedOutput: "false\nfalse\nfalse\nfalse\nfalse\nfalse\nfalse\nfalse\ntrue\ntrue\ntrue\ntrue\n",
            moduleName: "KUU3458CrossTypeEquals",
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
