@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AtomicScalarApiSurfaceTests {
    @Test
    func canonicalScalarsRejectJavaMethodNames() throws {
        let arithmeticCalls = [
            "getAndAdd(3)", "addAndGet(3)", "incrementAndGet()", "decrementAndGet()",
            "getAndIncrement()", "getAndDecrement()",
        ]
        let coreCalls = ["get()", "set(VALUE)", "getAndSet(VALUE)"]
        let updateCalls = ["getAndUpdate { it }", "updateAndGet { it }"]
        let calls = [
            ("ai", arithmeticCalls + coreCalls.map { $0.replacingOccurrences(of: "VALUE", with: "3") } + updateCalls),
            ("al", arithmeticCalls.map { $0.replacingOccurrences(of: "(3)", with: "(3L)") }
                + coreCalls.map { $0.replacingOccurrences(of: "VALUE", with: "3L") } + updateCalls),
            ("ar", coreCalls.map { $0.replacingOccurrences(of: "VALUE", with: "\"z\"") } + updateCalls),
            ("ab", coreCalls.map { $0.replacingOccurrences(of: "VALUE", with: "false") } + updateCalls),
        ].flatMap { receiver, methods in methods.map { "\(receiver).\($0)" } }
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.*
        import kotlin.concurrent.getAndAdd
        import kotlin.concurrent.getAndUpdate
        import kotlin.concurrent.updateAndGet
        fun main() {
            val ai = AtomicInt(0)
            val al = AtomicLong(0L)
            val ar = AtomicReference("x")
            val ab = AtomicBoolean(true)
            \(calls.joined(separator: "\n    "))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == calls.count, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0024" }, "\(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let memberCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, _, _, _, range) = ast.arena.expr(id),
                      ctx.sourceManager.origin(of: range.start.file) == .user
                else { return nil }
                return id
            }
            #expect(memberCalls.count == calls.count)
            for call in memberCalls {
                #expect(sema.bindings.callBinding(for: call) == nil)
            }
        }
    }

    // KUU-1365: names absent from the real kotlin.concurrent.atomics API
    // (checked against the JVM reference kotlinc) must not resolve: Native
    // extras (`value`, operator get/set, `length`, getAndSet, non-At CAS,
    // *AndGet aliases), the phantom atomicArrayOf factory / AtomicArray(size)
    // constructor, and the AtomicBoolean update family.
    @Test
    func canonicalAtomicsRejectNonCanonicalMembers() throws {
        let scalarCalls = [
            ("ai", ["get()", "set(3)", "getAndSet(3)", "lazySet(3)", "getAndUpdate { it }", "updateAndGet { it }"]),
            ("al", ["get()", "set(3L)", "getAndSet(3L)", "lazySet(3L)", "getAndUpdate { it }", "updateAndGet { it }"]),
            ("ar", ["get()", "set(\"z\")", "getAndSet(\"z\")", "lazySet(\"z\")", "getAndUpdate { it }", "updateAndGet { it }"]),
            ("ab", ["get()", "set(false)", "getAndSet(false)", "fetchAndUpdate { it }", "updateAndFetch { it }", "update { it }"]),
        ].flatMap { receiver, methods in methods.map { "\(receiver).\($0)" } }
        let scalarReads = ["ai.value", "al.value", "ar.value", "ab.value"]
        let arrayCalls = [
            ("ia", ["getAndSet(0, 1)", "compareAndSet(0, 1, 2)", "compareAndExchange(0, 1, 2)",
                    "getAndAdd(0, 1)", "addAndGet(0, 1)", "getAndIncrement(0)", "incrementAndGet(0)",
                    "getAndDecrement(0)", "decrementAndGet(0)"]),
            ("la", ["getAndSet(0, 1L)", "compareAndSet(0, 1L, 2L)", "compareAndExchange(0, 1L, 2L)",
                    "getAndAdd(0, 1L)", "addAndGet(0, 1L)", "getAndIncrement(0)", "incrementAndGet(0)",
                    "getAndDecrement(0)", "decrementAndGet(0)"]),
            ("ra", ["getAndSet(0, \"y\")", "compareAndSet(0, \"y\", \"z\")", "compareAndExchange(0, \"z\", \"w\")"]),
        ].flatMap { receiver, methods in methods.map { "\(receiver).\($0)" } }
        let arrayReads = ["ia[0]", "la[0]", "ra[0]", "ia.length", "la.length", "ra.length"]
        let arrayWrites = ["ia[0] = 1", "la[0] = 1L", "ra[0] = \"x\""]
        let factories = ["atomicArrayOf(\"x\")", "AtomicArray<Int>(3)"]
        let bad = scalarCalls + scalarReads + arrayCalls + arrayReads + arrayWrites + factories
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.*
        fun main() {
            val ai = AtomicInt(0)
            val al = AtomicLong(0L)
            val ar = AtomicReference("x")
            val ab = AtomicBoolean(true)
            val ia = AtomicIntArray(2)
            val la = AtomicLongArray(2)
            val ra = atomicArrayOfNulls<String>(1)
            \(bad.joined(separator: "\n    "))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == bad.count, "\(errors)")
        }
    }

    @Test
    func canonicalAtomicsApiSurfaceResolves() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.*
        fun main() {
            val ai = AtomicInt(0)
            println(ai.load()); ai.store(1); println(ai.exchange(2))
            println(ai.compareAndSet(2, 3)); println(ai.compareAndExchange(3, 4))
            println(ai.fetchAndAdd(1)); println(ai.addAndFetch(1))
            println(ai.fetchAndIncrement()); println(ai.incrementAndFetch())
            println(ai.fetchAndDecrement()); println(ai.decrementAndFetch())
            ai.update { it }; println(ai.updateAndFetch { it }); println(ai.fetchAndUpdate { it })
            ai += 1; ai -= 1; println(ai.toString())
            val al = AtomicLong(0L); al.update { it }; println(al.fetchAndUpdate { it } + al.updateAndFetch { it })
            val ab = AtomicBoolean(true)
            println(ab.load()); ab.store(false); println(ab.exchange(true))
            println(ab.compareAndSet(true, false)); println(ab.compareAndExchange(false, true)); println(ab.toString())
            val ar = AtomicReference("x")
            println(ar.load()); ar.store("y"); println(ar.exchange("z"))
            println(ar.compareAndSet("z", "w")); println(ar.compareAndExchange("w", "v"))
            ar.update { it }; println(ar.updateAndFetch { it }); println(ar.fetchAndUpdate { it }); println(ar.toString())
            val ia = AtomicIntArray(2)
            val ia2 = AtomicIntArray(intArrayOf(1, 2))
            val ia3 = AtomicIntArray(2) { it }
            ia.storeAt(0, 1); println(ia.loadAt(0)); println(ia.exchangeAt(0, 2))
            println(ia.compareAndSetAt(0, 2, 3)); println(ia.compareAndExchangeAt(0, 3, 4))
            println(ia.fetchAndAddAt(0, 1)); println(ia.addAndFetchAt(0, 1))
            println(ia.fetchAndIncrementAt(0)); println(ia.incrementAndFetchAt(0))
            println(ia.fetchAndDecrementAt(0)); println(ia.decrementAndFetchAt(0))
            ia.updateAt(0) { it }; println(ia.updateAndFetchAt(0) { it }); println(ia.fetchAndUpdateAt(0) { it })
            println(ia.size); println(ia.toString()); println(ia2.size); println(ia3.size)
            val la = AtomicLongArray(1); la.storeAt(0, 1L); println(la.loadAt(0) + la.size)
            val ra = atomicArrayOfNulls<String>(1)
            val rb = AtomicArray(arrayOf("a"))
            val rc = AtomicArray(2) { "i$it" }
            ra.storeAt(0, "x"); println(ra.loadAt(0) + ra.size + rb.size + rc.size)
            println(ra.exchangeAt(0, "z")); println(ra.compareAndSetAt(0, "z", "w"))
            println(ra.compareAndExchangeAt(0, "w", "v"))
            ra.updateAt(0) { it }; println(ra.updateAndFetchAt(0) { it }); println(ra.fetchAndUpdateAt(0) { it })
            println(ra.toString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func javaAndLegacyAliasesAndUserExtensionsRemainCallable() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        import kotlin.concurrent.atomics.*
        import java.util.concurrent.atomic.AtomicInteger
        import kotlin.concurrent.AtomicInt as LegacyInt
        import kotlin.concurrent.AtomicReference as LegacyReference
        fun AtomicInt.getAndAdd(delta: Int): Int = fetchAndAdd(delta)
        fun main() {
            val java = AtomicInteger(0)
            java.getAndAdd(3)
            java.addAndGet(3)
            java.incrementAndGet()
            java.decrementAndGet()
            java.getAndIncrement()
            java.getAndDecrement()
            java.getAndSet(0)
            java.get()
            java.set(0)
            val legacy = LegacyInt(0)
            legacy.getAndAdd(3)
            legacy.incrementAndGet()
            val reference = LegacyReference("x")
            reference.getAndSet("z")
            val canonical = AtomicInt(0)
            canonical.getAndAdd(3)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
