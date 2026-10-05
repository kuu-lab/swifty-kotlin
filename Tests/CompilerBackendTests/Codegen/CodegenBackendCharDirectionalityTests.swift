#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCharDirectionalityTests {

    @Test
    func testCodegenCharDirectionalityNames() throws {
        let source = """
        fun main() {
            println('A'.directionality)
            println('\\u05D0'.directionality)
            println('5'.directionality)
            println(' '.directionality)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "CharDirectionalityNames",
            expected:
                """
                LEFT_TO_RIGHT
                RIGHT_TO_LEFT
                EUROPEAN_NUMBER
                WHITESPACE
                """ + "\n"
        )
    }

    @Test
    func testCodegenCharDirectionalityArabic() throws {
        let source = """
        fun main() {
            println('\\u0627'.directionality)
        }
        """
        try assertKotlinOutput(source, moduleName: "CharDirectionalityArabic", expected: "RIGHT_TO_LEFT_ARABIC\n")
    }

    @Test(arguments: [true, false])
    func testCharDirectionalityEnumAPI(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        fun main() {
            println('a'.directionality)
            println(' '.directionality)
            println(CharDirectionality.UNDEFINED)
            println('a'.directionality.name)
            println('a'.directionality.toString())
            println(CharDirectionality.valueOf("WHITESPACE"))
            println(enumValues<CharDirectionality>().size)
            for (entry in enumValues<CharDirectionality>()) {
                println(entry.name + ":" + entry.ordinal)
                println(CharDirectionality.valueOf(entry.name) == entry)
                println(CharDirectionality.valueOf(entry.name) != entry)
            }
            println('a'.directionality == CharDirectionality.LEFT_TO_RIGHT)
            println('a'.directionality == CharDirectionality.WHITESPACE)
            println('a'.directionality != CharDirectionality.WHITESPACE)
            println(when (' '.directionality) {
                CharDirectionality.WHITESPACE -> "space"
                else -> "other"
            })
        }
        """
        let names = [
            "UNDEFINED", "LEFT_TO_RIGHT", "RIGHT_TO_LEFT", "RIGHT_TO_LEFT_ARABIC",
            "EUROPEAN_NUMBER", "EUROPEAN_NUMBER_SEPARATOR", "EUROPEAN_NUMBER_TERMINATOR",
            "ARABIC_NUMBER", "COMMON_NUMBER_SEPARATOR", "NONSPACING_MARK", "BOUNDARY_NEUTRAL",
            "PARAGRAPH_SEPARATOR", "SEGMENT_SEPARATOR", "WHITESPACE", "OTHER_NEUTRALS",
            "LEFT_TO_RIGHT_EMBEDDING", "LEFT_TO_RIGHT_OVERRIDE", "RIGHT_TO_LEFT_EMBEDDING",
            "RIGHT_TO_LEFT_OVERRIDE", "POP_DIRECTIONAL_FORMAT",
        ]
        let entries = names.enumerated().map { "\($0.element):\($0.offset)\ntrue\nfalse\n" }.joined()
        try assertKotlinOutput(
            source,
            moduleName: "CharDirectionalityEnumAPI",
            expected: "LEFT_TO_RIGHT\nWHITESPACE\nUNDEFINED\nLEFT_TO_RIGHT\nLEFT_TO_RIGHT\nWHITESPACE\n20\n"
                + entries + "true\nfalse\ntrue\nspace\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

}
#endif
