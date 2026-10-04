#if canImport(Testing)
@testable import CompilerCore
import Testing

/// An `override` of an `operator fun` inherits the `operator` modifier even
/// without repeating the keyword. Before `OverrideOperatorModifierInheritance`
/// (`Sources/CompilerCore/Sema/DataFlow/OverrideOperatorModifierInheritance.swift`),
/// `.operatorFunction` came only from the declaration's own modifiers, so
/// operator resolution dropped the override and `B() + 1` was rejected with
/// `KSWIFTK-SEMA-0002`.
@Suite
struct OverrideOperatorModifierInheritanceTests {
    @Test
    func overrideWithoutKeywordIsUsableAsOperator() throws {
        let source = """
        open class A { open operator fun plus(n: Int) = n }
        class B : A() { override fun plus(n: Int) = n * 2 }
        fun probe(): Int = B() + 1
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let bPlus = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("B"), ctx.interner.intern("plus")]).first)
        #expect(sema.symbols.symbol(bPlus)?.flags.contains(.operatorFunction) == true)
    }

    @Test
    func modifierPropagatesThroughKeywordlessIntermediateOverrides() throws {
        let source = """
        interface I { operator fun contains(x: Int): Boolean }
        open class A : I { override fun contains(x: Int) = false }
        open class B : A() { override fun contains(x: Int) = x > 0 }
        class C : B() { override fun contains(x: Int) = x % 2 == 0 }
        fun probe(): Boolean = 4 in C() && 1 in B()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        for owner in ["A", "B", "C"] {
            let member = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern(owner), ctx.interner.intern("contains")]).first)
            #expect(sema.symbols.symbol(member)?.flags.contains(.operatorFunction) == true, "\(owner).contains should inherit operator")
        }
    }

    @Test
    func nonOperatorOverrideStaysNonOperator() throws {
        let source = """
        open class A { open fun plus(n: Int) = n }
        class B : A() { override fun plus(n: Int) = n * 2 }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let bPlus = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("B"), ctx.interner.intern("plus")]).first)
        #expect(sema.symbols.symbol(bPlus)?.flags.contains(.operatorFunction) == false)
    }
}
#endif
