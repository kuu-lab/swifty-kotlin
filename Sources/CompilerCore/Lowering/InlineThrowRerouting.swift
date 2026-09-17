/// Rewires throw-producing instructions inside an inline/lambda expansion so a
/// throw that relied on the callee's function-level auto-propagation reaches
/// the caller's enclosing try instead.
///
/// Codegen's fallback for an unrouted throw is "store into the *current*
/// function's own out-parameter and return early". While a body compiles
/// standalone that fallback is correct; once the body is spliced into a
/// caller, "the current function" is the caller, so an unrouted throw would
/// silently escape the caller instead of reaching its enclosing try.
///
/// This matters because `appendThrowAwareInstructions` runs on the caller's
/// try body *before* inlining, when the call to the (later-inlined) function
/// is still a single opaque `.call`. If that call site was itself protected
/// by an enclosing try (`callerThrownResult != nil`), any unprotected throw
/// newly spliced into the caller by inlining must be redirected here so it
/// still reaches the caller's catch dispatch -- the pre-existing instructions
/// immediately following this splice point in the caller body.
enum InlineThrowRerouting {
    /// Redirects every throw producer in `instructions` that is not already
    /// routed to a local exception slot so it lands on `callerThrownResult`
    /// and jumps to the returned dispatch label.
    ///
    /// - `callerThrownResult`: the caller's exception slot -- the same slot the
    ///   original call site's throw-aware wrapping feeds the catch dispatch
    ///   from. `nil` means the call site is unprotected: the expansion passes
    ///   through unchanged and no label is allocated.
    /// - Local catch: an instruction whose `thrownResult` is already set (the
    ///   callee's own try/catch) keeps that route; rerouting it again would
    ///   steal the throw from the callee-local handler.
    /// - Finally guard: instructions between `.beginFinallyGuard` and the
    ///   matching `.endFinallyGuard` already have their throws claimed by the
    ///   guard's own dispatch and pass through untouched.
    /// - `throwDispatchLabel`: the single caller-namespace label every rerouted
    ///   throw jumps to. Allocated eagerly whenever `callerThrownResult` is
    ///   non-nil so numbering does not depend on the expansion's contents; the
    ///   call site emits it right after the spliced expansion. Distinct from
    ///   the non-local-return exit label -- both come from the same
    ///   `InlineLabelAllocator` caller cursor and never alias.
    static func rerouteUnprotectedThrows(
        in instructions: [KIRInstruction],
        callerThrownResult: KIRExprID?,
        labels: inout InlineLabelAllocator
    ) -> (instructions: [KIRInstruction], throwDispatchLabel: Int32?) {
        guard let callerThrownResult else {
            return (instructions, nil)
        }
        let throwLabel = labels.allocateCallerLabel()
        var result: [KIRInstruction] = []
        result.reserveCapacity(instructions.count)
        var finallyGuardDepth = 0
        for instruction in instructions {
            switch instruction {
            case .beginFinallyGuard:
                finallyGuardDepth += 1
            case .endFinallyGuard:
                finallyGuardDepth -= 1
            default:
                if finallyGuardDepth == 0,
                   let rerouted = callerRoute(
                       for: instruction,
                       thrownSlot: callerThrownResult,
                       dispatchLabel: throwLabel
                   )
                {
                    result.append(contentsOf: rerouted)
                    continue
                }
            }
            result.append(instruction)
        }
        return (result, throwLabel)
    }

    /// The routed replacement for one unrouted throw producer, or `nil` when
    /// `instruction` is not a throw producer this boundary owns -- a non-throw
    /// instruction, or a call already routed to a callee-local slot.
    ///
    /// A call's own `canThrow` flag is not a reliable "can the callee ever
    /// throw" predicate for ordinary (non-synthetic) functions -- it defaults
    /// to `false` and is only ever explicitly set to `true` for synthetic
    /// native-bridge stub registrations. A regular Kotlin function that throws
    /// conditionally (e.g. `checkWindowSizeStep` inside
    /// `Sequence.chunked`/`windowed`'s bundled Kotlin-source body, whose
    /// `throw` sits inside a nested `if`) still compiles its call sites with
    /// `canThrow: false, thrownResult: nil`, since that function has no local
    /// try/catch of its own: codegen unconditionally checks every call's
    /// outThrown slot regardless of the KIR-level `canThrow` flag, and
    /// `thrownResult == nil` means "propagate implicitly via my own outThrown
    /// parameter" -- correct as long as the function compiles standalone.
    /// Once auto-inlining (KIRLoweringDriver's `hasLambdaParam` heuristic)
    /// splices this body into a caller with its own enclosing try/catch, "my
    /// own outThrown" becomes the *caller's* outThrown, silently skipping the
    /// caller's catch block. Rerouting on `thrownResult == nil` alone
    /// (regardless of `canThrow`) catches this; for a call that genuinely
    /// cannot throw, the added check is simply dead code (it never observes a
    /// thrown value), not a correctness risk.
    private static func callerRoute(
        for instruction: KIRInstruction,
        thrownSlot: KIRExprID,
        dispatchLabel: Int32
    ) -> [KIRInstruction]? {
        switch instruction {
        case let .call(symbol, callee, arguments, callResult, _, thrownResult, isSuperCall, qualifiedSuperType)
            where thrownResult == nil:
            return [
                .call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: callResult,
                    canThrow: true,
                    thrownResult: thrownSlot,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ),
                .jumpIfNotNull(value: thrownSlot, target: dispatchLabel),
            ]
        case let .virtualCall(symbol, callee, receiver, arguments, callResult, _, thrownResult, dispatch)
            where thrownResult == nil:
            return [
                .virtualCall(
                    symbol: symbol,
                    callee: callee,
                    receiver: receiver,
                    arguments: arguments,
                    result: callResult,
                    canThrow: true,
                    thrownResult: thrownSlot,
                    dispatch: dispatch
                ),
                .jumpIfNotNull(value: thrownSlot, target: dispatchLabel),
            ]
        case let .rethrow(value):
            return [
                .copy(from: value, to: thrownSlot),
                .jump(dispatchLabel),
            ]
        default:
            return nil
        }
    }
}
