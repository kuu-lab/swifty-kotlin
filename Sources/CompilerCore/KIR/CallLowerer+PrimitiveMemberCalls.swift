// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallLowerer {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func tryLowerPrimitiveMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        requireNonNullableReceiverForConstFold: Bool,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // Primitive member function: Int/Long.inv() → kk_op_inv (P5-103)
        if calleeName == interner.intern("inv"),
           args.isEmpty,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_inv"),
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions
        // NOTE: This bit-count lowering logic is intentionally duplicated in
        // CallLowerer+SafeMemberCalls.swift for the safe-call (?.) path.
        // If you change the callee-name -> runtime-name mapping here, update
        // the other file as well. Consider extracting a shared helper if the
        // number of bit-operation intrinsics grows further.
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "countOneBits" || calleeStr == "countLeadingZeroBits" || calleeStr == "countTrailingZeroBits" ||
               calleeStr == "highestOneBit" || calleeStr == "lowestOneBit" || calleeStr == "takeHighestOneBit" || calleeStr == "takeLowestOneBit" {
                let intType = sema.types.intType
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if nonNullReceiverType == intType {
                    let runtimeName: String
                    switch calleeStr {
                    case "countOneBits": runtimeName = "kk_int_countOneBits"
                    case "countLeadingZeroBits": runtimeName = "kk_int_countLeadingZeroBits"
                    case "countTrailingZeroBits": runtimeName = "kk_int_countTrailingZeroBits"
                    case "highestOneBit": runtimeName = "kk_int_highestOneBit"
                    case "lowestOneBit": runtimeName = "kk_int_lowestOneBit"
                    case "takeHighestOneBit": runtimeName = "kk_int_takeHighestOneBit"
                    case "takeLowestOneBit": runtimeName = "kk_int_takeLowestOneBit"
                    default: fatalError("unreachable: calleeStr already guarded to bit operation functions")
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Int.rotateLeft() / rotateRight() (STDLIB-BIT-007)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "rotateLeft" || calleeStr == "rotateRight" {
                let intType = sema.types.intType
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if nonNullReceiverType == intType {
                    let runtimeName: String
                    switch calleeStr {
                    case "rotateLeft": runtimeName = "kk_int_rotateLeft"
                    case "rotateRight": runtimeName = "kk_int_rotateRight"
                    default: fatalError("unreachable: calleeStr already guarded to rotate functions")
                    }
                    let loweredArgID = driver.lowerExpr(
                        args[0].expr,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeName),
                        arguments: [loweredReceiverID, loweredArgID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Long bit manipulation functions (STDLIB-BIT-007)
        let longType = sema.types.longType
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)

        if nonNullReceiverType == longType {
            let calleeStr = interner.resolve(calleeName)

            // Zero-argument functions
            if args.isEmpty {
                let runtimeName: String?
                switch calleeStr {
                case "highestOneBit": runtimeName = "kk_long_highestOneBit"
                case "lowestOneBit": runtimeName = "kk_long_lowestOneBit"
                case "takeHighestOneBit": runtimeName = "kk_long_takeHighestOneBit"
                case "takeLowestOneBit": runtimeName = "kk_long_takeLowestOneBit"
                default: runtimeName = nil
                }

                if let name = runtimeName {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(name),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }

            // Single-argument functions (rotate)
            if args.count == 1 {
                let runtimeName: String?
                switch calleeStr {
                case "rotateLeft": runtimeName = "kk_long_rotateLeft"
                case "rotateRight": runtimeName = "kk_long_rotateRight"
                default: runtimeName = nil
                }

                if let name = runtimeName {
                    let loweredArgID = driver.lowerExpr(
                        args[0].expr,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(name),
                        arguments: [loweredReceiverID, loweredArgID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Boolean.not() → kk_op_not (STDLIB-308)
        if calleeName == interner.intern("not"),
           args.isEmpty
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_not"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                let boolCallee: InternedString? = switch interner.resolve(calleeName) {
                case "and":
                    interner.intern("kk_bitwise_and")
                case "or":
                    interner.intern("kk_bitwise_or")
                case "xor":
                    interner.intern("kk_bitwise_xor")
                default:
                    nil
                }
                if let boolCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: boolCallee,
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Float.mod(other) / Double.mod(other): Kotlin mod uses floor-style
        // modulo, while rem/% use truncating remainder.
        if args.count == 1,
           interner.resolve(calleeName) == "mod"
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
                var lhs = loweredReceiverID
                var rhs = loweredArgIDs[0]
                if resultType == doubleType {
                    if nonNullReceiverType == floatType {
                        let converted = arena.appendTemporary(type: doubleType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_float_to_double_bits"),
                            arguments: [lhs],
                            result: converted,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        lhs = converted
                    }
                    if nonNullRhsType == floatType {
                        let converted = arena.appendTemporary(type: doubleType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_float_to_double_bits"),
                            arguments: [rhs],
                            result: converted,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        rhs = converted
                    }
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(resultType == doubleType ? "kk_op_dfloor_mod" : "kk_op_ffloor_mod"),
                    arguments: [lhs, rhs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Primitive arithmetic/infix member functions on numeric receivers.
        if args.count == 1,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let rawRhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rawRhsType)
            let isShiftReceiver = nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
            let isUnsignedReceiver = nonNullReceiverType == uintType || nonNullReceiverType == ulongType || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
            let primitiveCallee: InternedString? = switch interner.resolve(calleeName) {
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
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_and") : nil
            case "or":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_or") : nil
            case "xor":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_xor") : nil
            case "shl":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shl") : nil
            case "shr":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shr") : nil
            case "ushr":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_ushr") : nil
            default:
                nil
            }
            if let primitiveCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: primitiveCallee,
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Int/Long/Byte/Short/UByte/UShort/UInt/ULong.coerceIn(min, max) (STDLIB-150, STDLIB-500)
        if interner.resolve(calleeName) == "coerceIn", args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(prefix + "_coerceIn"),
                    arguments: [loweredReceiverID, loweredArgIDs[0], loweredArgIDs[1]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Int/Long/UInt/ULong.coerceIn(range) — single ClosedRange argument (STDLIB-525, STDLIB-CONV-006)
        // Decompose the range into first/last and delegate to kk_{int,long,uint,ulong}_coerceIn.
        // The shared emitCoerceInRange helper types the extracted bounds as the non-nullable
        // receiver type and kk_range_first/kk_range_last return the range's element type.
        if interner.resolve(calleeName) == "coerceIn", args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let intType = sema.types.intType
            let longType = sema.types.longType
            let uintType = sema.types.uintType
            let ulongType = sema.types.ulongType
            let supportsRangeCoercion = receiverType == intType || receiverType == longType
                || receiverType == uintType || receiverType == ulongType
            if supportsRangeCoercion,
               let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                let argExprID = args[0].expr
                let argType = sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
                if sema.bindings.isRangeExpr(argExprID)
                    || nominalRangeElementType(for: argType, sema: sema, interner: interner) != nil
                {
                    emitCoerceInRange(
                        prefix: prefix,
                        receiverType: receiverType,
                        loweredReceiverID: loweredReceiverID,
                        loweredRangeArgID: loweredArgIDs[0],
                        result: result,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return result
                }
            }
        }

        // Int/Long/Double/Float/Byte/Short/UByte/UShort/UInt/ULong.coerceAtLeast(min)
        // / coerceAtMost(max) (STDLIB-150, STDLIB-500)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "coerceAtLeast" || calleeStr == "coerceAtMost" {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if let prefix = numericCoercionRuntimePrefix(receiverType: receiverType, sema: sema) {
                    // Check if this is range-based coercion (single range argument)
                    if args.count == 1 {
                        let argExprID = args[0].expr
                        if sema.bindings.isRangeExpr(argExprID) {
                            // Use range-based coercion functions
                            let suffix = calleeStr == "coerceAtLeast" ? "_coerceAtLeast_range" : "_coerceAtMost_range"
                            instructions.append(.call(
                                symbol: nil,
                                callee: interner.intern(prefix + suffix),
                                arguments: [loweredReceiverID, loweredArgIDs[0]],
                                result: result,
                                canThrow: false,
                                thrownResult: nil
                            ))
                            return result
                        }
                    }
                    // Fallback to single-value coercion
                    let suffix = calleeStr == "coerceAtLeast" ? "_coerceAtLeast" : "_coerceAtMost"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(prefix + suffix),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Primitive member function: Int/Long.toString() → kk_any_to_string
        // and Int/Long.toString(radix: Int) → kk_int_toString_radix (EXPR-003)
        if calleeName == interner.intern("toString"),
           args.count <= 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                if args.isEmpty {
                    let tagID = arena.appendExpr(.intLiteral(1), type: intType)
                    instructions.append(.constValue(result: tagID, value: .intLiteral(1)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_any_to_string"),
                        arguments: [loweredReceiverID, tagID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_int_toString_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return result
            }
        }

        let anyFallbackReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullAnyFallbackReceiverType = sema.types.makeNonNullable(anyFallbackReceiverType)
        let allowsAnyFallback: Bool = switch sema.types.kind(of: nonNullAnyFallbackReceiverType) {
        case .primitive(.string, _):
            false
        case .primitive:
            true
        case .typeParam:
            // All type parameters have an implicit upper bound of Any? in Kotlin,
            // so Any methods (toString, hashCode, equals) are always available on
            // type parameter receivers (STDLIB-GEN-055).
            true
        default:
            nonNullAnyFallbackReceiverType == sema.types.anyType
        }
        // Any.toString(): String — no-arg fallback via kk_any_to_string (STDLIB-306)
        if args.isEmpty, interner.resolve(calleeName) == "toString", allowsAnyFallback {
            let tag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
            instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [loweredReceiverID, tagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Any.hashCode(): Int — via kk_any_hashCode (STDLIB-306)
        if args.isEmpty, interner.resolve(calleeName) == "hashCode", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_hashCode"),
                arguments: [loweredReceiverID, receiverTagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Any.equals(other: Any?): Boolean — via kk_any_equals (STDLIB-306)
        if args.count == 1, interner.resolve(calleeName) == "equals", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let argType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let argTag = anyFallbackTag(for: argType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
            instructions.append(.constValue(result: argTagID, value: .intLiteral(argTag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_equals"),
                arguments: [loweredReceiverID, receiverTagID, loweredArgIDs[0], argTagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong(),
        // toFloat(), toByte(), toShort() (TYPE-005)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let charType = sema.types.charType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            let calleeStr = interner.resolve(calleeName)
            let conversionCallee: InternedString? = switch (calleeStr, nonNullReceiverType, nonNullResultType) {
            case ("toInt", uintType, intType): interner.intern("kk_uint_to_int")
            case ("toInt", ulongType, intType): interner.intern("kk_ulong_to_int")
            case ("toInt", ubyteType, intType): interner.intern("kk_ubyte_to_int")
            case ("toInt", ushortType, intType): interner.intern("kk_ushort_to_int")
            case ("toInt", doubleType, intType): interner.intern("kk_double_to_int")
            case ("toInt", floatType, intType): interner.intern("kk_float_to_int")
            case ("toInt", longType, intType): interner.intern("kk_long_to_int")
            case ("toInt", charType, intType): nil // identity (Char is stored as Int)
            case ("toInt", intType, intType): nil // identity
            case ("toChar", intType, charType): interner.intern("kk_int_to_char")
            case ("toUInt", intType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", longType, uintType): interner.intern("kk_long_to_uint")
            case ("toUInt", ubyteType, uintType): interner.intern("kk_ubyte_to_uint")
            case ("toUInt", ushortType, uintType): interner.intern("kk_ushort_to_uint")
            case ("toUInt", charType, uintType): interner.intern("kk_char_to_uint")
            case ("toUInt", uintType, uintType), ("toUInt", ulongType, uintType): nil // identity
            case ("toLong", intType, longType): interner.intern("kk_int_to_long")
            case ("toLong", uintType, longType): interner.intern("kk_uint_to_long")
            case ("toLong", ubyteType, longType): interner.intern("kk_ubyte_to_long")
            case ("toLong", ushortType, longType): interner.intern("kk_ushort_to_long")
            case ("toLong", doubleType, longType): interner.intern("kk_double_to_long")
            case ("toLong", floatType, longType): interner.intern("kk_float_to_long")
            case ("toLong", charType, longType): interner.intern("kk_char_to_long")
            case ("toLong", longType, longType), ("toLong", ulongType, longType): nil // identity
            case ("toULong", intType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", longType, ulongType): interner.intern("kk_long_to_ulong")
            case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
            case ("toULong", ubyteType, ulongType): interner.intern("kk_ubyte_to_ulong")
            case ("toULong", ushortType, ulongType): interner.intern("kk_ushort_to_ulong")
            case ("toULong", charType, ulongType): interner.intern("kk_char_to_ulong")
            case ("toULong", ulongType, ulongType): nil // identity
            case ("toFloat", intType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", longType, floatType): interner.intern("kk_long_to_float")
            case ("toFloat", doubleType, floatType): interner.intern("kk_double_to_float")
            case ("toFloat", floatType, floatType): nil // identity
            case ("toFloat", uintType, floatType): interner.intern("kk_uint_to_float")
            case ("toFloat", ulongType, floatType): interner.intern("kk_ulong_to_float")
            case ("toFloat", ubyteType, floatType): interner.intern("kk_ubyte_to_float")
            case ("toFloat", ushortType, floatType): interner.intern("kk_ushort_to_float")
            case ("toDouble", intType, doubleType): interner.intern("kk_int_to_double_bits")
            case ("toDouble", longType, doubleType): interner.intern("kk_long_to_double")
            case ("toDouble", floatType, doubleType): interner.intern("kk_float_to_double_bits")
            case ("toDouble", doubleType, doubleType): nil // identity
            case ("toDouble", uintType, doubleType): interner.intern("kk_uint_to_double")
            case ("toDouble", ulongType, doubleType): interner.intern("kk_ulong_to_double")
            case ("toDouble", ubyteType, doubleType): interner.intern("kk_ubyte_to_double")
            case ("toDouble", ushortType, doubleType): interner.intern("kk_ushort_to_double")
            case ("toByte", intType, intType): interner.intern("kk_int_to_byte")
            case ("toByte", longType, intType): interner.intern("kk_long_to_byte")
            case ("toByte", uintType, intType): interner.intern("kk_uint_to_byte")
            case ("toByte", ulongType, intType): interner.intern("kk_ulong_to_byte")
            case ("toByte", ubyteType, intType): interner.intern("kk_ubyte_to_byte")
            case ("toByte", ushortType, intType): interner.intern("kk_ushort_to_byte")
            case ("toShort", intType, intType): interner.intern("kk_int_to_short")
            case ("toShort", longType, intType): interner.intern("kk_long_to_short")
            case ("toShort", uintType, intType): interner.intern("kk_uint_to_short")
            case ("toShort", ulongType, intType): interner.intern("kk_ulong_to_short")
            case ("toShort", ubyteType, intType): interner.intern("kk_ubyte_to_short")
            case ("toShort", ushortType, intType): interner.intern("kk_ushort_to_short")
            case ("toUByte", intType, ubyteType): interner.intern("kk_int_to_ubyte")
            case ("toUByte", longType, ubyteType): interner.intern("kk_long_to_ubyte")
            case ("toUByte", uintType, ubyteType): interner.intern("kk_uint_to_ubyte")
            case ("toUByte", ulongType, ubyteType): interner.intern("kk_ulong_to_ubyte")
            case ("toUByte", ubyteType, ubyteType): nil // identity
            case ("toUByte", ushortType, ubyteType): interner.intern("kk_ushort_to_ubyte")
            case ("toUShort", intType, ushortType): interner.intern("kk_int_to_ushort")
            case ("toUShort", longType, ushortType): interner.intern("kk_long_to_ushort")
            case ("toUShort", uintType, ushortType): interner.intern("kk_uint_to_ushort")
            case ("toUShort", ulongType, ushortType): interner.intern("kk_ulong_to_ushort")
            case ("toUShort", ubyteType, ushortType): interner.intern("kk_ubyte_to_ushort")
            case ("toUShort", ushortType, ushortType): nil // identity
            case ("toChar", longType, charType): interner.intern("kk_long_to_char")
            case ("toChar", uintType, charType): interner.intern("kk_uint_to_char")
            case ("toChar", ulongType, charType): interner.intern("kk_ulong_to_char")
            case ("toChar", ubyteType, charType): interner.intern("kk_ubyte_to_char")
            case ("toChar", ushortType, charType): interner.intern("kk_ushort_to_char")
            case ("toChar", charType, charType): nil // identity
            default: nil
            }
            if let callee = conversionCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: callee,
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let isRepresentationPreservingConversion =
                (calleeStr == "toLong" && nonNullReceiverType == ulongType && nonNullResultType == longType)
                    || (calleeStr == "toUInt" && nonNullReceiverType == ulongType && nonNullResultType == uintType)
                    || (calleeStr == "toULong" && nonNullReceiverType == longType && nonNullResultType == ulongType)
                    || (calleeStr == "toInt" && nonNullReceiverType == charType && nonNullResultType == intType)
            if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toUByte", "toUShort", "toChar"].contains(calleeStr),
               nonNullReceiverType == nonNullResultType || isRepresentationPreservingConversion,
               nonNullReceiverType == intType || nonNullReceiverType == longType
               || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
               || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
               || nonNullReceiverType == floatType || nonNullReceiverType == doubleType
               || nonNullReceiverType == charType
            {
                instructions.append(.copy(from: loweredReceiverID, to: result))
                return result
            }
        }

        return nil
    }
}
