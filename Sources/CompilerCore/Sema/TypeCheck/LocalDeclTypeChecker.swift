
final class LocalDeclTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func inferLocalDeclExpr(
        _ id: ExprID,
        name: InternedString,
        isMutable: Bool,
        typeAnnotation: TypeRefID?,
        initializer: ExprID?,
        isDelegated: Bool,
        isLateinit: Bool,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        driver.diagnoseLocalValueOrClassifierRedeclaration(
            named: name,
            expression: id,
            range: range,
            ctx: ctx
        )

        var declaredType: TypeID?
        if let typeAnnotation {
            declaredType = driver.helpers.resolveTypeRef(
                typeAnnotation,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.sema.diagnostics,
                inferenceContext: ctx,
                usageRange: range
            )
        }

        // The delegate resolution below needs a symbol to key getValue/setValue
        // onto, so the symbol is defined up front instead of after localType.
        var localFlags: SymbolFlags = isMutable ? [.mutable] : []
        if isLateinit, isMutable { localFlags.insert(.lateinitProperty) }
        let localSymbol = sema.symbols.define(
            kind: .local,
            name: name,
            fqName: [
                ctx.interner.intern("__local_\(id.rawValue)"),
                name,
            ],
            declSite: range,
            visibility: .private,
            flags: localFlags
        )

        let localType: TypeID
        if isDelegated, let initializer {
            // Resolve getValue (and setValue for `var`) against the delegate
            // expression's type, exactly as member/top-level delegated properties
            // do (DeclTypeChecker.typeCheckDelegate); otherwise the local's type
            // silently falls back to the delegate instance's own type below, and
            // KIR lowering has no resolved operator to call — `val x by Prop()`
            // binds `x` straight to the `Prop()` instance instead of
            // `Prop().getValue(...)`.
            localType = driver.declChecker.typeCheckDelegate(
                initializer,
                isVar: isMutable,
                fallbackRange: range,
                symbol: localSymbol,
                inferredPropertyType: declaredType,
                ctx: ctx,
                locals: &locals,
                diagnostics: ctx.sema.diagnostics
            ) ?? declaredType ?? sema.types.nullableAnyType
        } else {
            var initializerType: TypeID?
            if let initializer {
                if declaredType != nil {
                    sema.bindings.markSourceDeclaredExpectedType(initializer)
                }
                initializerType = driver.inferExpr(initializer, ctx: ctx, locals: &locals, expectedType: declaredType)
                if declaredType == nil,
                   sema.bindings.callableRefKind(for: initializer) != nil {
                    sema.bindings.inferredCallableReferenceSymbols.insert(localSymbol)
                }
            }

            if let declaredType {
                localType = declaredType
                if let initializerType {
                    let rangeExprSatisfiesIterableAnnotation: Bool = {
                        guard let initializer,
                              sema.bindings.isRangeExpr(initializer),
                              driver.helpers.isPlainIterableType(
                                  declaredType,
                                  sema: sema,
                                  interner: interner
                              ),
                              let declaredElementType = driver.helpers.plainIterableElementType(
                                  for: declaredType,
                                  sema: sema,
                                  interner: interner
                              ),
                              let rangeElementType = driver.helpers.iterableElementType(
                                  for: initializerType,
                                  isRangeExpr: true,
                                  isCharRangeExpr: sema.bindings.isCharRangeExpr(initializer),
                                  sema: sema,
                                  interner: interner
                              )
                        else {
                            return false
                        }
                        return declaredElementType == rangeElementType
                    }()
                    if rangeExprSatisfiesIterableAnnotation
                        || (initializer.map {
                            driver.helpers.rangeExprMatchesDeclaredElementType(
                                bodyExprID: $0,
                                bodyType: initializerType,
                                declaredType: declaredType,
                                sema: sema,
                                interner: interner
                            )
                        } ?? false)
                    {
                        // Range expressions keep their runtime representation separate from
                        // the source-level range interface, so accept a matching range-like or
                        // plain Iterable annotation without forcing a nominal subtype check.
                    } else {
                        driver.emitSubtypeConstraint(
                            left: initializerType, right: declaredType,
                            range: range, solver: ConstraintSolver(),
                            sema: sema, diagnostics: ctx.sema.diagnostics
                        )
                    }
                }
            } else if let initializerType {
                let retypedInitializerType = initializer.flatMap {
                    driver.helpers.retypeClassNameAsCompanionValue(
                        $0, currentType: initializerType, ast: ast, sema: sema
                    )
                } ?? initializerType
                localType = isMutable
                    ? inferredMutableLocalStorageType(
                        initializer: initializer,
                        initializerType: initializerType,
                        ctx: ctx,
                        locals: locals
                    ) ?? retypedInitializerType
                    : retypedInitializerType
            } else {
                localType = sema.types.errorType
            }
        }
        if isLateinit {
            // The parser already diagnoses source-level `lateinit val`. Keep
            // programmatically constructed ASTs checked without duplicating it.
            let diagnosedVal = ctx.sema.diagnostics.diagnostics.contains { diagnostic in
                diagnostic.code == "KSWIFTK-SEMA-0418"
                    && diagnostic.primaryRange.map { range.contains($0) } == true
            }
            if !isMutable, !diagnosedVal {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0418",
                    "'lateinit' modifier is allowed only on mutable properties.",
                    range: range
                )
            }
            if initializer != nil || isDelegated {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' local variable must not have an initializer or delegate.",
                    range: range
                )
            }
            if typeAnnotation == nil {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' local variable must declare an explicit non-null reference type.",
                    range: range
                )
            }
            if !lateinitLocalTypeIsDefinitelyNonNull(localType, sema: sema) {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' local variable type must be non-null.",
                    range: range
                )
            } else if case .primitive = sema.types.kind(of: localType) {
                // Includes Byte/Short and every unsigned primitive.
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' is not allowed on primitive local variable types.",
                    range: range
                )
            } else if case let .classType(classType) = sema.types.kind(of: localType),
                      sema.symbols.symbol(classType.classSymbol)?.flags.contains(.valueType) == true
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-LATEINIT",
                    "'lateinit' is not allowed on local variable types that are value classes.",
                    range: range
                )
            }
        }
        sema.symbols.setPropertyType(localType, for: localSymbol)
        locals[name] = (localType, localSymbol, isMutable, initializer != nil)
        if isMutable, initializer != nil, !isDelegated,
           ctx.dataFlow.localStability.isNeverReassigned(id)
        {
            ctx.dataFlow.stableMutableReceivers.insert(localSymbol)
        }
        if isMutable {
            ctx.dataFlow.localDeclarations[localSymbol] = id
        }
        sema.bindings.bindIdentifier(id, symbol: localSymbol)
        // A `var` annotated with a range interface (or any other type that is
        // not a concrete range class) can be reassigned to a user-defined
        // range implementation, whose object is not a runtime range box. Its
        // reads must keep the interface/probe path rather than being pinned to
        // the box layout, so do not record the value marks. `OpenEndRange` is
        // excluded: its unmarked `contains` resolution already binds
        // `__kk_range_contains`, which rejects floating-point boxes outright —
        // the marks are the only path that reaches `__kk_double_range_contains`
        // there.
        let declaredOpenEndRange = declaredType.map {
            driver.helpers.isOpenEndRangeType($0, sema: sema, interner: interner)
        } ?? false
        let mutableNonBoxedRangeHolder = isMutable
            && typeAnnotation != nil
            && !declaredOpenEndRange
            && declaredType.map {
                nominalRangeElementType(for: $0, sema: sema, interner: interner) == nil
            } ?? false
        // Propagate collection marks through local variable declarations
        // so that `val list = listOf(1,2,3); list.size` still recognizes
        // `list` as a collection receiver (P5-84).
        if let initializer, !mutableNonBoxedRangeHolder, sema.bindings.isCollectionExpr(initializer) {
            sema.bindings.markCollectionExpr(id)
            sema.bindings.markCollectionSymbol(localSymbol)
        }
        if let initializer {
            if !mutableNonBoxedRangeHolder, sema.bindings.isRangeExpr(initializer) || declaredOpenEndRange {
                sema.bindings.markRangeExpr(id)
                sema.bindings.markRangeSymbol(localSymbol)
                if sema.bindings.isCharRangeExpr(initializer) {
                    sema.bindings.markCharRangeExpr(id)
                    sema.bindings.markCharRangeSymbol(localSymbol)
                }
                if sema.bindings.isUIntRangeExpr(initializer) {
                    sema.bindings.markUIntRangeExpr(id)
                    sema.bindings.markUIntRangeSymbol(localSymbol)
                }
                if sema.bindings.isULongRangeExpr(initializer) {
                    sema.bindings.markULongRangeExpr(id)
                    sema.bindings.markULongRangeSymbol(localSymbol)
                }
                if sema.bindings.isFloatingPointRangeExpr(initializer) {
                    sema.bindings.markFloatingPointRangeExpr(id)
                    sema.bindings.markFloatingPointRangeSymbol(localSymbol)
                    if let elementType = sema.bindings.floatingPointRangeElementType(forExpr: initializer) {
                        let endExclusive = sema.bindings.isOpenFloatingPointRangeExpr(initializer)
                        sema.bindings.bindFloatingPointRangeElementType(elementType, forExpr: id, endExclusive: endExclusive)
                        sema.bindings.bindFloatingPointRangeElementType(elementType, forSymbol: localSymbol, endExclusive: endExclusive)
                    }
                }
            }
        }
        if let initializer, !mutableNonBoxedRangeHolder, sema.bindings.isFlowExpr(initializer) {
            sema.bindings.markFlowExpr(id)
            sema.bindings.markFlowSymbol(localSymbol)
            if let flowElementType = sema.bindings.flowElementType(forExpr: initializer) {
                sema.bindings.bindFlowElementType(flowElementType, forExpr: id)
                sema.bindings.bindFlowElementType(flowElementType, forSymbol: localSymbol)
            }
        }
        if let initializer, !mutableNonBoxedRangeHolder, let deferredElementType = sema.bindings.deferredElementType(forExpr: initializer) {
            sema.bindings.bindDeferredElementType(deferredElementType, forExpr: id)
            sema.bindings.bindDeferredElementType(deferredElementType, forSymbol: localSymbol)
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    private func inferredMutableLocalStorageType(
        initializer: ExprID?,
        initializerType: TypeID,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        guard initializerType != sema.types.errorType,
              initializerType != sema.types.nothingType,
              let initializer,
              let reference = ctx.dataFlow.resolveStableReference(
                  initializer,
                  locals: locals,
                  ast: ctx.ast,
                  sema: sema,
                  interner: ctx.interner
              ),
              reference.isStable,
              reference.symbol.properties.isEmpty,
              reference.type == initializerType,
              let declaredType = declaredType(for: reference.symbol, ctx: ctx),
              declaredType != initializerType,
              sema.types.isSubtype(initializerType, declaredType)
        else {
            return nil
        }

        // A mutable copy of a stable reference keeps its declared storage type,
        // even when reads of that reference are flow-narrowed in this branch.
        return declaredType
    }

    private func declaredType(
        for reference: DataFlowReference,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        if let propertyType = sema.symbols.propertyType(for: reference.root) {
            return propertyType
        }
        guard let owner = sema.symbols.valueParameterOwner(for: reference.root),
              let signature = sema.symbols.functionSignature(for: owner),
              let index = signature.valueParameterSymbols.firstIndex(of: reference.root)
        else {
            return nil
        }
        return driver.declChecker.localTypeForParameter(
            at: index,
            signature: signature,
            sema: sema,
            interner: ctx.interner
        )
    }

    func inferLocalAssignExpr(
        _ id: ExprID,
        name: InternedString,
        value: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let interner = ctx.interner

        if let local = locals[name] {
            // Reassignment drops any smart cast narrowing applied to the local
            // inside the current branch, so both the constraint and the binding
            // use the declared type again.
            let declaredType = ctx.sema.symbols.propertyType(for: local.symbol) ?? local.type
            // A lambda literal assigned to a local (e.g. a recursive
            // `lateinit var` closure such as `fact = { ... fact(it - 1) ... }`)
            // may reference the target from inside its own body. That read is
            // deferred until the closure is later invoked, not evaluated
            // immediately, so mark the local initialized before inferring the
            // RHS: the lambda body type-checks against a snapshot of `locals`
            // taken at that point, and it must see the target as available.
            if case .lambdaLiteral = ast.arena.expr(value) {
                locals[name] = (local.type, local.symbol, local.isMutable, true)
            }
            let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: declaredType)
            ctx.sema.bindings.bindIdentifier(id, symbol: local.symbol)
            if !local.isMutable, local.isInitialized {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                driver.emitSubtypeConstraint(
                    left: valueType,
                    right: declaredType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: ctx.sema,
                    diagnostics: ctx.sema.diagnostics
                )
                // A stable nullable local assigned a non-null value remains
                // non-null until its next assignment, including captured
                // locals written directly in their own local function.
                let mutatedInClosure = ctx.dataFlow.localDeclarations[local.symbol].map {
                    ctx.dataFlow.localStability.isMutatedInClosure($0, sema: ctx.sema)
                } ?? false
                let narrowsFirstValAssignment = !local.isMutable
                    && !local.isInitialized
                    && !mutatedInClosure
                    && valueType != ctx.sema.types.errorType
                    && valueType != ctx.sema.types.nothingType
                    && valueType != declaredType
                    && ctx.sema.types.isSubtype(valueType, declaredType)
                // A sequenced write gives a stable mutable local the written
                // value's subtype for subsequent reads in this flow branch.
                // The first assignment to an uninitialized val establishes its
                // value too. Keep the declared type when a deferred closure may
                // overwrite the local.
                let assignedType: TypeID = local.isMutable
                    && !mutatedInClosure
                    && valueType != ctx.sema.types.errorType
                    && valueType != declaredType
                    && ctx.sema.types.isSubtype(valueType, declaredType)
                    ? valueType
                    : narrowsFirstValAssignment
                    ? valueType
                    : !mutatedInClosure
                    && ctx.sema.types.nullability(of: declaredType) == .nullable
                    && ctx.sema.types.nullability(of: valueType) == .nonNull
                    && valueType != ctx.sema.types.errorType
                    ? ctx.sema.types.makeNonNullable(declaredType) : declaredType
                locals[name] = (assignedType, local.symbol, local.isMutable, true)
                locals.invalidateMembers(root: local.symbol)
                if ctx.sema.bindings.isFlowExpr(value) {
                    ctx.sema.bindings.markFlowSymbol(local.symbol)
                    if let flowElementType = ctx.sema.bindings.flowElementType(forExpr: value) {
                        ctx.sema.bindings.bindFlowElementType(flowElementType, forSymbol: local.symbol)
                    }
                } else {
                    ctx.sema.bindings.unmarkFlowSymbol(local.symbol)
                }
            }
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }

        var implicitReceiverMember: (lookup: MemberPropertyLookupResult, receiverType: TypeID)?
        for receiverType in ctx.implicitReceiverMemberLookupTypes() {
            let nonNullReceiverType = ctx.sema.types.makeNonNullable(receiverType)
            if let entrySymbol = ctx.currentDeclSymbol,
               let member = driver.helpers.lookupEnumEntryMemberProperty(
                   named: name,
                   entrySymbol: entrySymbol,
                   receiverType: nonNullReceiverType,
                   sema: ctx.sema
               ) {
                implicitReceiverMember = (MemberPropertyLookupResult(
                    symbol: member.symbol, type: member.type, writeSymbol: nil
                ), nonNullReceiverType)
                break
            }
            if let member = driver.helpers.lookupMemberPropertyForWrite(
                named: name,
                receiverType: nonNullReceiverType,
                sema: ctx.sema
            ) {
                implicitReceiverMember = (member, nonNullReceiverType)
                break
            }
        }
        if let (member, receiverType) = implicitReceiverMember
        {
            let writeSymbol = member.writeSymbol ?? member.symbol
            let (_, invisible) = ctx.filterByVisibility([writeSymbol])
            if let property = invisible.first {
                driver.helpers.emitVisibilityError(
                    for: property,
                    name: interner.resolve(name),
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: ctx.sema)
            }
            let writeType = driver.helpers.memberPropertyWriteType(
                symbol: writeSymbol, receiverType: receiverType, fallback: member.type, sema: ctx.sema
            )
            let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: writeType)
            ctx.sema.bindings.bindIdentifier(id, symbol: writeSymbol)
            driver.helpers.checkDeprecation(
                for: writeSymbol, sema: ctx.sema, interner: interner,
                range: range, diagnostics: ctx.sema.diagnostics
            )
            driver.helpers.checkOptIn(
                for: writeSymbol, ctx: ctx, range: range,
                diagnostics: ctx.sema.diagnostics
            )
            let propSymbol = ctx.sema.symbols.symbol(writeSymbol)
            if propSymbol != nil,
               member.writeSymbol == nil,
               !ctx.allowsValPropertyInitialization
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                let setterIsAccessible: Bool = {
                    guard let visibility = ctx.sema.symbols.propertySetterVisibility(for: writeSymbol),
                          let propSymbol
                    else {
                        return true
                    }
                    let setter = SemanticSymbol(
                        id: propSymbol.id,
                        kind: propSymbol.kind,
                        name: propSymbol.name,
                        fqName: propSymbol.fqName,
                        declSite: propSymbol.declSite,
                        visibility: visibility,
                        flags: propSymbol.flags
                    )
                    guard !ctx.visibilityChecker.isAccessible(
                        setter, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                    ) else {
                        return true
                    }
                    driver.helpers.emitVisibilityError(
                        for: setter,
                        name: interner.resolve(name),
                        range: range,
                        diagnostics: ctx.sema.diagnostics
                    )
                    return false
                }()
                if setterIsAccessible {
                    if member.writeSymbol != nil {
                        driver.exprChecker.collectReceiverBuilderPropertyWriteConstraint(
                            valueType: valueType, writeType: writeType,
                            value: value, range: range, ctx: ctx
                        )
                    }
                    driver.emitSubtypeConstraint(
                        left: valueType,
                        right: writeType,
                        range: range,
                        solver: ConstraintSolver(),
                        sema: ctx.sema,
                        diagnostics: ctx.sema.diagnostics
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
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }

        // Find the nearest assignable property in the scope chain. A same-named
        // function in an inner class scope must not hide a top-level property.
        let allCandidateIDs = ctx.cachedScopeLookup(name, matching: { candidateID in
            guard let candidate = ctx.cachedSymbol(candidateID), candidate.kind == .property else {
                return false
            }
            guard let parentID = ctx.sema.symbols.parentSymbol(for: candidateID),
                  let parentSymbol = ctx.cachedSymbol(parentID)
            else {
                return true
            }
            return parentSymbol.kind == .package || parentSymbol.kind == .object
                || (ctx.implicitReceiverType != nil
                    && (parentSymbol.kind == .class || parentSymbol.kind == .object || parentSymbol.kind == .interface))
        })
        let dslBlockedIDs = allCandidateIDs.filter { ctx.isCandidateBlockedByDslMarker($0) }
        let dslFilteredIDs = allCandidateIDs.filter { !ctx.isCandidateBlockedByDslMarker($0) }
        let (visibleIDs, _) = ctx.filterByVisibility(dslFilteredIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if let propSymbol = candidates.first(where: { $0.kind == .property }) {
            let propType = ctx.sema.symbols.propertyType(for: propSymbol.id) ?? ctx.sema.types.anyType
            let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: propType)
            ctx.sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            driver.helpers.checkDeprecation(
                for: propSymbol.id, sema: ctx.sema, interner: interner,
                range: range, diagnostics: ctx.sema.diagnostics
            )
            driver.helpers.checkOptIn(
                for: propSymbol.id, ctx: ctx, range: range,
                diagnostics: ctx.sema.diagnostics
            )
            if !propSymbol.flags.contains(.mutable), !ctx.allowsValPropertyInitialization {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                driver.emitSubtypeConstraint(
                    left: valueType,
                    right: propType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: ctx.sema,
                    diagnostics: ctx.sema.diagnostics
                )
            }
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }

        // No assignment target was resolved; still type-check the RHS (with no
        // useful expected type) so its sub-expressions get bound types and any
        // diagnostics inside it are still reported.
        _ = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
        if !dslBlockedIDs.isEmpty {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-DSLMARKER",
                "'@DslMarker' implicit access to '\(interner.resolve(name))' from outer receiver is restricted. Use explicit receiver.",
                range: range
            )
        } else if name == KnownCompilerNames(interner: interner).field {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-FIELD",
                "'field' can only be used inside a property getter or setter body.",
                range: range
            )
        } else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0013",
                "Unresolved local variable '\(interner.resolve(name))'.",
                range: range
            )
        }
        ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
        return ctx.sema.types.errorType
    }
}

