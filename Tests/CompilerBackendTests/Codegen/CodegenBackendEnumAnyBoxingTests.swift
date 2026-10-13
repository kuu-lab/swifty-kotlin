#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

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

    /// BUG-182: an enum constant widened to `Any` must still answer
    /// `is`/`as`/`as?`/`KClass.isInstance` for its declared enum class.
    /// Previously `kk_enum_box_ordinal` produced a `RuntimeIntBox` with no
    /// nominal type tag, so `kk_op_is` treated every boxed enum as an
    /// unrelated object and `as`/`as?` threw or returned `null`.
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
