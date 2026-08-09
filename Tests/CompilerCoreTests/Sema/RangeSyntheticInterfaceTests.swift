#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct RangeSyntheticInterfaceTests {

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testClosedRangeAndClosedFloatingPointRangeSymbolsAreRegistered
            """
            package sample0
            fun noop() {}
            """,
            // testClosedRangeAndClosedFloatingPointRangeResolveInSource
            """
            package sample1

                    fun inspectClosedRange(range: ClosedRange<Int>): Boolean {
                        return range.start <= range.endInclusive && range.contains(3) && !range.isEmpty()
                    }

                    fun inspectClosedFloatingPointRange(): Boolean {
                        val range = 1.0..4.0
                        return range.start <= range.endInclusive &&
                            range.contains(3.0) &&
                            !range.isEmpty()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testClosedRangeAndClosedFloatingPointRangeSymbolsAreRegistered ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let rangesFQName = ["kotlin", "ranges"].map { interner.intern($0) }
                let closedRangeFQName = rangesFQName + [interner.intern("ClosedRange")]
                let closedFloatingPointRangeFQName = rangesFQName + [interner.intern("ClosedFloatingPointRange")]
                let comparableFQName = ["kotlin", "Comparable"].map { interner.intern($0) }

                let closedRangeSymbol = try #require(
                    sema.symbols.lookup(fqName: closedRangeFQName),
                    "Expected kotlin.ranges.ClosedRange to be registered"
                )
                let closedFloatingPointRangeSymbol = try #require(
                    sema.symbols.lookup(fqName: closedFloatingPointRangeFQName),
                    "Expected kotlin.ranges.ClosedFloatingPointRange to be registered"
                )
                let comparableSymbol = try #require(
                    sema.symbols.lookup(fqName: comparableFQName),
                    "Expected kotlin.Comparable to be registered"
                )

                #expect(sema.symbols.symbol(closedRangeSymbol)?.kind == .interface)
                #expect(sema.symbols.symbol(closedFloatingPointRangeSymbol)?.kind == .interface)

                let closedRangeTypeParamSymbol = try #require(sema.types.nominalTypeParameterSymbols(for: closedRangeSymbol).first)
                let closedFloatingPointRangeTypeParamSymbol = try #require(
                    sema.types.nominalTypeParameterSymbols(for: closedFloatingPointRangeSymbol).first
                )
                let closedRangeTypeParamType = sema.types.make(.typeParam(TypeParamType(
                    symbol: closedRangeTypeParamSymbol,
                    nullability: .nonNull
                )))
                let closedFloatingPointRangeTypeParamType = sema.types.make(.typeParam(TypeParamType(
                    symbol: closedFloatingPointRangeTypeParamSymbol,
                    nullability: .nonNull
                )))

                #expect(sema.types.nominalTypeParameterVariances(for: closedRangeSymbol) == [.invariant])
                #expect(sema.types.nominalTypeParameterVariances(for: closedFloatingPointRangeSymbol) == [.invariant])

                let expectedComparableBoundForClosedRange = sema.types.make(.classType(ClassType(
                    classSymbol: comparableSymbol,
                    args: [.invariant(closedRangeTypeParamType)],
                    nullability: .nonNull
                )))
                let expectedComparableBoundForFloatingPointRange = sema.types.make(.classType(ClassType(
                    classSymbol: comparableSymbol,
                    args: [.invariant(closedFloatingPointRangeTypeParamType)],
                    nullability: .nonNull
                )))

                #expect(
                    sema.symbols.typeParameterUpperBounds(for: closedRangeTypeParamSymbol) == [expectedComparableBoundForClosedRange]
                )
                #expect(
                    sema.symbols.typeParameterUpperBounds(for: closedFloatingPointRangeTypeParamSymbol) == [expectedComparableBoundForFloatingPointRange]
                )

                #expect(
                    sema.symbols.directSupertypes(for: closedFloatingPointRangeSymbol) == [closedRangeSymbol]
                )
                #expect(
                    sema.symbols.supertypeTypeArgs(for: closedFloatingPointRangeSymbol, supertype: closedRangeSymbol) == [.invariant(closedFloatingPointRangeTypeParamType)]
                )

                let closedRangeInterfaceType = sema.types.make(.classType(ClassType(
                    classSymbol: closedRangeSymbol,
                    args: [.invariant(closedRangeTypeParamType)],
                    nullability: .nonNull
                )))
                let closedFloatingPointRangeInterfaceType = sema.types.make(.classType(ClassType(
                    classSymbol: closedFloatingPointRangeSymbol,
                    args: [.invariant(closedFloatingPointRangeTypeParamType)],
                    nullability: .nonNull
                )))

                let startFQName = closedRangeFQName + [interner.intern("start")]
                let endFQName = closedRangeFQName + [interner.intern("endInclusive")]
                let containsFQName = closedRangeFQName + [interner.intern("contains")]
                let isEmptyFQName = closedRangeFQName + [interner.intern("isEmpty")]
                let floatingStartFQName = closedFloatingPointRangeFQName + [interner.intern("start")]
                let floatingEndFQName = closedFloatingPointRangeFQName + [interner.intern("endInclusive")]
                let floatingContainsFQName = closedFloatingPointRangeFQName + [interner.intern("contains")]
                let floatingIsEmptyFQName = closedFloatingPointRangeFQName + [interner.intern("isEmpty")]
                let lessThanOrEqualsFQName = closedFloatingPointRangeFQName + [interner.intern("lessThanOrEquals")]

                let startSymbol = try #require(sema.symbols.lookup(fqName: startFQName))
                let endSymbol = try #require(sema.symbols.lookup(fqName: endFQName))
                let containsSymbol = try #require(sema.symbols.lookup(fqName: containsFQName))
                let isEmptySymbol = try #require(sema.symbols.lookup(fqName: isEmptyFQName))
                let floatingStartSymbol = try #require(sema.symbols.lookup(fqName: floatingStartFQName))
                let floatingEndSymbol = try #require(sema.symbols.lookup(fqName: floatingEndFQName))
                let floatingContainsSymbol = try #require(sema.symbols.lookup(fqName: floatingContainsFQName))
                let floatingIsEmptySymbol = try #require(sema.symbols.lookup(fqName: floatingIsEmptyFQName))
                let lessThanOrEqualsSymbol = try #require(sema.symbols.lookup(fqName: lessThanOrEqualsFQName))

                #expect(sema.symbols.propertyType(for: startSymbol) == closedRangeTypeParamType)
                #expect(sema.symbols.propertyType(for: endSymbol) == closedRangeTypeParamType)
                #expect(sema.symbols.propertyType(for: floatingStartSymbol) == closedFloatingPointRangeTypeParamType)
                #expect(sema.symbols.propertyType(for: floatingEndSymbol) == closedFloatingPointRangeTypeParamType)

                let containsSignature = try #require(sema.symbols.functionSignature(for: containsSymbol))
                #expect(containsSignature.receiverType == closedRangeInterfaceType)
                #expect(containsSignature.parameterTypes == [closedRangeTypeParamType])
                #expect(containsSignature.returnType == sema.types.booleanType)
                let floatingContainsSignature = try #require(sema.symbols.functionSignature(for: floatingContainsSymbol))
                #expect(floatingContainsSignature.receiverType == closedFloatingPointRangeInterfaceType)
                #expect(floatingContainsSignature.parameterTypes == [closedFloatingPointRangeTypeParamType])
                #expect(floatingContainsSignature.returnType == sema.types.booleanType)

                let isEmptySignature = try #require(sema.symbols.functionSignature(for: isEmptySymbol))
                #expect(isEmptySignature.receiverType == closedRangeInterfaceType)
                #expect(isEmptySignature.parameterTypes == [])
                #expect(isEmptySignature.returnType == sema.types.booleanType)
                let floatingIsEmptySignature = try #require(sema.symbols.functionSignature(for: floatingIsEmptySymbol))
                #expect(floatingIsEmptySignature.receiverType == closedFloatingPointRangeInterfaceType)
                #expect(floatingIsEmptySignature.parameterTypes == [])
                #expect(floatingIsEmptySignature.returnType == sema.types.booleanType)

                let lessThanOrEqualsSignature = try #require(sema.symbols.functionSignature(for: lessThanOrEqualsSymbol))
                #expect(lessThanOrEqualsSignature.receiverType == closedFloatingPointRangeInterfaceType)
                #expect(lessThanOrEqualsSignature.parameterTypes == [closedFloatingPointRangeTypeParamType, closedFloatingPointRangeTypeParamType])
                #expect(lessThanOrEqualsSignature.returnType == sema.types.booleanType)

            }

            // === testClosedRangeAndClosedFloatingPointRangeResolveInSource ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnosticSummary = sample1Diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !(sample1Diagnostics.contains { $0.severity == .error }),
                    Comment(rawValue: "Expected ClosedRange and ClosedFloatingPointRange surface to resolve cleanly, got: \(diagnosticSummary)")
                )

            }

        }
    }

}

#endif
