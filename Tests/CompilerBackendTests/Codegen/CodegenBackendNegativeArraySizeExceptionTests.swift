#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendNegativeArraySizeExceptionTests {

    @Test
    func testCodegenByteArrayWithInitThrowsNegativeArraySizeExceptionForNegativeSize() throws {
        let source = """
        fun main() {
            try {
                val a = ByteArray(-1) { 0 }
                println("no throw, size=${a.size}")
            } catch (e: NegativeArraySizeException) {
                println("threw: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ByteArrayNegativeSize", expected: "threw: -1\n")
    }

    @Test
    func testCodegenByteArrayWithInitNegativeSizeIsCatchableAsGenericException() throws {
        let source = """
        fun main() {
            try {
                val a = ByteArray(-1) { 0 }
                println("no throw, size=${a.size}")
            } catch (e: Exception) {
                println("threw: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ByteArrayNegativeSizeGenericCatch", expected: "threw: -1\n")
    }

    @Test
    func testCodegenSiblingSizedArrayConstructorsThrowNegativeArraySizeException() throws {
        let source = """
        fun main() {
            try {
                IntArray(-2) { it }
                println("no throw")
            } catch (e: NegativeArraySizeException) {
                println("int: ${e.message}")
            }

            try {
                Array(-3) { "x" }
                println("no throw")
            } catch (e: NegativeArraySizeException) {
                println("generic: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SiblingArrayConstructorsNegativeSize",
            expected: "int: -2\ngeneric: -3\n"
        )
    }

    @Test
    func testCodegenByteArrayWithInitPositiveSizeStillWorks() throws {
        let source = """
        fun main() {
            val a = ByteArray(3) { it.toByte() }
            println(a.joinToString())
        }
        """

        try assertKotlinOutput(source, moduleName: "ByteArrayPositiveSizeRegression", expected: "0, 1, 2\n")
    }
}
#endif
