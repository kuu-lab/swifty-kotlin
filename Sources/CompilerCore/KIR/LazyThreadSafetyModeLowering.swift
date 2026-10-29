/// Non-constant mode expressions are lowered as KIR values so runtime-selected
/// modes are preserved; compiler fallback is used only when the mode expression
/// cannot be lowered as such.
enum LazyThreadSafetyModeLowering {
    /// A value typed as `LazyThreadSafetyMode` is deliberately not treated as a
    /// lock because the mode value is forwarded to the runtime lazy factory.
    static func lockExpression(
        from delegateExpression: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> ExprID? {
        guard let delegateExpression,
              case let .call(_, _, arguments, _) = ast.arena.expr(delegateExpression)
        else {
            return nil
        }
        for argument in arguments.dropLast().reversed() {
            guard let type = sema.bindings.exprTypes[argument.expr] else {
                return argument.expr
            }
            if isModeType(type, sema: sema, interner: interner) {
                continue
            }
            return argument.expr
        }
        return nil
    }

    static func isModeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let modeType = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return modeType.fqName == [interner.intern("kotlin"), interner.intern("LazyThreadSafetyMode")]
    }
}
