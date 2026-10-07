#if canImport(Testing)
@testable import CompilerCore
import Testing

extension OverloadResolverTests {
    @Test(arguments: [
        ("IntArray", false, true, true),
        ("IntArray", false, false, false),
        ("LongArray", false, true, false),
        ("Array", false, true, false),
        ("List", false, true, false),
        ("Int", false, true, false),
        ("IntArray", true, true, false),
    ])
    func testNamedPrimitiveVarargRequiresCompatibleArray(
        arrayName: String, nullable: Bool, named: Bool, accepted: Bool
    ) {
        let (_, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
        let array = symbols.define(
            kind: .class, name: interner.intern(arrayName),
            fqName: [interner.intern("kotlin"), interner.intern(arrayName)],
            declSite: nil, visibility: .public, flags: []
        )
        let argType = arrayName == "Int" ? types.intType : types.make(.classType(ClassType(
            classSymbol: array,
            args: ["Array", "List"].contains(arrayName) ? [.invariant(types.intType)] : [],
            nullability: nullable ? .nullable : .nonNull
        )))
        let fn = defineSymbol(kind: .function, name: "namedVararg", suffix: "namedVararg", symbols: symbols, interner: interner)
        let xs = defineSymbol(kind: .valueParameter, name: "xs", suffix: "namedVararg_xs", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(FunctionSignature(
            parameterTypes: [types.intType], returnType: types.intType,
            valueParameterSymbols: [xs], valueParameterIsVararg: [true]
        ), for: fn)
        let resolved = OverloadResolver().resolveCall(
            candidates: [fn],
            call: CallExpr(range: makeRange(start: 0, end: 10), calleeName: interner.intern("namedVararg"), args: [
                CallArg(label: named ? interner.intern("xs") : nil, type: argType),
            ]), expectedType: nil, ctx: ctx
        )
        #expect((resolved.chosenCallee == fn) == accepted)
        #expect((resolved.diagnostic == nil) == accepted)
    }

    @Test(arguments: [0, 1, 2])
    func testNamedVarargCannotBePassedTwice(form: Int) {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let fn = defineSymbol(kind: .function, name: "duplicate", suffix: "duplicate", symbols: symbols, interner: interner)
        let xs = defineSymbol(kind: .valueParameter, name: "xs", suffix: "duplicate_xs", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(FunctionSignature(
            parameterTypes: [types.intType], returnType: types.intType,
            valueParameterSymbols: [xs], valueParameterIsVararg: [true]
        ), for: fn)
        let args = [
            CallArg(label: form == 1 ? nil : interner.intern("xs"), isSpread: true, type: types.intType),
            CallArg(label: form == 2 ? nil : interner.intern("xs"), isSpread: true, type: types.intType),
        ]
        let signature = FunctionSignature(
            parameterTypes: [types.intType], returnType: types.intType,
            valueParameterSymbols: [xs], valueParameterIsVararg: [true]
        )
        #expect(resolver.buildParameterMapping(
            signature: signature, callArgs: args, symbols: symbols, typeSystem: types
        ) == nil)
        let resolved = resolver.resolveCall(candidates: [fn], call: CallExpr(
            range: makeRange(start: 0, end: 10), calleeName: interner.intern("duplicate"), args: args
        ), expectedType: nil, ctx: ctx)
        #expect(resolved.chosenCallee == nil)
        #expect(resolved.diagnostic?.code == "KSWIFTK-SEMA-0002")
    }

    @Test func testNamedGenericVarargInfersArrayElementType() {
        let (_, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
        let array = symbols.define(
            kind: .class, name: interner.intern("Array"),
            fqName: [interner.intern("kotlin"), interner.intern("Array")],
            declSite: nil, visibility: .public, flags: []
        )
        let t = defineSymbol(kind: .typeParameter, name: "T", suffix: "namedGeneric_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: t)))
        let fn = defineSymbol(kind: .function, name: "namedGeneric", suffix: "namedGeneric", symbols: symbols, interner: interner)
        let xs = defineSymbol(kind: .valueParameter, name: "xs", suffix: "namedGeneric_xs", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(FunctionSignature(
            parameterTypes: [tType], returnType: tType, valueParameterSymbols: [xs],
            valueParameterIsVararg: [true], typeParameterSymbols: [t]
        ), for: fn)
        let resolved = OverloadResolver().resolveCall(
            candidates: [fn],
            call: CallExpr(range: makeRange(start: 0, end: 10), calleeName: interner.intern("namedGeneric"), args: [
                CallArg(label: interner.intern("xs"), type: types.make(.classType(ClassType(
                    classSymbol: array, args: [.out(types.intType)]
                )))),
            ]), expectedType: nil, ctx: ctx
        )
        #expect(resolved.chosenCallee == fn)
        #expect(resolved.diagnostic == nil)
        #expect(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)] == types.intType)
    }
}
#endif
