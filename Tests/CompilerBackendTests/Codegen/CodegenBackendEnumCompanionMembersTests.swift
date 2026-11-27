#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendEnumCompanionMembersTests {

    @Test
    func testCodegenEnumCompanionFunctionIsCallableViaClassName() throws {
        let source = """
        enum class D { A, B; companion object { fun f(): Int = 1 } }
        fun main() {
            println(D.f())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumCompanionMinimalRepro",
            expected: "1\n"
        )
    }

    @Test
    func testCodegenEnumCompanionMembersAlongsideSyntheticMembers() throws {
        let source = """
        enum class Direction {
            NORTH, SOUTH, EAST, WEST;

            companion object {
                val label: String = "compass"
                fun count(): Int = 4
                fun opposite(direction: Direction): Direction = when (direction) {
                    Direction.NORTH -> Direction.SOUTH
                    Direction.SOUTH -> Direction.NORTH
                    Direction.EAST -> Direction.WEST
                    Direction.WEST -> Direction.EAST
                }
            }
        }

        class Plain { companion object { fun g(): Int = 2 } }

        fun main() {
            println(Plain.g())
            println(Direction.count())
            println(Direction.label)
            println(Direction.opposite(Direction.NORTH))
            println(Direction.NORTH)
            println(Direction.values().size)
            println(Direction.valueOf("SOUTH"))
            println(Direction.entries)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumCompanionMembers",
            expected:
                """
                2
                4
                compass
                SOUTH
                NORTH
                4
                SOUTH
                [NORTH, SOUTH, EAST, WEST]
                """
                + "\n"
        )
    }

}
#endif
