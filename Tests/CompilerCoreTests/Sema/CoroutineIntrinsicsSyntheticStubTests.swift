#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CoroutineIntrinsicsSyntheticStubTests {
    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func isError(_ diagnostic: Diagnostic) -> Bool {
        diagnostic.severity == .error
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
            // testCoroutineIntrinsicsStubsAreRegisteredWithExpectedShapes
            """
            package sample0
            fun noop() {}
            """,
            // testSuspendCoroutineIntrinsicsResolveInSource
            """
            package sample1

                    import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
                    import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

                    suspend fun probe(): Int {
                        return suspendCoroutineUninterceptedOrReturn { continuation ->
                            COROUTINE_SUSPENDED
                        }
                    }

            """,
            // testStartCoroutineUninterceptedOrReturnOverloadsAreRegistered
            """
            package sample2
            fun noop() {}
            """,
            // testRestrictsSuspensionAnnotationIsRegisteredWithClassTarget
            """
            package sample3
            fun noop() {}
            """,
            // testStartCoroutineUninterceptedOrReturnResolvesInSource
            """
            package sample4

                    import kotlin.coroutines.Continuation
                    import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn

                    fun probe(block: suspend () -> Int, completion: Continuation<Int>): Any? {
                        return block.startCoroutineUninterceptedOrReturn(completion)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testCoroutineIntrinsicsStubsAreRegisteredWithExpectedShapes ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
                let continuationSymbol = try #require(
                    sema.symbols.lookup(fqName: continuationFQName),
                    "Expected kotlin.coroutines.Continuation to be registered"
                )
                #expect(sema.symbols.symbol(continuationSymbol)?.kind == .interface)
                let continuationTypeParams = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
                #expect(continuationTypeParams.count == 1)

                let coroutineSuspendedFQName = ["kotlin", "coroutines", "intrinsics", "COROUTINE_SUSPENDED"].map { interner.intern($0) }
                let coroutineSuspendedSymbol = try #require(
                    sema.symbols.lookup(fqName: coroutineSuspendedFQName),
                    "Expected COROUTINE_SUSPENDED to be registered"
                )
                #expect(sema.symbols.symbol(coroutineSuspendedSymbol)?.kind == .property)
                #expect(sema.symbols.externalLinkName(for: coroutineSuspendedSymbol) == "kk_coroutine_suspended")
                #expect(sema.symbols.propertyType(for: coroutineSuspendedSymbol) == sema.types.nullableAnyType)

                let suspendIntrinsicFQName = ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"].map { interner.intern($0) }
                let suspendIntrinsicSymbol = try #require(
                    sema.symbols.lookup(fqName: suspendIntrinsicFQName),
                    "Expected suspendCoroutineUninterceptedOrReturn to be registered"
                )
                #expect(sema.symbols.symbol(suspendIntrinsicSymbol)?.kind == .function)
                #expect(sema.symbols.externalLinkName(for: suspendIntrinsicSymbol) == nil)

                let signature = try #require(sema.symbols.functionSignature(for: suspendIntrinsicSymbol))
                #expect(signature.isSuspend == true)
                #expect(signature.parameterTypes.count == 1)
                #expect(signature.typeParameterSymbols.count == 1)

                let functionTypeParam = try #require(signature.typeParameterSymbols.first)
                let functionTypeParamType = sema.types.make(.typeParam(TypeParamType(
                    symbol: functionTypeParam,
                    nullability: .nonNull
                )))
                let functionContinuationType = sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(functionTypeParamType)],
                    nullability: .nonNull
                )))
                let blockType = sema.types.make(.functionType(FunctionType(
                    params: [functionContinuationType],
                    returnType: sema.types.nullableAnyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))

                #expect(signature.parameterTypes == [blockType])
                #expect(signature.returnType == functionTypeParamType)

            }

            // === testSuspendCoroutineIntrinsicsResolveInSource ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
                })

                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .suspendCoroutineUninterceptedOrReturn)
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) ==
                    nil
                )
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)

            }

            // === testStartCoroutineUninterceptedOrReturnOverloadsAreRegistered ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let fqName = ["kotlin", "coroutines", "intrinsics", "startCoroutineUninterceptedOrReturn"].map {
                    interner.intern($0)
                }
                let symbols = sema.symbols.lookupAll(fqName: fqName)
                #expect(symbols.count == 2)

                let signatures = symbols.compactMap { sema.symbols.functionSignature(for: $0) }
                #expect(signatures.count == 2)
                #expect(symbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
                #expect(symbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == true })
                #expect(signatures.allSatisfy { $0.receiverType != nil })
                #expect(signatures.allSatisfy { $0.returnType == sema.types.nullableAnyType })
                #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
                #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))

            }

            // === testRestrictsSuspensionAnnotationIsRegisteredWithClassTarget ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let fqName = ["kotlin", "coroutines", "RestrictsSuspension"].map {
                    interner.intern($0)
                }
                let symbolID = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.coroutines.RestrictsSuspension to be registered"
                )
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.kind == .annotationClass)
                #expect(symbol.visibility == .public)
                #expect(symbol.flags.contains(.synthetic))

                let annotations = sema.symbols.annotations(for: symbolID)
                #expect(
                    annotations.contains {
                        $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                            && $0.arguments == ["AnnotationTarget.CLASS"]
                    },
                    "RestrictsSuspension should target class-like declarations, got: \(annotations)"
                )

            }

            // === testStartCoroutineUninterceptedOrReturnResolvesInSource ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(sample4Diagnostics.isEmpty, "\(sample4Diagnostics)")

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample4Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, memberName, _, _, _) = expr else { return false }
                    return interner.resolve(memberName) == "startCoroutineUninterceptedOrReturn"
                })

                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.nullableAnyType)

            }

        }
    }

}

#endif
