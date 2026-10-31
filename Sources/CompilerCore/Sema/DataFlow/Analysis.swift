enum DataFlowValue: Hashable {
    case boolean(Bool)
    case null
    case symbol(SymbolID)
}

/// Finite-value and negative-type facts kept alongside a variable's positive
/// smart-cast type. `possibleValues == nil` means no finite value set is known.
struct DataFlowValueFacts: Equatable {
    var possibleValues: Set<DataFlowValue>?
    var excludedValues: Set<DataFlowValue>
    var excludedTypes: Set<TypeID>

    init(
        possibleValues: Set<DataFlowValue>? = nil,
        excludedValues: Set<DataFlowValue> = [],
        excludedTypes: Set<TypeID> = []
    ) {
        self.possibleValues = possibleValues
        self.excludedValues = excludedValues
        self.excludedTypes = excludedTypes
    }

    var isEmpty: Bool {
        possibleValues == nil && excludedValues.isEmpty && excludedTypes.isEmpty
    }

    /// Combines facts known on the same path.
    func combining(_ other: Self) -> Self {
        let possibleValues: Set<DataFlowValue>?
        if let current = self.possibleValues, let next = other.possibleValues {
            possibleValues = current.intersection(next)
        } else {
            possibleValues = self.possibleValues ?? other.possibleValues
        }
        return Self(
            possibleValues: possibleValues,
            excludedValues: excludedValues.union(other.excludedValues),
            excludedTypes: excludedTypes.union(other.excludedTypes)
        )
    }

    /// Retains only facts that hold after either control-flow path can continue.
    func joining(_ other: Self) -> Self {
        let possibleValues: Set<DataFlowValue>? = if let current = self.possibleValues,
                                                       let next = other.possibleValues
        {
            current.union(next)
        } else {
            nil
        }
        return Self(
            possibleValues: possibleValues,
            excludedValues: excludedValues.intersection(other.excludedValues),
            excludedTypes: excludedTypes.intersection(other.excludedTypes)
        )
    }
}

struct VariableFlowState: Equatable {
    var possibleTypes: Set<TypeID>
    var nullability: Nullability
    var isStable: Bool
    var valueFacts: DataFlowValueFacts = DataFlowValueFacts()
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
        for symbol in locals.invalidatedVariableFacts {
            state.variables[symbol]?.valueFacts = DataFlowValueFacts()
        }
        for (symbol, facts) in locals.variableFacts {
            var variable = state.variables[symbol] ?? VariableFlowState(
                possibleTypes: [], nullability: .nonNull, isStable: true
            )
            variable.valueFacts = variable.valueFacts.combining(facts)
            state.variables[symbol] = variable
        }
        // Assignments update local bindings. Do not revive a stale fact from
        // an enclosing branch when splitting flow again after such a write.
        for local in locals.values where local.isMutable {
            if let variable = state.variables[local.symbol],
               variable.possibleTypes.count == 1, !variable.possibleTypes.contains(local.type)
            {
                state.variables.removeValue(forKey: local.symbol)
            }
        }
        return state
    }
}

