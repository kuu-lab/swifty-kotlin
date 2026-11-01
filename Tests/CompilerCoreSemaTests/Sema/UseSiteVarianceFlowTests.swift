@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct UseSiteVarianceFlowTests {

    @Test
    func testUseSiteVarianceBlocksWriteAndPreservesReadType() throws {
        let sources = [
            """
            package sample0

            class E

            class Box<T> {
                fun get(): T = throw E()
                fun set(v: T) {}
            }

            fun readOnly(box: Box<out Any>): Any = box.get()

            fun writeBlocked(box: Box<out Any>) {
                box.set(42)
            }
            """,
            """
            package sample1

            class E

            class Box<T> {
                fun get(): T = throw E()
                fun set(v: T) {}
            }

            fun starRead(box: Box<*>): Any? = box.get()

            fun starWrite(box: Box<*>) {
                box.set(42)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let outPath = paths[0]
            let outGetCall = try #require(firstExprID(in: ast, path: outPath, ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return callee == KnownCompilerNames(interner: ctx.interner).get
            })
            #expect(sema.bindings.exprType(for: outGetCall) == sema.types.anyType)

            let starPath = paths[1]
            let starGetCall = try #require(firstExprID(in: ast, path: starPath, ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return callee == KnownCompilerNames(interner: ctx.interner).get
            })
            #expect(sema.bindings.exprType(for: starGetCall) == sema.types.nullableAnyType)

            assertHasDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    @Test
    func testProjectedReceiverAcceptsUnsafeVarianceMemberParameters() throws {
        let source = """
        open class A<out K> {
            fun foo(value: @UnsafeVariance K): K = value
            fun fooNullable(value: @UnsafeVariance K?): K? = value
        }

        class Derived<out K> : A<K>()

        class Multi<out K, out V> {
            fun fooBoth(key: @UnsafeVariance K, value: @UnsafeVariance V): K = key
        }

        fun test(a: A<*>): Any? = a.foo("OK")
        fun inherited(a: Derived<*>): Any? = a.foo("OK")
        fun nullable(a: A<*>): Any? = a.fooNullable(null)
        fun multiple(a: Multi<*, *>): Any? = a.fooBoth("K", "V")
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VARIANCE", in: ctx)
        }
    }

    @Test
    func testUseSiteInProjectionOnInDeclaredParameterIsAccepted() throws {
        // KUU-1381: a use-site `in` on an `in`-declared parameter is a redundant
        // projection — kotlinc accepts it and `Sink<in X>` behaves like `Sink<X>`.
        let source = """
        interface Sink<in T> { fun put(t: T) }
        class IS<T> : Sink<T> { override fun put(t: T) {} }

        val s1: Sink<in Int> = IS<Int>()
        val s2: Sink<in Int> = IS<Any>()
        val f: Sink<*> = IS<Int>()

        fun feed(s: Sink<in Int>) { s.put(9) }
        val call = feed(IS<Any>())
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let hasError = ctx.diagnostics.hasError
            #expect(!hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
        }
    }

    @Test
    func testUseSiteInProjectionOnInDeclaredParameterKeepsContravariantDirection() throws {
        // `Sink<in Any>` still rejects `Sink<Int>` — the projection is redundant,
        // not direction-flipping (kotlinc rejects the same shape).
        let source = """
        interface Sink<in T> { fun put(t: T) }
        class IS<T> : Sink<T> { override fun put(t: T) {} }

        val bad: Sink<in Any> = IS<Int>()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // The projection check runs outside the initializer subtype
            // path, so it keeps the generic constraint code.
            assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    @Test(arguments: [false, true])
    func forLoopOverMutableMapYieldsInvariantMutableEntry(useArtifact: Bool) throws {
        // KUU-1420: `for (e in mutableMap)` types the loop variable as
        // MutableMap.MutableEntry<K, V> — invariant args, mirroring the real
        // `MutableMap.iterator().next()` return type. The earlier `out`
        // projections on the element args marked `V` write-forbidden, so
        // `e.setValue(...)` was wrongly rejected with KSWIFTK-SEMA-VAR-OUT.
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = """
        fun rewrite(map: MutableMap<String, Int>) {
            for (e in map) {
                e.setValue(9)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let setValueCall = try #require(firstExprID(in: ast, path: path, ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return callee == interner.intern("setValue")
            })
            let binding = try #require(sema.bindings.callBinding(for: setValueCall))
            let calleeSymbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(calleeSymbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableMap"),
                interner.intern("MutableEntry"),
                interner.intern("setValue"),
            ])
        }
    }

    @Test(arguments: [false, true])
    func forLoopOverMutableMapEntriesAllowsSetValue(useArtifact: Bool) throws {
        // KUU-3456: the entries view must preserve invariant MutableEntry arguments.
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = """
        fun main() {
            val m = mutableMapOf(1 to "a")
            for (e in m.entries) {
                e.setValue("b")
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)

            let ast = try #require(ctx.ast)
            let interner = ctx.interner
            let setValueCall = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return callee == interner.intern("setValue")
            })
            let sema = try #require(ctx.sema)
            let binding = try #require(sema.bindings.callBinding(for: setValueCall))
            let calleeSymbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(calleeSymbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableMap"),
                interner.intern("MutableEntry"),
                interner.intern("setValue"),
            ])
        }
    }

    @Test
    func testIndexedAccessAndAssignApplyProjectedReceiverVariance() throws {
        // Indexed operators must honor the receiver's use-site projection the
        // same way member calls do: `out` forbids `set`, `in` reads the
        // captured upper bound instead of the raw type argument (kotlinc
        // parity — `xs[0]` used to bind E directly and accept both shapes).
        let sources = [
            """
            package indexedOut

            class E

            class Box<T> {
                operator fun get(index: Int): T = throw E()
                operator fun set(index: Int, v: T) {}
            }

            fun readOk(box: Box<out Any>): Any = box[0]

            fun writeBlocked(box: Box<out Any>) {
                box[0] = 42
            }

            fun compoundWriteBlocked(box: Box<out Int>) {
                box[0] += 42
            }
            """,
            """
            package indexedIn

            class E

            class Box<T> {
                operator fun get(index: Int): T = throw E()
                operator fun set(index: Int, v: T) {}
            }

            fun writeOk(box: Box<in Int>) {
                box[0] = 42
            }

            fun readWide(box: Box<in Int>): Any? = box[0]

            fun readTooNarrow(box: Box<in Int>): Int = box[0]

            fun compoundReadCaptured(box: Box<in Int>) {
                box[0] += 42
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            // `box[0]` on `Box<out Any>` reads the captured upper bound `Any`,
            // matching `box.get()`.
            let outIndexedRead = try #require(firstExprID(in: ast, path: paths[0], ctx: ctx) { _, expr in
                guard case .indexedAccess = expr else { return false }
                return true
            })
            #expect(sema.bindings.exprType(for: outIndexedRead) == sema.types.anyType)

            // `out` projection forbids the indexed `set` — plain `=` and the
            // `set` half of `+=` alike; `in` accepts writes.
            assertDiagnosticCount("KSWIFTK-SEMA-VAR-OUT", expected: 2, in: ctx)
            // `Box<in Int>` reads a captured type — returning it as `Int` fails.
            assertDiagnosticCount("KSWIFTK-SEMA-0469", expected: 1, in: ctx)
            // `box[0] += v` on `Box<in Int>` reads a captured type on which
            // `plus` does not resolve (kotlinc: unresolved reference '+=').
            assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 1, in: ctx)
        }
    }

    @Test
    func forLoopOverReadOnlyMapStillRejectsSetValue() throws {
        // KUU-1420 companion: `for (e in map)` over read-only Map yields
        // Map.Entry<K, V> — setValue is not a member, so the write stays
        // rejected (same as kotlinc's unresolved-reference error).
        let source = """
        fun rewrite(map: Map<String, Int>) {
            for (e in map) {
                e.setValue(9)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
        }
    }
}
