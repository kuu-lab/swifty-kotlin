enum SyntheticSymbolScheme {
    /// Synthetic symbols derive a stable `SymbolID` from an existing symbol
    /// (a property, function, or type-parameter). All kinds share a single
    /// interleaved band so that distinct `(kind, original)` pairs never collide,
    /// regardless of how large the real symbol space grows:
    ///
    ///     rawValue = -(bandBase + kindCount * original + kindIndex)
    ///
    /// Every value stays in `(-1_000_000, -bandBase]`, clear of real (positive)
    /// symbols, `.invalid` (-1), and synthetic type-parameter symbols
    /// (`<= -1_000_000`, see `HeaderHelpers.syntheticTypeParameterBase`).
    ///
    /// An additive `offset - original` layout (previously used here) cannot stay
    /// collision-free: each kind's band grows downward with `original`, so two
    /// kinds whose offsets differ by less than the symbol count overlap. In
    /// particular a property's setter accessor collided with another property's
    /// getter accessor once symbol IDs exceeded the getter/setter offset gap.
    private static let bandBase: Int32 = 10000
    private static let kindCount: Int32 = 6

    private enum Kind: Int32 {
        case receiver = 0
        case getter = 1
        case setter = 2
        case typeToken = 3
        case mask = 4
        case stub = 5
    }

    private static func makeSymbol(kind: Kind, original: SymbolID) -> SymbolID {
        SymbolID(rawValue: -(bandBase + kindCount * original.rawValue + kind.rawValue))
    }

    private static func decode(_ symbol: SymbolID) -> (kind: Kind, original: SymbolID)? {
        let raw = symbol.rawValue
        guard raw <= -bandBase, raw > -1_000_000 else {
            return nil
        }
        let index = -raw - bandBase
        guard let kind = Kind(rawValue: index % kindCount) else {
            return nil
        }
        return (kind, SymbolID(rawValue: index / kindCount))
    }

    static func defaultStubSymbol(for original: SymbolID) -> SymbolID {
        makeSymbol(kind: .stub, original: original)
    }

    static func defaultMaskSymbol(for original: SymbolID) -> SymbolID {
        makeSymbol(kind: .mask, original: original)
    }

    static func setterValueParameterSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(kind: .mask, original: propertySymbol)
    }

    static func semaSetterValueSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(kind: .stub, original: propertySymbol)
    }

    static func reifiedTypeTokenSymbol(for typeParameterSymbol: SymbolID) -> SymbolID {
        makeSymbol(kind: .typeToken, original: typeParameterSymbol)
    }

    static func receiverParameterSymbol(for functionSymbol: SymbolID) -> SymbolID {
        makeSymbol(kind: .receiver, original: functionSymbol)
    }

    static func propertyGetterAccessorSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(kind: .getter, original: propertySymbol)
    }

    static func propertySetterAccessorSymbol(for propertySymbol: SymbolID) -> SymbolID {
        makeSymbol(kind: .setter, original: propertySymbol)
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
        switch decode(symbol)?.kind {
        case .getter, .setter:
            true
        default:
            false
        }
    }

    /// Returns true when `symbol` is a synthetic setter accessor symbol.
    static func isLikelySyntheticSetterAccessor(_ symbol: SymbolID) -> Bool {
        decode(symbol)?.kind == .setter
    }

    /// Reverse of `propertySetterAccessorSymbol(for:)`: recovers the original
    /// property symbol from a synthetic setter accessor symbol.
    static func originalPropertySymbolFromSetterAccessor(_ setterAccessor: SymbolID) -> SymbolID {
        decode(setterAccessor)?.original ?? .invalid
    }
}
