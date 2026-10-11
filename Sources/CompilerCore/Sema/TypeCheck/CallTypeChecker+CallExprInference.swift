// swiftlint:disable file_length

// swiftlint:disable type_body_length
/// Free-function call-expression inference: the `inferCallExpr` dispatcher
/// that intercepts stdlib/top-level special cases before generic overload
/// resolution, plus the `kotlin.context` / `kotlin.contextOf` shadowing
/// predicates consulted only by that dispatcher.
///
/// The interception blocks, candidate collection, argument preparation,
/// and fallback resolution live in the sibling `CallTypeChecker+CallExpr*`
/// files; this file keeps only the dispatch order.
///
/// Split out from `CallTypeChecker.swift`.
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
        let calleePath = qualifiedCalleePath(for: calleeID, ast: ast)

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
        if let customBuilderType = inferExperimentalBuilderCallExpr(
            id,
            calleeName: calleeName,
            args: args,
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
            expectedType: expectedType,
            calleeName: calleeName
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

        if let calleeName,
           let samCallType = inferSamConvertedCallExpr(
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
            sema.bindings.bindExprType(id, type: samCallType)
            return samCallType
        }

        var candidates: [SymbolID] = []
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
            implicitReceiverScopeCandidates: &implicitReceiverScopeCandidates,
            callImplicitReceiverType: &callImplicitReceiverType,
            memberExtensionReceiverMarks: &memberExtensionReceiverMarks,
            mergedImplicitReceiverMembers: &mergedImplicitReceiverMembers,
            callInvisible: &callInvisible
        ) {
            return inferred
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

        var expectedTypeOverrides: [Int: TypeID] = [:]
        var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
        prepareCallExprArgumentContexts(
            args: args,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            candidates: candidates,
            withContextExpectedLambdaType: withContextExpectedLambdaType,
            expectedTypeOverrides: &expectedTypeOverrides,
            lambdaContextOverrides: &lambdaContextOverrides
        )

        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            expectedTypeOverrides: expectedTypeOverrides,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: callImplicitReceiverType,
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
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            calleeName: calleeName,
            candidates: candidates,
            callImplicitReceiverType: callImplicitReceiverType,
            memberExtensionReceiverMarks: memberExtensionReceiverMarks,
            mergedImplicitReceiverMembers: mergedImplicitReceiverMembers,
            expectedTypeOverrides: expectedTypeOverrides,
            preparedArgs: preparedArgs,
            argTypes: argTypes
        ) {
            return inferred
        }

        if let inferred = inferCallableValueCall(
            id,
            calleeID: calleeID,
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
            driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
        } else {
            let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0023",
                "Unresolved function '\(nameStr)'.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    /// True when `candidate` is the stdlib `kotlin.context` / `kotlin.contextOf`
    /// intrinsic declaration (KSP-603: bundled Kotlin source, previously a
    /// synthetic stub).
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