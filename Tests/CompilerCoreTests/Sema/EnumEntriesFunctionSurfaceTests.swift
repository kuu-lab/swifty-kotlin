#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct EnumEntriesFunctionSurfaceTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "enumEntries surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testEnumEntriesFunctionIsRegisteredUnderKotlinEnums() throws {
        let (sema, interner) = try makeSema()
        let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("enumEntries"),
        ]))
        #expect(sema.symbols.symbol(enumEntriesSymbol)?.kind == .function)
        #expect(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enumEntries"),
        ]) == nil)
    }

    @Test func testEnumEntriesFunctionIsDefaultImportedFromKotlinEnums() throws {
        let source = """
        enum class Color { RED, BLUE }
        fun entries() = enumEntries<Color>()
        """
        let (sema, interner) = try makeSema(source: source)
        let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("enumEntries"),
        ]))
        let entriesFunction = try #require(sema.symbols.lookup(fqName: [
            interner.intern("entries"),
        ]))
        let signature = try #require(sema.symbols.functionSignature(for: entriesFunction))
        guard case .classType = sema.types.kind(of: signature.returnType) else {
            Issue.record("enumEntries<Color>() should return an EnumEntries-like class type"); return
        }
        let callBindingsContains = sema.bindings.callBindings.contains(where: { $0.value.chosenCallee == enumEntriesSymbol })
        #expect(
            callBindingsContains,
            "Unqualified enumEntries<Color>() should bind to kotlin.enums.enumEntries"
        )
    }
}
#endif
