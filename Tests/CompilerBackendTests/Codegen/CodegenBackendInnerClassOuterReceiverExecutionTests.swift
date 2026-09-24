#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendInnerClassOuterReceiverExecutionTests {
    @Test func unqualifiedOuterMemberCallUsesCapturedOuterInstance() throws {
        try assertKotlinOutput(
            """
            class Outer(val value: Int) {
                fun fetch(index: Int): Int = value + index
                inner class Inner {
                    fun compute(): Int = fetch(1)
                }
            }
            fun main() = println(Outer(7).Inner().compute())
            """,
            moduleName: "InnerClassOuterReceiverCall",
            expected: "8\n"
        )
    }
}
#endif
