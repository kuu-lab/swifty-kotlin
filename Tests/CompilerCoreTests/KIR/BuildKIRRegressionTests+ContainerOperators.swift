#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testBuildKIRContainerOperators() throws {
        let sources = [
            """
            package sample0

            class Bucket0(private val values: MutableList<Int>) {
                operator fun get(index: Int): Int = values[index]
                operator fun set(index: Int, value: Int) { values[index] = value }
                operator fun contains(value: Int): Boolean = values.any { it == value }
                operator fun rangeTo(other: Bucket0): Int = values.size + other.values.size
            }

            fun use0(box: Bucket0, other: Bucket0): Int {
                val value = box[0]
                box[0] = value + 1
                return if (1 in box) box..other else 0
            }
            """,
            """
            package sample1

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

            fun sumAll1(bag: EntryBag): Int {
                var sum = 0
                for ((a, b) in bag) {
                    sum += a + b
                }
                return sum
            }
            """,
            """
            package sample2

            class Counter2(private val limit: Int) : Iterator<Int> {
                private var count = 0
                override operator fun hasNext(): Boolean = count < limit
                override operator fun next(): Int {
                    val r = count
                    count++
                    return r
                }
            }

            fun sumAll2(): Int {
                var sum = 0
                for (i in Counter2(3)) { sum += i }
                return sum
            }
            """,
            """
            package sample3

            class NullableCounter3(private val limit: Int) : Iterator<String?> {
                private var count = 0
                override operator fun hasNext(): Boolean = count < limit
                override operator fun next(): String? {
                    val r = count
                    count++
                    return if (r % 2 == 0) "v$r" else null
                }
            }

            fun sumAll3(): Int {
                var sum = 0
                for (i in NullableCounter3(3)) {
                    if (i != null) { sum += i.length }
                }
                return sum
            }
            """,
            """
            package sample4

            class Counter4(private val limit: Int) : Iterator<Int> {
                private var count = 0
                override operator fun hasNext(): Boolean = count < limit
                override operator fun next(): Int {
                    val r = count
                    count++
                    return r
                }
            }

            class CounterBag4(private val limit: Int) : Iterable<Int> {
                override operator fun iterator(): Iterator<Int> = Counter4(limit)
            }

            fun sumAll4(): Int {
                var sum = 0
                for (i in CounterBag4(3)) { sum += i }
                return sum
            }
            """,
            """
            package sample5

            fun usesIn5(): Boolean = 5 in (1..10).step(2)
            fun usesNotIn5(): Boolean = 4 !in (1..10).step(2)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "use0", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)

                #expect(callees.contains("get"), "Expected custom get call, got: \(callees)")
                #expect(callees.contains("set"), "Expected custom set call, got: \(callees)")
                #expect(callees.contains("contains"), "Expected custom contains call, got: \(callees)")
                #expect(callees.contains("rangeTo"), "Expected custom rangeTo call, got: \(callees)")
                #expect(!(callees.contains("kk_op_rangeTo")), "Custom rangeTo should not lower to kk_op_rangeTo, got: \(callees)")
            }

            do {
                let body = try findKIRFunctionBody(named: "sumAll1", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)

                #expect(callees.contains("iterator"), "Expected custom iterator call, got: \(callees)")
                #expect(callees.contains("hasNext"), "Expected custom hasNext call, got: \(callees)")
                #expect(callees.contains("next"), "Expected custom next call, got: \(callees)")
                #expect(callees.contains("component1"), "Expected destructuring component1 call, got: \(callees)")
                #expect(callees.contains("component2"), "Expected destructuring component2 call, got: \(callees)")
                #expect(!(callees.contains("kk_range_iterator")), "Custom iterator loop should not use kk_range_iterator, got: \(callees)")
                #expect(!(callees.contains("kk_range_hasNext")), "Custom iterator loop should not use kk_range_hasNext, got: \(callees)")
                #expect(!(callees.contains("kk_range_next")), "Custom iterator loop should not use kk_range_next, got: \(callees)")
            }

            do {
                let body = try findKIRFunctionBody(named: "sumAll2", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)

                #expect(callees.contains("hasNext"), "Expected direct hasNext call, got: \(callees)")
                #expect(callees.contains("next"), "Expected direct next call, got: \(callees)")
                #expect(!(callees.contains("kk_range_iterator")), "User Iterator loop should not use kk_range_iterator, got: \(callees)")
                #expect(!(callees.contains("kk_range_hasNext")), "User Iterator loop should not use kk_range_hasNext, got: \(callees)")
                #expect(!(callees.contains("kk_range_next")), "User Iterator loop should not use kk_range_next, got: \(callees)")
            }

            do {
                let body = try findKIRFunctionBody(named: "sumAll3", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)

                #expect(callees.contains("hasNext"), "Expected direct hasNext call, got: \(callees)")
                #expect(callees.contains("next"), "Expected direct next call, got: \(callees)")
                #expect(!(callees.contains("kk_range_iterator")), "User nullable Iterator loop should not use kk_range_iterator, got: \(callees)")
                #expect(!(callees.contains("kk_range_hasNext")), "User nullable Iterator loop should not use kk_range_hasNext, got: \(callees)")
                #expect(!(callees.contains("kk_range_next")), "User nullable Iterator loop should not use kk_range_next, got: \(callees)")
            }

            do {
                let body = try findKIRFunctionBody(named: "sumAll4", in: module, interner: interner)
                let callCallees = extractCallees(from: body, interner: interner)
                let virtualCallees = extractVirtualCallees(from: body, interner: interner)
                let allCallees = Set(callCallees + virtualCallees)

                #expect(callCallees.contains("iterator"), "Expected custom iterator() call, got: \(callCallees)")
                #expect(
                    allCallees.contains("kk_iterator_hasNext"),
                    "Expected Iterator.hasNext to lower through the generic kk_iterator_hasNext runtime dispatcher, got: call=\(callCallees) virtual=\(virtualCallees)"
                )
                #expect(
                    allCallees.contains("kk_iterator_next"),
                    "Expected Iterator.next to lower through the generic kk_iterator_next runtime dispatcher, got: call=\(callCallees) virtual=\(virtualCallees)"
                )
                #expect(!allCallees.contains("kk_range_iterator"), "User Iterable loop should not use kk_range_iterator, got: \(allCallees)")
                #expect(!allCallees.contains("kk_range_hasNext"), "User Iterable loop should not use kk_range_hasNext, got: \(allCallees)")
                #expect(!allCallees.contains("kk_range_next"), "User Iterable loop should not use kk_range_next, got: \(allCallees)")
            }

            do {
                for functionName in ["usesIn5", "usesNotIn5"] {
                    let body = try findKIRFunctionBody(named: functionName, in: module, interner: interner)
                    let callees = extractCallees(from: body, interner: interner)

                    let hasSourceBackedRangeContains = body.contains { instruction in
                        guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else { return false }
                        return interner.resolve(callee) == "kk_range_contains" && symbol != nil && symbol != .invalid
                    }
                    #expect(hasSourceBackedRangeContains, "Expected source-backed range contains call, got: \(callees)")
                    #expect(callees.contains("kk_range_contains"), "Expected kk_range_contains callee, got: \(callees)")
                    #expect(!callees.contains("kk_op_contains"), "Range membership must not fall back to runtime kk_op_contains, got: \(callees)")
                }
            }
        }
    }
}
#endif
