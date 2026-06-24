#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JsArrayExternalClassTests {
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
                "Expected JsArray external class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
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
        #expect(sema.symbols.propertyType(for: symbol) != nil)
    }

    private func arrayType(element: TypeID, sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let arrayFQName = ["kotlin", "Array"].map { interner.intern($0) }
        let arraySymbol = try #require(sema.symbols.lookup(fqName: arrayFQName))
        return sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(element)],
            nullability: .nonNull
        )))
    }
}
#endif
