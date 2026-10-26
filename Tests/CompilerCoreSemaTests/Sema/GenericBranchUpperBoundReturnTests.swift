#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericBranchUpperBoundReturnTests {
    @Test
    func branchExpressionsUseSharedGenericUpperBoundAsReturnType() throws {
        let source = """
        class R<V, E>(val isOk: Boolean, val value: V, val error: E)

        fun <V : U, E : U, U> R<V, E>.mergeIf(): U =
            if (isOk) value else error

        fun <V : U, E : U, U> R<V, E>.mergeWhen(): U =
            when { isOk -> value; else -> error }

        fun <V : U, E : U, U> R<V, E>.mergeValue(): U = value
        fun <V : U, E : U, U> R<V, E>.mergeError(): U = error
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for name in ["mergeIf", "mergeWhen"] {
                let declaration = try #require(ast.files
                    .flatMap(\.topLevelDecls)
                    .compactMap { ast.arena.decl($0) }
                    .compactMap { decl -> FunDecl? in
                        guard case let .funDecl(function) = decl,
                              ctx.interner.resolve(function.name) == name
                        else { return nil }
                        return function
                    }
                    .first)
                guard case let .expr(bodyExpr, _) = declaration.body else {
                    Issue.record("Expected an expression body for \(name)")
                    continue
                }
                let symbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(name)]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sema.bindings.exprType(for: bodyExpr) == signature.returnType)
            }
        }
    }

    @Test
    func branchJoinStillRejectsUnboundedOrIncompatibleResults() throws {
        let source = """
        class R<V, E>(val isOk: Boolean, val value: V, val error: E)

        fun <V, E, U> R<V, E>.unbounded(): U = if (isOk) value else error
        fun <V : U, E : U, U> R<V, E>.narrowResult(): V =
            if (isOk) value else error
        fun <V : U, E : U, U> R<V, E>.unrelatedResult(): String =
            when { isOk -> value; else -> error }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let typeErrors = diagnosticsForPath(path, in: ctx).filter {
                $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001"
            }
            #expect(typeErrors.count >= 3, "Expected all incompatible returns to fail, got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
