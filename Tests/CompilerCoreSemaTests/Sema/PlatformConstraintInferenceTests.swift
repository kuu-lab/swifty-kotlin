#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PlatformConstraintInferenceTests {
    @Test(arguments: [Nullability.nonNull, .nullable, .platformType])
    func platformFunctionParameterInfersInputType(actualNullability: Nullability) {
        let result = resolve(actualNullability: actualNullability, expectedNullability: .platformType)
        #expect(result.resolved.chosenCallee == result.candidate)
        #expect(result.resolved.diagnostic == nil)
        #expect(result.resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)] == result.inputType)
    }

    @Test
    func platformFunctionValueInfersNonNullTargetInputType() {
        let result = resolve(actualNullability: .platformType, expectedNullability: .nonNull)
        #expect(result.resolved.chosenCallee == result.candidate)
        #expect(result.resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)] == result.inputType)
    }

    @Test
    func nullableFunctionValueStillRejectsNonNullTarget() {
        let result = resolve(actualNullability: .nullable, expectedNullability: .nonNull)
        #expect(result.resolved.chosenCallee == nil)
        #expect(result.resolved.diagnostic != nil)
    }

    @Test
    func platformFunctionParameterStillRejectsConcreteInputMismatch() {
        let result = resolve(actualNullability: .nonNull, expectedNullability: .platformType, mismatchedExplicitArgument: true)
        #expect(result.resolved.chosenCallee == nil)
        #expect(result.resolved.diagnostic != nil)
    }

    @Test(arguments: [Nullability.nonNull, .nullable, .platformType])
    func platformNominalParameterInfersArgumentType(actualNullability: Nullability) {
        let result = resolveNominal(actualNullability: actualNullability, expectedNullability: .platformType)
        #expect(result.resolved.chosenCallee == result.candidate)
        #expect(result.resolved.diagnostic == nil)
        #expect(result.resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)] == result.inputType)
    }

    @Test
    func platformNominalResultInfersFromNonNullExpectedType() {
        let result = resolveNominal(actualNullability: .platformType, expectedNullability: .nonNull, inferFromResult: true)
        #expect(result.resolved.chosenCallee == result.candidate)
        #expect(result.resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)] == result.inputType)
    }

    @Test
    func nullableNominalValueStillRejectsNonNullTarget() {
        let result = resolveNominal(actualNullability: .nullable, expectedNullability: .nonNull)
        #expect(result.resolved.chosenCallee == nil)
        #expect(result.resolved.diagnostic != nil)
    }

    @Test
    func platformNominalParameterStillRejectsExplicitMismatch() {
        let result = resolveNominal(actualNullability: .nonNull, expectedNullability: .platformType, mismatchedExplicitArgument: true)
        #expect(result.resolved.chosenCallee == nil)
        #expect(result.resolved.diagnostic != nil)
    }

    private func resolve(
        actualNullability: Nullability,
        expectedNullability: Nullability,
        mismatchedExplicitArgument: Bool = false
    ) -> (resolved: ResolvedCall, candidate: SymbolID, inputType: TypeID) {
        let setup = makeSemaModule()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner
        let parameter = symbols.define(kind: .typeParameter, name: interner.intern("T"), fqName: [interner.intern("T")], declSite: nil, visibility: .public)
        let parameterType = types.make(.typeParam(TypeParamType(symbol: parameter, nullability: .nonNull)))
        let candidate = symbols.define(kind: .function, name: interner.intern("extract"), fqName: [interner.intern("extract")], declSite: nil, visibility: .public)
        let expectedFunction = types.make(.functionType(FunctionType(
            params: [parameterType], returnType: types.intType, nullability: expectedNullability
        )))
        symbols.setFunctionSignature(FunctionSignature(
            parameterTypes: [expectedFunction], returnType: parameterType, typeParameterSymbols: [parameter]
        ), for: candidate)
        let inputType = types.stringType
        let actualFunction = types.make(.functionType(FunctionType(
            params: [inputType], returnType: types.intType, nullability: actualNullability
        )))
        let call = CallExpr(
            range: makeRange(start: 1, end: 5), calleeName: interner.intern("extract"),
            args: [CallArg(type: actualFunction)], explicitTypeArgs: mismatchedExplicitArgument ? [types.intType] : []
        )
        let resolved = OverloadResolver().resolveCall(candidates: [candidate], call: call, expectedType: nil, ctx: setup.ctx)
        return (resolved, candidate, inputType)
    }
    private func resolveNominal(
        actualNullability: Nullability,
        expectedNullability: Nullability,
        inferFromResult: Bool = false,
        mismatchedExplicitArgument: Bool = false
    ) -> (resolved: ResolvedCall, candidate: SymbolID, inputType: TypeID) {
        let setup = makeSemaModule()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner
        let parameter = symbols.define(kind: .typeParameter, name: interner.intern("T"), fqName: [interner.intern("T")], declSite: nil, visibility: .public)
        let parameterType = types.make(.typeParam(TypeParamType(symbol: parameter, nullability: .nonNull)))
        let box = symbols.define(kind: .class, name: interner.intern("Box"), fqName: [interner.intern("Box")], declSite: nil, visibility: .public)
        func boxed(_ argument: TypeID, _ nullability: Nullability) -> TypeID {
            types.make(.classType(ClassType(classSymbol: box, args: [.invariant(argument)], nullability: nullability)))
        }
        let candidate = symbols.define(kind: .function, name: interner.intern("extract"), fqName: [interner.intern("extract")], declSite: nil, visibility: .public)
        symbols.setFunctionSignature(FunctionSignature(
            parameterTypes: inferFromResult ? [] : [boxed(parameterType, expectedNullability)],
            returnType: inferFromResult ? boxed(parameterType, actualNullability) : parameterType,
            typeParameterSymbols: [parameter]
        ), for: candidate)
        let inputType = types.stringType
        let call = CallExpr(
            range: makeRange(start: 1, end: 5), calleeName: interner.intern("extract"),
            args: inferFromResult ? [] : [CallArg(type: boxed(inputType, actualNullability))],
            explicitTypeArgs: mismatchedExplicitArgument ? [types.intType] : []
        )
        let resolved = OverloadResolver().resolveCall(
            candidates: [candidate], call: call,
            expectedType: inferFromResult ? boxed(inputType, expectedNullability) : nil, ctx: setup.ctx
        )
        return (resolved, candidate, inputType)
    }
}
#endif
