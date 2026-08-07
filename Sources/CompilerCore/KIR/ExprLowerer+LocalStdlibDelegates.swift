
extension ExprLowerer {
    /// Runtime accessor called to read a local `by`-delegated value for the stdlib
    /// delegate factories. `nil` for `.custom`, whose getValue is dispatched
    /// directly on the resolved user-defined operator symbol instead.
    private static func getValueRuntimeName(for kind: StdlibDelegateKind) -> String? {
        switch kind {
        case .lazy: "kk_lazy_get_value"
        case .observable: "kk_observable_get_value"
        case .vetoable: "kk_vetoable_get_value"
        case .notNull: "kk_notNull_get_value"
        case .custom: nil
        }
    }

    private static func setValueRuntimeName(for kind: StdlibDelegateKind) -> String? {
        switch kind {
        case .observable: "kk_observable_set_value"
        case .vetoable: "kk_vetoable_set_value"
        case .notNull: "kk_notNull_set_value"
        case .lazy, .custom: nil
        }
    }

    /// Reads a local declared with a stdlib delegate (`val x by lazy { ... }`).
    ///
    /// `delegateHandle` is the value bound to the local's symbol — the delegate
    /// object produced by `kk_lazy_create` & friends. Member and top-level
    /// delegated properties get an accessor that performs this call
    /// (`MemberLowerer.lowerDelegateAccessor`); locals have no accessor, so the
    /// call is emitted at each read site instead. Reading through the runtime
    /// accessor on every read (rather than caching one value at the declaration)
    /// preserves `lazy`'s deferred initialization and lets `observable`/`vetoable`
    /// reads observe writes.
    ///
    /// Returns `nil` when `symbol` is not a stdlib-delegated local.
    func loadLocalStdlibDelegateValue(
        symbol: SymbolID,
        delegateHandle: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let kind = driver.ctx.localStdlibDelegateKind(for: symbol),
              let runtimeName = Self.getValueRuntimeName(for: kind)
        else {
            return nil
        }
        let propertyType = driver.ctx.localDeclaredType(for: symbol)
            ?? sema.symbols.propertyType(for: symbol)
            ?? sema.types.nullableAnyType
        let resultExprID = arena.appendTemporary(type: propertyType)
        let canThrow = kind == .notNull
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeName),
            arguments: [delegateHandle],
            result: resultExprID,
            canThrow: canThrow,
            thrownResult: canThrow ? arena.appendTemporary(type: sema.types.nullableAnyType) : nil
        ))
        return resultExprID
    }

    /// Writes to a local `var` declared with a stdlib delegate, mirroring
    /// `loadLocalStdlibDelegateValue`. Returns `false` when `symbol` is not a
    /// stdlib-delegated local (or its delegate has no setter, as for `lazy`),
    /// leaving the caller's normal assignment path in charge.
    func storeLocalStdlibDelegateValue(
        symbol: SymbolID,
        delegateHandle: KIRExprID,
        valueID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> Bool {
        guard let kind = driver.ctx.localStdlibDelegateKind(for: symbol),
              let runtimeName = Self.setValueRuntimeName(for: kind)
        else {
            return false
        }
        let resultExprID = arena.appendTemporary(type: sema.types.unitType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeName),
            arguments: [delegateHandle, valueID],
            result: resultExprID,
            canThrow: false,
            thrownResult: nil
        ))
        return true
    }
}
