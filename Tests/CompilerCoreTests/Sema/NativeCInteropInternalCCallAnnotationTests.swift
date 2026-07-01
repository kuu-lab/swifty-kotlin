#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropInternalCCallAnnotationTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Expected CCall surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func cCallSymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try #require(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "internal", "CCall"].map { interner.intern($0) }),
            "kotlinx.cinterop.internal.CCall must be registered"
        )
    }

    @Test func testCCallIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cCallSymbol(sema: sema, interner: interner)
        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
    }

    @Test func testCCallCarriesFunctionTarget() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cCallSymbol(sema: sema, interner: interner)
        let target = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "CCall must carry @Target metadata"
        )
        #expect(target.arguments == ["AnnotationTarget.FUNCTION"])
    }

    @Test func testCCallCarriesBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cCallSymbol(sema: sema, interner: interner)
        let retention = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "CCall must carry @Retention metadata"
        )
        #expect(retention.arguments == ["AnnotationRetention.BINARY"])
    }

    @Test func testCCallConstructorHasIdStringParameter() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cCallSymbol(sema: sema, interner: interner)
        guard let symbolInfo = sema.symbols.symbol(symbol) else {
            Issue.record("Could not retrieve CCall symbol info")
            return
        }
        let initFQName = symbolInfo.fqName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: initFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        #expect(!constructors.isEmpty, "CCall must have a constructor")
        let constructor = try #require(constructors.first)
        let sig = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(sig.parameterTypes.count == 1)
        #expect(sig.parameterTypes.first == sema.types.stringType)
    }
}
#endif
