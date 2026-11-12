
import Foundation

extension CallTypeChecker {
    func tryRangeMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        let isRangeIteratorMigrationMember = knownNames.rangeMigrationMemberNames.contains(calleeName)

        // An unqualified member call inside an extension body has no receiver
        // expression to bind. Use the extension receiver carried by the type
        // inference context in that case.
        let receiverType = sema.bindings.exprType(for: receiverID) ?? ctx.implicitReceiverType
        let isOpenEndRangeReceiver = receiverType.map {
            driver.helpers.isOpenEndRangeType($0, sema: sema, interner: interner)
        } ?? false

        let isTypedUIntRangeReceiver: Bool = {
            guard let receiverType,
                  let receiverKind = MemberRuntimeDispatch.rangeReceiverKind(
                      receiverExpr: receiverID,
                      receiverType: receiverType,
                      sema: sema,
                      interner: interner
                  )
            else {
                return false
            }
            return receiverKind == .uintRange || receiverKind == .uintProgression
        }()
        let isTypedULongProgressionReceiver: Bool = {
            guard let receiverType,
                  let receiverKind = MemberRuntimeDispatch.rangeReceiverKind(
                      receiverExpr: receiverID,
                      receiverType: receiverType,
                      sema: sema,
                      interner: interner
                  )
            else {
                return false
            }
            return receiverKind == .ulongProgression
        }()
        let isTypedIntRangeReceiver: Bool = {
            guard let receiverType,
                  let receiverKind = MemberRuntimeDispatch.rangeReceiverKind(
                      receiverExpr: receiverID,
                      receiverType: receiverType,
                      sema: sema,
                      interner: interner
                  )
            else {
                return false
            }
            return receiverKind == .intRange
        }()
        let isTypedLongRangeReceiver: Bool = {
            guard let receiverType,
                  let receiverKind = MemberRuntimeDispatch.rangeReceiverKind(
                      receiverExpr: receiverID,
                      receiverType: receiverType,
                      sema: sema,
                      interner: interner
                  )
            else {
                return false
            }
            return receiverKind == .longRange
        }()
        let isTypedULongRangeReceiver: Bool = {
            guard let receiverType,
                  let receiverKind = MemberRuntimeDispatch.rangeReceiverKind(
                      receiverExpr: receiverID,
                      receiverType: receiverType,
                      sema: sema,
                      interner: interner
                  )
            else {
                return false
            }
            return receiverKind == .ulongRange
        }()
        let isSyntacticRangeExpression = ControlFlowTypeChecker.isRangeExpression(receiverID, ast: ctx.ast)
        guard !isClassNameReceiver,
              (sema.bindings.isRangeExpr(receiverID)
                  || isOpenEndRangeReceiver
                  || isSyntacticRangeExpression
                  || (isTypedUIntRangeReceiver && isRangeIteratorMigrationMember)
                  || (isTypedULongProgressionReceiver
                      && (isRangeIteratorMigrationMember
                          || isUnsignedProgressionSourceBackedHOF(calleeName, knownNames: knownNames, argCount: args.count)))
                  || (isTypedIntRangeReceiver
                      && isIntRangeSourceBackedHOF(calleeName, argCount: args.count, knownNames: knownNames))
                  || (isTypedLongRangeReceiver
                      && isLongRangeSourceBackedHOF(calleeName, knownNames: knownNames, argCount: args.count))
                  || (isTypedULongRangeReceiver
                      && (isRangeIteratorMigrationMember
                          || isUnsignedRangeSourceBackedHOF(calleeName, argCount: args.count, knownNames: knownNames))))
        else {
            return nil
        }

        // Let normal overload resolution report invalid labels instead of
        // accepting them through the legacy range fallback. The source-backed
        // contains overloads all use Kotlin's `value` parameter name.
        if (isTypedIntRangeReceiver || isTypedLongRangeReceiver || isTypedUIntRangeReceiver),
           calleeName == knownNames.contains,
           args.contains(where: { argument in
               guard let label = argument.label else { return false }
               return label != knownNames.value
           })
        {
            return nil
        }

