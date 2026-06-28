@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCharPredicateHelpersMatchExpectedOutput() throws {
        let source = """
        fun main() {
            println('A'.isLetter())
            println('1'.isDigit())
            println(' '.isWhitespace())
            println('7'.isLetterOrDigit())
        }
        """

        try assertKotlinOutput(source, moduleName: "CharPredicatesRuntime", expected: "true\ntrue\ntrue\ntrue\n")
    }

    // STDLIB-TEXT-PROP-008: Char.isIdentifierIgnorable end-to-end execution test
    func testCodegenCharIsIdentifierIgnorableMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\u00AD'.isIdentifierIgnorable())
            println('A'.isIdentifierIgnorable())
        }
        """

        try assertKotlinOutput(source, moduleName: "CharIsIdentifierIgnorableRuntime", expected: "true\nfalse\n")
    }

    func testCodegenCharIsSurrogateMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\uD800'.isSurrogate())
            println('\\uDFFF'.isSurrogate())
            println('A'.isSurrogate())
        }
        """
        try assertKotlinOutput(source, moduleName: "CharIsSurrogateRuntime", expected: "true\ntrue\nfalse\n")
    }

    // STDLIB-TEXT-PROP-016: Char.isTitleCase end-to-end execution test
    func testCodegenCharIsTitleCaseMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\u01C5'.isTitleCase())
            println('A'.isTitleCase())
        }
        """

        try assertKotlinOutput(source, moduleName: "CharIsTitleCaseRuntime", expected: "true\nfalse\n")
    }

    func testCodegenCharCaseConversionHelpersHandleUnicodeMappings() throws {
        let source = """
        fun main() {
            println('ß'.uppercase())
            println('ǆ'.titlecase())
            println('İ'.lowercase())
        }
        """

        try assertKotlinOutput(source, moduleName: "CharCaseConversionRuntime", expected: "SS\nǅ\ni̇\n")
    }
}

