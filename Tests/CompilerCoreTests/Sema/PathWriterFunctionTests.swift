@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-042: Validates that the `writer` extension function
/// on `kotlin.io.path.Path` is wired through Sema with the expected
/// charset/options signature and resolves to `kk_path_writer`.
final class PathWriterFunctionTests: XCTestCase {
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

    func testPathWriterExtensionFunctionResolvesWithDefaultCharset() throws {
        let source = """
        import java.io.BufferedWriter
        import kotlin.io.path.Path
        import kotlin.io.path.writer

        fun openWriter(path: Path): BufferedWriter {
            return path.writer()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.writer() should resolve with default charset, got: \(diagnostics)"
            )
        }
    }

    func testPathWriterExtensionFunctionResolvesWithExplicitCharsetAndOptions() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer
        import kotlin.text.Charsets

        fun openWriter(path: Path, option: OpenOption): BufferedWriter {
            return path.writer(Charsets.UTF_8, option)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.writer(charset, option) should resolve with explicit charset and options, got: \(diagnostics)"
            )
        }
    }

    func testPathWriterFunctionSignatureAndRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let charsetSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern))
            )
            let openOptionSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern))
            )
            let bufferedWriterSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
            )

            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let bufferedWriterType = types.make(.classType(ClassType(classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull)))

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "writer"].map(interner.intern)
            )
            let writer = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, openOptionType]
                    && signature.returnType == bufferedWriterType
            })

            XCTAssertEqual(
                symbols.externalLinkName(for: writer),
                "kk_path_writer",
                "Path.writer should bind to runtime helper kk_path_writer"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: writer))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, true])
            XCTAssertEqual(signature.returnType, bufferedWriterType)
            XCTAssertEqual(signature.receiverType, pathType)
        }
    }

    func testPathWriterCallExpressionTypedAsBufferedWriter() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer
        import kotlin.text.Charsets

        fun openWriter(path: Path, option: OpenOption): BufferedWriter {
            val first = path.writer()
            val second = path.writer(Charsets.UTF_8, option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.writer() should resolve cleanly: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let bufferedWriterSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
            )
            let bufferedWriterType = types.make(
                .classType(ClassType(classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull))
            )

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "writer", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    bufferedWriterType,
                    "Each Path.writer() call expression must be typed as java.io.BufferedWriter"
                )
            }
        }
    }
}
