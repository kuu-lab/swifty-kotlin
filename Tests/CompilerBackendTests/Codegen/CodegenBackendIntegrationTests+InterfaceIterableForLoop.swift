#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// BUG-167: `for (x in xs)` over a value statically typed as an iterable
// *interface* (`Iterable<T>`, `Collection<T>`, ...) or as a source class
// implementing `Iterable` bound no `iterator()` in Sema, so lowering fell
// through to the range-iterator intrinsics and reinterpreted the collection
// object as a range, yielding garbage elements.

@Suite
struct CodegenBackendInterfaceIterableForLoopTests {

    @Test
    func testIterableInterfaceForLoopIteration() throws {
        let source = """
        fun f(xs: Iterable<Int>) {
            for (x in xs) {
                println(x)
            }
        }

        fun main() {
            f(listOf(0, 2, 4))
        }
        """
        try assertKotlinOutput(source, moduleName: "IterableInterfaceForLoopIteration", expected: "0\n2\n4\n")
    }

    @Test
    func testIterableInterfaceForLoopElementIsUnboxedPrimitive() throws {
        let source = """
        fun pick(s: String, indices: Iterable<Int>): String {
            val sb = StringBuilder()
            for (i in indices) {
                sb.append(s[i])
            }
            return sb.toString()
        }

        fun main() {
            println(pick("abcdef", listOf(1, 3, 5)))
        }
        """
        try assertKotlinOutput(source, moduleName: "IterableInterfaceForLoopUnboxing", expected: "bdf\n")
    }

    @Test
    func testCollectionInterfaceForLoopIteration() throws {
        let source = """
        fun sum(xs: Collection<Int>): Int {
            var total = 0
            for (x in xs) {
                total += x
            }
            return total
        }

        fun main() {
            println(sum(listOf(1, 2, 3)))
            println(sum(setOf(4, 5)))
        }
        """
        try assertKotlinOutput(source, moduleName: "CollectionInterfaceForLoopIteration", expected: "6\n9\n")
    }

    @Test
    func testIterableInterfaceForLoopContinueAndBreak() throws {
        let source = """
        fun f(xs: Iterable<Int>) {
            for (x in xs) {
                if (x == 2) continue
                if (x == 4) break
                println(x)
            }
        }

        fun main() {
            f(listOf(1, 2, 3, 4, 5))
        }
        """
        try assertKotlinOutput(source, moduleName: "IterableInterfaceForLoopContinueBreak", expected: "1\n3\n")
    }

    @Test
    func testSourceIterableClassForLoopIteration() throws {
        let source = """
        class Counter(val n: Int) : Iterable<Int> {
            override fun iterator(): Iterator<Int> = CounterIterator(n)
        }

        class CounterIterator(val n: Int) : Iterator<Int> {
            var i = 0
            override fun hasNext(): Boolean = i < n
            override fun next(): Int {
                val v = i
                i = i + 1
                return v
            }
        }

        fun main() {
            for (x in Counter(3)) {
                println(x)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "SourceIterableClassForLoopIteration", expected: "0\n1\n2\n")
    }

    @Test
    func testSourceIterableClassForLoopDestructuring() throws {
        let source = """
        class Pairs(val n: Int) : Iterable<Pair<Int, Int>> {
            override fun iterator(): Iterator<Pair<Int, Int>> = PairsIterator(n)
        }

        class PairsIterator(val n: Int) : Iterator<Pair<Int, Int>> {
            var i = 0
            override fun hasNext(): Boolean = i < n
            override fun next(): Pair<Int, Int> {
                val v = i
                i = i + 1
                return Pair(v, v * 2)
            }
        }

        fun main() {
            for ((a, b) in Pairs(3)) {
                println("" + a + ":" + b)
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SourceIterableClassForLoopDestructuring",
            expected: "0:0\n1:2\n2:4\n"
        )
    }

    @Test
    func testIterableInterfaceForLoopDestructuring() throws {
        let source = """
        fun f(ps: Iterable<Pair<Int, String>>) {
            for ((a, b) in ps) {
                println("" + a + b)
            }
        }

        fun main() {
            f(listOf(Pair(1, "a"), Pair(2, "b")))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "IterableInterfaceForLoopDestructuring",
            expected: "1a\n2b\n"
        )
    }

    @Test
    func testIterableInterfaceForLoopLowersToIteratorNotRangeIntrinsics() throws {
        let source = """
        fun f(xs: Iterable<Int>) {
            for (x in xs) {
                println(x)
            }
        }

        fun main() {
            f(listOf(0, 2, 4))
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "f", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("kk_iterator_hasNext"),
            "Iterable for-loop should call kk_iterator_hasNext, got: \(callees)"
        )
        #expect(
            callees.contains("kk_iterator_next"),
            "Iterable for-loop should call kk_iterator_next, got: \(callees)"
        )
        #expect(
            !callees.contains("kk_range_hasNext"),
            "Iterable for-loop must not use kk_range_hasNext, got: \(callees)"
        )
        #expect(
            !callees.contains("kk_range_next"),
            "Iterable for-loop must not use kk_range_next, got: \(callees)"
        )
    }

    @Test
    func testConcreteListForLoopStillUsesListIterator() throws {
        let source = """
        fun main() {
            val xs = listOf(1, 2)
            for (x in xs) {
                println(x)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("kk_list_iterator_next"),
            "List for-loop should keep using kk_list_iterator_next, got: \(callees)"
        )
    }

    @Test
    func testIntRangeForLoopUsesInductionVariablePath() throws {
        let source = """
        fun main() {
            for (i in 0..2) {
                println(i)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(!callees.contains("kk_range_for_in_iterator"), "IntRange induction loop must not allocate a runtime iterator, got: \(callees)")
        #expect(!callees.contains("kk_range_for_in_hasNext"), "IntRange induction loop must not call hasNext, got: \(callees)")
        #expect(!callees.contains("kk_range_for_in_next"), "IntRange induction loop must not call next, got: \(callees)")
        #expect(!callees.contains("__kk_range_first"), "direct IntRange induction loop should not load a range object bound, got: \(callees)")
        #expect(!callees.contains("__kk_range_last"), "direct IntRange induction loop should not load a range object bound, got: \(callees)")
        #expect(callees.contains("__kk_int_range_induction_le"), "IntRange induction loop should compare bounds, got: \(callees)")
    }
}
#endif
