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
            symbols: sema.symbols
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
}
#endif
