@testable import CompilerCore
import Testing

@Suite
struct ForLoopReceiverValidationTests {
    @Test(arguments: ["X()", "5", "true", "object {}", "null"])
    func rejectsNonIterableReceivers(receiver: String) throws {
        let ctx = makeContextFromSource("""
        class X { val v = 1 }
        fun main() {
            var n = 0
            for (e in \(receiver)) n++
            println(n)
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0172" }, "\(errors)")
    }

    @Test(arguments: ["List<Int>", "String", "IntArray", "Iterator<Int>"])
    func rejectsNullableReceivers(type: String) throws {
        let ctx = makeContextFromSource("""
        fun test(value: \(type)?) {
            for (e in value) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0172" }, "\(errors)")
    }

    @Test
    func rejectsNonOperatorIteratorAndInvalidDestructuringReceiver() throws {
        let ctx = makeContextFromSource("""
        class X {
            fun iterator(): Iterator<Int> = listOf(1).iterator()
        }
        fun test() {
            for (e in X()) {}
            for ((a, b) in 5) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0172" }
        #expect(errors.count == 2, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func acceptsSupportedIterationAndSmartCasts() throws {
        let ctx = makeContextFromSource("""
        class Counter {
            operator fun hasNext(): Boolean = false
            operator fun next(): Int = 1
        }
        class Bag { operator fun iterator(): Counter = Counter() }
        fun test(xs: List<Int>?, sequence: Sequence<Int>, text: CharSequence) {
            for (e in listOf(1, 2)) {}
            for (e in arrayOf(1, 2)) {}
            for (e in intArrayOf(1, 2)) {}
            for (e in "str") {}
            for (e in text) {}
            for (e in 1..3) {}
            for (e in 1 until 3) {}
            for (e in sequence) {}
            for (e in listOf(1).iterator()) {}
            for (e in Bag()) {}
            for ((a, b) in listOf(Pair(1, 2))) {}
            if (xs != null) { for (e in xs) {} }
        }
        fun <T : Iterable<Int>> generic(xs: T) { for (e in xs) {} }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

}
