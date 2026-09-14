/// Sequence and iterator builder call rewrites.
extension CollectionLiteralConstructionLoweringPass {
    func rewriteSequenceBuilderCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
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

        // yield(value) inside sequence builder → __kk_sequence_builder_yield
        if callee == lookup.yieldName, arguments.count == 2 {
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
                    into: &loweredBody
                )
                storedValue = boxedResult
            } else {
                storedValue = valueArg
            }
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceBuilderYieldName,
                arguments: [builderArg, storedValue],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        // yieldAll(iterable) inside sequence builder → __kk_sequence_builder_yieldAll (STDLIB-553)
        if callee == lookup.yieldAllName, arguments.count == 2 {
            loweredBody.append(.call(
                symbol: nil,
                callee: lookup.kkSequenceBuilderYieldAllName,
                arguments: arguments,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return true
        }

        return false
    }
}
