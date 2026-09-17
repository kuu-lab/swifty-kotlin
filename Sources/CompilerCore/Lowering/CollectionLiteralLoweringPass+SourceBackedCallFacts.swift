extension CollectionLiteralLoweringSupport {
    /// Resolve the runtime representation evidence needed by a source-backed
    /// call. State facts are authoritative; a receiver signature can only
    /// prove that an unclassified receiver is not a Sequence.
    func sequenceRuntimeRepresentationForCall(
        symbol: SymbolID?,
        receiver: KIRExprID?,
        state: CollectionRewriteState,
        module: KIRModule,
        sema: SemaModule?,
        interner: StringInterner
    ) -> SequenceRuntimeRepresentation {
        guard let receiver else {
            return .notSequence
        }

        let representation = state.sequenceRuntimeRepresentation(of: receiver)
        guard representation == .unknown, let sema else {
            return representation
        }

        let receiverType: TypeID?
        if let symbol {
            // A resolved top-level function has no receiver. Do not mistake
            // its first ordinary argument for an extension receiver merely
            // because that argument happens to have static type Sequence.
            guard let signature = sema.symbols.functionSignature(for: symbol) else {
                return representation
            }
            guard let signatureReceiverType = signature.receiverType else {
                return .notSequence
            }
            receiverType = signatureReceiverType
        } else {
            receiverType = module.arena.exprType(receiver)
        }
        guard let receiverType else { return representation }
        guard let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return representation
        }
        let sequenceFQName = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]
        return receiverSymbol.fqName == sequenceFQName ? .unknown : .notSequence
    }
}
