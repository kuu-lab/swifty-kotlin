
final class DeclTypeChecker {
    unowned let driver: TypeCheckDriver
    var annotationConstantEvaluator: ConstPropertyEvaluator?
    var pendingAnnotationConstants: [(ExprID, TypeInferenceContext, Bool)] = []

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    private func emitLateinitMustBeNonNullDiagnostic(
        for property: PropertyDecl,
        diagnostics: DiagnosticEngine
    ) {
        diagnostics.error(
            "KSWIFTK-SEMA-LATEINIT",
            "'lateinit' property type must be non-null.",
            range: property.range
        )
    }

    func validateOptInTypeUsage(
        _ type: TypeID,
        ctx: TypeInferenceContext,
        range: SourceRange?
    ) {
        driver.helpers.checkOptInForType(
            type,
            ctx: ctx,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
    }

    func validateFunctionHeaderOptInTypes(
        _ symbol: SymbolID,
        ctx: TypeInferenceContext,
        hasExplicitReturnType: Bool
    ) {
        guard let signature = ctx.sema.symbols.functionSignature(for: symbol) else {
            return
        }
        let range = ctx.sema.symbols.symbol(symbol)?.declSite
        if let receiverType = signature.receiverType {
            validateOptInTypeUsage(receiverType, ctx: ctx, range: range)
        }
        for parameterType in signature.parameterTypes {
            validateOptInTypeUsage(parameterType, ctx: ctx, range: range)
        }
        // An inferred return type is validated by its body usages. Rechecking
        // the refined signature after speculative inference would duplicate them.
        if hasExplicitReturnType {
            validateOptInTypeUsage(signature.returnType, ctx: ctx, range: range)
        }
    }

    func validatePropertyHeaderOptInTypes(
        _ symbol: SymbolID,
        ctx: TypeInferenceContext
    ) {
        let range = ctx.sema.symbols.symbol(symbol)?.declSite
        if let binding = ctx.sema.bindings.primaryConstructorPropertyParameters[symbol],
           let propertyType = ctx.sema.symbols.propertyType(for: symbol) {
            // Kotlin 2.3.10 also accepts the corresponding parameter's consent
            // for a generated property header. Keep it out of bodies and callers.
            driver.helpers.checkPrimaryConstructorPropertyHeaderOptIn(
                parameter: binding.parameter, parameterType: binding.type,
                propertyType: propertyType, constructor: binding.constructor,
                ctx: ctx, range: range
            )
            return
        }
        if let receiverType = ctx.sema.symbols.extensionPropertyReceiverType(for: symbol) {
            validateOptInTypeUsage(receiverType, ctx: ctx, range: range)
        }
        if let propertyType = ctx.sema.symbols.propertyType(for: symbol) {
            validateOptInTypeUsage(propertyType, ctx: ctx, range: range)
        }
    }

    func validateClassLikeHeaderOptInTypes(
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        range: SourceRange?
    ) {
        for supertypeSymbol in ctx.sema.symbols.directSupertypes(for: symbol) {
            let supertype = ctx.sema.types.make(.classType(ClassType(
                classSymbol: supertypeSymbol,
                args: [],
                nullability: .nonNull
            )))
            validateOptInTypeUsage(supertype, ctx: ctx, range: range)
        }
        driver.helpers.checkSubclassOptInRequirements(
            forClassLike: symbol,
            ctx: ctx,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
    }

    func inferFunctionBodyType(
        _ body: FunctionBody,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        ctx.dataFlow.localStability.analyze(body, ast: ctx.ast)
        switch body {
        case .unit:
            return ctx.sema.types.unitType

        case let .expr(exprID, _):
            let type = driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedType)
            if !ctx.isPropertyGetterReturn, expectedType == ctx.sema.types.unitType,
               ctx.sema.types.makeNonNullable(type) == ctx.sema.types.unitType
            {
                ctx.sema.bindings.markUnitReturnCoercion(exprID)
            }
            return type

        case let .block(exprIDs, _):
            let bodyCtx = ctx.copying(
                scope: BlockScope(parent: ctx.scope, symbols: ctx.sema.symbols)
            )
            var canComplete = true
            for exprID in exprIDs {
                if !canComplete {
                    if let stmtRange = bodyCtx.ast.arena.exprRange(exprID) {
                        bodyCtx.sema.diagnostics.warning(
                            "KSWIFTK-SEMA-0096",
                            "Unreachable code.",
                            range: stmtRange
                        )
                    }
                    _ = driver.inferExpr(exprID, ctx: bodyCtx, locals: &locals, expectedType: nil, isStatementContext: true)
                    continue
                }
                // Pass expectedType to return expressions (so the return value is
                // checked against the function return type), but NOT to the last
                // expression of a block body (where it's just a statement).
                let exprExpectedType: TypeID? = if let expr = bodyCtx.ast.arena.expr(exprID),
                                                   case .returnExpr = expr
                {
                    expectedType
                } else {
                    nil
                }
                _ = driver.inferExpr(exprID, ctx: bodyCtx, locals: &locals, expectedType: exprExpectedType, isStatementContext: true)
                canComplete = driver.controlFlowChecker.canCompleteNormally(exprID, ctx: bodyCtx)
            }
            if !canComplete {
                return ctx.sema.types.nothingType
            }
            return ctx.sema.types.unitType
        }
    }

    func typeCheckPropertyDecl(
        _ property: PropertyDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:],
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let annotations = property.annotations + (ctx.sema.bindings.primaryConstructorPropertyAnnotations[symbol] ?? [])
        typeCheckAnnotationFactories(annotations, symbol: symbol, ctx: ctx)
        let sema = ctx.sema
        var inferredPropertyType: TypeID? = property.type != nil
            ? sema.symbols.propertyType(for: symbol)
            : nil

        if let initializer = property.initializer {
            var locals: LocalBindings = initialLocals
            if inferredPropertyType != nil {
                sema.bindings.markSourceDeclaredExpectedType(initializer)
            }
            let initializerType = driver.inferExpr(
                initializer, ctx: ctx.with(initializingPropertySymbol: symbol), locals: &locals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                let rangeExprSatisfiesIterableAnnotation: Bool = {
                    guard sema.bindings.isRangeExpr(initializer),
                          driver.helpers.isPlainIterableType(
                              declaredType,
                              sema: sema,
                              interner: ctx.interner
                          ),
                          let declaredElementType = driver.helpers.plainIterableElementType(
                              for: declaredType,
                              sema: sema,
                              interner: ctx.interner
                          ),
                          let rangeElementType = driver.helpers.iterableElementType(
                              for: initializerType,
                              isRangeExpr: true,
                              isCharRangeExpr: sema.bindings.isCharRangeExpr(initializer),
                              sema: sema,
                              interner: ctx.interner
                          )
                    else {
                        return false
                    }
                    return declaredElementType == rangeElementType
                }()
                if rangeExprSatisfiesIterableAnnotation
                    || driver.helpers.rangeExprMatchesDeclaredElementType(
                        bodyExprID: initializer,
                        bodyType: initializerType,
                        declaredType: declaredType,
                        sema: sema,
                        interner: ctx.interner
                    )
                {
                    // Range expressions keep their runtime representation separate
                    // from the source-level range interface, so accept a matching
                    // range-like or plain Iterable annotation without forcing a
                    // nominal subtype check (mirrors inferLocalDeclExpr).
                } else {
                    driver.emitSubtypeConstraint(
                        left: initializerType, right: declaredType,
                        range: property.range, solver: solver,
                        sema: sema, diagnostics: diagnostics
                    )
                }
            } else {
                inferredPropertyType = initializerType
            }
            // Propagate the initializer's value marks onto the property symbol,
            // mirroring inferLocalDeclExpr: reads of this property must keep the
            // range/collection/flow classification so `x in range`, `r.isEmpty()`
            // and member probes resolve to the typed runtime bridges instead of
            // the generic interface path (KUU-2942).
            let declaredOpenEndRange = inferredPropertyType.map {
                driver.helpers.isOpenEndRangeType($0, sema: sema, interner: ctx.interner)
            } ?? false
            // A `var` annotated with `ClosedRange`/`ClosedFloatingPointRange`
            // can be reassigned to a user-defined range implementation, whose
            // object is not a runtime range box. Its reads must keep the
            // interface/probe path (which handles both representations) rather
            // than being pinned to the box layout, so do not record the value
            // marks. `OpenEndRange` is excluded: its unmarked `contains`
            // resolution already binds `__kk_range_contains`, which rejects
            // floating-point boxes outright — the marks are the only path that
            // reaches `__kk_double_range_contains` there.
            let mutableNonBoxedRangeHolder = property.isVar
                && property.type != nil
                && !declaredOpenEndRange
                && inferredPropertyType.map {
                    nominalRangeElementType(for: $0, sema: sema, interner: ctx.interner) == nil
                } ?? false
            if !mutableNonBoxedRangeHolder, sema.bindings.isRangeExpr(initializer) || declaredOpenEndRange {
                sema.bindings.markRangeSymbol(symbol)
                if sema.bindings.isCharRangeExpr(initializer) {
                    sema.bindings.markCharRangeSymbol(symbol)
                }
                if sema.bindings.isUIntRangeExpr(initializer) {
                    sema.bindings.markUIntRangeSymbol(symbol)
                }
                if sema.bindings.isULongRangeExpr(initializer) {
                    sema.bindings.markULongRangeSymbol(symbol)
                }
                if sema.bindings.isFloatingPointRangeExpr(initializer) {
                    sema.bindings.markFloatingPointRangeSymbol(symbol)
                    if let elementType = sema.bindings.floatingPointRangeElementType(forExpr: initializer) {
                        sema.bindings.bindFloatingPointRangeElementType(
                            elementType,
                            forSymbol: symbol,
                            endExclusive: sema.bindings.isOpenFloatingPointRangeExpr(initializer)
                        )
                    }
                }
            }
            if !mutableNonBoxedRangeHolder {
                if sema.bindings.isCollectionExpr(initializer) {
                    sema.bindings.markCollectionSymbol(symbol)
                }
                if sema.bindings.isFlowExpr(initializer) {
                    sema.bindings.markFlowSymbol(symbol)
                    if let flowElementType = sema.bindings.flowElementType(forExpr: initializer) {
                        sema.bindings.bindFlowElementType(flowElementType, forSymbol: symbol)
                    }
                }
                if let deferredElementType = sema.bindings.deferredElementType(forExpr: initializer) {
                    sema.bindings.bindDeferredElementType(deferredElementType, forSymbol: symbol)
                }
            }
        }

        if let explicitField = property.explicitBackingField {
            let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol)
            let explicitFieldType = explicitField.type.flatMap { _ in
                backingFieldSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            }
            if let explicitFieldType {
                if let declaredPropertyType = inferredPropertyType {
                    driver.emitSubtypeConstraint(
                        left: explicitFieldType, right: declaredPropertyType,
                        range: property.range, solver: solver,
                        sema: sema, diagnostics: diagnostics
                    )
                } else {
                    inferredPropertyType = explicitFieldType
                }
            }

            if let initializer = explicitField.initializer {
                let expectedType = explicitFieldType ?? inferredPropertyType
                var locals: LocalBindings = initialLocals
                if expectedType != nil {
                    sema.bindings.markSourceDeclaredExpectedType(initializer)
                }
                let initializerType = driver.inferExpr(
                    initializer,
                    ctx: ctx.with(initializingPropertySymbol: symbol),
                    locals: &locals,
                    expectedType: expectedType
                )

                if let explicitFieldType {
                    driver.emitSubtypeConstraint(
                        left: initializerType, right: explicitFieldType,
                        range: property.range, solver: solver,
                        sema: sema, diagnostics: diagnostics
                    )
                } else if let declaredPropertyType = inferredPropertyType {
                    driver.emitSubtypeConstraint(
                        left: initializerType, right: declaredPropertyType,
                        range: property.range, solver: solver,
                        sema: sema, diagnostics: diagnostics
                    )
                    if !property.isVar,
                       !sema.symbols.propertyHasCustomGetter(for: symbol),
                       sema.types.isSubtype(initializerType, declaredPropertyType),
                       let backingFieldSymbol
                    {
                        sema.symbols.setPropertyType(initializerType, for: backingFieldSymbol)
                    }
                } else {
                    inferredPropertyType = initializerType
                    if let backingFieldSymbol {
                        sema.symbols.setPropertyType(initializerType, for: backingFieldSymbol)
                    }
                }
            }
        }

