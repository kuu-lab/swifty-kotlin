#if canImport(Testing)
@testable import CompilerCore
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

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("get"), "Expected custom get call, got: \(callees)")
        #expect(callees.contains("set"), "Expected custom set call, got: \(callees)")
        #expect(callees.contains("contains"), "Expected custom contains call, got: \(callees)")
        #expect(callees.contains("rangeTo"), "Expected custom rangeTo call, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.opRangeTo))), "Custom rangeTo should not lower to kk_op_rangeTo, got: \(callees)")
    }

    // KSWIFTK-BUG: a bare integer literal index (`b[0]`) must contextualize to
    // a non-Int operator get()/set() parameter type (Long here), the same way
    // Kotlin already contextualizes the assigned value in `x[i] = value`.
    // Before the fix, the literal defaulted to Int, overload resolution
    // rejected the only get()/set() candidate (Int is not a subtype of Long),
    // and lowering silently fell back to raw kk_array_get/kk_array_set on the
    // non-array receiver instead of dispatching to the custom operator.
    @Test func testBuildKIRUsesCustomLongIndexedGetSetOperators() throws {
        let source = """
        class LongIndexedBox {
            private var data: ByteArray = byteArrayOf(9, 8, 7, 6)
            operator fun get(position: Long): Byte = data[position.toInt()]
            operator fun set(position: Long, value: Byte) { data[position.toInt()] = value }
        }

        fun use(box: LongIndexedBox): Byte {
            box[0] = box[1]
            return box[0]
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("get"), "Expected custom Long-indexed get call, got: \(callees)")
        #expect(callees.contains("set"), "Expected custom Long-indexed set call, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.arrayGet)), "Long-indexed get() must not fall back to raw array access, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.arraySet)), "Long-indexed set() must not fall back to raw array access, got: \(callees)")
    }

    // KSWIFTK-BUG: `a[i] += v` / `a[i]++` on a receiver with a custom (or
    // source-backed member, e.g. MutableList) get()/set() pair previously
    // always lowered to raw kk_array_get/kk_array_set on the receiver's own
    // memory, completely bypassing the custom operators (confirmed
    // empirically: the write had no effect through the custom get()).
    // lowerIndexedCompoundAssignExpr must instead dispatch through the
    // resolved get()/set() calls, mirroring how lowerIndexedAssignExpr
    // already does for plain `a[i] = v`.
    @Test func testBuildKIRUsesCustomOperatorsForIndexedCompoundAssignAndIncrement() throws {
        let source = """
        class Bucket(private val values: MutableList<Int>) {
            operator fun get(index: Int): Int = values[index]
            operator fun set(index: Int, value: Int) { values[index] = value }
        }

        fun use(box: Bucket): Int {
            box[0] += 5
            box[1]++
            return box[0] + box[1]
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("get"), "Expected custom get calls for the read halves, got: \(callees)")
        #expect(callees.contains("set"), "Expected custom set calls for the write-back halves, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.arrayGet)), "Compound assign on a custom operator must not read via raw array access, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.arraySet)), "Compound assign on a custom operator must not write via raw array access, got: \(callees)")
    }

    // A genuine built-in array must keep using the raw array/boxing runtime
    // path for compound assignment: it has no user-defined get()/set() to
    // dispatch through, and Array<T> in particular needs the box/unbox
    // handling this path alone provides.
    @Test func testBuildKIRKeepsRawArrayPathForBuiltInArrayCompoundAssign() throws {
        let source = """
        fun use(a: IntArray): Int {
            a[0] += 5
            a[1]++
            return a[0] + a[1]
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.arrayGet)), "Built-in IntArray compound assign should still use the raw array read, got: \(callees)")
        #expect(callees.contains(runtimeCallee(.arraySet)), "Built-in IntArray compound assign should still use the raw array write, got: \(callees)")
    }

    // KSWIFTK-BUG: the same dispatch-through-get()/set() fix above must also
    // hold for a multi-argument indexed operator (`grid[i, j]`), not just the
    // single-index case: both index expressions have to reach both the get()
    // read and the set() write-back, for `+=`, postfix `++`, and statement-
    // level prefix `++`/`--` alike.
    @Test func testBuildKIRUsesCustomOperatorsForMultiIndexCompoundAssignAndIncrement() throws {
        let source = """
        class Grid(val w: Int, val h: Int) {
            private val cells = IntArray(w * h)
            operator fun get(i: Int, j: Int): Int = cells[j * w + i]
            operator fun set(i: Int, j: Int, v: Int) { cells[j * w + i] = v }
        }

        fun use(grid: Grid): Int {
            grid[0, 0] += 5
            grid[1, 1]++
            ++grid[0, 1]
            return grid[0, 0] + grid[1, 1] + grid[0, 1]
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(!callees.contains(runtimeCallee(.arrayGet)), "Multi-index compound assign must not read via raw array access, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.arraySet)), "Multi-index compound assign must not write via raw array access, got: \(callees)")

        let getArgCounts: [Int] = body.compactMap { instruction in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  callee == KnownCompilerNames(interner: ctx.interner).get
            else { return nil }
            return arguments.count
        }
        let setArgCounts: [Int] = body.compactMap { instruction in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  callee == KnownCompilerNames(interner: ctx.interner).sbSet
            else { return nil }
            return arguments.count
        }

        // += , postfix ++, and prefix ++ each read once and write once (3
        // get() calls), plus 3 more get() calls from the plain reads in the
        // final `return` expression = 6 total; only the compound-assign
        // statements write, so 3 set() calls.
        #expect(getArgCounts.count == 6, "Expected 6 custom get() calls (3 compound-assign reads + 3 return-expression reads), got: \(getArgCounts.count)")
        #expect(setArgCounts.count == 3, "Expected 3 custom set() calls (+=, postfix ++, prefix ++), got: \(setArgCounts.count)")
        // set() must carry one more argument than its compound assign's own
        // get() (the extra value parameter): if a fix regresses to only
        // threading the first index through, both counts collapse by the
        // same amount and this delta check still catches it without hard-
        // coding the receiver-inclusion convention of the surrounding call
        // ABI. The first 3 get() calls are the compound-assign reads, in
        // program order, matching the 3 set() calls one-for-one.
        for (getCount, setCount) in zip(getArgCounts.prefix(3), setArgCounts) {
            #expect(setCount == getCount + 1, "set() should carry exactly one more argument than get() (the value), got get=\(getCount) set=\(setCount)")
        }
        #expect(getArgCounts.allSatisfy { $0 >= 2 }, "Expected both indices to reach get(), got argument counts: \(getArgCounts)")
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

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("iterator"), "Expected custom iterator call, got: \(callees)")
        #expect(callees.contains("hasNext"), "Expected custom hasNext call, got: \(callees)")
        #expect(callees.contains("next"), "Expected custom next call, got: \(callees)")
        #expect(callees.contains("component1"), "Expected destructuring component1 call, got: \(callees)")
        #expect(callees.contains("component2"), "Expected destructuring component2 call, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeIterator))), "Custom iterator loop should not use kk_range_iterator, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeHasNext))), "Custom iterator loop should not use kk_range_hasNext, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeNext))), "Custom iterator loop should not use kk_range_next, got: \(callees)")
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

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("hasNext"), "Expected direct hasNext call, got: \(callees)")
        #expect(callees.contains("next"), "Expected direct next call, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeIterator))), "User Iterator loop should not use kk_range_iterator, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeHasNext))), "User Iterator loop should not use kk_range_hasNext, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeNext))), "User Iterator loop should not use kk_range_next, got: \(callees)")
    }

    // KSP-938: a source-backed CharSequence.iterator() returns CharIterator,
    // so its inherited Iterator members must use interface dispatch in for-in.
    @Test func testBuildKIRUsesSourceBackedCharIteratorDispatch() throws {
        let source = """
        fun sumChars(): Int {
            var total = 0
            for (ch in "abc") { total += ch.code }
            return total
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "sumChars", in: module, interner: ctx.interner)
        let directCallees = extractCallees(from: body, interner: ctx.interner)
        let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)

        #expect(virtualCallees.contains("hasNext"), "CharIterator.hasNext must use interface dispatch, got: \(virtualCallees)")
        #expect(virtualCallees.contains("next"), "CharIterator.next must use interface dispatch, got: \(virtualCallees)")
        #expect(!directCallees.contains("hasNext"), "CharIterator.hasNext must not be a direct call, got: \(directCallees)")
        #expect(!directCallees.contains("next"), "CharIterator.next must not be a direct call, got: \(directCallees)")
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

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("hasNext"), "Expected direct hasNext call, got: \(callees)")
        #expect(callees.contains("next"), "Expected direct next call, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeIterator))), "User nullable Iterator loop should not use kk_range_iterator, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeHasNext))), "User nullable Iterator loop should not use kk_range_hasNext, got: \(callees)")
        #expect(!(callees.contains(runtimeCallee(.rangeNext))), "User nullable Iterator loop should not use kk_range_next, got: \(callees)")
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

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
        let callCallees = extractCallees(from: body, interner: ctx.interner)
        let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)
        let allCallees = Set(callCallees + virtualCallees)

        #expect(callCallees.contains("iterator"), "Expected custom iterator() call, got: \(callCallees)")
        #expect(
            allCallees.contains(runtimeCallee(.iteratorHasNext)) || virtualCallees.contains("hasNext"),
            "Expected Iterator.hasNext to use the source-backed virtual dispatch or generic runtime dispatcher, got: call=\(callCallees) virtual=\(virtualCallees)"
        )
        #expect(
            allCallees.contains(runtimeCallee(.iteratorNext)) || virtualCallees.contains("next"),
            "Expected Iterator.next to use the source-backed virtual dispatch or generic runtime dispatcher, got: call=\(callCallees) virtual=\(virtualCallees)"
        )
        #expect(!allCallees.contains(runtimeCallee(.rangeIterator)), "User Iterable loop should not use kk_range_iterator, got: \(allCallees)")
        #expect(!allCallees.contains(runtimeCallee(.rangeHasNext)), "User Iterable loop should not use kk_range_hasNext, got: \(allCallees)")
        #expect(!allCallees.contains(runtimeCallee(.rangeNext)), "User Iterable loop should not use kk_range_next, got: \(allCallees)")
    }

    // KSP-697: List is source-backed and therefore no longer synthetic, but a
    // concrete List receiver must retain the specialized iterator ABI.
    @Test func testBuildKIRUsesConcreteSourceBackedListIterator() throws {
        let source = """
        fun sumAll(): Int {
            val values: List<Int> = listOf(1, 2, 3)
            var sum = 0
            for (value in values) { sum += value }
            return sum
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.listIterator)), "Concrete List must use kk_list_iterator, got: \(callees)")
        #expect(callees.contains(runtimeCallee(.listIteratorHasNext)), "Concrete List must use list iterator hasNext, got: \(callees)")
        #expect(callees.contains(runtimeCallee(.listIteratorNext)), "Concrete List must use list iterator next, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.iterableIterator)), "Concrete List must not use the generic Iterable bridge, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.iteratorHasNext)), "Concrete List must not use generic hasNext, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.iteratorNext)), "Concrete List must not use generic next, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.rangeIterator)), "Concrete List must not use the range iterator, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.rangeHasNext)), "Concrete List must not use range hasNext, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.rangeNext)), "Concrete List must not use range next, got: \(callees)")
    }

    @Test func testBuildKIRUsesSourceBackedRangeContains() throws {
        let source = """
        fun usesIn(): Boolean = 5 in (1..10).step(2)
        fun usesNotIn(): Boolean = 4 !in (1..10).step(2)
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        for functionName in ["usesIn", "usesNotIn"] {
            let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            // KSP-312: IntRange/IntProgression.contains is source-backed, so `in`/`!in`
            // dispatches to the bundled Kotlin `contains()` member (external link name
            // __kk_range_contains) instead of the generic kk_op_contains runtime stub.
            let hasSourceBackedRangeContains = body.contains { instruction in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else { return false }
                return callee == ctx.interner.intern(runtimeCallee(.rangeContains)) && symbol != nil && symbol != .invalid
            }
            #expect(hasSourceBackedRangeContains, "Expected source-backed range contains call, got: \(callees)")
            #expect(callees.contains(runtimeCallee(.rangeContains)), "Expected __kk_range_contains callee, got: \(callees)")
            #expect(!callees.contains(runtimeCallee(.opContains)), "Range membership must not fall back to runtime kk_op_contains, got: \(callees)")
        }
    }

    @Test func testClosedRangeInterfaceMembershipUsesInterfaceDispatch() throws {
        let source = """
        fun check(range: ClosedRange<Int>): Boolean = 3 in range && range.contains(3)
        fun checkNotIn(range: ClosedRange<Int>): Boolean = 7 !in range
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        for functionName in ["check", "checkNotIn"] {
            let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            let interfaceContainsCalls = body.filter { instruction in
                guard case let .virtualCall(_, callee, _, _, _, _, _, dispatch) = instruction,
                      callee == KnownCompilerNames(interner: ctx.interner).contains,
                      case .itableDynamic = dispatch
                else { return false }
                return true
            }
            #expect(interfaceContainsCalls.count == (functionName == "check" ? 2 : 1),
                    "Erased ClosedRange calls must preserve source overrides through interface dispatch")
            #expect(!callees.contains("contains"), "A bare contains symbol cannot link: \(callees)")
        }
    }

    // ARCH-012: IntRange uses an induction variable, while other signed range
    // shapes retain the BUG-198 runtime iterator path.
    @Test func testBuildKIRLowersIntRangeForLoopThroughInductionVariablePath() throws {
        let source = """
        fun sumInts(): Int {
            var sum = 0
            for (i in 1..10) { sum += i }
            return sum
        }

        fun sumTyped(range: IntRange): Int {
            var sum = 0
            for (i in range) { sum += i }
            return sum
        }

        fun sumProgression(): Int {
            var sum = 0
            for (i in 10 downTo 1 step 3) { sum += i }
            return sum
        }

        fun sumLongs(): Long {
            var sum = 0L
            for (l in 1L..4L) { sum += l }
            return sum
        }

        fun sumChars(): Int {
            var sum = 0
            for (c in 'a'..'e') { sum += c.code }
            return sum
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        for functionName in ["sumInts", "sumTyped", "sumProgression", "sumLongs", "sumChars"] {
            let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            if functionName == "sumInts" {
                #expect(!callees.contains(runtimeCallee(.rangeForInIterator)), "\(functionName): induction loop must not allocate a runtime iterator, got: \(callees)")
                #expect(!callees.contains(runtimeCallee(.rangeForInHasNext)), "\(functionName): induction loop must not call hasNext, got: \(callees)")
                #expect(!callees.contains(runtimeCallee(.rangeForInNext)), "\(functionName): induction loop must not call next, got: \(callees)")
                #expect(!callees.contains(runtimeCallee(.rangeFirst)), "\(functionName): direct range should not load a range object bound, got: \(callees)")
                #expect(!callees.contains(runtimeCallee(.rangeLast)), "\(functionName): direct range should not load a range object bound, got: \(callees)")
                #expect(callees.contains(runtimeCallee(.intRangeInductionLe)), "\(functionName): expected native induction comparison, got: \(callees)")
            } else if functionName == "sumTyped" {
                #expect(!callees.contains(runtimeCallee(.rangeForInIterator)), "\(functionName): induction loop must not allocate a runtime iterator, got: \(callees)")
                #expect(!callees.contains(runtimeCallee(.rangeForInHasNext)), "\(functionName): induction loop must not call hasNext, got: \(callees)")
                #expect(!callees.contains(runtimeCallee(.rangeForInNext)), "\(functionName): induction loop must not call next, got: \(callees)")
                #expect(callees.contains(runtimeCallee(.rangeFirst)), "\(functionName): expected one-time first-bound load, got: \(callees)")
                #expect(callees.contains(runtimeCallee(.rangeLast)), "\(functionName): expected one-time last-bound load, got: \(callees)")
                #expect(callees.contains(runtimeCallee(.intRangeInductionLe)), "\(functionName): expected native induction comparison, got: \(callees)")
            } else {
                #expect(callees.contains(runtimeCallee(.rangeForInIterator)), "\(functionName): expected range fast-path iterator, got: \(callees)")
                #expect(callees.contains(runtimeCallee(.rangeForInHasNext)), "\(functionName): expected range fast-path hasNext, got: \(callees)")
                #expect(callees.contains(runtimeCallee(.rangeForInNext)), "\(functionName): expected range fast-path next, got: \(callees)")
            }
            #expect(!callees.contains("iterator"), "\(functionName): for-in must not allocate the generic source iterator, got: \(callees)")
            #expect(!callees.contains(runtimeCallee(.iteratorHasNext)), "\(functionName): for-in must not use generic hasNext dispatch, got: \(callees)")
            #expect(!callees.contains(runtimeCallee(.iteratorNext)), "\(functionName): for-in must not use generic next dispatch, got: \(callees)")
            #expect(!callees.contains(runtimeCallee(.rangeIterator)), "\(functionName): range loop must not use kk_range_iterator, got: \(callees)")
            #expect(!callees.contains(runtimeCallee(.rangeHasNext)), "\(functionName): range loop must not use kk_range_hasNext, got: \(callees)")
            #expect(!callees.contains(runtimeCallee(.rangeNext)), "\(functionName): range loop must not use kk_range_next, got: \(callees)")
        }
    }

    // KSP-996 review regression: generic iterator bridges have a trailing
    // outThrown ABI channel, so their KIR calls must be marked throwing.
    @Test
    func testBuildKIRMarksDynamicIterableBridgeCallsAsThrowing() throws {
        let source = """
        fun sumAll(xs: Iterable<Int>): Int {
            try {
                var sum = 0
                for (x in xs) { sum += x }
                return sum
            } catch (e: IllegalStateException) {
                return -1
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "sumAll", in: module, interner: ctx.interner)
        let expectedNames: Set<String> = [
            runtimeCallee(.iterableIterator),
            runtimeCallee(.iteratorHasNext),
            runtimeCallee(.iteratorNext),
        ]
        let bridgeCalls: [(name: String, canThrow: Bool, hasThrownResult: Bool)] = body.compactMap { instruction in
            guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instruction else {
                return nil
            }
            let name = ctx.interner.resolve(callee)
            guard expectedNames.contains(name) else {
                return nil
            }
            return (name, canThrow, thrownResult != nil)
        }

        #expect(Set(bridgeCalls.map { $0.name }) == expectedNames, "Unexpected iterator bridge calls: \(bridgeCalls)")
        #expect(bridgeCalls.allSatisfy { $0.canThrow && $0.hasThrownResult }, "Iterator bridge calls must carry the throwing channel: \(bridgeCalls)")
    }
}
#endif
