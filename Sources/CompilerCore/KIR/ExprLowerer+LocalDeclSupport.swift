/// Local-declaration helpers used by `ExprLowerer.lowerExpr`:
/// custom-delegate `provideDelegate` resolution, delegated-local `getValue`
/// reads, and the bare-variable-read predicate.
///
/// Split out from `ExprLowerer+ControlFlowAndBlocks.swift`.
extension ExprLowerer {
    /// Resolves the *effective* delegate for a local custom-delegate declaration
    /// (BUG-146). When the delegate factory exposes a `provideDelegate` operator,
    /// the actual delegate is its return value — the same rule member/top-level
    /// delegated properties follow in KIRLoweringDriver+ProvideDelegate.swift.
    /// Emits `rawDelegate.provideDelegate(null, KProperty("x"))` and returns the
    /// result. When no `provideDelegate` is present, returns `rawDelegateID`
    /// unchanged (the delegate factory instance is itself the delegate).
    func lowerLocalProvideDelegateIfNeeded(
        symbol: SymbolID,
        rawDelegateID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard sema.symbols.hasProvideDelegate(for: symbol),
              let provideDelegateSymbol = sema.symbols.delegateProvideDelegateSymbol(for: symbol)
        else {
            return rawDelegateID
        }
        let provideArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
            localSymbol: symbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let providedExprID = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: provideDelegateSymbol,
            callee: interner.intern("provideDelegate"),
            arguments: [rawDelegateID] + provideArgs,
            result: providedExprID,
            canThrow: false,
            thrownResult: nil
        ))
        return providedExprID
    }

    /// Reads a delegated local's current value by calling its resolved
    /// `getValue` operator fresh, rather than reusing whatever was computed
    /// at the declaration (which doesn't exist for delegates -- see the
    /// `.localDecl` case above). Real Kotlin delegated properties call
    /// getValue at every read site, and for `var` delegates observing writes
    /// (`Delegates.observable`, or a custom delegate a write may veto)
    /// depends on that: reusing a cached read would silently miss any
    /// change the delegate itself made to the stored value.
    /// Returns `nil` when `symbol` is not a delegated local.
    func readLocalDelegateValue(
        symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let delegateStorageID = driver.ctx.localDelegateStorage(for: symbol),
              let getValueSymbol = sema.symbols.delegateGetValueSymbol(for: symbol)
        else {
            return nil
        }
        let getterArgs = driver.memberLowerer.buildLocalDelegateAccessorArgs(
            localSymbol: symbol, sema: sema, arena: arena, interner: interner,
            instructions: &instructions
        )
        let propertyType = driver.ctx.localDeclaredType(for: symbol)
            ?? sema.symbols.propertyType(for: symbol)
            ?? sema.types.anyType
        let resultExprID = arena.appendTemporary(type: propertyType)
        instructions.append(driver.memberLowerer.dispatchedDelegateMemberCall(
            symbol: getValueSymbol,
            callee: interner.intern("getValue"),
            receiver: delegateStorageID,
            extraArguments: getterArgs,
            result: resultExprID,
            sema: sema,
            interner: interner
        ))
        return resultExprID
    }

    /// Whether the expression is a plain read of a variable (`b` in `val a = b`).
    /// Such initializers must be snapshotted into their own register instead of
    /// aliasing the source variable's storage.
    func isBareVariableRead(_ exprID: ExprID, ast: ASTModule) -> Bool {
        if case .nameRef = ast.arena.expr(exprID) {
            return true
        }
        return false
    }

}
