extension OverloadResolver {
    func satisfiesOnlyInputTypes(
        signature: FunctionSignature,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        inputConstraints: [VariableConstraint],
        ctx: SemaModule
    ) -> Bool {
        for symbol in signature.typeParameterSymbols {
            guard ctx.symbols.annotations(for: symbol).contains(where: {
                $0.annotationFQName == "kotlin.internal.OnlyInputTypes"
            }),
                let variable = typeVarBySymbol[symbol],
                let inferred = substitution[variable]
            else { continue }
            // A common supertype synthesized from unrelated inputs is not an
            // input type. A supplied Any/Any? is, and permits erased membership.
            let mentioned = inputConstraints.contains { constraint in
                switch (constraint.left, constraint.right) {
                case let (.type(type), .variable(other)), let (.variable(other), .type(type)):
                    return other == variable && type == inferred
                default:
                    return false
                }
            }
            if !mentioned {
                return false
            }
        }
        return true
    }

    func checkForUninferredTypeVariables(
        signature: FunctionSignature,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        range: SourceRange,
        typeSystem: TypeSystem
    ) -> Diagnostic? {
        for typeParamSymbol in signature.typeParameterSymbols {
            guard let typeVar = typeVarBySymbol[typeParamSymbol] else {
                continue
            }
            let resolved = substitution[typeVar]
            // A type variable is "uninferred" when it was either never
            // included in the substitution (no constraints at all) or the
            // solver explicitly set it to errorType.
            guard resolved == nil || resolved == typeSystem.errorType else {
                continue
            }
            // Only report for type parameters that actually appear in the
            // return type or parameter types. Unused type parameters
            // (e.g. `fun <T, U> foo(x: T): T` where U is never used)
            // are silently ignored.
            let usedInReturn = containsTypeVariable(
                signature.returnType,
                typeVarBySymbol: [typeParamSymbol: typeVar],
                typeSystem: typeSystem
            )
            let usedInParams = signature.parameterTypes.contains {
                containsTypeVariable(
                    $0,
                    typeVarBySymbol: [typeParamSymbol: typeVar],
                    typeSystem: typeSystem
                )
            }
            if usedInReturn || usedInParams {
                return Diagnostic(
                    severity: .error,
                    code: "KSWIFTK-SEMA-INFER",
                    message: "Cannot infer type argument from the call arguments and expected type; provide explicit type arguments or an explicit expected type.",
                    primaryRange: range,
                    secondaryRanges: []
                )
            }
        }
        return nil
    }

    func checkTypeParameterBounds(
        signature: FunctionSignature,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        starProjectedReceiverParameters: Set<SymbolID> = [],
        range: SourceRange,
        ctx: SemaModule
    ) -> Diagnostic? {
        func mergedUpperBounds(signatureBounds: [TypeID], symbolBounds: [TypeID]) -> [TypeID] {
            var merged: [TypeID] = []
            merged.reserveCapacity(signatureBounds.count + symbolBounds.count)
            for bound in signatureBounds where !merged.contains(bound) {
                merged.append(bound)
            }
            for bound in symbolBounds where !merged.contains(bound) {
                merged.append(bound)
            }
            return merged
        }

        for (index, typeParamSymbol) in signature.typeParameterSymbols.enumerated() {
            // A read-only receiver's star denotes an existential type constrained by its declaration.
            // Its readable approximation cannot be rechecked as a concrete F-bounded type argument.
            if starProjectedReceiverParameters.contains(typeParamSymbol) { continue }
            let signatureUpperBounds: [TypeID] = if index < signature.typeParameterUpperBoundsList.count {
                signature.typeParameterUpperBoundsList[index]
            } else {
                []
            }
            let symbolUpperBounds = ctx.symbols.typeParameterUpperBounds(for: typeParamSymbol)
            let upperBounds = mergedUpperBounds(
                signatureBounds: signatureUpperBounds,
                symbolBounds: symbolUpperBounds
            )

            guard let typeVar = typeVarBySymbol[typeParamSymbol],
                  let substitutedType = substitution[typeVar]
            else {
                continue
            }

            // Check all upper bounds (with type parameter substitution applied to bounds)
            for bound in upperBounds {
                let substitutedBound = ctx.types.substituteTypeParameters(
                    in: bound,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                if !ctx.types.isSubtype(substitutedType, substitutedBound),
                   !ctx.diagnostics.isSuppressed(code: "KSWIFTK-SEMA-BOUND", range: range)
                {
                    return Diagnostic(
                        severity: .error,
                        code: "KSWIFTK-SEMA-BOUND",
                        message: "Type argument does not satisfy upper bound constraint.",
                        primaryRange: range,
                        secondaryRanges: []
                    )
                }
            }
        }
        return nil
    }
}
