
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

    func callableFunctionType(
        for signature: FunctionSignature,
        bindReceiver: Bool,
        sema: SemaModule
    ) -> TypeID {
        var params = signature.parameterTypes
        if !bindReceiver, let receiverType = signature.receiverType {
            params.insert(receiverType, at: 0)
        }
        return sema.types.make(.functionType(FunctionType(
            params: params,
            returnType: signature.returnType,
            isSuspend: signature.isSuspend,
            nullability: .nonNull
        )))
    }

    /// The intrinsic `KProperty0<V>` / `KProperty1<T, V>` / `KMutableProperty0<V>` /
    /// `KMutableProperty1<T, V>` type of a property reference (`obj::prop` /
    /// `Type::prop`), independent of any expected type from the call site.
    ///
    /// Callers must not adopt an `expectedType` that still mentions unresolved
    /// type parameters (e.g. the declared `vararg elements: T` parameter type
    /// while inferring `listOf(C::v)`'s argument, before `T` is solved) — doing
    /// so binds the reference's static type to a bare type variable instead of
    /// a `KProperty*` classType, which later fails `lowerPropertyReferenceWrapperValue`'s
    /// shape guard and silently falls back to the legacy bare-symbol callable
    /// path (crashes at runtime: that path calls the property's raw accessor
    /// with no receiver). This natural type is what such callers should report
    /// instead.
    func naturalPropertyReferenceType(
        propertySymbol: SymbolID,
        ownerType: TypeID?,
        isBoundReceiver: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let propertyType = sema.symbols.propertyType(for: propertySymbol) else {
            return nil
        }
        let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
        let interfaceName: String = switch (isBoundReceiver, isMutable) {
        case (true, false): "KProperty0"
        case (true, true): "KMutableProperty0"
        case (false, false): "KProperty1"
        case (false, true): "KMutableProperty1"
        }
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        guard let interfaceSymbol = sema.symbols.lookup(fqName: reflectPkg + [interner.intern(interfaceName)]) else {
            return nil
        }
        let args: [TypeArg]
        if isBoundReceiver {
            args = [.invariant(propertyType)]
        } else {
            guard let ownerType else { return nil }
            args = [.invariant(ownerType), .invariant(propertyType)]
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: args,
            nullability: .nonNull
        )))
    }

    func chooseCallableReferenceTarget(
        from candidates: [SymbolID],
        expectedType: TypeID?,
        bindReceiver: Bool,
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
                sema: sema
            )
            return sema.types.isSubtype(inferredType, expectedFunctionType)
        }) {
            return matched
        }
        return sorted.first
    }
}
