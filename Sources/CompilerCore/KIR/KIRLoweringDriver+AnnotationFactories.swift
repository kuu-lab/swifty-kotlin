extension KIRLoweringDriver {
    func emitAnnotationFactories(shared: KIRLoweringSharedContext, compilationCtx: CompilationContext) {
        for (symbol, expression) in shared.sema.bindings.annotationFactoryExpressions.sorted(by: {
            $0.key.rawValue < $1.key.rawValue
        }) {
            if let range = shared.ast.arena.exprRange(expression),
               let file = shared.ast.file(for: range.start.file),
               shouldSkipAnnotationFactoryFile(file, compilationCtx: compilationCtx) { continue }
            ctx.resetScopeForFunction()
            ctx.beginCallableLoweringScope()
            ctx.setCurrentFunctionSymbol(symbol)
            var body: KIRLoweringEmitContext = [.beginBlock]
            let value = lowerExpr(expression, shared: shared, emit: &body)
            // Instances materialized through annotation reflection render
            // String/Char members quoted like the JVM proxy toString.
            let markResult = shared.arena.appendTemporary(type: shared.sema.types.intType)
            body.append(.call(
                callee: shared.interner.intern("__kk_annotation_mark_reflection_materialized"),
                arguments: [value],
                result: markResult,
                canThrow: false
            ))
            body.append(.returnValue(value))
            body.append(.endBlock)
            guard let name = shared.sema.symbols.symbol(symbol)?.name else { continue }
            _ = shared.arena.appendDecl(.function(KIRFunction(
                symbol: symbol, name: name, params: [], returnType: shared.sema.types.anyType,
                body: body.instructions, isSuspend: false, isInline: false,
                instructionLocations: body.instructionLocations
            )))
            _ = ctx.drainGeneratedCallableDecls()
            ctx.clearImplicitReceiver()
            ctx.setCurrentFunctionSymbol(nil)
        }
    }

    private func shouldSkipAnnotationFactoryFile(_ file: ASTFile, compilationCtx: CompilationContext) -> Bool {
        shouldSkipBundledFileForOutput(file, compilationCtx: compilationCtx)
    }
}
