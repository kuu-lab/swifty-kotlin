
// Callable target resolution and nominal subtype helpers.

extension TypeCheckHelpers {
    func isNominalSubtype(
        _ candidate: SymbolID,
        of base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        if candidate == base {
            return true
        }
        var queue = symbols.directSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next == base {
                return true
            }
            if visited.insert(next).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: next))
            }
        }
        return false
    }

    func callableTargetForCalleeExpr(
        _ calleeExprID: ExprID,
        sema: SemaModule
    ) -> CallableTarget? {
        if let explicitTarget = sema.bindings.callableTarget(for: calleeExprID) {
            return explicitTarget
        }
        guard let symbol = sema.bindings.identifierSymbol(for: calleeExprID) else {
            return nil
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol) else {
            return .localValue(symbol)
        }
        if semanticSymbol.kind == .function || semanticSymbol.kind == .constructor {
            return .symbol(symbol)
        }
        return .localValue(symbol)
    }

    /// `boundReceiver` carries the member symbol and the (possibly generic)
    /// type of a bound `value::member` reference. The member's signature is
    /// declared in terms of its owner's type parameters (`Transformer<A, B>.apply:
    /// (A) -> B`), so they are substituted with the receiver's type arguments
    /// (`Transformer<Int, Int>` -> `(Int) -> Int`) before the function type is built.
    func callableFunctionType(
        for signature: FunctionSignature,
        bindReceiver: Bool,
        boundReceiver: (symbol: SymbolID, receiverType: TypeID)? = nil,
        sema: SemaModule
    ) -> TypeID {
        var params = signature.parameterTypes
        var returnType = signature.returnType
        if let boundReceiver,
           let owner = sema.symbols.parentSymbol(for: boundReceiver.symbol),
           sema.symbols.symbol(owner)?.kind == .class || sema.symbols.symbol(owner)?.kind == .interface
        {
            func specialize(_ type: TypeID) -> TypeID {
                resolveMemberPropertyType(
                    type,
                    receiverType: boundReceiver.receiverType,
                    ownerSymbol: owner,
                    sema: sema
                )
            }
            params = params.map(specialize)
            returnType = specialize(returnType)
        }
        if !bindReceiver, let receiverType = signature.receiverType {
            params.insert(receiverType, at: 0)
        }
        return sema.types.make(.functionType(FunctionType(
            params: params,
            returnType: returnType,
            isSuspend: signature.isSuspend,
            nullability: .nonNull
        )))
    }

    func chooseCallableReferenceTarget(
        from candidates: [SymbolID],
        expectedType: TypeID?,
        bindReceiver: Bool,
        boundReceiverType: TypeID? = nil,
        sema: SemaModule
    ) -> SymbolID? {
        let sorted = candidates.sorted(by: { $0.rawValue < $1.rawValue })
        guard !sorted.isEmpty else {
            return nil
        }
        guard let expectedType else {
            return sorted.first
        }

        let expectedFunctionType: TypeID? = if case .functionType = sema.types.kind(of: expectedType) {
            expectedType
        } else if let samFT = samFunctionType(for: expectedType, sema: sema) {
            sema.types.make(.functionType(samFT))
        } else {
            nil
        }
        guard let expectedFunctionType else {
            return sorted.first
        }
        if let matched = sorted.first(where: { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            let inferredType = callableFunctionType(
                for: signature,
                bindReceiver: bindReceiver,
                boundReceiver: boundReceiverType.map { (symbolID, $0) },
                sema: sema
            )
            return sema.types.isSubtype(inferredType, expectedFunctionType)
        }) {
            return matched
        }
        return sorted.first
    }
}
