#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendEnumEntriesIndexAccessTests {

    @Test
    func testCodegenEnumEntriesIndexAccessMinimalRepro() throws {
        let source = """
        import kotlin.enums.enumEntries

        enum class Direction { NORTH, SOUTH }
        fun main() {
            println(enumEntries<Direction>()[0])
        }
        """

        try assertKotlinOutput(source, moduleName: "EnumEntriesIndexMinimalRepro", expected: "NORTH\n")
    }

    @Test
    func testCodegenEnumEntriesIndexAccessAcrossReceiverShapes() throws {
        let source = """
        import kotlin.enums.EnumEntries

        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            println(Direction.entries[1])
            println(Direction.entries.get(2))
            val entries: EnumEntries<Direction> = Direction.entries
            for (i in entries.indices) {
                println(entries[i])
            }
            println(entries[0] == Direction.NORTH)
            println(enumValues<Direction>()[2] == Direction.entries[2])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntriesIndexReceiverShapes",
            expected: """
            SOUTH
            EAST
            NORTH
            SOUTH
            EAST
            WEST
            true
            true

            """
        )
    }
}
#endif