/// A syntactically non-null `T` can still denote null when its upper bound
/// is nullable (including the implicit `Any?`). Local lateinit needs proof
/// that null cannot be a valid assigned value, since null is its sentinel.
/// Keep this separate from TypeSystem's syntactic nullability API.
func lateinitLocalTypeIsDefinitelyNonNull(
    _ type: TypeID,
    sema: SemaModule,
    visiting: Set<SymbolID> = []
) -> Bool {
    switch sema.types.kind(of: type) {
    case let .typeParam(parameter):
        guard parameter.nullability == .nonNull,
              !visiting.contains(parameter.symbol)
        else { return false }
        let bounds = sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
        // No explicit bound means Any?, never Any. A recursive path without
        // any concrete non-null evidence must not prove its own nullability.
        guard !bounds.isEmpty else { return false }
        let next = visiting.union([parameter.symbol])
        return bounds.contains {
            lateinitLocalTypeIsDefinitelyNonNull($0, sema: sema, visiting: next)
        }
    case let .intersection(parts):
        // A concrete non-null conjunct makes the intersection non-null even
        // when another conjunct is a nullable/recursive type parameter.
        return parts.contains {
            lateinitLocalTypeIsDefinitelyNonNull($0, sema: sema, visiting: visiting)
        }
    default:
        return sema.types.isDefinitelyNonNull(type)
    }
}
