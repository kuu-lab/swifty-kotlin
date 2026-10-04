#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendStringIsCharSequenceTests {

    @Test
    func testCodegenRuntimeBuiltStringIsCharSequence() throws {
        let source = """
        fun main() {
            val concatenated = "he" + "llo"
            println(concatenated is CharSequence)
            println(StringBuilder("x").toString() is CharSequence)
            println(buildString { append("y") } is CharSequence)
            val erased: Any = concatenated
            println(erased is CharSequence)
            println(concatenated is Comparable<*>)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RuntimeBuiltStringIsCharSequence",
            expected:
                """
                true
                true
                true
                true
                true
                """
                + "\n"
        )
    }

    @Test
    func testCodegenRuntimeBuiltStringIsNotUnrelatedNominalType() throws {
        let source = """
        interface Marker

        class Impl : Marker

        fun main() {
            val concatenated = "he" + "llo"
            println(concatenated is Marker)
            println(concatenated is List<*>)
            println(Impl() is CharSequence)
            println(1 is CharSequence)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RuntimeBuiltStringIsNotUnrelatedNominalType",
            expected:
                """
                false
                false
                false
                false
                """
                + "\n"
        )
    }

    @Test
    func testCodegenRuntimeBuiltStringCastToCharSequence() throws {
        let source = """
        fun main() {
            val concatenated = "he" + "llo"
            println((concatenated as CharSequence) === concatenated)
            println((concatenated as? CharSequence) != null)
            println((42 as? CharSequence) == null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RuntimeBuiltStringCastToCharSequence",
            expected:
                """
                true
                true
                true
                """
                + "\n"
        )
    }
}
#endif