        // Preserve the extension receiver and its property-name label across
        // nested receiver lambdas in getter/setter bodies.
        let extRecv = sema.symbols
            .extensionPropertyReceiverType(for: symbol)
        var accessorCtx: TypeInferenceContext = if let extRecv {
            ctx.copying(implicitReceiverType: extRecv).withOuterReceiver(
                label: property.name,
                type: extRecv,
                symbol: SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            )
        } else {
            ctx
        }
        if let extRecv {
            accessorCtx = addingCompanionLookupReceiver(
                to: accessorCtx,
                receiverType: extRecv,
                enabled: property.modifiers.contains(.companion)
            )
        }

        if let getter = property.getter {
            inferredPropertyType = typeCheckGetter(
                getter, property: property, symbol: symbol,
                inferredPropertyType: inferredPropertyType,
                accessorCtx: accessorCtx, solver: solver,
                diagnostics: diagnostics
            )
        }

        if let delegateExpr = property.delegateExpression {
            // A delegated property expression has the same initializer scope as
            // an ordinary property initializer, including bare primary
            // constructor parameters.
            var delegateLocals: LocalBindings = initialLocals
            // DEBT-KIR-008/BUG-170: a stdlib delegate factory's trailing lambda
            // (delegateBody) is parsed as a separate FunctionBody from
            // delegateExpression specifically so KIR lowering can repackage it
            // into a standalone synthetic function, so ordinary call-argument
            // inference never visits it -- identifier references inside it
            // (e.g. a captured `this`-implicit property) never got an
            // identifierSymbols binding at all and silently lowered to `.unit`
            // in KIR. `typeCheckDelegate` type-checks the body itself (for any
            // known stdlib delegate kind, not just `.lazy`: BUG-151 made
            // `.observable`/`.vetoable`'s three synthetic callback parameters
            // resolvable by name via `SyntheticSymbolScheme
            // .delegateLambdaParameterSymbol`, so binding them as locals here no
            // longer risks a spurious "unresolved reference" diagnostic).
            inferredPropertyType = typeCheckDelegate(
                delegateExpr, isVar: property.isVar,
                fallbackRange: property.range,
                symbol: symbol,
                inferredPropertyType: inferredPropertyType,
                ctx: ctx,
                locals: &delegateLocals,
                diagnostics: diagnostics,
                delegateBody: property.delegateBody,
                delegateBodyParams: property.delegateBodyParams
            )
        }

