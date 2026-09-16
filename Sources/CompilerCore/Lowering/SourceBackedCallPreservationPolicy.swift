/// How a call site's callee resolved, as far as source-backed preservation is
/// concerned.
enum SourceBackedCalleeResolution: Equatable {
    /// No usable callee binding was available.
    case unresolved
    /// A callee symbol id was not present in the symbol table.
    case unknownSymbol
    /// The resolved declaration has a source-backed implementation.
    case sourceBacked
    /// The resolved declaration is an external or synthetic runtime bridge.
    case externalBridge
}

extension SourceBackedCalleeResolution {
    /// Classify a callee without changing Sema's source-backed authority.
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

/// Decides whether a resolved declaration should remain selected by lowering.
///
/// Source-backed declarations are preserved by default. Runtime-backed
/// Sequence values are the explicit exception: their source declarations may
/// require a lowering bridge because the receiver is represented by an opaque
/// runtime box. Unresolved, unknown, and external declarations remain eligible
/// for the existing runtime rewrites.
struct SourceBackedCallPreservationPolicy {
    /// The policy is deliberately data-free: lookup tables identify concrete
    /// bridges, while this type only combines declaration resolution with
    /// runtime representation evidence.
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
