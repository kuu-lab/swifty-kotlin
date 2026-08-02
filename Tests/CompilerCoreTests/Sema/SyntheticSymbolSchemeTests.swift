#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SyntheticSymbolSchemeTests {

    /// A property setter accessor must never alias a *different* property's
    /// getter accessor. Regression for the additive `offset - symbol` layout,
    /// where `setter(P)` collided with `getter(P + gap)` once symbol IDs grew
    /// past the getter/setter offset gap, causing a top-level backing-field
    /// getter to be lowered as an unrelated accessor at codegen time.
    @Test
    func setterAndGetterAccessorsNeverCollideAcrossProperties() {
        var seen: [SymbolID: String] = [:]
        for raw in Int32(0)...5000 {
            let property = SymbolID(rawValue: raw)
            let getter = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: property)
            let setter = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: property)

            #expect(getter != setter)
            for (symbol, label) in [(getter, "getter"), (setter, "setter")] {
                if let previous = seen[symbol] {
                    Issue.record("\(label)(\(raw)) aliases \(previous) at \(symbol)")
                }
                seen[symbol] = "\(label)(\(raw))"
            }
        }
    }

    /// All synthetic kinds derived from the same original symbol must be
    /// distinct, and a setter accessor must round-trip back to its property.
    @Test
    func syntheticKindsAreMutuallyDistinctAndSetterRoundTrips() {
        for raw in [Int32(1), 90, 8251, 9251] {
            let symbol = SymbolID(rawValue: raw)
            let derived = [
                SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol),
                SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol),
                SyntheticSymbolScheme.receiverParameterSymbol(for: symbol),
                SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: symbol),
                SyntheticSymbolScheme.defaultMaskSymbol(for: symbol),
                SyntheticSymbolScheme.defaultStubSymbol(for: symbol),
            ]
            #expect(Set(derived).count == derived.count)

            let setter = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol)
            #expect(SyntheticSymbolScheme.isLikelySyntheticSetterAccessor(setter))
            #expect(SyntheticSymbolScheme.originalPropertySymbolFromSetterAccessor(setter) == symbol)

            let getter = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
            #expect(SyntheticSymbolScheme.isLikelySyntheticPropertyAccessor(getter))
            #expect(!SyntheticSymbolScheme.isLikelySyntheticSetterAccessor(getter))
        }
    }
}
#endif
