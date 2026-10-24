extension CallLowerer {

    func lowerLegacyRangeMemberRead(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeNameStr: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeText = calleeNameStr
            if (calleeText == "start" || calleeText == "endInclusive"),
               let runtimeGetter = closedRangeInterfaceRuntimeName(
                   memberName: calleeText,
                   receiverExpr: receiverExpr,
                   receiverType: receiverType,
                   chosenCallee: sema.bindings.callBindings[exprID]?.chosenCallee,
                   sema: sema,
                   interner: interner
               )
            {
                instructions.append(.call(callee: runtimeGetter, arguments: [loweredReceiverID], result: result, canThrow: false))
                return result
            }
            // Property `.first`/`.last` keep the non-throwing getters. Explicit
            // `first()`/`last()` must throw `NoSuchElementException` on empty,
            // including `IntRange` (Sema binds those calls to the property).
            // Explicit `first()`/`last()` on a *Progression* is excluded here:
            // it is bundled Kotlin source (RangeHOF.kt) that already throws
            // with the exact kotlinc message
            // ("Progression ${xxxProgressionDescription(this)} is empty."),
            // and is handled by the `isExplicitProgressionSourceCall` gate
            // below. Reconstructing a Runtime bridge call here would shadow
            // that source-backed implementation with a generic-message one.
            let progressionKinds: Set<MemberDispatchReceiverKind> = [
                .intProgression, .longProgression, .charProgression,
                .uintProgression, .ulongProgression,
            ]
            if (calleeText == "first" || calleeText == "last"),
               let rangeKind = MemberRuntimeDispatch.rangeReceiverKind(
                   receiverExpr: receiverExpr,
                   receiverType: receiverType,
                   sema: sema,
                   interner: interner
               )
            {
                let usesThrowingFunction = ast.arena.isExplicitCall(exprID)
                if !(usesThrowingFunction && progressionKinds.contains(rangeKind)) {
                    let runtimeName = usesThrowingFunction
                        ? MemberRuntimeDispatch.rangeFirstLastOrThrowLinkName(
                            kind: rangeKind,
                            wantLast: calleeText == "last"
                        )
                        : MemberRuntimeDispatch.rangeFirstLastPropertyLinkName(
                            kind: rangeKind,
                            wantLast: calleeText == "last"
                        )
                    instructions.append(.call(
                        callee: interner.intern(runtimeName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: usesThrowingFunction
                    ))
                    return result
                }
            }
            let isRangeLikeReceiver = sema.bindings.isRangeExpr(receiverExpr) || {
                guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
                    return false
                }
                let name = interner.resolve(symbol.name)
                return name == "IntProgression"
                    || name == "LongProgression"
                    || name == "LongRange"
                    || name == "CharProgression"
                    || name == "UIntRange"
                    || name == "UIntProgression"
                    || name == "ULongRange"
                    || name == "ULongProgression"
            }()
            let isULongRangeSourceEndProperty = {
                guard calleeNameStr == "endInclusive" || calleeNameStr == "endExclusive",
                      let (_, receiverSymbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema),
                      interner.resolve(receiverSymbol.name) == "ULongRange",
                      let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
                      sema.symbols.isSourceBackedSymbol(propertySymbol),
                      sema.symbols.parentSymbol(for: propertySymbol) == receiverSymbol.id
                else {
                    return false
                }
                return true
            }()
            let isExplicitProgressionSourceCall = ast.arena.isExplicitCall(exprID)
                && {
                    let memberName = calleeNameStr
                    guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
                        return false
                    }
                    switch interner.resolve(symbol.name) {
                    case "CharProgression":
                        return ["first", "firstOrNull", "last", "lastOrNull"].contains(memberName)
                    case "IntProgression":
                        return ["first", "last"].contains(memberName)
                    case "LongProgression":
                        return ["first", "firstOrNull", "last", "lastOrNull"].contains(memberName)
                    case "UIntProgression":
                        return ["first", "firstOrNull", "last", "lastOrNull"].contains(memberName)
                    case "ULongProgression":
                        return ["first", "firstOrNull", "last", "lastOrNull"].contains(memberName)
                    default:
                        return false
                    }
                }()
            let isLongRange = nonNullReceiverType == sema.types.longType
            if isRangeLikeReceiver && !isExplicitProgressionSourceCall && !isULongRangeSourceEndProperty {
                // KSP-1524: range first/last values are raw bits at this ABI
                // boundary, so ULong can use the shared getter as well.
                let runtimeGetter: InternedString? = switch calleeNameStr {
                case "start":
                    interner.intern("__kk_range_first")
                // `endInclusive` is the `ClosedRange` property name; `end` is the legacy alias.
                case "end", "endInclusive":
                    interner.intern("__kk_range_last")
                case "endExclusive":
                    interner.intern("__kk_range_endExclusive")
                case "first":
                    interner.intern("__kk_range_first")
                case "last":
                    interner.intern("__kk_range_last")
                case "step":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "__kk_ulong_range_step"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "__kk_uint_range_step"
                            : (isLongRange ? "__kk_long_range_step" : "__kk_range_step")))
                default:
                    nil
                }
                if let runtimeGetter {
                    instructions.append(.call(
                        callee: runtimeGetter,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: calleeNameStr == "endExclusive"
                    ))
                    return result
                }
            }
        }
        return nil
    }

    func lowerLegacyRangeStepMember(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if args.isEmpty,
           calleeName == interner.intern("step")
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let runtimeCallee: InternedString = if sema.bindings.isULongRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.ulongType
            {
                interner.intern("__kk_ulong_range_step")
            } else if sema.bindings.isUIntRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.uintType
            {
                interner.intern("__kk_uint_range_step")
            } else {
                interner.intern("__kk_range_step")
            }
            instructions.append(.call(callee: runtimeCallee, arguments: [loweredReceiverID], result: result, canThrow: false))
            return result
        }
        return nil
    }

}
