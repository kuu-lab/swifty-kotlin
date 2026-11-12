extension CallLowerer {

    func lowerLegacyRangeMemberRead(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
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
            let knownNames = KnownCompilerNames(interner: interner)
            let startName = interner.intern("start")
            let endName = interner.intern("end")
            let endInclusiveName = interner.intern("endInclusive")
            let endExclusiveName = interner.intern("endExclusive")
            let firstName = knownNames.first
            let lastName = knownNames.last
            let stepName = knownNames.step
            if calleeName == endExclusiveName,
               let chosen = sema.bindings.callBindings[exprID]?.chosenCallee,
               sema.symbols.symbol(chosen)?.kind == .function,
               sema.symbols.accessorOwnerProperty(for: chosen) == nil,
               sema.symbols.parentSymbol(for: chosen).flatMap(sema.symbols.symbol)?.kind != .property
            {
                // A same-named extension function is not the endpoint property.
                return nil
            }
            if (calleeName == startName || calleeName == endInclusiveName || calleeName == endExclusiveName),
               let runtimeGetter = closedRangeInterfaceRuntimeName(
                   memberName: interner.resolve(calleeName),
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
            if (calleeName == firstName || calleeName == lastName),
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
                            wantLast: calleeName == lastName
                        )
                        : MemberRuntimeDispatch.rangeFirstLastPropertyLinkName(
                            kind: rangeKind,
                            wantLast: calleeName == lastName
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
                let name = symbol.name
                return name == knownNames.intProgression
                    || name == knownNames.longProgression
                    || name == knownNames.longRange
                    || name == knownNames.charProgression
                    || name == knownNames.uintRange
                    || name == knownNames.uintProgression
                    || name == knownNames.ulongRange
                    || name == knownNames.ulongProgression
            }()
            let isULongRangeSourceEndProperty = {
                guard calleeName == endInclusiveName || calleeName == endExclusiveName,
                      let (_, receiverSymbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema),
                      receiverSymbol.name == knownNames.ulongRange,
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
                    let memberName = calleeName
                    let firstOrNullName = interner.intern("firstOrNull")
                    let lastOrNullName = interner.intern("lastOrNull")
                    guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
                        return false
                    }
                    switch symbol.name {
                    case knownNames.charProgression:
                        return [firstName, firstOrNullName, lastName, lastOrNullName].contains(memberName)
                    case knownNames.intProgression:
                        return [firstName, lastName].contains(memberName)
                    case knownNames.longProgression, knownNames.uintProgression, knownNames.ulongProgression:
                        return [firstName, firstOrNullName, lastName, lastOrNullName].contains(memberName)
                    default:
                        return false
                    }
                }()
            let isLongRange = nonNullReceiverType == sema.types.longType
            if isRangeLikeReceiver && !isExplicitProgressionSourceCall && !isULongRangeSourceEndProperty {
                // KSP-1524: range first/last values are raw bits at this ABI
                // boundary, so ULong can use the shared getter as well.
                let runtimeGetter: InternedString? = switch calleeName {
                case startName:
                    interner.intern("__kk_range_first")
                // `endInclusive` is the `ClosedRange` property name; `end` is the legacy alias.
                case endName, endInclusiveName:
                    interner.intern("__kk_range_last")
                case endExclusiveName:
                    interner.intern("__kk_range_endExclusive")
                case firstName:
                    interner.intern("__kk_range_first")
                case lastName:
                    interner.intern("__kk_range_last")
                case stepName:
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
                        canThrow: calleeName == endExclusiveName
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
