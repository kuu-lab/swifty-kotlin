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
}
