#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct EnumAPISurfaceInventoryTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Enum surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testEnumEntriesInterfaceIsRegisteredUnderKotlinEnums() throws {
        let (sema, interner) = try makeSema()
        let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]))
        #expect(sema.symbols.symbol(enumEntriesSymbol)?.kind == .interface)
        #expect(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("EnumEntries"),
        ]) == nil)
    }

    @Test func testEnumEntriesFunctionReturnsKotlinEnumsEnumEntries() throws {
        let (sema, interner) = try makeSema()
        let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]))
        let functionSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("enumEntries"),
        ]))
        let signature = try #require(sema.symbols.functionSignature(for: functionSymbol))
        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            Issue.record("enumEntries<T>() should return EnumEntries<T>"); return
        }
        #expect(returnClassType.classSymbol == enumEntriesSymbol)
        #expect(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enumEntries"),
        ]) == nil)
    }

    @Test func testEnumEntriesCompanionPropertyUsesKotlinEnumsEnumEntries() throws {
        let source = """
        enum class Color { RED, BLUE }
        fun noop() {}
        """
        let (sema, interner) = try makeSema(source: source)
        let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]))
        let entriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("Color"),
            interner.intern("Companion"),
            interner.intern("entries"),
        ]))
        let entriesType = try #require(sema.symbols.propertyType(for: entriesSymbol))
        guard case let .classType(entriesClassType) = sema.types.kind(of: entriesType) else {
            Issue.record("Color.entries should have EnumEntries<Color> type"); return
        }
        #expect(entriesClassType.classSymbol == enumEntriesSymbol)
    }
}
#endif
