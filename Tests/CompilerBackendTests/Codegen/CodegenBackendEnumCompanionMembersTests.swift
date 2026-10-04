#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// BUG-180: user-defined members of an enum's companion object were not
/// callable as `EnumClass.member()`.
///
/// Two independent defects were involved:
///
/// 1. `parseEnumBody` checked `isIdentifierLike` before `isDeclarationStart`,
///    and `isIdentifierLike` accepts keywords -- so `companion object { ... }`
///    inside an enum body was parsed as an enum *entry* named `companion`
///    and the companion's members were never collected.
/// 2. `EnumNameAccessLoweringPass.enumClassAncestor` treated any value
///    produced by a call to a symbol nested inside an enum class as an enum
///    ordinal, so `println(EnumClass.f())` for a companion function returning
///    `Int` was rewritten into an ordinal-to-name conversion and printed an
///    entry name instead of the number.

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

    /// Companion properties/functions of an enum, enum-returning companion
    /// functions, and the synthetic `values()`/`entries`/`valueOf` members
    /// must all keep working side by side. A plain `class` companion is
    /// included as the control case.
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

    /// BUG-183: enum entries must be visible without qualification inside the
    /// enum's companion object (e.g. `A` resolves to `D.A`).
    func testCodegenEnumCompanionObjectCanReferenceEntryUnqualified() throws {
        let source = """
        enum class D {
            A, B;
            companion object {
                fun pick(o: Int): D = if (o == 0) A else B
            }
        }

        fun main() {
            println(D.pick(0))
            println(D.pick(1))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumCompanionEntryScope",
            expected: "A\nB\n"
        )
    }
}
#endif
