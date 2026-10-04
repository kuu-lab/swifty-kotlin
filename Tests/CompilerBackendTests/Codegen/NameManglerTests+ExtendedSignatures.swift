#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension NameManglerTests {
    @Test
    func testMangledSignatureForProperty() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("x"),
            fqName: [interner.intern("x")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setPropertyType(intType, for: sym)

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig == "I")
    }

    @Test
    func testMangledSignatureForPropertyWithoutTypeReturnsUnderscore() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("noProp"),
            fqName: [interner.intern("noProp")],
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

    @Test
    func testMangledSignatureForTypeAlias() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .typeAlias,
            name: interner.intern("MyInt"),
            fqName: [interner.intern("MyInt")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setTypeAliasUnderlyingType(intType, for: sym)

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig == "I")
    }

    @Test
    func testMangledSignatureForTypeAliasWithoutTypeReturnsUnderscore() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .typeAlias,
            name: interner.intern("NoTA"),
            fqName: [interner.intern("NoTA")],
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

    @Test
    func testMangledSignatureForClassReturnsUnderscore() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .class,
            name: interner.intern("C"),
            fqName: [interner.intern("C")],
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

    @Test
    func testMangleFQNameMultipleComponents() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("baz"),
            fqName: [interner.intern("com"), interner.intern("example"), interner.intern("baz")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: #require(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        #expect(result.contains("3com"))
        #expect(result.contains("7example"))
        #expect(result.contains("3baz"))
    }

    @Test
    func testMangledSignatureForSuspendFunction() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("suspendFn"),
            fqName: [interner.intern("suspendFn")],
            declSite: nil,
            visibility: .public,
            flags: .suspendFunction
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: intType, isSuspend: true),
            for: sym
        )

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig.hasPrefix("SF"))
    }

    @Test
    func testMangledSignatureNullableType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("nullProp"),
            fqName: [interner.intern("nullProp")],
            declSite: nil,
            visibility: .public
        )
        let nullableInt = types.make(.primitive(.int, .nullable))
        symbols.setPropertyType(nullableInt, for: sym)

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig.contains("Q<"))
    }

    @Test
    func testMangledSignaturePlatformTypeErasesToNullableEncoding() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("platformProp"),
            fqName: [interner.intern("platformProp")],
            declSite: nil,
            visibility: .public
        )
        let platformInt = types.make(.primitive(.int, .platformType))
        symbols.setPropertyType(platformInt, for: sym)

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig == "Q<I>")
    }

    @Test
    func testMangledSignatureAllPrimitives() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let primitives: [(PrimitiveType, String)] = [
            (.boolean, "Z"), (.char, "C"), (.int, "I"),
            (.long, "J"), (.float, "F"), (.double, "D"),
        ]

        for (prim, expected) in primitives {
            let sym = symbols.define(
                kind: .property,
                name: interner.intern("p_\(prim.rawValue)"),
                fqName: [interner.intern("p_\(prim.rawValue)")],
                declSite: nil,
                visibility: .public
            )
            let type = types.make(.primitive(prim, .nonNull))
            symbols.setPropertyType(type, for: sym)

            let sig = try mangler.mangledSignature(
                for: #require(symbols.symbol(sym)),
                symbols: symbols,
                types: types
            )
            #expect(sig == expected, "Primitive \(prim) should encode to \(expected)")
        }

        let stringSym = symbols.define(
            kind: .property,
            name: interner.intern("p_string"),
            fqName: [interner.intern("p_string")],
            declSite: nil,
            visibility: .public
        )
        symbols.setPropertyType(types.stringType, for: stringSym)
        let stringSig = try mangler.mangledSignature(
            for: #require(symbols.symbol(stringSym)),
            symbols: symbols,
            types: types
        )
        #expect(stringSig == "Lkotlin_String;")
    }

    @Test
    func testMangledSignatureUnitType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("unitFn"),
            fqName: [interner.intern("unitFn")],
            declSite: nil,
            visibility: .public
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: types.unitType),
            for: sym
        )

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig.contains("U"))
    }

    @Test
    func testMangledSignatureNothingType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("nothingFn"),
            fqName: [interner.intern("nothingFn")],
            declSite: nil,
            visibility: .public
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: types.nothingType),
            for: sym
        )

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig.contains("N"))
    }

    @Test
    func testMangledSignatureAnyType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("anyProp"),
            fqName: [interner.intern("anyProp")],
            declSite: nil,
            visibility: .public
        )
        symbols.setPropertyType(types.anyType, for: sym)

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig == "A")
    }

    @Test
    func testMangledSignatureErrorType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("errProp"),
            fqName: [interner.intern("errProp")],
            declSite: nil,
            visibility: .public
        )
        symbols.setPropertyType(types.errorType, for: sym)

        let sig = try mangler.mangledSignature(
            for: #require(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        #expect(sig == "E")
    }
}
#endif
