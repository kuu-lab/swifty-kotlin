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

    /// A reassigned enum-typed `var`'s `.name`/`.ordinal` access must reflect
    /// its current value at each read, not the value it held when first
    /// folded. `d.name`/`d.ordinal` used to be constant-folded against
    /// whichever entry happened to lower the local's *initializer*
    /// expression, because the local's KIR storage was aliased directly to
    /// that expression instead of getting its own copy — so any later
    /// reassignment updated the runtime bits but never changed what the
    /// fold saw, and it kept resolving to the entry the local started with.
    func testEnumNameOrdinalReflectsReassignedVarValue() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            // if-without-else reassignment
            var d1: Direction = Direction.NORTH
            if (1 > 0) { d1 = Direction.SOUTH }
            println(d1.name)
            println(d1.ordinal)

            // if/else reassignment (both branches)
            var d2: Direction = Direction.NORTH
            if (1 > 0) { d2 = Direction.EAST } else { d2 = Direction.WEST }
            println(d2.name)
            println(d2.ordinal)

            // reassignment inside a loop, final value after last iteration
            var d3: Direction = Direction.NORTH
            for (i in 1..3) {
                d3 = if (i % 2 == 0) Direction.SOUTH else Direction.EAST
            }
            println(d3.name)
            println(d3.ordinal)

            // multiple sequential reassignments with no branching
            var d4: Direction = Direction.NORTH
            d4 = Direction.SOUTH
            d4 = Direction.EAST
            d4 = Direction.WEST
            println(d4.name)
            println(d4.ordinal)

            // while-loop reassignment
            var d5: Direction = Direction.NORTH
            var i = 0
            while (i < 2) {
                d5 = Direction.WEST
                i++
            }
            println(d5.name)
            println(d5.ordinal)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumNameOrdinalReassignedVar",
            expected:
                """
                SOUTH
                1
                EAST
                2
                EAST
                2
                WEST
                3
                WEST
                3
                """
                + "\n"
        )
    }
}
