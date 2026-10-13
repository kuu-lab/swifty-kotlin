extension CallLowerer {
    /// KUU-763: built-in floating-point range values are opaque
    /// `RuntimeDoubleRangeBox`/`RuntimeFloatRangeBox` handles that register no
    /// Kotlin vtable/itable, so `ClosedFloatingPointRange`/`ClosedRange`
    /// member calls on an interface-typed receiver cannot resolve the box
    /// through `.itableDynamic` (the lookup traps at runtime). Probe the
    /// runtime representation first and fall through to virtual dispatch only
    /// for user-defined implementations — the same pattern the endpoint
    /// properties already use via `emitRuntimeFloatingPointEndpointFastPath`
    /// (KUU-999).
    ///
    /// Emits the fast-path call, the null-sentinel compare, and the
    /// interface-dispatch label; returns the end label the caller must append
    /// after its own virtual-call instruction. Returns `nil` (emitting
    /// nothing) when `chosenCallee` is not one of the source-declared
    /// `contains`/`isEmpty`/`lessThanOrEquals` members on the two range
    /// interfaces.
    func emitFloatingPointRangeMemberProbe<C: RangeReplaceableCollection>(
        chosenCallee: SymbolID?,
        receiverID: KIRExprID,
        sourceReceiverID: KIRExprID? = nil,
        arguments: [KIRExprID],
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout C
    ) -> Int32? where C.Element == KIRInstruction {
        guard let chosenCallee,
              let calleeInfo = sema.symbols.symbol(chosenCallee),
              calleeInfo.kind == .function,
              let ownerID = sema.symbols.parentSymbol(for: chosenCallee),
              let ownerInfo = sema.symbols.symbol(ownerID)
        else { return nil }
        let owner = ownerInfo.fqName.map(interner.resolve)
        let isClosedFloatingPointRange = owner == [
            "kotlin", "ranges", "ClosedFloatingPointRange",
        ]
        let isClosedRange = owner == ["kotlin", "ranges", "ClosedRange"]
        let member = interner.resolve(calleeInfo.name)
        let probeName: String
        let arity: Int
        switch member {
        case "contains":
            guard isClosedFloatingPointRange || isClosedRange else { return nil }
            probeName = "__kk_floating_range_contains_or_null"
            arity = 1
        case "isEmpty":
            guard isClosedFloatingPointRange || isClosedRange else { return nil }
            probeName = "__kk_floating_range_isEmpty_or_null"
            arity = 0
        case "lessThanOrEquals":
            // `ClosedRange` does not declare `lessThanOrEquals`.
            guard isClosedFloatingPointRange else { return nil }
            probeName = "__kk_floating_range_lessThanOrEquals_or_null"
            arity = 2
        default:
            return nil
        }

        // Member signatures may prepend the receiver into `arguments`
        // (`signature.receiverType != nil` extension-style convention, and the
        // `in`-operator path passes `[container, element]` explicitly). Strip a
        // leading receiver occurrence so the probe sees exactly
        // `(receiver, declaredArgs...)`.
        var explicitArguments = arguments
        if let first = explicitArguments.first,
           first == receiverID || first == sourceReceiverID
        {
            explicitArguments.removeFirst()
        }
        let probeArguments = [receiverID] + explicitArguments.prefix(arity)

        let probed = arena.appendTemporary(type: sema.types.nullableAnyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(probeName),
            arguments: probeArguments,
            result: probed,
            canThrow: false,
            thrownResult: nil
        ))
        let null = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        instructions.append(.constValue(result: null, value: .null))
        let interfaceLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfEqual(lhs: probed, rhs: null, target: interfaceLabel))
        instructions.append(.copy(from: probed, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(interfaceLabel))
        return endLabel
    }
}
