
extension ExprLowerer {
    /// Returns whether a factory result is eventually stored in the local
    /// delegate handle. Inlined stdlib factories can emit bookkeeping
    /// instructions between the factory call and the storage copy.
    static func lazyFactoryResultStoresIntoHandle(
        result: KIRExprID,
        delegateHandle: KIRExprID,
        callIndex: Int,
        instructions: [KIRInstruction]
    ) -> Bool {
        guard result != delegateHandle else { return true }
        return instructions.dropFirst(callIndex + 1).contains { instruction in
            guard case let .copy(from, to) = instruction else { return false }
            return from == result && to == delegateHandle
        }
    }

    /// Replaces the source-backed `kotlin.lazy` factory used by a local
    /// `by lazy` declaration with the runtime handle consumed by the local
    /// delegate accessors.
    ///
    /// This is done while lowering the declaration, when the compiler still
    /// knows that the factory result is delegate storage. Inferring this later
    /// from `kk_lazy_get_value` consumers is incorrect for captured locals:
    /// reads in a nested lambda are emitted in a different KIR function.
    func lowerLocalLazyFactory(
        delegateKind: StdlibDelegateKind,
        delegateHandle: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> Bool {
        guard delegateKind == .lazy else { return true }

        let lazyName = interner.intern("lazy")
        let lazyFQName = [interner.intern("kotlin"), lazyName]
        let lazyImplFQName = [interner.intern("kotlin"), interner.intern("LazyImpl")]
        let callMatch = instructions.indices.reversed().compactMap({ index -> (Int, Bool)? in
            guard case let .call(symbol, _, arguments, result, _, _, _, _) = instructions[index],
                  let result,
                  !arguments.isEmpty,
                  let symbol,
                  let symbolInfo = sema.symbols.symbol(symbol)
            else {
                return nil
            }

            let isFactoryCall = symbolInfo.fqName == lazyFQName
            let isLazyImplConstructor: Bool
            if symbolInfo.kind == .constructor,
               let parentSymbol = sema.symbols.parentSymbol(for: symbol),
               let parentInfo = sema.symbols.symbol(parentSymbol)
            {
                isLazyImplConstructor = parentInfo.fqName == lazyImplFQName
            } else {
                isLazyImplConstructor = false
            }
            guard isFactoryCall || isLazyImplConstructor else { return nil }

            // The source-backed factory is auto-inlined because it takes a
            // function parameter. Its result is therefore often copied from
            // the LazyImpl constructor result into the local handle.
            let storesIntoHandle = Self.lazyFactoryResultStoresIntoHandle(
                result: result,
                delegateHandle: delegateHandle,
                callIndex: index,
                instructions: instructions
            )
            guard storesIntoHandle else { return nil }
            return (index, isLazyImplConstructor)
        }).first
        guard let callMatch else {
            return false
        }
        let callIndex = callMatch.0
        let isLazyImplConstructor = callMatch.1

        guard case let .call(_, _, arguments, result, _, _, _, _) = instructions[callIndex],
              let result,
              let initializer: KIRExprID = {
                  if isLazyImplConstructor {
                      guard arguments.count >= 6 else { return nil }
                      return arguments[1]
                  }
                  return arguments.last
              }()
        else {
            return false
        }

        let lockExpr: KIRExprID?
        let modeArgument: KIRExprID?
        if isLazyImplConstructor {
            guard arguments.count >= 6 else { return false }
            modeArgument = arguments[2]
            let constructorLock = arguments[3]
            if case .null = arena.expr(constructorLock) {
                lockExpr = nil
            } else {
                lockExpr = constructorLock
            }
        } else {
            lockExpr = LazyThreadSafetyModeLowering.lockExpression(
                from: arguments,
                arena: arena,
                sema: sema,
                interner: interner
            )
            modeArgument = arguments.dropLast().last
        }
        let modeExpr: KIRExprID
        let constantModeValue = modeArgument.flatMap {
            LazyThreadSafetyModeLowering.constantRawValue(
                from: $0, arena: arena, sema: sema, interner: interner
            )
        }
        let runtimeCallIndex: Int
        if lockExpr != nil {
            let modeValue = Int64(LazyDelegateThreadSafetyMode.synchronized.rawValue)
            modeExpr = arena.appendExpr(.intLiteral(modeValue), type: nil)
            instructions[callIndex] = .constValue(result: modeExpr, value: .intLiteral(modeValue))
            runtimeCallIndex = callIndex + 1
        } else if let modeValue = constantModeValue {
            modeExpr = arena.appendExpr(.intLiteral(modeValue), type: nil)
            instructions[callIndex] = .constValue(result: modeExpr, value: .intLiteral(modeValue))
            runtimeCallIndex = callIndex + 1
        } else {
            // The runtime bridge consumes a raw mode ordinal, while a
            // non-constant enum expression lowers to an object handle. Keep
            // the documented delegate fallback instead of passing that
            // handle through the integer ABI.
            let modeValue = LazyThreadSafetyModeLowering.rawValue(
                from: modeArgument,
                arena: arena,
                sema: sema,
                interner: interner,
                fallback: Int64(driver.ctx.lazyThreadSafetyMode.rawValue)
            )
            modeExpr = arena.appendExpr(.intLiteral(modeValue), type: nil)
            instructions[callIndex] = .constValue(result: modeExpr, value: .intLiteral(modeValue))
            runtimeCallIndex = callIndex + 1
        }
        let runtimeCallee = lockExpr == nil
            ? interner.intern("kk_lazy_create")
            : interner.intern("kk_lazy_create_with_lock")
        let runtimeArguments = lockExpr.map { [initializer, modeExpr, $0] }
            ?? [initializer, modeExpr]
        let runtimeCall = KIRInstruction.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: runtimeArguments,
            result: result,
            canThrow: false,
            thrownResult: nil
        )
        instructions.insert(runtimeCall, at: runtimeCallIndex)
        return true
    }

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
