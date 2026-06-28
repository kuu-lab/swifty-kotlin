@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testCPointerToLongNullReturnsZero() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun main() {
            val nullPtr: CPointer<ByteVar>? = null
            println(nullPtr.toLong())
        }
        """

        try assertKotlinOutput(source, moduleName: "CPointerToLongNull", expected: "0\n")
    }

    func testCPointerToLongFunctionWrapperCompilesAndLinks() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun pointerAddress(p: CPointer<ByteVar>?): Long = p.toLong()

        fun main() {
            println(pointerAddress(null))
        }
        """

        try assertKotlinOutput(source, moduleName: "CPointerToLongWrapper", expected: "0\n")
    }

    func testCPointerToLongReturnTypeIsLong() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun main() {
            val nullPtr: CPointer<ByteVar>? = null
            val addr: Long = nullPtr.toLong()
            println(addr == 0L)
        }
        """

        try assertKotlinOutput(source, moduleName: "CPointerToLongReturnType", expected: "true\n")
    }
}

