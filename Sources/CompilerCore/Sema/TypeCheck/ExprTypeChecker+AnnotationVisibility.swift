extension ExprTypeChecker {
    func validateExpressionAnnotationVisibility(_ id: ExprID, ctx: TypeInferenceContext) {
        let annotations = ctx.ast.arena.expressionAnnotations(for: id)
        guard !annotations.isEmpty, let file = ctx.ast.file(for: ctx.currentFileID) else { return }
        let enclosingName = ctx.currentDeclSymbol.flatMap { ctx.sema.symbols.symbol($0)?.fqName } ?? []
        var lexicalOwners: [SymbolID] = []
        var scope: Scope? = ctx.scope
        while let current = scope as? BaseScope {
            if let memberScope = current as? ClassMemberScope { lexicalOwners.append(memberScope.owner) }
            scope = current.parent
        }
        let lexicalNames = lexicalOwners.compactMap { ctx.sema.symbols.symbol($0)?.fqName }
        for annotation in annotations {
            guard let symbolID = resolveAnnotationSymbol(
                named: annotation.name, in: file, symbols: ctx.sema.symbols,
                interner: ctx.interner, types: ctx.sema.types,
                enclosingSymbol: ctx.enclosingClassSymbol, enclosingFQName: enclosingName,
                lexicalEnclosingFQNames: lexicalNames
            ), let symbol = ctx.sema.symbols.symbol(symbolID),
                  !ctx.visibilityChecker.isAccessible(
                      symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                  ), !lexicalOwners.contains(where: {
                      ctx.visibilityChecker.isAccessible(symbol, fromFile: ctx.currentFileID, enclosingClass: $0)
                  }) else { continue }
            driver.helpers.emitVisibilityError(
                for: symbol, name: annotation.name, range: ctx.ast.arena.exprRange(id),
                diagnostics: ctx.sema.diagnostics
            )
        }
    }
}
