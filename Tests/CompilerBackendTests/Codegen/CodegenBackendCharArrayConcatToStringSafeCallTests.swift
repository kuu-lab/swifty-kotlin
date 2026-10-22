#if canImport(Testing)
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCharArrayConcatToStringSafeCallTests {

    @Test
    func testCodegenNullableCharArrayConcatToStringThroughSafeCall() throws {
        let source = """
        fun main() {
            val chars: CharArray? = charArrayOf('h', 'i')
            val missing: CharArray? = null
            println(chars?.concatToString())
            println(missing?.concatToString())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharArrayConcatToStringSafeCall",
            expected: "hi\nnull\n"
        )
    }
}
#endif
