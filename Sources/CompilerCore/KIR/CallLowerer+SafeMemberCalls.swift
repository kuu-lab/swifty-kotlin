
extension CallLowerer {
    // swiftlint:disable:next cyclomatic_complexity
    func lowerSafeMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext,
        precomputedReceiverID: KIRExprID? = nil
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers
        let boundType = sema.bindings.exprTypes[exprID]

        if let lateinitStatus = tryLowerLateinitIsInitialized(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return lateinitStatus
        }

        if sema.bindings.scopeFunctionKind(for: exprID) != nil {
            let scopeBoundType = boundType ?? sema.types.anyType
            let nullableResultType = sema.types.makeNullable(scopeBoundType)
            let result = arena.appendTemporary(type: nullableResultType
            )
            let loweredReceiver = precomputedReceiverID ?? driver.lowerExpr(
                receiverExpr,
                shared: shared,
                emit: &instructions
            )
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: loweredReceiver, target: nonNullLabel))
            let nullVal = arena.appendExpr(.unit, type: nullableResultType)
            instructions.append(.constValue(result: nullVal, value: .null))
            instructions.append(.copy(from: nullVal, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))
            if let scopeResult = tryScopeFunctionLowering(
                exprID,
                receiverExpr: receiverExpr,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions.instructions,
                precomputedReceiver: loweredReceiver
            ) {
                instructions.append(.copy(from: scopeResult, to: result))
            }
            instructions.append(.label(endLabel))
            return result
        }

        // const val member property folding (P5-109): check before lowering
        // receiver so no dead instructions are emitted.
        // Only fold actual const val properties (constValue flag); regular
        // immutable class members must not be folded because the receiver
        // expression may have side effects that would be silently dropped.
        // Only fold when the receiver is statically non-nullable.
        // For nullable receivers, safe-call semantics (`receiver?.const`)
        // require the result to be null if the receiver is null, so we
        // must not replace the whole expression with the constant value.
        if args.isEmpty {
            let callBinding = sema.bindings.callBindings[exprID]
            if let chosen = callBinding?.chosenCallee,
               let constant = propertyConstantInitializers[chosen],
               let symInfo = sema.symbols.symbol(chosen),
               symInfo.flags.contains(.constValue)
            {
                let receiverType = sema.bindings.exprTypes[receiverExpr]
                if let receiverType,
                   receiverType == sema.types.makeNonNullable(receiverType)
                {
                    let id = arena.appendExpr(constant, type: boundType ?? sema.types.anyType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
            }
        }

        let loweredReceiverID = precomputedReceiverID ?? driver.lowerExpr(
            receiverExpr,
            shared: shared, emit: &instructions
        )

        if let numberConversionResult = tryLowerNumberConversion(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions,
            precomputedReceiver: loweredReceiverID,
            safeCall: true
        ) {
            return numberConversionResult
        }

        if let comparableCharResult = tryLowerComparableCharCompareToSafeCall(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            loweredReceiverID: loweredReceiverID,
            boundType: boundType,
            shared: shared,
            emit: &instructions
        ) {
            return comparableCharResult
        }

        // KUU-3670: a member property declared `T` on a generic owner crosses
        // the read boundary as a raw erased handle. Keeping the safe-call
        // merge slot at the erased type preserves the handle until the
        // claim-site checkcast instead of reinterpreting it as the
        // substituted representation first.
        let safeCallDeclaresErasedProperty: Bool = {
            let memberSymbol = sema.bindings.identifierSymbol(for: exprID)
                ?? sema.bindings.callBindings[exprID]?.chosenCallee
            guard let memberSymbol,
                  let declaredType = sema.symbols.propertyType(for: memberSymbol)
                    ?? sema.symbols.propertySymbol(forAccessor: memberSymbol)
                        .flatMap({ sema.symbols.propertyType(for: $0) })
            else {
                return false
            }
            return kirIsNonReifiedErasedABIType(declaredType, sema: sema)
        }()
        let result = arena.appendTemporary(
            type: safeCallDeclaresErasedProperty
                ? sema.types.nullableAnyType
                : boundType ?? sema.types.anyType
        )
        let safeReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullSafeReceiverType = sema.types.makeNonNullable(safeReceiverType)
        let isCoroutineReceiver = if case .primitive = sema.types.kind(of: nonNullSafeReceiverType) {
            false
        } else {
            true
        }
        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            interner.intern("invoke")
        } else {
            calleeName
        }
        let calleeStr = interner.resolve(effectiveCalleeName)

        if calleeStr == "cancel",
           isCoroutineContextReceiverType(nonNullSafeReceiverType, sema: sema, interner: interner)
        {
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
            let nullableUnitType = sema.types.makeNullable(sema.types.unitType)
            let nullValue = arena.appendExpr(.unit, type: nullableUnitType)
            instructions.append(.constValue(result: nullValue, value: .null))
            let nullableResult = arena.appendTemporary(type: nullableUnitType)
            instructions.append(.copy(from: nullValue, to: nullableResult))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))
            let nonNullResult = arena.appendTemporary(type: sema.types.unitType)
            let loweredArgIDs: [KIRExprID]
            switch args.count {
            case 0:
                loweredArgIDs = []
            case 1:
                loweredArgIDs = [
                    driver.lowerExpr(
                        args[0].expr,
                        shared: shared, emit: &instructions
                    ),
                ]
            default:
                loweredArgIDs = []
            }
            let runtimeCallee = interner.intern(args.isEmpty ? "kk_context_cancel_no_cause" : "kk_context_cancel")
            instructions.append(.call(callee: runtimeCallee, arguments: [loweredReceiverID] + loweredArgIDs, result: nonNullResult, canThrow: false))
            instructions.append(.copy(from: nonNullResult, to: nullableResult))
            instructions.append(.label(endLabel))
            return nullableResult
        }

        // Boolean safe calls: return null on null receiver and only evaluate
        // arguments on the non-null path.
        if sema.types.isSubtype(nonNullSafeReceiverType, sema.types.booleanType) {
            let boolCallee: InternedString? = switch calleeStr {
            case "not" where args.isEmpty:
                interner.intern("kk_op_not")
            case "and" where args.count == 1:
                interner.intern("kk_bitwise_and")
            case "or" where args.count == 1:
                interner.intern("kk_bitwise_or")
            case "xor" where args.count == 1:
                interner.intern("kk_bitwise_xor")
            default:
                nil
            }
            if let boolCallee {
                let nonNullLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
                let nullableBooleanType = sema.types.makeNullable(sema.types.booleanType)
                let nullValue = arena.appendExpr(.unit, type: nullableBooleanType)
                instructions.append(.constValue(result: nullValue, value: .null))
                let nullableResult = arena.appendTemporary(type: nullableBooleanType)
                instructions.append(.copy(from: nullValue, to: nullableResult))
                instructions.append(.jump(endLabel))
                instructions.append(.label(nonNullLabel))
                // Unbox the nullable receiver before passing it to the Boolean
                // intrinsic, which expects a non-null primitive value.
                let nonNullReceiver = arena.appendTemporary(type: sema.types.booleanType)
                instructions.append(.copy(from: loweredReceiverID, to: nonNullReceiver))
                let nonNullResult = arena.appendTemporary(type: sema.types.booleanType)
                let argumentIDs: [KIRExprID]
                if args.isEmpty {
                    argumentIDs = []
                } else {
                    argumentIDs = [
                        driver.lowerExpr(
                            args[0].expr,
                            shared: shared, emit: &instructions
                        ),
                    ]
                }
                instructions.append(.call(callee: boolCallee, arguments: [nonNullReceiver] + argumentIDs, result: nonNullResult, canThrow: false))
                instructions.append(.copy(from: nonNullResult, to: nullableResult))
                instructions.append(.label(endLabel))
                return nullableResult
            }
        }

        if calleeStr == "inv",
           args.isEmpty,
           sema.bindings.callBinding(for: exprID) == nil
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSigned(nonNullReceiverType) || sema.types.isUnsigned(nonNullReceiverType) {
                let nonNullLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
                let callResultType = sema.types.makeNonNullable(boundType ?? sema.types.anyType)
                let nullableResultType = sema.types.makeNullable(callResultType)
                let nullValue = arena.appendExpr(.unit, type: nullableResultType)
                instructions.append(.constValue(result: nullValue, value: .null))
                let nullableResult = arena.appendTemporary(type: nullableResultType)
                instructions.append(.copy(from: nullValue, to: nullableResult))
                instructions.append(.jump(endLabel))
                instructions.append(.label(nonNullLabel))
                let nonNullResult = arena.appendTemporary(type: callResultType)
                var receiverArgument = loweredReceiverID
                if receiverType != nonNullReceiverType {
                    receiverArgument = arena.appendTemporary(type: nonNullReceiverType)
                    instructions.append(.copy(from: loweredReceiverID, to: receiverArgument))
                }
                emitNonThrowingCall(
                    callee: interner.intern("kk_op_inv"),
                    arg: receiverArgument,
                    result: nonNullResult,
                    into: &instructions.instructions
                )
                instructions.append(.copy(from: nonNullResult, to: nullableResult))
                instructions.append(.label(endLabel))
                return nullableResult
            }
        }

        // KSP-642: Int/Long rotateLeft / rotateRight are lowered as ordinary calls to
        // the bundled Kotlin declarations in `Stdlib/kotlin/Numbers.kt`.

        // Float?.mod(other) / Double?.mod(other): keep safe-call argument
        // evaluation behind the null check and use Kotlin floor-style modulo.
        if args.count == 1,
           calleeStr == "mod"
        {
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let rhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rhsType)
            let isFloatingReceiver = nonNullReceiverType == floatType || nonNullReceiverType == doubleType
            let isFloatingRhs = nonNullRhsType == floatType || nonNullRhsType == doubleType
            if isFloatingReceiver, isFloatingRhs {
                let resultType = nonNullReceiverType == doubleType || nonNullRhsType == doubleType ? doubleType : floatType
                let nonNullLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
                let nullableResultType = sema.types.makeNullable(resultType)
                let nullValue = arena.appendExpr(.unit, type: nullableResultType)
                instructions.append(.constValue(result: nullValue, value: .null))
                let nullableResult = arena.appendTemporary(type: nullableResultType)
                instructions.append(.copy(from: nullValue, to: nullableResult))
                instructions.append(.jump(endLabel))
                instructions.append(.label(nonNullLabel))

                var lhs = loweredReceiverID
                var rhs = driver.lowerExpr(args[0].expr, shared: shared, emit: &instructions)
                if resultType == doubleType {
                    if nonNullReceiverType == floatType {
                        let converted = arena.appendTemporary(type: doubleType)
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_float_to_double_bits"),
                            arg: lhs,
                            result: converted,
                            into: &instructions.instructions
                        )
                        lhs = converted
                    }
                    if nonNullRhsType == floatType {
                        let converted = arena.appendTemporary(type: doubleType)
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_float_to_double_bits"),
                            arg: rhs,
                            result: converted,
                            into: &instructions.instructions
                        )
                        rhs = converted
                    }
                }

                let nonNullResult = arena.appendTemporary(type: resultType)
                instructions.append(.call(
                    callee: interner.intern(resultType == doubleType ? "kk_op_dfloor_mod" : "kk_op_ffloor_mod"),
                    arguments: [lhs, rhs],
                    result: nonNullResult,
                    canThrow: false
                ))
                instructions.append(.copy(from: nonNullResult, to: nullableResult))
                instructions.append(.label(endLabel))
                return nullableResult
            }
        }

        // Char/Float/Double arithmetic member calls share the same primitive
        // lowering as operator syntax. Keep the argument behind the safe-call
        // null check, then feed a non-null receiver to operator lowering so
        // nullable boxing is removed before the intrinsic reads its bits.
        let chosenArithmeticCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
        let isSourceArithmeticExtension = chosenArithmeticCallee.map {
            sema.symbols.isSourceBackedSymbol($0)
                && sema.symbols.functionSignature(for: $0)?.receiverType != nil
        } == true
        if !isSourceArithmeticExtension,
           args.count == 1,
           let binaryOp = explicitFloatingOrCharArithmeticOp(calleeStr),
           isNumericPrimitiveOperand(args[0].expr, sema: sema),
           !(sema.bindings.isRangeExpr(receiverExpr)
               || ControlFlowTypeChecker.isRangeExpression(receiverExpr, ast: ast))
        {
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            )
            if receiverType == sema.types.charType
                || receiverType == floatType
                || receiverType == doubleType
            {
                let nonNullLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                let callResultType = sema.types.makeNonNullable(boundType ?? sema.types.anyType)
                let nullableResultType = sema.types.makeNullable(callResultType)
                let nullValue = arena.appendExpr(.unit, type: nullableResultType)
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
                instructions.append(.constValue(result: nullValue, value: .null))
                let nullableResult = arena.appendTemporary(type: nullableResultType)
                instructions.append(.copy(from: nullValue, to: nullableResult))
                instructions.append(.jump(endLabel))
                instructions.append(.label(nonNullLabel))

                let nonNullReceiver = arena.appendTemporary(type: receiverType)
                instructions.append(.copy(from: loweredReceiverID, to: nonNullReceiver))
                let loweredArgument = driver.lowerExpr(
                    args[0].expr,
                    shared: shared,
                    emit: &instructions
                )
                let nonNullResult = arena.appendTemporary(type: callResultType)
                instructions.append(.binary(
                    op: binaryOp,
                    lhs: nonNullReceiver,
                    rhs: loweredArgument,
                    result: nonNullResult
                ))
                instructions.append(.copy(from: nonNullResult, to: nullableResult))
                instructions.append(.label(endLabel))
                return nullableResult
            }
        }

        if args.count == 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSigned(nonNullReceiverType) || sema.types.isUnsigned(nonNullReceiverType) {
                let rawRhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
                let nonNullRhsType = sema.types.makeNonNullable(rawRhsType)
                let isShiftReceiver = nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
                let isBitwiseReceiver = isShiftReceiver || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
                let isUnsignedReceiver = sema.types.isUnsigned(nonNullReceiverType)
                let primitiveCallee: InternedString? = switch calleeStr {
                case "plus":
                    interner.intern("kk_op_add")
                case "minus":
                    interner.intern("kk_op_sub")
                case "times":
                    interner.intern("kk_op_mul")
                case "div":
                    // swiftlint:disable:next void_function_in_ternary
                    isUnsignedReceiver ? interner.intern("kk_op_udiv") : interner.intern("kk_op_div")
                case "floorDiv":
                    // swiftlint:disable:next void_function_in_ternary
                    isUnsignedReceiver ? interner.intern("kk_op_udiv") : interner.intern("kk_op_floor_div")
                case "rem":
                    // swiftlint:disable:next void_function_in_ternary
                    isUnsignedReceiver ? interner.intern("kk_op_urem") : interner.intern("kk_op_mod")
                case "mod":
                    isUnsignedReceiver
                        // swiftlint:disable:next void_function_in_ternary
                        ? interner.intern("kk_op_urem")
                        : interner.intern(nonNullReceiverType == longType || nonNullRhsType == longType ? "kk_op_lfloor_mod" : "kk_op_floor_mod")
                case "and":
                    isBitwiseReceiver && rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_and") : nil
                case "or":
                    isBitwiseReceiver && rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_or") : nil
                case "xor":
                    isBitwiseReceiver && rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_xor") : nil
                case "shl":
                    isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shl") : nil
                case "shr":
                    isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shr") : nil
                case "ushr":
                    (nonNullReceiverType == intType || nonNullReceiverType == longType) && rawRhsType == intType ? interner.intern("kk_op_ushr") : nil
                default:
                    nil
                }
                if let primitiveCallee {
                    let nonNullLabel = driver.ctx.makeLoopLabel()
                    let endLabel = driver.ctx.makeLoopLabel()
                    instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
                    let callResultType = sema.types.makeNonNullable(boundType ?? sema.types.anyType)
                    let nullableResultType = sema.types.makeNullable(callResultType)
                    let nullValue = arena.appendExpr(.unit, type: nullableResultType)
                    instructions.append(.constValue(result: nullValue, value: .null))
                    let nullableResult = arena.appendTemporary(type: nullableResultType)
                    instructions.append(.copy(from: nullValue, to: nullableResult))
                    instructions.append(.jump(endLabel))
                    instructions.append(.label(nonNullLabel))
                    // Give boxing lowering the non-null primitive type so it
                    // unboxes the receiver before applying the intrinsic.
                    let nonNullReceiver = arena.appendTemporary(type: nonNullReceiverType)
                    instructions.append(.copy(from: loweredReceiverID, to: nonNullReceiver))
                    let nonNullResult = arena.appendTemporary(type: callResultType)
                    let loweredArgID = driver.lowerExpr(
                        args[0].expr,
                        shared: shared,
                        emit: &instructions
                    )
                    instructions.append(.call(
                        callee: primitiveCallee,
                        arguments: [nonNullReceiver, loweredArgID],
                        result: nonNullResult,
                        canThrow: false
                    ))
                    instructions.append(.copy(from: nonNullResult, to: nullableResult))
                    instructions.append(.label(endLabel))
                    return nullableResult
                }
            }
        }

        // NOTE: Arguments are intentionally NOT lowered here. Each path
        // below must lower arguments only after the receiver null check so
        // that `receiver?.f(sideEffect())` does not evaluate sideEffect()
        // when receiver is null.

        // Int/Long.toString(radix: Int) is bundled Kotlin source
        // (Stdlib/kotlin/text/StringNumberConversions.kt, KSP-717) and falls
        // through to the general safe-call lowering below.
        if calleeStr == "toString",
           args.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                let callLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
                instructions.append(.constValue(result: nullExpr, value: .null))
                instructions.append(.copy(from: nullExpr, to: result))
                instructions.append(.jump(endLabel))
                instructions.append(.label(callLabel))
                let tagID = arena.appendExpr(.intLiteral(1), type: intType)
                instructions.append(.constValue(result: tagID, value: .intLiteral(1)))
                instructions.append(.call(
                    callee: interner.intern("kk_any_to_string"),
                    arguments: [loweredReceiverID, tagID],
                    result: result,
                    canThrow: false
                ))
                instructions.append(.label(endLabel))
                return result
            }
        }

        let anyFallbackReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullAnyFallbackReceiverType = sema.types.makeNonNullable(anyFallbackReceiverType)
        let isKClassReceiver = isKClassReceiverType(
            anyFallbackReceiverType, sema: sema, interner: interner
        )
        let allowsAnyFallback: Bool = if isKClassReceiver
            || usesPrimitiveAnyFallbackRepresentation(for: anyFallbackReceiverType, sema: sema)
        {
            true
        } else {
            switch sema.types.kind(of: nonNullAnyFallbackReceiverType) {
            case .stringStruct:
                false
            case .primitive:
                true
            case .typeParam:
                // All type parameters have an implicit upper bound of Any? in Kotlin,
                // so Any methods (toString, hashCode, equals) are always available on
                // type parameter receivers (STDLIB-GEN-055).
                true
            case .nothing:
                // A `Nothing?` receiver (`null` literal, `v: Nothing?`) unwraps to
                // non-null `Nothing` under a safe call. Its member scope is `Any`'s,
                // so `toString`/`hashCode`/`equals` resolve to the tagged
                // `kk_any_*` fallback, matching `Any?` receivers (KUU-3146).
                true
            default:
                nonNullAnyFallbackReceiverType == sema.types.anyType
            }
        }
        if args.isEmpty, calleeStr == "toString", allowsAnyFallback {
            let tag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let callLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
            instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
            instructions.append(.constValue(result: nullExpr, value: .null))
            instructions.append(.copy(from: nullExpr, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(callLabel))
            let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
            instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
            instructions.append(.call(
                callee: interner.intern("kk_any_to_string"),
                arguments: [loweredReceiverID, tagID],
                result: result,
                canThrow: false
            ))
            instructions.append(.label(endLabel))
            return result
        }

        if args.isEmpty, calleeStr == "hashCode", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let callLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
            instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
            instructions.append(.constValue(result: nullExpr, value: .null))
            instructions.append(.copy(from: nullExpr, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(callLabel))
            let hashReceiverID = boxSentinelProneHashCodeReceiver(
                loweredReceiverID,
                sourceType: anyFallbackReceiverType,
                sema: sema,
                interner: interner,
                arena: arena,
                into: &instructions.instructions
            )
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            instructions.append(.call(
                callee: interner.intern("kk_any_hashCode"),
                arguments: [hashReceiverID, receiverTagID],
                result: result,
                canThrow: false
            ))
            instructions.append(.label(endLabel))
            return result
        }

        if args.count == 1, calleeStr == "equals", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let callLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
            instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
            instructions.append(.constValue(result: nullExpr, value: .null))
            instructions.append(.copy(from: nullExpr, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(callLabel))
            let loweredEqualsArg = driver.lowerExpr(
                args[0].expr,
                shared: shared, emit: &instructions
            )
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let argType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let argTag = anyFallbackTag(for: argType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
            instructions.append(.constValue(result: argTagID, value: .intLiteral(argTag)))
            instructions.append(.call(
                callee: interner.intern("kk_any_equals"),
                arguments: [loweredReceiverID, receiverTagID, loweredEqualsArg, argTagID],
                result: result,
                canThrow: false
            ))
            instructions.append(.label(endLabel))
            return result
        }

        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.ubyteType
            let ushortType = sema.types.ushortType
            let byteType = sema.types.byteType
            let shortType = sema.types.shortType
            let charType = sema.types.charType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let rawNonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let nonNullReceiverType = smartcastNarrowedPrimitiveType(of: rawNonNullReceiverType, sema: sema)
                ?? rawNonNullReceiverType
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            let conversionCallee: InternedString? = switch (calleeStr, nonNullReceiverType, nonNullResultType) {
            case ("toInt", uintType, intType): interner.intern("kk_uint_to_int")
            case ("toInt", ulongType, intType): interner.intern("kk_ulong_to_int")
            case ("toInt", ubyteType, intType): interner.intern("kk_ubyte_to_int")
            case ("toInt", ushortType, intType): interner.intern("kk_ushort_to_int")
            case ("toInt", doubleType, intType): interner.intern("__kk_double_to_int")
            case ("toInt", floatType, intType): interner.intern("__kk_float_to_int")
            case ("toInt", longType, intType): interner.intern("kk_long_to_int")
            case ("toInt", byteType, intType): nil // identity
            case ("toInt", shortType, intType): nil // identity
            case ("toInt", intType, intType): nil // identity
            case ("toUInt", intType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", longType, uintType): interner.intern("kk_long_to_uint")
            case ("toUInt", ubyteType, uintType): interner.intern("kk_ubyte_to_uint")
            case ("toUInt", ushortType, uintType): interner.intern("kk_ushort_to_uint")
            case ("toUInt", byteType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", shortType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", uintType, uintType): nil // identity
            // KSP-1533: ULong.toUInt() narrows 64 bits to 32 and must mask the
            // high bits away (kk_ulong_to_uint has no dedicated symbol; reuse
            // kk_long_to_uint, which already truncates via UInt32(truncatingIfNeeded:)
            // on the same raw-register representation). Was wrongly treated as
            // representation-preserving, which left garbage high bits behind
            // (observed: ULong.MAX_VALUE.toUInt() printed as -1 / 4294967295uL+5
            // printed as 4294967301 instead of 5).
            case ("toUInt", ulongType, uintType): interner.intern("kk_long_to_uint")
            case ("toLong", intType, longType): interner.intern("kk_int_to_long")
            case ("toLong", uintType, longType): interner.intern("kk_uint_to_long")
            case ("toLong", ubyteType, longType): interner.intern("kk_ubyte_to_long")
            case ("toLong", ushortType, longType): interner.intern("kk_ushort_to_long")
            case ("toLong", doubleType, longType): interner.intern("__kk_double_to_long")
            case ("toLong", floatType, longType): interner.intern("__kk_float_to_long")
            case ("toLong", byteType, longType): nil // identity
            case ("toLong", shortType, longType): nil // identity
            case ("toLong", longType, longType), ("toLong", ulongType, longType): nil // identity
            case ("toULong", intType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", longType, ulongType): interner.intern("kk_long_to_ulong")
            case ("toULong", ubyteType, ulongType): interner.intern("kk_ubyte_to_ulong")
            case ("toULong", ushortType, ulongType): interner.intern("kk_ushort_to_ulong")
            case ("toULong", byteType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", shortType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
            case ("toULong", ulongType, ulongType): nil // identity
            case ("toFloat", intType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", longType, floatType): interner.intern("kk_long_to_float")
            case ("toFloat", doubleType, floatType): interner.intern("kk_double_to_float")
            case ("toFloat", floatType, floatType): nil // identity
            case ("toFloat", uintType, floatType): interner.intern("kk_uint_to_float")
            case ("toFloat", ulongType, floatType): interner.intern("kk_ulong_to_float")
            case ("toFloat", byteType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", shortType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", ubyteType, floatType): interner.intern("kk_ubyte_to_float")
            case ("toFloat", ushortType, floatType): interner.intern("kk_ushort_to_float")
            case ("toDouble", longType, doubleType): interner.intern("kk_long_to_double")
            case ("toDouble", floatType, doubleType): interner.intern("__kk_float_to_double_bits")
            case ("toDouble", doubleType, doubleType): nil // identity
            case ("toDouble", uintType, doubleType): interner.intern("kk_uint_to_double")
            case ("toDouble", ulongType, doubleType): interner.intern("kk_ulong_to_double")
            case ("toDouble", byteType, doubleType): interner.intern("kk_int_to_double_bits")
            case ("toDouble", shortType, doubleType): interner.intern("kk_int_to_double_bits")
            case ("toDouble", ubyteType, doubleType): interner.intern("kk_ubyte_to_double")
            case ("toDouble", ushortType, doubleType): interner.intern("kk_ushort_to_double")
            case ("toByte", intType, byteType): interner.intern("kk_int_to_byte")
            case ("toByte", longType, byteType): interner.intern("kk_long_to_byte")
            case ("toByte", uintType, byteType): interner.intern("kk_uint_to_byte")
            case ("toByte", ulongType, byteType): interner.intern("kk_ulong_to_byte")
            case ("toByte", ubyteType, byteType): interner.intern("kk_ubyte_to_byte")
            case ("toByte", ushortType, byteType): interner.intern("kk_ushort_to_byte")
            case ("toByte", byteType, byteType): nil // identity
            case ("toByte", shortType, byteType): interner.intern("kk_int_to_byte")
            case ("toShort", intType, shortType): interner.intern("kk_int_to_short")
            case ("toShort", longType, shortType): interner.intern("kk_long_to_short")
            case ("toShort", uintType, shortType): interner.intern("kk_uint_to_short")
            case ("toShort", ulongType, shortType): interner.intern("kk_ulong_to_short")
            case ("toShort", ubyteType, shortType): interner.intern("kk_ubyte_to_short")
            case ("toShort", ushortType, shortType): interner.intern("kk_ushort_to_short")
            case ("toShort", byteType, shortType): nil // identity
            case ("toShort", shortType, shortType): nil // identity
            case ("toUByte", intType, ubyteType): interner.intern("kk_int_to_ubyte")
            case ("toUByte", longType, ubyteType): interner.intern("kk_long_to_ubyte")
            case ("toUByte", uintType, ubyteType): interner.intern("kk_uint_to_ubyte")
            case ("toUByte", ulongType, ubyteType): interner.intern("kk_ulong_to_ubyte")
            case ("toUByte", ubyteType, ubyteType): nil // identity
            case ("toUByte", ushortType, ubyteType): interner.intern("kk_ushort_to_ubyte")
            case ("toUByte", byteType, ubyteType): interner.intern("kk_byte_to_ubyte")
            case ("toUByte", shortType, ubyteType): interner.intern("kk_short_to_ubyte")
            case ("toUShort", intType, ushortType): interner.intern("kk_int_to_ushort")
            case ("toUShort", byteType, ushortType): interner.intern("kk_int_to_ushort")
            case ("toUShort", shortType, ushortType): interner.intern("kk_int_to_ushort")
            case ("toUShort", longType, ushortType): interner.intern("kk_long_to_ushort")
            case ("toUShort", uintType, ushortType): interner.intern("kk_uint_to_ushort")
            case ("toUShort", ulongType, ushortType): interner.intern("kk_ulong_to_ushort")
            case ("toUShort", ubyteType, ushortType): interner.intern("kk_ubyte_to_ushort")
            case ("toUShort", ushortType, ushortType): nil // identity
            case ("toChar", charType, charType): nil // identity
            default: nil
            }
            if let callee = conversionCallee {
                let nonNullLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
                let nullValue = arena.appendExpr(.unit, type: resultType)
                instructions.append(.constValue(result: nullValue, value: .null))
                instructions.append(.copy(from: nullValue, to: result))
                instructions.append(.jump(endLabel))
                instructions.append(.label(nonNullLabel))
                // The receiver slot keeps its erased/nullable
                // representation under the non-null branch; materialize
                // the raw primitive so the conversion callee consumes the
                // payload, not the box handle or sentinel.
                let conversionReceiverID = materializePrimitiveValue(
                    loweredReceiverID, toType: nonNullReceiverType, sema: sema,
                    arena: arena, instructions: &instructions.instructions
                ) ?? loweredReceiverID
                let nonNullResult = arena.appendTemporary(type: nonNullResultType)
                instructions.append(.call(callee: callee, arguments: [conversionReceiverID], result: nonNullResult, canThrow: false))
                instructions.append(.copy(from: nonNullResult, to: result))
                instructions.append(.label(endLabel))
                return result
            }
            let isRepresentationPreservingConversion =
                (calleeStr == "toLong" && nonNullReceiverType == ulongType && nonNullResultType == longType)
                    || (calleeStr == "toULong" && nonNullReceiverType == longType && nonNullResultType == ulongType)
                    || (calleeStr == "toInt" && (nonNullReceiverType == byteType || nonNullReceiverType == shortType) && nonNullResultType == intType)
                    || (calleeStr == "toLong" && (nonNullReceiverType == byteType || nonNullReceiverType == shortType) && nonNullResultType == longType)
                    || (calleeStr == "toShort" && nonNullReceiverType == byteType && nonNullResultType == shortType)
            // Identity conversions have no runtime callee; keep them from
            // falling through to generic member emission as raw symbols
            // (`Short?.toShort()`, `UByte?.toUByte()` linked against `_toShort`).
            if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toByte", "toShort", "toUByte", "toUShort"].contains(calleeStr),
               nonNullReceiverType == nonNullResultType || isRepresentationPreservingConversion,
               nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType || nonNullReceiverType == byteType || nonNullReceiverType == shortType || nonNullReceiverType == floatType || nonNullReceiverType == doubleType
            {
                if nonNullReceiverType == nonNullResultType {
                    instructions.append(.copy(from: loweredReceiverID, to: result))
                    return result
                }
                // The receiver's box is tagged with the receiver's type, so
                // copying it would hand out a `ULong` where a `Long?` is
                // expected (`ULong?.toLong()` printed as an unsigned value).
                // Unbox the payload and let the result copy box it again under
                // the result type.
                let nonNullLabel = driver.ctx.makeLoopLabel()
                let endLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
                let nullValue = arena.appendExpr(.unit, type: resultType)
                instructions.append(.constValue(result: nullValue, value: .null))
                instructions.append(.copy(from: nullValue, to: result))
                instructions.append(.jump(endLabel))
                instructions.append(.label(nonNullLabel))
                let conversionReceiverID = materializePrimitiveValue(
                    loweredReceiverID, toType: nonNullReceiverType, sema: sema,
                    arena: arena, instructions: &instructions.instructions
                ) ?? loweredReceiverID
                let nonNullResult = arena.appendTemporary(type: nonNullResultType)
                instructions.append(.copy(from: conversionReceiverID, to: nonNullResult))
                instructions.append(.copy(from: nonNullResult, to: result))
                instructions.append(.label(endLabel))
                return result
            }
        }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: effectiveCalleeName,
            argumentExprs: args.map(\.expr),
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        let chosen: SymbolID? = if let chosenCallee = callBinding?.chosenCallee, chosenCallee != .invalid {
            chosenCallee
        } else {
            nil
        }

        // Emit null-check BEFORE lowering arguments so that
        // receiver?.f(sideEffect()) does not evaluate sideEffect()
        // when receiver is null.
        let callLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let nullExpr = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
        instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: callLabel))
        instructions.append(.constValue(result: nullExpr, value: .null))
        instructions.append(.copy(from: nullExpr, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(callLabel))

        if let invokeResult = tryLowerNominalPropertyInvocation(
            exprID, receiverExpr: receiverExpr, args: args, precomputedReceiver: loweredReceiverID,
            shared: shared, emit: &instructions
        ) {
            instructions.append(.copy(from: invokeResult, to: result))
            instructions.append(.label(endLabel))
            return result
        }

        if let invokeResult = tryLowerLexicalExtensionCallableInvocation(
            exprID,
            receiverExpr: receiverExpr,
            loweredReceiverID: loweredReceiverID,
            calleeName: effectiveCalleeName,
            args: args,
            shared: shared,
            emit: &instructions
        ) {
            instructions.append(.copy(from: invokeResult, to: result))
            instructions.append(.label(endLabel))
            return result
        }

        if let primitiveCompareResult = tryLowerPrimitiveCompareTo(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: effectiveCalleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            precomputedReceiver: loweredReceiverID,
            instructions: &instructions.instructions
        ) {
            instructions.append(.copy(from: primitiveCompareResult, to: result))
            instructions.append(.label(endLabel))
            return result
        }

        // Mirrors the non-safe-call arm in `lowerMemberCallExpr` and goes
        // through `lowerResolvedCallBody` so positional-receiver / default-arg
        // shapes stay consistent.
        if let invokeResult = tryLowerFunctionTypeInvokeMemberCall(
            exprID,
            calleeName: effectiveCalleeName,
            args: args,
            loweredReceiverID: loweredReceiverID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            instructions.append(.copy(from: invokeResult, to: result))
            instructions.append(.label(endLabel))
            return result
        }

        // The receiver is already known non-null here. Explicit
        // `x?.invoke(args)` is handled above.
        if let callableBinding = sema.bindings.callableValueCalls[exprID],
           case let .functionType(fnType) = sema.types.kind(of: callableBinding.functionType),
           let invokeCallee = runtimeCallableInvokeCallee(
               callableValueCallBinding: callableBinding,
               sema: sema,
               interner: interner
           )
        {
            // Resolve the call prefix first so that a missed arm does not
            // emit dead argument instructions.
            var callSymbol: SymbolID?
            var callCallee = invokeCallee
            var callPrefix: [KIRExprID]?
            switch callableBinding.target {
            case .localValue(let localSym):
                if sema.symbols.symbol(localSym)?.kind == .property {
                    if let functionValue = lowerStoredMemberPropertyReadValue(
                        propertySymbol: localSym, callExprID: exprID,
                        receiverExpr: receiverExpr,
                        loweredReceiverID: loweredReceiverID,
                        resultType: callableBinding.functionType,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions.instructions
                    ) {
                        callSymbol = localSym
                        var prefix = [functionValue]
                        if fnType.receiver != nil,
                           callableBinding.receiverArgumentOffset == 0,
                           sema.symbols.extensionPropertyReceiverType(for: localSym) == nil
                        {
                            prefix.append(loweredReceiverID)
                        }
                        callPrefix = prefix
                    }
                } else if let functionValue = lowerLateinitLocalCallableRead(
                    symbol: localSym, sema: sema, arena: arena,
                    interner: interner, instructions: &instructions.instructions
                ) {
                    callSymbol = localSym
                    callPrefix = [functionValue, loweredReceiverID]
                } else if let localExprID = driver.ctx.localValue(for: localSym) {
                    if let info = driver.ctx.callableValueInfo(for: localExprID) {
                        callSymbol = info.symbol
                        callCallee = info.callee
                        callPrefix = info.captureArguments + [loweredReceiverID]
                    } else {
                        callSymbol = localSym
                        callPrefix = [localExprID, loweredReceiverID]
                    }
                }
            case nil:
                // `.invoke` sugar on a function value: the lowered receiver
                // itself is the function object.
                callPrefix = [loweredReceiverID]
            case .symbol:
                break
            }
            if var callPrefix {
                let loweredArgIDs = args.map { argument in
                    driver.lowerExpr(argument.expr, shared: shared, emit: &instructions)
                }
                callPrefix.append(contentsOf: normalizedCallableValueArguments(
                    providedArguments: loweredArgIDs,
                    callableValueCallBinding: callableBinding,
                    sema: sema
                ))
                let nonNullResult = arena.appendTemporary(type: fnType.returnType)
                instructions.append(.call(symbol: callSymbol, callee: callCallee, arguments: callPrefix, result: nonNullResult, canThrow: false))
                instructions.append(.copy(from: nonNullResult, to: result))
                instructions.append(.label(endLabel))
                return result
            }
        }

        // Handle the safe-call form here after the receiver null check;
        // otherwise the generic fallback emits an undefined `name` symbol.
        if tryLowerKCallableNameAccess(
            propertySymbol: sema.bindings.identifierSymbol(for: exprID),
            receiverType: nonNullSafeReceiverType,
            receiverID: loweredReceiverID,
            result: result,
            calleeName: effectiveCalleeName,
            sema: sema,
            interner: interner,
            instructions: &instructions.instructions
        ) {
            instructions.append(.label(endLabel))
            return result
        }

        // Keep the member's non-null primitive result separate from the safe-call
        // merge slot so ABI lowering boxes sentinel-colliding payloads.
        let memberResultType: TypeID = {
            let resultType = arena.exprType(result) ?? sema.types.nullableAnyType
            let memberSymbol = sema.bindings.identifierSymbol(for: exprID) ?? chosen
            let declaredType = memberSymbol.flatMap {
                sema.symbols.propertyType(for: $0) ?? sema.symbols.functionSignature(for: $0)?.returnType
            }
            guard let declaredType else { return resultType }
            // A nullable-underlying value class member yields the `V` payload
            // representation; splitting the merge slot lets the `V` -> `V?`
            // copy box it rather than storing the payload verbatim
            // (KUU-3115).
            if nullableUnderlyingValueClassSymbol(
                of: sema.types.kind(of: declaredType),
                types: sema.types, symbols: sema.symbols
            ) != nil,
               valueClassBoxTargetIsBoxed(
                   sema.types.kind(of: resultType), symbols: sema.symbols
               )
            {
                return declaredType
            }
            guard case let .primitive(declaredPrimitive, .nonNull) = resolveValueClassKind(
                      sema.types.kind(of: declaredType), types: sema.types, symbols: sema.symbols
                  ),
                  case let .primitive(resultPrimitive, .nonNull) = resolveValueClassKind(
                      sema.types.kind(of: sema.types.makeNonNullable(resultType)),
                      types: sema.types, symbols: sema.symbols
                  ),
                  declaredPrimitive == resultPrimitive
            else { return resultType }
            return sema.types.makeNonNullable(resultType)
        }()
        let memberResult = arena.exprType(result) == memberResultType
            ? result : arena.appendTemporary(type: memberResultType)

        // Preserve the getter or backing-field value: a platform Unit! may
        // carry null even when the property's declared type is Unit.

        // Enum.name/ordinal use ordinal helpers, not constructor-property
        // storage. Keep the primitive ordinal result non-null until the merge.
        if let enumProperty = tryLowerEnumEntryPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: effectiveCalleeName,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            resultTypeOverride: memberResultType,
            instructions: &instructions.instructions
        ) {
            instructions.append(.copy(from: enumProperty, to: result))
            instructions.append(.label(endLabel))
            return result
        }

        if args.isEmpty,
           let propSym = sema.bindings.identifierSymbol(for: exprID),
           let extLink = sema.symbols.externalLinkName(for: propSym),
           !extLink.isEmpty,
           !shouldDeferCollectionSizePropertyRead(
               propSym,
               receiverExpr: receiverExpr,
               sema: sema,
               interner: interner
           )
        {
            instructions.append(.call(
                symbol: propSym,
                callee: interner.intern(extLink),
                arguments: [loweredReceiverID],
                result: memberResult,
                canThrow: false
            ))
            if memberResult != result {
                instructions.append(.copy(from: memberResult, to: result))
            }
            instructions.append(.label(endLabel))
            return result
        }

        if let accessorRead = tryLowerMemberPropertyAccessorRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            result: memberResult,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions.instructions
        ) {
            if accessorRead != result {
                instructions.append(.copy(from: accessorRead, to: result))
            }
            instructions.append(.label(endLabel))
            return result
        }

        // Stored (field-backed) member property read, e.g. `w?.value` on a
        // class/value-class whose property has no custom getter. Without this,
        // safe-call property reads fell through to the generic call fallback
        // below, which emits a call to a callee literally named after the
        // property (e.g. "value") instead of a field-offset read — an
        // undefined symbol at link time.
        if let storedRead = tryLowerStoredMemberPropertyRead(
            exprID,
            receiverExpr: receiverExpr,
            loweredReceiverID: loweredReceiverID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            resultTypeOverride: memberResultType,
            instructions: &instructions.instructions
        ) {
            instructions.append(.copy(from: storedRead, to: result))
            instructions.append(.label(endLabel))
            return result
        }

        // Lower arguments only on the non-null path.
        let loweredArgIDs = args.enumerated().map { argumentIndex, argument in
            let previousAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
                argumentExpr: argument.expr,
                argumentIndex: argumentIndex,
                ast: ast,
                sema: sema,
                callBinding: callBinding,
                chosen: chosen
            )
            defer { driver.ctx.pendingLambdaNonLocalReturnAllowance = previousAllowance }
            return driver.lowerExpr(
                argument.expr,
                shared: shared, emit: &instructions
            )
        }
        let safeNormalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: loweredArgIDs,
            callBinding: callBinding,
            chosenCallee: chosen,
            spreadFlags: args.map(\.isSpread),
            argumentLabels: args.map(\.label),
            shared: shared, emit: &instructions
        )
        var finalArguments = safeNormalized.arguments
        if let chosen,
           sema.symbols.symbol(chosen)?.kind == .constructor,
           let innerClassSymbol = sema.symbols.parentSymbol(for: chosen),
           sema.symbols.symbol(innerClassSymbol)?.flags.contains(.innerClass) == true
        {
            // BUG-inner-outer: `outer?.Inner(args)` resolves to Inner's own
            // constructor just like the non-safe `outer.Inner(args)` form
            // (see `lowerMemberLikeCallExpr`'s matching intercept) --
            // allocate a real `Inner` instance and store `outer` (confirmed
            // non-null past `callLabel` above) into its `$outer` link,
            // instead of splicing `outer`'s own value in as if it already
            // were the constructed object.
            let allocatedObj = allocateAndRegisterConstructedObject(
                chosen: chosen,
                boundType: boundType.map { sema.types.makeNonNullable($0) },
                outerReceiver: loweredReceiverID,
                driver: driver,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions.instructions
            )
            finalArguments.insert(allocatedObj, at: 0)
            materializeSourceBackedFunctionValueArguments(
                chosenCallee: chosen,
                sourceArgExprs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions.instructions,
                arguments: &finalArguments
            )
        } else if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen),
           let declaredReceiverType = signature.receiverType
        {
            var receiverArgument = loweredReceiverID
            if safeReceiverType != nonNullSafeReceiverType,
               case .primitive(_, .nonNull) = sema.types.kind(of: declaredReceiverType)
            {
                // The null branch has exited. ABI argument adaptation skips
                // the receiver slot, so expose this boundary as a typed copy
                // to unbox nullable primitives before calling their member.
                receiverArgument = arena.appendTemporary(type: declaredReceiverType)
                instructions.append(.copy(from: loweredReceiverID, to: receiverArgument))
            }
            if sema.symbols.isSourceBackedSymbol(chosen),
               sema.symbols.symbol(chosen)?.flags.contains(.inlineFunction) != true,
               case let .functionType(functionType) = sema.types.kind(of: declaredReceiverType),
               functionType.isSuspend {
                receiverArgument = materializeFunctionValueArgument(
                    loweredArgID: receiverArgument,
                    argExprID: receiverExpr,
                    functionType: functionType,
                    sema: sema, arena: arena, interner: interner,
                    instructions: &instructions.instructions
                )
            }
            finalArguments.insert(receiverArgument, at: 0)
        } else if chosen == nil {
            if Self.unresolvedCoroutineHandleMemberNames.contains(calleeStr), isCoroutineReceiver {
                finalArguments.insert(loweredReceiverID, at: 0)
            }
        }

        let dispatchReceiver = chosen.flatMap {
            memberExtensionDispatchReceiver(
                for: $0,
                callExprID: exprID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions.instructions
            )
        }
        if let dispatchReceiver {
            finalArguments.insert(dispatchReceiver, at: 0)
        }

        if let chosen,
           let localValue = driver.ctx.localValue(for: chosen),
           let callable = driver.ctx.callableValueInfo(for: localValue)
        {
            finalArguments.insert(contentsOf: callable.captureArguments, at: 0)
        }

        if let chosen {
            materializeSourceBackedFunctionValueArguments(
                chosenCallee: chosen,
                sourceArgExprs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions.instructions,
                arguments: &finalArguments,
                valueArgOffsetOverride: dispatchReceiver == nil ? nil : 2
            )
        }

        if tryEmitEnumEntryDispatchCall(
            hasOmittedDefaultArguments: safeNormalized.hasOmittedDefaultArguments,
            isSuperCall: isSuperCall,
            chosenCallee: chosen,
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: loweredReceiverID,
                                         typeOverride: nonNullSafeReceiverType),
            result: memberResult,
            sema: sema,
            interner: interner,
            arguments: finalArguments,
            instructions: &instructions.instructions
        ) {
            if memberResult != result {
                instructions.append(.copy(from: memberResult, to: result))
            }
            instructions.append(.label(endLabel))
            return result
        }

        // Safe-call collection fallback can resolve the source-backed
        // joinToString declaration without retaining its default-value flags.
        // In that case normalizedCallArguments leaves zero sentinels for the
        // omitted parameters, including the limit and truncation marker.
        // Recover the mask from the source call labels and materialize the
        // Kotlin defaults before emitting the direct source-backed call.
        let sourceBackedJoinToStringMask: Int64 = {
            guard calleeStr == "joinToString",
                  let chosen,
                  sema.symbols.isSourceBackedSymbol(chosen),
                  finalArguments.count >= 4,
                  !args.contains(where: { ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true })
            else {
                return 0
            }
            return joinToStringDefaultMask(sourceArguments: args, interner: interner)
        }()
        let joinToStringMask = safeNormalized.defaultMask | sourceBackedJoinToStringMask
        if joinToStringMask != 0,
           calleeStr == "joinToString",
           let chosen,
           sema.symbols.isSourceBackedSymbol(chosen),
           finalArguments.count >= 4
        {
            materializeJoinToStringDefaultArguments(
                joinToStringMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions.instructions,
                arguments: &finalArguments
            )
        }

        let safeDefaultStubOwner = chosen.map {
            driver.callSupportLowerer.defaultStubOwnerSymbol(for: $0, sema: sema, callBinding: callBinding)
        }
        if safeNormalized.hasOmittedDefaultArguments,
           let chosen,
           let stubOwner = safeDefaultStubOwner,
           (sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true ||
            sema.symbols.externalLinkName(for: driver.callSupportLowerer.defaultStubSymbol(for: stubOwner)) != nil)
        {
            // KUU-655: an override that inherits its defaults never has its
            // own stub; resolve to the base declaration's stub instead (see
            // `defaultStubOwnerSymbol`).
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions.instructions,
                arguments: &finalArguments
            )
            // KUU-655: see the matching comment in
            // `CallLowerer+MemberCallEmission.swift` -- a `super?.f()` call
            // that omits a defaulted argument must dispatch statically.
            var effectiveMasks = safeNormalized.defaultMaskWords
            if isSuperCall, !effectiveMasks.isEmpty {
                if effectiveMasks.count > 1 {
                    effectiveMasks[effectiveMasks.count - 1] = 1
                } else {
                    effectiveMasks[0] |= Int64(1) << DefaultArgumentMask.superCallMarkerBitIndex
                }
            }
            appendDefaultMaskArguments(
                effectiveMasks,
                sema: sema,
                arena: arena,
                instructions: &instructions.instructions,
                arguments: &finalArguments
            )
            let stubName = interner.intern(calleeStr + "$default")
            let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: stubOwner)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArguments,
                result: memberResult,
                canThrow: false,
                isSuperCall: isSuperCall
            ))
        } else {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions.instructions,
                arguments: &finalArguments
            )
            // Matches emitMemberCallInstruction's computation exactly
            // (CallLowerer+MemberCallEmission.swift) — isCollectionHOFLambdaExpr
            // is a narrow Sema-set flag (only a handful of HOF names opt in via
            // markDeferredCollectionHOFLambdaIfNeeded), not a general "is this
            // syntactically a lambda" check. loweredMemberCalleeName's dispatch
            // key must be computed the same way here as in the regular
            // (non-safe) path, or it can resolve to a mismatched runtime entry
            // point expecting a different argument shape.
            let hasHOFLambdaArg = args.contains { sema.bindings.isCollectionHOFLambdaExpr($0.expr) }
            var resolvedViaGeneralCollectionFallback = false
            let resolvedCalleeName: InternedString
            if let chosen,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               !externalLinkName.isEmpty
            {
                resolvedCalleeName = interner.intern(externalLinkName)
            } else if chosen == nil, isCoroutineReceiver {
                switch calleeStr {
                case "await":
                    resolvedCalleeName = interner.intern("kk_kxmini_async_await")
                case "join":
                    resolvedCalleeName = interner.intern("kk_job_join")
                case "awaitCompletion":
                    resolvedCalleeName = interner.intern("kk_job_await_completion")
                case "cancel":
                    resolvedCalleeName = args.isEmpty
                        // swiftlint:disable:next void_function_in_ternary
                        ? interner.intern("kk_job_cancel")
                        : interner.intern("kk_job_cancel_with_cause")
                case "complete":
                    resolvedCalleeName = interner.intern("kk_job_complete")
                case "completeExceptionally":
                    resolvedCalleeName = interner.intern("kk_job_complete_exceptionally")
                default:
                    // Not actually a coroutine-handle member (isCoroutineReceiver
                    // just means "non-primitive receiver") — e.g. a not-yet-
                    // migrated stdlib collection member like `sortedBy` reached
                    // through a safe-call chain (`x?.entries?.sortedBy { ... }`).
                    // Fall back to the same name-based collection/synthetic
                    // dispatch the regular (non-safe) member call path uses,
                    // instead of emitting the bare Kotlin name as an unresolved
                    // external symbol.
                    resolvedViaGeneralCollectionFallback = true
                    resolvedCalleeName = loweredMemberCalleeName(
                        chosenCallee: nil,
                        fallback: effectiveCalleeName,
                        receiverExpr: receiverExpr,
                        argumentCount: finalArguments.count,
                        sourceArgumentCount: args.count,
                        hasHOFLambdaArg: hasHOFLambdaArg,
                        sema: sema,
                        interner: interner
                    )
                }
            } else {
                resolvedCalleeName = effectiveCalleeName
            }
            // The chosen == nil branches above never insert the receiver
            // into finalArguments (mirroring the "when Sema failed to
            // resolve nextLong/nextInt on Random" gap already worked around
            // for Random.nextInt/nextLong in the regular, non-safe path).
            // Reuse the exact same shared helper the regular path calls
            // (appendReceiverToMemberArguments, CallLowerer+MemberCallEmission.swift)
            // instead of hand-rolling the insertion, so collection/coroutine/
            // channel/flow member names all get identical treatment here.
            if resolvedViaGeneralCollectionFallback {
                appendReceiverToMemberArguments(
                    loweredReceiverID,
                    receiverExpr: receiverExpr,
                    calleeName: effectiveCalleeName,
                    chosenCallee: chosen,
                    prependReceiverForUnresolvedCollectionCall: true,
                    sema: sema,
                    interner: interner,
                    arguments: &finalArguments
                )
            }
            let receiverTypeForDispatch = sema.bindings.exprTypes[receiverExpr]
                ?? arena.exprType(loweredReceiverID)
            let isRuntimeRangeReceiver = receiverTypeForDispatch.map { receiverType in
                MemberRuntimeDispatch.rangeReceiverKind(
                    receiverExpr: receiverExpr,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ) != nil
            } ?? false
            let hasExternalLink = chosen.map { kirIsRuntimeBridgedCallee($0, sema: sema) } ?? false
            let usesIteratorRuntimeVirtualBridge = chosen.map {
                isIteratorRuntimeVirtualBridge(
                    $0,
                    receiverTypeID: receiverTypeForDispatch,
                    sema: sema,
                    interner: interner
                )
            } ?? false
            let usesBoxedCollectionVirtualBridge = chosen.map {
                isRuntimeBoxedCollectionVirtualBridge(
                    $0,
                    receiverTypeID: receiverTypeForDispatch,
                    sema: sema,
                    interner: interner
                )
            } ?? false
            if !isSuperCall,
               !isRuntimeRangeReceiver,
               let chosen,
               (!hasExternalLink
                   || isClockRuntimeVirtualBridge(chosen, sema: sema)
                   || usesIteratorRuntimeVirtualBridge
                   || usesBoxedCollectionVirtualBridge),
               let dispatchKind = resolveVirtualDispatch(
                   callee: chosen,
                   receiverTypeID: dispatchReceiver.flatMap { arena.exprType($0) } ?? receiverTypeForDispatch,
                   sema: sema, interner: interner
               )
            {
                var vcArguments = finalArguments
                if let signature = sema.symbols.functionSignature(for: chosen),
                   signature.receiverType != nil,
                   !vcArguments.isEmpty
                {
                    vcArguments.removeFirst()
                }
                let virtualCalleeName = usesIteratorRuntimeVirtualBridge
                    ? (sema.symbols.symbol(chosen)?.name ?? resolvedCalleeName)
                    : resolvedCalleeName
                let virtualInstruction: KIRInstruction = .virtualCall(
                    symbol: chosen,
                    callee: virtualCalleeName,
                    receiver: dispatchReceiver ?? loweredReceiverID,
                    arguments: vcArguments,
                    result: memberResult,
                    // Boxed-collection bridges (`__kk_list_get` and friends)
                    // declare the outThrown channel in their ABI; the virtual
                    // call must append it so the looked-up implementation's
                    // exception path stays intact.
                    canThrow: usesBoxedCollectionVirtualBridge
                        && needsThrownChannel(calleeName: virtualCalleeName, interner: interner),
                    dispatch: dispatchKind
                )
                // KUU-763: floating-point range boxes carry no itable, so a
                // safe-call on an interface-typed range receiver probes the
                // runtime representation before dispatching.
                if let probeEndLabel = emitFloatingPointRangeMemberProbe(
                    chosenCallee: chosen,
                    receiverID: dispatchReceiver ?? loweredReceiverID,
                    sourceReceiverID: loweredReceiverID,
                    arguments: finalArguments,
                    result: memberResult,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) {
                    instructions.append(virtualInstruction)
                    instructions.append(.label(probeEndLabel))
                } else {
                    instructions.append(virtualInstruction)
                }
            } else {
                instructions.append(.call(
                    symbol: chosen,
                    callee: resolvedCalleeName,
                    arguments: finalArguments,
                    result: memberResult,
                    canThrow: false,
                    isSuperCall: isSuperCall
                ))
            }
        }
        if memberResult != result {
            instructions.append(.copy(from: memberResult, to: result))
        }
        instructions.append(.label(endLabel))
        return result
    }

    /// Whether a callee's external link name denotes a runtime bridge (a `kk_*`
    /// entry point taking the runtime's argument shape) rather than an ordinary
    /// Kotlin declaration. A declaration imported from a precompiled library
    /// also carries a link name — its own `kk_fn_*` mangled definition — so the
    /// link name, not the mere presence of one, decides.
    func kirIsRuntimeBridgedCallee(_ callee: SymbolID, sema: SemaModule) -> Bool {
        !Self.isSourceBackedLinkName(sema.symbols.externalLinkName(for: callee))
    }

    /// `Clock.now()` keeps a runtime bridge as its fallback for the
    /// compiler-created `TimeSource.asClock()` wrapper, but it is also a
    /// user-implementable interface member. Allow its bridge-backed
    /// declaration to use the normal itable path so a source override is not
    /// bypassed by a direct `kk_clock_now` call.
    func isClockRuntimeVirtualBridge(_ callee: SymbolID, sema: SemaModule) -> Bool {
        guard sema.symbols.externalLinkName(for: callee) == "kk_clock_now",
              let parentID = sema.symbols.parentSymbol(for: callee),
              sema.symbols.symbol(parentID)?.kind == .interface
        else { return false }
        return true
    }

    /// Iterator's runtime links also back the source-declared Iterator
    /// interface. A source-backed class receiver still needs its itable so an
    /// override such as CharSequenceCharIterator.hasNext() is not bypassed.
    /// Runtime collection iterator boxes keep the direct bridge because their
    /// static receiver type is the Iterator interface or a type parameter.
    func isIteratorRuntimeVirtualBridge(
        _ callee: SymbolID,
        receiverTypeID: TypeID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let linkName = sema.symbols.externalLinkName(for: callee),
              linkName == "kk_iterator_hasNext" || linkName == "kk_iterator_next",
              let parentID = sema.symbols.parentSymbol(for: callee),
              let parentSymbol = sema.symbols.symbol(parentID),
              parentSymbol.kind == .interface,
              parentSymbol.fqName.map(interner.resolve) == ["kotlin", "collections", "Iterator"],
              let receiverTypeID,
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverTypeID)),
              sema.symbols.symbol(receiverClassType.classSymbol)?.kind == .class
        else { return false }
        return true
    }

    /// Collection nominals whose own constructor is rewritten to a runtime box
    /// factory (`ArrayList()` → `__kk_array_list_of`, `HashSet()` →
    /// `__kk_hash_set_of`, `TreeMap()` → `__kk_tree_map_of`, and so on) produce
    /// `Runtime*Box` handles rather than `kk_object_new` objects, so a bridged
    /// member such as `ArrayList.get` (`__kk_list_get`) must keep its direct
    /// runtime call for receivers typed by those nominals. A source subclass
    /// of them — `class StringList : ArrayList<String>` — still allocates a
    /// real object and registers its vtable overrides at construction, so the
    /// same bridged member must dispatch through the inherited vtable slot to
    /// reach the override (KUU-3669). The receiver's own nominal layout is the
    /// membership oracle: only a class that actually inherits the callee's
    /// slot carries an object vtable entry for it.
    func isRuntimeBoxedCollectionVirtualBridge(
        _ callee: SymbolID,
        receiverTypeID: TypeID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard kirIsRuntimeBridgedCallee(callee, sema: sema),
              let receiverTypeID,
              let owner = sema.symbols.parentSymbol(for: callee),
              case let .classType(receiverClassType) = sema.types.kind(
                  of: sema.types.makeNonNullable(receiverTypeID)
              ),
              let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol),
              receiverSymbol.kind == .class,
              receiverClassType.classSymbol != owner,
              !isRuntimeBoxedCollectionNominal(
                  receiverClassType.classSymbol, sema: sema, interner: interner
              ),
              sema.symbols.nominalLayout(for: receiverClassType.classSymbol)?
                  .vtableSlots[callee] != nil
        else { return false }
        return true
    }

    /// Nominals whose construction produces a `Runtime*Box` handle instead of
    /// a `kk_object_new` object — `ArrayList`/`HashSet`/`TreeMap` and friends
    /// lower their constructors to `__kk_*_of` factories and `ArrayDeque`
    /// allocates a `RuntimeArrayDequeBox`. A vtable dispatch on one of those
    /// exact types reads a slot the box never registered, so their receivers
    /// stay on direct runtime calls; user-defined subclasses between them and
    /// the receiver are the `kk_object_new` objects that do carry the slot.
    private func isRuntimeBoxedCollectionNominal(
        _ classSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(classSymbol) else { return false }
        switch symbol.fqName.map(interner.resolve) {
        case ["kotlin", "collections", "ArrayList"],
             ["kotlin", "collections", "ArrayDeque"],
             ["kotlin", "collections", "HashSet"],
             ["kotlin", "collections", "LinkedHashSet"],
             ["kotlin", "collections", "HashMap"],
             ["kotlin", "collections", "LinkedHashMap"],
             ["java", "util", "TreeSet"],
             ["java", "util", "TreeMap"]:
            return true
        default:
            return false
        }
    }

    /// Thin wrapper over the free `resolveVirtualDispatchKind` (below, outside
    /// this extension) so existing `CallLowerer`-qualified call sites (and the
    /// unit tests that exercise this by name) are unaffected; the free function
    /// exists so lowering passes without a `CallLowerer` instance -- e.g.
    /// `ConsolePrintLoweringPass`, which runs on already-built KIR well after
    /// the originating driver/CallLowerer have gone out of scope -- can reuse
    /// the exact same dispatch-kind resolution instead of hand-rolling a
    /// (potentially divergent) direct-call-only rewrite.
    func resolveVirtualDispatch(
        callee: SymbolID,
        receiverTypeID: TypeID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> KIRDispatchKind? {
        resolveVirtualDispatchKind(callee: callee, receiverTypeID: receiverTypeID, sema: sema, interner: interner)
    }
}

