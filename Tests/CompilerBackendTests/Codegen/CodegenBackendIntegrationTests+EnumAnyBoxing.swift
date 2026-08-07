@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// BUG-179: an enum constant widened straight to `Any` (or any other
/// reference-typed boundary erased at runtime -- collection literals,
/// function parameters/return types, data class fields, vararg elements)
/// leaked as its raw ordinal `Int` instead of being boxed, because
/// `resolveValueClassKind` (`ABILoweringPass+BoxingRules.swift`) only ever
/// resolved *value classes* to their underlying primitive kind -- an enum
/// class's `.classType` kind never matched `BoxingCalleeTable`'s
/// primitive-only lookup, so every boxing-callee lookup silently returned
/// `nil` and no boxing call was ever emitted. Fixed by teaching
/// `resolveValueClassKind` to also resolve non-null enum classes to `Int`,
/// and teaching `emitBoxCallWithValueClassTag`
/// (`Sources/CompilerCore/KIR/KIRCallEmissionHelpers.swift`) to box an enum
/// value via `kk_enum_box_ordinal` (BUG-177) instead of a plain `kk_box_int`,
/// tagging it with its declared name via the class's
/// `$enumOrdinalToName$<id>` helper so the generic Any-printing path can
/// still render it once the static enum type is erased.
extension CodegenBackendIntegrationTests {
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

    /// Broader coverage across every Any-erased boundary an enum value can
    /// flow through: local var widening, function argument/return widening,
    /// data class field widening (constructor argument boxing), mixed enum
    /// classes sharing one Any-erased collection (the `$enumOrdinalToName$<id>`
    /// helper name must stay unique per class so codegen's by-name resolution
    /// doesn't collide), `MutableList<Any>.add`, `Pair`, `sequenceOf`, and
    /// nullable `Any?`. Also pins that direct (non-Any) enum `==`/`when` and
    /// nullable enum handling are unaffected.
    func testCodegenEnumConstantWidenedToAnyAcrossAllBoundaries() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }
        enum class Color { RED, GREEN, BLUE }

        fun takesAny(x: Any): Any = x

        fun returnsAny(): Any = Direction.EAST

        data class Wrapper(val value: Any)

        fun main() {
            val x: Any = Direction.NORTH
            println(x)

            println(listOf(Direction.NORTH, Direction.SOUTH))

            println(takesAny(Direction.WEST))

            println(returnsAny())

            val w = Wrapper(Direction.SOUTH)
            println(w.value)
            println(w)

            val mixed: List<Any> = listOf(Direction.NORTH, Color.RED, Direction.SOUTH, Color.BLUE)
            println(mixed)

            val ml = mutableListOf<Any>()
            ml.add(Direction.EAST)
            ml.add(Color.GREEN)
            println(ml)

            val nx: Any? = Direction.SOUTH
            println(nx)

            val p = Pair(Direction.NORTH, "hello")
            println(p)

            println(sequenceOf(Direction.NORTH, Direction.SOUTH).toList())

            val d = Direction.NORTH
            println(d == Direction.NORTH)
            when (d) {
                Direction.NORTH -> println("is north")
                else -> println("not north")
            }
            val nd: Direction? = Direction.EAST
            println(nd)
            println(nd == Direction.EAST)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyWideningAllBoundaries",
            expected:
                """
                NORTH
                [NORTH, SOUTH]
                WEST
                EAST
                SOUTH
                Wrapper(value=SOUTH)
                [NORTH, RED, SOUTH, BLUE]
                [EAST, GREEN]
                SOUTH
                (NORTH, hello)
                [NORTH, SOUTH]
                true
                is north
                EAST
                true
                """
                + "\n"
        )
    }
}
