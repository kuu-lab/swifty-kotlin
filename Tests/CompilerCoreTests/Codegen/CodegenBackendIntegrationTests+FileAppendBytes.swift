@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)
    func testCodegenCompilesFileAppendBytes() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_append_bytes_codegen_test.bin"
            val file = File(path)
            file.delete()

            file.appendBytes(byteArrayOf(1, 2, 3))
            val bytes1 = file.readBytes()
            println(bytes1.size)
            for (b in bytes1) println(b)

            file.appendBytes(byteArrayOf(4, 5))
            val bytes2 = file.readBytes()
            println(bytes2.size)
            for (b in bytes2) println(b)

            file.delete()
            file.appendBytes(byteArrayOf(-128, -1))
            val bytes3 = file.readBytes()
            println(bytes3.size)
            for (b in bytes3) println(b)

            file.delete()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FileAppendBytes",
            expected:
                """
                3
                1
                2
                3
                5
                1
                2
                3
                4
                5
                2
                -128
                -1
                """
                + "\n"
        )
    }
}

