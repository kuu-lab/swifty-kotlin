extension CollectionLiteralConstructionLoweringPass {
    private func isSequenceScopeBuilderMethod(
        _ symbol: SymbolID?,
        named name: InternedString,
        ctx: KIRContext
    ) -> Bool {
        guard let symbol,
              let sema = ctx.sema,
              let info = sema.symbols.symbol(symbol),
              info.fqName.count == 4,
              info.fqName[0] == ctx.interner.intern("kotlin"),
              info.fqName[1] == ctx.interner.intern("sequences"),
              info.fqName[2] == ctx.interner.intern("SequenceScope"),
              info.fqName[3] == name,
              sema.symbols.functionSignature(for: symbol)?.isSuspend == true
        else {
            return false
        }
        return true
    }

    func rewriteSequenceBuilderCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        thrownResult: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout KIRLoweringEmitContext
    ) -> Bool {
        if callee == lookup.kkSequenceBuilderBuildName {
            if let result { state.sequenceExprIDs.insert(result.rawValue) }
            return false
        }

        if callee == lookup.kkIteratorBuilderBuildName {
            if let result { state.iteratorBuilderExprIDs.insert(result.rawValue) }
            return false
        }

        // KSP-1519: `sequence { ... }`/`iterator { ... }` are now source-backed
        // (Stdlib/kotlin/sequences/SequenceBuilder.kt, @KsSymbolName-bridged to
        // __kk_sequence_builder_build / __kk_iterator_builder_build), so the
        // normal external-call codegen path already emits calls to those names
        // directly — the two guards above pick them up for state tracking.
        // The raw-source-name rewrites that used to synthesize these calls for
        // the Swift-side synthetic stub were removed here.

        if callee == lookup.yieldName,
           arguments.count == 2,
           isSequenceScopeBuilderMethod(symbol, named: lookup.yieldName, ctx: ctx)
        {
            let builderArg = arguments[0]
            let valueArg = arguments[1]
            let storedValue: KIRExprID
            if let types = ctx.sema?.types,
               let argType = module.arena.exprType(valueArg),
               let boxCallee = primitiveBoxCalleeName(
                   for: argType,
                   types: types,
                   symbols: ctx.sema?.symbols,
                   interner: ctx.interner
               )
            {
                let boxedResult = module.arena.appendTemporary(type: types.anyType)
                emitBoxCallWithValueClassTag(
                    boxCallee: boxCallee,
                    value: valueArg,
                    rawSourceKind: types.kind(of: argType),
                    result: boxedResult,
                    resultType: types.anyType,
                    types: types,
                    symbols: ctx.sema?.symbols,
                    interner: ctx.interner,
                    arena: module.arena,
                    sema: ctx.sema,
                    cache: ctx.nominalDispatchCache,
                    into: &loweredBody
                )
                storedValue = boxedResult
            } else {
                storedValue = valueArg
            }
            loweredBody.append(.call(
                callee: lookup.kkSequenceBuilderYieldName,
                arguments: [builderArg, storedValue],
                result: result,
                canThrow: false
            ))
            return true
        }

        // Keep initial iterator-probe exceptions in the producer's catch scope.
        if callee == lookup.yieldAllName,
           arguments.count == 2,
           isSequenceScopeBuilderMethod(symbol, named: lookup.yieldAllName, ctx: ctx)
        {
            loweredBody.append(.call(
                callee: lookup.kkSequenceBuilderYieldAllName,
                arguments: arguments,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return true
        }

        return false
    }
}
