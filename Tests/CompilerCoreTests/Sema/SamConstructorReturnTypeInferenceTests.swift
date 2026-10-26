#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// Generic SAM constructor type arguments can be inferred from the lambda body's result.
@Suite
struct SamConstructorReturnTypeInferenceTests {

    // Keep the API and consumers in separate files, matching the public reproduction.
    private static let sources: [String] = [
        """
        package parser.base

        fun interface Parser<out T> {
            fun parse(source: String): ParserResult<T>
        }
        """,
        """
        package parser.base

        sealed interface ParserResult<out T> {
            data class Success<out T>(val value: T, val remaining: String) : ParserResult<T>
            object Failure : ParserResult<Nothing> {
                override fun toString(): String = "Failure"
            }
        }
        """,
        """
        package parser.intconsumer

        import parser.base.*

        fun requireIntParser(parser: Parser<Int>) {}

        fun main() {
            val parser = Parser { _: String -> ParserResult.Success(3, "") }
            requireIntParser(parser)
            println(parser.parse(""))
        }
        """,
        """
        package parser.stringconsumer

        import parser.base.*

        fun requireStringParser(parser: Parser<String>) {}

        fun main() {
            val parser = Parser { _: String -> ParserResult.Success("ok", "") }
            requireStringParser(parser)
            println(parser.parse(""))
        }
        """,
        """
        package parser.typedconsumer

        import parser.base.*

        fun main() {
            val parser: Parser<Int> = Parser { _: String -> ParserResult.Success(3, "") }
            println(parser.parse(""))
        }
        """,
        """
        package parser.invalidconsumer

        import parser.base.*

        fun main() {
            println(Parser { _: String -> "not a ParserResult" }.parse(""))
        }
        """,
    ]

    private static let _sharedLock = NSLock()
    private static nonisolated(unsafe) var _shared: (ctx: CompilationContext, paths: [String])?

    private func shared() throws -> (ctx: CompilationContext, paths: [String]) {
        Self._sharedLock.lock()
        defer { Self._sharedLock.unlock() }
        if let cached = Self._shared { return cached }
        var result: (ctx: CompilationContext, paths: [String])?
        try withTemporaryFiles(contents: Self.sources) { paths in
            TestStdlibCache.shared.prepare()
            let stdlibLibrary = try #require(CompilerOptions.defaultStdlibLibraryPath)
            let ctx = makeCompilationContext(
                inputs: paths,
                stdlibLibraryPath: stdlibLibrary,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            result = (ctx, paths)
        }
        let pair = try #require(result)
        Self._shared = pair
        return pair
    }

    private func parserType(in path: String, ctx: CompilationContext) -> TypeID? {
        guard let ast = ctx.ast,
              let sema = ctx.sema,
              let fileID = ctx.sourceManager.fileID(forPath: path)
        else {
            return nil
        }
        for (index, expr) in ast.arena.exprs.enumerated() {
            let exprID = ExprID(rawValue: Int32(index))
            guard ast.arena.exprRange(exprID)?.start.file == fileID,
                  case let .call(callee, _, _, _) = expr,
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(name) == "Parser"
            else {
                continue
            }
            return sema.bindings.exprType(for: exprID)
        }
        return nil
    }

    private func expectParserType(_ type: TypeID, equals expected: TypeID, in ctx: CompilationContext) {
        guard let sema = ctx.sema,
              case let .classType(parserType) = sema.types.kind(of: type)
        else {
            Issue.record("Expected an inferred Parser class type")
            return
        }
        #expect(parserType.args == [.invariant(expected)])
    }

    @Test
    func testUntypedIntSamConstructorInfersFromGenericResult() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected Parser<Int> from ParserResult.Success(3, ...), got: \(errors)")
        let type = try #require(parserType(in: paths[2], ctx: ctx))
        let sema = try #require(ctx.sema)
        expectParserType(type, equals: sema.types.intType, in: ctx)
    }

    @Test
    func testUntypedStringSamConstructorInfersFromGenericResult() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[3], in: ctx).filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected Parser<String> from ParserResult.Success(\"ok\", ...), got: \(errors)")
        let type = try #require(parserType(in: paths[3], ctx: ctx))
        let sema = try #require(ctx.sema)
        expectParserType(type, equals: sema.types.stringType, in: ctx)
    }

    @Test
    func testTypedSamConstructorStillCompiles() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[4], in: ctx).filter { $0.severity == .error }
        #expect(errors.isEmpty, "The explicitly typed Parser<Int> control should still compile, got: \(errors)")
        let type = try #require(parserType(in: paths[4], ctx: ctx))
        let sema = try #require(ctx.sema)
        expectParserType(type, equals: sema.types.intType, in: ctx)
    }

    @Test
    func testIncompatibleSamLambdaResultIsRejected() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[5], in: ctx).filter { $0.severity == .error }
        #expect(!errors.isEmpty, "A String lambda result must not satisfy ParserResult<T>")
    }
}
#endif
