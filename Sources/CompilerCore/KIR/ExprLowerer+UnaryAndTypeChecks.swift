extension ExprLowerer {
    func lowerUnaryExpr(
        op: UnaryOp,
        operandExpr: ExprID,
        exprID: ExprID,
        boundType: TypeID?,
        intType: TypeID,
        boolType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let callBinding = sema.bindings.callBindings[exprID],
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil
        {
            return driver.callLowerer.lowerMemberCallExpr(
                exprID,
                receiverExpr: operandExpr,
                calleeName: interner.intern(op.kotlinFunctionName),
                args: [],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        // A folded Int constant expression widened to Long (`-(1 shl 31)`) must not
        // be re-evaluated from its Int operand at the wider type.
        if let constValue = sema.bindings.constExprValue(for: exprID) {
            let constResult = arena.appendExpr(constValue, type: boundType ?? sema.types.anyType)
            instructions.append(.constValue(result: constResult, value: constValue))
            return constResult
        }
        let operandID = lowerExpr(
            operandExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        switch op {
        case .unaryPlus:
            // `+x` produces x's value, not an alias of its storage: a bare
            // variable read resolves to that variable's own register, so
            // forwarding operandID lets a later write through either name
            // retroactively change the other (`val a = +b` and `var a = +b`
            // initializers, `+b + b++` binary lhs, `return +b` before a
            // mutating finally). Snapshot bare reads, same as the
            // `val a = b` aliasing guard in the `.localDecl` case.
            guard isBareVariableRead(operandExpr, ast: ast) else {
                return operandID
            }
            let result = arena.appendTemporary(type: boundType ?? arena.exprType(operandID))
            instructions.append(.copy(from: operandID, to: result))
            return result
        case .unaryMinus:
            // IEEE floating-point negation must flip the sign bit so that
            // `-(0.0) == -0.0`. Lowering it as `0.0 - x` is wrong because
            // `0.0 - 0.0 == +0.0`. Use `x * -1.0`, which preserves the sign
            // of zero, infinity and NaN. The result type of unary minus
            // equals the operand type, so fall back to the operand's type
            // when the unary expression itself has no recorded binding
            // (e.g. inside expression-body function bodies).
            let negationType = boundType
                ?? sema.bindings.exprTypes[operandExpr]
                ?? arena.exprType(operandID)
            if let negationType,
               case let .primitive(primitiveKind, _) = sema.types.kind(of: negationType),
               primitiveKind == .double || primitiveKind == .float {
                let negativeOne = arena.appendTemporary(type: negationType)
                let literalValue: KIRExprKind = primitiveKind == .double ? .doubleLiteral(-1.0) : .floatLiteral(-1.0)
                instructions.append(.constValue(result: negativeOne, value: literalValue))
                let result = arena.appendTemporary(type: negationType)
                instructions.append(.binary(op: .multiply, lhs: operandID, rhs: negativeOne, result: result))
                return result
            }
            let zero = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: zero, value: .intLiteral(0)))
            let result = arena.appendTemporary(type: boundType ?? intType)
            instructions.append(.binary(op: .subtract, lhs: zero, rhs: operandID, result: result))
            return result
        case .not:
            let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            let result = arena.appendTemporary(type: boundType ?? boolType)
            instructions.append(.binary(op: .equal, lhs: operandID, rhs: falseValue, result: result))
            return result
        }
    }

    func lowerIsCheckExpr(
        exprToCheck: ExprID,
        typeRefID: TypeRefID,
        negated: Bool,
        exprID: ExprID,
        boundType: TypeID?,
        boolType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let operandID = lowerExpr(
            exprToCheck,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let typeToken: KIRExprID = if let targetType = sema.bindings.isCheckTargetType(for: exprID) {
            lowerTypeCheckTokenExpr(
                targetType: runtimeIsCheckTargetType(
                    subjectType: sema.bindings.exprType(for: exprToCheck),
                    targetType: targetType,
                    sema: sema
                ),
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
        } else {
            lowerIsCheckTypeTokenExpr(
                typeRefID: typeRefID,
                ast: ast,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
        }
        let isResult = arena.appendTemporary(type: boundType ?? boolType)
        instructions.append(.call(callee: interner.intern("kk_op_is"), arguments: [operandID, typeToken], result: isResult, canThrow: false))
        guard negated else {
            return isResult
        }
        let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
        let negatedResult = arena.appendTemporary(type: boundType ?? boolType)
        instructions.append(.binary(op: .equal, lhs: isResult, rhs: falseValue, result: negatedResult))
        return negatedResult
    }

    /// The runtime erasure a non-reified `as T`/`as? T` can check against:
    /// the parameter's first upper bound, resolved transitively when bounds
    /// reference other type parameters. Kotlin/JVM checkcasts `as T` against
    /// exactly this erasure — `R : C, I1, I2` checks `C` and leaves the rest
    /// unchecked. Returns nil when there is no bound or the bound encodes no
    /// runtime classifier (`.any`/`.unknown`), where the cast keeps the
    /// null-contract-only behavior.
    private func checkableCastErasure(of type: TypeID, sema: SemaModule) -> TypeID? {
        var visited: Set<SymbolID> = []
        var current = type
        while case let .typeParam(parameter) = sema.types.kind(of: current) {
            guard visited.insert(parameter.symbol).inserted,
                  let bound = sema.symbols.typeParameterUpperBounds(for: parameter.symbol).first
            else {
                return nil
            }
            current = bound
        }
        switch RuntimeTypeCheckToken.classify(type: current, sema: sema).category {
        case .unknown, .any:
            return nil
        default:
            return current
        }
    }

    /// Both sides name the same class once `?` is stripped (`N` vs `N?`).
    /// The runtime check for such casts only re-verifies the class the
    /// operand already statically is — but a value class's operand carries
    /// its unboxed payload, which has no nominal tag for `kk_op_cast` to
    /// find, so the check must be resolved statically here.
    private func sameNominalCastClass(_ lhs: TypeID, _ rhs: TypeID, sema: SemaModule) -> Bool {
        guard case let .classType(lhsClass) = sema.types.kind(of: sema.types.makeNonNullable(lhs)),
              case let .classType(rhsClass) = sema.types.kind(of: sema.types.makeNonNullable(rhs))
        else {
            return false
        }
        return lhsClass.classSymbol == rhsClass.classSymbol
    }

    /// `x as V` on a null operand never throws, whatever `V`'s underlying
    /// type: kotlinc checkcasts the box, which always admits null, and does
    /// not insert the `checkNotNull` a non-value-class cast would get.
    private func isValueClassCastTarget(_ type: TypeID, sema: SemaModule) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.flags.contains(.valueType)
    }

    /// A plain T may admit null through its upper bounds even when its type
    /// parameter node has no explicit `?`. Follow dependent bounds as well.
    private func castTypeRequiresNonNull(_ type: TypeID, sema: SemaModule) -> Bool {
        var visited: Set<SymbolID> = []
        func requiresNonNull(_ type: TypeID) -> Bool {
            guard sema.types.nullability(of: type) == .nonNull else { return false }
            if case let .typeParam(parameter) = sema.types.kind(of: type) {
                guard visited.insert(parameter.symbol).inserted else { return false }
                return sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
                    .contains(where: requiresNonNull)
            }
            return sema.types.isDefinitelyNonNull(type)
        }
        return requiresNonNull(type)
    }

    func lowerAsCastExpr(
        exprToCast: ExprID,
        typeRefID: TypeRefID,
        isSafe: Bool,
        exprID: ExprID,
        boundType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let operandID = lowerExpr(
            exprToCast,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        if driver.controlFlowLowerer.isTerminatedExpr(operandID, arena: arena, sema: sema) {
            return operandID
        }
        if let targetType = sema.bindings.castTargetType(for: exprID),
           let componentType = referenceArrayElementType(targetType, sema: sema, interner: interner)
        {
            // Reference arrays retain their allocation component type even
            // though Kotlin's generic type arguments are otherwise erased.
            let componentToken = runtimeArrayComponentTypeExpr(
                for: componentType,
                context: driver.ctx,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let typeToken = lowerTypeCheckTokenExpr(
                targetType: targetType,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern(isSafe ? "kk_array_op_safe_cast" : "kk_array_op_cast"),
                arguments: [operandID, typeToken, componentToken],
                result: result,
                canThrow: !isSafe
            ))
            return result
        }
        if let targetType = sema.bindings.castTargetType(for: exprID),
           isRedundantComparableCast(
               from: sema.bindings.exprTypes[exprToCast],
               to: targetType,
               sema: sema
           )
        {
            return operandID
        }
        // `v as V`, `v as V?`, `v? as V`, `v? as V?` — same nominal class
        // modulo nullability. A value class's runtime representation is its
        // unboxed payload, so the nominal `kk_op_cast` check cannot see that
        // the operand is already an instance of its own class. Only the null
        // contract remains: `as` to a non-null target asserts non-null,
        // everything else is a pass-through.
        if let targetType = sema.bindings.castTargetType(for: exprID),
           let operandType = sema.bindings.exprType(for: exprToCast),
           sameNominalCastClass(operandType, targetType, sema: sema)
        {
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            if !isSafe,
               castTypeRequiresNonNull(targetType, sema: sema),
               !castTypeRequiresNonNull(operandType, sema: sema),
               !isValueClassCastTarget(targetType, sema: sema)
            {
                instructions.append(.nullAssert(operand: operandID, result: result))
            } else {
                instructions.append(.copy(from: operandID, to: result))
            }
            return result
        }
        // Unchecked erasure cast: `as`/`as?` to a non-reified type parameter.
        // Kotlin/JVM still checkcasts against the parameter's erasure — its
        // first upper bound — so `Any() as R` with `R : C, I1, I2` throws a
        // catchable ClassCastException rather than silently passing. Bounds
        // that erase to Any (unbounded T, `T : Any`) or encode no classifier
        // carry no runtime contract beyond nullability, so those keep the
        // null-assertion-only path below.
        if let targetType = sema.bindings.castTargetType(for: exprID),
           case let .typeParam(typeParam) = sema.types.kind(of: targetType),
           let typeParamSymbol = sema.symbols.symbol(typeParam.symbol),
           !typeParamSymbol.flags.contains(.reifiedTypeParameter)
        {
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            let operandIsNonNull = sema.bindings.exprType(for: exprToCast).map {
                castTypeRequiresNonNull($0, sema: sema)
            } ?? false
            if let erasure = checkableCastErasure(of: targetType, sema: sema) {
                // A statically non-null operand can still reach the runtime as
                // an unboxed Long.MIN_VALUE — the null sentinel — so its token
                // is marked nullable to skip the sentinel branch only, not the
                // classifier check itself.
                let tokenType = operandIsNonNull || !castTypeRequiresNonNull(targetType, sema: sema)
                    ? sema.types.makeNullable(erasure)
                    : sema.types.makeNonNullable(erasure)
                let typeToken = lowerTypeCheckTokenExpr(
                    targetType: tokenType,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
                instructions.append(.call(
                    callee: interner.intern(isSafe ? "kk_op_safe_cast" : "kk_op_cast"),
                    arguments: [operandID, typeToken],
                    result: result,
                    canThrow: !isSafe
                ))
                return result
            }
            // A check on a statically non-null value is redundant and can
            // misread an unboxed Long.MIN_VALUE after inline specialization.
            if !isSafe, !operandIsNonNull, castTypeRequiresNonNull(targetType, sema: sema) {
                instructions.append(.nullAssert(operand: operandID, result: result))
            } else {
                instructions.append(.copy(from: operandID, to: result))
            }
            return result
        }
        let typeToken: KIRExprID = if let targetType = sema.bindings.castTargetType(for: exprID) {
            lowerTypeCheckTokenExpr(
                targetType: targetType,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
        } else {
            lowerIsCheckTypeTokenExpr(
                typeRefID: typeRefID,
                ast: ast,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
        }
        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        instructions.append(.call(
            callee: interner.intern(isSafe ? "kk_op_safe_cast" : "kk_op_cast"),
            arguments: [operandID, typeToken],
            result: result,
            canThrow: !isSafe
        ))
        return result
    }
}
