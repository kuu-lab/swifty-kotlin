/// Clones a KIR expression into a fresh id, or reuses a clone already made
/// for the same source within one inline/lambda expansion.
///
/// The per-expansion memo (`expandInlineCall`/`expandLambdaBody`'s
/// `localExprMap`) stays owned by the caller alongside the parameter- and
/// merge-slot substitutions it also records there; this type only owns the
/// clone-or-reuse operation built on top of it. Type substitution for a
/// generic inline body is not reimplemented here -- callers pass a
/// `substituteType` closure that delegates to the pass's existing
/// `substituteInlineType`, and `expandLambdaBody` (which has no inline type
/// parameters to substitute) relies on the identity default.
enum InlineExprCloning {
    /// Clones `source` into a fresh caller-scoped expression the first time it
    /// is encountered within a single inline expansion, and returns that same
    /// clone for every later occurrence of `source`. It is also used for
    /// `result` so that imported inline-KIR bodies (which are serialized after
    /// lowerings such as `IntegerNarrowingPass` and may reuse a single
    /// `KIRExprID` as a mutable loop variable) preserve writes across
    /// back-edges. `thrownResult` is routed this way because it is the field
    /// where the callee's own KIR intentionally reuses one physical expression
    /// -- a try/catch's shared exception slot -- as the `thrownResult` of
    /// every protected call inside the same try body (see
    /// `ControlFlowLowerer.appendThrowAwareInstructions`, which rewrites each
    /// protected call's `thrownResult` to the same pre-allocated
    /// `exceptionSlot`, while leaving `result` untouched). Cloning that slot
    /// independently on each occurrence would fragment one physical register
    /// into several disconnected ones, losing track of writes made through
    /// earlier clones.
    static func cloneOrReuseExpr(
        _ source: KIRExprID,
        localExprMap: inout [KIRExprID: KIRExprID],
        in arena: KIRArena,
        substituteType: (TypeID?) -> TypeID? = { $0 }
    ) -> KIRExprID {
        if let existing = localExprMap[source] {
            return existing
        }
        let cloned = cloneExpr(source, in: arena, substituteType: substituteType)
        localExprMap[source] = cloned
        return cloned
    }

    /// Clones `source` into a fresh expression in `arena`, keeping its
    /// existing `KIRExprKind` payload when one is recorded. A serialized
    /// imported-inline body can reference an id with no expression backing it,
    /// in which case the clone falls back to a plain `.temporary` -- the same
    /// fallback `appendTemporary` itself would allocate at this index, since
    /// both take their id from `arena`'s expression count at the same point.
    /// The clone's type is `substituteType` applied to `source`'s existing
    /// type, which defaults to leaving it unchanged.
    private static func cloneExpr(
        _ source: KIRExprID,
        in arena: KIRArena,
        substituteType: (TypeID?) -> TypeID?
    ) -> KIRExprID {
        let type = substituteType(arena.exprType(source))
        guard let expr = arena.expr(source) else {
            return arena.appendTemporary(type: type)
        }
        return arena.appendExpr(expr, type: type)
    }
}
