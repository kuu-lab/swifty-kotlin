@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ReifiedEnumValuesLoweringTests {
    enum TokenSource: CaseIterable {
        case parameter, capturedPair, packedCapture, packedValue, unrelatedCall, localPair, componentToken

        var isParameterToken: Bool {
            self == .parameter || self == .capturedPair || self == .packedCapture
        }
    }

    /// Only parameter-derived class tokens may bypass concrete specialization.
    @Test(arguments: TokenSource.allCases, [false, true])
    func tracksCapturedClassToken(source: TokenSource, isInline: Bool) throws {
        let (sema, symbols, types, interner) = makeSemaModule()
        let enumValues = symbols.define(
            kind: .function, name: interner.intern("enumValues"),
            fqName: ["kotlin", "enumValues"].map(interner.intern),
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        sema.wellKnownSymbols = WellKnownSymbols(
            symbols: symbols, interner: interner, sourceManager: SourceManager()
        )
        let arena = KIRArena()
        let parameter = SymbolID(rawValue: 100)
        let root = arena.appendExpr(.symbolRef(parameter), type: types.anyType)
        let extracted = arena.appendTemporary(type: types.intType)
        let token = arena.appendTemporary(type: types.intType)
        let result = arena.appendTemporary(type: types.anyType)
        var body: [KIRInstruction] = [.constValue(result: root, value: .symbolRef(parameter))]
        var input = root
        if source == .packedCapture || source == .packedValue {
            let offset = arena.appendExpr(.intLiteral(2), type: types.intType)
            let packed = arena.appendTemporary(type: types.anyType)
            body.append(.constValue(result: offset, value: .intLiteral(2)))
            body.append(.call(callee: interner.intern("kk_array_get_inbounds"),
                              arguments: [root, offset], result: packed, canThrow: false))
            input = packed
        } else if source == .localPair {
            input = arena.appendTemporary(type: types.anyType)
            let value = arena.appendExpr(.intLiteral(0), type: types.intType)
            body.append(.constValue(result: value, value: .intLiteral(0)))
            body.append(.call(callee: interner.intern("__kk_pair_new"),
                              arguments: [value, value], result: input, canThrow: false))
        }
        if source == .parameter || source == .packedValue {
            body.append(.copy(from: input, to: extracted))
        } else {
            let callee = source == .unrelatedCall ? "unrelated" :
                source == .componentToken ? "__kk_pair_second" : "__kk_pair_first"
            body.append(.call(callee: interner.intern(callee), arguments: [input],
                              result: extracted, canThrow: false))
        }
        // Copies after capture extraction must preserve the token's provenance.
        body.append(.copy(from: extracted, to: token))
        body.append(.call(symbol: enumValues, callee: interner.intern("enumValues"), arguments: [token],
                          result: result, canThrow: false))
        body.append(.returnValue(result))
        let functionID = arena.appendDecl(.function(KIRFunction(
            symbol: SymbolID(rawValue: 101), name: interner.intern("factoryLambda"),
            params: [KIRParameter(symbol: parameter, type: types.anyType)], returnType: types.anyType,
            body: body, isSuspend: false, isInline: isInline
        )))
        let module = KIRModule(files: [], arena: arena)
        let diagnostics = DiagnosticEngine()
        let ctx = makeKIRContext(interner: interner, sema: sema, diagnostics: diagnostics)
        try ReifiedEnumValuesLoweringPass().run(module: module, ctx: ctx)
        let lowered = try #require(arena.decl(functionID)?.function)
        let calls = loweringCalls(in: lowered.body)
        #expect(calls.contains { interner.resolve($0.callee) == "kk_enum_values_for_token" }
                == (source.isParameterToken && !isInline))
        #expect(calls.contains { $0.symbol == enumValues } == (!source.isParameterToken || isInline))
        #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-INL-0001" }
                == !source.isParameterToken)
    }
}
