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
