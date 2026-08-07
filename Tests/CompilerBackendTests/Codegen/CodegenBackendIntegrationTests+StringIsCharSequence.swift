@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// BUG-153: Strings built at runtime (concatenation, toString(), buildString)
// are allocated by the flat-string fast paths instead of kk_object_new, so
// they carry no runtime object type ID. kk_op_is's nominalBase case — the one
// an interface target such as CharSequence encodes to — therefore never found
// a source type for them and returned false for every `is CharSequence` /
// `is Comparable<*>` check on a dynamically produced String.
extension CodegenBackendIntegrationTests {
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
