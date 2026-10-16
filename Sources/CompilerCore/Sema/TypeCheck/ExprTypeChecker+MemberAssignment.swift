extension ExprTypeChecker {
    func inferMemberAssignExpr(
        _ id: ExprID,
        receiver: ExprID,
        name: InternedString,
        value: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let inferredReceiver = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        let receiverType = driver.helpers.retypeClassNameAsCompanionValue(
            receiver, currentType: inferredReceiver, ast: ctx.ast, sema: sema
        ) ?? inferredReceiver
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        if let member = driver.helpers.lookupMemberPropertyForWrite(
            named: name, receiverType: nonNullReceiver, sema: sema
        ) {
            let writeSymbol = member.writeSymbol ?? member.symbol
            // Resolve the write type before inferring the RHS, including contextual
            // integer literals and lambdas. The read type is unsafe for projections.
            let writeType = driver.helpers.memberPropertyWriteType(
                symbol: writeSymbol, receiverType: nonNullReceiver, fallback: member.type, sema: sema
            )
            let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: writeType)
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
                    driver.emitSubtypeConstraint(
                        left: valueType, right: writeType, range: range, solver: ConstraintSolver(),
                        sema: sema, diagnostics: sema.diagnostics
                    )
                }
            }
            if sema.types.nullability(of: receiverType) == .nullable {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0026",
                    "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                    range: range
                )
            }
        } else {
            // Extension properties keep their existing overload/setter resolution.
            let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            let errorsBeforeResolution = sema.diagnostics.errorCount
            let setter = driver.callChecker.resolveExtensionPropertySetter(
                id: id, calleeName: name, range: range, receiverType: receiverType, valueType: valueType, ctx: ctx
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
