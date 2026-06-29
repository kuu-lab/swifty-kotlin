#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-025: Validates that `kotlin.io.path.Path.inputStream(vararg OpenOption)`
/// resolves through Sema for plain Path receivers and yields a `java.io.InputStream` value.
/// The extension function is wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`, and is
/// expected to bind to the runtime helper `kk_path_inputStream` declared in
/// `Sources/RuntimeABI/RuntimeABISpec.swift`.
@Suite
struct PathInputStreamFunctionTests {
    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
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

    @Test func testPathInputStreamResolvesWithNoArguments() throws {
        let source = """
        import java.io.InputStream
        import kotlin.io.path.Path
        import kotlin.io.path.inputStream

        fun openSource(path: Path): InputStream {
            return path.inputStream()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.inputStream() should resolve without arguments, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathInputStreamResolvesWithVarargOpenOptions() throws {
        let source = """
        import java.io.InputStream
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.inputStream

        fun openSource(path: Path, first: OpenOption, second: OpenOption): InputStream {
            return path.inputStream(first, second)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.inputStream(option, option) should resolve with vararg OpenOption args, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathInputStreamFunctionSignatureAndRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let openOptionSymbol = try #require(
                symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern))
            )
            let inputStreamSymbol = try #require(
                symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let openOptionType = types.make(
                .classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull))
            )
            let inputStreamType = types.make(
                .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "inputStream"].map(interner.intern)
            )
            let inputStream = try #require(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [openOptionType]
                    && signature.returnType == inputStreamType
            })

            #expect(
                symbols.externalLinkName(for: inputStream) == "kk_path_inputStream",
                "Path.inputStream should bind to runtime helper kk_path_inputStream"
            )

            let signature = try #require(symbols.functionSignature(for: inputStream))
            #expect(signature.valueParameterIsVararg == [true])
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.returnType == inputStreamType)
            #expect(signature.receiverType == pathType)
        }
    }

    @Test func testPathInputStreamCallExpressionTypedAsInputStream() throws {
        let source = """
        import java.io.InputStream
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.inputStream

        fun openSource(path: Path, option: OpenOption): InputStream {
            val empty = path.inputStream()
            val single = path.inputStream(option)
            return single
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Path.inputStream() should resolve cleanly: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let inputStreamSymbol = try #require(
                symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
            )
            let inputStreamType = types.make(
                .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
            )

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "inputStream", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(
                    sema.bindings.exprTypes[callExpr] == inputStreamType,
                    "Each Path.inputStream() call expression must be typed as java.io.InputStream"
                )
            }
        }
    }
}
#endif
