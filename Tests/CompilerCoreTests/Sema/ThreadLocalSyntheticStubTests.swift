@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ThreadLocalSyntheticStubTests {
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
            // testThreadLocalConstructorAndGetOrSetSignatures
            """
            package sample0
            fun noop() {}
            """,
            // testThreadLocalGetOrSetResolvesInSource
            """
            package sample1

                    import java.lang.ThreadLocal
                    import kotlin.concurrent.getOrSet

                    fun probe(): Int {
                        val tl = ThreadLocal<Int>()
                        return tl.getOrSet { 42 }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testThreadLocalConstructorAndGetOrSetSignatures ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let threadLocalFQName = ["java", "lang", "ThreadLocal"].map { interner.intern($0) }
                let threadLocalSymbol = try #require(
                    sema.symbols.lookup(fqName: threadLocalFQName),
                    "Expected java.lang.ThreadLocal to be registered"
                )
                #expect(sema.symbols.symbol(threadLocalSymbol)?.kind == .class)

                let classTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: threadLocalSymbol)
                #expect(classTypeParameterSymbols.count == 1)
                #expect(sema.types.nominalTypeParameterVariances(for: threadLocalSymbol) == [.invariant])

                let classTParamSymbol = try #require(classTypeParameterSymbols.first)
                let classTType = sema.types.make(.typeParam(TypeParamType(
                    symbol: classTParamSymbol,
                    nullability: .nonNull
                )))
                let threadLocalClassType = sema.types.make(.classType(ClassType(
                    classSymbol: threadLocalSymbol,
                    args: [.invariant(classTType)],
                    nullability: .nonNull
                )))

                let initSymbol = try #require(
                    sema.symbols.lookup(fqName: threadLocalFQName + [interner.intern("<init>")]),
                    "Expected java.lang.ThreadLocal.<init> to be registered"
                )
                let initSignature = try #require(sema.symbols.functionSignature(for: initSymbol))
                #expect(initSignature.receiverType == nil)
                #expect(initSignature.parameterTypes == [])
                #expect(initSignature.returnType == threadLocalClassType)
                #expect(initSignature.typeParameterSymbols == [classTParamSymbol])
                #expect(initSignature.classTypeParameterCount == 1)
                #expect(sema.symbols.externalLinkName(for: initSymbol) == "kk_thread_local_new")

                let getOrSetFQName = ["kotlin", "concurrent", "getOrSet"].map { interner.intern($0) }
                let getOrSetSymbol = try #require(
                    sema.symbols.lookup(fqName: getOrSetFQName),
                    "Expected kotlin.concurrent.getOrSet to be registered"
                )
                let getOrSetSignature = try #require(sema.symbols.functionSignature(for: getOrSetSymbol))
                #expect(sema.symbols.symbol(getOrSetSymbol)?.flags.contains(.synthetic) == true)
                #expect(sema.symbols.symbol(getOrSetSymbol)?.flags.contains(.inlineFunction) == true)
                #expect(sema.symbols.externalLinkName(for: getOrSetSymbol) == "kk_thread_local_getOrSet")

                let functionTParamSymbol = try #require(getOrSetSignature.typeParameterSymbols.first)
                #expect(functionTParamSymbol != classTParamSymbol)

                let functionTType = sema.types.make(.typeParam(TypeParamType(
                    symbol: functionTParamSymbol,
                    nullability: .nonNull
                )))
                let receiverType = sema.types.make(.classType(ClassType(
                    classSymbol: threadLocalSymbol,
                    args: [.invariant(functionTType)],
                    nullability: .nonNull
                )))
                let defaultFunctionType = sema.types.make(.functionType(FunctionType(
                    params: [],
                    returnType: functionTType
                )))

                #expect(getOrSetSignature.receiverType == receiverType)
                #expect(getOrSetSignature.parameterTypes == [defaultFunctionType])
                #expect(getOrSetSignature.returnType == functionTType)
                #expect(getOrSetSignature.typeParameterSymbols == [functionTParamSymbol])
                #expect(getOrSetSignature.classTypeParameterCount == 0)

            }

            // === testThreadLocalGetOrSetResolvesInSource ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(sample1Diagnostics.isEmpty)

                let constructorCall = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "ThreadLocal"
                })
                let constructorCallee = try #require(
                    sema.bindings.callBinding(for: constructorCall)?.chosenCallee
                )
                #expect(
                    sema.symbols.externalLinkName(for: constructorCallee) == "kk_thread_local_new"
                )

                let getOrSetCall = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "getOrSet"
                })
                let chosenGetOrSet = try #require(
                    sema.bindings.callBinding(for: getOrSetCall)?.chosenCallee
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenGetOrSet) == "kk_thread_local_getOrSet"
                )

            }

        }
    }

}
