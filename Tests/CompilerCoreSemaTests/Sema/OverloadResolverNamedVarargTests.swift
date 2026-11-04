#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
        let (resolver, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
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

    // KUU-4090: Kotlin 1.4+ mixed arguments — once a vararg parameter is
    // filled by name, positional arguments continue at the next parameter in
    // declaration order (`f(keys = arrayOf("a"), 5)` binds `5` to `listener`).
    // `isTrailingLambda` is nil for normalized calls and non-nil for source
    // calls; both must reach the parameter after the named vararg.
    @Test(arguments: [nil, false] as [Bool?])
    func testPositionalAfterNamedVarargBindsNextParameter(isTrailingLambda: Bool?) {
        let (resolver, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
        let array = symbols.define(
            kind: .class, name: interner.intern("Array"),
            fqName: [interner.intern("kotlin"), interner.intern("Array")],
            declSite: nil, visibility: .public, flags: []
        )
        let stringArray = types.make(.classType(ClassType(
            classSymbol: array, args: [.out(types.stringType)], nullability: .nonNull
        )))
        let fn = defineSymbol(
            kind: .function, name: "namedVarargTrailing",
            suffix: "namedVarargTrailing", symbols: symbols, interner: interner
        )
        let keys = defineSymbol(
            kind: .valueParameter, name: "keys",
            suffix: "namedVarargTrailing_keys", symbols: symbols, interner: interner
        )
        let listener = defineSymbol(
            kind: .valueParameter, name: "listener",
            suffix: "namedVarargTrailing_listener", symbols: symbols, interner: interner
        )
        let signature = FunctionSignature(
            parameterTypes: [types.stringType, types.intType], returnType: types.intType,
            valueParameterSymbols: [keys, listener], valueParameterIsVararg: [true, false]
        )
        symbols.setFunctionSignature(signature, for: fn)
        let args = [
            CallArg(label: interner.intern("keys"), type: stringArray),
            CallArg(type: types.intType, isTrailingLambda: isTrailingLambda),
        ]
        #expect(resolver.buildParameterMapping(
            signature: signature, callArgs: args, symbols: symbols, typeSystem: types
        ) == [0: 0, 1: 1])
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: CallExpr(
                range: makeRange(start: 0, end: 10),
                calleeName: interner.intern("namedVarargTrailing"), args: args
            ),
            expectedType: nil, ctx: ctx
        )
        #expect(resolved.chosenCallee == fn)
        #expect(resolved.parameterMapping == [0: 0, 1: 1])
        #expect(resolved.diagnostic == nil)
    }

    @Test func testPositionalAfterNamedSpreadVarargBindsNextParameter() {
        let (resolver, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
        let array = symbols.define(
            kind: .class, name: interner.intern("Array"),
            fqName: [interner.intern("kotlin"), interner.intern("Array")],
            declSite: nil, visibility: .public, flags: []
        )
        let stringArray = types.make(.classType(ClassType(
            classSymbol: array, args: [.out(types.stringType)], nullability: .nonNull
        )))
        let fn = defineSymbol(
            kind: .function, name: "namedSpreadTrailing",
            suffix: "namedSpreadTrailing", symbols: symbols, interner: interner
        )
        let keys = defineSymbol(
            kind: .valueParameter, name: "keys",
            suffix: "namedSpreadTrailing_keys", symbols: symbols, interner: interner
        )
        let listener = defineSymbol(
            kind: .valueParameter, name: "listener",
            suffix: "namedSpreadTrailing_listener", symbols: symbols, interner: interner
        )
        let signature = FunctionSignature(
            parameterTypes: [types.stringType, types.intType], returnType: types.intType,
            valueParameterSymbols: [keys, listener], valueParameterIsVararg: [true, false]
        )
        symbols.setFunctionSignature(signature, for: fn)
        let args = [
            CallArg(label: interner.intern("keys"), isSpread: true, type: stringArray),
            CallArg(type: types.intType, isTrailingLambda: false),
        ]
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: CallExpr(
                range: makeRange(start: 0, end: 10),
                calleeName: interner.intern("namedSpreadTrailing"), args: args
            ),
            expectedType: nil, ctx: ctx
        )
        #expect(resolved.chosenCallee == fn)
        #expect(resolved.parameterMapping == [0: 0, 1: 1])
        #expect(resolved.diagnostic == nil)
    }

    @Test func testMultiplePositionalsAfterNamedVarargFillTrailingParameters() {
        let (resolver, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
        let array = symbols.define(
            kind: .class, name: interner.intern("Array"),
            fqName: [interner.intern("kotlin"), interner.intern("Array")],
            declSite: nil, visibility: .public, flags: []
        )
        let stringArray = types.make(.classType(ClassType(
            classSymbol: array, args: [.out(types.stringType)], nullability: .nonNull
        )))
        let fn = defineSymbol(
            kind: .function, name: "namedVarargTwoTrailing",
            suffix: "namedVarargTwoTrailing", symbols: symbols, interner: interner
        )
        let v = defineSymbol(
            kind: .valueParameter, name: "v",
            suffix: "namedVarargTwoTrailing_v", symbols: symbols, interner: interner
        )
        let a = defineSymbol(
            kind: .valueParameter, name: "a",
            suffix: "namedVarargTwoTrailing_a", symbols: symbols, interner: interner
        )
        let b = defineSymbol(
            kind: .valueParameter, name: "b",
            suffix: "namedVarargTwoTrailing_b", symbols: symbols, interner: interner
        )
        let signature = FunctionSignature(
            parameterTypes: [types.stringType, types.intType, types.intType],
            returnType: types.intType,
            valueParameterSymbols: [v, a, b], valueParameterIsVararg: [true, false, false]
        )
        symbols.setFunctionSignature(signature, for: fn)
        let args = [
            CallArg(label: interner.intern("v"), type: stringArray),
            CallArg(type: types.intType, isTrailingLambda: false),
            CallArg(type: types.intType, isTrailingLambda: false),
        ]
        #expect(resolver.buildParameterMapping(
            signature: signature, callArgs: args, symbols: symbols, typeSystem: types
        ) == [0: 0, 1: 1, 2: 2])
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: CallExpr(
                range: makeRange(start: 0, end: 10),
                calleeName: interner.intern("namedVarargTwoTrailing"), args: args
            ),
            expectedType: nil, ctx: ctx
        )
        #expect(resolved.chosenCallee == fn)
        #expect(resolved.parameterMapping == [0: 0, 1: 1, 2: 2])
    }

    // A positional argument cannot reach past the named vararg when no
    // parameter remains for it — `f(keys = arrayOf("a"), 5, 6)` has no third
    // parameter to absorb `6`.
    @Test func testPositionalAfterNamedVarargRejectsArgumentOverflow() {
        let (resolver, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
        let array = symbols.define(
            kind: .class, name: interner.intern("Array"),
            fqName: [interner.intern("kotlin"), interner.intern("Array")],
            declSite: nil, visibility: .public, flags: []
        )
        let stringArray = types.make(.classType(ClassType(
            classSymbol: array, args: [.out(types.stringType)], nullability: .nonNull
        )))
        let fn = defineSymbol(
            kind: .function, name: "namedVarargOverflow",
            suffix: "namedVarargOverflow", symbols: symbols, interner: interner
        )
        let keys = defineSymbol(
            kind: .valueParameter, name: "keys",
            suffix: "namedVarargOverflow_keys", symbols: symbols, interner: interner
        )
        let listener = defineSymbol(
            kind: .valueParameter, name: "listener",
            suffix: "namedVarargOverflow_listener", symbols: symbols, interner: interner
        )
        let signature = FunctionSignature(
            parameterTypes: [types.stringType, types.intType], returnType: types.intType,
            valueParameterSymbols: [keys, listener], valueParameterIsVararg: [true, false]
        )
        symbols.setFunctionSignature(signature, for: fn)
        let args = [
            CallArg(label: interner.intern("keys"), type: stringArray),
            CallArg(type: types.intType, isTrailingLambda: false),
            CallArg(type: types.intType, isTrailingLambda: false),
        ]
        #expect(resolver.buildParameterMapping(
            signature: signature, callArgs: args, symbols: symbols, typeSystem: types
        ) == nil)
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: CallExpr(
                range: makeRange(start: 0, end: 10),
                calleeName: interner.intern("namedVarargOverflow"), args: args
            ),
            expectedType: nil, ctx: ctx
        )
        #expect(resolved.chosenCallee == nil)
        #expect(resolved.diagnostic?.code == "KSWIFTK-SEMA-0002")
    }

    // A positional argument at the named vararg's own index still cannot bind
    // — `f(listener = 5, "a")` fails the mixed-order rule in kotlinc too.
    @Test func testPositionalAfterNamedLaterParameterStaysRejected() {
        let (resolver, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
        let fn = defineSymbol(
            kind: .function, name: "namedAfterVararg",
            suffix: "namedAfterVararg", symbols: symbols, interner: interner
        )
        let keys = defineSymbol(
            kind: .valueParameter, name: "keys",
            suffix: "namedAfterVararg_keys", symbols: symbols, interner: interner
        )
        let listener = defineSymbol(
            kind: .valueParameter, name: "listener",
            suffix: "namedAfterVararg_listener", symbols: symbols, interner: interner
        )
        let signature = FunctionSignature(
            parameterTypes: [types.stringType, types.intType], returnType: types.intType,
            valueParameterSymbols: [keys, listener], valueParameterIsVararg: [true, false]
        )
        symbols.setFunctionSignature(signature, for: fn)
        let args = [
            CallArg(label: interner.intern("listener"), type: types.intType),
            CallArg(type: types.stringType, isTrailingLambda: false),
        ]
        #expect(resolver.buildParameterMapping(
            signature: signature, callArgs: args, symbols: symbols, typeSystem: types
        ) == nil)
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: CallExpr(
                range: makeRange(start: 0, end: 10),
                calleeName: interner.intern("namedAfterVararg"), args: args
            ),
            expectedType: nil, ctx: ctx
        )
        #expect(resolved.chosenCallee == nil)
        #expect(resolved.diagnostic?.code == "KSWIFTK-SEMA-0002")
    }

    // kotlinc rejects single elements supplied to a vararg in named form;
    // mapping may still succeed but the array-typed constraint must fail.
    @Test func testScalarNamedVarargStillRejectedWhenPositionalsFollow() {
        let (resolver, types, symbols, interner, base) = makeEnv()
        let ctx = SemaModule(
            symbols: symbols, types: types, bindings: base.bindings,
            diagnostics: base.diagnostics, interner: interner
        )
        let fn = defineSymbol(
            kind: .function, name: "scalarNamedVararg",
            suffix: "scalarNamedVararg", symbols: symbols, interner: interner
        )
        let keys = defineSymbol(
            kind: .valueParameter, name: "keys",
            suffix: "scalarNamedVararg_keys", symbols: symbols, interner: interner
        )
        let listener = defineSymbol(
            kind: .valueParameter, name: "listener",
            suffix: "scalarNamedVararg_listener", symbols: symbols, interner: interner
        )
        let signature = FunctionSignature(
            parameterTypes: [types.stringType, types.intType], returnType: types.intType,
            valueParameterSymbols: [keys, listener], valueParameterIsVararg: [true, false]
        )
        symbols.setFunctionSignature(signature, for: fn)
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: CallExpr(
                range: makeRange(start: 0, end: 10),
                calleeName: interner.intern("scalarNamedVararg"),
                args: [
                    CallArg(label: interner.intern("keys"), type: types.stringType),
                    CallArg(type: types.intType, isTrailingLambda: false),
                ]
            ),
            expectedType: nil, ctx: ctx
        )
        #expect(resolved.chosenCallee == nil)
        #expect(resolved.diagnostic != nil)
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
