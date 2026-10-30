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
        let inferredReceiver = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
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
        // Class-name receivers (`A.x = v`) denote A's companion scope — the
        // same target the read path resolves before ordinary member lookup.
        // `retypeClassNameAsCompanionValue` only covers `companion object`s;
        // `companion { }` blocks live on the hidden `$CompanionBlocks` object,
        // and `companion`-marked extension properties resolve against the
        // owner nominal itself — neither is reachable through the inferred
        // receiver type (anyType when no companion object exists).
        let classNameOwnerNominal: SymbolID? = isSafeCall
            ? nil
            : driver.helpers.classNameReceiverNominalSymbol(
                forReceiverExpr: receiver, ctx: ctx
            )
        var memberWriteReceiverType = nonNullReceiver
        var memberResult = driver.helpers.lookupMemberPropertyForWrite(
            named: name, receiverType: nonNullReceiver, sema: sema
        )
        if memberResult == nil, let ownerNominal = classNameOwnerNominal {
            for scopeType in driver.helpers.companionScopeProbeTypes(for: ownerNominal, ctx: ctx)
            where scopeType != nonNullReceiver {
                if let companionMember = driver.helpers.lookupMemberPropertyForWrite(
                    named: name, receiverType: scopeType, sema: sema
                ) {
                    memberResult = companionMember
                    memberWriteReceiverType = scopeType
                    // Re-bind the qualifier to the companion scope so
                    // lowering emits the object value a member write
                    // actually dispatches on.
                    sema.bindings.bindExprType(receiver, type: scopeType)
                    break
                }
            }
        }
        if let member = memberResult {
            let writeSymbol = member.writeSymbol ?? member.symbol
            // Resolve the write type before inferring the RHS, including contextual
            // integer literals and lambdas. The read type is unsafe for projections.
            let writeType = driver.helpers.memberPropertyWriteType(
                symbol: writeSymbol, receiverType: memberWriteReceiverType, fallback: member.type, sema: sema
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
            var setter: SymbolID?
            if let ownerNominal = classNameOwnerNominal {
                // A source `companion object`'s type admits ordinary
                // extensions on it (`var A.Companion.x`, `var Any.x`) — the
                // retype above normally covers this, but probe it explicitly
                // for owners whose expression type never retyped (e.g. an
                // alias receiver). A `companion { }` block object is not a
                // value receiver and deliberately gets no unfiltered probe.
                let sourceCompanionSymbol = sema.symbols.companionObjectSymbol(for: ownerNominal)
                    ?? sema.symbols.actualSymbol(for: ownerNominal).flatMap {
                        sema.symbols.companionObjectSymbol(for: $0)
                    }
                let companionObjectType: TypeID? = sourceCompanionSymbol.map {
                    sema.symbols.propertyType(for: $0) ?? sema.types.make(.classType(ClassType(
                        classSymbol: $0, args: [], nullability: .nonNull
                    )))
                }
                if let companionObjectType,
                   companionObjectType != receiverType,
                   sema.diagnostics.errorCount == errorsBeforeResolution
                {
                    setter = driver.callChecker.resolveExtensionPropertySetter(
                        id: id, calleeName: name, range: range,
                        receiverType: companionObjectType,
                        value: value, locals: &locals, ctx: ctx,
                        emitUnresolvedDiagnostics: false
                    )
                    if setter != nil {
                        sema.bindings.bindExprType(receiver, type: companionObjectType)
                    }
                }
                // `companion`-marked extensions (`companion var A.x`) resolve
                // against the owner nominal — the receiver the read path uses
                // for the same qualifier. The companion-only filter keeps a
                // plain `var A.x` from binding where Kotlin reports unresolved.
                if setter == nil,
                   sema.diagnostics.errorCount == errorsBeforeResolution
                {
                    let ownerReceiverType = sema.types.make(.classType(ClassType(
                        classSymbol: ownerNominal, args: [], nullability: .nonNull
                    )))
                    setter = driver.callChecker.resolveExtensionPropertySetter(
                        id: id, calleeName: name, range: range,
                        receiverType: ownerReceiverType,
                        value: value, locals: &locals, ctx: ctx,
                        requireCompanionExtension: true,
                        emitUnresolvedDiagnostics: false
                    )
                    if setter != nil {
                        sema.bindings.bindExprType(receiver, type: ownerReceiverType)
                    }
                }
            }
            if setter == nil, sema.diagnostics.errorCount == errorsBeforeResolution {
                setter = driver.callChecker.resolveExtensionPropertySetter(
                    id: id, calleeName: name, range: range,
                    receiverType: isSafeCall ? nonNullReceiver : receiverType,
                    value: value, locals: &locals, ctx: ctx
                )
            }
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
