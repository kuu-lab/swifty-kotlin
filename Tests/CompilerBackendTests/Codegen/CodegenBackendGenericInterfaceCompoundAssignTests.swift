@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendGenericInterfaceCompoundAssignTests {
    @Test
    func testGenericInterfaceCompoundAssignmentDispatchesThroughItable() throws {
        let source = """
        interface Ring<T> {
            operator fun times(other: Ring<T>): Ring<T>
            val value: Int
            val one: Ring<T>
        }

        class MInt(override val value: Int, val m: Int) : Ring<MInt> {
            override fun times(other: Ring<MInt>) = MInt((value * other.value) % m, m)
            override val one: Ring<MInt> get() = MInt(1, m)
        }

        fun <T> Ring<T>.pow(p: Int): Ring<T> {
            var result = one
            repeat(p) { result *= this }
            return result
        }

        fun main() {
            println(MInt(4, 7).pow(3).value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KUU2329GenericInterfaceCompoundAssign",
            expected: "1\n"
        )
    }
}
#endif
