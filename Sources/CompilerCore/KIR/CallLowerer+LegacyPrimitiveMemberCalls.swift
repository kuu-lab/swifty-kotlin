extension CallLowerer {

    func lowerLegacyPrimitiveMemberOperatorCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        calleeNameStr: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        chosenCalleeForArgumentAdaptation: SymbolID?,
        requireNonNullableReceiverForConstFold: Bool,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if calleeName == interner.intern("inv"),
           args.isEmpty,
           sema.bindings.callBinding(for: exprID) == nil,
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

        // KSP-642: Int/Long rotateLeft / rotateRight are lowered as ordinary calls to
        // the bundled Kotlin declarations in `Stdlib/kotlin/Numbers.kt`.

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

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                let boolCallee: InternedString? = switch calleeNameStr {
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
           calleeNameStr == "mod"
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
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: doubleType)
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_float_to_double_bits"),
                            arg: lhs,
                            result: converted,
                            into: &instructions
                        )
                        lhs = converted
                    }
                    if nonNullRhsType == floatType {
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: doubleType)
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_float_to_double_bits"),
                            arg: rhs,
                            result: converted,
                            into: &instructions
                        )
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

        let isSourceArithmeticExtension = explicitFloatingOrCharArithmeticOp(calleeNameStr) != nil
            && chosenCalleeForArgumentAdaptation.map {
                sema.symbols.isSourceBackedSymbol($0)
                    && sema.symbols.functionSignature(for: $0)?.receiverType != nil
            } == true
        if !isSourceArithmeticExtension,
           calleeNameStr == "plus", args.count == 1,
           sema.types.makeNonNullable(sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType) == sema.types.charType,
           sema.bindings.exprTypes[args[0].expr] == sema.types.stringType
        {
            let receiverString = emitAnyToStringWithNullGuard(
                valueID: loweredReceiverID, valueType: sema.types.charType,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            instructions.append(.call(
                symbol: nil, callee: interner.intern("__kk_string_concat_flat"),
                arguments: [receiverString, loweredArgIDs[0]], result: result,
                canThrow: false, thrownResult: nil
            ))
            return result
        }

        // Explicit `Char.plus/minus` and `Float`/`Double` arithmetic member calls
        // behave exactly like the operator syntax, so emit the same `.binary` node
        // and let the operator/narrowing passes type it. The integer-receiver fast
        // path below only knows `kk_op_*` on integral slots.
        if !isSourceArithmeticExtension, args.count == 1,
           let binaryOp = explicitFloatingOrCharArithmeticOp(calleeNameStr),
           isNumericPrimitiveOperand(args[0].expr, sema: sema),
           !(sema.bindings.isRangeExpr(receiverExpr) || ControlFlowTypeChecker.isRangeExpression(receiverExpr, ast: ast))
        {
            let receiverType = sema.types.makeNonNullable(sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType)
            if receiverType == sema.types.charType
                || receiverType == sema.types.floatType
                || receiverType == sema.types.doubleType
            {
                instructions.append(.binary(op: binaryOp, lhs: loweredReceiverID, rhs: loweredArgIDs[0], result: result))
                return result
            }
        }

        // Direct range expressions are typed with their scalar element type, but
        // `plus`/`minus` must keep the selected Iterable extension at this stage.
        let isRangePlusMinusReceiver = ["plus", "minus"].contains(calleeNameStr)
            && (sema.bindings.isRangeExpr(receiverExpr)
                || ControlFlowTypeChecker.isRangeExpression(receiverExpr, ast: ast))
        if !isSourceArithmeticExtension, args.count == 1,
           !isRangePlusMinusReceiver,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold),
           isNumericPrimitiveOperand(args[0].expr, sema: sema)
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
            let isBitwiseReceiver = isShiftReceiver || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
            let isUnsignedReceiver = sema.types.isUnsigned(nonNullReceiverType)
            let primitiveCallee: InternedString? = switch calleeNameStr {
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
        return nil
    }

    func lowerLegacyIntLongToStringCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // Int/Long.toString(radix: Int) is bundled Kotlin source
        // (Stdlib/kotlin/text/StringNumberConversions.kt, KSP-717) and falls
        // through to the normal resolved-symbol call lowering below.
        if calleeName == interner.intern("toString"),
           args.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                let stringReceiverID: KIRExprID
                if nonNullReceiverType == longType {
                    // kk_any_to_string treats the raw null sentinel as null.
                    // Long.MIN_VALUE has the same representation, so box a
                    // Long receiver before generic stringification; the
                    // non-null variant preserves the value at that boundary.
                    stringReceiverID = boxValueForAnySlot(
                        loweredReceiverID,
                        sourceType: receiverType,
                        types: sema.types,
                        symbols: sema.symbols,
                        interner: interner,
                        arena: arena,
                        resultType: sema.types.anyType,
                        requireNonNull: sema.types.nullability(of: receiverType) == .nonNull,
                        sema: sema,
                        into: &instructions
                    )
                } else {
                    stringReceiverID = loweredReceiverID
                }
                let tagID = arena.appendExpr(.intLiteral(1), type: intType)
                instructions.append(.constValue(result: tagID, value: .intLiteral(1)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_any_to_string"),
                    arguments: [stringReceiverID, tagID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        return nil
    }

    func lowerLegacyPrimitiveConversionCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let byteType = sema.types.byteType
            let shortType = sema.types.shortType
            let charType = sema.types.charType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let rawNonNullReceiverType = sema.types.makeNonNullable(receiverType)
            // A smartcast intersection (`Interface & Char`) keeps the
            // primitive as one part; resolve to it so the conversion table
            // sees the concrete primitive receiver type.
            let nonNullReceiverType = smartcastNarrowedPrimitiveType(of: rawNonNullReceiverType, sema: sema)
                ?? rawNonNullReceiverType
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            // The lowered receiver can still carry its erased/boxed
            // representation (an `Any` slot holds e.g. a RuntimeCharBox
            // after `x is Char`) while the bound type names a non-null
            // primitive. Materialize the raw value so conversion callees —
            // and the identity `.copy` below, which ABI lowering would
            // otherwise map to the *result* type's unboxer — consume the
            // primitive payload, not the box handle.
            let conversionReceiverID = materializePrimitiveValue(
                loweredReceiverID, toType: nonNullReceiverType, sema: sema,
                arena: arena, instructions: &instructions
            ) ?? loweredReceiverID
            let calleeStr = calleeNameStr
            let conversionCallee: InternedString? = switch (calleeStr, nonNullReceiverType, nonNullResultType) {
            case ("toInt", uintType, intType): interner.intern("kk_uint_to_int")
            case ("toInt", ulongType, intType): interner.intern("kk_ulong_to_int")
            case ("toInt", ubyteType, intType): interner.intern("kk_ubyte_to_int")
            case ("toInt", ushortType, intType): interner.intern("kk_ushort_to_int")
            case ("toInt", doubleType, intType): interner.intern("__kk_double_to_int")
            case ("toInt", floatType, intType): interner.intern("__kk_float_to_int")
            case ("toInt", longType, intType): interner.intern("kk_long_to_int")
            case ("toInt", charType, intType): nil // Char is stored as Int
            case ("toInt", byteType, intType): nil
            case ("toInt", shortType, intType): nil
            case ("toInt", intType, intType): nil
            case ("toUInt", intType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", longType, uintType): interner.intern("kk_long_to_uint")
            case ("toUInt", ubyteType, uintType): interner.intern("kk_ubyte_to_uint")
            case ("toUInt", ushortType, uintType): interner.intern("kk_ushort_to_uint")
            case ("toUInt", byteType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", shortType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", uintType, uintType): nil
            // KSP-1533: ULong.toUInt() narrows 64 bits to 32 and must mask the
            // high bits away (kk_ulong_to_uint has no dedicated symbol; reuse
            // kk_long_to_uint, which already truncates via UInt32(truncatingIfNeeded:)
            // on the same raw-register representation). Was wrongly treated as
            // representation-preserving, which left garbage high bits behind.
            case ("toUInt", ulongType, uintType): interner.intern("kk_long_to_uint")
            case ("toLong", intType, longType): interner.intern("kk_int_to_long")
            case ("toLong", uintType, longType): interner.intern("kk_uint_to_long")
            case ("toLong", ubyteType, longType): interner.intern("kk_ubyte_to_long")
            case ("toLong", ushortType, longType): interner.intern("kk_ushort_to_long")
            case ("toLong", doubleType, longType): interner.intern("__kk_double_to_long")
            case ("toLong", floatType, longType): interner.intern("__kk_float_to_long")
            case ("toLong", byteType, longType): nil
            case ("toLong", shortType, longType): nil
            case ("toLong", longType, longType), ("toLong", ulongType, longType): nil
            case ("toULong", intType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", longType, ulongType): interner.intern("kk_long_to_ulong")
            case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
            case ("toULong", ubyteType, ulongType): interner.intern("kk_ubyte_to_ulong")
            case ("toULong", ushortType, ulongType): interner.intern("kk_ushort_to_ulong")
            case ("toULong", byteType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", shortType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", ulongType, ulongType): nil
            case ("toFloat", intType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", longType, floatType): interner.intern("kk_long_to_float")
            case ("toFloat", uintType, floatType): interner.intern("kk_uint_to_float")
            case ("toFloat", ulongType, floatType): interner.intern("kk_ulong_to_float")
            case ("toFloat", ubyteType, floatType): interner.intern("kk_ubyte_to_float")
            case ("toFloat", ushortType, floatType): interner.intern("kk_ushort_to_float")
            case ("toFloat", byteType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", shortType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", doubleType, floatType): interner.intern("kk_double_to_float")
            case ("toFloat", floatType, floatType): nil
            case ("toDouble", uintType, doubleType): interner.intern("kk_uint_to_double")
            case ("toDouble", ulongType, doubleType): interner.intern("kk_ulong_to_double")
            case ("toDouble", ubyteType, doubleType): interner.intern("kk_ubyte_to_double")
            case ("toDouble", ushortType, doubleType): interner.intern("kk_ushort_to_double")
            case ("toDouble", byteType, doubleType): interner.intern("kk_int_to_double_bits")
            case ("toDouble", shortType, doubleType): interner.intern("kk_int_to_double_bits")
            case ("toDouble", longType, doubleType): interner.intern("kk_long_to_double")
            case ("toDouble", floatType, doubleType): interner.intern("__kk_float_to_double_bits")
            case ("toDouble", doubleType, doubleType): nil
            case ("toByte", intType, byteType): interner.intern("kk_int_to_byte")
            case ("toByte", longType, byteType): interner.intern("kk_long_to_byte")
            case ("toByte", uintType, byteType): interner.intern("kk_uint_to_byte")
            case ("toByte", ulongType, byteType): interner.intern("kk_ulong_to_byte")
            case ("toByte", ubyteType, byteType): interner.intern("kk_ubyte_to_byte")
            case ("toByte", ushortType, byteType): interner.intern("kk_ushort_to_byte")
            case ("toByte", byteType, byteType): nil
            case ("toByte", shortType, byteType): interner.intern("kk_int_to_byte")
            case ("toShort", intType, shortType): interner.intern("kk_int_to_short")
            case ("toShort", longType, shortType): interner.intern("kk_long_to_short")
            case ("toShort", uintType, shortType): interner.intern("kk_uint_to_short")
            case ("toShort", ulongType, shortType): interner.intern("kk_ulong_to_short")
            case ("toShort", ubyteType, shortType): interner.intern("kk_ubyte_to_short")
            case ("toShort", ushortType, shortType): interner.intern("kk_ushort_to_short")
            case ("toShort", byteType, shortType): nil
            case ("toShort", shortType, shortType): nil
            case ("toUByte", intType, ubyteType): interner.intern("kk_int_to_ubyte")
            case ("toUByte", longType, ubyteType): interner.intern("kk_long_to_ubyte")
            case ("toUByte", uintType, ubyteType): interner.intern("kk_uint_to_ubyte")
            case ("toUByte", ulongType, ubyteType): interner.intern("kk_ulong_to_ubyte")
            case ("toUByte", ubyteType, ubyteType): nil
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
            case ("toChar", charType, charType): nil
            default: nil
            }
            if let callee = conversionCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: callee,
                    arguments: [conversionReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let isRepresentationPreservingConversion =
                (calleeStr == "toLong" && nonNullReceiverType == ulongType && nonNullResultType == longType)
                    || (calleeStr == "toULong" && nonNullReceiverType == longType && nonNullResultType == ulongType)
                    || (calleeStr == "toInt" && nonNullReceiverType == charType && nonNullResultType == intType)
                    || (calleeStr == "toInt" && (nonNullReceiverType == byteType || nonNullReceiverType == shortType) && nonNullResultType == intType)
                    || (calleeStr == "toLong" && (nonNullReceiverType == byteType || nonNullReceiverType == shortType) && nonNullResultType == longType)
                    || (calleeStr == "toShort" && nonNullReceiverType == byteType && nonNullResultType == shortType)
            // Byte.toByte() and Short.toShort() have no runtime callee; keep
            // identity/representation-preserving conversions from falling through
            // to generic member emission as raw symbols.
            if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toByte", "toShort", "toUByte", "toUShort", "toChar"].contains(calleeStr),
               nonNullReceiverType == nonNullResultType || isRepresentationPreservingConversion,
               nonNullReceiverType == intType || nonNullReceiverType == longType
               || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
               || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
               || nonNullReceiverType == byteType || nonNullReceiverType == shortType
               || nonNullReceiverType == floatType || nonNullReceiverType == doubleType
               || nonNullReceiverType == charType
            {
                instructions.append(.copy(from: conversionReceiverID, to: result))
                return result
            }
        }
        return nil
    }

    func lowerLegacyCharCodeCall(
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // KSP-662: bundled Kotlin (kotlin.text.CharConversions) resolves
        // digitToInt / digitToIntOrNull, so no lowering special case is needed.
        if args.isEmpty, calleeNameStr == "code" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if sema.types.makeNonNullable(receiverType) == sema.types.charType {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_char_code"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        return nil
    }

    func explicitFloatingOrCharArithmeticOp(_ name: String) -> KIRBinaryOp? {
        switch name {
        case "plus": .add
        case "minus": .subtract
        case "times": .multiply
        case "div": .divide
        case "rem": .modulo
        default: nil
        }
    }

}
