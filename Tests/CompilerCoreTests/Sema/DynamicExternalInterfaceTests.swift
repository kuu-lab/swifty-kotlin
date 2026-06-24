#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct DynamicExternalInterfaceTests {
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
                "Expected Dynamic external interface surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
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
        #expect(sema.symbols.propertyType(for: symbol) != nil)
    }

    @Test func testDynamicIteratorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let dynamicFQName = ["kotlin", "js", "Dynamic"].map { interner.intern($0) }
        let dynamicSymbol = try #require(sema.symbols.lookup(fqName: dynamicFQName))
        let dynamicType = try #require(sema.symbols.propertyType(for: dynamicSymbol))
        let iteratorSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterator"].map { interner.intern($0) })
        )

        let iteratorFunction = try #require(
            sema.symbols.lookupAll(fqName: dynamicFQName + [interner.intern("iterator")]).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      case let .classType(returnType) = sema.types.kind(of: signature.returnType)
                else {
                    return false
                }
                return signature.receiverType == dynamicType
                    && signature.parameterTypes.isEmpty
                    && returnType.classSymbol == iteratorSymbol
                    && returnType.args.count == 1
            },
            "Dynamic.iterator() member must be registered"
        )
        let info = try #require(sema.symbols.symbol(iteratorFunction))

        #expect(info.visibility == .public)
        #expect(info.flags.contains(.synthetic))
        #expect(info.flags.contains(.operatorFunction))
        #expect(sema.symbols.externalLinkName(for: iteratorFunction) == "kk_dynamic_iterator")
    }

    @Test func testDynamicIteratorResolvesFromSource() throws {
        let source = """
        import kotlin.js.Dynamic
        import kotlin.collections.Iterator

        fun iteratorOf(value: Dynamic): Iterator<Dynamic> = value.iterator()
        """
        let (sema, interner) = try makeSema(source: source)

        let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern("iteratorOf")]))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        guard case .classType = sema.types.kind(of: signature.returnType) else {
            Issue.record("iteratorOf should return Iterator<Dynamic>, got \(sema.types.renderType(signature.returnType))"); return
        }
    }
}
#endif
