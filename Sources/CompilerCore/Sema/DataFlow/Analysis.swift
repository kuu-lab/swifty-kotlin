struct VariableFlowState: Equatable {
    var possibleTypes: Set<TypeID>
    var nullability: Nullability
    var isStable: Bool
}

struct DataFlowReference: Hashable {
    let root: SymbolID
    var properties: [SymbolID] = []
}

struct DataFlowState: Equatable {
    var variables: [SymbolID: VariableFlowState]
    var members: [DataFlowReference: VariableFlowState] = [:]

    init(variables: [SymbolID: VariableFlowState] = [:]) {
        self.variables = variables
    }

    subscript(reference: DataFlowReference) -> VariableFlowState? {
        get { reference.properties.isEmpty ? variables[reference.root] : members[reference] }
        set {
            if reference.properties.isEmpty {
                variables[reference.root] = newValue
            } else {
                members[reference] = newValue
            }
        }
    }

    func includingMembers(from locals: LocalBindings) -> DataFlowState {
        var state = self
        state.members = locals.memberFlow
        return state
    }
}

struct WhenBranchSummary {
    let coveredSymbols: Set<InternedString>
    let coveredTypeSymbols: Set<SymbolID>
    let hasElse: Bool
    let hasNullCase: Bool
    let hasTrueCase: Bool
    let hasFalseCase: Bool

    init(
        coveredSymbols: Set<InternedString>,
        hasElse: Bool,
        hasNullCase: Bool = false,
        hasTrueCase: Bool? = nil,
        hasFalseCase: Bool? = nil,
        coveredTypeSymbols: Set<SymbolID> = []
    ) {
        self.coveredSymbols = coveredSymbols
        self.coveredTypeSymbols = coveredTypeSymbols
        self.hasElse = hasElse
        self.hasNullCase = hasNullCase
        self.hasTrueCase = hasTrueCase ?? coveredSymbols.contains(InternedString(rawValue: 1))
        self.hasFalseCase = hasFalseCase ?? coveredSymbols.contains(InternedString(rawValue: 2))
    }
}

struct ConditionBranch: Equatable {
    let trueState: DataFlowState
    let falseState: DataFlowState
}

final class DataFlowAnalyzer {
    var stableMemberProperties: [SymbolID: Bool] = [:]
    let localStability = LocalVariableStabilityAnalyzer()
    var stableMutableReceivers: Set<SymbolID> = []
    init() {}

    private func builtinTypeNames(interner: StringInterner) -> BuiltinTypeNames {
        BuiltinTypeNames(interner: interner)
    }