        let inferred = inferredPropertyType ?? sema.types.nullableAnyType
        let finalPropertyType = property.type == nil ? exposedAnonymousType(inferred, symbol: symbol, range: property.range, ctx: ctx) : inferred
        sema.symbols.setPropertyType(finalPropertyType, for: symbol)

        if property.modifiers.contains(.lateinit) {
            validateLateinitProperty(
                property,
                finalPropertyType: finalPropertyType,
                diagnostics: diagnostics,
                sema: sema
            )
        }

        if let setter = property.setter {
            typeCheckSetter(
                setter, property: property, symbol: symbol,
                finalPropertyType: finalPropertyType,
                accessorCtx: accessorCtx, solver: solver,
                diagnostics: diagnostics
            )
        }
    }

    private func validateLateinitProperty(
        _ property: PropertyDecl,
        finalPropertyType: TypeID,
        diagnostics: DiagnosticEngine,
        sema: SemaModule
    ) {
        if !property.isVar {
            diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'lateinit' is only allowed on mutable properties.",
                range: property.range
            )
        }
        if property.initializer != nil {
            diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'lateinit' property must not have an initializer.",
                range: property.range
            )
        }
        if property.type == nil {
            diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'lateinit' property must declare an explicit non-null reference type.",
                range: property.range
            )
        }

        switch sema.types.kind(of: finalPropertyType) {
        case let .stringStruct(nullability):
            if nullability == .nullable {
                emitLateinitMustBeNonNullDiagnostic(for: property, diagnostics: diagnostics)
            }
        case let .primitive(primitive, nullability):
            if nullability == .nullable {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' property type must be non-null.",
                    range: property.range
                )
            } else if primitive == .boolean
                || primitive == .char
                || primitive == .int
                || primitive == .long
                || primitive == .float
                || primitive == .double
                || primitive == .uint
                || primitive == .ulong
                || primitive == .ubyte
                || primitive == .ushort
            {
                diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' is not allowed on primitive property types.",
                    range: property.range
                )
            }
        case let .classType(classType):
            if classType.nullability == .nullable {
                emitLateinitMustBeNonNullDiagnostic(for: property, diagnostics: diagnostics)
            }
        case let .typeParam(typeParam):
            if typeParam.nullability == .nullable {
                emitLateinitMustBeNonNullDiagnostic(for: property, diagnostics: diagnostics)
            }
        case let .functionType(functionType):
            if functionType.nullability == .nullable {
                emitLateinitMustBeNonNullDiagnostic(for: property, diagnostics: diagnostics)
            }
        case let .nothing(nullability):
            if nullability == .nullable {
                emitLateinitMustBeNonNullDiagnostic(for: property, diagnostics: diagnostics)
            }
        case let .any(nullability):
            if nullability == .nullable {
                emitLateinitMustBeNonNullDiagnostic(for: property, diagnostics: diagnostics)
            }
        case let .kClassType(kClassType):
            if kClassType.nullability == .nullable {
                emitLateinitMustBeNonNullDiagnostic(for: property, diagnostics: diagnostics)
            }
        case .nullableUnit:
            emitLateinitMustBeNonNullDiagnostic(for: property, diagnostics: diagnostics)
        case .error, .unit, .platformUnit, .intersection:
            break
        }
    }
}
