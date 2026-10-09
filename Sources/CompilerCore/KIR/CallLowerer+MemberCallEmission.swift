// swiftlint:disable file_length

/// Member-call argument normalization and instruction emission helpers.
extension CallLowerer {
    func memberExtensionOwnerSymbol(for callee: SymbolID, sema: SemaModule) -> SymbolID? {
        sema.symbols.memberExtensionOwnerSymbol(for: callee)
    }

    func memberExtensionDispatchReceiver(
        for callee: SymbolID,
        callExprID: ExprID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let owner = memberExtensionOwnerSymbol(for: callee, sema: sema),
              let ownerInfo = sema.symbols.symbol(owner)
        else { return nil }
        // A receiver found under an owner that merely *reaches* the dispatch
        // owner (a subtype like `Derived` for `Base`, or an `inner class`
        // instance that must hop through its `$outer` link) is not yet a
        // value of the owner's type — chain it, and reject values that
        // cannot reach `owner` at all instead of passing them as-is.
        func resolveToOwner(_ exprID: KIRExprID?) -> KIRExprID? {
            exprID.flatMap {
                resolveOuterChainValue(
                    from: $0,
                    to: owner,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
        }
        if let marked = callExprID
            .flatMap({ sema.bindings.implicitReceiverOuterReceiver(for: $0) })
            .flatMap({ driver.ctx.localValue(for: $0) }),
           let resolved = resolveToOwner(marked)
        {
            return resolved
        }
        if let direct = driver.ctx.capturedOuterReceiverExprID(for: owner) {
            return direct
        }
        if let reachingOwner = driver.ctx.capturedOuterReceiverOwner(reaching: owner, sema: sema),
           let resolved = resolveToOwner(driver.ctx.capturedOuterReceiverExprID(for: reachingOwner))
        {
            return resolved
        }
        if let receiver = resolveToOwner(driver.ctx.qualifiedThisReceiverExprID(for: ownerInfo.name))
            ?? resolveToOwner(driver.ctx.activeImplicitReceiverExprID())
        {
            return receiver
        }
        // Imported object/companion extensions have no enclosing dispatch
        // receiver. Their source bodies still require the singleton before
        // the extension receiver, including primitive property getters.
        // Imported companion extensions can bind as ordinary member calls,
        // including property getters. They still need the singleton dispatch
        // receiver even when no lexical receiver is active.
        if ownerInfo.kind == .object {
            driver.emitObjectLazyInitGuardIfNeeded(
                objectSymbol: owner, arena: arena, sema: sema, instructions: &instructions
            )
            let ownerType = sema.types.make(.classType(ClassType(
                classSymbol: owner, args: [], nullability: .nonNull
            )))
            let receiver = arena.appendExpr(.symbolRef(owner), type: ownerType)
            instructions.append(.constValue(result: receiver, value: .symbolRef(owner)))
            return receiver
        }
        return nil
    }

    /// Supply the dispatch receiver shared by getter, setter and compound updates.
    func propertyAccessorArguments(
        for accessor: SymbolID,
        arguments: [KIRExprID],
        callExprID: ExprID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        if let receiver = memberExtensionDispatchReceiver(
            for: accessor, callExprID: callExprID, sema: sema, arena: arena,
            interner: interner, instructions: &instructions
        ) {
            return [receiver] + arguments
        }
        return arguments
    }

    func sequenceBuilderRuntimeCalleeName(
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let chosenCallee,
              let symbol = sema.symbols.symbol(chosenCallee),
              symbol.fqName.count == 4,
              symbol.fqName[0] == knownNames.kotlin,
              symbol.fqName[1] == knownNames.sequences,
              symbol.fqName[2] == knownNames.sequenceScope
        else {
            return nil
        }

        switch calleeName {
        case knownNames.yield:
            return interner.intern("__kk_sequence_builder_yield")
        case knownNames.yieldAll:
            return interner.intern("__kk_sequence_builder_yieldAll_checked")
        default:
            return nil
        }
    }

    /// Whether `symbol` is a `const val` whose value `tryFoldConstMemberProperty`
    /// inlines at the use site.
    func isFoldableConstProperty(
        _ symbol: SymbolID,
        sema: SemaModule,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) -> Bool {
        guard let symInfo = sema.symbols.symbol(symbol),
              symInfo.flags.contains(.constValue)
        else {
            return false
        }
        return propertyConstantInitializers[symbol] != nil
            || sema.symbols.constValueExprKind(for: symbol) != nil
    }

    func tryFoldConstMemberProperty(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        requireNonNullableReceiver: Bool,
        sema: SemaModule,
        arena: KIRArena,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.isEmpty else { return nil }
        let callBinding = sema.bindings.callBindings[exprID]
        guard let chosen = callBinding?.chosenCallee,
              isFoldableConstProperty(
                  chosen, sema: sema, propertyConstantInitializers: propertyConstantInitializers
              )
        else {
            return nil
        }
        let constant = propertyConstantInitializers[chosen] ?? sema.symbols.constValueExprKind(for: chosen)
        guard let constant else { return nil }
        if requireNonNullableReceiver {
            guard let receiverType = sema.bindings.exprTypes[receiverExpr],
                  receiverType == sema.types.makeNonNullable(receiverType)
            else {
                return nil
            }
        }
        let boundType = sema.bindings.exprTypes[exprID]
        let id = arena.appendExpr(constant, type: boundType ?? sema.types.anyType)
        instructions.append(.constValue(result: id, value: constant))
        return id
    }

    func shouldLowerPrimitiveInv(
        receiverExpr: ExprID,
        sema: SemaModule,
        nullableReceiverAllowed: Bool
    ) -> Bool {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let uintType = sema.types.make(.primitive(.uint, .nonNull))
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
        let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
        let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
        let byteType = sema.types.byteType
        let shortType = sema.types.shortType
        var receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        if nullableReceiverAllowed {
            receiverType = sema.types.makeNonNullable(receiverType)
        }
        return receiverType == intType || receiverType == longType || receiverType == uintType || receiverType == ulongType || receiverType == ubyteType || receiverType == ushortType || receiverType == byteType || receiverType == shortType
    }

    /// Whether `exprID`'s type is a primitive (numeric or Char), i.e. one of
    /// the types the built-in `kk_op_*` arithmetic intrinsics actually accept.
    /// A non-primitive argument (a user class, String, ...) means the callee
    /// name only *looks* like a primitive operator; the real applicable
    /// candidate is whatever Sema resolved (e.g. a user's
    /// `operator fun Int.times(v: Vec)` extension), so the primitive fast
    /// path in `shouldLowerPrimitiveInv`'s callers must not claim the call.
    func isNumericPrimitiveOperand(_ exprID: ExprID, sema: SemaModule) -> Bool {
        let type = sema.types.makeNonNullable(sema.bindings.exprTypes[exprID] ?? sema.types.anyType)
        if case .primitive = sema.types.kind(of: type) {
            return true
        }
        return false
    }

    func appendReceiverToMemberArguments(
        _ loweredReceiverID: KIRExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        chosenCallee: SymbolID?,
        prependReceiverForUnresolvedCollectionCall: Bool,
        sema: SemaModule,
        interner: StringInterner,
        arguments: inout [KIRExprID]
    ) {
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let calleeText = interner.resolve(calleeName)
        if sema.bindings.isRangeExpr(receiverExpr) {
            let rangeMembers: Set<String> = [
                "first", "last", "endExclusive", "step", "contains", "isEmpty", "sum", "count",
                "toList", "forEach", "map", "mapIndexed", "mapNotNull",
                "filter", "filterIndexed", "filterNot", "reduce", "reduceIndexed",
                "fold", "foldIndexed", "find", "findLast", "firstOrNull",
                "lastOrNull", "any", "all", "none", "chunked", "windowed",
                "reversed",
                "take", "drop", "average", "sorted",
                "random",
            ]
            if rangeMembers.contains(calleeText) {
                arguments.insert(loweredReceiverID, at: 0)
                return
            }
        }
        if let chosenCallee,
           let signature = sema.symbols.functionSignature(for: chosenCallee),
           signature.receiverType != nil
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        guard chosenCallee == nil,
              prependReceiverForUnresolvedCollectionCall
        else {
            return
        }
        if Self.unresolvedCollectionMemberNames.contains(calleeText) {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        // String.length: extension needs receiver even when chosenCallee is nil
        // (e.g. mapIndexed { _, v -> v.length } where type inference may not bind).
        // Always prepend receiver for "length"; codegen extracts the aggregate length
        // field when the receiver is String. Other types would be a type error at use site.
        if calleeText == "length" {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        // Enum.name / Enum.ordinal are source-backed properties whose values are
        // still materialized by compiler-owned per-enum helpers. When an older or
        // source-less stdlib surface leaves the property unresolved, prepend the
        // receiver so EnumNameAccessLoweringPass's generic (arguments.count == 1)
        // rewrite can recover the same residual path. Gate on the receiver being
        // enum-typed so unrelated "name"/"ordinal" members remain unaffected.
        if calleeText == "name" || calleeText == "ordinal",
           let (_, classSym) = resolveClassTypeSymbol(receiverType, sema: sema),
           classSym.kind == .enumClass
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
        let isCoroutineHandleReceiver = receiverClassifier.isCoroutineHandleReceiverType(receiverType)
        if isCoroutineHandleReceiver,
           Self.unresolvedCoroutineHandleMemberNames.contains(calleeText)
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        let isChannelReceiver = receiverClassifier.isChannelReceiverType(receiverType)
        if isChannelReceiver,
           Self.unresolvedChannelMemberNames.contains(calleeText)
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
        if Self.unresolvedFlowMemberNames.contains(calleeText),
           isFlowReceiverType(receiverType, sema: sema, interner: interner)
        {
            arguments.insert(loweredReceiverID, at: 0)
            return
        }
    }

    func emitMemberCallInstruction(
        normalized: NormalizedCallResult,
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        receiver: MemberCallReceiver,
        result: KIRExprID,
        isSuperCall: Bool,
        qualifiedSuperType: SymbolID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: [KIRExprID],
        sourceArgExprs: [ExprID] = [],
        sourceArgLabels: [InternedString?] = [],
        callExprID: ExprID? = nil
    ) {
        let knownNames = KnownCompilerNames(interner: interner)
        var finalArguments = arguments
        let memberExtensionDispatchReceiver = chosenCallee.flatMap {
            self.memberExtensionDispatchReceiver(
                for: $0,
                callExprID: callExprID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        if let memberExtensionDispatchReceiver {
            finalArguments.insert(memberExtensionDispatchReceiver, at: 0)
        }
        if let chosenCallee,
           let localValue = driver.ctx.localValue(for: chosenCallee),
           let callable = driver.ctx.callableValueInfo(for: localValue)
        {
            finalArguments.insert(contentsOf: callable.captureArguments, at: 0)
        }
        if let chosenCallee,
           let scopeBuilderLink = sema.symbols.externalLinkName(for: chosenCallee),
           (scopeBuilderLink == "kk_coroutine_scope_async" || scopeBuilderLink == "__kk_coroutine_scope_launch_context"),
           finalArguments.count == 4
        {
            for parameterIndex in 0 ..< 2 where normalized.defaultMask & (1 << parameterIndex) != 0 {
                let zero = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zero, value: .intLiteral(0)))
                finalArguments[parameterIndex + 1] = zero
            }
            if let handleSymbol = sema.symbols.lookupAll(fqName: ["kotlinx", "coroutines", "__kkScopeHandle"].map { interner.intern($0) }).first(where: {
                   sema.symbols.symbol($0)?.kind == .function
               }),
               let handleInfo = sema.symbols.symbol(handleSymbol)
            {
                let scopeHandle = arena.appendTemporary(type: sema.types.anyType)
                instructions.append(.call(
                    symbol: handleSymbol,
                    callee: handleInfo.name,
                    arguments: [finalArguments[0]],
                    result: scopeHandle,
                    canThrow: true,
                    thrownResult: nil
                ))
                finalArguments[0] = scopeHandle
            }
            // Keep captures visible to suspend liveness before launcher rewriting.
            finalArguments.append(contentsOf: driver.ctx.callableValueInfo(for: finalArguments[3])?.captureArguments ?? [])
            instructions.append(.call(
                symbol: chosenCallee, callee: interner.intern(scopeBuilderLink),
                arguments: finalArguments, result: result,
                canThrow: false, thrownResult: nil
            ))
            return
        }
        // Enum entry implementations are stored as ordinary functions whose
        // first argument is the ordinal-backed enum value. Route the resolved
        // enum member through the predeclared ordinal dispatcher before any
        // runtime-name or virtual-dispatch rewriting can select the abstract
        // declaration itself.
        //
        // BUG-A: `chosenCallee` may name a *shared* base (`kotlin.Enum.toString`,
        // or any interface member) that more than one enum class in this
        // compilation registers entry-body dispatch for. A single
        // base-symbol-keyed reverse lookup (`SymbolID -> dispatch helper`)
        // would have the second such enum processed silently overwrite the
        // first's registration. Resolve the helper directly under the
        // *receiver's own* enum class fqName instead (deterministic from
        // `chosenCallee`'s mangled name, same as `enumToStringOverrideHelper`),
        // so `firstEnum.X.toString()` and `secondEnum.Y.toString()` never
        // cross-resolve to each other's dispatch helper.
        if normalized.defaultMask == 0,
           !isSuperCall,
           let chosenCallee,
           let chosenCalleeInfo = sema.symbols.symbol(chosenCallee),
           let receiverType = sema.bindings.exprTypes[receiver.expr],
           let (_, receiverClassSymbol) = resolveClassTypeSymbol(
               sema.types.makeNonNullable(receiverType), sema: sema
           ),
           receiverClassSymbol.kind == .enumClass,
           let dispatchSymbol = {
               let helperName = NameMangler.enumEntryDispatchHelperName(for: chosenCalleeInfo, interner: interner)
               return sema.symbols.lookupAll(fqName: receiverClassSymbol.fqName + [helperName]).first { id in
                   sema.symbols.symbol(id).map { $0.kind == .function } ?? false
               }
           }(),
           let dispatchInfo = sema.symbols.symbol(dispatchSymbol),
           let dispatchSignature = sema.symbols.functionSignature(for: dispatchSymbol),
           dispatchSignature.typeParameterSymbols.isEmpty,
           dispatchSignature.reifiedTypeParameterIndices.isEmpty,
           !dispatchSignature.isSuspend,
           finalArguments.first == receiver.loweredID
        {
            instructions.append(.call(
                symbol: dispatchSymbol,
                callee: dispatchInfo.name,
                arguments: finalArguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return
        }
        // Enum values are raw ordinals while they remain statically enum-typed.
        // Enum.equals(Any?) is an Any-boundary call, so box the receiver with
        // its nominal class ID before reaching the shared Any bridge. Without
        // this, Direction.NORTH.equals(Color.RED) compares two bare ordinals
        // and incorrectly reports equality for matching entry positions.
        if finalArguments.first == receiver.loweredID,
           let chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_any_member_equals",
           let receiverType = sema.bindings.exprTypes[receiver.expr],
           let (receiverClassType, receiverClassSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
           receiverClassType.nullability == .nonNull,
           receiverClassSymbol.kind == .enumClass,
           !receiverClassSymbol.flags.contains(.synthetic)
        {
            let boxedReceiver = arena.appendTemporary(type: sema.types.anyType)
            emitEnumOrdinalBoxCall(
                ordinal: receiver.loweredID,
                classSymbol: receiverClassType.classSymbol,
                result: boxedReceiver,
                resultType: sema.types.anyType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                into: &instructions
            )
            finalArguments[0] = boxedReceiver
        }
        let hasHOFLambdaArg = sourceArgExprs.contains { sema.bindings.isCollectionHOFLambdaExpr($0) }
        // Must run before the "$default" stub dispatch below (which returns
        // early): the stub forwards its own `transform`-shaped parameter
        // straight to the real source-backed function (e.g.
        // `Sequence.windowed(size, step = 1, partialWindows = false,
        // transform)`), which expects the normal wrapped function-value
        // convention. Without materializing here, a call like
        // `windowed(3) { it.sum() + bonus }` (defaults skipped, so this path
        // is taken) forwarded the lambda as a bare, unwrapped symbol
        // reference -- fine for a non-capturing lambda (closureRaw is unused
        // either way), but silently dropping any captured values (`bonus`)
        // for one that does capture, since nothing ever threaded the actual
        // closure environment through.
        // Member-extension calls carry TWO leading receiver slots here --
        // [dispatch, extension, ...valueArgs] once the dispatch receiver was
        // inserted above -- while the callee signature counts only the
        // extension receiver. Without the override, value-parameter index 0
        // (e.g. a `suspend (E) -> R` block) would be matched against the
        // extension receiver slot, so its function value silently stayed a
        // raw `symbolRef` and crossed the kklib boundary with an ABI the
        // callee's kk_suspend_function_invoke cannot drive (aggregate
        // params, KUU-962).
        adaptCoroutineLauncherBlock(
            chosenCallee: chosenCallee,
            sourceArgExprs: sourceArgExprs,
            sema: sema, arena: arena, interner: interner,
            instructions: &instructions, arguments: &finalArguments
        )
        // Kotlin coroutine builders accept a suspend function as their extension
        // receiver. Preserve the same boxed callable ABI as value parameters.
        if let chosenCallee,
           sema.symbols.isSourceBackedSymbol(chosenCallee),
           let receiverType = sema.symbols.functionSignature(for: chosenCallee)?.receiverType,
           case let .functionType(functionType) = sema.types.kind(of: receiverType),
           functionType.isSuspend,
           sema.symbols.symbol(chosenCallee)?.flags.contains(.inlineFunction) != true {
            let receiverIndex = memberExtensionDispatchReceiver == nil ? 0 : 1
            finalArguments[receiverIndex] = materializeFunctionValueArgument(
                loweredArgID: finalArguments[receiverIndex],
                argExprID: receiver.expr,
                functionType: functionType,
                sema: sema, arena: arena, interner: interner,
                instructions: &instructions
            )
        }
        materializeSourceBackedFunctionValueArguments(
            chosenCallee: chosenCallee,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: &finalArguments,
            valueArgOffsetOverride: memberExtensionDispatchReceiver != nil ? 2 : nil
        )
        if normalized.defaultMask != 0,
           let chosenCallee,
           let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee),
           externalLinkName.hasSuffix("_joinToString")
        {
            materializeJoinToStringDefaultArguments(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if normalized.defaultMask != 0,
           let chosenCallee
        {
            // KUU-655: an override that inherits its defaults never has its
            // own stub; resolve to the base declaration's stub instead (see
            // `defaultStubOwnerSymbol`).
            let stubOwner = driver.callSupportLowerer.defaultStubOwnerSymbol(for: chosenCallee, sema: sema)
            if sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty ?? true ||
                sema.symbols.externalLinkName(for: driver.callSupportLowerer.defaultStubSymbol(for: stubOwner)) != nil
            {
                appendReifiedTypeTokens(
                    chosenCallee: chosenCallee,
                    callBinding: callBinding,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions,
                    arguments: &finalArguments
                )
                // KUU-655: a `super.f()` call that omits a defaulted
                // argument must resolve the default *and* dispatch
                // statically to the overridden implementation, never
                // virtually to the runtime type's own override -- see the
                // reserved mask bit 30 decoded in
                // `CallSupportLowerer.generateDefaultStubFunction`.
                let effectiveMask = isSuperCall ? (normalized.defaultMask | (Int64(1) << 30)) : normalized.defaultMask
                appendDefaultMaskArgument(
                    effectiveMask,
                    sema: sema,
                    arena: arena,
                    instructions: &instructions,
                    arguments: &finalArguments
                )
                let stubName = interner.intern(interner.resolve(calleeName) + "$default")
                let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: stubOwner)
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))
                return
            }
        }

        appendReifiedTypeTokens(
            chosenCallee: chosenCallee,
            callBinding: callBinding,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions,
            arguments: &finalArguments
        )

        let loweredCallee = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            receiverExpr: receiver.expr,
            argumentCount: finalArguments.count,
            sourceArgumentCount: sourceArgExprs.count,
            hasHOFLambdaArg: hasHOFLambdaArg,
            sema: sema,
            interner: interner
        )
        let loweredCalleeText = interner.resolve(loweredCallee)
        if loweredCalleeText == "__kk_double_range_contains",
           sourceArgExprs.count == 1,
           finalArguments.count >= 2,
           sema.types.makeNonNullable(
               sema.bindings.exprTypes[sourceArgExprs[0]] ?? sema.types.anyType
           ) == sema.types.floatType
        {
            // OpenEndRange<Double>.contains(Float) widens the argument before
            // reaching the Double range ABI; the raw Float bits are not a valid
            // Double bit pattern and must not be passed through unchanged.
            let converted = arena.appendTemporary(type: sema.types.doubleType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_float_to_double_bits"),
                arguments: [finalArguments[1]],
                result: converted,
                canThrow: false,
                thrownResult: nil
            ))
            finalArguments[1] = converted
        }
        // KUU-600: Regex.replace's transform uses the runtime callback ABI.
        // Its Kotlin function-value argument must be split into the raw
        // function pointer and closure environment expected by the bridge.
        if loweredCalleeText == "__kk_regex_replace_lambda",
           finalArguments.count == 3,
           sourceArgExprs.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], finalArguments[1], fnPtrExpr, envPtrExpr]
        }
        if (loweredCalleeText == "kk_coroutine_scope_launch" || loweredCalleeText == "kk_coroutine_scope_async"),
           !finalArguments.isEmpty,
           let handleSymbol = sema.symbols.lookupAll(fqName: ["kotlinx", "coroutines", "__kkScopeHandle"].map { interner.intern($0) }).first(where: {
               sema.symbols.symbol($0)?.kind == .function
           }),
           let handleInfo = sema.symbols.symbol(handleSymbol)
        {
            let scopeHandle = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: handleSymbol,
                callee: handleInfo.name,
                arguments: [finalArguments[0]],
                result: scopeHandle,
                canThrow: true,
                thrownResult: nil
            ))
            finalArguments[0] = scopeHandle
        }
        // BUG-049: `CoroutineScope.launch { block }` where `block` captures outer
        // variables. The receiver scope is finalArguments[0] and the suspend lambda
        // reference is finalArguments[1]; inject the lambda's captures after it so the
        // coroutine lowering can thread them through the continuation (mirrors the free
        // launch/withContext capture injection in CallLowerer).
        if loweredCalleeText == "kk_coroutine_scope_launch",
           finalArguments.count >= 2,
           let callableInfo = driver.ctx.callableValueInfo(for: finalArguments[1]),
           !callableInfo.captureArguments.isEmpty
        {
            finalArguments.insert(contentsOf: callableInfo.captureArguments, at: 2)
        }
        // A source-backed HashSet declaration is only the semantic target. Its
        // runtime representation is a RuntimeSetBox, so a remapped set
        // operation must not retain the source symbol for NativeEmitter's
        // internal-function lookup; that would bypass the runtime ABI callee.
        let runtimeSetMemberCallee = runtimeBackedSetMemberCallee(
            memberName: interner.resolve(calleeName),
            receiverType: sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType,
            chosenCallee: chosenCallee,
            sema: sema,
            interner: interner
        )
        let receiverType = sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType
        let runtimeProgressionMemberCallee = runtimeBackedULongProgressionMemberCallee(
            memberName: interner.resolve(calleeName),
            receiverType: receiverType,
            sema: sema,
            interner: interner
        )
        let usesRuntimeSetMember = runtimeSetMemberCallee.map { $0 == loweredCallee } == true
            && isSourceBackedHashSetType(receiverType, sema: sema, interner: interner)
        let usesRuntimeProgressionMember = runtimeProgressionMemberCallee.map { $0 == loweredCallee } == true
        let rangeInterfaceCallee = closedRangeInterfaceRuntimeName(
            memberName: interner.resolve(calleeName),
            receiverExpr: receiver.expr,
            receiverType: receiverType,
            chosenCallee: chosenCallee,
            sema: sema,
            interner: interner
        )
        let usesRuntimeRangeMember = rangeInterfaceCallee.map { $0 == loweredCallee } == true
        // Remapped runtime bridges must not retain a source symbol whose own
        // external link would override the concrete runtime callee.
        let callSymbol: SymbolID? = usesRuntimeSetMember || usesRuntimeProgressionMember || usesRuntimeRangeMember
            ? nil
            : chosenCallee
        // KSP-641: ClosedFloatingPointRange members are still compiler residuals,
        // so lower the concrete Double/Float overload directly to the range ABI.
        // The source-backed generic declaration remains available for overload
        // resolution, while this path preserves the stdlib's empty-range and NaN
        // behavior without dispatching synthetic range accessors through an
        // unpopulated itable.
        if calleeName == knownNames.coerceIn,
           sourceArgExprs.count == 1,
           sema.bindings.isFloatingPointRangeExpr(sourceArgExprs[0])
        {
            let receiverType = sema.types.makeNonNullable(
                sema.bindings.exprTypes[receiver.expr] ?? sema.types.anyType
            )
            let floatingRangeCallee: InternedString? = if receiverType == sema.types.floatType {
                interner.intern("__kk_float_coerceIn_range")
            } else if receiverType == sema.types.doubleType {
                interner.intern("__kk_double_coerceIn_range")
            } else {
                nil
            }
            if let floatingRangeCallee {
                var rangeArguments = finalArguments
                if rangeArguments.count == 1 {
                    rangeArguments.insert(receiver.loweredID, at: 0)
                }
                guard rangeArguments.count == 2 else {
                    preconditionFailure("KSP-641 range coerceIn must lower to receiver and range arguments")
                }
                let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: floatingRangeCallee,
                    arguments: rangeArguments,
                    result: result,
                    canThrow: true,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))
                let continueLabel = driver.ctx.makeLoopLabel()
                let rethrowLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
                instructions.append(.jump(continueLabel))
                instructions.append(.label(rethrowLabel))
                instructions.append(.rethrow(value: thrownResult))
                instructions.append(.label(continueLabel))
                return
            }
        }
        if loweredCalleeText == "kk_worker_execute",
           finalArguments.count == 4,
           sourceArgExprs.count == 3
        {
            let producerArgs = makeClosureThunkExpandedArguments(
                loweredArgID: finalArguments[2],
                argExprID: sourceArgExprs[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let jobArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[3],
                argExprID: sourceArgExprs[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], finalArguments[1]] + producerArgs + jobArgs
        }
        if loweredCalleeText == "kk_worker_execute_after",
           finalArguments.count == 3,
           sourceArgExprs.count == 2
        {
            let operationArgs = makeClosureThunkExpandedArguments(
                loweredArgID: finalArguments[2],
                argExprID: sourceArgExprs[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], finalArguments[1]] + operationArgs
        }
        // CoroutineContext.fold(initial, operation): the kk_context_fold cdecl
        // takes (contextRaw, initial, fnPtr, closureRaw, outThrown), so the
        // operation lambda must expand to a (fnPtr, closureRaw) pair like the
        // collection-HOF callable arguments.
        if loweredCalleeText == "kk_context_fold",
           finalArguments.count == 3,
           sourceArgExprs.count == 2
        {
            let operationArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[2],
                argExprID: sourceArgExprs[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], finalArguments[1]] + operationArgs
        }
        let isComparatorBinarySearch: Bool = {
            guard loweredCalleeText == "binarySearch",
                  let chosenCallee,
                  let signature = sema.symbols.functionSignature(for: chosenCallee)
            else {
                return false
            }
            return signature.parameterTypes.contains { parameterType in
                guard let (_, symbol) = resolveClassTypeSymbol(parameterType, sema: sema)
                else {
                    return false
                }
                return symbol.name == knownNames.comparator
            }
        }()
        if isComparatorBinarySearch {
            materializeBinarySearchDefaultArguments(
                normalized.defaultMask,
                receiverExpr: receiver.expr,
                loweredReceiverID: receiver.loweredID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments,
                sourceArgLabels: sourceArgLabels
            )
        }
        finalArguments = adaptComparatorBackedCollectionArguments(
            loweredCallee: loweredCallee,
            finalArguments: finalArguments,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if normalized.defaultMask != 0,
           loweredCalleeText == "__kk_byteArray_toKString"
        {
            materializeByteArrayToKStringDefaultArguments(
                normalized.defaultMask,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArguments
            )
        }
        if loweredCalleeText == "kk_list_zip_transform",
           finalArguments.count == 3
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments[2] = fnPtrExpr
            finalArguments.append(envPtrExpr)
        }
        let isStringRuntimeHOFCallee = switch loweredCalleeText {
        case "kk_string_indexOfFirst",
             "kk_string_indexOfLast":
            true
        default:
            false
        }
        if isStringRuntimeHOFCallee,
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if loweredCalleeText == "kk_sequence_firstNotNullOf"
            || loweredCalleeText == "kk_sequence_firstNotNullOfOrNull"
            || loweredCalleeText == "kk_sequence_indexOfFirst"
            || loweredCalleeText == "kk_sequence_takeLastWhile"
            || loweredCalleeText == "kk_sequence_indexOfLast",
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if loweredCalleeText == "kk_sequence_elementAtOrElse",
           finalArguments.count == 3
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[2],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], finalArguments[1], fnPtrExpr, envPtrExpr]
        }
        if loweredCalleeText == "__kk_iterable_firstNotNullOf"
            || loweredCalleeText == "__kk_iterable_firstNotNullOfOrNull"
            || loweredCalleeText == "__kk_iterable_any"
            || loweredCalleeText == "__kk_iterable_all",
           finalArguments.count == 2
        {
            let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                finalArguments[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0], fnPtrExpr, envPtrExpr]
        }
        if Self.resultFunction1CalleeNames.contains(loweredCalleeText),
           finalArguments.count == 2,
           sourceArgExprs.count == 1
        {
            let callbackArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[1],
                argExprID: sourceArgExprs[0],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0]] + callbackArgs
        }
        if loweredCalleeText == "kk_runtime_result_fold",
           finalArguments.count == 3,
           sourceArgExprs.count == 2
        {
            let successArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[1],
                argExprID: sourceArgExprs[0],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let failureArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: finalArguments[2],
                argExprID: sourceArgExprs[1],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArguments = [finalArguments[0]] + successArgs + failureArgs
        }
        if loweredCalleeText == "kk_channel_send"
            || loweredCalleeText == "kk_channel_receive"
            || loweredCalleeText == "kk_mutex_lock"
            || loweredCalleeText == "__kk_mutex_lock_owner"
            || loweredCalleeText == "kk_semaphore_acquire"
        {
            let continuationExpr = arena.appendExpr(
                .intLiteral(0),
                type: sema.types.intType
            )
            instructions.append(.constValue(result: continuationExpr, value: .intLiteral(0)))
            finalArguments.append(continuationExpr)
        }
        // KSP-677: Mutex.withLock / Semaphore.withPermit / Lock.withLock are Kotlin
        // source (Stdlib/kotlinx/coroutines/sync/Sync.kt, Stdlib/kotlin/concurrent/Lock.kt).
        // The Mutex/Semaphore helpers compose lock()/unlock() and acquire()/release();
        // Lock.withLock delegates to the demoted __kk_lock_withLock bridge via the general
        // closure-taking ABI, so none of them need a dedicated closure-conversion branch.
        // Skip virtual dispatch when loweredMemberCalleeName remapped the callee
        // to a concrete runtime function (e.g. iterator → kk_list_iterator).
        // Virtual dispatch is only correct when no remapping occurred; a
        // declaration imported from a precompiled library is always named by
        // its own mangled link name, which is not such a remapping. KSP-611: for
        // an abstract imported interface member that link name is an empty stub,
        // so itable dispatch must be attempted there as well;
        // tryEmitVirtualDispatch falls back to the link name when the receiver
        // has no resolvable itable entry.
        // Source-backed ListIterator inherits hasNext/next from Iterator, but
        // loweredMemberCalleeName intentionally retains those names so the
        // implementation can be selected through its dynamic itable.
        let listIteratorInheritedDispatch = listIteratorInheritedDispatchCallee(
            receiverType: sema.bindings.exprTypes[receiver.expr],
            calleeName: loweredCallee,
            sema: sema,
            interner: interner
        ) != nil
        let isImportedLibraryLink = chosenCallee.map { symbol in
            // Imported source-backed interface members (kk_fn_* links) still
            // need itable dispatch, but runtime-bridged interface members must
            // call their ABI entry point directly. The latter can now be
            // source-declared and serialized into a stdlib artifact (for
            // example Collection.isEmpty), so treating every imported
            // interface link as virtual dispatch breaks runtime collection
            // boxes that intentionally have no Kotlin itable entry.
            let linkMatches = sema.symbols.externalLinkName(for: symbol)
                .map { interner.intern($0) == loweredCallee } == true
            return linkMatches && !kirIsRuntimeBridgedCallee(symbol, sema: sema)
        } ?? false
        let isRuntimeBridgedCallee = chosenCallee.map {
            kirIsRuntimeBridgedCallee($0, sema: sema)
        } ?? false
        if (loweredCallee == calleeName && !isRuntimeBridgedCallee)
            || listIteratorInheritedDispatch
            || isImportedLibraryLink
            || chosenCallee.map({ isClockRuntimeVirtualBridge($0, sema: sema) }) == true
            || chosenCallee.map({
                isIteratorRuntimeVirtualBridge(
                    $0,
                    receiverTypeID: sema.bindings.exprTypes[receiver.expr],
                    sema: sema,
                    interner: interner
                )
            }) == true,
           let inst = tryEmitVirtualDispatch(
               chosenCallee: chosenCallee, calleeName: loweredCallee,
               receiverExpr: memberExtensionDispatchReceiver == nil ? receiver.expr : nil,
               loweredReceiverID: memberExtensionDispatchReceiver ?? receiver.loweredID,
               isSuperCall: isSuperCall, finalArguments: finalArguments,
               result: result, sema: sema, arena: arena, interner: interner
           )
        {
            // KUU-763: floating-point range boxes carry no itable, so
            // interface-typed `ClosedFloatingPointRange`/`ClosedRange` member
            // calls probe the runtime representation before dispatching.
            if let probeEndLabel = emitFloatingPointRangeMemberProbe(
                chosenCallee: chosenCallee,
                receiverID: memberExtensionDispatchReceiver ?? receiver.loweredID,
                sourceReceiverID: receiver.loweredID,
                arguments: finalArguments,
                result: result,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) {
                instructions.append(inst)
                instructions.append(.label(probeEndLabel))
            } else {
                instructions.append(inst)
            }
            return
        }
        var callArguments = finalArguments
        if let chosenCallee, runtimeExternalOmitsObjectReceiver(chosenCallee, sema: sema) {
            callArguments = Array(callArguments.dropFirst())
        } else if loweredCalleeText == "__kk_system_currentTimeMillis"
            || loweredCalleeText == "__kk_system_nanoTime"
            || loweredCalleeText == "__kk_system_process_start_nanos"
            || loweredCalleeText == "__kk_system_gc"
            || loweredCalleeText == "__kk_runtime_getRuntime"
            || loweredCalleeText == "__kk_runtime_totalMemory"
            || loweredCalleeText == "__kk_runtime_freeMemory"
            || loweredCalleeText == "__kk_runtime_maxMemory"
            || loweredCalleeText == "kk_instant_now"
            || loweredCalleeText == "kk_clock_system_now" {
            callArguments = []
        }
        if let bridgeCall = listWindowChunkMemberSourceBridgeCall(
            chosenCallee: chosenCallee,
            calleeName: loweredCallee,
            receiverExpr: receiver.expr,
            argumentCount: callArguments.count,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            interner: interner
        ) {
            var bridgeArguments = callArguments
            // The `*_transform` bridges store the callback's raw return into
            // `List<R>` verbatim. When the args were already expanded to a
            // `(fnPtr, closureRaw)` pair, the fnPtr still has to present the
            // erased-`R` (boxed) ABI — re-split it through the adapter so a
            // concrete Boolean/Char result does not render as `0`/`1`
            // (KUU-1434).
            if bridgeCall.callee == interner.intern("__kk_list_chunked_transform")
                || bridgeCall.callee == interner.intern("__kk_list_windowed_transform")
                || bridgeCall.callee == interner.intern("__kk_list_zip_transform")
                || bridgeCall.callee == interner.intern("__kk_list_zipWithNextTransform"),
               bridgeArguments.count >= 3,
               let transformArgExprID = sourceArgExprs.last
            {
                let split = splitErasedTransformBridgeArgument(
                    bridgeArguments[bridgeArguments.count - 2],
                    existingEnvPtrID: bridgeArguments[bridgeArguments.count - 1],
                    argExprID: transformArgExprID,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                bridgeArguments[bridgeArguments.count - 2] = split.fnPtrExpr
                bridgeArguments[bridgeArguments.count - 1] = split.envPtrExpr
            }
            instructions.append(.call(
                symbol: nil,
                callee: bridgeCall.callee,
                arguments: bridgeArguments,
                result: result,
                canThrow: bridgeCall.canThrow,
                thrownResult: bridgeCall.canThrow ? arena.appendTemporary(type: sema.types.nullableAnyType) : nil,
                isSuperCall: isSuperCall,
                qualifiedSuperType: qualifiedSuperType
            ))
            return
        }
        let throwingCallees = Self.throwingMemberCalleeNames
        let needsOutThrown = needsThrownChannel(calleeName: loweredCallee, interner: interner)
        let thrownResult: KIRExprID? = needsOutThrown
            ? arena.appendTemporary(type: sema.types.nullableAnyType)
            : nil
        let canThrow = throwingCallees.contains(loweredCalleeText) || thrownResult != nil
        instructions.append(.call(
            symbol: callSymbol,
            callee: loweredCallee,
            arguments: callArguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult,
            isSuperCall: isSuperCall,
            qualifiedSuperType: qualifiedSuperType
        ))
        if let thrownResult,
           shouldRethrowThrownChannelResult(calleeName: loweredCallee, interner: interner)
        {
            let continueLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
            instructions.append(.jump(continueLabel))
            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: thrownResult))
            instructions.append(.label(continueLabel))
        }
    }

    /// Runtime callee names whose `.call` should be emitted with
    /// `canThrow: true`.
    private static let throwingMemberCalleeNames: Set<String> = [
        "kk_list_random",
        "kk_iterable_iterator",
        "kk_iterator_next",
        "kk_list_iterator_next",
        "kk_sequence_takeLast",
        "__kk_iterable_firstNotNullOf",
        "__kk_iterable_firstNotNullOfOrNull",
        "__kk_iterable_any",
        "__kk_iterable_all",
        "__kk_iterable_requireNoNulls",
        "__kk_string_codePointCount_from",
        "__kk_string_codePointCount_range",
        "__kk_kclass_cast",
        "kk_range_first_predicate",
        "kk_range_last_predicate",
        "__kk_range_first_orThrow",
        "__kk_range_last_orThrow",
        "__kk_uint_range_first_orThrow",
        "__kk_uint_range_last_orThrow",
        "__kk_ulong_range_first_orThrow",
        "__kk_ulong_range_last_orThrow",
        "__kk_range_random",
        "__kk_range_random_random",
        "__kk_char_range_random",
        "__kk_char_range_random_random",
        "__kk_random_nextInt_rangeObject",
        "__kk_random_nextLong_rangeObject",
        "kk_range_reduce",
        "kk_range_reduceIndexed",
        "__kk_long_range_random",
        "__kk_long_range_random_random",
        "__kk_uint_range_random",
        "__kk_uint_range_random_random",
        "__kk_ulong_range_random",
        "__kk_ulong_range_random_random",
        "__kk_int_progression_fromClosedRange",
        "__kk_long_progression_fromClosedRange",
        "__kk_uint_progression_fromClosedRange",
        "__kk_ulong_progression_fromClosedRange",
        "__kk_char_progression_fromClosedRange",
        "__kk_op_step",
        "__kk_char_range_step",
        "kk_sequence_reduceOrNull",
        "kk_sequence_reduceRight",
        "kk_sequence_reduce",
        "kk_sequence_scan",
        "kk_sequence_reduceIndexed",
        "kk_sequence_reduceIndexedOrNull",
        "kk_sequence_reduceRightIndexed",
        "kk_sequence_reduceRightOrNull",
        "kk_sequence_reduceRightIndexedOrNull",
        "kk_sequence_runningFold",
        "kk_sequence_runningReduceIndexed",
        "kk_sequence_sortedBy",
        "kk_sequence_sortedByDescending",
        "kk_sequence_takeLastWhile",
        "kk_sequence_firstNotNullOf",
        "kk_sequence_firstNotNullOfOrNull",
        "kk_sequence_indexOfFirst",
        "kk_sequence_indexOfLast",
        "kk_map_mapKeysTo",
        "kk_map_mapValuesTo",
        "kk_sequence_mapNotNull",
        "kk_sequence_mapIndexedNotNull",
        "kk_sequence_mapIndexed",
        "kk_sequence_filterIndexed",
        "kk_sequence_elementAt",
        "kk_sequence_min",
        "kk_sequence_ifEmpty",
        "kk_sequence_first",
        "kk_sequence_random",
        "kk_sequence_last",
        "kk_sequence_max",
        "kk_sequence_firstOrNull",
        "kk_sequence_single",
        "kk_sequence_singleOrNull",
        "kk_sequence_randomOrNull",
        "kk_sequence_count",
        "kk_sequence_to_list",
        "kk_sequence_runningFoldIndexed",
        "kk_sequence_scanIndexed",
    ]

    /// Runtime callee names whose `Result`-style callbacks expand inline.
    private static let resultFunction1CalleeNames: Set<String> = [
        "kk_runtime_result_get_or_else",
        "kk_runtime_result_map",
        "kk_runtime_result_on_success",
        "kk_runtime_result_on_failure",
        "kk_runtime_result_recover",
        "kk_runtime_result_recover_catching",
    ]

    private func listWindowChunkMemberSourceBridgeCall(
        chosenCallee: SymbolID?,
        calleeName: InternedString,
        receiverExpr: ExprID,
        argumentCount: Int,
        sourceArgExprs: [ExprID],
        sema: SemaModule,
        interner: StringInterner
    ) -> (callee: InternedString, canThrow: Bool)? {
        let receiverType = sema.types.makeNonNullable(sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType)
        let isListWindowChunkReceiver = isConcreteListLikeType(receiverType, sema: sema, interner: interner)
            || isSetLikeType(receiverType, sema: sema, interner: interner)
            || isIterableOrCollectionInterfaceType(receiverType, sema: sema, interner: interner)
            || isConcreteArrayLikeType(receiverType, sema: sema, interner: interner)
        let knownNames = KnownCompilerNames(interner: interner)
        guard isListWindowChunkReceiver else {
            return nil
        }

        if calleeName == knownNames.zip,
           let chosenCallee,
           sema.symbols.isSourceBackedSymbol(chosenCallee),
           let declaredReceiver = sema.symbols.functionSignature(for: chosenCallee)?.receiverType,
           isConcreteArrayLikeType(declaredReceiver, sema: sema, interner: interner)
        {
            // Array and primitive-array zip extensions use their selected
            // Kotlin bodies, including overloads whose argument is an Iterable.
            return nil
        }

        if calleeName == knownNames.zip,
           let firstArgument = sourceArgExprs.first,
           let firstArgumentType = sema.bindings.exprTypes[firstArgument],
           isGenericKotlinArrayType(
               sema.types.makeNonNullable(firstArgumentType),
               sema: sema,
               interner: interner
           )
        {
            // KSP-999: Array overloads execute the bundled Kotlin source body;
            // the materializing Iterable bridge is retained for Iterable inputs.
            return nil
        }

        let callee: String
        let canThrow: Bool
        switch (calleeName, argumentCount) {
        case (knownNames.chunked, 2):
            callee = "__kk_list_chunked"
            canThrow = true
        case (knownNames.chunked, 4):
            callee = "__kk_list_chunked_transform"
            canThrow = true
        case (knownNames.windowed, 4):
            callee = "__kk_list_windowed"
            canThrow = true
        case (knownNames.windowed, 6):
            callee = "__kk_list_windowed_transform"
            canThrow = true
        case (knownNames.zip, 2):
            callee = "__kk_list_zip"
            canThrow = false
        case (knownNames.zip, 4):
            callee = "__kk_list_zip_transform"
            canThrow = true
        case (knownNames.zipWithNext, 1):
            callee = "__kk_list_zipWithNext"
            canThrow = false
        case (knownNames.zipWithNext, 3):
            callee = "__kk_list_zipWithNextTransform"
            canThrow = true
        default:
            return nil
        }
        return (interner.intern(callee), canThrow)
    }

    func splitCallableLambdaArgument(
        _ lambdaID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (fnPtrExpr: KIRExprID, envPtrExpr: KIRExprID) {
        let fnPtrExpr: KIRExprID
        let envPtrExpr: KIRExprID
        if let callableInfo = driver.ctx.callableValueInfo(for: lambdaID) {
            fnPtrExpr = arena.appendExpr(
                .symbolRef(callableInfo.symbol),
                type: sema.types.anyType
            )
            instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
            if callableInfo.captureArguments.count >= 2 {
                // Multi-capture: pack captures into a closure object.
                let intType = sema.types.intType
                let anyType = sema.types.anyType
                let kkObjectNew = interner.intern("kk_object_new")
                let kkArraySet = interner.intern("kk_array_set")
                let slotCount = Int64(2 + callableInfo.captureArguments.count)
                let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
                instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
                let classIDExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
                let closureObjExpr = arena.appendTemporary(type: anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: kkObjectNew,
                    arguments: [slotCountExpr, classIDExpr],
                    result: closureObjExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                for (captureIndex, captureArg) in callableInfo.captureArguments.enumerated() {
                    let fieldOffset = Int64(captureIndex + 2)
                    let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: intType)
                    instructions.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                    let unusedResult = arena.appendTemporary(type: anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: kkArraySet,
                        arguments: [closureObjExpr, offsetExpr, captureArg],
                        result: unusedResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                envPtrExpr = closureObjExpr
            } else if let closureRaw = callableInfo.captureArguments.first {
                envPtrExpr = closureRaw
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                envPtrExpr = zeroExpr
            }
        } else {
            // Fallback when callableValueInfo is unavailable (e.g. stored lambda /
            // function reference forwarded as an ordinary argument to a bundled
            // Kotlin-source HOF, which boxes it via kk_function_create_1 rather
            // than lowering it with the raw closure-trampoline shape). lambdaID
            // may be a boxed Function1 object or an already-raw function
            // reference; kk_function_value_fn_ptr/closure_raw resolve either
            // shape at runtime (naively treating a boxed value as a raw fnPtr
            // and invoking it directly crashes — see BUG-... Sequence
            // chunked/windowed transform).
            let intType = sema.types.intType
            let fnPtrResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_function_value_fn_ptr"),
                arguments: [lambdaID],
                result: fnPtrResult,
                canThrow: false,
                thrownResult: nil
            ))
            fnPtrExpr = fnPtrResult
            let closureRawResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_function_value_closure_raw"),
                arguments: [lambdaID],
                result: closureRawResult,
                canThrow: false,
                thrownResult: nil
            ))
            envPtrExpr = closureRawResult
        }
        return (fnPtrExpr, envPtrExpr)
    }
}
