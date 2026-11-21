
extension CallTypeChecker {
    func sourceLevelRangeArgumentType(
        _ expr: ExprID,
        inferredType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard sema.bindings.isRangeExpr(expr) || sema.bindings.isFloatingPointRangeExpr(expr),
              case .primitive = sema.types.kind(of: sema.types.makeNonNullable(inferredType)),
              let rangeType = floatingPointRangeArgumentType(
                  expr, ast: ctx.ast, sema: sema, interner: ctx.interner
              ) ?? sourceLevelRangeMemberLookupType(
                  receiverExpr: expr,
                  receiverType: inferredType,
                  sema: sema,
                  interner: ctx.interner
              )
        else {
            return inferredType
        }
        return sema.types.nullability(of: inferredType) == .nullable
            ? sema.types.makeNullable(rangeType)
            : rangeType
    }

    func integerLiteralValues(
        _ exprID: ExprID,
        ast: ASTModule
    ) -> (signed: Int64?, unsigned: UInt64?) {
        switch ast.arena.expr(exprID) {
        case let .intLiteral(value, _):
            return (value, nil)
        case let .uintLiteral(value, _):
            return (nil, value)
        case let .unaryExpr(op, operand, _) where op == .unaryMinus || op == .unaryPlus:
            guard case let .intLiteral(value, _) = ast.arena.expr(operand) else {
                return (integerConstantExpressionValue(exprID, ast: ast), nil)
            }
            if op == .unaryMinus {
                let (negated, overflow) = value.multipliedReportingOverflow(by: -1)
                return (overflow ? nil : negated, nil)
            }
            return (value, nil)
        default:
            if let value = integerConstantExpressionValue(exprID, ast: ast) {
                return (value, nil)
            }
            return (nil, nil)
        }
    }

    func integerArgumentValues(
        _ exprID: ExprID,
        ctx: TypeInferenceContext
    ) -> (signed: Int64?, unsigned: UInt64?) {
        let literal = integerLiteralValues(exprID, ast: ctx.ast)
        if literal.signed != nil || literal.unsigned != nil {
            return literal
        }

        let sema = ctx.sema
        let callee = sema.bindings.callBinding(for: exprID)?.chosenCallee
        let property = callee.flatMap {
            sema.symbols.accessorOwnerProperty(for: $0) ?? sema.symbols.parentSymbol(for: $0)
        }
        guard let symbol = sema.bindings.identifierSymbol(for: exprID) ?? property,
              let info = sema.symbols.symbol(symbol),
              info.kind == .property,
              info.flags.contains(.constValue),
              hasImplicitIntegerCoercionAnnotation(
                  sema.symbols.annotations(for: symbol), forParameter: false
              ),
              let constant = sema.symbols.constValueExprKind(for: symbol)
        else {
            return (nil, nil)
        }
        switch constant {
        case let .intLiteral(value), let .longLiteral(value):
            return (value, nil)
        default:
            return (nil, nil)
        }
    }

    func integerConstantExpressionValue(_ exprID: ExprID, ast: ASTModule) -> Int64? {
        switch ast.arena.expr(exprID) {
        case .binary, .memberCall, .unaryExpr:
            guard isIntegerLiteralOnlyExpression(exprID, ast: ast) else { return nil }
            let collector = ConstantCollector(canFoldMemberCall: { _ in true })
            guard case let .intLiteral(value) = collector.literalConstantExpr(exprID, ast: ast, interner: driver.interner) else {
                return nil
            }
            return value
        default:
            return nil
        }
    }

    private func isIntegerLiteralOnlyExpression(_ exprID: ExprID, ast: ASTModule) -> Bool {
        switch ast.arena.expr(exprID) {
        case .intLiteral:
            return true
        case let .unaryExpr(op, operand, _):
            return (op == .unaryMinus || op == .unaryPlus) && isIntegerLiteralOnlyExpression(operand, ast: ast)
        case let .binary(op, lhs, rhs, _):
            switch op {
            case .add, .subtract, .multiply, .divide, .modulo:
                return isIntegerLiteralOnlyExpression(lhs, ast: ast) && isIntegerLiteralOnlyExpression(rhs, ast: ast)
            default:
                return false
            }
        case let .memberCall(receiver, callee, typeArgs, args, _):
            guard typeArgs.isEmpty, args.count == 1, args[0].label == nil, !args[0].isSpread else { return false }
            switch driver.interner.resolve(callee) {
            case "shl", "shr", "ushr", "and", "or", "xor":
                return isIntegerLiteralOnlyExpression(receiver, ast: ast)
                    && isIntegerLiteralOnlyExpression(args[0].expr, ast: ast)
            default:
                return false
            }
        default:
            return false
        }
    }

