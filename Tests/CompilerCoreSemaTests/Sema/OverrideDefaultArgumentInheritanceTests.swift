#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
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
        let source = KotlinSourceFixtures.classOverrideInheritedDefaultArgument
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
        let source = KotlinSourceFixtures.interfaceOverrideInheritedDefaultArgument
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

    /// KUU-2950 / KT-36188: when an override inherits the same member through
    /// several supertypes, the *first declared* supertype's chain supplies the
    /// default — even when its declaration sits deeper than a later
    /// supertype's. `Impl : A2, B` resolves through `A2` to `A.foo` ("OK" on
    /// the JVM), not to `B.foo`.
    @Test
    func conflictingInheritedDefaultsPickFirstSupertypeChain() throws {
        let source = """
        interface A { fun foo(a: String = "OK"): String }
        interface A2 : A
        interface B { fun foo(a: String = "Fail"): String }
        class Impl : A2, B { override fun foo(a: String) = a }
        fun probe(): String = Impl().foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let aFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("A"), ctx.interner.intern("foo")]).first)
        let implFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Impl"), ctx.interner.intern("foo")]).first)
        #expect(
            sema.symbols.overrideDefaultsBaseSymbol(for: implFoo) == aFoo,
            "Impl.foo should inherit its default through the first-declared supertype A2 -> A"
        )
    }

    @Test
    func conflictingInheritedDefaultsFollowDeclarationOrder() throws {
        let source = """
        interface A { fun foo(a: String = "OK"): String }
        interface A2 : A
        interface B { fun foo(a: String = "Fail"): String }
        class Impl : B, A2 { override fun foo(a: String) = a }
        fun probe(): String = Impl().foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let bFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("B"), ctx.interner.intern("foo")]).first)
        let implFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Impl"), ctx.interner.intern("foo")]).first)
        #expect(
            sema.symbols.overrideDefaultsBaseSymbol(for: implFoo) == bFoo,
            "With B declared first, Impl.foo should inherit B.foo's default"
        )
    }

    @Test
    func conflictingInheritedDefaultsThroughIntermediateInterface() throws {
        let source = """
        interface A { fun foo(a: String = "OK"): String }
        interface A2 : A
        interface B { fun foo(a: String = "Fail"): String }
        interface C : A2, B
        class Impl : C { override fun foo(a: String) = a }
        fun probe(): String = Impl().foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let aFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("A"), ctx.interner.intern("foo")]).first)
        let implFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Impl"), ctx.interner.intern("foo")]).first)
        #expect(sema.symbols.overrideDefaultsBaseSymbol(for: implFoo) == aFoo)
    }

    @Test
    func conflictingInheritedDefaultsResolveThroughAbstractClass() throws {
        let source = """
        interface A { fun foo(a: String = "OK"): String }
        interface A2 : A
        interface B { fun foo(a: String = "Fail"): String }
        abstract class Impl : A2, B
        class Impl2 : Impl() { override fun foo(a: String) = a }
        fun probe(): String = Impl2().foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let aFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("A"), ctx.interner.intern("foo")]).first)
        let impl2Foo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Impl2"), ctx.interner.intern("foo")]).first)
        #expect(sema.symbols.overrideDefaultsBaseSymbol(for: impl2Foo) == aFoo)
    }

    @Test
    func conflictingInheritedDefaultsDescendThroughIntermediateOverride() throws {
        let source = """
        interface A { fun foo(a: String = "OK"): String }
        interface A2 : A { override fun foo(a: String) = a }
        interface B { fun foo(a: String = "Fail"): String }
        class Impl : A2, B { override fun foo(a: String) = a }
        fun probe(): String = Impl().foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let aFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("A"), ctx.interner.intern("foo")]).first)
        let implFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Impl"), ctx.interner.intern("foo")]).first)
        #expect(sema.symbols.overrideDefaultsBaseSymbol(for: implFoo) == aFoo)
    }

    /// An overriding function must not redeclare default parameter values —
    /// kotlinc reports "an overriding function is not allowed to specify
    /// default values for its parameters" whether or not the overridden
    /// declaration has defaults of its own.
    @Test
    func overrideRedeclaringDefaultOverDefaultedBaseIsRejected() throws {
        let ctx = makeContextFromSource("""
        open class A { open fun f(x: Int = 1): Int = x }
        class B : A() { override fun f(x: Int = 2): Int = x }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-DEFAULT-ARGS", in: ctx)
    }

    @Test
    func overrideIntroducingDefaultOverPlainBaseIsRejected() throws {
        let ctx = makeContextFromSource("""
        open class A { open fun g(x: Int): Int = x }
        class B : A() { override fun g(x: Int = 2): Int = x }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-DEFAULT-ARGS", in: ctx)
    }

    @Test
    func interfaceImplementationRedeclaringDefaultIsRejected() throws {
        let ctx = makeContextFromSource("""
        interface Greeter { fun greet(name: String = "World"): String }
        class GreeterImpl : Greeter {
            override fun greet(name: String = "Me") = "Hello, $name!"
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-DEFAULT-ARGS", in: ctx)
    }

    @Test
    func overrideWithOnlySomeParamsDefaultedIsRejected() throws {
        let ctx = makeContextFromSource("""
        open class A { open fun f(a: Int, b: Int = 0): Int = a + b }
        class B : A() { override fun f(a: Int, b: Int = 9): Int = a - b }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-DEFAULT-ARGS", in: ctx)
    }

    @Test
    func nonOverrideFunctionWithDefaultsStillAccepted() throws {
        let ctx = makeContextFromSource("""
        open class A { open fun f(x: Int = 1): Int = x }
        class B : A() { fun g(x: Int = 3): Int = x }
        """)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-DEFAULT-ARGS", in: ctx)
    }

    @Test
    func inheritedDefaultFallsToLaterBranchWhenEarlierHasNone() throws {
        let source = """
        interface A { fun foo(a: String): String }
        interface A2 : A
        interface B { fun foo(a: String = "Fail"): String }
        class Impl : A2, B { override fun foo(a: String) = a }
        fun probe(): String = Impl().foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let bFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("B"), ctx.interner.intern("foo")]).first)
        let implFoo = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Impl"), ctx.interner.intern("foo")]).first)
        #expect(
            sema.symbols.overrideDefaultsBaseSymbol(for: implFoo) == bFoo,
            "A.foo declares no default, so B.foo's applies"
        )
    }
}
#endif
