#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendBooleanSafeXorTests {
    @Test
    func nullableBooleanXorUnboxesReceiverBeforeIntrinsicCall() throws {
        let source = """
        fun main() {
            val t: Boolean? = true
            val f: Boolean? = false
            val n: Boolean? = null
            println(t?.xor(true))
            println(t?.xor(false))
            println(f?.xor(true))
            println(f?.xor(false))
            println(n?.xor(true))
            println(true.xor(true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BooleanSafeXor",
            expected: "false\ntrue\ntrue\nfalse\nnull\nfalse\n"
        )
    }
}
#endif
