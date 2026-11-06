#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Regression coverage for KUU-4342: arrow-functions' `currying.kt` /
/// `partials.kt` shape — arity-N `curried()`/`uncurried()` overloads whose
/// bodies are N-deep nested lambda literals or N-deep `this(p1)(p2)...(pn)`
/// invoke chains — used to make `kswiftc` appear to hang (>420s, timeout
/// kill) where each overload alone took seconds.
///
/// Two independent exponential paths were involved:
///
/// - `parseLambdaBody` first probed the body as a block (which fully parsed
///   the nested-lambda subtree once) and then reparsed the same tokens as a
///   single expression, doubling the work at every lambda nesting level —
///   O(2^depth) parses. The block probe's winning expression parse is now
///   reused instead of reparsed.
/// - `inferCallExpr` pre-inferred a nameless call-spine callee, but only
///   kept that type for `inferCallableValueCall` when a nominal `invoke`
///   candidate existed. Function types expose none, so the fallback
///   re-inferred — and re-paid for — the whole callee chain at every level,
///   again O(2^depth).
@Suite
struct DeeplyNestedCallAndLambdaRegressionTests {
    private func context(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path], includeStdlib: false,
            stdlibLibraryPath: nil, allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    /// N-deep `{ pN: Int -> ... }` nesting: every lambda body is a single
    /// expression, which used to trigger the block-probe parse plus a full
    /// expression reparse at each level. Depth 20 is ~1M subtree parses
    /// under the old code (minutes in a debug build) and linear now; the
    /// loose bound only distinguishes "completed" from "exploded".
    @Test
    func deeplyNestedLambdaBodiesDoNotParseExponentially() throws {
        let depth = 20
        var body = "result"
        for level in stride(from: depth, through: 1, by: -1) {
            body = "{ p\(level): Int -> \(body) }"
        }
        let source = """
        fun nested(): Any = \(body)
        """
        let ctx = try context(source)
        let start = Date()
        try runFrontend(ctx)
        let elapsed = Date().timeIntervalSince(start)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
        #expect(elapsed < 30, "lambda body parsing exploded again: \(elapsed)s")
    }

    /// N-deep `this(p1)(p2)...(pn)` invoke chain on a function-typed
    /// receiver — the `uncurried()` shape. Each call-spine level used to
    /// infer its callee chain twice (once for candidate collection, once in
    /// the callable-value fallback), so depth 18 needed ~100s before the
    /// fix; the pre-inferred callee type is now reused and the whole chain
    /// is linear.
    @Test
    func deeplyNestedInvokeChainDoesNotInferExponentially() throws {
        let arity = 18
        let params = (1 ... arity).map { "P\($0)" }.joined(separator: ", ")
        let valueParams = (1 ... arity).map { "p\($0): P\($0)" }.joined(separator: ", ")
        let callChain = (1 ... arity).map { "(p\($0))" }.joined()
        let nestedType = (1 ... arity).reversed().reduce("R") { acc, i in
            "(P\(i)) -> \(acc)"
        }
        let source = """
        fun <\(params), R> (\(nestedType)).uncurriedForTest(): (\(params)) -> R =
            { \(valueParams) -> this\(callChain) }
        """
        let ctx = try context(source)
        let start = Date()
        try runSema(ctx)
        let elapsed = Date().timeIntervalSince(start)
        #expect(!ctx.diagnostics.hasError, "Unexpected: \(ctx.diagnostics.diagnostics)")
        #expect(elapsed < 30, "invoke-chain callee inference exploded again: \(elapsed)s")
    }
}
#endif
