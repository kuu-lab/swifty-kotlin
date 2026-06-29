#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-007: Validates that the `bufferedReader` extension function
/// on `kotlin.io.path.Path` is wired through Sema with the expected
/// charset/bufferSize/options signature and resolves to `kk_path_bufferedReader`.
@Suite
struct PathBufferedReaderFunctionTests {
    private func memberCallExprIDs(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    @Test func testPathBufferedReaderExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.io.BufferedReader
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.bufferedReader
        import kotlin.text.Charsets

        fun readers(path: Path, option: OpenOption): BufferedReader {
            val first: BufferedReader = path.bufferedReader()
            val second: BufferedReader = path.bufferedReader(Charsets.UTF_8, 4096, option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !ctx.diagnostics.hasError,
                "Path.bufferedReader(charset, bufferSize, options) extension in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let bufferedReaderSymbol = try #require(symbols.lookup(fqName: ["java", "io", "BufferedReader"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let bufferedReaderType = types.make(.classType(ClassType(classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull)))

            let bufferedReaderSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "bufferedReader"].map(interner.intern))
            let bufferedReader = try #require(bufferedReaderSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, types.intType, openOptionType]
                    && signature.returnType == bufferedReaderType
            })
            #expect(symbols.externalLinkName(for: bufferedReader) == "kk_path_bufferedReader")

            let signature = try #require(symbols.functionSignature(for: bufferedReader))
            #expect(signature.valueParameterHasDefaultValues == [true, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "bufferedReader", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            let allMatch = chosenCallees.allSatisfy { $0 == bufferedReader }
            #expect(allMatch)
            for callExpr in callExprs {
                #expect(sema.bindings.exprTypes[callExpr] == bufferedReaderType)
            }
        }
    }
}
#endif
