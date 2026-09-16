#if canImport(Testing)
@testable import CompilerCore
import Testing

struct InlineErasedLambdaABITests {
    @Test
    func detectsOnlyImportedHigherOrderInlineBodies() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        let package = interner.intern("inlineABI")
        let callbackType = types.make(.functionType(FunctionType(
            params: [types.intType],
            returnType: types.intType
        )))

        func define(_ name: String, flags: SymbolFlags) -> SymbolID {
            let internedName = interner.intern(name)
            return symbols.define(
                kind: .function,
                name: internedName,
                fqName: [package, internedName],
                declSite: nil,
                visibility: .public,
                flags: flags
            )
        }

        let importedHOF = define("importedHOF", flags: [.inlineFunction, .importedLibrary])
        let importedNonHOF = define("importedNonHOF", flags: [.inlineFunction, .importedLibrary])
        let localHOF = define("localHOF", flags: [.inlineFunction])
        let sema = makeSemaModule(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics
        ).ctx
        let ctx = makeKIRContext(
            moduleName: "InlineErasedLambdaABI",
            interner: interner,
            sema: sema,
            diagnostics: diagnostics
        )

        let importedHOFTarget = KIRFunction(
            symbol: importedHOF,
            name: interner.intern("importedHOF"),
            params: [KIRParameter(symbol: SymbolID(rawValue: 1), type: callbackType)],
            returnType: types.unitType,
            body: [],
            isSuspend: false,
            isInline: true
        )
        let importedNonHOFTarget = KIRFunction(
            symbol: importedNonHOF,
            name: interner.intern("importedNonHOF"),
            params: [KIRParameter(symbol: SymbolID(rawValue: 2), type: types.intType)],
            returnType: types.unitType,
            body: [],
            isSuspend: false,
            isInline: true
        )
        let localHOFTarget = KIRFunction(
            symbol: localHOF,
            name: interner.intern("localHOF"),
            params: [KIRParameter(symbol: SymbolID(rawValue: 3), type: callbackType)],
            returnType: types.unitType,
            body: [],
            isSuspend: false,
            isInline: true
        )

