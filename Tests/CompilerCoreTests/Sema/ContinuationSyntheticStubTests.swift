#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ContinuationSyntheticStubTests {
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
            // testContinuationAndCoroutineContextStubsAreRegistered
            """
            package sample0
            fun noop() {}
            """,
            // testCreateCoroutineUninterceptedOverloadsAreRegistered
            """
            package sample1
            fun noop() {}
            """,
            // testCreateCoroutineOverloadsAreRegistered
            """
            package sample2
            fun noop() {}
            """,
            // testStartCoroutineOverloadsAreRegistered
            """
            package sample3
            fun noop() {}
            """,
            // testContinuationInterceptedResolvesInSource
            """
            package sample4

                    import kotlin.coroutines.Continuation
                    import kotlin.coroutines.intrinsics.intercepted

                    fun probe(c: Continuation<Int>): Continuation<Int> {
                        return c.intercepted()
                    }

            """,
            // testContinuationFactoryResolvesInSource
            """
            package sample5

                    import kotlin.coroutines.Continuation
                    import kotlin.coroutines.CoroutineContext

                    fun probe(context: CoroutineContext): Continuation<Int> {
                        return Continuation<Int>(context = context, resumeWith = { result: Result<Int> -> println(result) })
                    }

            """,
            // testStartCoroutineNoReceiverResolvesInSource
            """
            package sample6

                    import kotlin.coroutines.Continuation
                    import kotlin.coroutines.startCoroutine

                    fun probe(block: suspend () -> Int, completion: Continuation<Int>) {
                        block.startCoroutine(completion)
                    }

            """,
            // testCreateCoroutineNoReceiverResolvesInSource
            """
            package sample7

                    import kotlin.coroutines.Continuation
                    import kotlin.coroutines.createCoroutine

                    fun probe(block: suspend () -> Int, completion: Continuation<Int>): Continuation<Unit> {
                        return block.createCoroutine(completion)
                    }

            """,
            // testStartCoroutineWithReceiverResolvesInSource
            """
            package sample8

                    import kotlin.coroutines.Continuation
                    import kotlin.coroutines.startCoroutine

                    fun probe(block: suspend String.() -> Int, completion: Continuation<Int>) {
                        block.startCoroutine("swift", completion)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testContinuationAndCoroutineContextStubsAreRegistered ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
                let continuationSymbol = try #require(
                    sema.symbols.lookup(fqName: continuationFQName),
                    "Expected kotlin.coroutines.Continuation to be registered"
                )
                #expect(sema.symbols.symbol(continuationSymbol)?.kind == .interface)
                #expect(sema.symbols.symbol(continuationSymbol)?.flags.contains(.synthetic) == true)

                let continuationTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
                #expect(continuationTypeParameterSymbols.count == 1)
                #expect(sema.types.nominalTypeParameterVariances(for: continuationSymbol) == [.invariant])

                let continuationTParamSymbol = try #require(continuationTypeParameterSymbols.first)
                let continuationTType = sema.types.make(.typeParam(TypeParamType(
                    symbol: continuationTParamSymbol,
                    nullability: .nonNull
                )))
                let continuationType = sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(continuationTType)],
                    nullability: .nonNull
                )))

                let coroutineContextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
                let coroutineContextSymbol = try #require(
                    sema.symbols.lookup(fqName: coroutineContextFQName),
                    "Expected kotlin.coroutines.CoroutineContext to be registered"
                )
                #expect(sema.symbols.symbol(coroutineContextSymbol)?.kind == .interface)
                #expect(sema.symbols.symbol(coroutineContextSymbol)?.flags.contains(.synthetic) == true)
                let coroutineContextType = sema.types.make(.classType(ClassType(
                    classSymbol: coroutineContextSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let resultFQName = ["kotlin", "Result"].map { interner.intern($0) }
                let resultSymbol = try #require(
                    sema.symbols.lookup(fqName: resultFQName),
                    "Expected kotlin.Result to be registered"
                )
                let resultOfContinuationTType = sema.types.make(.classType(ClassType(
                    classSymbol: resultSymbol,
                    args: [.invariant(continuationTType)],
                    nullability: .nonNull
                )))

                let contextSymbol = try #require(
                    sema.symbols.lookup(fqName: continuationFQName + [interner.intern("context")]),
                    "Expected Continuation.context to be registered"
                )
                #expect(sema.symbols.symbol(contextSymbol)?.kind == .property)
                #expect(sema.symbols.propertyType(for: contextSymbol) == coroutineContextType)

                let resumeWithSymbol = try #require(
                    sema.symbols.lookup(fqName: continuationFQName + [interner.intern("resumeWith")]),
                    "Expected Continuation.resumeWith to be registered"
                )
                let resumeWithSignature = try #require(sema.symbols.functionSignature(for: resumeWithSymbol))
                #expect(resumeWithSignature.receiverType == continuationType)
                #expect(resumeWithSignature.parameterTypes == [resultOfContinuationTType])
                #expect(resumeWithSignature.returnType == sema.types.unitType)
                #expect(resumeWithSignature.typeParameterSymbols == [continuationTParamSymbol])
                #expect(resumeWithSignature.classTypeParameterCount == 1)

                // Sanity-check the Result<T> shape used by the parameter type.
                #expect(
                    resultOfContinuationTType ==
                    sema.types.make(.classType(ClassType(
                        classSymbol: resultSymbol,
                        args: [.invariant(continuationTType)],
                        nullability: .nonNull
                    )))
                )

                let continuationFactorySymbol = try #require(
                    sema.symbols.lookupAll(fqName: continuationFQName).first { symbolID in
                        sema.symbols.symbol(symbolID)?.kind == .function
                    },
                    "Expected kotlin.coroutines.Continuation factory function to be registered"
                )
                let continuationFactorySignature = try #require(sema.symbols.functionSignature(for: continuationFactorySymbol))
                #expect(sema.symbols.externalLinkName(for: continuationFactorySymbol) == "kk_coroutine_continuation_factory")
                #expect(continuationFactorySignature.typeParameterSymbols.count == 1)
                let continuationFactoryTParamSymbol = try #require(continuationFactorySignature.typeParameterSymbols.first)
                let continuationFactoryTType = sema.types.make(.typeParam(TypeParamType(
                    symbol: continuationFactoryTParamSymbol,
                    nullability: .nonNull
                )))
                let resultOfContinuationFactoryTType = sema.types.make(.classType(ClassType(
                    classSymbol: resultSymbol,
                    args: [.invariant(continuationFactoryTType)],
                    nullability: .nonNull
                )))
                let continuationFactoryResumeWithType = sema.types.make(.functionType(FunctionType(
                    params: [resultOfContinuationFactoryTType],
                    returnType: sema.types.unitType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let continuationFactoryReturnType = sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(continuationFactoryTType)],
                    nullability: .nonNull
                )))
                #expect(continuationFactorySignature.parameterTypes == [
                    coroutineContextType,
                    continuationFactoryResumeWithType,
                ])
                #expect(continuationFactorySignature.returnType == continuationFactoryReturnType)

                let interceptorFQName = ["kotlin", "coroutines", "ContinuationInterceptor"].map { interner.intern($0) }
                let interceptorSymbol = try #require(
                    sema.symbols.lookup(fqName: interceptorFQName),
                    "Expected kotlin.coroutines.ContinuationInterceptor to be registered"
                )
                #expect(sema.symbols.symbol(interceptorSymbol)?.kind == .interface)
                let dispatcherFQName = ["kotlinx", "coroutines", "CoroutineDispatcher"].map { interner.intern($0) }
                let dispatcherSymbol = try #require(
                    sema.symbols.lookup(fqName: dispatcherFQName),
                    "Expected kotlinx.coroutines.CoroutineDispatcher to be registered"
                )
                #expect(
                    sema.symbols.directSupertypes(for: dispatcherSymbol).contains(interceptorSymbol),
                    "CoroutineDispatcher should be a ContinuationInterceptor"
                )

                let interceptedFQName = ["kotlin", "coroutines", "intrinsics", "intercepted"].map { interner.intern($0) }
                let interceptedSymbol = try #require(
                    sema.symbols.lookup(fqName: interceptedFQName),
                    "Expected kotlin.coroutines.intrinsics.intercepted to be registered"
                )
                let interceptedSignature = try #require(sema.symbols.functionSignature(for: interceptedSymbol))
                #expect(sema.symbols.externalLinkName(for: interceptedSymbol) == "kk_continuation_intercepted")
                #expect(interceptedSignature.receiverType == continuationType)
                #expect(interceptedSignature.returnType == continuationType)
                #expect(interceptedSignature.typeParameterSymbols == [continuationTParamSymbol])
                #expect(interceptedSignature.classTypeParameterCount == 1)

                let interceptContinuationFQName = ["kotlin", "coroutines", "ContinuationInterceptor", "interceptContinuation"].map { interner.intern($0) }
                let interceptContinuationSymbol = try #require(
                    sema.symbols.lookup(fqName: interceptContinuationFQName),
                    "Expected kotlin.coroutines.ContinuationInterceptor.interceptContinuation to be registered"
                )
                let interceptContinuationSignature = try #require(sema.symbols.functionSignature(for: interceptContinuationSymbol))
                #expect(sema.symbols.externalLinkName(for: interceptContinuationSymbol) == "kk_continuation_interceptor_intercept_continuation")
                let interceptorType = sema.types.make(.classType(ClassType(
                    classSymbol: interceptorSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(interceptContinuationSignature.receiverType == interceptorType)
                #expect(interceptContinuationSignature.parameterTypes == [continuationType])
                #expect(interceptContinuationSignature.returnType == continuationType)
                #expect(interceptContinuationSignature.typeParameterSymbols == [continuationTParamSymbol])

            }

            // === testCreateCoroutineUninterceptedOverloadsAreRegistered ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let createCoroutineFQName = ["kotlin", "coroutines", "intrinsics", "createCoroutineUnintercepted"].map { interner.intern($0) }
                let createCoroutineSymbols = sema.symbols.lookupAll(fqName: createCoroutineFQName)
                #expect(createCoroutineSymbols.count == 2)

                let signatures = createCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
                #expect(signatures.count == 2)
                #expect(signatures.allSatisfy { $0.receiverType != nil })
                #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
                #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))

            }

            // === testCreateCoroutineOverloadsAreRegistered ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let createCoroutineFQName = ["kotlin", "coroutines", "createCoroutine"].map { interner.intern($0) }
                let createCoroutineSymbols = sema.symbols.lookupAll(fqName: createCoroutineFQName)
                #expect(createCoroutineSymbols.count == 2)

                let signatures = createCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
                #expect(signatures.count == 2)
                #expect(createCoroutineSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
                #expect(signatures.allSatisfy { $0.receiverType != nil })
                #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
                #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))

            }

            // === testStartCoroutineOverloadsAreRegistered ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let startCoroutineFQName = ["kotlin", "coroutines", "startCoroutine"].map { interner.intern($0) }
                let startCoroutineSymbols = sema.symbols.lookupAll(fqName: startCoroutineFQName)
                #expect(startCoroutineSymbols.count == 2)

                let signatures = startCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
                #expect(signatures.count == 2)
                #expect(startCoroutineSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
                #expect(signatures.allSatisfy { $0.receiverType != nil })
                #expect(signatures.allSatisfy { $0.returnType == sema.types.unitType })
                #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
                #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))

            }

            // === testContinuationInterceptedResolvesInSource ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(sample4Diagnostics.isEmpty)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample4Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                        return false
                    }
                    return interner.resolve(calleeName) == "intercepted"
                })
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected intercepted() to resolve"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) ==
                    "kk_continuation_intercepted"
                )

            }

            // === testContinuationFactoryResolvesInSource ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                #expect(sample5Diagnostics.isEmpty, "\(sample5Diagnostics)")

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample5Path, ctx: ctx) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "Continuation"
                })
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected Continuation(context, resumeWith) to resolve"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) ==
                    "kk_coroutine_continuation_factory"
                )

            }

            // === testStartCoroutineNoReceiverResolvesInSource ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                #expect(sample6Diagnostics.isEmpty, "\(sample6Diagnostics)")

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample6Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                        return false
                    }
                    return interner.resolve(calleeName) == "startCoroutine"
                })
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected startCoroutine() to resolve"
                )
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.unitType)

            }

            // === testCreateCoroutineNoReceiverResolvesInSource ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                #expect(sample7Diagnostics.isEmpty, "\(sample7Diagnostics)")

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample7Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                        return false
                    }
                    return interner.resolve(calleeName) == "createCoroutine"
                })
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected createCoroutine() to resolve"
                )
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)

            }

            // === testStartCoroutineWithReceiverResolvesInSource ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                #expect(sample8Diagnostics.isEmpty, "\(sample8Diagnostics)")

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample8Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                        return false
                    }
                    return interner.resolve(calleeName) == "startCoroutine"
                })
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected receiver startCoroutine() to resolve"
                )
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.unitType)

            }

        }
    }

}

#endif
