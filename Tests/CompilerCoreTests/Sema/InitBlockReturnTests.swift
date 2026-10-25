@testable import CompilerCore
import Foundation
import Testing

@Suite
struct InitBlockReturnTests {
    private func context(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func rejectsReturnInInitBlock() throws {
        let ctx = context("""
        class C { init { return } }
        """)

        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0312", in: ctx)
    }

    @Test func initBlockReturnCannotTargetEnclosingFunction() throws {
        let ctx = context("""
        fun outer() {
            class Local { init { return } }
        }
        """)

        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0312", in: ctx)
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.functionReturnLambdaPaths.isEmpty)
    }

    @Test func nestedLocalFunctionCanReturnFromItsOwnBody() throws {
        let ctx = context("""
        class C {
            init {
                fun helper() { return }
            }
        }
        """)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func initBlockCanReturnToNestedLambdaLabel() throws {
        let ctx = context("""
        inline fun run2(block: () -> Unit) = block()

        class C { init { run2 { return@run2 } } }
        """)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