/// Returns `.vtable(slot:)` for class methods or `.itable(slot:)` for interface methods,
/// or `nil` if the call should use direct (static) dispatch.
///
/// A free function (not a `CallLowerer` member) so both BuildKIR-time callers
/// (via `CallLowerer.resolveVirtualDispatch` above) and later, driver-less
/// lowering passes can resolve the same dispatch kind for a callee symbol.
func resolveVirtualDispatchKind(
    callee: SymbolID,
    receiverTypeID: TypeID?,
    sema: SemaModule,
    interner: StringInterner
) -> KIRDispatchKind? {
    guard let calleeSymbol = sema.symbols.symbol(callee),
          calleeSymbol.kind == .function
    else { return nil }
    // Bundled top-level extensions can be parented by their receiver nominal
    // for lookup, but remain static calls. Use the semantic receiver/owner
    // relationship so regular interface and class members keep virtual dispatch.
    if TypeCheckHelpers().declaresExtensionReceiver(callee, sema: sema, interner: interner),
       sema.symbols.memberExtensionOwnerSymbol(for: callee) == nil
    {
        return nil
    }
    // Private members cannot be overridden and are omitted from a user
    // library's exported dispatch metadata. Their own bodies must call them
    // directly even when the enclosing class has known subclasses.
    guard calleeSymbol.visibility != .private else { return nil }
    // Range/progression receivers are RuntimeRangeBox handles without a
    // Kotlin vtable/itable — dispatching a member virtually on them crashes
    // at kk_vtable_lookup (KSWIFTK-RUNTIME-0001). Their member calls always
    // use direct dispatch.
    if let receiverTypeID,
       MemberRuntimeDispatch.rangeReceiverKind(for: receiverTypeID, sema: sema, interner: interner) != nil
    {
        return nil
    }
    guard let parentID = sema.symbols.parentSymbol(for: callee),
          let parentSymbol = sema.symbols.symbol(parentID)
    else { return nil }
    // Members declared on a range/progression class are only ever invoked on
    // RuntimeRangeBox handles — the constructors are internal, so no
    // vtable-carrying subclass exists. Keep them on direct dispatch even when
    // the receiver's static type lost the nominal (e.g. ClosedRange<Long>).
    if parentSymbol.kind == .class,
       MemberRuntimeDispatch.rangeReceiverKind(forClassSymbol: parentSymbol, interner: interner) != nil
    {
        return nil
    }
    // An extension accessor is parented by its property; dispatch on the
    // property's enclosing class, using its synthetic getter/setter slot.
    if parentSymbol.kind == .property,
       parentSymbol.flags.contains(.memberExtension),
       let owner = sema.symbols.parentSymbol(for: parentID),
       sema.symbols.symbol(owner)?.kind == .class,
       sema.symbols.symbol(owner)?.flags.contains(.abstractType) == true
           || !sema.symbols.directSubtypes(of: owner).isEmpty,
       let ownerLayout = sema.symbols.nominalLayout(for: owner)
    {
        let kind: PropertyAccessorKind = sema.symbols.extensionPropertySetterAccessor(for: parentID) == callee
            ? .setter : .getter
        let slotSymbol = SyntheticSymbolScheme.propertyAccessorSymbol(for: parentID, kind: kind)
        return ownerLayout.vtableSlots[slotSymbol].map { .vtable(slot: $0) }
    }
    guard let layout = sema.symbols.nominalLayout(for: parentID) else { return nil }
    if parentSymbol.kind == .interface {
        return resolveItableDispatchKind(
            callee: callee, parentID: parentID, layout: layout,
            receiverTypeID: receiverTypeID, sema: sema, interner: interner
        )
    }
    if parentSymbol.kind == .class {
        // Final internal helpers are also absent from exported dispatch
        // metadata. Open/abstract/non-final override members still need the
        // implementation selected from the concrete receiver.
        let isOverridable = !calleeSymbol.flags.contains(.finalMember)
            && !calleeSymbol.flags.intersection([.openType, .abstractType, .overrideMember]).isEmpty
        guard calleeSymbol.visibility != .internal || isOverridable else { return nil }
        // KSP-1281: members of the range/progression classes are never
        // vtable-dispatchable. Their values are runtime `RuntimeRangeBox`
        // handles, not heap objects carrying a KTypeInfo vtable, so
        // `kk_vtable_lookup` traps on the receiver. The paired Range classes
        // are `final` and the progressions have `internal` constructors, so
        // no user subtype can ever materialize as a real object — the only
        // subtype a progression can gain (e.g. `UIntRange : UIntProgression`)
        // is box-backed itself. Direct calls to the resolved source member
        // lower through the `__kk_range_*` handle bridges and are correct.
        if isRuntimeRangeBoxNominal(parentSymbol, interner: interner) { return nil }
        return resolveVtableDispatchKind(callee: callee, parentID: parentID, layout: layout, sema: sema)
    }
    return nil
}

