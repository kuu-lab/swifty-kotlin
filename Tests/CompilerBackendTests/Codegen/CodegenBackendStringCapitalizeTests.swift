@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite struct CodegenBackendStringCapitalizeTests {

    @Test func testCodegenStringCapitalizeTitlecasesFirstChar() throws {
        let source = """
        fun main() {
            println("hello".capitalize())
            println("world".capitalize())
            println("abc def".capitalize())
        }
        """

        try assertKotlinOutput(source, moduleName: "StringCapitalize", expected: "Hello\nWorld\nAbc def\n")
    }

    @Test func testCodegenStringCapitalizeUsesDigraphTitlecase() throws {
        let source = """
        fun main() {
            println("ǆenan".capitalize())
            println("ǉubǉana".capitalize())
            println("ǌegoš".capitalize())
            println("ǳuro".capitalize())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringCapitalizeDigraphs",
            expected: "ǅenan\nǈubǉana\nǋegoš\nǲuro\n"
        )
    }

    @Test func testCodegenStringCapitalizePreservesNonLowercaseFirstChar() throws {
        let source = """
        fun main() {
            println("ǅenan".capitalize())
            println("Ǆenan".capitalize())
            println("ᾈbc".capitalize())
            println("1abc".capitalize())
            println("😀abc".capitalize())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringCapitalizeUnchanged",
            expected: "ǅenan\nǄenan\nᾈbc\n1abc\n😀abc\n"
        )
    }

    @Test func testCodegenStringCapitalizePreservesUppercaseExpansions() throws {
        let source = """
        fun main() {
            println("ßeta".capitalize())
            println("ﬃle".capitalize())
            println("ᾀbc".capitalize())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringCapitalizeExpansions",
            expected: "SSeta\nFFIle\nἈΙbc\n"
        )
    }

    @Test func testCodegenStringCapitalizeHandlesEdgeCases() throws {
        let source = """
        fun main() {
            println("".capitalize())
            println("Hello".capitalize())
            println("A".capitalize())
        }
        """

        try assertKotlinOutput(source, moduleName: "StringCapitalizeEdgeCases", expected: "\nHello\nA\n")
    }
}
#endif
