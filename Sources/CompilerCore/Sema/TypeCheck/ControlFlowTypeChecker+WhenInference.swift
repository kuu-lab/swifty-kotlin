
extension ControlFlowTypeChecker {
    func inferWhenExpr(
        _ id: ExprID,
        subjectID: ExprID?,
        branches: [WhenBranch],
        elseExpr: ExprID?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        isStatementContext: Bool = false
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.booleanType

        if let subjectID {
            let declaredType = ast.arena.whenSubjectTypeRef(for: id).map {
                driver.helpers.resolveTypeRef(
                    $0, ast: ast, sema: sema, interner: interner,
                    scope: ctx.scope, diagnostics: ctx.sema.diagnostics,
                    inferenceContext: ctx, usageRange: range
                )
            }
            if declaredType != nil {
                sema.bindings.markSourceDeclaredExpectedType(subjectID)
            }
            let initializerType = driver.inferExpr(
                subjectID, ctx: ctx, locals: &locals, expectedType: declaredType
            )
            if let declaredType {
                driver.emitSubtypeConstraint(
                    left: initializerType, right: declaredType,
                    range: ast.arena.exprRange(subjectID), solver: ConstraintSolver(),
                    sema: sema, diagnostics: ctx.sema.diagnostics
                )
            }
            let subjectType = declaredType ?? initializerType
            var ctx = ctx
            if declaredType != nil {
                ctx.whenSubjectTypes[subjectID] = subjectType
            }

            if let subjectVarName = ast.arena.whenSubjectVarName(for: id) {
                let subjectVarSymbol = sema.symbols.define(
                    kind: .local,
                    name: subjectVarName,
                    fqName: [
                        interner.intern("__when_\(id.rawValue)"),
                        subjectVarName,
                    ],
                    declSite: range,
                    visibility: .private,
                    flags: []
                )
                sema.symbols.setPropertyType(subjectType, for: subjectVarSymbol)
                locals[subjectVarName] = (subjectType, subjectVarSymbol, false, true)
                sema.bindings.bindIdentifier(id, symbol: subjectVarSymbol)
            }

            let subjectLocalBinding: (name: InternedString, type: TypeID, symbol: DataFlowReference, isStable: Bool, isMutable: Bool)? = {
                if let subjectVarName = ast.arena.whenSubjectVarName(for: id),
                   let local = locals[subjectVarName]
                {
                    return (
                        subjectVarName, local.type, DataFlowReference(root: local.symbol),
                        driver.helpers.isStableLocalSymbol(local.symbol, sema: sema),
                        local.isMutable
                    )
                }
                guard let reference = ctx.dataFlow.resolveStableReference(
                    subjectID, locals: locals, ast: ast, sema: sema, interner: interner
                ) else { return nil }
                guard let name = locals.first(where: { $0.value.symbol == reference.symbol.root })?.key else { return nil }
                return (
                    name, reference.type, reference.symbol, reference.isStable,
                    locals[name]?.isMutable ?? false
                )
            }()
            let subjectValueFacts: DataFlowValueFacts? = if let subjectLocalBinding,
                                                               subjectLocalBinding.isStable
            {
                ctx.flowState.includingMembers(from: locals)[subjectLocalBinding.symbol]?.valueFacts
            } else {
                nil
            }
            // When the subject is the implicit receiver `this`, narrowing must
            // also update `ctx.implicitReceiverType` so bare-name member
            // access (e.g. `v`, not just `this.v`) resolves against the
            // narrowed type inside each branch.
            let subjectIsImplicitReceiverThis: Bool = {
                guard let subjectExpr = ast.arena.expr(subjectID),
                      case let .thisRef(label, _) = subjectExpr
                else {
                    return false
                }
                return label == nil
            }()
            let hasExplicitNullBranch = branches.contains { branch in
                branch.conditions.contains { cond in
                    guard let conditionExpr = ast.arena.expr(cond),
                          case .nullLiteral = conditionExpr
                    else {
                        return false
                    }
                    return true
                }
            }
            var branchTypes: [TypeID] = []
            var covered: Set<InternedString> = []
            var coveredTypeSymbols: Set<SymbolID> = []
            var negatedTypeCheckTypes: Set<TypeID> = []
            var hasNullCase = false
            var hasTrueCase = false
            var hasFalseCase = false
            var allBranchLocals: [LocalBindings] = []
            let subjectNominalSymbol = driver.helpers.nominalSymbol(of: subjectType, types: sema.types)
            // Tracks all condition "keys" seen across the entire when expression
            // for cross-branch duplicate detection.  A key is a string that
            // uniquely identifies a condition value (e.g. "int:42", "bool:true",
            // "name:Red", "null", "is:TypeName").
            var allSeenConditionKeys: Set<String> = []

            func isNullCondition(_ conditionID: ExprID) -> Bool {
                guard let conditionExpr = ast.arena.expr(conditionID),
                      case .nullLiteral = conditionExpr
                else {
                    return false
                }
                return true
            }

            func recordCoverage(for conditionID: ExprID, conditionType: TypeID) {
                guard let conditionExpr = ast.arena.expr(conditionID) else {
                    return
                }

                func recordResolvedConditionSymbol(_ conditionSymbolID: SymbolID, fallbackName: InternedString?) {
                    guard let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
                        if let fallbackName {
                            covered.insert(fallbackName)
                        }
                        return
                    }
                    switch conditionSymbol.kind {
                    case .field:
                        if let ownerID = sema.symbols.enumOwnerSymbol(for: conditionSymbol),
                           ownerID == subjectNominalSymbol
                        {
                            covered.insert(conditionSymbol.name)
                        } else if let fallbackName {
                            covered.insert(fallbackName)
                        } else {
                            covered.insert(conditionSymbol.name)
                        }

                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        if let subjectNominalSymbol,
                           driver.helpers.isNominalSubtype(conditionSymbolID, of: subjectNominalSymbol, symbols: sema.symbols)
                        {
                            covered.insert(conditionSymbol.name)
                        } else if let fallbackName {
                            covered.insert(fallbackName)
                        } else {
                            covered.insert(conditionSymbol.name)
                        }

                    default:
                        if let fallbackName {
                            covered.insert(fallbackName)
                        } else {
                            covered.insert(conditionSymbol.name)
                        }
                    }
                }

                switch conditionExpr {
                case .boolLiteral(true, _):
                    if conditionType == boolType {
                        hasTrueCase = true
                    }
                    covered.insert(interner.intern("true"))

                case .boolLiteral(false, _):
                    if conditionType == boolType {
                        hasFalseCase = true
                    }
                    covered.insert(interner.intern("false"))

                case .nullLiteral:
                    hasNullCase = true

                case let .nameRef(name, _):
                    guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID] else {
                        covered.insert(name)
                        return
                    }
                    recordResolvedConditionSymbol(conditionSymbolID, fallbackName: name)

                case let .memberCall(_, calleeName, _, args, _):
                    guard args.isEmpty else {
                        break
                    }
                    guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID] else {
                        covered.insert(calleeName)
                        return
                    }
                    recordResolvedConditionSymbol(conditionSymbolID, fallbackName: calleeName)

                case let .isCheck(checkedExprID, _, negated, _):
                    // The parser desugars a bare `is Type` when-branch condition to
                    // `.isCheck(expr: subject, ...)`, reusing the exact subject
                    // ExprID -- so identity comparison is both equivalent to, and
                    // (for synthetic subjects such as `this` or a lambda parameter,
                    // which never get an `identifierSymbols` binding) more reliable
                    // than resolving the checked expression through
                    // `identifierSymbols` and comparing symbols. Qualified or
                    // computed subjects do not have a local binding either, but
                    // their `is` conditions still cover sealed subclasses.
                    guard checkedExprID == subjectID,
                          let targetType = sema.bindings.isCheckTargetType(for: conditionID)
                    else {
                        return
                    }
                    if negated {
                        negatedTypeCheckTypes.insert(targetType)
                    } else if let targetNominal = driver.helpers.nominalSymbol(of: targetType, types: sema.types) {
                        coveredTypeSymbols.insert(targetNominal)
                    }

                default:
                    break
                }
            }

            for branch in branches {
                var isNullBranch = false
                var branchLocals = locals
                var branchCtx = ctx
                // The branch runs on its own locals copy, so narrowing inside
                // cannot leak to the enclosing conditional path.
                branchCtx.isConditionallyEvaluated = false
                var trueFlowStates: [DataFlowState] = []
                var cumulativeFalseState = ctx.flowState.includingMembers(from: locals)
                var branchConditionKeys: Set<String> = []

                for cond in branch.conditions {
                    var conditionCtx = ctx.copying(flowState: cumulativeFalseState)
                    conditionCtx.isConditionallyEvaluated = false
                    let condType = driver.inferExpr(cond, ctx: conditionCtx, locals: &branchLocals)
                    let isTypeOrMembershipCondition: Bool = switch ast.arena.expr(cond) {
                    case .isCheck, .inExpr, .notInExpr:
                        true
                    default:
                        false
                    }
                    if !isTypeOrMembershipCondition,
                       subjectType != sema.types.errorType,
                       condType != sema.types.errorType
                    {
                        let equalitySubjectType = driver.exprChecker.equalityOperandType(
                            subjectID, inferred: subjectType, ctx: conditionCtx
                        )
                        let equalityConditionType = driver.exprChecker.equalityOperandType(
                            cond, inferred: condType, ctx: conditionCtx
                        )
                        if driver.exprChecker.equalityHasIncompatibleBuiltinTypes(
                            equalitySubjectType, equalityConditionType, sema: sema
                        ) {
                            ctx.sema.diagnostics.error(
                                "KSWIFTK-SEMA-0002",
                                "Operator '==' cannot be applied to unrelated types.",
                                range: ast.arena.exprRange(cond)
                            )
                        }
                    }
                    if branch.guard_ == nil, isNullCondition(cond) {
                        hasNullCase = true
                        isNullBranch = true
                    }
                    if branch.guard_ == nil {
                        recordCoverage(for: cond, conditionType: condType)
                    }

                    if let key = whenConditionKey(for: cond, ast: ast, sema: sema, interner: interner) {
                        if !branchConditionKeys.insert(key).inserted {
                            ctx.sema.diagnostics.warning(
                                "KSWIFTK-SEMA-0072",
                                "Duplicate condition in when branch.",
                                range: ast.arena.exprRange(cond)
                            )
                        } else if branch.guard_ == nil, !allSeenConditionKeys.insert(key).inserted {
                            ctx.sema.diagnostics.warning(
                                "KSWIFTK-SEMA-0073",
                                "Condition already covered by a previous when branch.",
                                range: ast.arena.exprRange(cond)
                            )
                        }
                    }

                    if let subjectLocalBinding, subjectLocalBinding.isStable {
                        let trueState = ctx.dataFlow.branchOnWhenSubject(
                            subjectSymbol: subjectLocalBinding.symbol,
                            subjectType: subjectType,
                            subjectID: subjectID,
                            conditionID: cond,
                            base: cumulativeFalseState,
                            ast: ast,
                            sema: sema,
                            interner: interner,
                            scope: ctx.scope
                        )
                        trueFlowStates.append(trueState)

                        if isNullCondition(cond) {
                            cumulativeFalseState = ctx.dataFlow.whenNonNullBranchState(
                                subjectSymbol: subjectLocalBinding.symbol,
                                subjectType: subjectLocalBinding.type,
                                base: cumulativeFalseState,
                                sema: sema
                            )
                        }
                    }
                }

                if let subjectLocalBinding, subjectLocalBinding.isStable {
                    if let firstTrueState = trueFlowStates.first {
                        var branchFlowState = firstTrueState
                        for trueState in trueFlowStates.dropFirst() {
                            branchFlowState = ctx.dataFlow.merge(branchFlowState, trueState)
                        }

                        if hasExplicitNullBranch, !isNullBranch,
                           ctx.dataFlow.resolvedTypeFromFlowState(
                               branchFlowState,
                               reference: subjectLocalBinding.symbol
                           ) == nil
                        {
                            branchFlowState = ctx.dataFlow.whenNonNullBranchState(
                                subjectSymbol: subjectLocalBinding.symbol,
                                subjectType: subjectLocalBinding.type,
                                base: branchFlowState,
                                sema: sema
                            )
                        }

                        branchCtx = ctx.copying(flowState: branchFlowState)
                        driver.exprChecker.applyFlowStateToLocals(
                            branchFlowState,
                            locals: &branchLocals,
                            sema: sema
                        )

                        if subjectLocalBinding.symbol.properties.isEmpty,
                           let narrowedType = ctx.dataFlow.resolvedTypeFromFlowState(
                            branchFlowState,
                            reference: subjectLocalBinding.symbol
                        ) {
                            branchLocals[subjectLocalBinding.name] = (
                                narrowedType,
                                subjectLocalBinding.symbol.root,
                                subjectLocalBinding.isMutable,
                                true
                            )
                            if subjectIsImplicitReceiverThis {
                                branchCtx = branchCtx.copying(implicitReceiverType: narrowedType)
                            }
                        }
                    } else if hasExplicitNullBranch, !isNullBranch {
                        let nonNullState = ctx.dataFlow.whenNonNullBranchState(
                            subjectSymbol: subjectLocalBinding.symbol,
                            subjectType: subjectLocalBinding.type,
                            base: ctx.flowState.includingMembers(from: locals),
                            sema: sema
                        )
                        branchCtx = ctx.copying(flowState: nonNullState)
                        driver.exprChecker.applyFlowStateToLocals(nonNullState, locals: &branchLocals, sema: sema)
                        if subjectIsImplicitReceiverThis,
                           let narrowedType = ctx.dataFlow.resolvedTypeFromFlowState(
                               nonNullState,
                               reference: subjectLocalBinding.symbol
                           )
                        {
                            branchCtx = branchCtx.copying(implicitReceiverType: narrowedType)
                        }
                    }
                }

                // The guard is checked within the narrowed context so smart casts from
                // `is` checks are available.
                if let guardExpr = branch.guard_ {
                    if branch.conditions.count > 1 {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0447",
                            "A comma-separated list of conditions in a when branch cannot have a guard.",
                            range: ast.arena.exprRange(guardExpr)
                        )
                    }
                    let guardType = driver.inferExpr(guardExpr, ctx: branchCtx, locals: &branchLocals)
                    // `Nothing` guards (`return`/`throw`/`break`/`continue`) never
                    // fall through, so any `Nothing` subtype of Boolean is legal.
                    if !sema.types.isSubtype(guardType, boolType), guardType != sema.types.errorType {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0074",
                            "When branch guard condition must be a Boolean expression.",
                            range: ast.arena.exprRange(guardExpr)
                        )
                    }
                }

                var branchBodyType = driver.inferExpr(branch.body, ctx: branchCtx, locals: &branchLocals, expectedType: expectedType, isStatementContext: isStatementContext)
                if let companionType = driver.helpers.retypeBranchClassObjectValue(
                    branch.body, currentType: branchBodyType, ast: ctx.ast, sema: ctx.sema
                ) {
                    branchBodyType = companionType
                }
                branchTypes.append(branchBodyType)
                allBranchLocals.append(branchLocals)
            }

            if let elseExpr {
                var elseLocals = locals
                var elseCtx = ctx
                if let subjectLocalBinding, subjectLocalBinding.isStable, hasExplicitNullBranch {
                    let elseFlowState = ctx.dataFlow.whenElseState(
                        subjectSymbol: subjectLocalBinding.symbol,
                        subjectType: subjectLocalBinding.type,
                        hasExplicitNullBranch: hasExplicitNullBranch,
                        base: ctx.flowState.includingMembers(from: locals), sema: sema
                    )
                    elseCtx = ctx.copying(flowState: elseFlowState)
                    driver.exprChecker.applyFlowStateToLocals(elseFlowState, locals: &elseLocals, sema: sema)
                    if subjectIsImplicitReceiverThis,
                       let narrowedType = ctx.dataFlow.resolvedTypeFromFlowState(
                           elseFlowState,
                           reference: subjectLocalBinding.symbol
                       )
                    {
                        elseCtx = elseCtx.copying(implicitReceiverType: narrowedType)
                    }
                }
                var elseBodyType = driver.inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType, isStatementContext: isStatementContext)
                if let companionType = driver.helpers.retypeBranchClassObjectValue(
                    elseExpr, currentType: elseBodyType, ast: ctx.ast, sema: ctx.sema
                ) {
                    elseBodyType = companionType
                }
                branchTypes.append(elseBodyType)
                allBranchLocals.append(elseLocals)
            }

            let summary = WhenBranchSummary(
                coveredSymbols: covered, hasElse: elseExpr != nil,
                hasNullCase: hasNullCase, hasTrueCase: hasTrueCase,
                hasFalseCase: hasFalseCase, coveredTypeSymbols: coveredTypeSymbols,
                negatedTypeCheckTypes: negatedTypeCheckTypes
            )
            let isExhaustive = ctx.dataFlow.isWhenExhaustive(
                subjectType: subjectType,
                branches: summary,
                sema: sema,
                valueFacts: subjectValueFacts
            )
            sema.bindings.bindWhenExhaustiveness(id, isExhaustive: isExhaustive)
            // A subject-ful `when` used as a statement (its value discarded) only
            // needs to be exhaustive when the subject is Boolean, enum, or sealed —
            // for any other subject type, Kotlin requires exhaustiveness only when
            // the when's value is actually used (see the subjectless `when` path
            // below, which already applies this rule).
            if !isExhaustive,
               isStatementContext,
               !ctx.dataFlow.subjectRequiresStatementExhaustiveness(subjectType: subjectType, sema: sema)
            {
                // Not exhaustive, but legal as a statement: fall through without
                // diagnosing, matching the subjectless `when` statement behavior.
            } else if !isExhaustive {
                let hasQualifiedObjectCondition = branches.contains { branch in
                    branch.conditions.contains { conditionID in
                        guard let conditionExpr = ast.arena.expr(conditionID) else {
                            return false
                        }
                        if case .memberCall = conditionExpr {
                            return true
                        }
                        return false
                    }
                }
                if !hasQualifiedObjectCondition,
                   let missingBranches = ctx.dataFlow.missingSealedBranches(
                       subjectType: subjectType,
                       branches: summary,
                       sema: sema,
                       valueFacts: subjectValueFacts
                   )
                {
                    let missingNames = missingBranches.map { interner.resolve($0) }.sorted()
                    let missingList = missingNames.joined(separator: ", ")
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0071",
                        "Non-exhaustive when expression on sealed type. Missing branches: \(missingList).",
                        range: range
                    )
                } else {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0004",
                        "Non-exhaustive when expression.",
                        range: range
                    )
                }
            }

            // A branch whose body never completes normally (`return`/`throw`/
            // `break`/`continue`, typed `Nothing`) vacuously satisfies any
            // initialization requirement: control can only reach the code after
            // the `when` through a branch that does complete normally.
            if isExhaustive {
                let completingBranchLocals = zip(branchTypes, allBranchLocals)
                    .filter { type, _ in type != sema.types.nothingType }
                    .map(\.1)
                if !completingBranchLocals.isEmpty {
                    for (name, local) in locals where !local.isInitialized {
                        let allInit = completingBranchLocals.allSatisfy { branchLocal in
                            guard let bl = branchLocal[name] else { return false }
                            return bl.isInitialized && bl.symbol == local.symbol
                        }
                        if allInit {
                            let joinedType = joinedInitializedLocalType(
                                name: name,
                                symbol: local.symbol,
                                from: completingBranchLocals,
                                fallback: local.type,
                                sema: sema
                            )
                            locals[name] = (joinedType, local.symbol, local.isMutable, true)
                        }
                    }
                }
            }

            // A non-exhaustive statement-position `when` can fall through with no value,
            // so its result is Unit even when its branches produce other values.
            let completingLocals = zip(branchTypes, allBranchLocals)
                .filter { $0.0 != sema.types.nothingType }.map(\.1)
            mergeNullableBranchAssignments(
                completingLocals + (isExhaustive ? [] : [locals]), sema: sema, locals: &locals
            )
            let contextualizedTypes = contextualizeLongBranchLiterals(
                expressions: branches.map(\.body) + (elseExpr.map { [$0] } ?? []),
                types: branchTypes, ctx: ctx
            )
            let inferredType = isExhaustive || !isStatementContext
                ? sema.types.lub(contextualizedTypes)
                : sema.types.unitType
            let type = isExhaustive
                ? contextualizeBranchJoin(
                    inferredType,
                    branchTypes: contextualizedTypes,
                    expectedType: expectedType,
                    ctx: ctx
                )
                : inferredType
            adaptCallableReferenceBranches(
                expressions: branches.map(\.body) + (elseExpr.map { [$0] } ?? []),
                branchTypes: contextualizedTypes,
                resultType: type,
                ctx: ctx
            )
            sema.bindings.bindExprType(id, type: type)
            return type
        } else {
            var branchTypes: [TypeID] = []
            var allBranchLocals: [LocalBindings] = []
            var hasTrueCase = false
            var hasFalseCase = false
            var cumulativeFalseState = ctx.flowState.includingMembers(from: locals)
            for branch in branches {
                var branchLocals = locals
                var condCtx = ctx.copying(flowState: cumulativeFalseState)
                condCtx.isConditionallyEvaluated = false
                driver.exprChecker.applyFlowStateToLocals(cumulativeFalseState, locals: &branchLocals, sema: sema)
                var branchCtx = condCtx
                // Collect all true-states and merge them (join) for the body context,
                // since the body executes when ANY condition is true.
                // condCtx is updated after each condition so subsequent conditions see
                // the narrowing from prior conditions being false (short-circuit OR semantics).
                var trueStates: [DataFlowState] = []
                for cond in branch.conditions {
                    let condType = driver.inferExpr(cond, ctx: condCtx, locals: &branchLocals, expectedType: boolType)
                    if !sema.types.isSubtype(condType, boolType), condType != sema.types.errorType {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0032",
                            "Subject-less when branch condition must be a Boolean expression.",
                            range: branch.range
                        )
                    }
                    let condBranch = ctx.dataFlow.branchOnCondition(
                        cond, base: cumulativeFalseState, locals: branchLocals,
                        ast: ast, sema: sema, interner: interner, scope: ctx.scope
                    )
                    trueStates.append(condBranch.trueState)
                    // Chain false-state: branch is false only when ALL conditions are false
                    cumulativeFalseState = condBranch.falseState
                    condCtx = ctx.copying(flowState: cumulativeFalseState)
                    driver.exprChecker.applyFlowStateToLocals(cumulativeFalseState, locals: &branchLocals, sema: sema)
                    if let condExpr = ast.arena.expr(cond) {
                        switch condExpr {
                        case .boolLiteral(true, _) where branch.guard_ == nil:
                            hasTrueCase = true
                        case .boolLiteral(false, _) where branch.guard_ == nil:
                            hasFalseCase = true
                        default:
                            break
                        }
                    }
                }
                if let firstTrue = trueStates.first {
                    var joinedState = firstTrue
                    for state in trueStates.dropFirst() {
                        joinedState = ctx.dataFlow.merge(joinedState, state)
                    }
                    branchCtx = ctx.copying(flowState: joinedState)
                    branchLocals = locals
                    driver.exprChecker.applyFlowStateToLocals(joinedState, locals: &branchLocals, sema: sema)
                }

                if let guardExpr = branch.guard_ {
                    // Kotlin reports WHEN_GUARD_WITHOUT_SUBJECT here: branch
                    // conditions of a subject-less `when` are already full
                    // Boolean expressions, so a guard is never allowed.
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0448",
                        "When branch guards are only allowed in 'when' with a subject.",
                        range: ast.arena.exprRange(guardExpr)
                    )
                    _ = driver.inferExpr(guardExpr, ctx: branchCtx, locals: &branchLocals)
                }

                var branchBodyType = driver.inferExpr(branch.body, ctx: branchCtx, locals: &branchLocals, expectedType: expectedType, isStatementContext: isStatementContext)
                if let companionType = driver.helpers.retypeBranchClassObjectValue(
                    branch.body, currentType: branchBodyType, ast: ctx.ast, sema: ctx.sema
                ) {
                    branchBodyType = companionType
                }
                branchTypes.append(branchBodyType)
                allBranchLocals.append(branchLocals)
            }

            if let elseExpr {
                var elseLocals = locals
                let elseCtx = ctx.copying(flowState: cumulativeFalseState)
                driver.exprChecker.applyFlowStateToLocals(cumulativeFalseState, locals: &elseLocals, sema: sema)
                var elseBodyType = driver.inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType, isStatementContext: isStatementContext)
                if let companionType = driver.helpers.retypeBranchClassObjectValue(
                    elseExpr, currentType: elseBodyType, ast: ctx.ast, sema: ctx.sema
                ) {
                    elseBodyType = companionType
                }
                branchTypes.append(elseBodyType)
                allBranchLocals.append(elseLocals)
            }

            let summary = WhenBranchSummary(
                coveredSymbols: [], hasElse: elseExpr != nil,
                hasNullCase: false, hasTrueCase: hasTrueCase,
                hasFalseCase: hasFalseCase
            )
            let isExhaustive = ctx.dataFlow.isWhenExhaustive(subjectType: boolType, branches: summary, sema: sema)
            sema.bindings.bindWhenExhaustiveness(id, isExhaustive: isExhaustive)
            // A subject-less `when` used as a statement (its value discarded) does not
            // require exhaustiveness in Kotlin - only `when` used as an expression does.
            if !isExhaustive, !isStatementContext {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0004",
                    "Non-exhaustive when expression.",
                    range: range
                )
            }

            // A branch whose body never completes normally (`return`/`throw`/
            // `break`/`continue`, typed `Nothing`) vacuously satisfies any
            // initialization requirement: control can only reach the code after
            // the `when` through a branch that does complete normally.
            if isExhaustive {
                let completingBranchLocals = zip(branchTypes, allBranchLocals)
                    .filter { type, _ in type != sema.types.nothingType }
                    .map(\.1)
                if !completingBranchLocals.isEmpty {
                    for (name, local) in locals where !local.isInitialized {
                        let allInit = completingBranchLocals.allSatisfy { branchLocal in
                            guard let bl = branchLocal[name] else { return false }
                            return bl.isInitialized && bl.symbol == local.symbol
                        }
                        if allInit {
                            let joinedType = joinedInitializedLocalType(
                                name: name,
                                symbol: local.symbol,
                                from: completingBranchLocals,
                                fallback: local.type,
                                sema: sema
                            )
                            locals[name] = (joinedType, local.symbol, local.isMutable, true)
                        }
                    }
                }
            }

            // A non-exhaustive statement-position `when` can fall through with no value,
            // so its result is Unit even when its branches produce other values.
            let completingLocals = zip(branchTypes, allBranchLocals)
                .filter { $0.0 != sema.types.nothingType }.map(\.1)
            mergeNullableBranchAssignments(
                completingLocals + (isExhaustive ? [] : [locals]), sema: sema, locals: &locals
            )
            locals.memberFlow = joinMemberFlow(
                from: completingLocals + (isExhaustive ? [] : [locals]),
                base: locals.memberFlow,
                sema: sema
            )
            let flowFactBranches = completingLocals + (isExhaustive ? [] : [locals])
            locals.joinVariableFacts(from: flowFactBranches)
            let contextualizedTypes = contextualizeLongBranchLiterals(
                expressions: branches.map(\.body) + (elseExpr.map { [$0] } ?? []),
                types: branchTypes, ctx: ctx
            )
            let inferredType = isExhaustive || !isStatementContext
                ? sema.types.lub(contextualizedTypes)
                : sema.types.unitType
            let type = isExhaustive
                ? contextualizeBranchJoin(
                    inferredType,
                    branchTypes: contextualizedTypes,
                    expectedType: expectedType,
                    ctx: ctx
                )
                : inferredType
            adaptCallableReferenceBranches(
                expressions: branches.map(\.body) + (elseExpr.map { [$0] } ?? []),
                branchTypes: contextualizedTypes,
                resultType: type,
                ctx: ctx
            )
            sema.bindings.bindExprType(id, type: type)
            return type
        }
    }
}