    func contextualizeResolvedIntegerArguments(
        args: [CallArgument],
        resolved: ResolvedCall,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        guard let chosen = resolved.chosenCallee,
              let signature = ctx.sema.symbols.functionSignature(for: chosen)
        else { return }
        let typeVarBySymbol = ctx.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        for (index, argument) in args.enumerated() where !argument.isSpread {
            let literal = integerArgumentValues(argument.expr, ctx: ctx)
            guard literal.signed != nil || literal.unsigned != nil,
                  let parameterIndex = resolved.parameterMapping[index],
                  signature.parameterTypes.indices.contains(parameterIndex)
            else { continue }
            let parameterType = ctx.sema.types.substituteTypeParameters(
                in: signature.parameterTypes[parameterIndex],
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
            if ctx.sema.implicitSignedToUnsignedIntegerConversionEnabled,
               let value = literal.signed,
               signature.valueParameterSymbols.indices.contains(parameterIndex),
               hasImplicitIntegerCoercionAnnotation(
                   ctx.sema.symbols.annotations(for: signature.valueParameterSymbols[parameterIndex]),
                   forParameter: true
               ),
               let targetType = implicitSignedIntegerCoercionTargetType(
                   value, parameterType: parameterType, types: ctx.sema.types
               ),
               let convertedConstant = implicitSignedIntegerCoercionConstant(
                   value, to: parameterType, types: ctx.sema.types
               )
            {
                ctx.sema.bindings.bindExprType(argument.expr, type: targetType)
                ctx.sema.bindings.bindConstExprValue(argument.expr, value: convertedConstant)
                continue
            }
            _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: parameterType)
        }
    }

