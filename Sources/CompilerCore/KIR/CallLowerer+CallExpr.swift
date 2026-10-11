extension CallLowerer {
    /// True when the call resolved to the stdlib `kotlin.contextOf` intrinsic.
    /// A user-declared `contextOf()` resolves to its own symbol and must keep
    /// normal call lowering instead of being replaced by a context receiver.
    private func isStdlibContextOfCall(
        _ exprID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .symbol(symbol)? = sema.bindings.callableTarget(for: exprID),
              let resolved = sema.symbols.symbol(symbol)
        else {
            return false
        }
        return resolved.fqName.map { interner.resolve($0) } == ["kotlin", "contextOf"]
    }

    // swiftlint:disable:next cyclomatic_complexity
    func lowerCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // `contract { ... }` is a compiler-only DSL. Sema has already recorded
        // its effects, so lowering the builder lambda would create dead KIR
        // (including enum references such as InvocationKind.EXACTLY_ONCE)
        // with no runtime meaning and potentially undefined link symbols.
        if sema.bindings.stdlibSpecialCallKind(for: exprID) == .contract {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }

        // SAM constructor calls: `Transformer { ... }` — the single lambda
        // argument is already marked as a SAM conversion and no call binding
        // exists for the constructor (the callee name is the fun interface itself).
        // Lower the lambda directly; the SAM wrapper is produced by LambdaLowerer.
        // A regular function call with a single SAM-converted argument (e.g.
        // `useOp(::myCompare)`) must still call the function, so require the
        // absence of a call binding here.
        if args.count == 1,
           sema.bindings.isSamConversion(args[0].expr),
           sema.bindings.callBinding(for: exprID) == nil
        {
            return driver.lowerExpr(
                args[0].expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        // Invoke operator calls are lowered as member calls: the callee expr
        // becomes the receiver and the invoke method is the callee.
        if sema.bindings.isInvokeOperatorCall(exprID) {
            let invokeName = interner.intern("invoke")
            return lowerMemberCallExpr(
                exprID,
                receiverExpr: calleeExpr,
                calleeName: invokeName,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        if let loweredSuspendIntrinsic = lowerSuspendCoroutineUninterceptedOrReturnCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredSuspendIntrinsic
        }

        if let loweredRepeat = lowerRepeatCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredRepeat
        }

        if let loweredArrayConstructor = lowerArrayConstructorCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredArrayConstructor
        }

        if let loweredAtomicIntArrayFactory = lowerAtomicIntArrayFactoryCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredAtomicIntArrayFactory
        }

        if let loweredAtomicLongArrayFactory = lowerAtomicLongArrayFactoryCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredAtomicLongArrayFactory
        }

        if let loweredEnumValues = lowerEnumValuesCallExpr(
            exprID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return loweredEnumValues
        }

        if let loweredEnumEntries = lowerEnumEntriesCallExpr(
            exprID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return loweredEnumEntries
        }

        if let loweredEnumValueOf = lowerEnumValueOfCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredEnumValueOf
        }

        // REFL-005: typeOf<T>() — reified inline function returning KType
        if let loweredTypeOf = lowerTypeOfCallExpr(
            exprID,
            calleeExpr: calleeExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return loweredTypeOf
        }

        if let loweredComparison = lowerComparisonSpecialCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredComparison
        }

        if args.isEmpty,
           let callee = ast.arena.expr(calleeExpr),
           case let .nameRef(calleeName, _) = callee,
           calleeName == interner.intern("contextOf"),
           isStdlibContextOfCall(exprID, sema: sema, interner: interner)
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            if let contextValue = driver.ctx.contextReceiverValue(matching: boundType, sema: sema) {
                return contextValue
            }
            let fallback = arena.appendExpr(.unit, type: boundType)
            instructions.append(.constValue(result: fallback, value: .unit))
            return fallback
        }

        // --- Context helper: context(with, block) (STDLIB-KOTLIN-ROOT-CTX-001) ---
        if let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
           scopeKind == .scopeContext,
           args.count >= 2,
           args.count <= 23
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let loweredContextArguments = args.dropLast().map { contextArgument in
                driver.lowerExpr(
                    contextArgument.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[args.count - 1].expr) {
                let contextReceiverValues = zip(args.dropLast(), loweredContextArguments).map { argument, loweredExpr in
                    KIRLoweringContext.ContextReceiverValue(
                        type: sema.bindings.exprTypes[argument.expr] ?? sema.types.anyType,
                        exprID: loweredExpr
                    )
                }
                return driver.ctx.withContextReceiverValues(contextReceiverValues) {
                    driver.lowerExpr(
                        bodyExpr,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                }
            }
            let previousLambdaAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
                argumentExpr: args[args.count - 1].expr,
                argumentIndex: args.count - 1,
                ast: ast,
                sema: sema,
                callBinding: sema.bindings.callBinding(for: exprID),
                chosen: sema.bindings.callBinding(for: exprID)?.chosenCallee
            )
            let loweredLambdaID = driver.lowerExpr(
                args[args.count - 1].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            driver.ctx.pendingLambdaNonLocalReturnAllowance = previousLambdaAllowance

            let result = arena.appendTemporary(type: boundType
            )
            if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: info.captureArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                emitNonThrowingCall(
                    callee: interner.intern("invoke"),
                    arg: loweredLambdaID,
                    result: result,
                    into: &instructions
                )
            }
            return result
        }

        // --- kotlinx.cinterop.memScoped { } (KUU-1375) ---
        if let loweredMemScoped = lowerMemScopedCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMemScoped
        }

        let boundType = sema.bindings.exprTypes[exprID]
        let loweredCalleeExprID = driver.lowerExpr(
            calleeExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let loweredCallable = driver.ctx.callableValueInfo(for: loweredCalleeExprID)
            ?? chosen.flatMap { symbol in
                driver.ctx.localValue(for: symbol).flatMap { driver.ctx.callableValueInfo(for: $0) }
            }
        let callableValueCallBinding = sema.bindings.callableValueCalls[exprID]
        let sourceCalleeName: InternedString = if let callee = ast.arena.expr(calleeExpr), case let .nameRef(name, _) = callee {
            name
        } else if let loweredCallable {
            loweredCallable.callee
        } else {
            interner.intern("<unknown>")
        }
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
            defer {
                driver.ctx.pendingLambdaNonLocalReturnAllowance = previousAllowance
            }
            let rawArgID = driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            // Freeze each bare mutable-local argument immediately after
            // lowering it (e.g. `x` in `f(x, x++)`) so it observes its
            // value at the point it was evaluated, not any mutation a later
            // argument performs on the same variable. Anything else (a
            // literal, a lambda, a nested call, ...) is left untouched —
            // see needsEvaluationOrderFreeze's doc comment for why an
            // unconditional freeze here is unsafe for trailing-lambda
            // arguments to inline functions. Only worth it when a later
            // argument could actually mutate something (expressionMayMutateState).
            return needsEvaluationOrderFreeze(argument.expr, ast: ast, sema: sema)
                && anyExpressionMayMutateState(args[(argumentIndex + 1)...].map(\.expr), ast: ast)
                ? freezeEvaluationOrderOperand(rawArgID, arena: arena, instructions: &instructions)
                : rawArgID
        }
        let knownNames = KnownCompilerNames(interner: interner)
        // buildList, buildSet, and buildMap are fully Kotlinized (KSP-622, KSP-623)
        // and no longer use builder-DSL runtime lowering.
        if let loweredToList = tryLowerCollectionToListCall(
            sourceCalleeName: sourceCalleeName,
            args: args,
            loweredArgIDs: loweredArgIDs,
            boundType: boundType,
            sema: sema,
            arena: arena,
            interner: interner,
            knownNames: knownNames,
            instructions: &instructions
        ) {
            return loweredToList
        }
        if let loweredCollectionFactory = tryLowerCollectionFactoryCall(
            args: args,
            loweredArgIDs: loweredArgIDs,
            chosenCallee: chosen,
            boundType: boundType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            // Runtime factories like `linkedSetOf()` return concrete-class
            // boxes that never pass `kk_object_new`, so the constructor-site
            // vtable registrations never ran for them. Register the nominal
            // vtable implementations on the box so an open member dispatch
            // (e.g. `LinkedHashSet.size`) resolves instead of trapping at
            // `kk_vtable_lookup`. No-ops for interface-typed results.
            if let factoryResultClass = collectionFactoryResultClassSymbol(
                result: loweredCollectionFactory,
                boundType: boundType,
                arena: arena,
                sema: sema
            ) {
                appendFactoryObjectVtableMethodRegistrations(
                    objectValue: loweredCollectionFactory,
                    nominalSymbol: factoryResultClass,
                    sema: sema,
                    cache: driver.ctx.nominalDispatchCache,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            return loweredCollectionFactory
        }
        // Numeric conversions take no value parameters, so a resolved callee
        // that consumes the single argument (e.g. an implicit-receiver
        // `toInt(radix)` inside a `String` extension) is a real call, not a
        // conversion of that argument.
        let chosenConsumesArgument = chosen
            .flatMap { sema.symbols.functionSignature(for: $0) }
            .map { $0.parameterTypes.count == args.count } ?? false
        if args.count == 1,
           !chosenConsumesArgument,
           let loweredNumericConversion = lowerTopLevelNumericConversionCall(
               sourceCalleeName: sourceCalleeName,
               argumentExpr: args[0].expr,
               loweredArgumentID: loweredArgIDs[0],
               boundType: boundType ?? sema.types.anyType,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return loweredNumericConversion
        }
        return lowerResolvedCallBody(
            exprID,
            args: args,
            loweredArgIDs: loweredArgIDs,
            chosen: chosen,
            callBinding: callBinding,
            callableValueCallBinding: callableValueCallBinding,
            loweredCallable: loweredCallable,
            loweredCalleeExprID: loweredCalleeExprID,
            sourceCalleeName: sourceCalleeName,
            boundType: boundType,
            knownNames: knownNames,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }

    /// Resolves the concrete class a runtime collection factory result claims
    /// to be, or nil for interface-typed results (those dispatch through the
    /// itable, not the class vtable).
    private func collectionFactoryResultClassSymbol(
        result: KIRExprID,
        boundType: TypeID?,
        arena: KIRArena,
        sema: SemaModule
    ) -> SymbolID? {
        let resultType = boundType ?? arena.exprType(result)
        guard let resultType,
              let resolved = resolveClassTypeSymbol(resultType, sema: sema),
              resolved.symbol.kind == .class
        else { return nil }
        return resolved.symbol.id
    }

    private func tryLowerCollectionToListCall(
        sourceCalleeName: InternedString,
        args: [CallArgument],
        loweredArgIDs: [KIRExprID],
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        knownNames: KnownCompilerNames,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sourceCalleeName == interner.intern("toList"),
              args.count == 1,
              sema.bindings.isCollectionExpr(args[0].expr)
        else {
            return nil
        }

        let argumentType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
        let nonNullArgumentType = sema.types.makeNonNullable(argumentType)
        let runtimeCallee: InternedString? = if let (_, symbol) = resolveClassTypeSymbol(nonNullArgumentType, sema: sema)
        {
            switch symbol.name {
            case knownNames.list, knownNames.mutableList:
                nil
            case interner.intern("Range"), interner.intern("IntRange"):
                interner.intern("kk_range_toList")
            case interner.intern("LongRange"):
                interner.intern("__kk_long_range_toList")
            case interner.intern("ULongRange"):
                // KSP-1524: ULongRange.toList() is bundled source; preserve
                // the selected Kotlin declaration instead of a removed bridge.
                nil
            case interner.intern("CharRange"), interner.intern("CharProgression"):
                interner.intern("__kk_char_range_toList")
            default:
                interner.intern("kk_sequence_to_list")
            }
        } else {
            interner.intern("kk_sequence_to_list")
        }
        guard let runtimeCallee else {
            return loweredArgIDs[0]
        }

        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: loweredArgIDs,
            result: result,
            canThrow: runtimeCallee == interner.intern("kk_sequence_to_list"),
            thrownResult: nil
        ))
        return result
    }

    private func lowerTopLevelNumericConversionCall(
        sourceCalleeName: InternedString,
        argumentExpr: ExprID,
        loweredArgumentID: KIRExprID,
        boundType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let receiverType = sema.types.makeNonNullable(sema.bindings.exprTypes[argumentExpr] ?? sema.types.anyType)
        let calleeStr = interner.resolve(sourceCalleeName)

        let runtimeCallee: InternedString? = switch (calleeStr, receiverType, boundType) {
        case ("toInt", sema.types.uintType, sema.types.intType): interner.intern("kk_uint_to_int")
        case ("toInt", sema.types.ulongType, sema.types.intType): interner.intern("kk_ulong_to_int")
        case ("toInt", sema.types.ubyteType, sema.types.intType): interner.intern("kk_ubyte_to_int")
        case ("toInt", sema.types.ushortType, sema.types.intType): interner.intern("kk_ushort_to_int")
        case ("toInt", sema.types.doubleType, sema.types.intType): interner.intern("__kk_double_to_int")
        case ("toInt", sema.types.floatType, sema.types.intType): interner.intern("__kk_float_to_int")
        case ("toInt", sema.types.charType, sema.types.intType): nil
        case ("toInt", sema.types.byteType, sema.types.intType): nil
        case ("toInt", sema.types.shortType, sema.types.intType): nil
        case ("toInt", sema.types.intType, sema.types.intType), ("toInt", sema.types.longType, sema.types.intType): nil
        case ("toLong", sema.types.intType, sema.types.longType): interner.intern("kk_int_to_long")
        case ("toLong", sema.types.uintType, sema.types.longType): interner.intern("kk_uint_to_long")
        case ("toLong", sema.types.ubyteType, sema.types.longType): interner.intern("kk_ubyte_to_long")
        case ("toLong", sema.types.ushortType, sema.types.longType): interner.intern("kk_ushort_to_long")
        case ("toLong", sema.types.doubleType, sema.types.longType): interner.intern("__kk_double_to_long")
        case ("toLong", sema.types.floatType, sema.types.longType): interner.intern("__kk_float_to_long")
        case ("toLong", sema.types.charType, sema.types.longType): nil
        case ("toLong", sema.types.byteType, sema.types.longType): nil
        case ("toLong", sema.types.shortType, sema.types.longType): nil
        case ("toLong", sema.types.longType, sema.types.longType), ("toLong", sema.types.ulongType, sema.types.longType): nil
        case ("toUInt", sema.types.intType, sema.types.uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", sema.types.longType, sema.types.uintType): interner.intern("kk_long_to_uint")
        case ("toUInt", sema.types.ubyteType, sema.types.uintType): interner.intern("kk_ubyte_to_uint")
        case ("toUInt", sema.types.ushortType, sema.types.uintType): interner.intern("kk_ushort_to_uint")
        case ("toUInt", sema.types.charType, sema.types.uintType): nil
        case ("toUInt", sema.types.byteType, sema.types.uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", sema.types.shortType, sema.types.uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", sema.types.uintType, sema.types.uintType): nil
        // KSP-1533: ULong.toUInt() narrows 64 bits to 32 and must mask the high
        // bits away; reuse kk_long_to_uint (same raw-register representation,
        // already truncates via UInt32(truncatingIfNeeded:)) rather than the
        // representation-preserving identity this wrongly used before.
        case ("toUInt", sema.types.ulongType, sema.types.uintType): interner.intern("kk_long_to_uint")
        case ("toULong", sema.types.intType, sema.types.ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", sema.types.longType, sema.types.ulongType): interner.intern("kk_long_to_ulong")
        case ("toULong", sema.types.ubyteType, sema.types.ulongType): interner.intern("kk_ubyte_to_ulong")
        case ("toULong", sema.types.ushortType, sema.types.ulongType): interner.intern("kk_ushort_to_ulong")
        case ("toULong", sema.types.charType, sema.types.ulongType): nil
        case ("toULong", sema.types.byteType, sema.types.ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", sema.types.shortType, sema.types.ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", sema.types.uintType, sema.types.ulongType): interner.intern("kk_uint_to_ulong")
        case ("toULong", sema.types.ulongType, sema.types.ulongType): nil
        case ("toFloat", sema.types.intType, sema.types.floatType): interner.intern("kk_int_to_float")
        case ("toFloat", sema.types.longType, sema.types.floatType): interner.intern("kk_long_to_float")
        case ("toFloat", sema.types.doubleType, sema.types.floatType): interner.intern("kk_double_to_float")
        case ("toFloat", sema.types.floatType, sema.types.floatType): nil
        case ("toDouble", sema.types.longType, sema.types.doubleType): interner.intern("kk_long_to_double")
        case ("toDouble", sema.types.floatType, sema.types.doubleType): interner.intern("__kk_float_to_double_bits")
        case ("toDouble", sema.types.doubleType, sema.types.doubleType): nil
        case ("toByte", sema.types.intType, sema.types.byteType): interner.intern("kk_int_to_byte")
        case ("toByte", sema.types.longType, sema.types.byteType): interner.intern("kk_long_to_byte")
        case ("toByte", sema.types.uintType, sema.types.byteType): interner.intern("kk_uint_to_byte")
        case ("toByte", sema.types.ulongType, sema.types.byteType): interner.intern("kk_ulong_to_byte")
        case ("toByte", sema.types.ubyteType, sema.types.byteType): interner.intern("kk_ubyte_to_byte")
        case ("toByte", sema.types.ushortType, sema.types.byteType): interner.intern("kk_ushort_to_byte")
        case ("toByte", sema.types.byteType, sema.types.byteType): nil
        case ("toByte", sema.types.shortType, sema.types.byteType): interner.intern("kk_int_to_byte")
        case ("toShort", sema.types.intType, sema.types.shortType): interner.intern("kk_int_to_short")
        case ("toShort", sema.types.longType, sema.types.shortType): interner.intern("kk_long_to_short")
        case ("toShort", sema.types.uintType, sema.types.shortType): interner.intern("kk_uint_to_short")
        case ("toShort", sema.types.ulongType, sema.types.shortType): interner.intern("kk_ulong_to_short")
        case ("toShort", sema.types.ubyteType, sema.types.shortType): interner.intern("kk_ubyte_to_short")
        case ("toShort", sema.types.ushortType, sema.types.shortType): interner.intern("kk_ushort_to_short")
        case ("toShort", sema.types.byteType, sema.types.shortType): nil
        case ("toShort", sema.types.shortType, sema.types.shortType): nil
        case ("toUByte", sema.types.intType, sema.types.ubyteType): interner.intern("kk_int_to_ubyte")
        case ("toUByte", sema.types.longType, sema.types.ubyteType): interner.intern("kk_long_to_ubyte")
        case ("toUByte", sema.types.uintType, sema.types.ubyteType): interner.intern("kk_uint_to_ubyte")
        case ("toUByte", sema.types.ulongType, sema.types.ubyteType): interner.intern("kk_ulong_to_ubyte")
        case ("toUByte", sema.types.ubyteType, sema.types.ubyteType): nil
        case ("toUByte", sema.types.ushortType, sema.types.ubyteType): interner.intern("kk_ushort_to_ubyte")
        case ("toUByte", sema.types.byteType, sema.types.ubyteType): interner.intern("kk_byte_to_ubyte")
        case ("toUByte", sema.types.shortType, sema.types.ubyteType): interner.intern("kk_short_to_ubyte")
        case ("toUShort", sema.types.intType, sema.types.ushortType): interner.intern("kk_int_to_ushort")
        case ("toUShort", sema.types.byteType, sema.types.ushortType): interner.intern("kk_int_to_ushort")
        case ("toUShort", sema.types.shortType, sema.types.ushortType): interner.intern("kk_int_to_ushort")
        case ("toUShort", sema.types.longType, sema.types.ushortType): interner.intern("kk_long_to_ushort")
        case ("toUShort", sema.types.uintType, sema.types.ushortType): interner.intern("kk_uint_to_ushort")
        case ("toUShort", sema.types.ulongType, sema.types.ushortType): interner.intern("kk_ulong_to_ushort")
        case ("toUShort", sema.types.ushortType, sema.types.ushortType): nil
        case ("toChar", sema.types.charType, sema.types.charType): nil
        default: nil
        }

        let isCharNarrowingConversion = receiverType == sema.types.charType
            && (calleeStr == "toByte" || calleeStr == "toShort")
        if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toByte", "toShort", "toChar"].contains(calleeStr),
           runtimeCallee == nil,
           !isCharNarrowingConversion
        {
            return loweredArgumentID
        }
        guard let runtimeCallee else {
            return nil
        }

        let result = arena.appendTemporary(type: boundType)
        emitNonThrowingCall(
            callee: runtimeCallee,
            arg: loweredArgumentID,
            result: result,
            into: &instructions
        )
        return result
    }
}
