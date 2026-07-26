#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testBuildKIRUsesCustomContainerOperatorsForIndexedContainsAndRangeTo() throws {
        let source = """
        class Bucket(private val values: MutableList<Int>) {
            operator fun get(index: Int): Int = values[index]
            operator fun set(index: Int, value: Int) { values[index] = value }
            operator fun contains(value: Int): Boolean = values.any { it == value }
            operator fun rangeTo(other: Bucket): Int = values.size + other.values.size
        }

        fun use(box: Bucket, other: Bucket): Int {
            val value = box[0]
            box[0] = value + 1
            return if (1 in box) box..other else 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("get"), "Expected custom get call, got: \(callees)")
            #expect(callees.contains("set"), "Expected custom set call, got: \(callees)")
            #expect(callees.contains("contains"), "Expected custom contains call, got: \(callees)")
            #expect(callees.contains("rangeTo"), "Expected custom rangeTo call, got: \(callees)")
            #expect(!(callees.contains("kk_op_rangeTo")), "Custom rangeTo should not lower to kk_op_rangeTo, got: \(callees)")
        }
    }

    @Test func testBuildKIRUsesCustomIteratorOperatorsInForLoops() throws {
        let source = """
        class Entry(val first: Int, val second: Int) {
            operator fun component1(): Int = first
            operator fun component2(): Int = second
        }

        class EntryIterator(private val values: MutableList<Entry>) {
            private var index = 0
            operator fun hasNext(): Boolean = index < values.size
            operator fun next(): Entry = values[index++]
        }

        class EntryBag(private val values: MutableList<Entry>) {
            operator fun iterator(): EntryIterator = EntryIterator(values)
        }

        fun sumAll(bag: EntryBag): Int {
            var sum = 0
            for ((a, b) in bag) {
                sum += a + b
            }
            return sum
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("iterator"), "Expected custom iterator call, got: \(callees)")
            #expect(callees.contains("hasNext"), "Expected custom hasNext call, got: \(callees)")
            #expect(callees.contains("next"), "Expected custom next call, got: \(callees)")
            #expect(callees.contains("component1"), "Expected destructuring component1 call, got: \(callees)")
            #expect(callees.contains("component2"), "Expected destructuring component2 call, got: \(callees)")
            #expect(!(callees.contains("kk_range_iterator")), "Custom iterator loop should not use kk_range_iterator, got: \(callees)")
            #expect(!(callees.contains("kk_range_hasNext")), "Custom iterator loop should not use kk_range_hasNext, got: \(callees)")
            #expect(!(callees.contains("kk_range_next")), "Custom iterator loop should not use kk_range_next, got: \(callees)")
        }
    }

    // BUG-013 / KSP-CAP-002: user-defined Iterator/Iterable should drive for-in
    // lowering without silently falling back to range intrinsics.
    @Test func testBuildKIRUsesUserIteratorSubtypeDirectly() throws {
        let source = """
        class Counter(private val limit: Int) : Iterator<Int> {
            private var count = 0
            override operator fun hasNext(): Boolean = count < limit
            override operator fun next(): Int {
                val r = count
                count++
                return r
            }
        }

        fun sumAll(): Int {
            var sum = 0
            for (i in Counter(3)) { sum += i }
            return sum
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("hasNext"), "Expected direct hasNext call, got: \(callees)")
            #expect(callees.contains("next"), "Expected direct next call, got: \(callees)")
            #expect(!(callees.contains("kk_range_iterator")), "User Iterator loop should not use kk_range_iterator, got: \(callees)")
            #expect(!(callees.contains("kk_range_hasNext")), "User Iterator loop should not use kk_range_hasNext, got: \(callees)")
            #expect(!(callees.contains("kk_range_next")), "User Iterator loop should not use kk_range_next, got: \(callees)")
        }
    }

    @Test func testBuildKIRUsesUserNullableIteratorSubtypeDirectly() throws {
        let source = """
        class NullableCounter(private val limit: Int) : Iterator<String?> {
            private var count = 0
            override operator fun hasNext(): Boolean = count < limit
            override operator fun next(): String? {
                val r = count
                count++
                return if (r % 2 == 0) "v$r" else null
            }
        }

        fun sumAll(): Int {
            var sum = 0
            for (i in NullableCounter(3)) {
                if (i != null) { sum += i.length }
            }
            return sum
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("hasNext"), "Expected direct hasNext call, got: \(callees)")
            #expect(callees.contains("next"), "Expected direct next call, got: \(callees)")
            #expect(!(callees.contains("kk_range_iterator")), "User nullable Iterator loop should not use kk_range_iterator, got: \(callees)")
            #expect(!(callees.contains("kk_range_hasNext")), "User nullable Iterator loop should not use kk_range_hasNext, got: \(callees)")
            #expect(!(callees.contains("kk_range_next")), "User nullable Iterator loop should not use kk_range_next, got: \(callees)")
        }
    }

    @Test func testBuildKIRUsesUserIterableSubtypeIterator() throws {
        let source = """
        class Counter(private val limit: Int) : Iterator<Int> {
            private var count = 0
            override operator fun hasNext(): Boolean = count < limit
            override operator fun next(): Int {
                val r = count
                count++
                return r
            }
        }

        class CounterBag(private val limit: Int) : Iterable<Int> {
            override operator fun iterator(): Iterator<Int> = Counter(limit)
        }

        fun sumAll(): Int {
            var sum = 0
            for (i in CounterBag(3)) { sum += i }
            return sum
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("iterator"), "Expected custom iterator() call, got: \(callees)")
            #expect(callees.contains("kk_iterator_hasNext"), "Expected generic kk_iterator_hasNext dispatch, got: \(callees)")
            #expect(callees.contains("kk_iterator_next"), "Expected generic kk_iterator_next dispatch, got: \(callees)")
            #expect(!(callees.contains("kk_range_iterator")), "User Iterable loop should not use kk_range_iterator, got: \(callees)")
            #expect(!(callees.contains("kk_range_hasNext")), "User Iterable loop should not use kk_range_hasNext, got: \(callees)")
            #expect(!(callees.contains("kk_range_next")), "User Iterable loop should not use kk_range_next, got: \(callees)")
        }
    }

    @Test func testBuildKIRKeepsRangeMembershipOnRuntimePath() throws {
        let source = """
        fun usesIn(): Boolean = 5 in (1..10).step(2)
        fun usesNotIn(): Boolean = 4 !in (1..10).step(2)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            for functionName in ["usesIn", "usesNotIn"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)

                #expect(callees.contains("kk_range_contains"), "Expected range membership runtime call, got: \(callees)")
                #expect(!callees.contains("contains"), "Range membership must not target an unlinked source symbol")
            }
        }
    }
}
#endif
