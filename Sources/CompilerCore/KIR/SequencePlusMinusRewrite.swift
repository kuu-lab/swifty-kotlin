struct SequencePlusMinusRuntimeCallees {
    let plus: InternedString
    let minus: InternedString
    let ofSingle: InternedString

    init(plus: InternedString, minus: InternedString, ofSingle: InternedString) {
        self.plus = plus
        self.minus = minus
        self.ofSingle = ofSingle
    }

    init(interner: StringInterner) {
        self.init(
            plus: interner.intern("kk_sequence_plus"),
            minus: interner.intern("kk_sequence_minus"),
            ofSingle: interner.intern("kk_sequence_of_single")
        )
    }
}

enum SequencePlusMinusRewriteOperation {
    case plus
    case minus
}

enum SequencePlusMinusRewriteResult {
    case emitted
    case unsupportedCollectionMinus
}

/// Emits the shared Sequence plus/minus runtime rewrite used by KIR lowering
/// and collection call rewrites.
@discardableResult
func emitSequencePlusMinusRewrite(
    operation: SequencePlusMinusRewriteOperation,
    receiver: KIRExprID,
    argument: KIRExprID,
    argumentIsCollection: Bool,
    result: KIRExprID?,
    arena: KIRArena,
    callees: SequencePlusMinusRuntimeCallees,
    instructions: inout [KIRInstruction]
) -> SequencePlusMinusRewriteResult {
    switch operation {
    case .plus:
        let effectiveArgument: KIRExprID
        if argumentIsCollection {
            effectiveArgument = argument
        } else {
            // Keep kk_sequence_plus ABI inputs unambiguous by passing a
            // collection handle even for single-element plus.
            let wrappedArgument = arena.appendTemporary(type: nil)
            instructions.append(.call(
                symbol: nil,
                callee: callees.ofSingle,
                arguments: [argument],
                result: wrappedArgument,
                canThrow: false,
                thrownResult: nil
            ))
            effectiveArgument = wrappedArgument
        }
        instructions.append(.call(
            symbol: nil,
            callee: callees.plus,
            arguments: [receiver, effectiveArgument],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return .emitted

    case .minus:
        guard !argumentIsCollection else {
            return .unsupportedCollectionMinus
        }
        instructions.append(.call(
            symbol: nil,
            callee: callees.minus,
            arguments: [receiver, argument],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return .emitted
    }
}
