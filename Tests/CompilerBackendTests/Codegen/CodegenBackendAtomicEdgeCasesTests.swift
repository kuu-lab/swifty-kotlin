#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendAtomicEdgeCasesTests {

    @Test
    func testCodegenCompilesAtomicEdgeCases() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicReference

        data class Token(val value: String)

        fun main() {
            val initial = Token("a")
            val updated = Token("b")
            val ref = AtomicReference(initial)
            println(ref.load().value)
            println(ref.compareAndSet(Token("x"), updated))
            println(ref.compareAndSet(initial, updated))
            println(ref.exchange(Token("c")).value)
            println(ref.load().value)

            val count = AtomicInt(1)
            println(count.load())
            println(count.addAndFetch(4))
            println(count.fetchAndAdd(3))
            println(count.compareAndExchange(8, 10))
            println(count.compareAndExchange(9, 10))
            println(count.load())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AtomicEdgeCases",
            expected:
                """
                a
                false
                true
                b
                c
                1
                5
                5
                8
                10
                10
                """ + "\n"
        )
    }
}
#endif
