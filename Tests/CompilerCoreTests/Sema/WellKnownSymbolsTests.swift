#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct WellKnownSymbolsTests {
    private static let fixture = SemaFixture(surface: "well-known symbols")

    @Test
    func resolvesRepresentativeSymbolsByExactSymbolID() throws {
        let (sema, interner) = try Self.fixture.shared()

        let collectionCases: [([String], WellKnownCollectionFactory)] = [
            (["kotlin", "collections", "emptyList"], .emptyList),
            (["kotlin", "collections", "setOfNotNull"], .setOfNotNull),
            (["kotlin", "collections", "mapOf"], .mapOf),
        ]
        for (parts, expected) in collectionCases {
            let symbol = try #require(sema.symbols.lookup(fqName: parts.map(interner.intern)))
            #expect(sema.wellKnownSymbols.collectionFactory(for: symbol) == expected)
        }

        let enumCases: [([String], WellKnownEnumIntrinsic)] = [
            (["kotlin", "enumValues"], .enumValues),
            (["kotlin", "enumValueOf"], .enumValueOf),
            (["kotlin", "enums", "enumEntries"], .enumEntries),
            (["kotlin", "enums", "enumEntriesIntrinsic"], .enumEntriesIntrinsic),
        ]
        for (parts, expected) in enumCases {
            let symbol = try #require(sema.symbols.lookup(fqName: parts.map(interner.intern)))
            #expect(sema.wellKnownSymbols.enumIntrinsic(for: symbol) == expected)
        }

        let sourceBackedFactory = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("listOfNotNull"),
        ]))
        #expect(
            sema.wellKnownSymbols.collectionFactory(for: sourceBackedFactory) == nil,
            "Source-backed listOfNotNull must stay on its Kotlin implementation path"
        )
    }

    @Test
    func userDeclarationsWithWellKnownNamesShadowIntrinsicPaths() throws {
        let source = """
        fun emptyList(): String = "user list"
        fun enumValues(): String = "user enum"
        fun callEmptyList(): String = emptyList()
        fun callEnumValues(): String = enumValues()
        """
        let (sema, interner) = try Self.fixture.make(source: source)

        let userEmptyList = try #require(sema.symbols.lookup(fqName: [interner.intern("emptyList")]))
        let userEnumValues = try #require(sema.symbols.lookup(fqName: [interner.intern("enumValues")]))
        #expect(sema.wellKnownSymbols.collectionFactory(for: userEmptyList) == nil)
        #expect(sema.wellKnownSymbols.enumIntrinsic(for: userEnumValues) == nil)
        #expect(
            sema.bindings.callBindings.values.contains { $0.chosenCallee == userEmptyList },
            "emptyList() should bind to the user declaration"
        )
        #expect(
            sema.bindings.callBindings.values.contains { $0.chosenCallee == userEnumValues },
            "enumValues() should bind to the user declaration"
        )
    }
}
#endif
