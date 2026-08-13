#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-645: `kotlin.experimental` の Byte/Short 版 `and`/`or`/`xor`/`inv`。
///
/// `Byte`/`Short` は独立したプリミティブ型として解決される。
/// これらの呼び出しは `CallTypeChecker+MemberCallInferenceRegularPrimitiveSpecials.swift`
/// の数値特例で解決され、受信型を保つ。値としては kotlinc と一致する
/// （`Scripts/diff_cases/byte_short_bitwise_basic.kt`）。
///
/// このテストは、Byte/Short のビット演算が受信型を保つことを固定する。
@Suite
struct ExperimentalBitwiseFunctionTests {

    private static let bitwiseImports = """
    import kotlin.experimental.and
    import kotlin.experimental.inv
    import kotlin.experimental.or
    import kotlin.experimental.xor
    """

    private static let sources: [String] = [
        // 0: testByteBitwiseOperationsResolveWithoutDiagnostics
        """
        package sample0

        \(Self.bitwiseImports)

        fun byteOps(a: Byte, b: Byte) {
            println(a and b)
            println(a or b)
            println(a xor b)
            println(a.inv())
            println(a.and(b))
            println(a.or(b))
            println(a.xor(b))
        }
        """,
        // 1: testShortBitwiseOperationsResolveWithoutDiagnostics
        """
        package sample1

        \(Self.bitwiseImports)

        fun shortOps(a: Short, b: Short) {
            println(a and b)
            println(a or b)
            println(a xor b)
            println(a.inv())
            println(a.and(b))
            println(a.or(b))
            println(a.xor(b))
        }
        """,
        // 2: testIntBitwiseIsNotNarrowedByExperimentalImports
        """
        package sample2

        \(Self.bitwiseImports)

        fun intOps(): Int {
            val wide: Int = 0x1234 and 0xFF00
            return wide
        }
        """,
        // 3: testBitwiseResultKeepsReceiverType (Byte)
        """
        package sample3

        \(Self.bitwiseImports)

        fun ops(a: Byte, b: Byte) {
            println(a and b)
            println(a.inv())
        }
        """,
        // 4: testBitwiseResultKeepsReceiverType (Short)
        """
        package sample4

        \(Self.bitwiseImports)

        fun ops(a: Short, b: Short) {
            println(a and b)
            println(a.inv())
        }
        """,
    ]

    private static nonisolated(unsafe) var _shared: (ctx: CompilationContext, paths: [String])?

    private func shared() throws -> (ctx: CompilationContext, paths: [String]) {
        if let cached = Self._shared { return cached }
        var result: (ctx: CompilationContext, paths: [String])?
        try withTemporaryFiles(contents: Self.sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let pair = try #require(result)
        Self._shared = pair
        return pair
    }

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path,
                  predicate(exprID, expr)
            else { continue }
            return exprID
        }
        return nil
    }

    @Test func testByteBitwiseOperationsResolveWithoutDiagnostics() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Byte bitwise operations to resolve: \\(errors.map { $0.message })"
        )
    }

    @Test func testShortBitwiseOperationsResolveWithoutDiagnostics() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Short bitwise operations to resolve: \\(errors.map { $0.message })"
        )
    }

    @Test func testBitwiseResultKeepsReceiverType() throws {
        let (ctx, paths) = try shared()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let samples: [(path: String, typeName: String, receiverType: TypeID)] = [
            (paths[3], "Byte", sema.types.byteType),
            (paths[4], "Short", sema.types.shortType),
        ]

        for (samplePath, typeName, receiverType) in samples {
            for name in ["and", "inv"] {
                let callExpr = try #require(
                    firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return ctx.interner.resolve(callee) == name
                    },
                    "Expected \\(typeName).\\(name) member call"
                )
                #expect(
                    sema.bindings.exprType(for: callExpr) == receiverType,
                    "\\(typeName).\\(name) should keep the receiver type"
                )
            }
        }
    }

    @Test func testIntBitwiseIsNotNarrowedByExperimentalImports() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Int bitwise operations to resolve: \\(errors.map { $0.message })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(
            firstExprID(in: ast, path: paths[2], ctx: ctx) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "and"
            },
            "Expected Int.and member call"
        )
        #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
    }
}
#endif
