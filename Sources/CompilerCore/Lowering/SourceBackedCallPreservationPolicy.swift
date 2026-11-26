enum SourceBackedCalleeResolution: Equatable {
    case unresolved
    case unknownSymbol
    case sourceBacked
    case externalBridge
}

extension SourceBackedCalleeResolution {
    init(symbol: SymbolID?, sema: SemaModule?) {
        guard let symbol, let sema else {
            self = .unresolved
            return
        }
        guard sema.symbols.symbol(symbol) != nil else {
            self = .unknownSymbol
            return
        }
        self = sema.symbols.isSourceBackedSymbol(symbol) ? .sourceBacked : .externalBridge
    }
}

struct SourceBackedCallPreservationPolicy {
    init() {}

    func preserves(
        resolution: SourceBackedCalleeResolution,
        sequenceRuntimeRepresentation: CollectionLiteralLoweringSupport.SequenceRuntimeRepresentation
    ) -> Bool {
        guard resolution == .sourceBacked else {
            return false
        }

        switch sequenceRuntimeRepresentation {
        case .sourceObject, .notSequence:
            return true
        case .runtimeBox, .unknown:
            return false
        }
    }
}
