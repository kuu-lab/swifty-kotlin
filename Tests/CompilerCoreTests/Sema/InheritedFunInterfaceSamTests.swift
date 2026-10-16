#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

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
