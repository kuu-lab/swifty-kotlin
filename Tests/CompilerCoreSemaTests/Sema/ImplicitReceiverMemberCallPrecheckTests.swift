@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-3780: an inferred property whose initializer calls a member function on
/// the implicit receiver (`val x = makeInt()`) kept its header-registered
/// `Any?` placeholder when a reader in another file was checked first. Member
/// signatures store their dispatch receiver in `signature.receiverType`, so the
/// precheck's zero-argument call path — which filtered candidates to
/// `receiverType == nil` — could never see them. The same gap hid explicit
/// `this.makeInt()` receivers (`thisRef` was not handled). The precheck now
/// walks the implicit receiver tower for member candidates, the way
/// `safePrecheckNameReference` already does for member properties.
///
/// KUU-4014: the same gap existed for calls *with arguments* —
/// `val currentLine = getLine(lineN)!!` inside JetBrains/markdown's inner
/// `LookaheadText.Position` class. The argument-bearing branch used to bail
/// out as soon as any same-named member existed; it now collects applicable
/// implicit-receiver members with `precheckArgumentFitsSignature`, lets an
/// inapplicable member fall through to outer receivers and lexical
/// candidates, and keeps same-named member properties on the normal pass.
@Suite
struct ImplicitReceiverMemberCallPrecheckTests {
    private func semaContext(sources: [String], useLibrary: Bool) throws -> CompilationContext {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSources(sources, allowDefaultStdlibLibrary: useLibrary)
        try runSema(ctx)
        return ctx
    }