    /// Returns the expected numeric type (Long/Byte/Short) for an unsuffixed
    /// int-literal argument if every applicable candidate agrees on that
    /// parameter being one of those types, so the literal can be widened before
    /// overload resolution instead of defaulting to Int and rejecting every
    /// candidate. Unsigned parameters are deliberately excluded: Kotlin
    /// requires the `u`/`uL` suffix for UInt/ULong arguments, so leaving the
    /// literal as Int makes such calls fail resolution like kotlinc does
    /// (KUU-3890). Returns nil (leaving the literal as Int) when applicable
    /// candidates disagree or none expect a wideable numeric type — the normal
    /// Int-literal path and existing overload resolution still handle those cases.
    func uniformNumericLiteralParameterType(
        at index: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> TypeID? {
        var result: TypeID?
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return nil
            }
            guard let parameterType = parameterTypeForArgument(
                at: index,
                argumentLabel: argumentLabel,
                in: signature,
                sema: sema
            ) else {
                continue
            }
            let nonNullParameterType = sema.types.makeNonNullable(parameterType)
            guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullParameterType)
            else {
                continue
            }
            if primitive == .int {
                return nil
            }
            guard primitive == .long || primitive == .byte || primitive == .short
            else {
                continue
            }
            if let result, result != nonNullParameterType {
                return nil
            }
            result = nonNullParameterType
        }
        return result
    }

    func parameterTypeForArgument(
        at index: Int,
        argumentLabel: InternedString?,
        in signature: FunctionSignature,
        sema: SemaModule
    ) -> TypeID? {
        guard let argumentLabel else {
            return parameterTypeForArgument(at: index, in: signature)
        }
        for (parameterIndex, parameterSymbol) in signature.valueParameterSymbols.enumerated() {
            if sema.symbols.symbol(parameterSymbol)?.name == argumentLabel,
               parameterIndex < signature.parameterTypes.count
            {
                return signature.parameterTypes[parameterIndex]
            }
        }
        return nil
    }

    func parameterMappingForCallArguments(
        _ args: [CallArgument],
        in signature: FunctionSignature,
        callRange: SourceRange,
        ctx: TypeInferenceContext
    ) -> [Int: Int]? {
        let sema = ctx.sema
        let callArgs = args.map { argument in
            CallArg.source(
                argument, type: sema.bindings.exprTypes[argument.expr] ?? sema.types.anyType,
                callRange: callRange, ast: ctx.ast
            )
        }
        return ctx.resolver.buildParameterMapping(
            signature: signature,
            callArgs: callArgs,
            symbols: sema.symbols,
            typeSystem: sema.types,
            isCallableArgument: { index in
                guard args.indices.contains(index) else { return false }
                if ctx.ast.arena.isAnonymousFunction(args[index].expr) {
                    return true
                }
                if case .lambdaLiteral = ctx.ast.arena.expr(args[index].expr) {
                    return true
                }
                if case .callableRef = ctx.ast.arena.expr(args[index].expr) {
                    return true
                }
                guard let type = sema.bindings.exprTypes[args[index].expr] else {
                    return false
                }
                if case .functionType = sema.types.kind(of: type) {
                    return true
                }
                return false
            }
        )
    }

    func contextualCallArgumentType(
        _ argument: CallArgument,
        parameterIndex: Int,
        in signature: FunctionSignature,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        guard signature.parameterTypes.indices.contains(parameterIndex) else {
            return nil
        }
        let parameterType = signature.parameterTypes[parameterIndex]
        let isVararg = signature.valueParameterIsVararg.indices.contains(parameterIndex)
            && signature.valueParameterIsVararg[parameterIndex]
        guard isVararg, argument.isSpread || argument.label != nil else {
            return parameterType
        }
        if let primitiveArrayType = primitiveVarargArrayType(
            elementType: parameterType,
            sema: ctx.sema,
            interner: ctx.interner
        ) {
            return primitiveArrayType
        }
        let arrayName = ctx.interner.intern("Array")
        guard let arraySymbol = ctx.sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), arrayName]) else {
            return nil
        }
        return ctx.sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.out(parameterType)],
            nullability: .nonNull
        )))
    }

    func uniformContextualParameterType(
        for argument: CallArgument,
        at index: Int,
        candidates: [SymbolID],
        receiverType: TypeID? = nil,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        var commonType: TypeID?
        for candidate in candidates {
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  let parameterIndex = parameterIndexForCallArgument(
                      at: index,
                      label: argument.label,
                      in: signature,
                      sema: ctx.sema
                  ),
                  let declaredParameterType = contextualCallArgumentType(
                      argument,
                      parameterIndex: parameterIndex,
                      in: signature,
                      ctx: ctx
                  )
            else {
                return nil
            }
            let parameterType = applyReceiverClassTypeArgs(
                to: declaredParameterType,
                signature: signature,
                candidate: candidate,
                receiverType: receiverType,
                sema: ctx.sema
            )
            let typeVarBySymbol = ctx.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            guard !ctx.resolver.containsTypeVariable(
                parameterType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: ctx.sema.types
            ) else {
                return nil
            }
            if let commonType, commonType != parameterType {
                return nil
            }
            commonType = parameterType
        }
        return commonType
    }

    func uniformUnsignedLiteralParameterType(
        at index: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> TypeID? {
        var result: TypeID?
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = parameterTypeForArgument(
                      at: index,
                      argumentLabel: argumentLabel,
                      in: signature,
                      sema: sema
                  )
            else {
                return nil
            }
            let nonNullParameterType = sema.types.makeNonNullable(parameterType)
            guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullParameterType)
            else {
                continue
            }
            if primitive == .uint {
                return nil
            }
            guard primitive == .ubyte || primitive == .ushort ||
                  primitive == .uint || primitive == .ulong
            else {
                continue
            }
            if let result, result != nonNullParameterType {
                return nil
            }
            result = nonNullParameterType
        }
        return result
    }

    func integerLiteralFitsParameter(
        _ exprID: ExprID,
        parameterType: TypeID,
        ctx: TypeInferenceContext
    ) -> Bool {
        let values = integerLiteralValues(exprID, ast: ctx.ast)
        let types = ctx.sema.types
        guard case let .primitive(primitive, _) = types.kind(of: types.makeNonNullable(parameterType)) else {
            return false
        }
        if let value = values.signed {
            switch primitive {
            case .byte: return (-128...127).contains(value)
            case .short: return (-32768...32767).contains(value)
            case .long: return true
            default: return false
            }
        }
        if let value = values.unsigned {
            switch primitive {
            case .ubyte: return value <= UInt64(UInt8.max)
            case .ushort: return value <= UInt64(UInt16.max)
            case .ulong: return true
            default: return false
            }
        }
        return false
    }
}
