#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct InheritedFunInterfaceSamTests {
    private func context(_ source: String) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path], stdlibLibraryPath: CompilerOptions.defaultStdlibLibraryPath,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test
    func inheritedSingleAbstractFunctionIsSam() throws {
        let ctx = context("""
        interface Base<T> { fun run(x: T): String }
        fun interface Derived : Base<Int>
        fun interface Redeclared : Base<String> { override fun run(x: String): String }
        fun main() {
            val d = Derived { it.toString() }
            val r = Redeclared { it + "?" }
            println(d.run(1) + r.run("a"))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func suspendFunctionTypeSupertypeProvidesInheritedSamMethod() throws {
        let ctx = context("""
        fun interface Foo<P> : suspend (P) -> Unit
        fun make(): Foo<Int> = Foo<Int> { }
        class FooImpl<T> : Foo<T> {
            override suspend fun invoke(p1: T) {}
        }
        fun <P> create2(foo: FooImpl<P>): Foo<P> = foo
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let fooSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Foo")]))
        let method = try #require(TypeCheckHelpers().effectiveSamAbstractMethod(
            for: fooSymbol,
            symbols: sema.symbols,
            types: sema.types
        ))
        let methodSignature = try #require(sema.symbols.functionSignature(for: method))
        #expect(methodSignature.isSuspend)

        let fooIntType = sema.types.make(.classType(ClassType(
            classSymbol: fooSymbol,
            args: [.invariant(sema.types.intType)],
            nullability: .nonNull
        )))
        let samType = try #require(TypeCheckHelpers().samFunctionType(for: fooIntType, sema: sema))
        #expect(samType.isSuspend)
        #expect(samType.params == [sema.types.intType])
        #expect(samType.returnType == sema.types.unitType)

        let suspendFunctionType = sema.types.make(.functionType(FunctionType(
            params: [sema.types.intType],
            returnType: sema.types.unitType,
            isSuspend: true
        )))
        let regularFunctionType = sema.types.make(.functionType(FunctionType(
            params: [sema.types.intType],
            returnType: sema.types.unitType
        )))
        #expect(sema.types.isSubtype(fooIntType, suspendFunctionType))
        #expect(!sema.types.isSubtype(fooIntType, regularFunctionType))
    }

    @Test
    func functionTypeSupertypeContributesSyntheticInvokeToSam() throws {
        let ctx = context("""
        fun interface Foo : () -> Int
        fun main() {
            val foo = Foo { 42 }
            println(foo.invoke())
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitAnyToStringOverrideIsSam() throws {
        let ctx = context("""
        fun interface SomeFun { override fun toString(): String }
        fun box(): String {
            val x = SomeFun { "OK" }
            return x.toString()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitAnyToStringAndAnotherAbstractFunctionIsRejected() throws {
        let ctx = context("""
        fun interface SomeFun {
            override fun toString(): String
            fun run()
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0406" })
    }

    @Test
    func inheritedSecondAbstractFunctionIsRejected() throws {
        let ctx = context("""
        interface A { fun a() }
        interface B { fun b() }
        fun interface Bad : A, B
        fun main() {}
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0406" })
    }

    /// KUU-4360: an intermediate interface's abstract `override` re-declares
    /// the base SAM method — both collapse into a single requirement.
    @Test
    func inheritedAbstractOverrideChainIsSam() throws {
        let ctx = context("""
        interface RG { fun next(): Int }
        class Ch(val s: String)
        fun interface Sampler<out T> { fun sample(g: RG): T }
        interface B : Sampler<Ch> { override fun sample(g: RG): Ch }
        fun interface N : B
        fun main() {
            val n = N { g -> Ch("x") }
            println(n.sample(RGImpl()).s)
        }
        class RGImpl : RG { override fun next(): Int = 1 }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    /// KUU-4360: the collapse must compare signatures after substituting the
    /// intermediate supertype's type arguments — `sample(x: T)` and its
    /// `sample(x: CharSequence)` re-declaration are one requirement.
    @Test
    func substitutedSignatureOverrideChainIsSam() throws {
        let ctx = context("""
        fun interface Sam4<T> { fun sample(x: T): Int }
        interface B4 : Sam4<CharSequence> { override fun sample(x: CharSequence): Int }
        fun interface N4 : B4
        fun main() {}
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    /// KUU-4360: the same abstract signature arriving through two unrelated
    /// super-interfaces is a single requirement on the JVM too.
    @Test
    func diamondSameSignatureIsSam() throws {
        let ctx = context("""
        fun interface I { fun f() }
        fun interface J { fun f() }
        fun interface K : I, J
        fun main() {
            val k = K { println("hi") }
            k.f()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
    }

    /// Same-name members that do not override each other stay distinct
    /// requirements — the interface must still be rejected.
    @Test
    func inheritedOverloadIsRejected() throws {
        let ctx = context("""
        fun interface I { fun f() }
        interface J { fun f(x: Int) }
        fun interface K : I, J
        fun main() {}
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0406" })
    }

    /// A concrete own override satisfies the inherited requirement entirely,
    /// leaving zero abstract functions — kotlinc rejects this shape too.
    @Test
    func concreteOverrideLeavesNoSamIsRejected() throws {
        let ctx = context("""
        interface I { fun f() }
        fun interface M : I { override fun f() {} }
        fun main() {}
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0406" })
    }
}
#endif
