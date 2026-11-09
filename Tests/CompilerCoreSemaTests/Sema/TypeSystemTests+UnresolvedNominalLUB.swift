@testable import CompilerCore
import Testing

extension TypeSystemTests {
    @Test
    func nominalLUBUsesInvariantFallbackWhenVarianceMetadataIsMissing() {
        let types = TypeSystem()
        let box = SymbolID(rawValue: 100)
        let module = SymbolID(rawValue: 101)
        let leftArgument = SymbolID(rawValue: 102)
        let rightArgument = SymbolID(rawValue: 103)
        types.setNominalDirectSupertypes([module], for: leftArgument)
        types.setNominalDirectSupertypes([module], for: rightArgument)

        func nominal(_ symbol: SymbolID) -> TypeID {
            types.make(.classType(ClassType(classSymbol: symbol)))
        }
        func applied(_ argument: TypeID) -> TypeID {
            types.make(.classType(ClassType(classSymbol: box, args: [.invariant(argument)])))
        }

        let left = applied(nominal(leftArgument))
        let right = applied(nominal(rightArgument))
        let expected = types.make(.classType(ClassType(
            classSymbol: box,
            args: [.out(nominal(module))]
        )))

        #expect(types.lub([left, right]) == expected)
        #expect(types.lub([right, left]) == expected)
    }
}
