#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JsDynamicSurfaceTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Dynamic surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are asserted by each test.
        }
        return ctx
    }

    @Test func testDynamicInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "Dynamic"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.Dynamic must be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))

        #expect(info.kind == .interface)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(
            sema.symbols.parentSymbol(for: symbol) == sema.symbols.lookup(fqName: ["kotlin", "js"].map { interner.intern($0) })
        )
    }

    @Test func testDynamicCanBeImportedAndUsedAsParameterType() {
        let source = """
        import kotlin.js.Dynamic

        fun accept(value: Dynamic): Dynamic = value
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(errors.isEmpty, "Expected Dynamic parameter usage to type-check, got \(errors)")
    }
}
#endif
