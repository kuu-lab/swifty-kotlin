#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JsArraySurfaceTests {
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
                "Expected JsArray surface to resolve cleanly, got: \(diagnostics)"
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

    @Test func testJsArrayClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsArray"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsArray must be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))

        #expect(info.kind == .class)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(
            sema.symbols.parentSymbol(for: symbol) == sema.symbols.lookup(fqName: ["kotlin", "js"].map { interner.intern($0) })
        )
        #expect(sema.symbols.propertyType(for: symbol) != nil)
    }

    @Test func testJsArrayTypeParameterAndSupertypeAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsArray"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: symbol)
        let jsAnySymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsAny"].map { interner.intern($0) })
        )

        #expect(typeParameters.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: symbol) == [.invariant])
        #expect(sema.symbols.symbol(typeParameters[0])?.name == interner.intern("T"))
        #expect(sema.symbols.parentSymbol(for: typeParameters[0]) == symbol)
        #expect(sema.symbols.directSupertypes(for: symbol) == [jsAnySymbol])
    }

    @Test func testJsArrayDoesNotExposeToList() throws {
        let source = """
        import kotlin.js.JsArray

        fun fail(value: JsArray<String>) = value.toList()
        """
        let ctx = runSemaCollectingDiagnostics(source)

        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func testJsArrayCanBeImportedAndUsedAsGenericParameterType() {
        let source = """
        import kotlin.js.JsArray

        fun accept(value: JsArray<String>): JsArray<String> = value
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(errors.isEmpty, "Expected JsArray parameter usage to type-check, got \(errors)")
    }
}
#endif
