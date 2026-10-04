/// Delegate kinds recognized by the compiler (P5-80, P5-79).
///
/// KSP-491 wired `lazy`/`Delegates.observable/vetoable/notNull` to the same
/// operator-convention `getValue`/`setValue` resolution `.custom` delegates
/// already use, so this no longer selects a distinct runtime dispatch
/// strategy for property *access*. It's still needed to pick which bundled
/// Kotlin implementation to construct for a delegate's *creation* (KIR
/// lowering can't recover this from the resolved delegate type alone, since
/// `lazy { ... }`'s trailing lambda is parsed apart from `delegateExpr` --
/// see `KIRLoweringDriver+ModuleLowering+PropertyDecl.swift`).
enum StdlibDelegateKind: Equatable {
    case lazy
    case observable
    case vetoable
    case notNull
    /// Custom user-defined delegate with getValue/setValue operators.
    case custom

    /// Detects the delegate kind from the delegate expression's AST shape.
    ///
    /// This is the single source of truth for recognizing the stdlib delegate
    /// factories (`lazy`, `Delegates.observable/vetoable/notNull`) — do not
    /// reimplement the matching elsewhere, since callers disagreeing on which
    /// expressions count as "known" would misselect the creation-time
    /// implementation to construct.
    ///
    /// The name set intentionally differs *per AST node shape*: a bare name
    /// only ever refers to the top-level `lazy` function; a member call only
    /// ever means `Delegates.observable/vetoable/notNull` (those are never
    /// referenced as a bare identifier).
    static func detect(
        delegateExpr: ExprID?,
        ast: ASTModule,
        interner: StringInterner
    ) -> StdlibDelegateKind {
        guard let exprID = delegateExpr,
              let expr = ast.arena.expr(exprID) else { return .custom }
        let lazyID = interner.intern("lazy")
        let observableID = interner.intern("observable")
        let vetoableID = interner.intern("vetoable")
        let notNullID = interner.intern("notNull")
        switch expr {
        case let .nameRef(name, _):
            if name == lazyID { return .lazy }
            return .custom
        case let .call(callee, _, _, _):
            if let calleeExpr = ast.arena.expr(callee) {
                switch calleeExpr {
                case let .nameRef(name, _):
                    if name == observableID { return .observable }
                    if name == vetoableID { return .vetoable }
                    if name == notNullID { return .notNull }
                    if name == lazyID { return .lazy }
                default: break
                }
            }
            return detectFromCallExpr(callee: callee, ast: ast, interner: interner)
        case let .memberCall(_, callee, _, _, _):
            if callee == observableID { return .observable }
            if callee == vetoableID { return .vetoable }
            if callee == notNullID { return .notNull }
            return .custom
        default:
            return .custom
        }
    }

    private static func detectFromCallExpr(
        callee: ExprID, ast: ASTModule, interner: StringInterner
    ) -> StdlibDelegateKind {
        guard let expr = ast.arena.expr(callee) else { return .custom }
        let observableID = interner.intern("observable")
        let vetoableID = interner.intern("vetoable")
        let notNullID = interner.intern("notNull")
        switch expr {
        case let .memberCall(_, name, _, _, _):
            if name == observableID { return .observable }
            if name == vetoableID { return .vetoable }
            if name == notNullID { return .notNull }
        case let .nameRef(name, _):
            if name == observableID { return .observable }
            if name == vetoableID { return .vetoable }
            if name == notNullID { return .notNull }
        default: break
        }
        return .custom
    }
}
