@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesEnumEdgeCoverage() throws {
        let source = """
        enum class Direction {
            NORTH,
            SOUTH,
        }

        fun main() {
            println(Direction.entries)
            println(enumValues<Direction>().toList())
            println(enumValueOf<Direction>("NORTH"))
            println(Direction.SOUTH.name)
            println(Direction.SOUTH.ordinal)

            try {
                println(enumValueOf<Direction>("WEST"))
            } catch (e: Throwable) {
                println("invalid-enum-name")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEdgeCoverage",
            expected:
                """
                [NORTH, SOUTH]
                [NORTH, SOUTH]
                NORTH
                SOUTH
                1
                invalid-enum-name
                """
                + "\n"
        )
    }

    /// BUG-172: `values()`/`entries` stored each element as a pre-baked name
    /// string instead of a genuinely boxed ordinal (see
    /// `appendEnumOrdinalArrayCreation` /
    /// `CallLowerer+EnumStdlib.lowerEnumEntryCollectionCallExpr`). Printing an
    /// *individual* element read out of the collection unboxed that string as
    /// an Int (garbage, matching no ordinal) and printed a blank line;
    /// comparing it against a real enum constant compared an unrelated boxed
    /// handle against a raw ordinal and was always false. Printing the whole
    /// collection happened to look right regardless, since the elements were
    /// already name strings -- this test pins that this remains true now
    /// that elements are real boxed ordinals tagged with their name (see
    /// `kk_enum_box_ordinal` / `RuntimeIntBox.enumEntryName`).
    func testCodegenEnumValuesEntriesElementAccessEqualityAndWhen() throws {
        let source = """
        enum class Direction {
            NORTH,
            SOUTH,
        }

        fun main() {
            enumValues<Direction>().forEach { d -> println(d) }
            for (d in Direction.entries) {
                println(d)
            }
            println(enumValues<Direction>().toList())
            println(Direction.entries)

            val first = enumValues<Direction>()[0]
            val second = enumValues<Direction>()[1]
            println(first == Direction.NORTH)
            println(first == Direction.SOUTH)
            println(second == Direction.SOUTH)
            when (first) {
                Direction.NORTH -> println("first-is-north")
                Direction.SOUTH -> println("first-is-south")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumValuesEntriesElementAccess",
            expected:
                """
                NORTH
                SOUTH
                NORTH
                SOUTH
                [NORTH, SOUTH]
                [NORTH, SOUTH]
                true
                false
                true
                first-is-north
                """
                + "\n"
        )
    }
}

