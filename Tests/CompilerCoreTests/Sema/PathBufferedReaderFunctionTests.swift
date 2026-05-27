@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-007: Validates that the `bufferedReader` extension function
/// on `kotlin.io.path.Path` is wired through Sema with the expected
/// charset/bufferSize/options signature and resolves to `kk_path_bufferedReader`.
final class PathBufferedReaderFunctionTests: XCTestCase {
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

    func testPathBufferedReaderExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.bufferedReader(charset, bufferSize, options) extension in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charsetSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let bufferedReaderSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "io", "BufferedReader"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let bufferedReaderType = types.make(.classType(ClassType(classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull)))

            let bufferedReaderSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "bufferedReader"].map(interner.intern))
            let bufferedReader = try XCTUnwrap(bufferedReaderSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, types.intType, openOptionType]
                    && signature.returnType == bufferedReaderType
            })
            XCTAssertEqual(symbols.externalLinkName(for: bufferedReader), "kk_path_bufferedReader")

            let signature = try XCTUnwrap(symbols.functionSignature(for: bufferedReader))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, true, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, false, true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "bufferedReader", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            XCTAssertTrue(chosenCallees.allSatisfy { $0 == bufferedReader })
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], bufferedReaderType)
            }
        }
    }
}
