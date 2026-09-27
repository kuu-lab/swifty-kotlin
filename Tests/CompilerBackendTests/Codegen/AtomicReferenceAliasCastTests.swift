@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct AtomicReferenceAliasCastTests {
    @Test
    func aliasCastPreservesReferenceAndLiteralCASIdentity() throws {
        try assertKotlinOutput("""
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference
        import kotlin.concurrent.compareAndSet
        class RefBox(val text: String)
        fun main() {
            val atomic = AtomicReference(RefBox("box"))
            val ref = atomic as kotlin.concurrent.AtomicReference<RefBox>
            println(ref.load().text)
            println(ref === atomic)
            val text = AtomicReference("initial") as kotlin.concurrent.AtomicReference<String>
            println(text.compareAndSet("initial", "updated"))
            println(text.load())
        }
        """, moduleName: "AtomicReferenceAliasCast", expected: "box\ntrue\ntrue\nupdated\n")
    }
}
