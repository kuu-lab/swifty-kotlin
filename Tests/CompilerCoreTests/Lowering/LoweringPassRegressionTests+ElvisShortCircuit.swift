#if canImport(Testing)
@testable import CompilerCore
import Testing

// BUG-189: `?:` was lowered strictly, as `kk_op_elvis(lhs, rhs)` with both
// operands evaluated up front. The fallback therefore ran even when lhs was
// non-null, so `x ?: return -1` always returned, `x ?: throw e` always threw,
// and any side-effecting fallback always fired. It now lowers to the same
// branch-and-copy shape `&&`/`||` use, with rhs emitted behind a
// `jumpIfNotNull` over it.
extension LoweringPassRegressionTests {
    @Test
    func testElvisLowersToShortCircuitBranchInsteadOfStrictRuntimeCall() throws {
        let source = """
        fun firstOr(x: Int?): Int {
            val v = x ?: -1
            return v
        }
        fun main() {
            println(firstOr(5))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ElvisShortCircuit", emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "firstOr", in: module, interner: ctx.interner)

            #expect(!extractCallees(from: body, interner: ctx.interner).contains("kk_op_elvis"),
                    "?: must not evaluate both operands through the strict runtime helper")
            #expect(body.contains(where: { if case .jumpIfNotNull = $0 { true } else { false } }),
                    "?: must guard its fallback with a non-null branch; body: \(body)")
        }
    }

    @Test
    func testElvisDoesNotEmitFallbackCallBeforeNullCheck() throws {
        let source = """
        fun fallback(): Int = 0
        fun firstOr(x: Int?): Int {
            val v = x ?: fallback()
            return v
        }
        fun main() {
            println(firstOr(5))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ElvisFallbackOrder", emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "firstOr", in: module, interner: ctx.interner)

            let branchIndex = try #require(
                body.firstIndex(where: { if case .jumpIfNotNull = $0 { true } else { false } }),
                "?: must guard its fallback with a non-null branch; body: \(body)"
            )
            let fallbackIndex = try #require(
                body.firstIndex(where: {
                    guard case let .call(_, callee, _, _, _, _, _, _) = $0 else { return false }
                    return ctx.interner.resolve(callee).contains("fallback")
                }),
                "the fallback call must be emitted; body: \(body)"
            )
            #expect(fallbackIndex > branchIndex,
                    "the fallback must be evaluated only on the null path; body: \(body)")
        }
    }
}
#endif
