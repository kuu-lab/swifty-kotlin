/// `Any` member fallbacks (`toString`/`hashCode`/`equals`) for receivers
/// Sema did not bind to a concrete member: nullable-Any unbound calls,
/// KClass receivers, primitives, type parameters, and erased `Any`
/// values.

extension CallLowerer {

    func lowerLegacyAnyFallbackMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let anyFallbackReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullAnyFallbackReceiverType = sema.types.makeNonNullable(anyFallbackReceiverType)
        let isKClassReceiver = isKClassReceiverType(
            anyFallbackReceiverType, sema: sema, interner: interner
        )
        let memberName = calleeNameStr
        let hasResolvedCallBinding = sema.bindings.callBindings[exprID].map { $0.chosenCallee != .invalid } ?? false
        let isUnresolvedNullableAnyToStringOrHashCode = !hasResolvedCallBinding
            && sema.types.nullability(of: anyFallbackReceiverType) == .nullable
            && (memberName == "toString" || memberName == "hashCode")
        let allowsAnyFallback: Bool = if isUnresolvedNullableAnyToStringOrHashCode {
            true
        } else if isKClassReceiver {
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
            default:
                nonNullAnyFallbackReceiverType == sema.types.anyType
            }
        }
        // Use the member-dispatch bridge so a Throwable override remains
        // visible after erasure to Any. Keep the tagged helper for primitive
        // and type-parameter fallback values.
        if args.isEmpty, calleeNameStr == "toString", allowsAnyFallback {
            if nonNullAnyFallbackReceiverType == sema.types.anyType {
                instructions.append(.call(
                    callee: interner.intern("kk_any_member_to_string"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false
                ))
                return result
            }
            // A nullable Float?/Double?/ULong? receiver shares the runtime
            // null sentinel's bit pattern with an in-range value (0.0, -0.0,
            // or a ULong of exactly 2^63), and kk_any_to_string decodes those
            // tags before checking the sentinel — so a real null would render
            // as that value. Route primitive receivers through the guarded
            // helper, which null-checks nullable tag-5/6/7 values first and
            // boxes a statically non-null Long so Long.MIN_VALUE renders its
            // digits instead of "null" (KUU-3661).
            if case .primitive = sema.types.kind(of: nonNullAnyFallbackReceiverType) {
                let converted = emitAnyToStringWithNullGuard(
                    valueID: loweredReceiverID,
                    valueType: anyFallbackReceiverType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.copy(from: converted, to: result))
                return result
            }
            let tag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
            instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
            instructions.append(.call(
                callee: interner.intern("kk_any_to_string"),
                arguments: [loweredReceiverID, tagID],
                result: result,
                canThrow: false
            ))
            return result
        }

        if args.isEmpty, calleeNameStr == "hashCode", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let hashReceiverID = boxSentinelProneHashCodeReceiver(
                loweredReceiverID,
                sourceType: anyFallbackReceiverType,
                sema: sema,
                interner: interner,
                arena: arena,
                into: &instructions
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
            return result
        }

        if args.count == 1, calleeNameStr == "equals", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let argType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let argTag = anyFallbackTag(for: argType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
            instructions.append(.constValue(result: argTagID, value: .intLiteral(argTag)))
            let boxedResult = arena.appendTemporary(type: sema.types.makeNullable(sema.types.booleanType))
            instructions.append(.call(
                callee: interner.intern("kk_any_equals"),
                arguments: [loweredReceiverID, receiverTagID, loweredArgIDs[0], argTagID],
                result: boxedResult,
                canThrow: false
            ))
            instructions.append(.call(callee: interner.intern("kk_unbox_bool_static"), arguments: [boxedResult], result: result, canThrow: false))
            return result
        }
        return nil
    }

}
