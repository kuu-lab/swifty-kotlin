#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct KnownCompilerNamesFQNTests {

    @Test(arguments: [[], ["kotlin", "collections"], ["mypkg"], ["mypkg", "nested"], ["kotlin", "other"]])
    func mutableCollectionFamiliesRespectPackage(package: [String]) throws {
        let interner = StringInterner()
        let knownNames = KnownCompilerNames(interner: interner)
        for name in ["MutableSet", "HashSet", "LinkedHashSet", "MutableMap", "HashMap", "LinkedHashMap"] {
            let symbols = SymbolTable()
            let fqName = package.isEmpty ? [] : (package + [name]).map(interner.intern)
            let id = symbols.define(
                kind: .class, name: interner.intern(name), fqName: fqName,
                declSite: nil, visibility: .public, flags: []
            )
            let symbol = try #require(symbols.symbol(id))
            let isSet = name.hasSuffix("Set")
            let expected = package == ["kotlin", "collections"]
                || (package.isEmpty && (isSet || name == "MutableMap"))
            if isSet {
                #expect(knownNames.isMutableSetSymbol(symbol) == expected)
                #expect(knownNames.isSetLikeSymbol(symbol) == expected)
            } else {
                #expect(knownNames.isMutableMapSymbol(symbol) == expected)
                #expect(knownNames.isMapLikeSymbol(symbol) == expected)
            }
            if package.isEmpty {
                let rootID = symbols.define(
                    kind: .class, name: interner.intern(name), fqName: [interner.intern(name)],
                    declSite: nil, visibility: .public, flags: []
                )
                let rootSymbol = try #require(symbols.symbol(rootID))
                #expect(!knownNames.isMutableSetSymbol(rootSymbol))
                #expect(!knownNames.isMutableMapSymbol(rootSymbol))
            }
        }
    }

    @Test(arguments: ["SortedSet", "NavigableSet", "TreeSet", "SortedMap", "NavigableMap", "TreeMap"])
    func javaUtilMutableCollectionFamiliesRemainRecognized(name: String) throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)
        let id = symbols.define(
            kind: .class, name: interner.intern(name),
            fqName: ["java", "util", name].map(interner.intern),
            declSite: nil, visibility: .public, flags: []
        )
        let symbol = try #require(symbols.symbol(id))
        if name.hasSuffix("Set") {
            #expect(knownNames.isMutableSetSymbol(symbol))
            #expect(knownNames.isSetLikeSymbol(symbol))
        } else {
            #expect(knownNames.isMutableMapSymbol(symbol))
            #expect(knownNames.isMapLikeSymbol(symbol))
        }
    }

    @Test func testIsSetLikeSymbolMatchesStdlibSetFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        let stdlibSetSymbol = symbols.define(
            kind: .typeAlias,
            name: interner.intern("Set"),
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Set")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let stdlibSetInfo = symbols.symbol(stdlibSetSymbol)!
        #expect(knownNames.isSetLikeSymbol(stdlibSetInfo),
                      "stdlib Set (kotlin.collections.Set) should be recognized as set-like")
    }

    @Test func testIsSetLikeSymbolMatchesStdlibMutableSetFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        let stdlibMutableSetSymbol = symbols.define(
            kind: .typeAlias,
            name: interner.intern("MutableSet"),
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("MutableSet")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let stdlibMutableSetInfo = symbols.symbol(stdlibMutableSetSymbol)!
        #expect(knownNames.isSetLikeSymbol(stdlibMutableSetInfo),
                      "stdlib MutableSet (kotlin.collections.MutableSet) should be recognized as set-like")
    }

    @Test func testIsSetLikeSymbolRejectsUserDefinedSetWithNonStdlibFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        let userSetSymbol = symbols.define(
            kind: .class,
            name: interner.intern("Set"),
            fqName: [interner.intern("com"), interner.intern("example"), interner.intern("Set")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let userSetInfo = symbols.symbol(userSetSymbol)!
        #expect(!(knownNames.isSetLikeSymbol(userSetInfo)),
                       "User-defined Set (com.example.Set) must NOT be recognized as stdlib set-like")
    }

    @Test func testIsSetLikeSymbolRejectsUserDefinedMutableSetWithNonStdlibFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        let userMutableSetSymbol = symbols.define(
            kind: .class,
            name: interner.intern("MutableSet"),
            fqName: [interner.intern("com"), interner.intern("mylib"), interner.intern("MutableSet")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let userMutableSetInfo = symbols.symbol(userMutableSetSymbol)!
        #expect(!(knownNames.isSetLikeSymbol(userMutableSetInfo)),
                       "User-defined MutableSet (com.mylib.MutableSet) must NOT be recognized as stdlib set-like")
    }

    @Test func testIsSetLikeSymbolAllowsSyntheticSymbolWithoutFQN() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)

        let syntheticSetSymbol = symbols.define(
            kind: .typeAlias,
            name: interner.intern("Set"),
            fqName: [],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let syntheticSetInfo = symbols.symbol(syntheticSetSymbol)!
        #expect(knownNames.isSetLikeSymbol(syntheticSetInfo),
                      "Synthetic Set (no FQN) should still be recognized as set-like via fallback")
    }

    @Test(arguments: ["List", "MutableList"])
    func listLikeSymbolsRequireStdlibOrSyntheticIdentity(name: String) throws {
        let interner = StringInterner()
        let knownNames = KnownCompilerNames(interner: interner)

        let userSymbols = SymbolTable()
        let userID = userSymbols.define(
            kind: .class,
            name: interner.intern(name),
            fqName: [interner.intern(name)],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let userSymbol = try #require(userSymbols.symbol(userID))
        #expect(!knownNames.isConcreteListLikeSymbol(userSymbol))

        let stdlibSymbols = SymbolTable()
        let stdlibID = stdlibSymbols.define(
            kind: .class,
            name: interner.intern(name),
            fqName: ["kotlin", "collections", name].map(interner.intern),
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let stdlibSymbol = try #require(stdlibSymbols.symbol(stdlibID))
        #expect(knownNames.isConcreteListLikeSymbol(stdlibSymbol))

        let syntheticSymbols = SymbolTable()
        let syntheticID = syntheticSymbols.define(
            kind: .class,
            name: interner.intern(name),
            fqName: [],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let syntheticSymbol = try #require(syntheticSymbols.symbol(syntheticID))
        #expect(knownNames.isConcreteListLikeSymbol(syntheticSymbol))
    }

    @Test func testRegexConstructorWithUserDefinedSetDoesNotRouteToSetOverload() {
        let fixture = makeKIRDirectLoweringFixture()
        let interner = fixture.interner
        let types = fixture.types
        let symbols = fixture.symbols
        types.symbolTable = symbols

        let knownNames = KnownCompilerNames(interner: interner)

        let userSetClassSymbol = symbols.define(
            kind: .class,
            name: interner.intern("Set"),
            fqName: [interner.intern("com"), interner.intern("example"), interner.intern("Set")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let userSetType = types.make(.classType(ClassType(
            classSymbol: userSetClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        let stringType = types.stringType

        let regexCallee = interner.intern("Regex")
        let result = fixture.driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
            for: regexCallee,
            argumentCount: 2,
            argumentTypes: [stringType, userSetType],
            interner: interner,
            types: types,
            knownNames: knownNames
        )

        #expect(
            result == KIRRuntimeFunction.regexCreateWithOption.name(in: interner),
            "Regex(String, user-defined-Set) should NOT route to kk_regex_create_with_options"
        )
    }

    @Test func testRegexConstructorWithStdlibSetRoutesToSetOverload() {
        let fixture = makeKIRDirectLoweringFixture()
        let interner = fixture.interner
        let types = fixture.types
        let symbols = fixture.symbols
        types.symbolTable = symbols

        let knownNames = KnownCompilerNames(interner: interner)

        let stdlibSetClassSymbol = symbols.define(
            kind: .class,
            name: interner.intern("Set"),
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Set")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let stdlibSetType = types.make(.classType(ClassType(
            classSymbol: stdlibSetClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        let stringType = types.stringType

        let regexCallee = interner.intern("Regex")
        let result = fixture.driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
            for: regexCallee,
            argumentCount: 2,
            argumentTypes: [stringType, stdlibSetType],
            interner: interner,
            types: types,
            knownNames: knownNames
        )

        #expect(
            result == KIRRuntimeFunction.regexCreateWithOptions.name(in: interner),
            "Regex(String, stdlib-Set) should route to kk_regex_create_with_options"
        )
    }

    @Test func testAtomicArrayClassesAreRuntimeFactorySymbols() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let knownNames = KnownCompilerNames(interner: interner)
        let names = [
            ["kotlin", "concurrent", "AtomicIntArray"],
            ["kotlin", "concurrent", "AtomicLongArray"],
            ["kotlin", "concurrent", "AtomicArray"],
            ["kotlin", "concurrent", "atomics", "AtomicIntArray"],
            ["kotlin", "concurrent", "atomics", "AtomicLongArray"],
            ["kotlin", "concurrent", "atomics", "AtomicArray"],
        ]
        for fqName in names {
            let interned = fqName.map(interner.intern)
            let symbol = symbols.define(
                kind: .class,
                name: interned.last!,
                fqName: interned,
                declSite: nil,
                visibility: .public,
                flags: []
            )
            let info = symbols.symbol(symbol)!
            #expect(
                knownNames.isAtomicScalarFactorySymbol(info),
                Comment(rawValue: fqName.joined(separator: ".") + " constructor must lower as a runtime factory")
            )
        }
    }
}
#endif
