@testable import CompilerCore
import Testing

extension TypeSystemTests {
    @Test(arguments: [TypeVariance.out, .invariant])
    func nominalJoinRespectsVarianceAndBranchOrder(variance: TypeVariance) {
        let types = TypeSystem()
        let result = SymbolID(rawValue: 0)
        let success = SymbolID(rawValue: 1)
        let failure = SymbolID(rawValue: 2)
        let successParameter = SymbolID(rawValue: 3)
        let returnParameter = SymbolID(rawValue: 4)
        let successArgument = types.make(.typeParam(TypeParamType(symbol: successParameter)))
        let returnArgument = types.make(.typeParam(TypeParamType(symbol: returnParameter)))
        types.setNominalTypeParameterVariances([variance], for: result)
        types.setNominalTypeParameterSymbols([successParameter], for: success)
        types.setNominalDirectSupertypes([result], for: success)
        types.setNominalDirectSupertypes([result], for: failure)
        types.setNominalSupertypeTypeArgs([.invariant(successArgument)], for: success, supertype: result)
        types.setNominalSupertypeTypeArgs([.invariant(types.nothingType)], for: failure, supertype: result)

        let successType = types.make(.classType(ClassType(classSymbol: success, args: [.invariant(returnArgument)])))
        let failureType = types.make(.classType(ClassType(classSymbol: failure, args: [])))
        let expected = types.make(.classType(ClassType(classSymbol: result, args: [.invariant(returnArgument)])))
        #expect(types.isSubtype(failureType, expected) == (variance == .out))
        // An invariant position joins the differing lifted arguments
        // covariantly: `Result<R>` ∪ `Result<Nothing>` is `Result<out R>`,
        // matching kotlinc's projection of the common supertype.
        let joined = if variance == .out {
            expected
        } else {
            types.make(.classType(ClassType(classSymbol: result, args: [.out(returnArgument)])))
        }
        #expect(types.lub([failureType, successType]) == joined)
        #expect(types.lub([successType, failureType]) == joined)
        #expect(types.lub([types.makeNullable(failureType), successType]) == types.makeNullable(joined))
    }
}