    func branchOnCondition(
        _ conditionID: ExprID,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> ConditionBranch {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        switch conditionExpr {
        case .call, .memberCall:
            return ConditionBranch(
                trueState: applyContractImplications(conditionID, result: .returnsTrue, base: base, locals: locals, ast: ast, sema: sema, interner: interner, scope: scope),
                falseState: applyContractImplications(conditionID, result: .returnsFalse, base: base, locals: locals, ast: ast, sema: sema, interner: interner, scope: scope)
            )
        case let .binary(op, lhsID, rhsID, _):
            return branchOnBinary(
                op: op, lhsID: lhsID, rhsID: rhsID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
        case let .unaryExpr(.not, operandID, _):
            let inner = branchOnCondition(
                operandID, base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            return ConditionBranch(trueState: inner.falseState, falseState: inner.trueState)
        case let .isCheck(exprID, typeRefID, negated, _):
            let branch = branchOnIsCheck(
                exprID: exprID, typeRefID: typeRefID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            if negated {
                return ConditionBranch(trueState: branch.falseState, falseState: branch.trueState)
            }
            return branch
        default:
            return ConditionBranch(trueState: base, falseState: base)
        }
    }

    func applyContractImplications(
        _ callID: ExprID,
        result: ContractReturnCondition,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> DataFlowState {
        guard let binding = sema.bindings.callBinding(for: callID),
              let expr = ast.arena.expr(callID) else { return base }
        let args: [CallArgument]
        switch expr {
        case let .call(_, _, arguments, _), let .memberCall(_, _, _, arguments, _): args = arguments
        default: return base
        }
        var state = base
        for effect in sema.symbols.contractImplicationEffects(for: binding.chosenCallee) {
            guard effect.returnCondition == .normally || effect.returnCondition == result
                || (effect.returnCondition == .returnsNotNull && (result == .returnsTrue || result == .returnsFalse)),
                let argumentIndex = binding.parameterMapping.first(where: { $0.value == effect.parameterIndex })?.key,
                args.indices.contains(argumentIndex) else { continue }
            let argument = args[argumentIndex].expr
            switch effect.argumentCondition {
            case .isType:
                if let rawTargetType = effect.targetType {
                    let parameters = sema.symbols.functionSignature(for: binding.chosenCallee)?.typeParameterSymbols ?? []
                    let variables = sema.types.makeTypeVarBySymbol(parameters)
                    var substitution: [TypeVarID: TypeID] = [:]
                    for (parameter, type) in zip(parameters, binding.substitutedTypeArguments) {
                        if let variable = variables[parameter] { substitution[variable] = type }
                    }
                    let targetType = sema.types.substituteTypeParameters(
                        in: rawTargetType, substitution: substitution, typeVarBySymbol: variables
                    )
                    state = branchOnResolvedIsCheck(exprID: argument, rawTargetType: targetType,
                        base: state, locals: locals, ast: ast, sema: sema, interner: interner).trueState
                }
            case .nonNull:
                state = narrowNonNull(argument, base: state, locals: locals, ast: ast, sema: sema, interner: interner)
            case .booleanTrue, .booleanFalse:
                let branch = branchOnCondition(argument, base: state, locals: locals, ast: ast, sema: sema, interner: interner, scope: scope)
                state = effect.argumentCondition == .booleanTrue ? branch.trueState : branch.falseState
            }
        }
        return state
    }

    /// Narrows a stable local expression to its non-null type after a contract
    /// guarantees that the expression is non-null on normal return.
    func narrowNonNull(
        _ expressionID: ExprID,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> DataFlowState {
        guard let (symbol, currentType, isStable) = resolveStableReference(
            expressionID,
            locals: locals,
            ast: ast,
            sema: sema,
            interner: interner
        ), isStable else {
            return base
        }
        let effectiveType: TypeID = if let baseState = base[symbol],
                                       baseState.possibleTypes.count == 1,
                                       let baseType = baseState.possibleTypes.first
        {
            baseType
        } else {
            currentType
        }
        var variables = base
        variables[symbol] = VariableFlowState(
            possibleTypes: [makeTypeNonNullable(effectiveType, types: sema.types)],
            nullability: .nonNull,
            isStable: true
        )
        return variables
    }

    private func branchOnBinary(
        op: BinaryOp,
        lhsID: ExprID,
        rhsID: ExprID,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> ConditionBranch {
        switch op {
        case .equal, .notEqual, .identityEqual, .notIdentityEqual:
            let testedCall: ExprID?
            let trueResult: ContractReturnCondition
            var falseResult: ContractReturnCondition
            if isNullLiteral(rhsID, ast: ast, interner: interner) || isNullLiteral(lhsID, ast: ast, interner: interner) {
                testedCall = isNullLiteral(rhsID, ast: ast, interner: interner) ? lhsID : rhsID
                trueResult = .returnsNull
                falseResult = .returnsNotNull
            } else if let value = booleanLiteral(rhsID, ast: ast, interner: interner) {
                testedCall = lhsID
                trueResult = value ? .returnsTrue : .returnsFalse
                falseResult = value ? .returnsFalse : .returnsTrue
            } else if let value = booleanLiteral(lhsID, ast: ast, interner: interner) {
                testedCall = rhsID
                trueResult = value ? .returnsTrue : .returnsFalse
                falseResult = value ? .returnsFalse : .returnsTrue
            } else {
                testedCall = nil
                trueResult = .normally
                falseResult = .normally
            }
            if let testedCall, sema.bindings.callBinding(for: testedCall) != nil {
                if trueResult == .returnsTrue || trueResult == .returnsFalse,
                   let resultType = sema.bindings.exprTypes[testedCall],
                   makeTypeNonNullable(resultType, types: sema.types) != resultType
                {
                    // A nullable Boolean unequal to a literal may be null, not its opposite.
                    falseResult = .normally
                }
                let branch = ConditionBranch(
                    trueState: applyContractImplications(testedCall, result: trueResult, base: base, locals: locals, ast: ast, sema: sema, interner: interner, scope: scope),
                    falseState: applyContractImplications(testedCall, result: falseResult, base: base, locals: locals, ast: ast, sema: sema, interner: interner, scope: scope)
                )
                if op == .notEqual || op == .notIdentityEqual {
                    return ConditionBranch(trueState: branch.falseState, falseState: branch.trueState)
                }
                return branch
            }
            // `x === null` / `x !== null` narrow nullability exactly like `==`/`!=`
            // (identity comparison against the null literal is not overridable).
            let nullResult = branchOnNullComparison(
                lhsID: lhsID, rhsID: rhsID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner
            )
            if let nullResult {
                if op == .notEqual || op == .notIdentityEqual {
                    return ConditionBranch(trueState: nullResult.falseState, falseState: nullResult.trueState)
                }
                return nullResult
            }
            return ConditionBranch(trueState: base, falseState: base)
        case .logicalAnd:
            let left = branchOnCondition(
                lhsID, base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            let right = branchOnCondition(
                rhsID, base: left.trueState, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            let trueState = right.trueState
            let falseState = merge(left.falseState, right.falseState)
            return ConditionBranch(trueState: trueState, falseState: falseState)
        case .logicalOr:
            let left = branchOnCondition(
                lhsID, base: base, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            let right = branchOnCondition(
                rhsID, base: left.falseState, locals: locals,
                ast: ast, sema: sema, interner: interner, scope: scope
            )
            let trueState = merge(left.trueState, right.trueState)
            let falseState = right.falseState
            return ConditionBranch(trueState: trueState, falseState: falseState)
        default:
            return ConditionBranch(trueState: base, falseState: base)
        }
    }

    private func booleanLiteral(_ id: ExprID, ast: ASTModule, interner: StringInterner) -> Bool? {
        switch ast.arena.expr(id) {
        case let .boolLiteral(value, _): return value
        case let .nameRef(name, _):
            switch interner.resolve(name) {
            case "true": return true
            case "false": return false
            default: return nil
            }
        default: return nil
        }
    }

    private func branchOnNullComparison(
        lhsID: ExprID,
        rhsID: ExprID,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> ConditionBranch? {
        let variableID: ExprID
        if isNullLiteral(rhsID, ast: ast, interner: interner) {
            variableID = lhsID
        } else if isNullLiteral(lhsID, ast: ast, interner: interner) {
            variableID = rhsID
        } else {
            return nil
        }
        guard let (symbol, currentType, isStable) = resolveStableReference(
            variableID, locals: locals, ast: ast, sema: sema, interner: interner
        ), isStable else {
            return nil
        }
        let effectiveType: TypeID = if let baseState = base[symbol], baseState.possibleTypes.count == 1,
                                       let baseType = baseState.possibleTypes.first
        {
            baseType
        } else {
            currentType
        }
        let nonNullType = makeTypeNonNullable(effectiveType, types: sema.types)
        var trueVars = base
        trueVars[symbol] = VariableFlowState(
            possibleTypes: [effectiveType],
            nullability: .nullable,
            isStable: true
        )
        var falseVars = base
        falseVars[symbol] = VariableFlowState(
            possibleTypes: [nonNullType],
            nullability: .nonNull,
            isStable: true
        )
        return ConditionBranch(
            trueState: trueVars,
            falseState: falseVars
        )
    }

    private func branchOnIsCheck(
        exprID: ExprID,
        typeRefID: TypeRefID,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> ConditionBranch {
        guard let rawTargetType = resolveIsCheckTargetType(
            typeRefID: typeRefID,
            scope: scope,
            ast: ast,
            sema: sema,
            interner: interner
        ) else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        return branchOnResolvedIsCheck(exprID: exprID, rawTargetType: rawTargetType,
            base: base, locals: locals, ast: ast, sema: sema, interner: interner)
    }

    private func branchOnResolvedIsCheck(
        exprID: ExprID, rawTargetType: TypeID, base: DataFlowState,
        locals: LocalBindings, ast: ASTModule, sema: SemaModule, interner: StringInterner
    ) -> ConditionBranch {
        guard let (symbol, currentType, isStable) = resolveStableReference(
            exprID, locals: locals, ast: ast, sema: sema, interner: interner
        ), isStable else {
            return ConditionBranch(trueState: base, falseState: base)
        }
        let priorType: TypeID = if let baseState = base[symbol], baseState.possibleTypes.count == 1,
                                   let baseType = baseState.possibleTypes.first
        {
            baseType
        } else {
            currentType
        }
        // `this is List` (no explicit type argument) checked against a value
        // already known to be `Iterable<T>` must narrow to `List<T>`, not a
        // raw/star-projected `List<*>` -- see narrowedSubtypeArgs.
        let targetType = refineIsCheckTargetType(rawTargetType, priorType: priorType, sema: sema)
        let targetNullability = sema.types.nullability(of: targetType)
        // Use intersection with previous flow state type for chained is-checks (P5-97)
        let narrowedType: TypeID = if let baseState = base[symbol],
                                      baseState.possibleTypes.count == 1,
                                      let existingType = baseState.possibleTypes.first
        {
            if sema.types.isSubtype(existingType, targetType) {
                // Existing flow type is already more specific; keep it.
                existingType
            } else if sema.types.isSubtype(targetType, existingType) {
                // New target type is more specific; use it.
                targetType
            } else {
                // Types are unrelated; intersect them for chained is-checks.
                sema.types.make(.intersection([existingType, targetType]))
            }
        } else {
            targetType
        }
        var trueVars = base
        trueVars[symbol] = VariableFlowState(
            possibleTypes: [narrowedType],
            nullability: targetNullability,
            isStable: true
        )
        let falseType: TypeID = if let baseState = base[symbol], baseState.possibleTypes.count == 1,
                                   let baseType = baseState.possibleTypes.first
        {
            baseType
        } else {
            currentType
        }
        var falseVars = base
        falseVars[symbol] = VariableFlowState(
            possibleTypes: [falseType],
            nullability: base[symbol]?.nullability ?? (makeTypeNonNullable(falseType, types: sema.types) != falseType ? .nullable : .nonNull),
            isStable: true
        )
        return ConditionBranch(
            trueState: trueVars,
            falseState: falseVars
        )
    }

    func branchOnWhenSubject(
        subjectSymbol: DataFlowReference,
        subjectType: TypeID,
        subjectID: ExprID,
        conditionID: ExprID,
        base: DataFlowState,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> DataFlowState {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return base
        }
        switch conditionExpr {
        case let .nameRef(name, _):
            if name == builtinTypeNames(interner: interner).null {
                var vars = base
                vars[subjectSymbol] = VariableFlowState(
                    possibleTypes: [subjectType],
                    nullability: .nullable,
                    isStable: true
                )
                return vars
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID] else {
                return base
            }
            return narrowedStateForConditionSymbol(
                conditionSymbolID,
                subjectSymbol: subjectSymbol, subjectType: subjectType,
                base: base, sema: sema
            )
        case let .memberCall(_, _, _, args, _):
            guard args.isEmpty,
                  let conditionSymbolID = sema.bindings.identifierSymbols[conditionID]
            else {
                return base
            }
            return narrowedStateForConditionSymbol(
                conditionSymbolID,
                subjectSymbol: subjectSymbol, subjectType: subjectType,
                base: base, sema: sema
            )
        case .boolLiteral:
            if case .primitive(.boolean, _) = sema.types.kind(of: subjectType) {
                let narrowed = sema.types.make(.primitive(.boolean, .nonNull))
                var vars = base
                vars[subjectSymbol] = VariableFlowState(
                    possibleTypes: [narrowed],
                    nullability: .nonNull,
                    isStable: true
                )
                return vars
            }
            return base
        case let .isCheck(exprID, typeRefID, negated, _):
            return narrowedStateForIsCheck(
                exprID: exprID, typeRefID: typeRefID, negated: negated,
                subjectSymbol: subjectSymbol, subjectType: subjectType, subjectID: subjectID, conditionID: conditionID,
                base: base, ast: ast, sema: sema, interner: interner, scope: scope
            )
        default:
            return base
        }
    }

    private func narrowedStateForConditionSymbol(
        _ conditionSymbolID: SymbolID,
        subjectSymbol: DataFlowReference,
        subjectType: TypeID,
        base: DataFlowState,
        sema: SemaModule
    ) -> DataFlowState {
        guard let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
            return base
        }
        switch conditionSymbol.kind {
        case .field:
            guard let ownerID = enumOwnerSymbolID(for: conditionSymbol, symbols: sema.symbols),
                  nominalSymbolID(of: subjectType, types: sema.types) == ownerID
            else {
                return base
            }
            let narrowed = sema.types.make(.classType(ClassType(
                classSymbol: ownerID, args: [], nullability: .nonNull
            )))
            var vars = base
            vars[subjectSymbol] = VariableFlowState(
                possibleTypes: [narrowed], nullability: .nonNull, isStable: true
            )
            return vars
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            guard let subjectNominal = nominalSymbolID(of: subjectType, types: sema.types),
                  isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols)
            else {
                return base
            }
            let rawNarrowed = sema.types.make(.classType(ClassType(
                classSymbol: conditionSymbolID, args: [], nullability: .nonNull
            )))
            // Same "no explicit type argument" narrowing gap as
            // narrowedStateForIsCheck -- see refineIsCheckTargetType.
            let narrowed = refineIsCheckTargetType(rawNarrowed, priorType: subjectType, sema: sema)
            var vars = base
            vars[subjectSymbol] = VariableFlowState(
                possibleTypes: [narrowed], nullability: .nonNull, isStable: true
            )
            return vars
        default:
            return base
        }
    }

    private func narrowedStateForIsCheck(
        exprID: ExprID,
        typeRefID: TypeRefID,
        negated: Bool,
        subjectSymbol: DataFlowReference,
        subjectType: TypeID,
        subjectID: ExprID,
        conditionID _: ExprID,
        base: DataFlowState,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> DataFlowState {
        // Only narrow when the isCheck's expr refers to the when subject. A
        // bare `is Type` when-branch condition is always parsed as
        // `.isCheck(expr: subject, ...)`, reusing the subject's own ExprID
        // (BuildASTPhase+ExpressionParserControlFlow.parseWhenBranchCondition),
        // so identity comparison here is reliable even for synthetic subjects
        // (`this`, a lambda parameter) that never get an `identifierSymbols`
        // binding for their own ExprID.
        guard exprID == subjectID else {
            return base
        }
        guard !negated else { return base }
        guard let rawNarrowed = resolveIsCheckTargetType(
            typeRefID: typeRefID, scope: scope, ast: ast, sema: sema, interner: interner
        ) else {
            return base
        }
        // `when (this) { is List -> ... }` on a value known to be
        // `Iterable<T>` must narrow to `List<T>`, not an under-specified
        // `List` -- see the matching fix in branchOnIsCheck/refineIsCheckTargetType.
        let narrowed = refineIsCheckTargetType(rawNarrowed, priorType: subjectType, sema: sema)
        let narrowedNullability = sema.types.nullability(of: narrowed)
        var vars = base
        vars[subjectSymbol] = VariableFlowState(
            possibleTypes: [narrowed], nullability: narrowedNullability, isStable: true
        )
        return vars
    }

    func whenElseState(
        subjectSymbol: DataFlowReference,
        subjectType: TypeID,
        hasExplicitNullBranch: Bool,
        base: DataFlowState,
        sema: SemaModule
    ) -> DataFlowState {
        guard hasExplicitNullBranch else {
            return base
        }
        let nonNullType = makeTypeNonNullable(subjectType, types: sema.types)
        var vars = base
        vars[subjectSymbol] = VariableFlowState(
            possibleTypes: [nonNullType],
            nullability: .nonNull,
            isStable: true
        )
        return vars
    }

    func whenNonNullBranchState(
        subjectSymbol: DataFlowReference,
        subjectType: TypeID,
        base: DataFlowState,
        sema: SemaModule
    ) -> DataFlowState {
        let nonNullType = makeTypeNonNullable(subjectType, types: sema.types)
        var vars = base
        vars[subjectSymbol] = VariableFlowState(
            possibleTypes: [nonNullType],
            nullability: .nonNull,
            isStable: true
        )
        return vars
    }

    func resolvedTypeFromFlowState(
        _ state: DataFlowState,
        symbol: SymbolID
    ) -> TypeID? {
        return resolvedTypeFromFlowState(state, reference: DataFlowReference(root: symbol))
    }

    func resolvedTypeFromFlowState(
        _ state: DataFlowState,
        reference: DataFlowReference
    ) -> TypeID? {
        guard let flowState = state[reference],
              flowState.possibleTypes.count == 1,
              let narrowed = flowState.possibleTypes.first
        else {
            return nil
        }
        return narrowed
    }

    private func isNullLiteral(_ id: ExprID, ast: ASTModule, interner: StringInterner) -> Bool {
        guard let expr = ast.arena.expr(id),
              case let .nameRef(name, _) = expr
        else {
            return false
        }
        return name == builtinTypeNames(interner: interner).null
    }

    private func makeTypeNonNullable(_ type: TypeID, types: TypeSystem) -> TypeID {
        types.makeNonNullable(type)
    }

    private func nominalSymbolID(of type: TypeID, types: TypeSystem) -> SymbolID? {
        if case let .classType(classType) = types.kind(of: type) {
            return classType.classSymbol
        }
        return nil
    }

    private func isNominalSubtype(
        _ candidate: SymbolID,
        of base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        if candidate == base {
            return true
        }
        var queue = symbols.directSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next == base {
                return true
            }
            if visited.insert(next).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: next))
            }
        }
        return false
    }

    private func enumOwnerSymbolID(for entrySymbol: SemanticSymbol, symbols: SymbolTable) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2
        else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }

    func merge(_ lhs: DataFlowState, _ rhs: DataFlowState) -> DataFlowState {
        var merged: [SymbolID: VariableFlowState] = [:]
        for (symbol, lhsState) in lhs.variables {
            guard let rhsState = rhs.variables[symbol] else { continue }
            let types = lhsState.possibleTypes.union(rhsState.possibleTypes)
            let nullability: Nullability = (lhsState.nullability == .nullable || rhsState.nullability == .nullable)
                ? .nullable
                : .nonNull
            merged[symbol] = VariableFlowState(
                possibleTypes: types,
                nullability: nullability,
                isStable: lhsState.isStable && rhsState.isStable
            )
        }
        var result = DataFlowState(variables: merged)
        for (reference, lhsState) in lhs.members {
            guard let rhsState = rhs.members[reference] else { continue }
            result.members[reference] = VariableFlowState(
                possibleTypes: lhsState.possibleTypes.union(rhsState.possibleTypes),
                nullability: lhsState.nullability == .nullable || rhsState.nullability == .nullable ? .nullable : .nonNull,
                isStable: lhsState.isStable && rhsState.isStable
            )
        }
        return result
    }

    func isWhenExhaustive(
        subjectType: TypeID,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> Bool {
        if branches.hasElse {
            return true
        }
        let kind = sema.types.kind(of: subjectType)
        switch kind {
        case .primitive(.boolean, .nonNull):
            return branches.hasTrueCase && branches.hasFalseCase
        case .primitive(.boolean, .nullable):
            return branches.hasTrueCase && branches.hasFalseCase && branches.hasNullCase
        case let .classType(classType):
            return isClassWhenExhaustive(
                classType: classType,
                branches: branches,
                sema: sema
            )
        case .any(.nullable):
            return false
        default:
            return false
        }
    }

    /// Whether a non-exhaustive `when` over `subjectType` is an error even when
    /// the `when` is used as a statement (its value discarded). Kotlin only
    /// enforces exhaustiveness unconditionally — regardless of expression vs.
    /// statement position — for `Boolean` and sealed/enum subjects; any other
    /// subject type (`Byte`, `Int`, `String`, a non-sealed class, ...) is only
    /// required to be exhaustive when the `when`'s value is actually used.
    func subjectRequiresStatementExhaustiveness(subjectType: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: subjectType) {
        case .primitive(.boolean, _):
            return true
        case let .classType(classType):
            guard let classSymbol = sema.symbols.symbol(classType.classSymbol) else {
                return false
            }
            return classSymbol.kind == .enumClass || classSymbol.flags.contains(.sealedType)
        default:
            return false
        }
    }

    /// P5-78: Returns the set of missing sealed subtype InternedString names for diagnostic purposes.
    /// Returns nil if the type is not a sealed type or if all branches are covered.
    func missingSealedBranches(
        subjectType: TypeID,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> [InternedString]? {
        if branches.hasElse {
            return nil
        }
        let kind = sema.types.kind(of: subjectType)
        guard case let .classType(classType) = kind else {
            return nil
        }
        guard let classSymbol = sema.symbols.symbol(classType.classSymbol),
              classSymbol.flags.contains(.sealedType)
        else {
            return nil
        }
        let subtypes = sealedSubtypeSymbols(for: classSymbol, sema: sema)
        guard !subtypes.isEmpty else {
            return nil
        }
        let missing = subtypes.filter { !isSealedSubtypeCovered($0, branches: branches, sema: sema) }
        guard !missing.isEmpty else {
            return nil
        }
        return Array(Set(missing.compactMap { sema.symbols.symbol($0)?.name }))
    }

    private func isClassWhenExhaustive(
        classType: ClassType,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> Bool {
        guard let classSymbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }

        switch classSymbol.kind {
        case .enumClass:
            let enumEntryNames = enumEntryNames(for: classSymbol, sema: sema)
            guard !enumEntryNames.isEmpty else {
                return false
            }
            let hasAllEnumEntries = enumEntryNames.isSubset(of: branches.coveredSymbols)
            if classType.nullability == .nullable {
                return hasAllEnumEntries && branches.hasNullCase
            }
            return hasAllEnumEntries

        default:
            if classSymbol.flags.contains(.sealedType) {
                let subtypes = sealedSubtypeSymbols(for: classSymbol, sema: sema)
                guard !subtypes.isEmpty else {
                    return false
                }
                let hasAllSealedSubtypes = subtypes.allSatisfy {
                    isSealedSubtypeCovered($0, branches: branches, sema: sema)
                }
                if classType.nullability == .nullable {
                    return hasAllSealedSubtypes && branches.hasNullCase
                }
                return hasAllSealedSubtypes
            }
            return false
        }
    }

    private func isSealedSubtypeCovered(
        _ subtype: SymbolID,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> Bool {
        if let name = sema.symbols.symbol(subtype)?.name,
           branches.coveredSymbols.contains(name)
        {
            return true
        }
        return branches.coveredTypeSymbols.contains {
            isNominalSubtype(subtype, of: $0, symbols: sema.symbols)
        }
    }

    /// P5-78: Get sealed subtype symbols, using sealedSubclasses metadata for cross-module support,
    /// falling back to directSubtypes for same-module sealed types.
    private func sealedSubtypeSymbols(for classSymbol: SemanticSymbol, sema: SemaModule) -> [SymbolID] {
        // First try sealedSubclasses (populated from metadata for cross-module)
        if let sealedSubs = sema.symbols.sealedSubclasses(for: classSymbol.id) {
            return sealedSubs
        }
        // Fall back to directSubtypes (same-module)
        return sema.symbols.directSubtypes(of: classSymbol.id)
    }

    /// Refines a raw `is` target type resolved with no explicit type argument
    /// (`this is List`) using a value already known to be some generic
    /// `priorType` (e.g. `Iterable<T>`), narrowing `List` to `List<T>` rather
    /// than leaving it under-specified. See `TypeSystem.narrowedSubtypeArgs`
    /// for why this is sound and when it can't determine an argument.
    private func refineIsCheckTargetType(
        _ rawTargetType: TypeID,
        priorType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard case let .classType(targetClass) = sema.types.kind(of: rawTargetType),
              targetClass.args.isEmpty,
              !sema.types.nominalTypeParameterSymbols(for: targetClass.classSymbol).isEmpty,
              case let .classType(priorClass) = sema.types.kind(of: sema.types.makeNonNullable(priorType)),
              let narrowedArgs = sema.types.narrowedSubtypeArgs(
                  forSubtype: targetClass.classSymbol,
                  givenSupertype: priorClass.classSymbol,
                  supertypeArgs: priorClass.args
              )
        else {
            return rawTargetType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: targetClass.classSymbol,
            args: narrowedArgs,
            nullability: targetClass.nullability
        )))
    }

    private func resolveIsCheckTargetType(
        typeRefID: TypeRefID,
        scope: Scope,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let typeRef = ast.arena.typeRef(typeRefID),
              case let .named(path, _, _) = typeRef,
              let shortName = path.last
        else {
            return nil
        }

        if path.count == 1,
           let typeParameterSymbol = resolveTypeParameterSymbol(shortName, scope: scope, sema: sema),
           let typeParameter = sema.symbols.symbol(typeParameterSymbol),
           !typeParameter.flags.contains(.reifiedTypeParameter)
        {
            return nil
        }

        let targetType = TypeCheckHelpers().resolveTypeRef(
            typeRefID, ast: ast, sema: sema, interner: interner, scope: scope
        )
        return targetType == sema.types.errorType ? nil : targetType
    }

    private func resolveTypeParameterSymbol(
        _ name: InternedString,
        scope: Scope,
        sema: SemaModule
    ) -> SymbolID? {
        scope.lookup(name).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .typeParameter
        }
    }

    private func enumEntryNames(for enumSymbol: SemanticSymbol, sema: SemaModule) -> Set<InternedString> {
        let childIDs = sema.symbols.children(ofFQName: enumSymbol.fqName)
        var names: Set<InternedString> = []
        for childID in childIDs {
            guard let child = sema.symbols.symbol(childID),
                  child.kind == .field
            else {
                continue
            }
            names.insert(child.name)
        }
        return names
    }
}
