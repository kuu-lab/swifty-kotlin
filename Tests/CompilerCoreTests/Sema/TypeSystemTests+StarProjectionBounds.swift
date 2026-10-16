@testable import CompilerCore
import Testing

extension TypeSystemTests {
    @Test
    func covariantStarSupertypeLiftingUsesAllDeclaredUpperBounds() {
        let types = TypeSystem()
        let base = SymbolID(rawValue: 1600)
        let child = SymbolID(rawValue: 1601)
        let baseParameter = SymbolID(rawValue: 1602)
        let childParameter = SymbolID(rawValue: 1603)
        let marker = SymbolID(rawValue: 1604)
        let secondBound = SymbolID(rawValue: 1605)
        let unrelated = SymbolID(rawValue: 1606)

        func nominal(_ symbol: SymbolID) -> TypeID {
            types.make(.classType(ClassType(classSymbol: symbol)))
        }

        types.setNominalTypeParameterSymbols([baseParameter], for: base)
        types.setNominalTypeParameterVariances([.out], for: base)
        types.setNominalTypeParameterSymbols([childParameter], for: child)
        types.setNominalTypeParameterVariances([.out], for: child)
        types.setNominalTypeParameterUpperBounds([[nominal(marker), nominal(secondBound)]], for: child)
        types.setNominalDirectSupertypes([base], for: child)
        let childParameterType = types.make(.typeParam(TypeParamType(symbol: childParameter)))
        types.setNominalSupertypeTypeArgs([.invariant(childParameterType)], for: child, supertype: base)

        let projectedChild = types.make(.classType(ClassType(classSymbol: child, args: [.star])))
        let baseWithBound = types.make(.classType(ClassType(classSymbol: base, args: [.invariant(nominal(marker))])))
        let baseWithSecondBound = types.make(.classType(ClassType(classSymbol: base, args: [.invariant(nominal(secondBound))])))
        let baseWithUnrelatedArgument = types.make(.classType(ClassType(classSymbol: base, args: [.invariant(nominal(unrelated))])))

        #expect(types.isSubtype(projectedChild, baseWithBound))
        #expect(types.isSubtype(projectedChild, baseWithSecondBound))
        #expect(!types.isSubtype(projectedChild, baseWithUnrelatedArgument))
    }
}