        #expect(InlineErasedLambdaABI.usesErasedLambdaABI(importedHOFTarget, ctx: ctx))
        #expect(!InlineErasedLambdaABI.usesErasedLambdaABI(importedNonHOFTarget, ctx: ctx))
        #expect(!InlineErasedLambdaABI.usesErasedLambdaABI(localHOFTarget, ctx: ctx))
    }

    @Test
    func preservesPrimitiveNullableAndErasedGenericArgumentBoundaries() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        let genericSymbol = symbols.define(
            kind: .typeParameter,
            name: interner.intern("T"),
            fqName: [interner.intern("inlineABI"), interner.intern("T")],
            declSite: nil,
            visibility: .private
        )
        let genericType = types.make(.typeParam(TypeParamType(symbol: genericSymbol)))
        let nullableIntType = types.makeNullable(types.intType)
        let sema = makeSemaModule(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics
        ).ctx
        let ctx = makeKIRContext(
            moduleName: "InlineErasedLambdaABI",
            interner: interner,
            sema: sema,
            diagnostics: diagnostics
        )
        let module = KIRModule(files: [], arena: arena)
        let lambda = KIRFunction(
            symbol: SymbolID(rawValue: 10),
            name: interner.intern("lambda"),
            params: [
                KIRParameter(symbol: SymbolID(rawValue: 11), type: types.intType),
                KIRParameter(symbol: SymbolID(rawValue: 12), type: nullableIntType),
                KIRParameter(symbol: SymbolID(rawValue: 13), type: genericType),
            ],
            returnType: types.intType,
            body: [],
            isSuspend: false,
            isInline: false
        )
        let erasedArguments = [
            arena.appendTemporary(),
            arena.appendTemporary(),
            arena.appendTemporary(),
        ]
        var body = KIRLoweringEmitContext()
        let unboxedArguments = InlineErasedLambdaABI.unboxErasedLambdaArguments(
            arguments: erasedArguments,
            lambdaFunction: lambda,
            module: module,
            ctx: ctx,
            erasedCallConvention: true,
            into: &body
        )

        #expect(unboxedArguments[0] != erasedArguments[0])
        #expect(unboxedArguments[1] == erasedArguments[1])
        #expect(unboxedArguments[2] == erasedArguments[2])
        #expect(callNames(in: body, interner: interner) == ["kk_unbox_int"])

        let returnedInt = arena.appendExpr(.intLiteral(7), type: types.intType)
        let erasedResult = arena.appendTemporary(type: types.anyType)
        let boxedResult = InlineErasedLambdaABI.boxErasedLambdaResultIfNeeded(
            returnedExpr: returnedInt,
            result: erasedResult,
            module: module,
            ctx: ctx,
            into: &body
        )
        #expect(boxedResult != returnedInt)
        #expect(callNames(in: body, interner: interner).last == "kk_box_int")

        let returnedNullable = arena.appendTemporary(type: nullableIntType)
        let nullableResult = arena.appendTemporary(type: types.anyType)
        let unchanged = InlineErasedLambdaABI.boxErasedLambdaResultIfNeeded(
            returnedExpr: returnedNullable,
            result: nullableResult,
            module: module,
            ctx: ctx,
            into: &body
        )
        #expect(unchanged == returnedNullable)
        #expect(callNames(in: body, interner: interner).filter { $0 == "kk_box_int" }.count == 1)
    }

    @Test
    func reErasesSubstitutedArgumentsAndUnboxesPrimitiveResults() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        let package = interner.intern("inlineABI")
        let genericSymbol = symbols.define(
            kind: .typeParameter,
            name: interner.intern("T"),
            fqName: [package, interner.intern("T")],
            declSite: nil,
            visibility: .private
        )
        let genericType = types.make(.typeParam(TypeParamType(symbol: genericSymbol)))
        let nullableIntType = types.makeNullable(types.intType)
        let callbackType = types.make(.functionType(FunctionType(
            params: [types.intType],
            returnType: types.intType
        )))
        let sema = makeSemaModule(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics
        ).ctx
        let ctx = makeKIRContext(
            moduleName: "InlineErasedLambdaABI",
            interner: interner,
            sema: sema,
            diagnostics: diagnostics
        )
        let module = KIRModule(files: [], arena: arena)
        let callable = arena.appendTemporary(type: callbackType)
        let originalErased = arena.appendTemporary(type: genericType)
        let loweredInt = arena.appendExpr(.intLiteral(2), type: types.intType)
        let nullable = arena.appendExpr(.intLiteral(3), type: nullableIntType)
        var body = KIRLoweringEmitContext()

        let loweredInvokeArguments = InlineErasedLambdaABI.boxSubstitutedErasedArguments(
            originalArguments: [callable, originalErased, nullable],
            loweredArguments: [callable, loweredInt, nullable],
            module: module,
            ctx: ctx,
            into: &body
        )
        #expect(loweredInvokeArguments[0] == callable)
        #expect(loweredInvokeArguments[1] != loweredInt)
        #expect(loweredInvokeArguments[2] == nullable)
        #expect(callNames(in: body, interner: interner) == ["kk_box_int"])

        let target = KIRFunction(
            symbol: SymbolID(rawValue: 20),
            name: interner.intern("acceptErased"),
            params: [
                KIRParameter(symbol: SymbolID(rawValue: 21), type: types.anyType),
                KIRParameter(symbol: SymbolID(rawValue: 22), type: nullableIntType),
                KIRParameter(symbol: SymbolID(rawValue: 23), type: genericType),
            ],
            returnType: types.unitType,
            body: [],
            isSuspend: false,
            isInline: true
        )
        let directArguments = InlineErasedLambdaABI.boxPrimitiveArgumentsForErasedParameters(
            arguments: [loweredInt, nullable, originalErased],
            inlineTarget: target,
            module: module,
            ctx: ctx,
            into: &body
        )
        #expect(directArguments[0] != loweredInt)
        #expect(directArguments[1] == nullable)
        #expect(directArguments[2] == originalErased)
        #expect(callNames(in: body, interner: interner).filter { $0 == "kk_box_int" }.count == 2)

        let originalResult = arena.appendTemporary(type: genericType)
        let loweredResult = arena.appendTemporary(type: types.intType)
        let unboxCallee = InlineErasedLambdaABI.substitutedErasedResultUnboxingCallee(
            originalResult: originalResult,
            loweredResult: loweredResult,
            expectedType: nil,
            module: module,
            ctx: ctx
        )
        #expect(unboxCallee.map { interner.resolve($0) } == "kk_unbox_int")

        let nullableUnboxCallee = InlineErasedLambdaABI.substitutedErasedResultUnboxingCallee(
            originalResult: originalResult,
            loweredResult: loweredResult,
            expectedType: nullableIntType,
            module: module,
            ctx: ctx
        )
        #expect(nullableUnboxCallee == nil)
    }

    @Test
    func unboxesErasedInvokeResultsBeforeFloatingPointOperators() {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let diagnostics = DiagnosticEngine()
        let sema = makeSemaModule(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics
        ).ctx
        let ctx = makeKIRContext(
            moduleName: "InlineErasedLambdaABI",
            interner: interner,
            sema: sema,
            diagnostics: diagnostics
        )
        let module = KIRModule(files: [], arena: arena)
        let invokeResult = arena.appendTemporary()
        let other = arena.appendExpr(.floatLiteral(1), type: types.floatType)
        let invokeCallee = interner.intern("kk_function_invoke")
        var body = KIRLoweringEmitContext([
            .call(
                symbol: nil,
                callee: invokeCallee,
                arguments: [],
                result: invokeResult,
                canThrow: false,
                thrownResult: nil
            ),
        ])

        let normalized = InlineErasedLambdaABI.unboxErasedArithmeticArgumentsIfNeeded(
            callee: interner.intern("kk_op_fadd"),
            arguments: [invokeResult, other],
            module: module,
            ctx: ctx,
            into: &body
        )
        #expect(normalized[0] != invokeResult)
        #expect(normalized[1] == other)
        #expect(callNames(in: body, interner: interner).last == "kk_unbox_float")
    }

    private func callNames(in body: KIRLoweringEmitContext, interner: StringInterner) -> [String] {
        body.instructions.compactMap { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return nil
            }
            return interner.resolve(callee)
        }
    }
}
#endif
