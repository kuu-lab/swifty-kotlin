#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
        enum class Direction { NORTH, SOUTH }
        fun <T : Enum<T>> enumEntries(): String = "user entries"
        fun callEmptyList(): String = emptyList()
        fun callEnumValues(): String = enumValues()
        fun callEnumEntries(): String = enumEntries<Direction>()
        """
        let (sema, interner) = try Self.fixture.make(source: source)

        let userEmptyList = try #require(sema.symbols.lookup(fqName: [interner.intern("emptyList")]))
        let userEnumValues = try #require(sema.symbols.lookup(fqName: [interner.intern("enumValues")]))
        let userEnumEntries = try #require(sema.symbols.lookup(fqName: [interner.intern("enumEntries")]))
        #expect(sema.wellKnownSymbols.collectionFactory(for: userEmptyList) == nil)
        #expect(sema.wellKnownSymbols.enumIntrinsic(for: userEnumValues) == nil)
        #expect(sema.wellKnownSymbols.enumIntrinsic(for: userEnumEntries) == nil)
        #expect(
            sema.bindings.callBindings.values.contains { $0.chosenCallee == userEmptyList },
            "emptyList() should bind to the user declaration"
        )
        #expect(
            sema.bindings.callBindings.values.contains { $0.chosenCallee == userEnumValues },
            "enumValues() should bind to the user declaration"
        )
        #expect(
            sema.bindings.callBindings.values.contains { $0.chosenCallee == userEnumEntries },
            "enumEntries<Direction>() should bind to the user declaration when no explicit import is present"
        )
    }

    @Test
    func explicitImportOfEnumEntriesWinsOverSameNameUserDeclaration() throws {
        let source = """
        import kotlin.enums.enumEntries
        enum class Color { RED, GREEN, BLUE }
        fun <T : Enum<T>> enumEntries(): String = "USER_ENTRIES"
        fun useEntries() = enumEntries<Color>()
        """
        let (sema, interner) = try Self.fixture.make(source: source)

        let importedEnumEntries = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"), interner.intern("enums"), interner.intern("enumEntries"),
        ]))
        let userEnumEntries = try #require(sema.symbols.lookup(fqName: [interner.intern("enumEntries")]))
        let specialCall = try #require(sema.bindings.callBindings.first { id, binding in
            sema.bindings.stdlibSpecialCallKind(for: id) == .enumEntries
                && binding.chosenCallee == importedEnumEntries
        })
        #expect(specialCall.value.chosenCallee == importedEnumEntries)
        #expect(specialCall.value.chosenCallee != userEnumEntries)
    }

    @Test
    func importAliasesOfEnumIntrinsicsStayOnIntrinsicPath() throws {
        let source = """
        import kotlin.enumValueOf as evo
        import kotlin.enums.enumEntries as ee
        enum class Direction { NORTH, SOUTH }
        fun south(): Direction = evo<Direction>("SOUTH")
        fun entries() = ee<Direction>()
        """
        let (sema, interner) = try Self.fixture.make(source: source)

        let valueOfSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"), interner.intern("enumValueOf"),
        ]))
        let entriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"), interner.intern("enums"), interner.intern("enumEntries"),
        ]))
        #expect(
            sema.bindings.callBindings.contains {
                sema.bindings.stdlibSpecialCallKind(for: $0.key) == .enumValueOf
                    && $0.value.chosenCallee == valueOfSymbol
            },
            "evo<Direction>(...) must take the enumValueOf intrinsic path"
        )
        #expect(
            sema.bindings.callBindings.contains {
                sema.bindings.stdlibSpecialCallKind(for: $0.key) == .enumEntries
                    && $0.value.chosenCallee == entriesSymbol
            },
            "ee<Direction>() must take the enumEntries intrinsic path"
        )
    }

    @Test
    func fullyQualifiedEnumCollectionCallsStayOnIntrinsicPath() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun values() = kotlin.enumValues<Direction>()
        fun entries() = kotlin.enums.enumEntries<Direction>()
        """
        let (sema, interner) = try Self.fixture.make(source: source)

        let valuesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"), interner.intern("enumValues"),
        ]))
        let entriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"), interner.intern("enums"), interner.intern("enumEntries"),
        ]))
        #expect(
            sema.bindings.callBindings.contains {
                sema.bindings.stdlibSpecialCallKind(for: $0.key) == .enumValues
                    && $0.value.chosenCallee == valuesSymbol
            },
            "kotlin.enumValues<Direction>() must take the enumValues intrinsic path"
        )
        #expect(
            sema.bindings.callBindings.contains {
                sema.bindings.stdlibSpecialCallKind(for: $0.key) == .enumEntries
                    && $0.value.chosenCallee == entriesSymbol
            },
            "kotlin.enums.enumEntries<Direction>() must take the enumEntries intrinsic path"
        )
    }
}
#endif