    private func assertNoErrors(_ ctx: CompilationContext, _ label: String) {
        #expect(
            !ctx.diagnostics.hasError,
            "\(label): expected no diagnostics, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test(arguments: [false, true])
    func memberFunctionCallInitializerPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        let declaring = """
        class B {
            val fromMemberFunc = makeInt()
            private fun makeInt(): Int = 42
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.fromMemberFunc
            b.fromMemberFunc.inc()
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func explicitThisMemberCallInitializerPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        let declaring = """
        class B {
            val fromThis = this.makeInt()
            fun makeInt(): Int = 42
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.fromThis
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func inheritedMemberFunctionCallPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        let declaring = """
        open class Base {
            fun baseInt(): Int = 1
        }
        class Derived : Base() {
            val fromBase = baseInt()
        }
        """
        let using = """
        fun f(d: Derived) {
            val i: Int = d.fromBase
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func companionMemberCallPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        let declaring = """
        class B {
            val fromCompanion = compInt()
            companion object {
                fun compInt(): Int = 50
            }
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.fromCompanion
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func memberFunctionShadowsTopLevelFunctionInPrecheck(useLibrary: Bool) throws {
        // The member must win over the same-named top-level function: the
        // published property type has to be the member's return type (Int),
        // not String.
        let declaring = """
        fun shadowed(): String = "s"
        class B {
            val picked = shadowed()
            fun shadowed(): Int = 7
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.picked
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func inapplicableMemberFallsThroughToTopLevelCandidate(useLibrary: Bool) throws {
        // `takesArg()` cannot bind the member that requires an argument, so
        // resolution continues past it to the top-level overload (kotlinc
        // resolves the same); the property is `Int`.
        let declaring = """
        fun takesArg(): Int = 5
        class B {
            val picked = takesArg()
            fun takesArg(x: Int): String = "s"
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.picked
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func memberPropertyInvokeCallPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        // A same-named member *property* shadows the top-level function;
        // `picked()` resolves through `invoke` on `() -> Int`, so `x` is `Int`.
        let declaring = """
        fun picked(): String = "s"
        class B {
            val picked: () -> Int = { 3 }
            val x = picked()
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.x
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func operatorInvokeCallPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        // `handler()` on a class-typed member resolves through the nominal
        // `operator fun invoke`, so `x` publishes `Int` ahead of source order.
        let declaring = """
        class Handler {
            operator fun invoke(): Int = 5
        }
        class B {
            val handler = Handler()
            val x = handler()
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.x
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func chainedInferredPropertyFollowsMemberCallPublication(useLibrary: Bool) throws {
        let declaring = """
        class B {
            val base = makeInt()
            val chained = base + 1
            private fun makeInt(): Int = 40
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.chained
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func accessorBodiedVarWithMemberCallInitializerPublishesTypeAcrossFileOrder(useLibrary: Bool) throws {
        let declaring = """
        class B {
            var size = makeInt()
                set(value) { field = value }
            private fun makeInt(): Int = 9
        }
        """
        let using = """
        fun f(b: B) {
            b.size--
            b.size++
            val i: Int = b.size
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func genericMemberReturnTypePublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        let declaring = """
        class G<T>(val v: T) {
            fun pick(): T = v
            val picked = pick()
        }
        """
        let using = """
        fun f(g: G<Int>) {
            val i: Int = g.picked
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func inferredPropertyTypeIsMemberReturnType(useLibrary: Bool) throws {
        let ctx = try semaContext(sources: [
            """
            class B {
                val fromMemberFunc = makeInt()
                private fun makeInt(): Int = 42
            }
            """,
            """
            fun f(b: B) {
                val i: Int = b.fromMemberFunc
            }
            """,
        ], useLibrary: useLibrary)
        assertNoErrors(ctx, "use-first library=\(useLibrary)")
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(
            fqName: ["B", "fromMemberFunc"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.propertyType(for: symbol) == sema.types.intType)
    }

    // MARK: - KUU-4014: implicit-receiver member calls with arguments

    @Test(arguments: [false, true])
    func innerClassMemberCallWithArgumentsPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        // The ticket repro: an inner-class property inferred from an
        // enclosing-class method that takes arguments. The consumer file
        // checked first must still see `String?`/`String`, not `Any?`.
        let declaring = """
        class Holder {
            fun pub(n: Int): String? = if (n > 0) "x" else null
            fun nonNull(n: Int): String = "v"
            inner class P(val n: Int) {
                val inferred = pub(n)
                val inferredNN = nonNull(n)
                val explicit: String? = pub(n)
            }
        }
        """
        let using = """
        fun c1(p: Holder.P): Int? = p.inferred?.length
        fun c2(p: Holder.P): Int = p.inferredNN.length
        fun c3(p: Holder.P): Int? = p.explicit?.length
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func nullAssertWrappedMemberCallPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        // The markdown shape: `val currentLine = getLine(lineN)!!` — a
        // force-not-null wrapping an implicit-receiver call with arguments.
        let declaring = """
        class Lookahead {
            private fun getLine(n: Int): String? = if (n > 0) "l" else null
            inner class Position(val lineN: Int) {
                val currentLine = getLine(lineN)!!
            }
        }
        """
        let using = """
        fun read(p: Lookahead.Position): Int = p.currentLine.length
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func nestedClassMemberCallWithArgumentsPublishesInferredTypeAcrossFileOrder(useLibrary: Bool) throws {
        // A nested (non-inner) class has no enclosing instance, but its own
        // member call with arguments hits the same implicit-receiver path.
        let declaring = """
        class Outer {
            class Nested(val n: Int) {
                val own = make(n)
                fun make(x: Int): Long = x.toLong()
            }
        }
        """
        let using = """
        fun c(p: Outer.Nested): Long = p.own
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
    }

    @Test(arguments: [false, true])
    func memberFunctionWithArgumentsShadowsTopLevelInPrecheck(useLibrary: Bool) throws {
        // With arguments the member must still win over the same-named
        // top-level function: `picked` has to publish the member's `Int`,
        // not the top-level `String`.
        let declaring = """
        fun pick(n: Int): String = "top"
        class B {
            val picked = pick(1)
            fun pick(n: Int): Int = 7
        }
        """
        let using = """
        fun f(b: B) {
            val i: Int = b.picked
        }
        """
        for sources in [[declaring, using], [using, declaring]] {
            let ctx = try semaContext(sources: sources, useLibrary: useLibrary)
            assertNoErrors(ctx, "order=\(sources[0] == declaring ? "decl-first" : "use-first") library=\(useLibrary)")
        }
        let ctx = try semaContext(sources: [using, declaring], useLibrary: useLibrary)
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(
            fqName: ["B", "picked"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.propertyType(for: symbol) == sema.types.intType)
    }

    @Test(arguments: [false, true])
    func inapplicableMemberWithArgumentsKeepsCallOnNormalPass(useLibrary: Bool) throws {
        // The member `other(Int)` cannot take a String argument, so the
        // precheck must not publish a member-derived type. With the
        // declaration checked first the authoritative pass still resolves
        // the call to the top-level `other(String)` exactly like kotlinc.
        let declaring = """
        fun other(s: String): String = "top"
        class B {
            val picked = other("x")
            fun other(n: Int): Int = 9
        }
        """
        let using = """
        fun f(b: B) {
            val s: String = b.picked
        }
        """
        let ctx = try semaContext(sources: [declaring, using], useLibrary: useLibrary)
        assertNoErrors(ctx, "decl-first library=\(useLibrary)")
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(
            fqName: ["B", "picked"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.propertyType(for: symbol) == sema.types.stringType)
    }
}
