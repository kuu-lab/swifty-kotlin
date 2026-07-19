#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct NameManglerTests {

    @Test
    func testMangleProducesKKPrefix() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("foo"),
            fqName: [interner.intern("foo")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: sym
        )

        let result = try mangler.mangle(
            moduleName: "TestModule",
            symbol: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types,
            nameResolver: { interner.resolve($0) }
        )
        #expect(result.hasPrefix("_KK_TestModule__"))
    }

    @Test
    func testMangleWithExplicitSignature() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("bar"),
            fqName: [interner.intern("bar")],
            declSite: nil,
            visibility: .public
        )

        let result = try mangler.mangle(
            moduleName: "M",
            symbol: #require(symbols.symbol(sym)),
            signature: "SIG",
            nameResolver: { interner.resolve($0) }
        )
        #expect(result.hasPrefix("_KK_M__"))
        #expect(result.contains("__F__SIG__"))
    }

    @Test
    func testMangleIsDeterministic() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("f"),
            fqName: [interner.intern("f")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: intType),
            for: sym
        )

        let r1 = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            symbols: symbols, types: types, nameResolver: { interner.resolve($0) }
        )
        let r2 = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            symbols: symbols, types: types, nameResolver: { interner.resolve($0) }
        )
        #expect(r1 == r2)
    }

    @Test
    func testMangleContainsHashSuffix() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("test"),
            fqName: [interner.intern("test")],
            declSite: nil,
            visibility: .public
        )

        let result = try mangler.mangle(
            moduleName: "M",
            symbol: #require(symbols.symbol(sym)),
            signature: "_",
            nameResolver: { interner.resolve($0) }
        )
        // Result ends with __<8 hex chars>
        let parts = result.split(separator: "_").filter { !$0.isEmpty }
        let lastPart = try String(#require(parts.last))
        #expect(lastPart.count == 8)
        let hasOnlyHexDigits = lastPart.allSatisfy { $0.isHexDigit }
        #expect(hasOnlyHexDigits)
    }

    @Test
    func testMangleKindCodeForFunction() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("fn"),
            fqName: [interner.intern("fn")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__F__"))
    }

    @Test
    func testMangleKindCodeForClass() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .class,
            name: interner.intern("MyClass"),
            fqName: [interner.intern("MyClass")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__C__"))
    }

    @Test
    func testMangleKindCodeForConstructor() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .constructor,
            name: interner.intern("init"),
            fqName: [interner.intern("MyClass"), interner.intern("init")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__K__"))
    }

    @Test
    func testMangleKindCodeForProperty() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("prop"),
            fqName: [interner.intern("prop")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__P__"))
    }

    @Test
    func testMangleKindCodeForObject() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .object,
            name: interner.intern("Obj"),
            fqName: [interner.intern("Obj")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__O__"))
    }

    @Test
    func testMangleKindCodeForInterface() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .interface,
            name: interner.intern("I"),
            fqName: [interner.intern("I")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__I__"))
    }

    @Test
    func testMangleKindCodeForEnumClass() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .enumClass,
            name: interner.intern("E"),
            fqName: [interner.intern("E")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__E__"))
    }

    @Test
    func testMangleKindCodeForTypeAlias() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .typeAlias,
            name: interner.intern("TA"),
            fqName: [interner.intern("TA")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__T__"))
    }

    @Test
    func testMangleGetterDeclKindOverridesKindCode() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("p"),
            fqName: [interner.intern("p")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", declKind: .getter,
            nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__G__"))
    }

    @Test
    func testMangleSetterDeclKindOverridesKindCode() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("p"),
            fqName: [interner.intern("p")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", declKind: .setter,
            nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("__S__"))
    }

    @Test
    func testMangledSignatureForFunctionWithSignature() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("add"),
            fqName: [interner.intern("add")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType, intType], returnType: intType),
            for: sym
        )

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types,
            nameResolver: { interner.resolve($0) }
        )
        // Should contain encoded function type with Int params
        #expect(sig.contains("I"))
    }

    @Test
    func testEncodeTypeUnboxesValueClassToUnderlyingType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        // Define a value class "Meter" wrapping Int
        let meterSym = symbols.define(
            kind: .class,
            name: interner.intern("Meter"),
            fqName: [interner.intern("Meter")],
            declSite: nil,
            visibility: .public,
            flags: [.valueType]
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setValueClassUnderlyingType(intType, for: meterSym)

        let meterType = types.make(.classType(ClassType(classSymbol: meterSym, args: [], nullability: .nonNull)))
        let encoded = mangler.encodeType(meterType, symbols: symbols, types: types, nameResolver: { interner.resolve($0) })
        // Non-null value class should encode using VC<underlying> notation
        // which contains the underlying type (Int -> "I")
        #expect(encoded == "VC<I>", "Non-null value class should encode as VC<underlying>")
    }

    @Test
    func testEncodeTypeNullableValueClassNotUnboxed() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let meterSym = symbols.define(
            kind: .class,
            name: interner.intern("Meter"),
            fqName: [interner.intern("Meter")],
            declSite: nil,
            visibility: .public,
            flags: [.valueType]
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setValueClassUnderlyingType(intType, for: meterSym)

        let nullableMeterType = types.make(.classType(ClassType(classSymbol: meterSym, args: [], nullability: .nullable)))
        let encoded = mangler.encodeType(nullableMeterType, symbols: symbols, types: types, nameResolver: { interner.resolve($0) })
        // Nullable value class should NOT be unboxed; should contain class name
        #expect(encoded.contains("Meter"))
    }

    @Test
    func testMangledSignatureForFunctionWithValueClassParam() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let meterSym = symbols.define(
            kind: .class,
            name: interner.intern("Meter"),
            fqName: [interner.intern("Meter")],
            declSite: nil,
            visibility: .public,
            flags: [.valueType]
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setValueClassUnderlyingType(intType, for: meterSym)
        let meterType = types.make(.classType(ClassType(classSymbol: meterSym, args: [], nullability: .nonNull)))

        let fnSym = symbols.define(
            kind: .function,
            name: interner.intern("measure"),
            fqName: [interner.intern("measure")],
            declSite: nil,
            visibility: .public
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [meterType], returnType: intType),
            for: fnSym
        )

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(fnSym)),
            symbols: symbols,
            types: types,
            nameResolver: { interner.resolve($0) }
        )
        // With value class unboxing enabled, the mangler encodes the
        // underlying type wrapped in VC<...> to distinguish from the
        // raw primitive type. This prevents signature collisions between
        // e.g. `fun f(Meter)` and `fun f(Int)`.
        #expect(sig.contains("VC<I>"), "Mangled signature should contain VC<underlying> for value class param")
    }

    @Test
    func testMangledSignatureForFunctionWithoutSignatureReturnsUnderscore() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("noSig"),
            fqName: [interner.intern("noSig")],
            declSite: nil,
            visibility: .public
        )

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig == "_")
    }
}
#endif
