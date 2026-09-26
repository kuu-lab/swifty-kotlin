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

    @Test func unqualifiedOuterMemberCallFromAnonymousObjectUsesCapturedOuterInstance() throws {
        try assertKotlinOutput(
            """
            interface Getter<E> {
                fun fetch(index: Int): E
            }
            class ConstGetter(val value: Int) : Getter<Int> {
                override fun fetch(index: Int): Int = value + index
                fun call(): Int {
                    val result = object : Any() {
                        fun compute(): Int = fetch(3)
                    }
                    return result.compute()
                }
            }
            fun main() = println(ConstGetter(7).call())
            """,
            moduleName: "AnonymousObjectOuterReceiverCall",
            expected: "10\n"
        )
    }
}
#endif
