@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct AtomicReferenceAliasCastTests {
    @Test
    func dynamicStringCASRequiresReferenceIdentity() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.AtomicReference
        import kotlin.concurrent.atomics.AtomicArray
        fun main() {
            val first = charArrayOf('s', 'a', 'm', 'e').concatToString()
            val second = charArrayOf('s', 'a', 'm', 'e').concatToString()
            val atomic = AtomicReference(first)
            println(atomic.compareAndSet(second, "wrong"))
            println(atomic.compareAndExchange(second, "wrong") === first)
            println(atomic.load() === first)
            println(atomic.compareAndSet(atomic.load(), "correct"))
            println(atomic.load())
            val array = AtomicArray(arrayOf(first))
            println(array.compareAndSetAt(0, second, "wrong"))
            println(array.compareAndExchangeAt(0, second, "wrong") === first)
            println(array.loadAt(0) === first)
            println(array.compareAndSetAt(0, array.loadAt(0), "correct"))
            println(array.loadAt(0))
        }
        """
        let expected = "false\ntrue\ntrue\ntrue\ncorrect\nfalse\ntrue\ntrue\ntrue\ncorrect\n"
        for useArtifact in [false, true] {
            try assertKotlinOutput(
                source,
                moduleName: "AtomicDynamicStringIdentity",
                expected: expected,
                allowDefaultStdlibLibrary: useArtifact
            )
        }
    }

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
