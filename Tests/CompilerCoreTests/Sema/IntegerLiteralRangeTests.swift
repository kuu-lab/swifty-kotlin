#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IntegerLiteralRangeTests {
    private func buildFrontend(_ source: String) throws -> (CompilationContext, ASTModule, FileID) {
        var result: (CompilationContext, ASTModule, FileID)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runFrontend(ctx)
            result = (ctx, try #require(ctx.ast), try #require(ctx.sourceManager.fileIDs().first))
        }
        return try #require(result)
    }

    private func localInitializers(
        in ast: ASTModule,
        fileID: FileID,
        interner: StringInterner
    ) -> [String: ExprID] {
        Dictionary(uniqueKeysWithValues: ast.arena.exprs.enumerated().compactMap { (index, expr) -> (String, ExprID)? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .localDecl(name, _, _, initializer?, _, _) = expr,
                  ast.arena.exprRange(exprID)?.start.file == fileID
            else {
                return nil
            }
            return (interner.resolve(name), initializer)
        })
    }

    @Test
    func unsuffixedLiteralsWidenAtInt32Boundary() throws {
        let source = """
        fun probe() {
            val decimal = 4294967296
            val hexadecimal = 0x80000000
            val unsigned = 4294967296u
            val small = 2147483647
        }
        """
        let (ctx, ast, fileID) = try buildFrontend(source)
        let initializers = localInitializers(in: ast, fileID: fileID, interner: ctx.interner)

        guard let decimal = initializers["decimal"],
              let hexadecimal = initializers["hexadecimal"],
              let unsigned = initializers["unsigned"],
              let small = initializers["small"]
        else {
            Issue.record("Expected all integer literal local declarations in the user source")
            return
        }

        guard case .longLiteral(4294967296, _) = ast.arena.expr(decimal) else {
            Issue.record("4294967296 must be represented as a Long literal in the AST")
            return
        }
        guard case .longLiteral(2147483648, _) = ast.arena.expr(hexadecimal) else {
            Issue.record("0x80000000 must be represented as a Long literal in the AST")
            return
        }
        guard case .ulongLiteral(4294967296, _) = ast.arena.expr(unsigned) else {
            Issue.record("4294967296u must be represented as a ULong literal in the AST")
            return
        }
        guard case .intLiteral(2147483647, _) = ast.arena.expr(small) else {
            Issue.record("2147483647 must remain an Int literal in the AST")
            return
        }

        try SemaPhase().run(ctx)
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.exprType(for: decimal) == sema.types.longType)
        #expect(sema.bindings.exprType(for: hexadecimal) == sema.types.longType)
        #expect(sema.bindings.exprType(for: unsigned) == sema.types.ulongType)
        #expect(sema.bindings.exprType(for: small) == sema.types.intType)
    }

    @Test
    func signedLiteralsBeyondInt64DoNotWrapToNegativeValues() throws {
        let source = """
        val hexadecimal = 0xFFFFFFFFFFFFFFFF
        val decimal = 9223372036854775808
        val suffixed = 9223372036854775808L
        """
        let (ctx, _, _) = try buildFrontend(source)
        let overflowDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LEX-0002" }
        #expect(overflowDiagnostics.count == 3, "Expected one overflow diagnostic per out-of-range literal, got: \(overflowDiagnostics)")
    }
}
#endif
