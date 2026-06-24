#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JsBooleanSurfaceTests {
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
                "Expected JsBoolean surface to resolve cleanly, got: \(diagnostics)"
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

    @Test func testJsBooleanClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsBooleanFQName = ["kotlin", "js", "JsBoolean"].map { interner.intern($0) }
        let jsBooleanSymbol = try #require(
            sema.symbols.lookup(fqName: jsBooleanFQName),
            "kotlin.js.JsBoolean must be registered"
        )
        let info = try #require(sema.symbols.symbol(jsBooleanSymbol))

        #expect(info.kind == .class)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.propertyType(for: jsBooleanSymbol) != nil)
        #expect(
            sema.symbols.parentSymbol(for: jsBooleanSymbol) == sema.symbols.lookup(fqName: ["kotlin", "js"].map { interner.intern($0) })
        )
    }

    @Test func testJsBooleanExtendsJsAny() throws {
        let (sema, interner) = try makeSema()
        let jsBooleanSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsBoolean"].map { interner.intern($0) })
        )
        let jsAnySymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsAny"].map { interner.intern($0) })
        )

        #expect(sema.symbols.directSupertypes(for: jsBooleanSymbol) == [jsAnySymbol])
    }

    @Test func testJsBooleanCanBeImportedAndUsedAsParameterType() {
        let source = """
        import kotlin.js.JsBoolean

        fun accept(value: JsBoolean): JsBoolean = value
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(errors.isEmpty, "Expected JsBoolean parameter usage to type-check, got \(errors)")
    }
}
#endif
