
extension CallTypeChecker {
    func sourceLevelRangeArgumentType(
        _ expr: ExprID,
        inferredType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        // Preserve the scalar binding for range lowering, but use the nominal
        // type for argument constraints, including generic upper bounds.
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
                return (nil, nil)
            }
            if op == .unaryMinus {
                let (negated, overflow) = value.multipliedReportingOverflow(by: -1)
                return (overflow ? nil : negated, nil)
            }
            return (value, nil)
        default:
            return (nil, nil)
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
            let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
            guard literal.signed != nil || literal.unsigned != nil,
                  let parameterIndex = resolved.parameterMapping[index],
                  signature.parameterTypes.indices.contains(parameterIndex)
            else { continue }
            let parameterType = ctx.sema.types.substituteTypeParameters(
                in: signature.parameterTypes[parameterIndex],
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
            _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: parameterType)
        }
    }

    /// Returns the expected numeric type (Long/UInt/ULong/Byte/Short) for an
    /// unsuffixed int-literal argument if every candidate agrees on that
    /// parameter being one of those types, so the literal can be widened before
    /// overload resolution instead of defaulting to Int and rejecting every
    /// candidate. Returns nil (leaving the literal as Int) when candidates
    /// disagree or none expect a wideable numeric type — the normal Int-literal
    /// path and existing overload resolution still handle those cases.
    func uniformNumericLiteralParameterType(
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
                // A parameter of non-numeric type can never accept an integer
                // literal -- it does not veto narrowing to a numeric overload
                // (e.g. `onTimeout(30)` with `Long` and `Duration` overloads).
                continue
            }
            // A plain `Int` candidate absorbs the literal as an exact match
            // and must not be pre-empted by narrowing.
            if primitive == .int {
                return nil
            }
            guard primitive == .long || primitive == .uint || primitive == .ulong ||
                  primitive == .byte || primitive == .short
            else {
                // Float/Double/other primitives cannot take an integer literal.
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

    /// Builds the same source-argument to parameter mapping that final overload
    /// resolution uses. The older index-only helpers cannot distinguish a
    /// positional vararg element from a later defaulted parameter once the
    /// argument list crosses the vararg slot.
    func parameterMappingForCallArguments(
        _ args: [CallArgument],
        in signature: FunctionSignature,
        ctx: TypeInferenceContext
    ) -> [Int: Int]? {
        let sema = ctx.sema
        let callArgs = args.map { argument in
            CallArg(
                label: argument.label,
                isSpread: argument.isSpread,
                type: sema.bindings.exprTypes[argument.expr] ?? sema.types.anyType
            )
        }
        return ctx.resolver.buildParameterMapping(
            signature: signature,
            callArgs: callArgs,
            symbols: sema.symbols,
            typeSystem: sema.types,
            isCallableArgument: { index in
                guard args.indices.contains(index) else { return false }
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

    /// The expected source type of one nested call argument. A spread argument
    /// and a named vararg argument carry the complete array at the call site;
    /// their contextual type is therefore the vararg array, not its element.
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

    /// Returns the single unsigned parameter type shared by all candidates for a
    /// suffixed unsigned literal. Unlike unsuffixed integer literals, Kotlin
    /// allows a constant UInt literal to narrow to UByte/UShort or widen to
    /// ULong when the expected parameter type requires it.
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
