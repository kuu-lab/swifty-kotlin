
extension CollectionLiteralConstructionLoweringPass {

    /// Result-tagging and closureRaw injection for Reader/BufferedReader
    /// runtime calls that Sema has already rewritten to a `__kk_*` callee via
    /// externalLinkName.
    ///
    /// CLEANUP-STUB-107 removed the parallel `java.io.File` handling this
    /// function used to perform (File(path) construction, File member
    /// dispatch): File's own Sema facade no longer exists, so those branches
    /// were unreachable. CLEANUP-STUB-115 removed the `kotlin.io.path.Path`
    /// branches the same way. What remains here is the Reader/BufferedReader
    /// family, which CLEANUP-STUB-107 kept.
    func rewriteFileCall(
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
        // --- Append closureRaw argument for lambda-accepting methods (STDLIB-322) ---
        // STDLIB-IO-FN-040: covers `__kk_buffered_reader_useLines`, the synthetic
        // stub for `kotlin.io.Reader.useLines` (resolved against `BufferedReader`).
        // STDLIB-IO-FN-017: covers `__kk_buffered_reader_forEachLine`, the synthetic
        // stub for `kotlin.io.Reader.forEachLine` (resolved against `BufferedReader`).
        // When the KIR callee is already rewritten via externalLinkName,
        // the lambda argument must be supplemented with closureRaw (0)
        // so the runtime receives (receiverRaw, fnPtr, closureRaw, outThrown).
        if callee == lookup.kkBufferedReaderUseLinesName
            || callee == lookup.kkBufferedReaderForEachLineName
        {
            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            loweredBody.append(.call(
                symbol: symbol,
                callee: callee,
                arguments: arguments + [zeroExpr],
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult
            ))
            return true
        }

        return false
    }
}
