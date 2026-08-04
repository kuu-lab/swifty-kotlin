#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ConcurrencySyntheticStubTests {

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
            // testThreadClassAndFunctionSignatures
            """
            package sample0
            fun noop() {}
            """,
            // testThreadResolvesInSource
            """
            package sample1

                    import kotlin.concurrent.thread

                    fun probe(): Unit {
                        thread(
                            start = false,
                            isDaemon = false,
                            contextClassLoader = null,
                            name = "worker",
                            priority = 7,
                            block = {}
                        )
                    }

            """,
            // testVolatileAnnotationClassIsRegisteredWithFieldTarget
            """
            package sample2
            fun noop() {}
            """,
            // testVolatileAnnotationResolvesInSource
            """
            package sample3

                    import kotlin.concurrent.Volatile

                    class Holder {
                        @Volatile
                        var value: Int = 0
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testThreadClassAndFunctionSignatures ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let threadFQName = ["java", "lang", "Thread"].map { interner.intern($0) }
                let threadSymbol = try #require(
                    sema.symbols.lookup(fqName: threadFQName),
                    "Expected java.lang.Thread to be registered"
                )
                #expect(sema.symbols.symbol(threadSymbol)?.kind == .class)

                let threadType = sema.types.make(.classType(ClassType(
                    classSymbol: threadSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(sema.symbols.propertyType(for: threadSymbol) == threadType)

                let threadFunctionFQName = ["kotlin", "concurrent", "thread"].map { interner.intern($0) }
                let threadFunctionSymbol = try #require(
                    sema.symbols.lookup(fqName: threadFunctionFQName),
                    "Expected kotlin.concurrent.thread to be registered"
                )
                let threadSignature = try #require(sema.symbols.functionSignature(for: threadFunctionSymbol))
                #expect(sema.symbols.symbol(threadFunctionSymbol)?.flags.contains(.synthetic) == true)
                #expect(sema.symbols.symbol(threadFunctionSymbol)?.flags.contains(.inlineFunction) == true)
                #expect(sema.symbols.externalLinkName(for: threadFunctionSymbol) == "kk_thread_create")
                #expect(threadSignature.receiverType == nil)
                #expect(threadSignature.returnType == threadType)
                #expect(threadSignature.parameterTypes.count == 6)
                #expect(threadSignature.parameterTypes[0] == sema.types.booleanType)
                #expect(threadSignature.parameterTypes[1] == sema.types.booleanType)
                #expect(threadSignature.parameterTypes[3] == sema.types.makeNullable(sema.types.stringType))
                #expect(threadSignature.parameterTypes[4] == sema.types.intType)

                let classLoaderFQName = ["java", "lang", "ClassLoader"].map { interner.intern($0) }
                let classLoaderSymbol = try #require(
                    sema.symbols.lookup(fqName: classLoaderFQName),
                    "Expected java.lang.ClassLoader to be registered"
                )
                let classLoaderType = sema.types.make(.classType(ClassType(
                    classSymbol: classLoaderSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let nullableClassLoaderType = sema.types.makeNullable(classLoaderType)
                #expect(threadSignature.parameterTypes[2] == nullableClassLoaderType)

                let blockType = sema.types.make(.functionType(FunctionType(
                    params: [],
                    returnType: sema.types.unitType
                )))
                #expect(threadSignature.parameterTypes[5] == blockType)
                #expect(threadSignature.valueParameterHasDefaultValues == [true, true, true, true, true, false])

            }

            // === testThreadResolvesInSource ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(!(sample1Diagnostics.contains { $0.severity == .error }), "Expected thread call to resolve: \(sample1Diagnostics.map(\.message))")
                #expect(sample1Diagnostics.isEmpty, "Unexpected diagnostics: \(sample1Diagnostics.map(\.message))")

            }

            // === testVolatileAnnotationClassIsRegisteredWithFieldTarget ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let volatileFQName = ["kotlin", "concurrent", "Volatile"].map { interner.intern($0) }
                let volatileSymbol = try #require(
                    sema.symbols.lookup(fqName: volatileFQName),
                    "Expected kotlin.concurrent.Volatile to be registered"
                )

                #expect(sema.symbols.symbol(volatileSymbol)?.kind == .annotationClass)
                #expect(sema.symbols.symbol(volatileSymbol)?.flags.contains(.synthetic) == true)
                #expect(
                    sema.symbols.annotations(for: volatileSymbol).contains {
                        $0.annotationFQName == "kotlin.annotation.Target"
                            && $0.arguments == ["AnnotationTarget.FIELD"]
                    },
                    "Expected Volatile to carry @Target(AnnotationTarget.FIELD)"
                )

            }

            // === testVolatileAnnotationResolvesInSource ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(!(sample3Diagnostics.contains { $0.severity == .error }), "Expected Volatile annotation to resolve: \(sample3Diagnostics.map(\.message))")

            }

        }
    }

}

#endif
