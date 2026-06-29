#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JsEvalFunctionTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected eval synthetic function surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testEvalFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try #require(
            evalSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            ),
            "kotlin.js.eval(String) must be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))

        #expect(info.kind == .function)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: symbol) == sema.symbols.lookup(fqName: packageFQName))
        #expect(sema.symbols.externalLinkName(for: symbol) == nil)
        #expect(signature.parameterTypes == [sema.types.stringType])
        #expect(signature.returnType == sema.types.anyType)
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [false])
    }

    @Test func testEvalParameterIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try #require(
            evalSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            )
        )
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        let parameter = try #require(signature.valueParameterSymbols.first)

        #expect(sema.symbols.symbol(parameter)?.name == interner.intern("expr"))
        #expect(sema.symbols.propertyType(for: parameter) == sema.types.stringType)
        #expect(sema.symbols.parentSymbol(for: parameter) == symbol)
    }

    private func evalSymbol(
        in packageFQName: [InternedString],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = packageFQName + [interner.intern("eval")]
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.parameterTypes == [
                sema.types.stringType,
            ]
        }
    }
}
#endif