struct WhenBranchSummary {
    let coveredSymbols: Set<InternedString>
    let coveredTypeSymbols: Set<SymbolID>
    let negatedTypeCheckTypes: Set<TypeID>
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
        coveredTypeSymbols: Set<SymbolID> = [],
        negatedTypeCheckTypes: Set<TypeID> = []
    ) {
        self.coveredSymbols = coveredSymbols
        self.coveredTypeSymbols = coveredTypeSymbols
        self.negatedTypeCheckTypes = negatedTypeCheckTypes
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
    var localDeclarations: [SymbolID: ExprID] = [:]
    init() {}

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
        guard let signature = sema.symbols.functionSignature(for: binding.chosenCallee) else {
            return base
        }
        var state = base
        for effect in sema.symbols.contractImplicationEffects(for: binding.chosenCallee) {
            guard effect.returnCondition == .normally || effect.returnCondition == result
                || (effect.returnCondition == .returnsNotNull && (result == .returnsTrue || result == .returnsFalse))
            else { continue }
            let argument: ExprID
            switch effect.target {
            case let .valueParameter(parameterIndex):
                guard let argumentIndex = binding.parameterMapping.first(where: { $0.value == parameterIndex })?.key,
                      args.indices.contains(argumentIndex) else { continue }
                argument = args[argumentIndex].expr
            case .extensionReceiver:
                guard signature.receiverType != nil,
                      case let .memberCall(receiver, _, _, _, _) = expr else { continue }
                argument = receiver
            }
            switch effect.argumentCondition {
            case .isType:
                if let rawTargetType = effect.targetType {
                    let parameters = signature.typeParameterSymbols
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
            interner: interner,
            narrowingToNonNull: true
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
            isStable: true,
            valueFacts: base[symbol]?.valueFacts ?? DataFlowValueFacts()
        )
        return variables
    }

    /// Narrows each stable side of an equality comparison to the other side's
    /// type when that type is strictly more precise (Kotlin smart cast on
    /// `x === y` / `x == y`).
    private func narrowStateForTypedEquality(
        lhsID: ExprID,
        rhsID: ExprID,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> DataFlowState {
        var state = base
        for (exprID, otherID) in [(lhsID, rhsID), (rhsID, lhsID)] {
            guard let (symbol, currentType, isStable) = resolveStableReference(
                exprID, locals: locals, ast: ast, sema: sema, interner: interner
            ), isStable,
               let otherType = sema.bindings.exprTypes[otherID],
               sema.types.isSubtype(otherType, currentType),
               !sema.types.isSubtype(currentType, otherType)
            else {
                continue
            }
            state[symbol] = VariableFlowState(
                possibleTypes: [otherType],
                nullability: sema.types.nullability(of: otherType),
                isStable: true,
                valueFacts: state[symbol]?.valueFacts ?? DataFlowValueFacts()
            )
        }
        return state
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
            if let valueBranch = branchOnDataFlowValueComparison(
                op: op, lhsID: lhsID, rhsID: rhsID,
                base: base, locals: locals, ast: ast, sema: sema, interner: interner
            ) {
                return valueBranch
            }
            if let value = booleanLiteral(rhsID, ast: ast, interner: interner),
               sema.bindings.exprTypes[lhsID] == sema.types.booleanType
            {
                return branchOnBooleanExpressionComparison(
                    op: op, expressionID: lhsID, equals: value,
                    base: base, locals: locals, ast: ast, sema: sema,
                    interner: interner, scope: scope
                )
            }
            if let value = booleanLiteral(lhsID, ast: ast, interner: interner),
               sema.bindings.exprTypes[rhsID] == sema.types.booleanType
            {
                return branchOnBooleanExpressionComparison(
                    op: op, expressionID: rhsID, equals: value,
                    base: base, locals: locals, ast: ast, sema: sema,
                    interner: interner, scope: scope
                )
            }
            let safeCallBranch = branchOnSafeCallComparison(
                op: op, lhsID: lhsID, rhsID: rhsID,
                base: base, locals: locals, ast: ast, sema: sema, interner: interner
            )
            let equalityTrueBase: DataFlowState = if let safeCallBranch {
                op == .equal || op == .identityEqual ? safeCallBranch.trueState : safeCallBranch.falseState
            } else {
                base
            }
            let equalityFalseBase: DataFlowState = if let safeCallBranch {
                op == .equal || op == .identityEqual ? safeCallBranch.falseState : safeCallBranch.trueState
            } else {
                base
            }
            let testedCall: ExprID?
            let trueResult: ContractReturnCondition
            var falseResult: ContractReturnCondition
            if isNullLiteral(rhsID, ast: ast) || isNullLiteral(lhsID, ast: ast) {
                testedCall = isNullLiteral(rhsID, ast: ast) ? lhsID : rhsID
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
                    trueState: applyContractImplications(
                        testedCall, result: trueResult, base: equalityTrueBase,
                        locals: locals, ast: ast, sema: sema, interner: interner, scope: scope
                    ),
                    falseState: applyContractImplications(
                        testedCall, result: falseResult, base: equalityFalseBase,
                        locals: locals, ast: ast, sema: sema, interner: interner, scope: scope
                    )
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
            if let safeCallBranch {
                return safeCallBranch
            }
            // `x === y` / `x == y` narrows the wider side to the tighter type on
            // the equality-true branch (the false branch of `!==`/`!=`).
            let typedEqualityTrueState = narrowStateForTypedEquality(
                lhsID: lhsID, rhsID: rhsID,
                base: base, locals: locals,
                ast: ast, sema: sema, interner: interner
            )
            if op == .notEqual || op == .notIdentityEqual {
                return ConditionBranch(trueState: base, falseState: typedEqualityTrueState)
            }
            return ConditionBranch(trueState: typedEqualityTrueState, falseState: base)
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

    private func branchOnDataFlowValueComparison(
        op: BinaryOp,
        lhsID: ExprID,
        rhsID: ExprID,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> ConditionBranch? {
        for (referenceExpr, valueExpr) in [(lhsID, rhsID), (rhsID, lhsID)] {
            guard let value = dataFlowValue(valueExpr, ast: ast, sema: sema, interner: interner),
                  value != .null,
                  let (reference, type, isStable) = resolveStableReference(
                      referenceExpr, locals: locals, ast: ast, sema: sema, interner: interner
                  ), isStable,
                  isDataFlowValue(value, compatibleWith: type, sema: sema)
            else {
                continue
            }

            var equalState = base
            var equalVariable = equalState[reference] ?? VariableFlowState(
                possibleTypes: [type],
                nullability: sema.types.nullability(of: type),
                isStable: true
            )
            if let possibleValues = equalVariable.valueFacts.possibleValues {
                equalVariable.valueFacts.possibleValues = possibleValues.intersection([value])
            } else {
                equalVariable.valueFacts.possibleValues = [value]
            }
            equalVariable.valueFacts.excludedValues.remove(value)
            equalState[reference] = equalVariable

            var unequalState = base
            var unequalVariable = unequalState[reference] ?? VariableFlowState(
                possibleTypes: [type],
                nullability: sema.types.nullability(of: type),
                isStable: true
            )
            if var possibleValues = unequalVariable.valueFacts.possibleValues {
                possibleValues.remove(value)
                unequalVariable.valueFacts.possibleValues = possibleValues
            } else {
                unequalVariable.valueFacts.excludedValues.insert(value)
            }
            unequalState[reference] = unequalVariable

            if op == .notEqual || op == .notIdentityEqual {
                return ConditionBranch(trueState: unequalState, falseState: equalState)
            }
            return ConditionBranch(trueState: equalState, falseState: unequalState)
        }
        return nil
    }

    private func branchOnBooleanExpressionComparison(
        op: BinaryOp,
        expressionID: ExprID,
        equals value: Bool,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope
    ) -> ConditionBranch {
        let inner = branchOnCondition(
            expressionID, base: base, locals: locals,
            ast: ast, sema: sema, interner: interner, scope: scope
        )
        let equalTrueState = value ? inner.trueState : inner.falseState
        let equalFalseState = value ? inner.falseState : inner.trueState
        if op == .notEqual || op == .notIdentityEqual {
            return ConditionBranch(trueState: equalFalseState, falseState: equalTrueState)
        }
        return ConditionBranch(trueState: equalTrueState, falseState: equalFalseState)
    }

    func dataFlowValue(
        _ id: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> DataFlowValue? {
        if let boolean = booleanLiteral(id, ast: ast, interner: interner) {
            return .boolean(boolean)
        }
        if isNullLiteral(id, ast: ast) {
            return .null
        }
        guard let symbolID = sema.bindings.identifierSymbols[id],
              let symbol = sema.symbols.symbol(symbolID)
        else {
            return nil
        }
        switch symbol.kind {
        case .object:
            return .symbol(symbolID)
        case .field where sema.symbols.enumOwnerSymbol(for: symbol) != nil:
            return .symbol(symbolID)
        default:
            return nil
        }
    }

    private func isDataFlowValue(
        _ value: DataFlowValue,
        compatibleWith type: TypeID,
        sema: SemaModule
    ) -> Bool {
        switch value {
        case .boolean:
            if case .primitive(.boolean, _) = sema.types.kind(of: type) { return true }
            return false
        case .null:
            return sema.types.nullability(of: type) == .nullable
        case let .symbol(valueSymbol):
            guard let owner = nominalSymbolID(of: type, types: sema.types),
                  let symbol = sema.symbols.symbol(valueSymbol)
            else {
                return false
            }
            if let enumOwner = sema.symbols.enumOwnerSymbol(for: symbol) {
                return enumOwner == owner
            }
            return symbol.kind == .object
                && TypeCheckHelpers().isNominalSubtype(valueSymbol, of: owner, symbols: sema.symbols)
        }
    }

    private func branchOnSafeCallComparison(
        op: BinaryOp,
        lhsID: ExprID,
        rhsID: ExprID,
        base: DataFlowState,
        locals: LocalBindings,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> ConditionBranch? {
        let equalityIsTrue = op == .equal || op == .identityEqual
        let receiver: ExprID
        let comparedValueID: ExprID
        if let safeReceiver = safeCallReceiver(of: lhsID, ast: ast) {
            receiver = safeReceiver
            comparedValueID = rhsID
        } else if let safeReceiver = safeCallReceiver(of: rhsID, ast: ast),
                  op == .identityEqual || op == .notIdentityEqual || isNullLiteral(lhsID, ast: ast)
        {
            // A user-defined equals() on the non-null left operand may report
            // equality with a null right operand, so structural equality is
            // only useful when the safe-call is on the left (or left is null).
            receiver = safeReceiver
            comparedValueID = lhsID
        } else {
            return nil
        }

        let equalityRequiresNonNullResult: Bool
        if isNullLiteral(comparedValueID, ast: ast) {
            equalityRequiresNonNullResult = false
        } else if let comparedType = sema.bindings.exprTypes[comparedValueID],
                  sema.types.nullability(of: comparedType) == .nonNull
        {
            equalityRequiresNonNullResult = true
        } else {
            return nil
        }

        let nonNullResultOnTrueBranch = equalityIsTrue == equalityRequiresNonNullResult
        let narrowedState = narrowNonNull(
            receiver, base: base, locals: locals, ast: ast, sema: sema, interner: interner
        )
        return ConditionBranch(
            trueState: nonNullResultOnTrueBranch ? narrowedState : base,
            falseState: nonNullResultOnTrueBranch ? base : narrowedState
        )
    }

    private func safeCallReceiver(of id: ExprID, ast: ASTModule) -> ExprID? {
        guard case let .safeMemberCall(receiver, _, _, _, _) = ast.arena.expr(id) else {
            return nil
        }
        return receiver
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
        if isNullLiteral(rhsID, ast: ast) {
            variableID = lhsID
        } else if isNullLiteral(lhsID, ast: ast) {
            variableID = rhsID
        } else {
            return nil
        }
        guard let (symbol, currentType, _) = resolveStableReference(
            variableID, locals: locals, ast: ast, sema: sema, interner: interner
        ) else {
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
        // `x == null` narrows a type parameter to `Nothing? & T` — Kotlin's
        // smart cast keeps `T`'s identity, so `arrayOf(k, v)` still joins at
        // `Any?` rather than `V?` (KUU-2693). Concrete nullable types keep
        // `Nothing?`.
        let nullType: TypeID
        if case .typeParam = sema.types.kind(of: effectiveType) {
            nullType = sema.types.make(.intersection([sema.types.nullableNothingType, effectiveType]))
        } else {
            nullType = sema.types.nullableNothingType
        }

        let nullStable = resolveStableReference(
            variableID, locals: locals, ast: ast, sema: sema, interner: interner, narrowingType: nullType
        )?.isStable ?? false

        let nonNullStable = resolveStableReference(
            variableID, locals: locals, ast: ast, sema: sema, interner: interner, narrowingToNonNull: true
        )?.isStable ?? false

        guard nullStable || nonNullStable else {
            return nil
        }

        var trueVars = base
        if nullStable {
            trueVars[symbol] = VariableFlowState(
                possibleTypes: [nullType],
                nullability: .nullable,
                isStable: true,
                valueFacts: base[symbol]?.valueFacts ?? DataFlowValueFacts()
            )
            trueVars[symbol]?.valueFacts.possibleValues = [.null]
        }
        var falseVars = base
        if nonNullStable {
            falseVars[symbol] = VariableFlowState(
                possibleTypes: [nonNullType],
                nullability: .nonNull,
                isStable: true,
                valueFacts: base[symbol]?.valueFacts ?? DataFlowValueFacts()
            )
            if var possibleValues = falseVars[symbol]?.valueFacts.possibleValues {
                possibleValues.remove(.null)
                falseVars[symbol]?.valueFacts.possibleValues = possibleValues
            } else {
                falseVars[symbol]?.valueFacts.excludedValues.insert(.null)
            }
        }
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
            exprID, locals: locals, ast: ast, sema: sema, interner: interner, narrowingType: rawTargetType
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
        let refinedTargetType = refineIsCheckTargetType(rawTargetType, priorType: priorType, sema: sema)
        let targetNullability = sema.types.nullability(of: refinedTargetType)
        // The first is-check must retain the declared type too (KUU-2138).
        // A non-null target also proves the prior value is non-null.
        let existingType = targetNullability == .nonNull ? sema.types.makeNonNullable(priorType) : priorType
        // A non-null prior value cannot be the null accepted by `is Marker?`.
        let targetType = isKnownNonNullForIsCheck(existingType, sema: sema)
            ? sema.types.makeNonNullable(refinedTargetType) : refinedTargetType
        let narrowedType: TypeID
        if sema.types.isSubtype(existingType, targetType) {
            narrowedType = existingType
        } else if sema.types.isSubtype(targetType, existingType) {
            narrowedType = targetType
        } else {
            // Keep chained checks flat so generic constraint decomposition can
            // still recover the nominal arguments from each conjunct.
            let parts: [TypeID] = if case let .intersection(existingParts) = sema.types.kind(of: existingType) {
                existingParts
            } else {
                [existingType]
            }
            narrowedType = sema.types.make(.intersection(parts + [targetType]))
        }
        var trueVars = base
        trueVars[symbol] = VariableFlowState(
            possibleTypes: [narrowedType],
            nullability: isKnownNonNullForIsCheck(narrowedType, sema: sema) ? .nonNull : targetNullability,
            isStable: true,
            valueFacts: base[symbol]?.valueFacts ?? DataFlowValueFacts()
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
            isStable: true,
            valueFacts: base[symbol]?.valueFacts ?? DataFlowValueFacts()
        )
        falseVars[symbol]?.valueFacts.excludedTypes.insert(refinedTargetType)
        return ConditionBranch(
            trueState: trueVars,
            falseState: falseVars
        )
    }

    private func isKnownNonNullForIsCheck(
        _ type: TypeID, sema: SemaModule, visiting: Set<TypeID> = []
    ) -> Bool {
        guard !visiting.contains(type) else { return false }
        let visiting = visiting.union([type])
        switch sema.types.kind(of: type) {
        case let .typeParam(parameter):
            // Bare T can contain null even without a syntactic '?' when its
            // upper bound is nullable. Do not use that spelling as a proof.
            guard parameter.nullability == .nonNull else { return false }
            let bounds = parameter.capture.map { [$0.upper] }
                ?? sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
            return bounds.contains { isKnownNonNullForIsCheck($0, sema: sema, visiting: visiting) }
        case let .intersection(parts):
            return parts.contains { isKnownNonNullForIsCheck($0, sema: sema, visiting: visiting) }
        default:
            return sema.types.isDefinitelyNonNull(type)
        }
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
        case .nullLiteral:
            var vars = base
            // See `branchOnNullComparison`: a type parameter narrows to
            // `Nothing? & T`, preserving its identity for later joins
            // (KUU-2693).
            let nullType: TypeID
            if case .typeParam = sema.types.kind(of: subjectType) {
                nullType = sema.types.make(.intersection([sema.types.nullableNothingType, subjectType]))
            } else {
                nullType = sema.types.nullableNothingType
            }
            vars[subjectSymbol] = VariableFlowState(
                possibleTypes: [nullType],
                nullability: .nullable,
                isStable: true,
                valueFacts: base[subjectSymbol]?.valueFacts ?? DataFlowValueFacts()
            )
            return vars
        case .nameRef:
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
                    isStable: true,
                    valueFacts: base[subjectSymbol]?.valueFacts ?? DataFlowValueFacts()
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
            guard let ownerID = sema.symbols.enumOwnerSymbol(for: conditionSymbol),
                  nominalSymbolID(of: subjectType, types: sema.types) == ownerID
            else {
                return base
            }
            let narrowed = sema.types.make(.classType(ClassType(
                classSymbol: ownerID, args: [], nullability: .nonNull
            )))
            var vars = base
            vars[subjectSymbol] = VariableFlowState(
                possibleTypes: [narrowed], nullability: .nonNull, isStable: true,
                valueFacts: base[subjectSymbol]?.valueFacts ?? DataFlowValueFacts()
            )
            return vars
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            guard let subjectNominal = nominalSymbolID(of: subjectType, types: sema.types),
                  TypeCheckHelpers().isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols)
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
                possibleTypes: [narrowed], nullability: .nonNull, isStable: true,
                valueFacts: base[subjectSymbol]?.valueFacts ?? DataFlowValueFacts()
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
            possibleTypes: [narrowed], nullability: narrowedNullability, isStable: true,
            valueFacts: base[subjectSymbol]?.valueFacts ?? DataFlowValueFacts()
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
            isStable: true,
            valueFacts: base[subjectSymbol]?.valueFacts ?? DataFlowValueFacts()
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
            isStable: true,
            valueFacts: base[subjectSymbol]?.valueFacts ?? DataFlowValueFacts()
        )
        return vars
    }

    func resolvedTypeFromFlowState(
        _ state: DataFlowState,
        symbol: SymbolID,
        types: TypeSystem? = nil
    ) -> TypeID? {
        return resolvedTypeFromFlowState(state, reference: DataFlowReference(root: symbol), types: types)
    }

    func resolvedTypeFromFlowState(
        _ state: DataFlowState,
        reference: DataFlowReference,
        types: TypeSystem? = nil
    ) -> TypeID? {
        guard let flowState = state[reference],
              flowState.isStable,
              !flowState.possibleTypes.isEmpty
        else {
            return nil
        }
        if flowState.possibleTypes.count == 1,
           let narrowed = flowState.possibleTypes.first
        {
            return narrowed
        }
        if let types {
            return types.lub(Array(flowState.possibleTypes))
        }
        return nil
    }

    private func isNullLiteral(_ id: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(id),
              case .nullLiteral = expr
        else {
            return false
        }
        return true
    }

    private func makeTypeNonNullable(_ type: TypeID, types: TypeSystem) -> TypeID {
        // A type parameter narrows to `T & Any` — Kotlin's definitely
        // non-null refinement — because bare `T` stays null-capable through
        // its implicit `Any?` bound (KUU-2693).
        types.definitelyNonNullForm(of: type)
    }

    private func nominalSymbolID(of type: TypeID, types: TypeSystem) -> SymbolID? {
        if case let .classType(classType) = types.kind(of: type) {
            return classType.classSymbol
        }
        return nil
    }


    func merge(_ lhs: DataFlowState, _ rhs: DataFlowState) -> DataFlowState {
        // An empty set means the path has no positive type information.
        // It must not inherit a narrowing that holds only on the other path.
        func mergedPossibleTypes(_ left: Set<TypeID>, _ right: Set<TypeID>) -> Set<TypeID> {
            guard !left.isEmpty, !right.isEmpty else { return [] }
            return left.union(right)
        }

        var merged: [SymbolID: VariableFlowState] = [:]
        for (symbol, lhsState) in lhs.variables {
            guard let rhsState = rhs.variables[symbol] else { continue }
            let types = mergedPossibleTypes(lhsState.possibleTypes, rhsState.possibleTypes)
            let nullability: Nullability = (lhsState.nullability == .nullable || rhsState.nullability == .nullable)
                ? .nullable
                : .nonNull
            merged[symbol] = VariableFlowState(
                possibleTypes: types,
                nullability: nullability,
                isStable: lhsState.isStable && rhsState.isStable,
                valueFacts: lhsState.valueFacts.joining(rhsState.valueFacts)
            )
        }
        var result = DataFlowState(variables: merged)
        for (reference, lhsState) in lhs.members {
            guard let rhsState = rhs.members[reference] else { continue }
            result.members[reference] = VariableFlowState(
                possibleTypes: mergedPossibleTypes(lhsState.possibleTypes, rhsState.possibleTypes),
                nullability: lhsState.nullability == .nullable || rhsState.nullability == .nullable ? .nullable : .nonNull,
                isStable: lhsState.isStable && rhsState.isStable,
                valueFacts: lhsState.valueFacts.joining(rhsState.valueFacts)
            )
        }
        return result
    }

    func isWhenExhaustive(
        subjectType: TypeID,
        branches: WhenBranchSummary,
        sema: SemaModule,
        valueFacts: DataFlowValueFacts? = nil
    ) -> Bool {
        if branches.hasElse {
            return true
        }
        // A finite reachable-value set is exhaustive on its own when every
        // value the subject can still take is covered, whatever its static
        // type is — a local narrowed to a singleton type (e.g. `s = S.O`
        // refining `s: S` to the object type) keeps its declared domain's
        // exhaustiveness only through this check.
        if let possibleValues = valueFacts?.possibleValues,
           possibleValues.allSatisfy({
               isWhenBranchCovered($0, branches: branches, sema: sema)
           })
        {
            return true
        }
        let kind = sema.types.kind(of: subjectType)
        switch kind {
        case .primitive(.boolean, .nonNull):
            return [DataFlowValue.boolean(true), .boolean(false)]
                .filter { valueMayReach($0, facts: valueFacts) }
                .allSatisfy { isWhenBranchCovered($0, branches: branches, sema: sema) }
        case .primitive(.boolean, .nullable):
            return [DataFlowValue.boolean(true), .boolean(false), .null]
                .filter { valueMayReach($0, facts: valueFacts) }
                .allSatisfy { isWhenBranchCovered($0, branches: branches, sema: sema) }
        case let .classType(classType):
            return isClassWhenExhaustive(
                classType: classType,
                branches: branches,
                sema: sema,
                valueFacts: valueFacts
            )
        case .typeParam:
            guard let upperBoundClassTypes = capturedUpperBoundClassTypes(for: subjectType, sema: sema) else {
                return false
            }
            return upperBoundClassTypes.contains {
                isClassWhenExhaustive(classType: $0, branches: branches, sema: sema, valueFacts: valueFacts)
            }
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
        case .typeParam:
            guard let upperBoundClassTypes = capturedUpperBoundClassTypes(for: subjectType, sema: sema) else {
                return false
            }
            return upperBoundClassTypes.contains { classType in
                guard let classSymbol = sema.symbols.symbol(classType.classSymbol) else {
                    return false
                }
                return classSymbol.kind == .enumClass || classSymbol.flags.contains(.sealedType)
            }
        default:
            return false
        }
    }

    /// P5-78: Returns the set of missing sealed subtype InternedString names for diagnostic purposes.
    /// Returns nil if the type is not a sealed type or if all branches are covered.
    func missingSealedBranches(
        subjectType: TypeID,
        branches: WhenBranchSummary,
        sema: SemaModule,
        valueFacts: DataFlowValueFacts? = nil
    ) -> [InternedString]? {
        if branches.hasElse {
            return nil
        }
        let classTypes: [ClassType]
        switch sema.types.kind(of: subjectType) {
        case let .classType(classType):
            classTypes = [classType]
        case .typeParam:
            classTypes = capturedUpperBoundClassTypes(for: subjectType, sema: sema) ?? []
        default:
            return nil
        }
        guard let classType = classTypes.first(where: { classType in
            sema.symbols.symbol(classType.classSymbol)?.flags.contains(.sealedType) == true
        }),
              let classSymbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }
        let subtypes = sealedSubtypeSymbols(for: classSymbol, sema: sema)
        guard !subtypes.isEmpty else {
            return nil
        }
        let missing = subtypes.flatMap {
            uncoveredSealedBranchSymbols($0, branches: branches, sema: sema, valueFacts: valueFacts)
        }
        guard !missing.isEmpty else {
            return nil
        }
        return Array(Set(missing.compactMap { sema.symbols.symbol($0)?.name }))
    }

    /// Returns the still-uncovered symbols under `subtype`: kotlinc names the
    /// missing leaf branches (`is B`) rather than a partially covered sealed
    /// intermediate (`N`), so a sealed subtype descends to its uncovered
    /// children when it cannot be proven covered as a whole (KUU-3775).
    private func uncoveredSealedBranchSymbols(
        _ subtype: SymbolID,
        branches: WhenBranchSummary,
        sema: SemaModule,
        valueFacts: DataFlowValueFacts?
    ) -> [SymbolID] {
        if isSealedSubtypeCovered(subtype, branches: branches, sema: sema, valueFacts: valueFacts) {
            return []
        }
        guard let subtypeSymbol = sema.symbols.symbol(subtype) else {
            return [subtype]
        }
        if subtypeSymbol.kind == .enumClass {
            // A partially covered enum child reports its uncovered entries
            // (`E.Y`), matching the subject-level enum exhaustiveness rule.
            let entries = enumEntrySymbols(for: subtypeSymbol, sema: sema)
            guard !entries.isEmpty else {
                return [subtype]
            }
            let uncovered = entries.filter {
                valueMayReach(.symbol($0), facts: valueFacts)
                    && !isWhenBranchCovered(.symbol($0), branches: branches, sema: sema)
            }
            return uncovered.isEmpty ? [subtype] : uncovered
        }
        guard subtypeSymbol.flags.contains(.sealedType) else {
            return [subtype]
        }
        let nested = sealedSubtypeSymbols(for: subtypeSymbol, sema: sema)
        guard !nested.isEmpty else {
            return [subtype]
        }
        return nested.flatMap {
            uncoveredSealedBranchSymbols($0, branches: branches, sema: sema, valueFacts: valueFacts)
        }
    }

    /// Exposes nominal components of a captured parameter's upper bound for
    /// closed-world `when` checks while preserving possible null values.
    private func capturedUpperBoundClassTypes(for subjectType: TypeID, sema: SemaModule) -> [ClassType]? {
        guard case let .typeParam(parameter) = sema.types.kind(of: subjectType),
              let capture = parameter.capture
        else {
            return nil
        }

        let upperBoundNullability = sema.types.nullability(of: capture.upper)
        let effectiveNullability: Nullability = parameter.nullability == .nonNull
            && upperBoundNullability == .nonNull
            ? .nonNull
            : .nullable

        func classTypes(in upperBound: TypeID) -> [ClassType] {
            switch sema.types.kind(of: upperBound) {
            case let .classType(classType):
                return [ClassType(
                    classSymbol: classType.classSymbol,
                    args: classType.args,
                    nullability: effectiveNullability
                )]
            case let .intersection(parts):
                return parts.flatMap(classTypes(in:))
            default:
                return []
            }
        }

        return classTypes(in: capture.upper)
    }

    private func isClassWhenExhaustive(
        classType: ClassType,
        branches: WhenBranchSummary,
        sema: SemaModule,
        valueFacts: DataFlowValueFacts? = nil
    ) -> Bool {
        guard let classSymbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }

        switch classSymbol.kind {
        case .enumClass:
            let enumEntrySymbols = enumEntrySymbols(for: classSymbol, sema: sema)
            guard !enumEntrySymbols.isEmpty else {
                return false
            }
            let hasAllReachableEntries = enumEntrySymbols.allSatisfy { entry in
                !valueMayReach(.symbol(entry), facts: valueFacts)
                    || isWhenBranchCovered(.symbol(entry), branches: branches, sema: sema)
            }
            let nullIsReachable = classType.nullability == .nullable
                && valueMayReach(.null, facts: valueFacts)
            return hasAllReachableEntries && (!nullIsReachable || branches.hasNullCase)

        default:
            if classSymbol.flags.contains(.sealedType) {
                let subtypes = sealedSubtypeSymbols(for: classSymbol, sema: sema)
                guard !subtypes.isEmpty else {
                    return false
                }
                let hasAllSealedSubtypes = subtypes.allSatisfy {
                    isSealedSubtypeCovered($0, branches: branches, sema: sema, valueFacts: valueFacts)
                }
                let nullIsReachable = classType.nullability == .nullable
                    && valueMayReach(.null, facts: valueFacts)
                return hasAllSealedSubtypes && (!nullIsReachable || branches.hasNullCase)
            }
            return false
        }
    }

    private func isSealedSubtypeCovered(
        _ subtype: SymbolID,
        branches: WhenBranchSummary,
        sema: SemaModule,
        valueFacts: DataFlowValueFacts? = nil
    ) -> Bool {
        // A sealed intermediate or enum class is never a value itself, so
        // `.symbol(subtype)` can never appear in a finite value set — the
        // leaf-oriented possibleValues shortcut would mark it covered
        // unconditionally. Its reachability is decided by the recursive
        // inhabitant check below.
        let enumeratesInhabitants: Bool = {
            guard let symbol = sema.symbols.symbol(subtype) else { return false }
            return symbol.flags.contains(.sealedType) || symbol.kind == .enumClass
        }()
        if !enumeratesInhabitants,
           let possibleValues = valueFacts?.possibleValues,
           !possibleValues.contains(.symbol(subtype))
        {
            return true
        }
        if valueFacts?.excludedValues.contains(.symbol(subtype)) == true {
            return true
        }
        if valueFacts?.excludedTypes.contains(where: {
            isSealedSubtypeWithin(subtype, targetType: $0, sema: sema)
        }) == true {
            return true
        }
        if let name = sema.symbols.symbol(subtype)?.name,
           branches.coveredSymbols.contains(name)
        {
            return true
        }
        if branches.coveredTypeSymbols.contains(where: {
            TypeCheckHelpers().isNominalSubtype(subtype, of: $0, symbols: sema.symbols)
        }) {
            return true
        }
        if branches.negatedTypeCheckTypes.contains(where: {
            isSealedSubtypeDisjointFrom(subtype, targetType: $0, sema: sema)
        }) {
            return true
        }
        // Inhabitant-enumerating subtypes propagate coverage upward: `is A` +
        // `is B` exhaust a sealed child `N : F`, and `E.X` + `E.Y` exhaust an
        // enum child `E : F` inside `when (f: F)` (KUU-3775).
        guard let subtypeSymbol = sema.symbols.symbol(subtype) else {
            return false
        }
        if subtypeSymbol.kind == .enumClass {
            let entries = enumEntrySymbols(for: subtypeSymbol, sema: sema)
            return !entries.isEmpty && entries.allSatisfy {
                !valueMayReach(.symbol($0), facts: valueFacts)
                    || isWhenBranchCovered(.symbol($0), branches: branches, sema: sema)
            }
        }
        if subtypeSymbol.flags.contains(.sealedType) {
            let nested = sealedSubtypeSymbols(for: subtypeSymbol, sema: sema)
            return !nested.isEmpty && nested.allSatisfy {
                isSealedSubtypeCovered($0, branches: branches, sema: sema, valueFacts: valueFacts)
            }
        }
        return false
    }

    private func valueMayReach(_ value: DataFlowValue, facts: DataFlowValueFacts?) -> Bool {
        guard let facts else { return true }
        if let possibleValues = facts.possibleValues, !possibleValues.contains(value) {
            return false
        }
        return !facts.excludedValues.contains(value)
    }

    private func isWhenBranchCovered(
        _ value: DataFlowValue,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> Bool {
        switch value {
        case .boolean(true):
            return branches.hasTrueCase
        case .boolean(false):
            return branches.hasFalseCase
        case .null:
            return branches.hasNullCase
        case let .symbol(symbol):
            guard let name = sema.symbols.symbol(symbol)?.name else { return false }
            return branches.coveredSymbols.contains(name)
                || branches.coveredTypeSymbols.contains(where: {
                    TypeCheckHelpers().isNominalSubtype(symbol, of: $0, symbols: sema.symbols)
                })
        }
    }

    /// A negative `is` fact excludes a sealed leaf only when that whole leaf
    /// is a subtype of the tested type.
    private func isSealedSubtypeWithin(
        _ subtype: SymbolID,
        targetType: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard case let .classType(targetClassType) = sema.types.kind(of: targetType),
              targetClassType.nullability == .nonNull
        else {
            return false
        }
        let subtypeType = sema.types.make(.classType(ClassType(
            classSymbol: subtype,
            args: [],
            nullability: .nonNull
        )))
        return sema.types.isSubtype(subtypeType, targetType)
    }

    /// A negated type check covers a sealed subtype only when their nominal
    /// ranges are provably disjoint. Open types, generic applications, and
    /// nullable targets can overlap in ways that the symbol graph cannot prove.
    private func isSealedSubtypeDisjointFrom(
        _ subtype: SymbolID,
        targetType: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard case let .classType(targetClassType) = sema.types.kind(of: targetType),
              targetClassType.nullability == .nonNull,
              targetClassType.args.isEmpty,
              sema.types.nominalTypeParameterSymbols(for: targetClassType.classSymbol).isEmpty,
              sema.types.nominalTypeParameterSymbols(for: subtype).isEmpty
        else {
            return false
        }

        let subtypeType = sema.types.make(.classType(ClassType(
            classSymbol: subtype,
            args: [],
            nullability: .nonNull
        )))
        guard !sema.types.isSubtype(subtypeType, targetType),
              !sema.types.isSubtype(targetType, subtypeType)
        else {
            return false
        }

        let targetSymbol = targetClassType.classSymbol
        if isClassNominalType(subtype, sema: sema),
           isClassNominalType(targetSymbol, sema: sema)
        {
            // Unrelated classes cannot share instances, even when either class
            // is open: Kotlin classes have a single superclass.
            return true
        }
        return isClosedNominalType(subtype, sema: sema)
            || isClosedNominalType(targetSymbol, sema: sema)
    }

    private func isClassNominalType(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return false
        }
        switch symbol.kind {
        case .class, .object, .enumClass, .annotationClass:
            return true
        default:
            return false
        }
    }

    private func isClosedNominalType(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return false
        }
        switch symbol.kind {
        case .class, .object, .enumClass, .annotationClass:
            return !symbol.flags.contains(.openType)
                && !symbol.flags.contains(.abstractType)
                && !symbol.flags.contains(.sealedType)
        default:
            return false
        }
    }

    /// P5-78: Get sealed subtype symbols, using sealedSubclasses metadata for cross-module support,
    /// falling back to directSubtypes for same-module sealed types.
    private func sealedSubtypeSymbols(for classSymbol: SemanticSymbol, sema: SemaModule) -> [SymbolID] {
        if let sealedSubs = sema.symbols.sealedSubclasses(for: classSymbol.id) {
            return sealedSubs
        }
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
        guard case let .classType(targetClass) = sema.types.kind(of: rawTargetType) else {
            return rawTargetType
        }
        // Read-only covariant targets retain the element information already
        // known through their supertype. Invariant targets keep their stars
        // so a mutable view never gains permission to write a wider value.
        let variances = sema.types.nominalTypeParameterVariances(for: targetClass.classSymbol)
        let preservesCovariantStars = !targetClass.args.isEmpty
            && targetClass.args.count == variances.count
            && zip(targetClass.args, variances).allSatisfy { argument, variance in
                if case .star = argument { return variance == .out }
                return false
            }
        guard targetClass.args.isEmpty || preservesCovariantStars,
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
           let typeParameterSymbol = TypeCheckHelpers().resolveTypeParameterSymbol(shortName, scope: scope, sema: sema),
           let typeParameter = sema.symbols.symbol(typeParameterSymbol),
           !typeParameter.flags.contains(.reifiedTypeParameter)
        {
            return nil
        }

        let targetType = TypeCheckHelpers().resolveTypeRef(
            typeRefID,
            ast: ast,
            sema: sema,
            interner: interner,
            scope: scope,
            allowBareGenericTypeAliasProjection: true
        )
        return targetType == sema.types.errorType ? nil : targetType
    }


    private func enumEntrySymbols(for enumSymbol: SemanticSymbol, sema: SemaModule) -> [SymbolID] {
        sema.symbols.children(ofFQName: enumSymbol.fqName).filter { childID in
            guard let child = sema.symbols.symbol(childID) else { return false }
            return sema.symbols.enumOwnerSymbol(for: child) == enumSymbol.id
        }
    }
}