        // Nullable membership must be handled by overload resolution, not the
        // legacy fallback which accepts any element type without a binding.
        if calleeName == knownNames.contains, args.count == 1,
           sema.types.nullability(of: driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)) == .nullable
        {
            return nil
        }

        // KSP-453: IntRange/IntProgression HOFs now have bundled Kotlin source
        // implementations; prefer source-backed resolution instead of the legacy
        // hardcoded range-member fallback.
        if let sourceType = bindSourceRangeHOFCall(
            id,
            calleeName: calleeName,
            receiverID: receiverID,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
        ) {
            return sourceType
        }

        if sema.bindings.isFloatingPointRangeExpr(receiverID),
           args.isEmpty,
           calleeName == knownNames.start || calleeName == knownNames.endInclusive,
           let elementType = sema.bindings.floatingPointRangeElementType(forExpr: receiverID)
        {
            let resultType = safeCall ? sema.types.makeNullable(elementType) : elementType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        if sema.bindings.isFloatingPointRangeExpr(receiverID),
           let floatingPointResult = tryRangeMembershipFallback(
            calleeName: calleeName,
            knownNames: knownNames,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
           )
        {
            sema.bindings.bindExprType(id, type: floatingPointResult)
            return floatingPointResult
        }
        // Only endpoint and membership operations above apply to floating-point
        // ranges. Leave other names to ordinary member/extension resolution.
        guard !sema.bindings.isFloatingPointRangeExpr(receiverID) else {
            return nil
        }
        if isOpenEndRangeReceiver,
           let sourceType = bindSourceOpenEndRangeContainsCall(
            id,
            receiverID: receiverID,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
           )
        {
            return sourceType
        }
        if isOpenEndRangeReceiver,
           let openEndResult = tryRangeMembershipFallback(
            calleeName: calleeName,
            knownNames: knownNames,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
           )
        {
            sema.bindings.bindExprType(id, type: openEndResult)
            return openEndResult
        }
        guard isSupportedRangeMember(calleeName, knownNames: knownNames),
              isValidRangeMemberArity(calleeName, knownNames: knownNames, argCount: args.count)
        else {
            return nil
        }

        let rangeKind = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType ?? sema.types.anyType,
            sema: sema,
            interner: interner
        ) ?? .intRange
        let isCharRange = rangeKind.isCharRangeLike
        let isLongRange = rangeKind.isLongRangeLike
        // STDLIB-523: UIntRange / ULongRange support
        // Note on lowering: UIntRange/ULongRange do not require separate lowering
        // passes or runtime helpers. All numeric ranges (Int, Long, UInt, ULong)
        // share the same RuntimeRangeBox representation (first/last/step stored as
        // Swift Int, which is platform-sized -- 64-bit on all supported platforms).
        // The existing __kk_range_* runtime functions handle unsigned values correctly for the
        // common case because:
        //   - UInt values (0..UInt32.max) fit in the non-negative half of Int64
        //   - rangeTo/rangeUntil always produce non-negative step (+1)
        //   - Signed comparisons (<=, >=) are correct for non-negative values
        //   - Wrapping arithmetic (&+=) works identically for both representations
        // Limitation: ULong values > Int64.max (i.e. > 2^63-1) are stored via
        // bit-pattern reinterpretation and may produce incorrect iteration order
        // or comparison results. This is a known limitation; full ULong support
        // would require unsigned comparison helpers in the runtime.
        // Only CharRange needs separate helpers (__kk_char_range_*) due to box/unbox.
        let isUIntRange = rangeKind.isUIntRangeLike
        let isULongRange = rangeKind.isULongRangeLike

        if args.isEmpty,
           [knownNames.step, knownNames.start, knownNames.end, knownNames.endExclusive].contains(calleeName),
           let propertyResult = driver.helpers.lookupMemberProperty(
               named: calleeName,
               receiverType: sema.types.makeNonNullable(receiverType ?? sema.types.anyType),
               sema: sema
           )
        {
            sema.bindings.bindIdentifier(id, symbol: propertyResult.symbol)
        }

        var mappedElementType: TypeID?
        if let expectation = rangeMemberLambdaExpectation(
            calleeName: calleeName,
            knownNames: knownNames,
            argCount: args.count,
            sema: sema,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
            // STDLIB-090: `map`'s declared expected type is `Any` (a permissive
            // upper bound for lambda inference), but the lambda body still infers
            // its own tightest type. Read that back so `(1..n).map { ... }` reports
            // `List<R>` instead of always widening to `List<Any>`.
            if calleeName == knownNames.mapMember,
               case let .lambdaLiteral(_, bodyExpr, _, _) = ctx.ast.arena.expr(lambdaArgExpr)
            {
                mappedElementType = sema.bindings.exprType(for: bodyExpr)
            }
        }

        if calleeName == knownNames.random,
           args.count == 1
        {
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: rangeMemberRandomType(sema: sema, interner: interner)
            )
        }

        if isRangeMemberReturningCollection(calleeName, knownNames: knownNames) {
            sema.bindings.markCollectionExpr(id)
        }
        if calleeName == knownNames.reversed || (calleeName == knownNames.step && args.count == 1) {
            sema.bindings.markRangeExpr(id)
            if sema.bindings.isCharRangeExpr(receiverID) {
                sema.bindings.markCharRangeExpr(id)
            }
            if sema.bindings.isUIntRangeExpr(receiverID) {
                sema.bindings.markUIntRangeExpr(id)
            }
            if sema.bindings.isULongRangeExpr(receiverID) {
                sema.bindings.markULongRangeExpr(id)
            }
        }

        let resultType = rangeMemberResultType(
            calleeName: calleeName,
            knownNames: knownNames,
            argCount: args.count,
            sema: sema,
            interner: interner,
            receiverType: receiverType,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange,
            mappedElementType: mappedElementType
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func bindSourceOpenEndRangeContainsCall(
        _ id: ExprID,
        receiverID: ExprID,
        args: [CallArgument],
        safeCall: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        guard args.count == 1 else { return nil }

        let sema = ctx.sema
        let interner = ctx.interner
        guard let receiverType = sema.bindings.exprType(for: receiverID) ?? ctx.implicitReceiverType,
              let receiverElementType = driver.helpers.rangeLikeDeclaredElementType(
                  for: receiverType,
                  sema: sema,
                  interner: interner
              )
        else {
            return nil
        }
        let argumentType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)

        let candidates = sema.symbols.lookupByShortName(interner.intern("contains")).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType,
                  signature.parameterTypes.count == 1,
                  signature.parameterTypes[0] == sema.types.makeNonNullable(argumentType),
                  let declaredElementType = driver.helpers.rangeLikeDeclaredElementType(
                      for: declaredReceiver,
                      sema: sema,
                      interner: interner
                  ),
                  declaredElementType == receiverElementType,
                  driver.helpers.isOpenEndRangeType(
                      declaredReceiver,
                      sema: sema,
                      interner: interner
                  )
            else {
                return false
            }

            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }

        guard let chosen = candidates.first,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: signature.parameterTypes[0]
        )
        let returnType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: ResolvedCall(
                chosenCallee: chosen,
                substitutedTypeArguments: [:],
                parameterMapping: [0: 0],
                diagnostic: nil
            ),
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func tryRangeMembershipFallback(
        calleeName: InternedString,
        knownNames: KnownCompilerNames,
        args: [CallArgument],
        safeCall: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        switch calleeName {
        case knownNames.contains:
            guard args.count == 1 else { return nil }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        case knownNames.isEmpty:
            guard args.isEmpty else { return nil }
        default:
            return nil
        }
        let resultType = ctx.sema.types.booleanType
        return safeCall ? ctx.sema.types.makeNullable(resultType) : resultType
    }

    private func isIntRangeSourceBackedHOF(_ calleeName: InternedString, argCount: Int, knownNames: KnownCompilerNames) -> Bool {
        if calleeName == knownNames.contains {
            return argCount == 1
        }
        if calleeName == knownNames.first || calleeName == knownNames.last {
            return argCount == 0 || argCount == 1
        }
        return knownNames.intRangeSourceBackedHOFNames.contains(calleeName)
    }

    private func isCharProgressionSourceBackedHOF(_ calleeName: InternedString, knownNames: KnownCompilerNames, argCount: Int) -> Bool {
        if calleeName == knownNames.mapMember {
            return argCount == 1
        }
        guard argCount == 0 else { return false }
        return calleeName == knownNames.first
            || calleeName == knownNames.firstOrNull
            || calleeName == knownNames.last
            || calleeName == knownNames.lastOrNull
    }

    private func isCharRangeSourceBackedHOF(_ calleeName: InternedString, knownNames: KnownCompilerNames, argCount: Int) -> Bool {
        calleeName == knownNames.mapMember && argCount == 1
    }

    private func isUnsignedProgressionSourceBackedHOF(_ calleeName: InternedString, knownNames: KnownCompilerNames, argCount: Int) -> Bool {
        if calleeName == knownNames.iterator {
            return argCount == 0
        }
        if calleeName == knownNames.step {
            return argCount == 1
        }
        if calleeName == knownNames.first || calleeName == knownNames.firstOrNull
            || calleeName == knownNames.last || calleeName == knownNames.lastOrNull
        {
            return calleeName == knownNames.first || calleeName == knownNames.last
                ? argCount == 0
                : argCount == 0 || argCount == 1
        }
        if calleeName == knownNames.windowed {
            return (1...3).contains(argCount)
        }
        if calleeName == knownNames.isEmpty || calleeName == knownNames.toList
            || calleeName == knownNames.count || calleeName == knownNames.sum
            || calleeName == knownNames.reversed
        {
            return argCount == 0
        }
        guard argCount == 1 else { return false }
        switch calleeName {
        case knownNames.mapMember, knownNames.mapIndexed, knownNames.mapNotNull,
             knownNames.filter, knownNames.filterIndexed, knownNames.filterNot,
             knownNames.chunked, knownNames.take, knownNames.drop,
             knownNames.contains, knownNames.isEmpty, knownNames.toList,
             knownNames.count, knownNames.sum, knownNames.reversed:
            return true
        default:
            return false
        }
    }

    private func isLongRangeSourceBackedHOF(_ calleeName: InternedString, knownNames: KnownCompilerNames, argCount: Int) -> Bool {
        (calleeName == knownNames.contains || calleeName == knownNames.forEach || calleeName == knownNames.mapMember) && argCount == 1
    }

    private func isLongRangeCrossTypeContains(
        _ argumentTypes: [TypeID]?,
        sema: SemaModule
    ) -> Bool {
        guard let argumentTypes, argumentTypes.count == 1 else {
            return false
        }
        let argumentType = sema.types.makeNonNullable(argumentTypes[0])
        return argumentType == sema.types.byteType
            || argumentType == sema.types.intType
            || argumentType == sema.types.shortType
    }

    private func isUnsignedRangeSourceBackedHOF(_ calleeName: InternedString, argCount: Int, knownNames: KnownCompilerNames) -> Bool {
        if calleeName == knownNames.contains {
            return argCount == 1
        }
        if calleeName == knownNames.iterator {
            return argCount == 0
        }
        if calleeName == knownNames.step {
            return argCount == 1
        }
        if calleeName == knownNames.first || calleeName == knownNames.last
            || calleeName == knownNames.firstOrNull || calleeName == knownNames.lastOrNull
        {
            return calleeName == knownNames.first || calleeName == knownNames.last
                ? argCount > 0
                : argCount == 0 || argCount == 1
        }
        if knownNames.unsignedRangeSourceBackedHOFNames.contains(calleeName) {
            if [knownNames.isEmpty, knownNames.toList, knownNames.count, knownNames.sum, knownNames.reversed, knownNames.sorted].contains(calleeName) {
                return argCount == 0
            }
            if calleeName == knownNames.fold || calleeName == knownNames.foldIndexed {
                return argCount == 2
            }
            return calleeName == knownNames.windowed ? (1...3).contains(argCount) : argCount == 1
        }
        return false
    }

    private func isULongRangeCrossTypeContains(
        _ argumentTypes: [TypeID]?,
        sema: SemaModule
    ) -> Bool {
        guard let argumentTypes, argumentTypes.count == 1 else {
            return false
        }
        let argumentType = sema.types.makeNonNullable(argumentTypes[0])
        return argumentType == sema.types.ubyteType
            || argumentType == sema.types.uintType
            || argumentType == sema.types.ushortType
    }

    /// Unary +/- is treated like a bare signed integer literal because the
    /// parser represents it as a wrapper expression.
    func isContextualizableIntegerLiteral(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        switch expr {
        case .intLiteral:
            return true
        case let .unaryExpr(op, operand, _):
            guard op == .unaryPlus || op == .unaryMinus else { return false }
            if case .intLiteral = ast.arena.expr(operand) {
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Kotlin contextualizes a suffixed unsigned literal to ULong when the
    /// ULongRange.contains(ULong) member is the applicable overload. Keep the
    /// literal form distinguishable from an explicitly typed UInt so the
    /// source-backed UInt bridge cannot steal member priority.
    func isContextualizableUnsignedIntegerLiteral(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        if case .uintLiteral = expr {
            return true
        }
        return false
    }

    func longRangeContainsMemberSymbol(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let containsName = interner.intern("contains")
        let longRangeFQName = [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern("LongRange"),
        ]
        let matches: (SymbolID) -> Bool = { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  sema.types.makeNonNullable(signature.parameterTypes[0]) == sema.types.longType,
                  let declaredReceiver = signature.receiverType,
                  let receiverSymbol = self.driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(declaredReceiver),
                      types: sema.types
                  ),
                  let receiverInfo = sema.symbols.symbol(receiverSymbol)
            else {
                return false
            }
            return receiverInfo.fqName == longRangeFQName
        }

        let candidates = driver.helpers.collectMemberFunctionCandidates(
            named: containsName,
            receiverType: sema.types.makeNonNullable(receiverType),
            sema: sema,
            interner: interner
        )
        if let candidate = candidates.first(where: matches) {
            return candidate
        }
        return sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            containsName,
        ]).first(where: matches)
    }

    func ulongRangeContainsMemberSymbol(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let containsName = interner.intern("contains")
        let ulongRangeFQName = [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern("ULongRange"),
        ]
        let matches: (SymbolID) -> Bool = { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  sema.types.makeNonNullable(signature.parameterTypes[0]) == sema.types.ulongType,
                  let declaredReceiver = signature.receiverType,
                  let receiverSymbol = self.driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(declaredReceiver),
                      types: sema.types
                  ),
                  let receiverInfo = sema.symbols.symbol(receiverSymbol)
            else {
                return false
            }
            return receiverInfo.fqName == ulongRangeFQName
        }

        let candidates = driver.helpers.collectMemberFunctionCandidates(
            named: containsName,
            receiverType: sema.types.makeNonNullable(receiverType),
            sema: sema,
            interner: interner
        )
        if let candidate = candidates.first(where: matches) {
            return candidate
        }
        return sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            containsName,
        ]).first(where: matches)
    }

    func bindSourceRangeHOFCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverID: ExprID,
        args: [CallArgument],
        safeCall: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        guard let receiverType = sema.bindings.exprType(for: receiverID),
              let rangeKind = MemberRuntimeDispatch.memberCallReceiverKind(
                  MemberRuntimeDispatch.rangeReceiverKind(
                      receiverExpr: receiverID,
                      receiverType: receiverType,
                      sema: sema,
                      interner: interner
                  ),
                  receiverExpr: receiverID,
                  ast: ctx.ast
              )
        else {
            return nil
        }

        let argumentTypesForSourceLookup: [TypeID]? = if calleeName == knownNames.contains {
            args.map { argument in
                if rangeKind == .longRange,
                   isContextualizableIntegerLiteral(argument.expr, ast: ctx.ast)
                {
                    // Kotlin gives an unsuffixed literal the Long context of
                    // LongRange.contains(Long), even when an Int extension is
                    // also visible at the call site.
                    return driver.inferExpr(
                        argument.expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: sema.types.longType
                    )
                }
                if rangeKind == .ulongRange,
                   isContextualizableUnsignedIntegerLiteral(argument.expr, ast: ctx.ast)
                {
                    return driver.inferExpr(
                        argument.expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: sema.types.ulongType
                    )
                }
                return driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
            }
        } else {
            nil
        }
        let argumentLabelsForSourceLookup: [InternedString?]? = if calleeName == knownNames.contains {
            args.map(\.label)
        } else {
            nil
        }

        let isSourceBackedRangeCall =
            ((rangeKind == .intRange || rangeKind == .intProgression)
                && isIntRangeSourceBackedHOF(calleeName, argCount: args.count, knownNames: knownNames))
            || (rangeKind == .uintRange
                && isUnsignedRangeSourceBackedHOF(calleeName, argCount: args.count, knownNames: knownNames))
            || ((rangeKind == .uintProgression || rangeKind == .ulongProgression)
                && isUnsignedProgressionSourceBackedHOF(calleeName, knownNames: knownNames, argCount: args.count))
            || (rangeKind == .charProgression
                && isCharProgressionSourceBackedHOF(calleeName, knownNames: knownNames, argCount: args.count))
            || (rangeKind == .charRange
                && isCharRangeSourceBackedHOF(calleeName, knownNames: knownNames, argCount: args.count))
            || (rangeKind == .longProgression
                && isCharProgressionSourceBackedHOF(calleeName, knownNames: knownNames, argCount: args.count))
            || (rangeKind == .longRange
                && isLongRangeSourceBackedHOF(calleeName, knownNames: knownNames, argCount: args.count)
                && (calleeName != knownNames.contains
                    || isLongRangeCrossTypeContains(argumentTypesForSourceLookup, sema: sema)))
            || (rangeKind == .ulongRange
                && isUnsignedRangeSourceBackedHOF(calleeName, argCount: args.count, knownNames: knownNames)
                && (calleeName != knownNames.contains
                    || isULongRangeCrossTypeContains(argumentTypesForSourceLookup, sema: sema)))
            || ((calleeName == knownNames.random || calleeName == knownNames.randomOrNull)
                && (rangeKind == .longRange || rangeKind == .charRange
                    || rangeKind == .uintRange || rangeKind == .ulongRange))

        let sourceLookupReceiverType = sourceLevelRangeMemberLookupType(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) ?? receiverType
        if rangeKind == .longRange,
           calleeName == knownNames.contains,
           argumentTypesForSourceLookup?.count == 1,
           argumentTypesForSourceLookup?[0] == sema.types.longType,
           let member = longRangeContainsMemberSymbol(
               receiverType: sourceLookupReceiverType,
               sema: sema,
               interner: interner
           ),
           let signature = sema.symbols.functionSignature(for: member)
        {
            for (index, argument) in args.enumerated() {
                let expectedType = index < signature.parameterTypes.count
                    ? signature.parameterTypes[index]
                    : nil
                _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            }
            let resolved = ResolvedCall(
                chosenCallee: member,
                substitutedTypeArguments: [:],
                parameterMapping: [0: 0],
                diagnostic: nil
            )
            let returnType = bindCallAndResolveReturnType(id, chosen: member, resolved: resolved, sema: sema)
            let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if rangeKind == .ulongRange,
           calleeName == knownNames.contains,
           argumentTypesForSourceLookup?.count == 1,
           argumentTypesForSourceLookup?[0] == sema.types.ulongType,
           let member = ulongRangeContainsMemberSymbol(
               receiverType: sourceLookupReceiverType,
               sema: sema,
               interner: interner
           ),
           let signature = sema.symbols.functionSignature(for: member)
        {
            for (index, argument) in args.enumerated() {
                let expectedType = index < signature.parameterTypes.count
                    ? signature.parameterTypes[index]
                    : nil
                _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            }
            let resolved = ResolvedCall(
                chosenCallee: member,
                substitutedTypeArguments: [:],
                parameterMapping: [0: 0],
                diagnostic: nil
            )
            let returnType = bindCallAndResolveReturnType(id, chosen: member, resolved: resolved, sema: sema)
            let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        let isLongRangeLiteralArgument = rangeKind == .longRange
            && args.count == 1
            && args.first.map { argument in
                isContextualizableIntegerLiteral(argument.expr, ast: ctx.ast)
            } == true
        let isULongUnsignedLiteralArgument = rangeKind == .ulongRange
            && args.count == 1
            && args.first.map { argument in
                isContextualizableUnsignedIntegerLiteral(argument.expr, ast: ctx.ast)
            } == true
        let scopedRangeUserCandidates: [SymbolID] = if calleeName == knownNames.contains, rangeKind == .intRange {
            collectScopedRangeUserExtensionCandidates(
                named: calleeName,
                receiverType: sourceLookupReceiverType,
                ctx: ctx,
                sema: sema,
                interner: interner
            ).filter {
                isIntRangeCrossTypeContainsCandidate($0, sema: sema)
            }
        } else if calleeName == knownNames.contains, rangeKind == .uintRange {
            collectScopedRangeUserExtensionCandidates(
                named: calleeName,
                receiverType: sourceLookupReceiverType,
                ctx: ctx,
                sema: sema,
                interner: interner
            ).filter {
                isUIntRangeCrossTypeContainsCandidate($0, sema: sema)
            }
        } else if calleeName == knownNames.contains,
                  rangeKind == .longRange,
                  !isLongRangeLiteralArgument
        {
            collectScopedRangeUserExtensionCandidates(
                named: calleeName,
                receiverType: sourceLookupReceiverType,
                ctx: ctx,
                sema: sema,
                interner: interner
            ).filter { candidate in
                guard args.count == 1,
                      argumentTypesForSourceLookup?.count == 1,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      signature.parameterTypes[0] == argumentTypesForSourceLookup?[0],
                      isLongRangeCrossTypeContains(argumentTypesForSourceLookup, sema: sema)
                else {
                    return false
                }
                guard let label = args[0].label else { return true }
                guard signature.valueParameterSymbols.count == 1,
                      let parameter = sema.symbols.symbol(signature.valueParameterSymbols[0])
                else {
                    return false
                }
                return parameter.name == label
            }
        } else if calleeName == knownNames.contains,
                  rangeKind == .ulongRange,
                  !isULongUnsignedLiteralArgument
        {
            collectScopedRangeUserExtensionCandidates(
                named: calleeName,
                receiverType: sourceLookupReceiverType,
                ctx: ctx,
                sema: sema,
                interner: interner
            ).filter { candidate in
                guard args.count == 1,
                      argumentTypesForSourceLookup?.count == 1,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      signature.parameterTypes[0] == argumentTypesForSourceLookup?[0],
                      [sema.types.ubyteType, sema.types.uintType, sema.types.ushortType]
                          .contains(signature.parameterTypes[0])
                else {
                    return false
                }
                guard let label = args[0].label else { return true }
                guard signature.valueParameterSymbols.count == 1,
                      let parameter = sema.symbols.symbol(signature.valueParameterSymbols[0])
                else {
                    return false
                }
                return parameter.name == label
            }
        } else {
            []
        }
        if ((rangeKind == .longRange && !isLongRangeLiteralArgument)
                || (rangeKind == .ulongRange && !isULongUnsignedLiteralArgument)),
           let argumentTypesForSourceLookup,
           !scopedRangeUserCandidates.isEmpty
        {
            guard let callRange = ctx.ast.arena.exprRange(id) ?? ctx.ast.arena.exprRange(receiverID) else {
                return nil
            }
            let callArgs = zip(args, argumentTypesForSourceLookup).map { argument, type in
                CallArg.source(argument, type: type, callRange: callRange, ast: ctx.ast)
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: scopedRangeUserCandidates,
                call: CallExpr(
                    range: callRange,
                    calleeName: calleeName,
                    args: callArgs,
                    isOperatorCall: true
                ),
                expectedType: nil,
                implicitReceiverType: sourceLookupReceiverType,
                ctx: ctx.sema
            )
            guard let chosen = resolved.chosenCallee,
                  let signature = sema.symbols.functionSignature(for: chosen)
            else {
                return nil
            }
            for (index, argument) in args.enumerated() {
                let parameterIndex = resolved.parameterMapping[index] ?? index
                let expectedType = parameterIndex < signature.parameterTypes.count
                    ? signature.parameterTypes[parameterIndex]
                    : nil
                _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            }
            let returnType = bindCallAndResolveReturnType(
                id,
                chosen: chosen,
                resolved: resolved,
                sema: sema
            )
            let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        guard isSourceBackedRangeCall,
              let sourceSymbol = sourceRangeHOFSymbol(
                  calleeName: calleeName,
                  rangeKind: rangeKind,
                  argCount: args.count,
                  argumentTypes: argumentTypesForSourceLookup,
                  argumentLabels: argumentLabelsForSourceLookup,
                  preferredCandidates: Set(scopedRangeUserCandidates),
                  sema: sema,
                  interner: interner
              ),
              let signature = sema.symbols.functionSignature(for: sourceSymbol)
        else {
            return nil
        }

        let lambdaExpectation = rangeMemberLambdaExpectation(
            calleeName: calleeName,
            knownNames: knownNames,
            argCount: args.count,
            sema: sema,
            isCharRange: rangeKind.isCharRangeLike,
            isLongRange: rangeKind.isLongRangeLike,
            isUIntRange: rangeKind.isUIntRangeLike,
            isULongRange: rangeKind.isULongRangeLike
        )

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var rConcrete: TypeID?

        for (index, arg) in args.enumerated() {
            let isLambda = ctx.ast.arena.expr(arg.expr)?.isLambdaOrCallableRef == true
            if isLambda {
                let expectedType: TypeID
                if (calleeName == knownNames.fold || calleeName == knownNames.foldIndexed), index == 1, let rConcrete,
                   let baseExpected = lambdaExpectation?.expectedType,
                   case let .functionType(fnType) = sema.types.kind(of: baseExpected) {
                    let params: [TypeID]
                    if calleeName == knownNames.fold {
                        params = [rConcrete] + Array(fnType.params.dropFirst())
                    } else {
                        var mutableParams = fnType.params
                        if mutableParams.count >= 2 {
                            mutableParams[1] = rConcrete
                        }
                        params = mutableParams
                    }
                    expectedType = sema.types.make(.functionType(FunctionType(
                        params: params,
                        returnType: rConcrete
                    )))
                } else if let baseExpected = lambdaExpectation?.expectedType {
                    expectedType = baseExpected
                } else {
                    expectedType = sema.types.anyType
                }

                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: expectedType)
                if ctx.ast.arena.expr(arg.expr)?.isLambdaOrCallableRef == true {
                    sema.bindings.markCollectionHOFLambdaExpr(arg.expr)
                }

                if rConcrete == nil,
                   let lambdaExpr = ctx.ast.arena.expr(arg.expr),
                   case let .lambdaLiteral(_, bodyExpr, _, _) = lambdaExpr {
                    let bodyType = sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                    switch calleeName {
                    case knownNames.mapMember, knownNames.mapIndexed:
                        rConcrete = bodyType
                    case knownNames.mapNotNull:
                        rConcrete = sema.types.makeNonNullable(bodyType)
                    default:
                        break
                    }
                }
            } else {
                let expectedType: TypeID?
                if calleeName == knownNames.fold || calleeName == knownNames.foldIndexed {
                    expectedType = nil
                } else if calleeName == knownNames.windowed {
                    expectedType = (index == 1 ? sema.types.intType : (index == 2 ? sema.types.booleanType : nil))
                } else if calleeName == knownNames.chunked || calleeName == knownNames.take || calleeName == knownNames.drop {
                    expectedType = sema.types.intType
                } else {
                    expectedType = nil
                }

                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: expectedType)
                if (calleeName == knownNames.fold || calleeName == knownNames.foldIndexed), index == 0, rConcrete == nil {
                    rConcrete = sema.bindings.exprType(for: arg.expr) ?? sema.types.anyType
                }
            }
        }

        let concreteR = rConcrete ?? sema.types.anyType
        var substitutions: [TypeVarID: TypeID] = [:]
        for (_, typeVar) in typeVarBySymbol {
            substitutions[typeVar] = concreteR
        }

        var parameterMapping: [Int: Int] = [:]
        for index in args.indices {
            parameterMapping[index] = index
        }

        let resolved = ResolvedCall(
            chosenCallee: sourceSymbol,
            substitutedTypeArguments: substitutions,
            parameterMapping: parameterMapping,
            diagnostic: nil
        )

        let returnType = bindCallAndResolveReturnType(id, chosen: sourceSymbol, resolved: resolved, sema: sema)
        if isRangeMemberReturningCollection(calleeName, knownNames: knownNames) {
            sema.bindings.markCollectionExpr(id)
        }
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func hasIntRangeSourceBackedContainsCandidate(
        receiverType: TypeID,
        argumentType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        collectRangeSourceExtensionCandidates(
            named: interner.intern("contains"),
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ).contains { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1
            else {
                return false
            }
            return signature.parameterTypes[0] == argumentType
        }
    }

    func isIntRangeCrossTypeContainsCandidate(_ candidate: SymbolID, sema: SemaModule) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: candidate),
              signature.parameterTypes.count == 1
        else {
            return false
        }
        return [sema.types.byteType, sema.types.longType, sema.types.shortType]
            .contains(signature.parameterTypes[0])
    }


    func isUIntRangeCrossTypeContainsCandidate(_ candidate: SymbolID, sema: SemaModule) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: candidate),
              signature.parameterTypes.count == 1
        else {
            return false
        }
        return [sema.types.ubyteType, sema.types.ulongType, sema.types.ushortType]
            .contains(signature.parameterTypes[0])
    }

    func sourceRangeHOFSymbol(
        calleeName: InternedString,
        rangeKind: MemberDispatchReceiverKind,
        argCount: Int,
        argumentTypes: [TypeID]? = nil,
        argumentLabels: [InternedString?]? = nil,
        preferredCandidates: Set<SymbolID> = [],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let expectedReceiverFQ = expectedRangeClassFQ(rangeKind: rangeKind, interner: interner) else {
            return nil
        }

        let candidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
            guard let symbolInfo = sema.symbols.symbol(candidate),
                  symbolInfo.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }

            guard argCount <= signature.parameterTypes.count else { return false }
            if let argumentTypes {
                guard argumentTypes.count == signature.parameterTypes.count,
                      zip(argumentTypes, signature.parameterTypes).allSatisfy({ $0 == $1 })
                else {
                    return false
                }
            }
            if let argumentLabels {
                guard argumentLabels.count == signature.parameterTypes.count,
                      argumentLabels.indices.allSatisfy({ index in
                          guard let label = argumentLabels[index] else { return true }
                          guard index < signature.valueParameterSymbols.count,
                                let parameter = sema.symbols.symbol(signature.valueParameterSymbols[index])
                          else {
                              return false
                          }
                          return parameter.name == label
                      })
                else {
                    return false
                }
            }
            for missingIndex in argCount..<signature.parameterTypes.count {
                guard missingIndex < signature.valueParameterHasDefaultValues.count,
                      signature.valueParameterHasDefaultValues[missingIndex]
                else {
                    return false
                }
            }

            let declaredNonNull = sema.types.makeNonNullable(declaredReceiver)
            guard case let .classType(classType) = sema.types.kind(of: declaredNonNull),
                  let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }

            return receiverSymbol.fqName == expectedReceiverFQ
        }

        func hasLink(_ candidate: SymbolID) -> Bool {
            guard let linkName = sema.symbols.externalLinkName(for: candidate) else { return false }
            return !linkName.isEmpty
        }

        if let preferred = candidates.first(where: { preferredCandidates.contains($0) }) {
            return preferred
        }
        return candidates.first { hasLink($0) } ?? candidates.first
    }

    private func expectedRangeClassFQ(
        rangeKind: MemberDispatchReceiverKind,
        interner: StringInterner
    ) -> [InternedString]? {
        let kotlin = interner.intern("kotlin")
        let ranges = interner.intern("ranges")
        switch rangeKind {
        case .intRange:
            return [kotlin, ranges, interner.intern("IntRange")]
        case .intProgression:
            return [kotlin, ranges, interner.intern("IntProgression")]
        case .longProgression:
            return [kotlin, ranges, interner.intern("LongProgression")]
        case .ulongProgression:
            return [kotlin, ranges, interner.intern("ULongProgression")]
        case .charProgression:
            return [kotlin, ranges, interner.intern("CharProgression")]
        case .longRange:
            return [kotlin, ranges, interner.intern("LongRange")]
        case .charRange:
            return [kotlin, ranges, interner.intern("CharRange")]
        case .uintRange:
            return [kotlin, ranges, interner.intern("UIntRange")]
        case .uintProgression:
            return [kotlin, ranges, interner.intern("UIntProgression")]
        case .ulongRange:
            return [kotlin, ranges, interner.intern("ULongRange")]
        default:
            return nil
        }
    }

    private func isSupportedRangeMember(_ calleeName: InternedString, knownNames: KnownCompilerNames) -> Bool {
        // KSP-1523: `average`/`toUIntArray` were removed from this legacy
        // allowlist — neither is a real UIntRange member in Kotlin
        // (confirmed via diff_kotlinc.sh), and this fallback only binds a
        // result *type* (see `rangeMemberResultType` below), never a callee
        // symbol. With no bundled RangeHOF.kt declaration or Sema synthetic
        // registration to resolve the actual call, keeping these names here
        // let `(1u..5u).average()` type-check successfully and fall all the
        // way through to a bare, unresolved `average` callee at link time
        // (`Undefined symbols ... "_average"`) instead of being rejected at
        // Sema, the way real kotlinc rejects it. `IntRange`/`LongRange`'s
        // `average()` — genuine Kotlin members — do not depend on this
        // allowlist entry: they resolve earlier via `bindSourceRangeHOFCall`
        // (bundled Kotlin source); verified by probe that both still
        // type-check and produce correct results with `average` absent from
        // this set. `toUIntArray` was never valid for any other range type's
        // receiver, and neither are `toIntArray`/`toLongArray`/`toULongArray`
        // for their signed/ULong counterparts (BUG-259/KSP-1524) -- none of the
        // four belong in this allowlist.
        return knownNames.supportedRangeMemberNames.contains(calleeName)
    }

    private func isValidRangeMemberArity(_ calleeName: InternedString, knownNames: KnownCompilerNames, argCount: Int) -> Bool {
        switch calleeName {
        case knownNames.count, knownNames.start, knownNames.end, knownNames.endInclusive,
             knownNames.endExclusive, knownNames.toList, knownNames.reversed, knownNames.sum, knownNames.sorted:
            argCount == 0
        case knownNames.random:
            argCount == 0 || argCount == 1
        case knownNames.step:
            argCount == 0 || argCount == 1
        case knownNames.first, knownNames.last:
            argCount == 0 || argCount == 1
        case knownNames.forEach, knownNames.mapMember, knownNames.mapIndexed, knownNames.mapNotNull,
             knownNames.filter, knownNames.filterIndexed, knownNames.filterNot,
             knownNames.reduce, knownNames.reduceIndexed,
             knownNames.find, knownNames.findLast,
             knownNames.anyMember, knownNames.allMember, knownNames.noneMember,
             knownNames.take, knownNames.drop:
            argCount == 1
        case knownNames.firstOrNull, knownNames.lastOrNull:
            argCount == 0 || argCount == 1
        case knownNames.randomOrNull:
            argCount == 0 || argCount == 1
        case knownNames.fold, knownNames.foldIndexed:
            argCount == 2
        case knownNames.chunked:
            argCount == 1
        case knownNames.windowed:
            (1...3).contains(argCount)
        default:
            true
        }
    }

    private func isRangeMemberReturningCollection(_ calleeName: InternedString, knownNames: KnownCompilerNames) -> Bool {
        switch calleeName {
        case knownNames.toList, knownNames.mapMember, knownNames.mapIndexed, knownNames.mapNotNull,
             knownNames.filter, knownNames.filterIndexed, knownNames.filterNot,
             knownNames.chunked, knownNames.windowed, knownNames.take, knownNames.drop, knownNames.sorted:
            return true
        default:
            return false
        }
    }

    private func rangeMemberElementType(
        sema: SemaModule,
        isCharRange: Bool,
        isLongRange: Bool,
        isUIntRange: Bool,
        isULongRange: Bool
    ) -> TypeID {
        if isCharRange {
            return sema.types.charType
        }
        if isLongRange {
            return sema.types.longType
        }
        if isUIntRange {
            return sema.types.uintType
        }
        if isULongRange {
            return sema.types.ulongType
        }
        return sema.types.intType
    }

    private func rangeMemberResultType(
        calleeName: InternedString,
        knownNames: KnownCompilerNames,
        argCount: Int,
        sema: SemaModule,
        interner: StringInterner,
        receiverType: TypeID? = nil,
        isCharRange: Bool = false,
        isLongRange: Bool = false,
        isUIntRange: Bool = false,
        isULongRange: Bool = false,
        mappedElementType: TypeID? = nil
    ) -> TypeID {
        let elementType = rangeMemberElementType(
            sema: sema,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        )
        switch calleeName {
        case knownNames.first, knownNames.last, knownNames.start, knownNames.end,
             knownNames.endInclusive, knownNames.endExclusive:
            return elementType
        case knownNames.random:
            return elementType
        case knownNames.firstOrNull, knownNames.lastOrNull, knownNames.randomOrNull,
             knownNames.find, knownNames.findLast:
            return sema.types.makeNullable(elementType)
        case knownNames.count:
            return sema.types.intType
        case knownNames.sum:
            return elementType
        case knownNames.anyMember, knownNames.allMember, knownNames.noneMember:
            return sema.types.booleanType
        case knownNames.forEach:
            return sema.types.unitType
        case knownNames.toList:
            return rangeMemberListType(elementType: elementType, sema: sema, interner: interner)
        case knownNames.filter, knownNames.filterIndexed, knownNames.filterNot:
            return rangeMemberListType(elementType: elementType, sema: sema, interner: interner)
        case knownNames.mapMember:
            return rangeMemberListType(elementType: mappedElementType ?? sema.types.anyType, sema: sema, interner: interner)
        case knownNames.mapIndexed, knownNames.mapNotNull:
            return rangeMemberListType(elementType: sema.types.anyType, sema: sema, interner: interner)
        case knownNames.reduce, knownNames.reduceIndexed:
            return elementType
        case knownNames.fold, knownNames.foldIndexed:
            return sema.types.anyType
        case knownNames.chunked, knownNames.windowed:
            return rangeMemberListType(
                elementType: rangeMemberListType(elementType: elementType, sema: sema, interner: interner),
                sema: sema,
                interner: interner
            )
        case knownNames.take, knownNames.drop, knownNames.sorted:
            return rangeMemberListType(elementType: elementType, sema: sema, interner: interner)
        case knownNames.reversed:
            return rangeMemberRangeType(
                receiverType: receiverType,
                elementType: elementType,
                sema: sema,
                interner: interner,
                isLongRange: isLongRange,
                isUIntRange: isUIntRange,
                isULongRange: isULongRange,
                returnsProgression: true
            )
        case knownNames.step:
            return argCount == 0 ? sema.types.intType : rangeMemberRangeType(
                receiverType: receiverType,
                elementType: elementType,
                sema: sema,
                interner: interner,
                isLongRange: isLongRange,
                isUIntRange: isUIntRange,
                isULongRange: isULongRange,
                returnsProgression: true
            )
        default:
            return sema.types.anyType
        }
    }

    private func rangeMemberRandomType(
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let randomFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("random"),
            interner.intern("Random"),
        ]
        guard let randomSymbol = sema.symbols.lookup(fqName: randomFQName) else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func rangeMemberListType(
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = sema.symbols.lookupNominal(fqName: listFQName) else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func rangeMemberRangeType(
        receiverType: TypeID?,
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        isLongRange: Bool,
        isUIntRange: Bool,
        isULongRange: Bool,
        returnsProgression: Bool = false
    ) -> TypeID {
        // Primitive range reversed()/step() return progression classes. Retaining
        // the range type here selects range-only toString and HOF overloads.
        if returnsProgression {
            let progressionName: String
            if isLongRange {
                progressionName = "LongProgression"
            } else if isUIntRange {
                progressionName = "UIntProgression"
            } else if isULongRange {
                progressionName = "ULongProgression"
            } else if elementType == sema.types.charType {
                progressionName = "CharProgression"
            } else {
                progressionName = "IntProgression"
            }
            let progressionFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("ranges"),
                interner.intern(progressionName),
            ]
            if let progressionSymbol = sema.symbols.lookup(fqName: progressionFQName) {
                return sema.types.make(.classType(ClassType(
                    classSymbol: progressionSymbol,
                    args: [],
                    nullability: .nonNull
                )))
            }
        }

        if let receiverType,
           case .classType = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        {
            return sema.types.makeNonNullable(receiverType)
        }

        if isULongRange {
            return sema.types.ulongType
        }
        if isUIntRange {
            return sema.types.uintType
        }
        if isLongRange {
            return sema.types.longType
        }
        if elementType == sema.types.charType {
            return sema.types.intType
        }

        guard let intRangeSymbol = sema.symbols.lookupByShortName(interner.intern("IntRange")).first else {
            return sema.types.intType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: intRangeSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func rangeMemberLambdaExpectation(
        calleeName: InternedString,
        knownNames: KnownCompilerNames,
        argCount: Int,
        sema: SemaModule,
        isCharRange: Bool = false,
        isLongRange: Bool = false,
        isUIntRange: Bool = false,
        isULongRange: Bool = false
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let elementType = rangeMemberElementType(
            sema: sema,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        )
        let expectation: (Int, [TypeID], TypeID)?
        switch calleeName {
        case knownNames.forEach:
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType], sema.types.unitType)
        case knownNames.mapMember:
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType], sema.types.anyType)
        case knownNames.mapNotNull:
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType], sema.types.nullableAnyType)
        case knownNames.filter, knownNames.filterNot, knownNames.find, knownNames.findLast,
             knownNames.first, knownNames.firstOrNull, knownNames.last, knownNames.lastOrNull,
             knownNames.anyMember, knownNames.allMember, knownNames.noneMember:
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType], sema.types.booleanType)
        case knownNames.mapIndexed:
            guard argCount == 1 else { return nil }
            expectation = (0, [sema.types.intType, elementType], sema.types.anyType)
        case knownNames.filterIndexed:
            guard argCount == 1 else { return nil }
            expectation = (0, [sema.types.intType, elementType], sema.types.booleanType)
        case knownNames.reduce:
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType, elementType], elementType)
        case knownNames.reduceIndexed:
            guard argCount == 1 else { return nil }
            expectation = (0, [sema.types.intType, elementType, elementType], elementType)
        case knownNames.fold:
            guard argCount == 2 else { return nil }
            expectation = (1, [sema.types.anyType, elementType], sema.types.anyType)
        case knownNames.foldIndexed:
            guard argCount == 2 else { return nil }
            expectation = (1, [sema.types.intType, sema.types.anyType, elementType], sema.types.anyType)
        default:
            expectation = nil
        }
        guard let expectation else { return nil }
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: expectation.1,
            returnType: expectation.2,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: expectation.0, expectedType: expectedType)
    }
}
