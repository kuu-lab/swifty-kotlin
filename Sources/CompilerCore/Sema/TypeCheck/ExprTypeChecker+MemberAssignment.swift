extension ExprTypeChecker {
    func collectReceiverBuilderPropertyWriteConstraint(
        valueType: TypeID,
        writeType: TypeID,
        value: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) {
        guard let session = ctx.builderInference,
              !session.isFinalized,
              session.mentionsVariable(writeType, types: ctx.sema.types),
              valueType != ctx.sema.types.errorType
        else {
            return
        }
        session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
            subtype: valueType,
            supertype: writeType,
            typeVarBySymbol: session.typeVarBySymbol,
            typeSystem: ctx.sema.types,
            blameRange: ctx.ast.arena.exprRange(value) ?? range
        ))
    }

    func inferMemberAssignExpr(
        _ id: ExprID,
        receiver: ExprID,
        name: InternedString,
        value: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        isSafeCall: Bool = false
    ) -> TypeID {
        let sema = ctx.sema
        // The receiver of `a?.b = v` is evaluated iff the assignment itself
        // is — it keeps the conditionality this node was entered with, not
        // the raised flag that gates the value write (KUU-3966).
        var receiverCtx = ctx
        receiverCtx.isConditionallyEvaluated = ctx.receiverConditionallyEvaluated
        let inferredReceiver = driver.inferExpr(receiver, ctx: receiverCtx, locals: &locals, expectedType: nil)
        var receiverType = driver.helpers.retypeClassNameAsCompanionValue(
            receiver, currentType: inferredReceiver, ast: ctx.ast, sema: sema
        ) ?? inferredReceiver
        // KUU-3522: `super.foo = value` must pick the supertype that declares
        // `foo`, exactly like `super.foo` reads and `super.foo()` calls do.
        // An unqualified `super` in a class with only interface supertypes
        // otherwise stays typed `kotlin.Any` (the implicit class superclass)
        // and the write lookup reports SEMA-0022.
        if !isSafeCall, receiverType != sema.types.errorType {
            receiverType = driver.callChecker.resolveSuperMemberReceiverType(
                receiverID: receiver,
                receiverType: receiverType,
                calleeName: name,
                isPropertyAccess: true,
                ctx: ctx
            )
        }
        // The invalid super receiver already emitted its own diagnostic;
        // looking a member up on the error type adds a second, unrelated
        // "unresolved" error.
        if receiverType == sema.types.errorType,
           case .superRef = ctx.ast.arena.expr(receiver)
        {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        let memberResult = driver.helpers.lookupMemberPropertyForWrite(
            named: name, receiverType: nonNullReceiver, sema: sema
        )
        if let member = memberResult {
            let writeSymbol = member.writeSymbol ?? member.symbol
            // Resolve the write type before inferring the RHS, including contextual
            // integer literals and lambdas. The read type is unsafe for projections.
            let writeType = driver.helpers.memberPropertyWriteType(
                symbol: writeSymbol, receiverType: nonNullReceiver, fallback: member.type, sema: sema
            )
            let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: writeType)
            driver.recordGenericCallConsumer(
                value, type: sema.symbols.propertyType(for: writeSymbol) ?? writeType
            )
            sema.bindings.bindIdentifier(id, symbol: writeSymbol)
            driver.helpers.checkDeprecation(
                for: writeSymbol,
                sema: sema,
                interner: ctx.interner,
                range: range,
                diagnostics: sema.diagnostics
            )
            driver.helpers.checkOptIn(
                for: writeSymbol,
                ctx: ctx,
                range: range,
                diagnostics: sema.diagnostics
            )
            if let property = sema.symbols.symbol(writeSymbol) {
                if !ctx.visibilityChecker.isAccessible(property, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol) {
                    driver.helpers.emitVisibilityError(
                        for: property, name: ctx.interner.resolve(name), range: range, diagnostics: sema.diagnostics
                    )
                } else if member.writeSymbol == nil,
                          !(ctx.allowsValPropertyInitialization && isInitializingOwnProperty(receiver, property: member.symbol, ctx: ctx)) {
                    sema.diagnostics.error("KSWIFTK-SEMA-0014", "Val cannot be reassigned.", range: range)
                } else {
                    if let visibility = sema.symbols.propertySetterVisibility(for: writeSymbol) {
                        let setter = SemanticSymbol(
                            id: property.id, kind: property.kind, name: property.name, fqName: property.fqName,
                            declSite: property.declSite, visibility: visibility, flags: property.flags
                        )
                        if !ctx.visibilityChecker.isAccessible(setter, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol) {
                            driver.helpers.emitVisibilityError(
                                for: setter, name: ctx.interner.resolve(name), range: range, diagnostics: sema.diagnostics
                            )
                        }
                    }
                    if member.writeSymbol != nil {
                        collectReceiverBuilderPropertyWriteConstraint(
                            valueType: valueType, writeType: writeType,
                            value: value, range: range, ctx: ctx
                        )
                    }
                    driver.emitSubtypeConstraint(
                        left: valueType, right: writeType, range: range, solver: ConstraintSolver(),
                        sema: sema, diagnostics: sema.diagnostics
                    )
                    driver.helpers.recordMemberValInitializationSmartCast(
                        property: writeSymbol,
                        declaredType: writeType,
                        valueType: valueType,
                        ctx: ctx,
                        locals: &locals
                    )
                }
            }
            if !isSafeCall, sema.types.nullability(of: receiverType) == .nullable {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0026",
                    "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                    range: range
                )
            }
        } else {
            // Extension setter resolution provides the RHS context when its
            // candidates agree on a value type, just as member-property writes do.
            let errorsBeforeResolution = sema.diagnostics.errorCount
            let setter = driver.callChecker.resolveExtensionPropertySetter(
                id: id, calleeName: name, range: range,
                receiverType: isSafeCall ? nonNullReceiver : receiverType,
                value: value, locals: &locals, ctx: ctx
            )
            if setter == nil, sema.diagnostics.errorCount == errorsBeforeResolution {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0022", "Unresolved reference '\(ctx.interner.resolve(name))'.", range: range
                )
            }
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    private func isInitializingOwnProperty(_ receiver: ExprID, property: SymbolID, ctx: TypeInferenceContext) -> Bool {
        guard case .thisRef = ctx.ast.arena.expr(receiver),
              ctx.sema.symbols.parentSymbol(for: property) == ctx.enclosingClassSymbol
        else { return false }
        return true
    }
}
