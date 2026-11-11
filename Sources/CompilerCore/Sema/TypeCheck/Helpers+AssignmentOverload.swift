extension TypeCheckHelpers {
    /// Returns whether the assignment target type or property symbol is opted in
    /// to assignment overloading via `org.jetbrains.kotlin.assignment`.
    func isAssignmentOverloadEligible(
        targetType: TypeID,
        targetSymbol: SymbolID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        if sema.assignmentOverloadTypes.isEmpty && sema.assignmentOverloadProperties.isEmpty {
            return false
        }
        if let targetSymbol, sema.assignmentOverloadProperties.contains(targetSymbol) {
            return true
        }
        let nonNullTarget = sema.types.makeNonNullable(targetType)
        let nominalRoots = allNominalSymbols(
            of: nonNullTarget,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner
        )
        var queue = nominalRoots
        var visited: Set<SymbolID> = []
        while !queue.isEmpty {
            let sym = queue.removeFirst()
            guard visited.insert(sym).inserted else { continue }
            if sema.assignmentOverloadTypes.contains(sym) {
                return true
            }
            queue.append(contentsOf: sema.symbols.directSupertypes(for: sym))
        }
        return false
    }
}

extension ExprTypeChecker {
    /// Attempts to rewrite `lhs = rhs` into `lhs.assign(rhs)` when the target type or
    /// property is annotated for the `assignment` compiler plugin and has a matching
    /// `assign` function for `valueType`.
    func tryResolvePluginOverloadedAssignment(
        exprID: ExprID,
        targetType: TypeID,
        targetSymbol: SymbolID?,
        valueType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard driver.helpers.isAssignmentOverloadEligible(
            targetType: targetType,
            targetSymbol: targetSymbol,
            sema: sema,
            interner: interner
        ) else {
            return nil
        }

        let assignName = interner.intern("assign")
        let nonNullTarget = sema.types.makeNonNullable(targetType)
        let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: assignName,
            receiverType: nonNullTarget,
            sema: sema,
            includeUnattachedPackageExtensions: false,
            interner: interner
        )
        let scopeExtensionCandidates = ctx.scope.lookup(assignName).filter { candidate in
            guard let sig = sema.symbols.functionSignature(for: candidate),
                  let recv = sig.receiverType
            else { return false }
            return sema.types.isSubtype(nonNullTarget, sema.types.makeNonNullable(recv))
                || sema.types.typeContainsAnyTypeParam(recv)
        }
        let allCandidates = Array(Set(memberCandidates + scopeExtensionCandidates))
        guard !allCandidates.isEmpty else {
            return nil
        }

        let call = CallExpr(
            range: range,
            calleeName: assignName,
            args: [CallArg(type: valueType)],
            dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type),
            isOperatorCall: false
        )
        let resolved = ctx.resolver.resolveCall(
            candidates: allCandidates,
            call: call,
            expectedType: nil,
            implicitReceiverType: nonNullTarget,
            ctx: sema
        )
        guard let chosenCallee = resolved.chosenCallee,
              resolved.diagnostic == nil
        else {
            return nil
        }

        sema.pluginOverloadedAssignments[exprID] = PluginOverloadedAssignmentInfo(
            assignCallee: chosenCallee,
            targetType: nonNullTarget,
            targetSymbol: targetSymbol,
            callBinding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
        sema.bindings.bindExprType(exprID, type: sema.types.unitType)
        return sema.types.unitType
    }
}
