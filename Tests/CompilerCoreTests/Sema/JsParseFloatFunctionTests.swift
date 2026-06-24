#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JsParseFloatFunctionTests {
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
                "Expected parseFloat synthetic function surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testParseFloatFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try #require(
            parseFloatSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            ),
            "kotlin.js.parseFloat(String, Int) must be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))

        #expect(info.kind == .function)
        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: symbol) == sema.symbols.lookup(fqName: packageFQName))
        #expect(sema.symbols.externalLinkName(for: symbol) == nil)
        #expect(signature.parameterTypes == [sema.types.stringType, sema.types.intType])
        #expect(signature.returnType == sema.types.doubleType)
        #expect(signature.valueParameterHasDefaultValues == [false, true])
        #expect(signature.valueParameterIsVararg == [false, false])
    }

    @Test func testParseFloatParametersAndDeprecatedMetadataAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try #require(
            parseFloatSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            )
        )
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        let sParameter = try #require(signature.valueParameterSymbols.first)
        let radixParameter = try #require(signature.valueParameterSymbols.dropFirst().first)
        let deprecated = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.Deprecated" }
        )

        #expect(sema.symbols.symbol(sParameter)?.name == interner.intern("s"))
        #expect(sema.symbols.propertyType(for: sParameter) == sema.types.stringType)
        #expect(sema.symbols.symbol(radixParameter)?.name == interner.intern("radix"))
        #expect(sema.symbols.propertyType(for: radixParameter) == sema.types.intType)
        #expect(sema.symbols.parentSymbol(for: sParameter) == symbol)
        #expect(sema.symbols.parentSymbol(for: radixParameter) == symbol)
        let hasMessage = deprecated.arguments.contains("message = \"Use toDouble() instead.\"")
        #expect(hasMessage)
        let hasReplaceWith = deprecated.arguments.contains("replaceWith = ReplaceWith(\"s.toDouble()\")")
        #expect(hasReplaceWith)
        let hasLevel = deprecated.arguments.contains("level = DeprecationLevel.ERROR")
        #expect(hasLevel)
    }

    private func parseFloatSymbol(
        in packageFQName: [InternedString],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = packageFQName + [interner.intern("parseFloat")]
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.parameterTypes == [
                sema.types.stringType,
                sema.types.intType,
            ]
        }
    }
}
#endif
