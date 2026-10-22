// swiftlint:disable file_length

// swiftlint:disable type_body_length
extension CallTypeChecker {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func inferCallExpr(
        _ id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        defer { recordFlowBuilderEmitAll(id, args: args, ctx: ctx) }

        let calleeExpr = ast.arena.expr(calleeID)
        let calleeName: InternedString? = if case let .nameRef(name, _) = calleeExpr {
            name
        } else {
            nil
        }
        // `(D::f)(x)` invokes the reference value; `D::f` is not the qualified
        // function name `D.f`, so it must not feed FQ-name candidate lookup.
        let calleePath: [InternedString]? = if case .callableRef = calleeExpr {
            nil
        } else {
            qualifiedCalleePath(for: calleeID, ast: ast)
        }
        if calleeName.map(interner.resolve) == "$annotationArrayLiteral" {
            if expectedType == nil, let boundType = sema.bindings.exprTypes[id],
               sema.bindings.callBindings[id] != nil { return boundType }
            var factoryName = "arrayOf"
            if let expectedType,
               case let .classType(array) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
               let name = sema.symbols.symbol(array.classSymbol)?.name,
               primitiveArrayElementType(className: name, sema: sema, interner: interner) != nil {
                let text = interner.resolve(name)
                factoryName = text.prefix(1).lowercased() + text.dropFirst() + "Of"
            }
            let kotlin = ast.arena.appendExpr(.nameRef(interner.intern("kotlin"), range))
            let factory = ast.arena.appendExpr(.memberCall(receiver: kotlin, callee: interner.intern(factoryName),
                                                           typeArgs: [], args: [], range: range))
            return inferCallExpr(id, calleeID: factory, args: args, range: range,
                                 ctx: ctx, locals: &locals, expectedType: expectedType)
        }

        if let inferred = inferContextOfCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let builderType = inferReceiverBuilderCall(
            id, calleeName: calleeName, args: args, range: range,
            ctx: ctx, locals: &locals, expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return builderType
        }
        if let memberType = inferPostponedImplicitReceiverMemberCall(
            id, calleeName: calleeName, args: args, range: range,
            ctx: ctx, locals: &locals, expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return memberType
        }
        if let customBuilderType = inferExperimentalBuilderCallExpr(
            id,
            calleeName: calleeName,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return customBuilderType
        }

        if let inferred = inferBuilderDSLSpecialCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferSequenceBuilderCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferIteratorBuilderCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferContextHelperCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferMemScopedCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferBundledProduceCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferProduceCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferSuspendCoroutineIntrinsicCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            calleePath: calleePath
        ) {
            return inferred
        }

        if let inferred = inferSuspendCoroutineCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferFlowBuilderCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = postponeFlowEmitAsConstraint(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferEmitInFlowScopeCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferArrayConstructorCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferAtomicIntArrayCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferAtomicLongArrayCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferReflectTypeOfCall(
            id,
            args: args,
            ctx: ctx,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            calleePath: calleePath,
            locals: locals
        ) {
            return inferred
        }

        if let inferred = inferEnumStdlibSpecialCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferMinMaxOfCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferContractCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            calleeName: calleeName,
            calleePath: calleePath
        ) {
            return inferred
        }

        let compareBySelectorArguments = resolveCompareBySelectorArguments(
            calleeName: calleeName, args: args, ctx: ctx, locals: &locals
        )

        if let inferred = inferCompareBySelectorsCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            compareBySelectorArguments: compareBySelectorArguments
        ) {
            return inferred
        }

        if let inferred = inferCompareByPairCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            compareBySelectorArguments: compareBySelectorArguments
        ) {
            return inferred
        }

        if let inferred = inferCompareByVarargCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferCompareBySingleSelectorCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        if let inferred = inferNaturalOrderCall(
            id,
            args: args,
            ctx: ctx,
            locals: locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        // KSP-678: `Channel()` / `Channel(capacity)` resolve through the bundled
        // Kotlin factory functions (Channels.kt) via normal overload resolution.

        let withContextExpectedLambdaType = resolveWithContextExpectedLambdaType(
            calleeName: calleeName, args: args, expectedType: expectedType, ctx: ctx
        )

        var samFactoryCandidates: [SymbolID]?
        if let calleeName,
           let samCallType = inferSamConvertedCallExpr(
               id,
               calleeName: calleeName,
               args: args,
               range: range,
               ctx: ctx,
               locals: &locals,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs,
               samFactoryCandidates: &samFactoryCandidates
           )
        {
            sema.bindings.bindExprType(id, type: samCallType)
            return samCallType
        }

        var candidates: [SymbolID] = []
        var constructorTypeAlias: SymbolID?
        var implicitReceiverScopeCandidates: [SymbolID] = []
        var callImplicitReceiverType = ctx.implicitReceiverType
        /// Member-extension candidates -> the receiver-tower symbol Sema
        /// picked to supply their declared extension receiver. Recorded into
        /// `implicitExtensionReceiverSymbols` once overload resolution
        /// chooses, so KIR lowering materializes that exact receiver value
        /// (through capture when the call sits inside a nested lambda)
        /// instead of blindly using the innermost implicit receiver.
        var memberExtensionReceiverMarks: [SymbolID: SymbolID] = [:]
        /// Members merged from the innermost implicit receiver while the
        /// scope lookup produced no candidates (e.g. `FlowCollector.emit`
        /// inside a `transform` lambda). Their resolver pass can fail on an
        /// opaque builder-inference type parameter in the receiver
        /// signature, so the member path's lenient single-candidate bind
        /// must still apply to them.
        var mergedImplicitReceiverMembers: [SymbolID] = []
        var callInvisible: [SemanticSymbol] = []
        var knownApplicableImplicitMembers: Set<SymbolID> = []
        var typeNameCompanionInvokeCandidates: Set<SymbolID> = []
        var typeNameCompanionInvokeReceiverType: TypeID?
        var typeAliasConstructor: TypeAliasConstructorContext?

        if let inferred = collectCallExprCandidates(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            calleePath: calleePath,
            candidates: &candidates,
            constructorTypeAlias: &constructorTypeAlias,
            typeAliasConstructor: &typeAliasConstructor,
            implicitReceiverScopeCandidates: &implicitReceiverScopeCandidates,
            callImplicitReceiverType: &callImplicitReceiverType,
            memberExtensionReceiverMarks: &memberExtensionReceiverMarks,
            mergedImplicitReceiverMembers: &mergedImplicitReceiverMembers,
            callInvisible: &callInvisible,
            knownApplicableImplicitMembers: &knownApplicableImplicitMembers,
            typeNameCompanionInvokeCandidates: &typeNameCompanionInvokeCandidates,
            typeNameCompanionInvokeReceiverType: &typeNameCompanionInvokeReceiverType
        ) {
            return inferred
        }

        if let samFactoryCandidates {
            candidates = candidates.filter { samFactoryCandidates.contains($0) }
        }

        if let inferred = inferCompareValuesByCall(
            id,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            candidates: candidates
        ) {
            return inferred
        }

        applyImplicitReceiverPredicateCandidatePreference(
            args: args,
            ctx: ctx,
            calleeName: calleeName,
            candidates: &candidates,
            implicitReceiverScopeCandidates: implicitReceiverScopeCandidates
        )

        if let calleeName,
           let implicitReceiverResult = tryBindImplicitReceiverCollectionMemberCall(
               id,
               calleeName: calleeName,
               args: args,
               range: range,
               ctx: ctx,
               locals: &locals,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs
           )
        {
            return implicitReceiverResult
        }

        if let inferred = inferLocalInvokeOperatorCall(
            id,
            calleeID: calleeID,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName
        ) {
            return inferred
        }

        preferScopeCandidatesForInapplicableImplicitMembers(
            args: args,
            callRange: range,
            calleeName: calleeName,
            scopeCandidates: implicitReceiverScopeCandidates,
            candidates: &candidates,
            receiverType: &callImplicitReceiverType,
            ctx: ctx,
            locals: locals
        )

        var argumentContextCandidates = candidates
        var argumentContextReceiverType = callImplicitReceiverType
        var preInferredCallableCalleeType: TypeID?
        let isCallChainValueCallee: Bool
        if let calleeExpr {
            switch calleeExpr {
            case .call, .indexedAccess:
                isCallChainValueCallee = true
            default:
                isCallChainValueCallee = false
            }
        } else {
            isCallChainValueCallee = false
        }
        // A call whose callee is another call or indexed access can be an
        // implicit `invoke` chain. Resolve its receiver type before checking
        // trailing lambdas so the selected operator's parameter supplies their
        // expected type (including a receiver function type's `this`). Keep
        // named calls on the ordinary candidate path so constructor and
        // companion `invoke` precedence remains unchanged.
        if candidates.isEmpty, calleeName == nil, isCallChainValueCallee {
            let calleeType = driver.inferExpr(calleeID, ctx: ctx, locals: &locals)
            let invokeCandidates = implicitInvokeOperatorCandidates(for: calleeType, ctx: ctx)
            if !invokeCandidates.isEmpty {
                argumentContextCandidates = invokeCandidates
                argumentContextReceiverType = calleeType
                preInferredCallableCalleeType = calleeType
            }
        }

        var expectedTypeOverrides: [Int: TypeID] = [:]
        var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
        let argumentDiagnosticsCheckpoint = sema.diagnostics.checkpoint()
        let originalArgumentLocals = locals
        // Contextual argument inference uses the underlying owner's positions,
        // while overload resolution consumes the alias's public type arguments.
        let argumentContextTypeArgs = typeAliasConstructor.map {
            aliasConstructorArgumentContextTypes($0, explicitTypeArgs: explicitTypeArgs, sema: sema)
        } ?? explicitTypeArgs
        let expectedTypeHintIndices = prepareCallExprArgumentContexts(
            args: args,
            callRange: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: argumentContextTypeArgs,
            calleeName: calleeName,
            candidates: argumentContextCandidates,
            withContextExpectedLambdaType: withContextExpectedLambdaType,
            expectedTypeOverrides: &expectedTypeOverrides,
            lambdaContextOverrides: &lambdaContextOverrides
        )

        // Calling a function-typed local (`m { it }`): no candidate declares the
        // parameter types, so seed lambda arguments from the value's own type.
        if candidates.isEmpty, let calleeName, let local = locals[calleeName],
           case let .functionType(calleeFunctionType) = sema.types.kind(of: sema.types.makeNonNullable(local.type)),
           calleeFunctionType.receiver == nil,
           args.count == calleeFunctionType.params.count
        {
            for (index, argument) in args.enumerated()
                where !argument.isSpread && argument.label == nil && expectedTypeOverrides[index] == nil
            {
                if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                    expectedTypeOverrides[index] = calleeFunctionType.params[index]
                }
            }
        }

        let preparedArgs = prepareCallArguments(
            args: args,
            callRange: range,
            candidates: argumentContextCandidates,
            expectedTypeOverrides: expectedTypeOverrides,
            expectedTypeHintIndices: expectedTypeHintIndices,
            contextualCallResultType: ctx.isCallResultDiscarded && ctx.isUnitCoercionContext
                ? sema.types.unitType : expectedType,
            explicitTypeArgs: argumentContextTypeArgs,
            receiverType: argumentContextReceiverType,
            boundObjectDispatchReceiverCandidates: importedObjectDispatchReceiverCandidates(
                named: calleeName, candidates: candidates, ctx: ctx
            ).union(typeNameCompanionInvokeCandidates),
            lambdaContextOverrides: lambdaContextOverrides,
            ctx: ctx,
            locals: &locals
        )
        let argTypes = preparedArgs.argTypes

        if let inferred = inferSourceBackedCollectionFactoryCall(
            id,
            args: args,
            ctx: ctx,
            locals: locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            candidates: candidates,
            argTypes: argTypes
        ) {
            return inferred
        }

        applyIndexOfReceiverPreference(
            ctx: ctx,
            calleeName: calleeName,
            candidates: &candidates
        )

        if let inferred = resolveCallExprCandidates(
            id,
            calleeID: calleeID,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            candidates: candidates,
            constructorTypeAlias: constructorTypeAlias,
            typeAliasConstructor: typeAliasConstructor,
            typeNameCompanionInvokeCandidates: typeNameCompanionInvokeCandidates,
            typeNameCompanionInvokeReceiverType: typeNameCompanionInvokeReceiverType,
            callImplicitReceiverType: callImplicitReceiverType,
            memberExtensionReceiverMarks: memberExtensionReceiverMarks,
            mergedImplicitReceiverMembers: mergedImplicitReceiverMembers,
            knownApplicableImplicitMembers: knownApplicableImplicitMembers,
            expectedTypeOverrides: expectedTypeOverrides,
            preparedArgs: preparedArgs,
            argTypes: argTypes
        ) {
            // A successful nested inference can still make another invariant
            // argument incompatible. Retry the whole call without lifted hints,
            // retaining its declared expected result and all ordinary constraints.
            // listOf retains useful element hints even in the fallback pass.
            // Those hints must not recursively schedule the same retry again.
            if inferred == sema.types.errorType, ctx.allowsLiftedCallExpectedTypeHints, !expectedTypeHintIndices.isEmpty {
                sema.diagnostics.rollback(to: argumentDiagnosticsCheckpoint)
                locals = originalArgumentLocals
                var retryContext = ctx
                retryContext.allowsLiftedCallExpectedTypeHints = false
                return driver.inferExpr(id, ctx: retryContext, locals: &locals, expectedType: expectedType)
            }
            return inferred
        }

        if let inferred = inferCallableValueCall(
            id,
            calleeID: calleeID,
            preInferredCalleeType: preInferredCallableCalleeType,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            argTypes: argTypes
        ) {
            return inferred
        }

        if let inferred = inferImplicitReceiverFallbackCall(
            id,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            candidates: candidates,
            memberExtensionReceiverMarks: &memberExtensionReceiverMarks
        ) {
            return inferred
        }

        if let firstInvisible = callInvisible.first, let calleeName {
            driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.sema.diagnostics)
        } else {
            let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0023",
                "Unresolved function '\(nameStr)'.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func isStdlibContextHelper(
        _ candidate: SymbolID,
        named name: String,
        ctx: TypeInferenceContext,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = ctx.cachedSymbol(candidate) else { return false }
        return symbol.fqName.map { interner.resolve($0) } == ["kotlin", name]
    }

    /// True when `candidate` is a non-stdlib declaration that is applicable to the
    /// call, so it takes precedence over the `context` / `contextOf` intrinsic
    /// handling. Declarations with a different arity — or without the type
    /// parameters the call spells out explicitly — are not applicable and leave
    /// the intrinsic path in charge.
    func shadowsStdlibContextHelper(
        _ candidate: SymbolID,
        named name: String,
        argumentCount: Int,
        explicitTypeArgumentCount: Int,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard !isStdlibContextHelper(candidate, named: name, ctx: ctx, interner: interner) else {
            return false
        }
        guard let signature = sema.symbols.functionSignature(for: candidate) else {
            return true
        }
        return signature.parameterTypes.count == argumentCount
            && (explicitTypeArgumentCount == 0
                || signature.typeParameterSymbols.count == explicitTypeArgumentCount)
    }
}

// swiftlint:enable type_body_length
