#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendCharSequenceMemberAccessTests {

    @Test
    func testCodegenCharSequenceGetSupportsStringAndStringBuilder() throws {
        let source = """
        fun main() {
            val stringValue: CharSequence = "abc"
            val builderValue: CharSequence = StringBuilder("xyz")
            println(stringValue.get(1))
            println(stringValue[2])
            println(builderValue.get(1))
            println(builderValue[2])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharSequenceMemberAccess",
            expected:
                """
                b
                c
                y
                z
                """
                + "\n"
        )
    }
}
#endif
