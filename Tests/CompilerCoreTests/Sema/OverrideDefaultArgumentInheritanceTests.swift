#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-655: an `override` inherits the *base* declaration's default
/// parameter values even when the override itself declares none of its own.
/// Before `OverrideDefaultArgumentInheritance`
/// (`Sources/CompilerCore/Sema/DataFlow/OverrideDefaultArgumentInheritance.swift`),
/// `MemberHeaderCollection` built every function's
/// `FunctionSignature.valueParameterHasDefaultValues` purely from that
/// function's own AST parameters, so an omitted-argument call through an
/// override was rejected with `KSWIFTK-SEMA-0002`.
@Suite
struct OverrideDefaultArgumentInheritanceTests {
    @Test
    func classOverrideAcceptsOmittedArgumentThroughBaseType() throws {
        let source = """
        open class A { open fun f(x: Int = 1) = "A$x" }
        class B : A() { override fun f(x: Int) = "B$x" }
        fun probe(): String {
            val a: A = B()
            return a.f() + B().f()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let aFQName = [ctx.interner.intern("A"), ctx.interner.intern("f")]
        let bFQName = [ctx.interner.intern("B"), ctx.interner.intern("f")]
        let aF = try #require(sema.symbols.lookupAll(fqName: aFQName).first)
        let bF = try #require(sema.symbols.lookupAll(fqName: bFQName).first)

        let aSig = try #require(sema.symbols.functionSignature(for: aF))
        let bSig = try #require(sema.symbols.functionSignature(for: bF))
        #expect(aSig.valueParameterHasDefaultValues == [true], "Got: \(aSig.valueParameterHasDefaultValues)")
        #expect(
            bSig.valueParameterHasDefaultValues == aSig.valueParameterHasDefaultValues,
            "B.f should have inherited A.f's default-value flags, got: \(bSig.valueParameterHasDefaultValues)"
        )
        #expect(
            sema.symbols.overrideDefaultsBaseSymbol(for: bF) == aF,
            "B.f should link to A.f as its defaults-owning base"
        )
        #expect(
            sema.symbols.overrideDefaultsBaseSymbol(for: aF) == nil,
            "A.f owns its own defaults and should not carry an inheritance link"
        )
    }

    @Test
    func interfaceOverrideAcceptsOmittedArgument() throws {
        let source = """
        interface I { fun m(x: Int = 5): String }
        class IC : I { override fun m(x: Int) = "IC$x" }
        fun probe(): String {
            val i: I = IC()
            return i.m() + IC().m()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func threeLevelChainInheritsFromTopmostDeclaration() throws {
        let source = """
        open class A { open fun f(x: Int = 1) = "A$x" }
        open class B : A() { override fun f(x: Int) = "B$x" }
        class C : B() { override fun f(x: Int) = "C$x" }
        fun probe(): String = C().f()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let aF = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("A"), ctx.interner.intern("f")]).first)
        let bF = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("B"), ctx.interner.intern("f")]).first)
        let cF = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("C"), ctx.interner.intern("f")]).first)
        #expect(sema.symbols.overrideDefaultsBaseSymbol(for: bF) == aF)
        #expect(
            sema.symbols.overrideDefaultsBaseSymbol(for: cF) == aF,
            "C.f must resolve through B.f (which has no defaults of its own) to A.f, not stop at B.f"
        )
    }

    @Test
    func byDelegationForwarderInheritsDefaults() throws {
        let source = """
        interface Greeter { fun greet(name: String = "World"): String }
        class GreeterImpl : Greeter {
            override fun greet(name: String) = "Hello, $name!"
        }
        class Wrapper(impl: Greeter) : Greeter by impl
        fun probe(): String = Wrapper(GreeterImpl()).greet()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
