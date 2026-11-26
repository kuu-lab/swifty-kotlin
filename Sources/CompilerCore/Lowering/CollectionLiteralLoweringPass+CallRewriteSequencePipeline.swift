extension CollectionLiteralConstructionLoweringPass {
    func rewriteSequencePipelineCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        instruction: KIRInstruction,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        // STDLIB-pipeline §5 / KSP-441〜447: If the resolved callee is a bundled
        // Kotlin source declaration, only a confirmed RuntimeSequenceBox may
        // enter the runtime bridge path. A source object, a non-Sequence
        // receiver, or unknown provenance must keep the original source call;
        // static `Sequence` type alone is not enough to select a bridge.
        if isSourceBacked(symbol: symbol, ctx: ctx),
           let receiverID = arguments.first,
           state.sequenceRuntimeRepresentation(of: receiverID) != .runtimeBox {
            return false
        }

    if callee == lookup.kkListAsSequenceName || callee == lookup.kkArrayAsSequenceName
        || callee == lookup.kkSequenceMapName || callee == lookup.kkSequenceFilterName
        || callee == lookup.kkSequenceFlatMapName
        || callee == lookup.kkSequenceFlatMapIndexedName
        || callee == lookup.kkSequenceConstrainOnceName
        || callee == lookup.kkSequenceShuffledName || callee == lookup.kkSequenceShuffledRandomName
        || callee == lookup.kkSequencePlusName || callee == lookup.kkSequenceMinusName
        || callee == lookup.kkSequenceTakeName || callee == lookup.kkSequenceDropName
        || callee == lookup.kkSequenceTakeWhileName || callee == lookup.kkSequenceDropWhileName
    {
        loweredBody.append(instruction)
        if let result { state.sequenceExprIDs.insert(result.rawValue) }
        return true
    }

    if callee == lookup.asSequenceName, arguments.count == 1 {
        let receiverID = arguments[0]
        classifyTrackedExprByStaticType(
            receiverID,
            module: module,
            sema: ctx.sema,
            lookup: lookup,
            state: &state
        )

        // Runtime array/list handles must use kk_*_asSequence. Source-backed
        // Iterable/Sequence.asSequence cannot traverse RuntimeArrayBox/ListBox.
        // Check tracking before the source-backed short-circuit: an unbound
        // asSequence call (symbol == nil) has an empty externalLinkName and would
        // otherwise be misclassified as source-backed, leaving a virtual call that
        // yields an empty sequence (BUG with primitive Array.asSequence pipelines).
        if state.arrayExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(callee: lookup.kkArrayAsSequenceName, arguments: [receiverID], result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
        if state.listExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(callee: lookup.kkListAsSequenceName, arguments: [receiverID], result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }

        if let symbol,
           let sema = ctx.sema,
           sema.symbols.symbol(symbol) != nil,
           (sema.symbols.externalLinkName(for: symbol) ?? "").isEmpty
        {
            loweredBody.append(instruction)
            return true
        }

        loweredBody.append(instruction)
        return true
    }

    if callee == lookup.constrainOnceName, arguments.count == 1 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(callee: lookup.kkSequenceConstrainOnceName, arguments: [receiverID], result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // The bundled source iterator cannot propagate an exception thrown from
    // hasNext(), so the runtime pipeline step (which sets outThrown) is kept.
    if callee == lookup.requireNoNullsName, arguments.count == 1,
       let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: 0) {
        loweredBody.append(.call(callee: kkName, arguments: arguments, result: result, canThrow: false))
        if let result { state.sequenceExprIDs.insert(result.rawValue) }
        return true
    }

    if callee == lookup.mapName || callee == lookup.filterName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceRuntimeRepresentation(of: receiverID) == .runtimeBox,
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: 1) ?? callee
            let expanded = expandSequenceLambdaArgument(
                lambdaExpr: arguments[1],
                module: module,
                ctx: ctx,
                loweredBody: &loweredBody
            )
            loweredBody.append(.call(callee: kkName, arguments: [receiverID, expanded.fnPtr, expanded.closureRaw], result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    // KUU-3850: `take`/`drop`/`takeWhile`/`dropWhile` would otherwise run the
    // bundled `object : Sequence`/`object : Iterator` wrappers — a generated
    // GC-framed hasNext/next pair per element on top of the underlying
    // iterator dispatch. The runtime step forms stay lazy, keep the eager
    // `require(n >= 0)` contract via outThrown, and propagate producer
    // exceptions through the same outThrown channel.
    //
    // kklib-imported stdlib callees arrive as `kk_fn_*` link names, so the
    // resolved `kotlin.sequences`/`kotlin.collections` declaration is matched
    // as well as the plain callee name.
    let sequenceDeclName = sequenceExtensionSimpleName(
        symbol: symbol,
        sema: ctx.sema,
        interner: ctx.interner
    )
    let isTakeCall = sequenceDeclName == lookup.takeName
        || (symbol == nil && callee == lookup.takeName)
    let isDropCall = sequenceDeclName == lookup.dropName
        || (symbol == nil && callee == lookup.dropName)
    if isTakeCall || isDropCall, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceRuntimeRepresentation(of: receiverID) == .runtimeBox,
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            var origThrownResult: KIRExprID?
            if case let .call(_, _, _, _, _, thrownResult, _, _) = instruction {
                origThrownResult = thrownResult
            }
            let kkName = isTakeCall
                ? lookup.kkSequenceTakeName : lookup.kkSequenceDropName
            loweredBody.append(.call(
                callee: kkName,
                arguments: [receiverID, arguments[1]],
                result: result,
                canThrow: true,
                thrownResult: origThrownResult
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    let isTakeWhileCall = sequenceDeclName == lookup.takeWhileName
        || (symbol == nil && callee == lookup.takeWhileName)
    let isDropWhileCall = sequenceDeclName == lookup.dropWhileName
        || (symbol == nil && callee == lookup.dropWhileName)
    if isTakeWhileCall || isDropWhileCall,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceRuntimeRepresentation(of: receiverID) == .runtimeBox,
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            let kkName = isTakeWhileCall
                ? lookup.kkSequenceTakeWhileName : lookup.kkSequenceDropWhileName
            let expanded = expandSequenceLambdaArgument(
                lambdaExpr: arguments[1],
                module: module,
                ctx: ctx,
                loweredBody: &loweredBody
            )
            loweredBody.append(.call(
                callee: kkName,
                arguments: [receiverID, expanded.fnPtr, expanded.closureRaw],
                result: result,
                canThrow: false
            ))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    if callee == lookup.flatMapName || callee == lookup.flatMapIndexedName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue),
           !state.arrayExprIDs.contains(receiverID.rawValue)
        {
            let arity = callee == lookup.flatMapIndexedName ? 2 : 1
            let kkName = lookup.collectionHOFRuntimeName(ownerKind: .sequence, callee: callee, arity: arity) ?? callee
            let expanded = expandSequenceLambdaArgument(
                lambdaExpr: arguments[1],
                module: module,
                ctx: ctx,
                loweredBody: &loweredBody
            )
            loweredBody.append(.call(callee: kkName, arguments: [receiverID, expanded.fnPtr, expanded.closureRaw], result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    if callee == lookup.flatMapName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(callee: lookup.kkSequenceFlatMapName, arguments: arguments, result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    if callee == lookup.flatMapIndexedName,
       arguments.count == 2 || arguments.count == 3
    {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(callee: lookup.kkSequenceFlatMapIndexedName, arguments: arguments, result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    if callee == lookup.shuffledName, arguments.count == 1 || arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let kkName = arguments.count == 2
                ? lookup.kkSequenceShuffledRandomName
                : lookup.kkSequenceShuffledName
            loweredBody.append(.call(callee: kkName, arguments: arguments, result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    let sequencePlusMinusCallees = SequencePlusMinusRuntimeCallees(
        plus: lookup.kkSequencePlusName,
        minus: lookup.kkSequenceMinusName,
        ofSingle: lookup.kkSequenceOfSingleName
    )

    if callee == lookup.plusMemberName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let argID = arguments[1]
            // Only sequence/list/array are supported by
            // kk_sequence_plus at the ABI level (not Set/Map).
            let isArgCollection = state.listExprIDs.contains(argID.rawValue)
                || state.sequenceExprIDs.contains(argID.rawValue)
                || state.arrayExprIDs.contains(argID.rawValue)
            emitSequencePlusMinusRewrite(
                operation: .plus,
                receiver: receiverID,
                argument: argID,
                argumentIsCollection: isArgCollection,
                result: result,
                arena: module.arena,
                callees: sequencePlusMinusCallees,
                instructions: &loweredBody
            )
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    if callee == lookup.plusElementName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            loweredBody.append(.call(callee: lookup.kkSequencePlusElementName, arguments: arguments, result: result, canThrow: false))
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

    if callee == lookup.minusMemberName || callee == lookup.minusElementName, arguments.count == 2 {
        let receiverID = arguments[0]
        if state.sequenceExprIDs.contains(receiverID.rawValue) {
            let argID = arguments[1]
            let isArgCollection = state.listExprIDs.contains(argID.rawValue)
                || state.sequenceExprIDs.contains(argID.rawValue)
                || state.arrayExprIDs.contains(argID.rawValue)
            let rewriteResult = emitSequencePlusMinusRewrite(
                operation: .minus,
                receiver: receiverID,
                argument: argID,
                argumentIsCollection: isArgCollection,
                result: result,
                arena: module.arena,
                callees: sequencePlusMinusCallees,
                instructions: &loweredBody
            )
            guard case .emitted = rewriteResult else {
                loweredBody.append(instruction)
                return true
            }
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return true
        }
    }

        return false
    }

    private func expandSequenceLambdaArgument(
        lambdaExpr: KIRExprID,
        module: KIRModule,
        ctx: KIRContext,
        loweredBody: inout KIRLoweringEmitContext
    ) -> (fnPtr: KIRExprID, closureRaw: KIRExprID) {
        if let sema = ctx.sema,
           let info = module.arena.callableValueInfo(for: lambdaExpr) {
            let intType = sema.types.intType
            let fnPtrExpr = module.arena.appendExpr(.symbolRef(info.symbol), type: intType)
            loweredBody.append(.constValue(result: fnPtrExpr, value: .symbolRef(info.symbol)))
            if let closureRaw = info.captureArguments.first {
                return (fnPtrExpr, closureRaw)
            }
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: intType)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return (fnPtrExpr, zeroExpr)
        }

        let intType = ctx.sema?.types.intType
        let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: intType)
        if intType != nil {
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        }
        return (lambdaExpr, zeroExpr)
    }
}
