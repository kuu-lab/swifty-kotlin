#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendEnumEdgeCoverageTests {

    @Test
    func testEnumEntryBodyImplicitNameUsesCurrentEntry() throws {
        let source = """
        enum class E {
            A {
                override fun describe(): String = "base-" + name
            };
            abstract fun describe(): String
        }

        fun main() { println(E.A.describe()) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntryBodyImplicitName",
            expected: "base-A\n"
        )
    }

    @Test
    func testCodegenEnumCollectionHOFUnboxesConstructorPropertyReceiver() throws {
        let source = """
        enum class Color(val rgb: Int) {
            RED(0xFF0000),
            GREEN(0x00FF00),
            BLUE(0x0000FF),
        }

        fun main() {
            println(Color.entries.find { it.rgb == 0xFF0000 })
            println(Color.values().find { it.rgb == 0x00FF00 })
            println(Color.entries.find { it.rgb == 123456 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumCollectionHOFConstructorProperty",
            expected:
                """
                RED
                GREEN
                null
                """
                + "\n"
        )
    }

    @Test
    func testCodegenEnumEntriesIndexedAccessReturnsRealSingleton() throws {
        let source = """
        import kotlin.enums.enumEntries

        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            println(Direction.entries[0])
            println(Direction.entries[3])
            println(enumEntries<Direction>()[1])
            println(Direction.entries[0] == Direction.NORTH)
            println(Direction.entries[1] == Direction.SOUTH)
            println(Direction.entries[0] == Direction.SOUTH)
            println(enumValues<Direction>()[2] == Direction.EAST)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntriesIndexedAccess",
            expected:
                """
                NORTH
                WEST
                SOUTH
                true
                true
                false
                true
                """
                + "\n"
        )
    }

    @Test
    func testFullyQualifiedEnumValuesAndEntriesCalls() throws {
        let source = """
        enum class Color { RED, GREEN, BLUE }
        fun main() {
            println(kotlin.enumValues<Color>().size)
            println(kotlin.enums.enumEntries<Color>().size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FullyQualifiedEnumValuesAndEntries",
            expected: "3\n3\n"
        )
    }

    @Test
    func testForInOverEnumValuesReadsConstructorProperty() throws {
        let source = """
        enum class Dogs(val id: String) {
            BULLDOG("bulldog"), TERRIER("terrier"), HOUND("hound"), MASTIFF("mastiff")
        }

        fun main() {
            for (value in Dogs.values())
                println("${value.name} -> ${value.id}")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumValuesForInConstructorProperty",
            expected: "BULLDOG -> bulldog\nTERRIER -> terrier\nHOUND -> hound\nMASTIFF -> mastiff\n"
        )
    }
}
#endif
