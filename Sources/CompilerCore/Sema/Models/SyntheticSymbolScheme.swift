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
    /// Originals are also allowed to be synthetic themselves — a reified type
    /// token is derived from a metadata type-parameter symbol, which is already
    /// negative. Those pairs get the same interleaved layout in a second band
    /// (`mirrorBandBase`) keyed by the original's magnitude, because negating a
    /// negative original would produce a *positive* rawValue aliasing a real
    /// symbol.
    ///
    /// An additive `offset - original` layout (previously used here) cannot stay
    /// collision-free: each kind's band grows downward with `original`, so two
    /// kinds whose offsets differ by less than the symbol count overlap. In
    /// particular a property's setter accessor collided with another property's
    /// getter accessor once symbol IDs exceeded the getter/setter offset gap.
    private static let bandBase: Int32 = 10000
    private static let kindCount: Int32 = 9
    /// Exclusive lower end of the band. Values at or below it belong to other
    /// synthetic families (type parameters, lambda parameters), so an original
    /// symbol large enough to push its derived symbols past this limit must not
    /// be encoded silently.
    private static let bandLimit: Int32 = 1_000_000

    /// Largest original symbol the band can encode. Beyond it the derived
    /// symbols would leave the band and alias another synthetic family.
    static let maxOriginalRawValue: Int32 = (bandLimit - bandBase) / kindCount - 1

    /// Band for negative (already synthetic) originals. It starts far below
    /// every other synthetic family so the two bands cannot meet.
    private static let mirrorBandBase: Int32 = 1_000_000_000

    /// Largest magnitude a negative original may have before its derived
    /// symbols would overflow `Int32`.
    static let maxMirrorOriginalMagnitude: Int32 = (Int32.max - mirrorBandBase) / kindCount - 1

    private enum Kind: Int32 {
        case receiver = 0
        case getter = 1
        case setter = 2
        case typeToken = 3
        case mask = 4
        case stub = 5
        case delegateLambdaParameter0 = 6
        case delegateLambdaParameter1 = 7
        case delegateLambdaParameter2 = 8
    }

    /// Delegate callback lambdas take at most three parameters
    /// (`property`, `oldValue`, `newValue`), so each position owns its own band
    /// kind.
    private static let delegateLambdaParameterKinds: [Kind] = [
        .delegateLambdaParameter0, .delegateLambdaParameter1, .delegateLambdaParameter2
    ]

    private static func makeSymbol(kind: Kind, original: SymbolID) -> SymbolID {
        let raw = original.rawValue
        // Leaving a band would silently alias an unrelated symbol and miscompile
        // the call it names, so fail where the cause is still visible.
        if raw >= 0 {
            precondition(
                raw <= maxOriginalRawValue,
                "synthetic symbol band exhausted: original \(raw) exceeds \(maxOriginalRawValue)"
            )
            return SymbolID(rawValue: -(bandBase + kindCount * raw + kind.rawValue))
        }
        let magnitude = Int64(raw).magnitude
        precondition(
            magnitude <= UInt64(maxMirrorOriginalMagnitude),
            "synthetic symbol mirror band exhausted: original \(raw) exceeds \(maxMirrorOriginalMagnitude)"
        )
        return SymbolID(rawValue: -(mirrorBandBase + kindCount * Int32(magnitude) + kind.rawValue))
    }

    private static func decode(_ symbol: SymbolID) -> (kind: Kind, original: SymbolID)? {
        let raw = symbol.rawValue
        let bandDescriptor: (base: Int32, sign: Int32)? = if raw <= -bandBase, raw > -bandLimit {
            (bandBase, 1)
        } else if raw <= -mirrorBandBase, raw > Int32.min {
            (mirrorBandBase, -1)
        } else {
            nil
        }
        guard let (base, sign) = bandDescriptor else {
            return nil
        }
        let index = -raw - base
        guard let kind = Kind(rawValue: index % kindCount) else {
            return nil
        }
        return (kind, SymbolID(rawValue: sign * (index / kindCount)))
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

    static func delegateLambdaParameterSymbol(
        for propertySymbol: SymbolID,
        at index: Int
    ) -> SymbolID {
        precondition(
            delegateLambdaParameterKinds.indices.contains(index),
            "delegate callback lambdas take at most \(delegateLambdaParameterKinds.count) parameters, got index \(index)"
        )
        return makeSymbol(kind: delegateLambdaParameterKinds[index], original: propertySymbol)
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
