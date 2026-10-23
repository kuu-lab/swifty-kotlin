#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Testing

@Suite
struct CodegenBackendAnyReceiverArrayExtensionOverloadTests {
    @Test
    func anyReceiverArrayTypeCheckMatchesKotlin() throws {
        let source = """
        fun <T> Array<T>.getLength(): Int = size
        fun Any.getLength(): Int = if (this is Array<*>) size else -1

        fun box(): String {
            val array1: Array<String> = arrayOf("1", "2", "3")
            val array2: Any = arrayOf("1", "2", "3")
            if (array1.getLength() + array2.getLength() != 6) return "FAILURE"
            if ((42 as Any).getLength() != -1) return "FAILURE"
            return "OK"
        }

        fun main() {
            println(box())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AnyReceiverArrayExtensionOverload",
            expected: "OK\n"
        )
    }
}
#endif
