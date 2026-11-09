#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendStringEncodingAndStringBuilderTests {

    // TEST-TEXT-021: String encoding, byte array decoding, and StringBuilder clear pure Kotlin operations
    @Test
    func testCodegenStringPureKotlinEncodingAndStringBuilderOperations() throws {
        let source = """
        fun main() {
            val text = "Hello, Kotlin!"
            val bytes = text.toByteArray()
            println(bytes.size)
            val bytes2 = text.encodeToByteArray()
            println(bytes2.size)

            val decoded1 = bytes.decodeToString()
            println(decoded1)
            val decoded2 = bytes.decodeToString(7, 13)
            println(decoded2)

            val strFromBytes = String(bytes)
            println(strFromBytes)

            val sb = StringBuilder("abc")
            println(sb.toString())
            sb.clear()
            println(sb.length)
            sb.append("def")
            println(sb.toString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "PureKotlinEncodingAndStringBuilder",
            expected:
                """
                14
                14
                Hello, Kotlin!
                Kotlin
                Hello, Kotlin!
                abc
                0
                def
                """
                + "\n"
        )
    }
}
#endif
