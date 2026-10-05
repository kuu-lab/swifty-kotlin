
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

    /// Whether `symbolID` declares an *extension* receiver rather than the
    /// dispatch receiver a member signature stores. Member functions record
    /// `extensionReceiverType ?? ownerType` as `signature.receiverType`
    /// (MemberHeaderCollection), so a non-nil receiver whose nominal differs
    /// from the function's own parent symbol is an extension receiver.
    /// Top-level extensions (package/nil parent) count unconditionally:
    /// Kotlin resolves them only through `Type::ext`/`obj::ext` forms and
    /// rejects a bare `::name` reference, while member-extensions are
    /// unreferenceable in every `::` form ("member and an extension at the
    /// same time").
    func declaresExtensionReceiver(_ symbolID: SymbolID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: symbolID),
              let receiverType = signature.receiverType
        else { return false }
        guard let parentID = sema.symbols.parentSymbol(for: symbolID),
              let parent = sema.symbols.symbol(parentID),
              parent.kind != .package
        else { return true }
        let receiverNominals = allNominalSymbols(
            of: receiverType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner
        )
        if receiverNominals.contains(parentID) {
            return false
        }
        // Builtin nominal shells can be recreated under a fresh SymbolID while
        // bundled sources are collected; compare FQ identity as well before
        // concluding the receiver is foreign to the declaring owner.
        let parentFQName = parent.fqName
        return !parentFQName.isEmpty
            && !receiverNominals.contains(where: {
                sema.symbols.symbol($0)?.fqName == parentFQName
            })
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
        } else if let fnType = functionNType(for: expectedType, sema: sema) {
            // KUU-1084: nominal `FunctionN<P..N, R>` drives overload
            // selection the same way the function type it names does.
            sema.types.make(.functionType(fnType))
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
