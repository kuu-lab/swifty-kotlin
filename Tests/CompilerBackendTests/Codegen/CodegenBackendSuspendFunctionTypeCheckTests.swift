#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSuspendFunctionTypeCheckTests {
    @Test
    func testIsAndCastsCheckSuspendMarkerAndFunctionArity() throws {
        let source = """
        @Suppress("CANNOT_CHECK_FOR_ERASED")
        fun main() {
            val suspendedZero: suspend () -> Int = { 5 }
            val plainZero: () -> Int = { 6 }
            val suspendedOne: suspend (Int) -> Int = { it + 1 }
            val erasedSuspended: Any = suspendedZero
            val erasedPlain: Any = plainZero
            val erasedWrongArity: Any = suspendedOne

            println(erasedSuspended is suspend () -> Int)
            println(erasedPlain is suspend () -> Int)
            println(erasedWrongArity is suspend () -> Int)
            println((erasedSuspended as? suspend () -> Int) != null)
            println((erasedPlain as? suspend () -> Int) == null)
            println((erasedSuspended as? () -> Int) == null)
            println((erasedPlain as? () -> Int) != null)
            println((erasedSuspended as? Function1<*, *>) != null)

            try {
                val invalid: suspend () -> Int = erasedPlain as suspend () -> Int
                println("unexpected cast: " + invalid)
            } catch (error: ClassCastException) {
                println("caught cast")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SuspendFunctionTypeChecks",
            expected:
                """
                true
                false
                false
                true
                true
                true
                true
                true
                caught cast
                """
                + "\n"
        )
    }
}
#endif
