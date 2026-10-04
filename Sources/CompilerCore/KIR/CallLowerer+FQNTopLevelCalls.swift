
extension CallLowerer {
    /// Lowers a package-qualified property or classifier without evaluating
    /// its namespace-only receiver path. Sema marks these expressions while
    /// resolving `kotlin.math.PI` or the `kotlin.Int` prefix of
    /// `kotlin.Int.MAX_VALUE`.
    func tryLowerFQNQualifiedValue(
        _ exprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.isFQNQualifiedValueExpr(exprID),
              let symbolID = sema.bindings.identifierSymbol(for: exprID),
              let symbol = sema.symbols.symbol(symbolID)
        else {
            return nil
        }

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.symbols.propertyType(for: symbolID)
            ?? sema.types.anyType
        if symbol.kind == .property {
            if let constant = sema.bindings.constExprValue(for: exprID)
                ?? sema.symbols.constValueExprKind(for: symbolID)
            {
                let result = arena.appendExpr(constant, type: resultType)
                instructions.append(.constValue(result: result, value: constant))
                return result
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: symbolID),
               !externalLinkName.isEmpty
            {
                let result = arena.appendTemporary(type: resultType)
                instructions.append(.call(
                    symbol: symbolID,
                    callee: interner.intern(externalLinkName),
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if symbol.flags.contains(.importedLibrary),
               sema.symbols.propertyHasCustomGetter(for: symbolID),
               let getter = sema.symbols.extensionPropertyGetterAccessor(for: symbolID)
            {
                let result = arena.appendTemporary(type: resultType)
                instructions.append(.call(
                    symbol: getter,
                    callee: interner.intern("get"),
                    arguments: [],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let result = arena.appendExpr(.symbolRef(symbolID), type: resultType)
            instructions.append(.loadGlobal(result: result, symbol: symbolID))
            return wrapLateinitReadIfNeeded(
                result,
                symbol: symbolID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        switch symbol.kind {
        case .class, .interface, .object, .enumClass, .annotationClass:
            let valueSymbol: SymbolID
            if case let .classType(classType) = sema.types.kind(of: resultType) {
                valueSymbol = classType.classSymbol
            } else {
                valueSymbol = symbolID
            }
            let result = arena.appendExpr(.symbolRef(valueSymbol), type: resultType)
            instructions.append(.constValue(result: result, value: .symbolRef(valueSymbol)))
            return result
        default:
            return nil
        }
    }

    /// Lowers a `.memberCall` resolved by Sema's FQN-package-qualified
    /// top-level lookup (`CallTypeChecker.tryInferFQNPackageTopLevelCall`),
    /// e.g. `kotlin.math.abs(x)` or `kotlin.text.StringBuilder()`. That
    /// resolution fires before receiver inference, so the receiver
    /// expression (the namespace path `kotlin.math`/`kotlin.text`) never
    /// gets a Sema type binding — it is not a real value, just a
    /// disambiguating qualifier. Lowering it as one anyway (the ordinary
    /// `.memberCall` path) tries to evaluate the bogus chain, which either
    /// fails to link (an unresolved multi-segment chain is treated as a
    /// global/property load, e.g. an undefined `_math`/`_text` symbol) or,
    /// for a resolved constructor, silently prepends a bogus receiver
    /// argument that shifts the real constructor arguments by one slot and
    /// drops the last one. Marked explicitly by Sema
    /// (`markFQNTopLevelCallExpr`) rather than inferred from the receiver's
    /// missing type binding, so this can never misfire on some other
    /// receiver-skipping special case that happens to leave the receiver
    /// untyped for an unrelated reason.
    func tryLowerFQNTopLevelResolvedCall(
        _ exprID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.isFQNTopLevelCallExpr(exprID),
              let callBinding = sema.bindings.callBinding(for: exprID)
        else {
            return nil
        }

        // Qualified `kotlin.reflect.typeOf<T>()` expands through the same
        // intrinsic lowering as the unqualified call (KSP-1323).
        if let typeOfResult = lowerTypeOfCallExpr(
            exprID,
            calleeExpr: exprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return typeOfResult
        }

        let chosen = callBinding.chosenCallee
        let loweredArgIDs = args.enumerated().map { argumentIndex, argument in
            let previousAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
                argumentExpr: argument.expr,
                argumentIndex: argumentIndex,
                ast: ast,
                sema: sema,
                callBinding: callBinding,
                chosen: chosen
            )
            defer {
                driver.ctx.pendingLambdaNonLocalReturnAllowance = previousAllowance
            }
            return driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        return lowerResolvedCallBody(
            exprID,
            args: args,
            loweredArgIDs: loweredArgIDs,
            chosen: chosen,
            callBinding: callBinding,
            callableValueCallBinding: nil,
            loweredCallable: nil,
            loweredCalleeExprID: nil,
            sourceCalleeName: calleeName,
            boundType: sema.bindings.exprTypes[exprID],
            knownNames: KnownCompilerNames(interner: interner),
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }
}
