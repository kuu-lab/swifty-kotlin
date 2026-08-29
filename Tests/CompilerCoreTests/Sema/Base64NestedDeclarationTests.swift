#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct Base64NestedDeclarationTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema {
            return cached
        }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let pair = try #require(result)
        Self._sharedSema = pair
        return pair
    }

    @Test
    func testDefaultIsNamedCompanionObject() throws {
        let (sema, interner) = try sharedSema()
        let base64FQName = ["kotlin", "io", "encoding", "Base64"].map(interner.intern)
        let base64Symbol = try #require(sema.symbols.lookup(fqName: base64FQName))
        let defaultSymbol = try #require(sema.symbols.lookup(fqName: base64FQName + [interner.intern("Default")]))
        let defaultInfo = try #require(sema.symbols.symbol(defaultSymbol))

        #expect(defaultInfo.kind == .object)
        #expect(defaultInfo.visibility == .public)
        #expect(sema.symbols.companionObjectSymbol(for: base64Symbol) == defaultSymbol)
        #expect(sema.symbols.directSupertypes(for: defaultSymbol).contains(base64Symbol))
        #expect(sema.symbols.externalLinkName(for: defaultSymbol) == nil)
    }

    @Test
    func testDefaultASTRetainsSuperclassConstructorArguments() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let interner = ctx.interner
            let defaultFQName = ["kotlin", "io", "encoding", "Base64", "Default"].map(interner.intern)
            let defaultSymbol = try #require(sema.symbols.lookup(fqName: defaultFQName))
            let defaultDeclID = try #require(
                sema.bindings.declSymbols.first { $0.value == defaultSymbol }?.key
            )
            let defaultDecl = try #require(ast.arena.decl(defaultDeclID))
            guard case let .objectDecl(objectDecl) = defaultDecl else {
                Issue.record("Base64.Default was not lowered from an object declaration")
                return
            }
            #expect(objectDecl.superTypeConstructorArgs.count == 2)
        }
    }

    @Test
    func testPaddingOptionIsPublicNestedEnumWithStableEntries() throws {
        let (sema, interner) = try sharedSema()
        let paddingFQName = ["kotlin", "io", "encoding", "Base64", "PaddingOption"].map(interner.intern)
        let paddingSymbol = try #require(sema.symbols.lookup(fqName: paddingFQName))
        let paddingInfo = try #require(sema.symbols.symbol(paddingSymbol))
        let entryNames = sema.symbols.children(ofFQName: paddingFQName)
            .compactMap { sema.symbols.symbol($0) }
            .filter { $0.kind == .field }
            .sorted { $0.declSite?.start.offset ?? .max < $1.declSite?.start.offset ?? .max }
            .map { interner.resolve($0.name) }

        #expect(paddingInfo.kind == .enumClass)
        #expect(paddingInfo.visibility == .public)
        #expect(entryNames == ["PRESENT", "ABSENT", "PRESENT_OPTIONAL", "ABSENT_OPTIONAL"])
        #expect(sema.symbols.externalLinkName(for: paddingSymbol) == nil)
    }

    @Test
    func testDefaultObjectCanBeExplicitlyTypedInLocalDeclaration() throws {
        let source = """
            import kotlin.io.encoding.Base64
            import kotlin.io.encoding.ExperimentalEncodingApi

            @OptIn(ExperimentalEncodingApi::class)
            fun localDefault() {
                val value: Base64.Default = Base64.Default
            }
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Explicitly-typed Base64.Default local declaration failed: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
#endif