/// Whether `symbol` is one of the `kotlin.ranges` progression/range classes
/// whose values the runtime represents as `RuntimeRangeBox` handles rather
/// than real heap objects — a `vtable` dispatch on such an owner can never
/// resolve a slot (`kk_vtable_lookup` traps on the raw handle).
private func isRuntimeRangeBoxNominal(_ symbol: SemanticSymbol, interner: StringInterner) -> Bool {
    let fqName = symbol.fqName
    guard fqName.count == 3,
          fqName[0] == interner.intern("kotlin"),
          fqName[1] == interner.intern("ranges")
    else { return false }
    switch interner.resolve(fqName[2]) {
    case "IntRange", "LongRange", "CharRange", "UIntRange", "ULongRange",
         "IntProgression", "LongProgression", "CharProgression",
         "UIntProgression", "ULongProgression":
        return true
    default:
        return false
    }
}

private func resolveItableDispatchKind(
    callee: SymbolID,
    parentID: SymbolID,
    layout: NominalLayout,
    receiverTypeID: TypeID?,
    sema: SemaModule,
    interner: StringInterner
) -> KIRDispatchKind? {
    guard let receiverTypeID,
          let methodSlot = layout.vtableSlots[callee]
    else { return nil }

    func containsNominalSubtype(
        _ type: TypeID,
        of owner: SymbolID,
        visitedTypeParameters: Set<SymbolID> = []
    ) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case let .classType(classType):
            return sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: owner)
        case let .intersection(parts):
            return parts.contains {
                containsNominalSubtype($0, of: owner, visitedTypeParameters: visitedTypeParameters)
            }
        case let .typeParam(typeParameter):
            if let capture = typeParameter.capture {
                return containsNominalSubtype(
                    capture.upper,
                    of: owner,
                    visitedTypeParameters: visitedTypeParameters
                )
            }
            guard !visitedTypeParameters.contains(typeParameter.symbol) else { return false }
            let visited = visitedTypeParameters.union([typeParameter.symbol])
            return sema.symbols.typeParameterUpperBounds(for: typeParameter.symbol).contains {
                containsNominalSubtype($0, of: owner, visitedTypeParameters: visited)
            }
        default:
            return false
        }
    }

    let nonNullReceiverType = sema.types.makeNonNullable(receiverTypeID)
    switch sema.types.kind(of: nonNullReceiverType) {
    case let .classType(classType):
        let receiverClassSymID = classType.classSymbol
        guard let receiverClassSym = sema.symbols.symbol(receiverClassSymID) else { return nil }

        if receiverClassSym.kind == .class {
            let hasSubtypes = !sema.symbols.directSubtypes(of: receiverClassSymID).isEmpty
            let needsAbstractInterfaceDispatch = sema.symbols.symbol(callee)?.flags.contains(.abstractType) == true
            // If the receiver is a concrete class with no subtypes, use direct
            // dispatch when the selected method has a concrete body. An
            // abstract interface declaration still needs the implementing
            // class's itable, even when this final class cannot have subtypes.
            guard hasSubtypes || needsAbstractInterfaceDispatch,
                  let receiverLayout = sema.symbols.nominalLayout(for: receiverClassSymID)
            else { return nil }
            let interfaceSlot: Int
            if let registeredSlot = receiverLayout.itableSlots[parentID] {
                interfaceSlot = registeredSlot
            } else if hasSubtypes {
                // Preserve the established fallback for a class whose subtype
                // metadata is incomplete in this compilation unit.
                interfaceSlot = 0
            } else {
                return nil
            }
            return .itable(interfaceSlot: interfaceSlot, methodSlot: methodSlot)
        }

        // The receiver's static type is the interface itself (e.g. a function
        // parameter typed `d: Describable`) — the concrete implementing class,
        // and therefore the itable slot that class assigned to this interface,
        // is unknown at this call site. Falling back to slot 0 here previously
        // dispatched to whatever interface happened to occupy slot 0 on the
        // object actually passed in (e.g. Printable instead of Describable).
        // Defer the slot lookup to runtime instead, keyed by the interface's
        // stable type ID (see kk_itable_lookup_dynamic).
        if receiverClassSym.kind == .interface {
            let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: parentID, sema: sema, interner: interner
            )
            return .itableDynamic(interfaceTypeID: interfaceTypeID, methodSlot: methodSlot)
        }
    case .typeParam:
        // A generic receiver (e.g. `T : AutoCloseable` in `AutoCloseable.use`)
        // has an unknown concrete class at compile time, so the interface
        // itable must be resolved dynamically at runtime.
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: parentID, sema: sema, interner: interner
        )
        return .itableDynamic(interfaceTypeID: interfaceTypeID, methodSlot: methodSlot)
    case .intersection:
        // A smart-cast intersection can prove the member's interface through any
        // one of its conjuncts, but the concrete runtime class is still unknown.
        // Dispatch through the declaring interface's itable just like a direct
        // interface or bounded type-parameter receiver.
        guard containsNominalSubtype(nonNullReceiverType, of: parentID) else { return nil }
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: parentID, sema: sema, interner: interner
        )
        return .itableDynamic(interfaceTypeID: interfaceTypeID, methodSlot: methodSlot)
    default:
        break
    }
    return nil
}

private func resolveVtableDispatchKind(
    callee: SymbolID,
    parentID: SymbolID,
    layout: NominalLayout,
    sema: SemaModule
) -> KIRDispatchKind? {
    // Open and abstract classes can acquire subtypes in a later compilation
    // unit. Their method bodies must retain virtual dispatch when a library
    // is compiled in isolation, even without currently known subtypes.
    //
    // Compiler-created objects register their concrete vtable slot methods at
    // allocation time, mirroring the existing itable method registry.  Raw
    // kk_alloc-backed objects can still use KTypeInfo vtables via the runtime
    // lookup fallback.
    let subtypes = sema.symbols.directSubtypes(of: parentID)
    let flags = sema.symbols.symbol(parentID)?.flags ?? []
    guard !subtypes.isEmpty || flags.contains(.abstractType) || flags.contains(.openType) else { return nil }
    return layout.vtableSlots[callee].map { .vtable(slot: $0) }
}
