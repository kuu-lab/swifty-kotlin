#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendEnumAnyTypeChecksTests {

    @Test
    func testCodegenEnumWidenedToAnyAnswersTypeChecks() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            val boxed: Any = Direction.WEST
            println(boxed is Direction)
            println(boxed is Enum<*>)
            println(boxed is Comparable<*>)
            println(boxed !is Direction)
            println(boxed as Direction)
            println(boxed as? Direction)
            println(Direction::class.isInstance(boxed))

            val other: Any = 42
            println(other is Direction)
            println(other as? Direction)
            println(Direction::class.isInstance(other))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyTypeChecksMinimal",
            expected:
                """
                true
                true
                true
                false
                WEST
                WEST
                true
                false
                null
                false
                """
                + "\n"
        )
    }

    @Test
    func testCodegenMixedEnumClassesInAnyCollectionFilterCorrectly() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        enum class Color { RED, GREEN }

        fun main() {
            val mixed: List<Any> = listOf(Direction.NORTH, Color.RED, Direction.SOUTH, Color.GREEN)
            println(mixed.filterIsInstance<Direction>())
            println(mixed.filterIsInstance<Color>())
            println(mixed.filterIsInstance<Enum<*>>().size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyFilterIsInstance",
            expected:
                """
                [NORTH, SOUTH]
                [RED, GREEN]
                4
                """
                + "\n"
        )
    }

    @Test
    func testCodegenStaticallyTypedEnumAnswersTypeChecks() throws {
        let source = try diffCaseSource("bug225_enum_type_checks.kt")

        try assertKotlinOutput(
            source,
            moduleName: "EnumStaticTypeChecks",
            expected:
                """
                true
                true
                true
                true
                enum-yes
                label-yes
                BRONZE
                SILVER
                GOLD
                BRONZE
                """
                + "\n",
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
