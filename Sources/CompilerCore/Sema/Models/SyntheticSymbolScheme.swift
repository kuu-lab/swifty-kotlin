enum SyntheticSymbolScheme {
    static let defaultStubOffset: Int32 = -40000
    static let defaultMaskOffset: Int32 = -30000
    static let typeTokenOffset: Int32 = -20000
    static let propertySetterAccessorOffset: Int32 = -13000
    static let propertyGetterAccessorOffset: Int32 = -12000
    static let receiverParameterOffset: Int32 = -10000

    private static func makeSymbol(offset: Int32, original: SymbolID) -> SymbolID {
        SymbolID(rawValue: offset - original.rawValue)
    }

    static func defaultStubSymbol(for original: SymbolID) -> SymbolID {
        makeSymbol(offset: defaultStubOffset, original: original)
    }

    static func defaultMaskSymbol(for original: SymbolID) -> SymbolID {
        makeSymbol(offset: defaultMaskOffset, original: original)
    }

    static func setterValueParameterSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: defaultMaskOffset, original: propertySymbol)
    }

    static func semaSetterValueSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: defaultStubOffset, original: propertySymbol)
    }

    static func reifiedTypeTokenSymbol(for typeParameterSymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: typeTokenOffset, original: typeParameterSymbol)
    }

    static func receiverParameterSymbol(for functionSymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: receiverParameterOffset, original: functionSymbol)
    }

    static func propertyGetterAccessorSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: propertyGetterAccessorOffset, original: propertySymbol)
    }

    static func propertySetterAccessorSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(offset: propertySetterAccessorOffset, original: propertySymbol)
    }

    static func propertyAccessorSymbol(
        for propertySymbol: SymbolID,
        kind: PropertyAccessorKind
    ) -> SymbolID {
        switch kind {
        case .getter:
            propertyGetterAccessorSymbol(for: propertySymbol)
        case .setter:
            propertySetterAccessorSymbol(for: propertySymbol)
        }
    }

    /// Preserves the historical heuristic used by ABI lowering to classify
    /// synthetic accessor call symbols as non-throwing.
    static func isLikelySyntheticPropertyAccessor(_ symbol: SymbolID) -> Bool {
        let raw = symbol.rawValue
        return raw <= propertyGetterAccessorOffset && raw > typeTokenOffset
    }

    /// Returns true when `symbol` is a synthetic setter accessor symbol
    /// (raw value in the setter accessor range, below getter accessor offset).
    static func isLikelySyntheticSetterAccessor(_ symbol: SymbolID) -> Bool {
        let raw = symbol.rawValue
        return raw < propertyGetterAccessorOffset && raw > typeTokenOffset
    }

    /// Reverse of `propertySetterAccessorSymbol(for:)`: recovers the original
    /// property symbol from a synthetic setter accessor symbol.
    static func originalPropertySymbolFromSetterAccessor(_ setterAccessor: SymbolID) -> SymbolID {
        SymbolID(rawValue: propertySetterAccessorOffset - setterAccessor.rawValue)
    }

    /// Symbol for the `index`-th synthetic parameter of a stdlib delegate
    /// factory's trailing lambda (`property`/`old`/`new` for
    /// `Delegates.observable`/`vetoable`; unused for `lazy`, which has none).
    /// Shared between Sema (`typeCheckDelegate`, which binds these names as
    /// locals so bare references elsewhere in the body -- including to other
    /// outer instance fields, BUG-170 -- get resolved at all) and KIR lowering
    /// (`lowerDelegateLambdaBody`, which allocates the actual KIR parameters):
    /// both sides must compute the identical symbol for a binding made by one
    /// to be visible to the other.
    static func delegateLambdaParamSymbol(for propertySymbol: SymbolID, index: Int) -> SymbolID {
        SymbolID(rawValue: -(propertySymbol.rawValue + Int32(index + 1) * 1000 + 50000))
    }
}
