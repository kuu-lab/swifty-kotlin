// swiftlint:disable file_length

/// Collection HOF argument adaptation and comparator trampoline helpers.
extension CallLowerer {
    func isCollectionHOFCallee(
        _ calleeName: InternedString,
        interner: StringInterner
    ) -> Bool {
        [
            "map", "filter", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull", "forEach", "flatMap", "flatMapIndexed",
            "any", "none", "all", "fold", "foldRight", "reduce", "reduceRight", "scan", "scanIndexed", "scanReduce",
            "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed", "groupBy", "groupingBy",
            "aggregate", "aggregateTo",
            "sortedBy", "count", "first", "last", "find", "firstOrNull", "lastOrNull", "distinctBy",
            "associateBy", "associateWith", "associate",
            "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "sumOf", "sumBy", "sumByDouble", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues",
            "getOrElse", "elementAtOrElse", "getOrPut",
            "maxBy", "minBy", "min", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull",
            "maxOf", "minOf",
            "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
            "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
            "indexOfFirst", "indexOfLast", "binarySearch", "binarySearchBy", "reduceIndexed", "reduceIndexedOrNull", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "foldIndexed", "foldRightIndexed",
            "sortedByDescending", "sortedWith", "partition", "zip", "zipWithNext",
            "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "filterNot", "findLast",
            "trim", "trimStart", "trimEnd",
            "sortWith", "sortBy", "sortByDescending",
            "onEach", "onEachIndexed",
            "ifEmpty",
            "ifBlank",
            "chunked", "chunkedSequence", "windowed", "copyOf",
            "toComponents",
            "onSuccess", "onFailure", "recover", "recoverCatching",
            "collect", "collectLatest",
        ].contains(interner.resolve(calleeName))
    }

    func addCollectionHOFClosureArguments(
        loweredArgIDs: [KIRExprID],
        argExprIDs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard loweredArgIDs.count == argExprIDs.count else {
            return loweredArgIDs
        }
        var finalArgs: [KIRExprID] = []
        finalArgs.reserveCapacity(loweredArgIDs.count + 1)

        for (loweredArgID, argExprID) in zip(loweredArgIDs, argExprIDs) {
            let callableInfo: KIRCallableValueInfo? = {
                if sema.bindings.isCollectionHOFLambdaExpr(argExprID) {
                    return driver.ctx.callableValueInfo(for: loweredArgID) ?? {
                        guard case let .symbolRef(symbol)? = arena.expr(loweredArgID) else {
                            return nil
                        }
                        return KIRCallableValueInfo(
                            symbol: symbol,
                            callee: interner.intern(""),
                            captureArguments: arena.lambdaCaptureArgsBySymbol[symbol] ?? [],
                            hasClosureParam: true
                        )
                    }()
                }
                guard let loweredCallable = driver.ctx.callableValueInfo(for: loweredArgID),
                      !loweredCallable.hasClosureParam,
                      let adapted = makeCollectionHOFCallableAdapter(
                          callableInfo: loweredCallable,
                          loweredArgID: loweredArgID,
                          argExprID: argExprID,
                          sema: sema,
                          arena: arena,
                          interner: interner,
                          namePrefix: "kk_hof_adapter",
                          symbolIDOffsetBase: -700_000
                      )
                else {
                    return nil
                }
                return adapted
            }()
            guard let callableInfo else {
                finalArgs.append(loweredArgID)
                continue
            }

            let fnPtrExpr = arena.appendExpr(
                .symbolRef(callableInfo.symbol),
                type: arena.exprType(loweredArgID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
            driver.ctx.registerCallableValue(
                fnPtrExpr,
                symbol: callableInfo.symbol,
                callee: callableInfo.callee,
                captureArguments: callableInfo.captureArguments,
                hasClosureParam: callableInfo.hasClosureParam
            )
            finalArgs.append(fnPtrExpr)
            let boxedCaptureArguments = makeBoxedCallableCaptureArguments(
                callableInfo: callableInfo,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            if let boxedCaptureArgument = boxedCaptureArguments.first {
                finalArgs.append(boxedCaptureArgument)
            } else {
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                finalArgs.append(zeroExpr)
            }
        }

        return finalArgs
    }

    /// Comparator-taking collection HOFs use the `(comparator, closureRaw)` runtime
    /// ABI pair. KSP-461 moved every comparator factory to bundled Kotlin source, so
    /// the comparator is always a `Comparator<T>` object dispatched through its
    /// itable compare slot and the closure slot is always zero.
    func makeComparatorObjectArgumentPair(
        loweredComparatorID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        return [loweredComparatorID, zeroExpr]
    }

    func adaptComparatorFactoryArgumentsForCollectionHOF(
        calleeName: InternedString,
        loweredArgIDs: [KIRExprID],
        argExprIDs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let comparatorOnlyHOFNames: Set<String> = [
            "sortWith", "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        ]
        _ = argExprIDs
        guard comparatorOnlyHOFNames.contains(interner.resolve(calleeName)),
              loweredArgIDs.count == 1,
              let comparatorArgID = loweredArgIDs.first
        else {
            return loweredArgIDs
        }
        return makeComparatorObjectArgumentPair(
            loweredComparatorID: comparatorArgID,
            sema: sema,
            arena: arena,
            instructions: &instructions
        )
    }

    func adaptComparatorBackedCollectionArguments(
        loweredCallee: InternedString,
        finalArguments: [KIRExprID],
        sourceArgExprs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let comparatorOnlyCallees: Set<InternedString> = [
            interner.intern("kk_sequence_maxWith"),
            interner.intern("kk_sequence_maxWithOrNull"),
            interner.intern("kk_sequence_minWith"),
            interner.intern("kk_sequence_minWithOrNull"),
        ]
        if comparatorOnlyCallees.contains(loweredCallee),
           finalArguments.count == 2
        {
            let comparatorArgs = makeComparatorObjectArgumentPair(
                loweredComparatorID: finalArguments[1],
                sema: sema,
                arena: arena,
                instructions: &instructions
            )
            return [finalArguments[0]] + comparatorArgs
        }

        if loweredCallee == interner.intern("kk_list_binarySearch_comparator"),
           finalArguments.count == 5,
           sourceArgExprs.count >= 2
        {
            let comparatorArgs = makeComparatorObjectArgumentPair(
                loweredComparatorID: finalArguments[2],
                sema: sema,
                arena: arena,
                instructions: &instructions
            )
            var adapted: [KIRExprID] = [finalArguments[0], finalArguments[1]]
            adapted.append(contentsOf: comparatorArgs)
            adapted.append(contentsOf: finalArguments[3...])
            return adapted
        }

        return finalArguments
    }
}
