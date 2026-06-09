@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-042: Validates that the `writer` extension function on
/// `kotlin.io.path.Path` is wired through Sema with the expected
/// charset/options signature and resolves to `kk_path_writer`.
///
/// Kotlin signature:
///
///     public actual fun Path.writer(
///         charset: Charset = Charsets.UTF_8,
///         vararg options: OpenOption
///     ): BufferedWriter
final class PathWriterFunctionTests: XCTestCase {

    // MARK: - Basic resolution

    func testPathWriterDefaultCharsetResolves() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer

        fun openWriter(path: Path): BufferedWriter = path.writer()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.writer() with default charset should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathWriterExplicitCharsetResolves() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer
        import kotlin.text.Charsets

        fun openWriter(path: Path): BufferedWriter = path.writer(Charsets.UTF_8)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.writer(charset) should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathWriterWithOpenOptionResolves() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer
        import kotlin.text.Charsets

        fun openWriter(path: Path, option: OpenOption): BufferedWriter =
            path.writer(Charsets.UTF_8, option)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.writer(charset, options) should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathWriterReturnTypeIsBufferedWriter() throws {
        let source = """
        import java.io.BufferedWriter
        import kotlin.io.path.Path
        import kotlin.io.path.writer

        fun check(path: Path): BufferedWriter {
            val w: BufferedWriter = path.writer()
            return w
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.writer() return type should be BufferedWriter: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Chained member calls

    func testPathWriterChainedWriteFlushCloseResolve() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.writer

        fun writeAndClose(path: Path) {
            val writer = path.writer()
            writer.write("hello")
            writer.newLine()
            writer.flush()
            writer.close()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Chained BufferedWriter member calls after Path.writer() should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathWriterUseBlockResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.writer

        fun writeOneLiner(path: Path) {
            path.writer().use { it.write("data") }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.writer().use { } should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Sema surface inspection

    func testPathWriterExtensionFunctionSurfaceIsRegistered() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer
        import kotlin.text.Charsets

        fun stub(path: Path, option: OpenOption): BufferedWriter = path.writer(Charsets.UTF_8, option)
        """

        try withTemporaryFile(contents: source) { filePath in
            let ctx = makeCompilationContext(inputs: [filePath])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.writer(charset, options) should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

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

            let writerSymbols = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "writer"].map(interner.intern)
            )
            let writer = try XCTUnwrap(
                writerSymbols.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == pathType
                        && signature.parameterTypes == [charsetType, openOptionType]
                        && signature.returnType == bufferedWriterType
                },
                "Expected kotlin.io.path.writer with receiver=Path, params=[Charset, OpenOption], ret=BufferedWriter"
            )

            XCTAssertEqual(
                symbols.externalLinkName(for: writer),
                "kk_path_writer"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: writer))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, true])
        }
    }

    func testPathWriterCallBindingAndReturnType() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer
        import kotlin.text.Charsets

        fun writers(path: Path, option: OpenOption): BufferedWriter {
            val first: BufferedWriter = path.writer()
            val second: BufferedWriter = path.writer(Charsets.UTF_8, option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { filePath in
            let ctx = makeCompilationContext(inputs: [filePath])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.writer() calls should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let ast = try XCTUnwrap(ctx.ast)

            let bufferedWriterSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
            )
            let bufferedWriterType = types.make(.classType(ClassType(
                classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
            )))

            let callExprs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      interner.resolve(callee) == "writer"
                else { return nil }
                return exprID
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], bufferedWriterType)
            }
        }
    }
}
