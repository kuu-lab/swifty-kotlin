@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // STDLIB-CINTEROP-FN-029: ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence)
    func testCodegenCinteropByteArrayToKString() throws {
        let source = """
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.toKString

        @OptIn(ExperimentalForeignApi::class)
        fun main() {
            val bytes = "hello".encodeToByteArray()
            println(bytes.toKString())
            println(bytes.toKString(1, 4))
            println(bytes.toKString(0, bytes.size, false))

            val malformed = byteArrayOf((-61).toByte(), 40.toByte())
            println(malformed.toKString().length > 0)
            try {
                println(malformed.toKString(0, 2, true))
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CinteropByteArrayToKString",
            expected:
                """
                hello
                ell
                hello
                true
                caught
                """
                + "\n"
        )
    }
}
