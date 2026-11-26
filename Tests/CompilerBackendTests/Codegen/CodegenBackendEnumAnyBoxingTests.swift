#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendEnumAnyBoxingTests {

    @Test
    func testCodegenEnumConstantWidenedToAnyIsBoxedNotRawOrdinal() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun main() {
            val x: Any = Direction.NORTH
            println(x)
            println(listOf(Direction.NORTH, Direction.SOUTH))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyWideningMinimalRepro",
            expected:
                """
                NORTH
                [NORTH, SOUTH]
                """
                + "\n"
        )
    }

    @Test
    func testCodegenEnumWidenedToAnyIsAsAndKClassIsInstance() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            val boxed: Any = Direction.WEST
            println(boxed is Direction)
            val unboxed = boxed as Direction
            println(unboxed)
            val safe = boxed as? Direction
            if (safe != null) println(safe) else println("null")
            println(Direction::class.isInstance(boxed))
            println(Direction::class.isInstance("not an enum"))
            val wrong: Any = 42
            val wrongSafe = wrong as? Direction
            if (wrongSafe != null) println(wrongSafe) else println("null")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyWideningIsAs",
            expected:
                """
                true
                WEST
                WEST
                true
                false
                null
                """
                + "\n"
        )
    }
}
#endif
