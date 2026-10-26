extension ExprTypeChecker {
    func inferBuilderBoundCallableReferenceReceiverType(
        signature: FunctionSignature,
        targetSymbol: SymbolID,
        boundReceiverType: TypeID,
        expectedFunctionType: TypeID,
        range: SourceRange,
        availableContextReceiverTypes: [TypeID],
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        guard let session = ctx.builderInference,
              !session.isFinalized
        else {
            return nil
        }

        let inferredType = driver.helpers.callableFunctionType(
            for: signature,
            bindReceiver: true,
            boundReceiver: (targetSymbol, boundReceiverType),
            targetSymbol: targetSymbol,
            interner: ctx.interner,
            sema: sema
        )
        let contextualType = driver.helpers.unitCoercedCallableReferenceType(
            inferredType,
            expectedFunctionType: expectedFunctionType,
            sema: sema
        ) ?? inferredType
        let constraintExpectedType = driver.helpers.suspendConvertedCallableReferenceExpectedType(
            contextualType,
            expectedFunctionType: expectedFunctionType,
            sema: sema
        ) ?? expectedFunctionType
        let constraints = ctx.resolver.decomposeSubtypeConstraint(
            subtype: contextualType,
            supertype: constraintExpectedType,
            typeVarBySymbol: session.typeVarBySymbol,
            typeSystem: sema.types,
            blameRange: range
        )
        let sessionVariables = Set(session.typeVarBySymbol.values)
        let introducedVariables = Set(ctx.resolver.usedTypeVariables(from: constraints))
        guard !constraints.isEmpty,
              !sessionVariables.isDisjoint(with: introducedVariables)
        else {
            return nil
        }

        let proposedConstraints = session.constraints + constraints
        let solution = ConstraintSolver().solve(
            vars: ctx.resolver.usedTypeVariables(from: proposedConstraints),
            constraints: proposedConstraints,
            typeSystem: sema.types
        )
        guard solution.isSuccess else {
            return nil
        }

        let resolvedReceiverType = sema.types.substituteTypeParameters(
            in: boundReceiverType,
            substitution: solution.substitution,
            typeVarBySymbol: session.typeVarBySymbol
        )
        guard driver.helpers.contextualCallableReferenceBinding(
            for: signature,
            targetSymbol: targetSymbol,
            bindReceiver: true,
            boundReceiver: (targetSymbol, resolvedReceiverType),
            expectedFunctionType: expectedFunctionType,
            interner: ctx.interner,
            availableContextReceiverTypes: availableContextReceiverTypes,
            sema: sema
        ) != nil else {
            return nil
        }

        session.constraints.append(contentsOf: constraints)
        return resolvedReceiverType
    }
}
