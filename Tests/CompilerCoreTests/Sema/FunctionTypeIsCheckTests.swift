@testable import CompilerCore
import Testing

@Suite
struct FunctionTypeIsCheckTests {
    @Test
    func testErasedFunctionChecksEmitErrorsInsteadOfUnresolvedCalls() throws {
        let source = """
        typealias Action = (Int) -> Int
        fun plain(x: Any) = x is (Int) -> Int
        fun negated(x: Any) = x !is (Int) -> Int
        fun suspended(x: Any) = x is suspend (Int) -> Int
        fun receiver(x: Any) = x is Int.() -> Int
        fun suspendReceiver(x: Any) = x is suspend Int.() -> Int
        fun nullable(x: Any?) = x is ((Int) -> Int)?
        fun nested(x: Any) = x is (Int) -> (Int) -> Int
        fun alias(x: Any) = x is Action
        fun branch(x: Any) = when (x) { is (Int) -> Int -> true; else -> false }
        fun negatedBranch(x: Any) = when (x) { !is suspend (Int) -> Int -> true; else -> false }
        fun narrowedResult(x: (Int) -> Any) = x is (Int) -> Int
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 11)
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-ERASED-TYPE" })
            #expect(errors.allSatisfy { $0.message.contains("Cannot check for instance of erased type") })
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let checks = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                if case .isCheck = expr { return true }
                return false
            }
            #expect(checks.count == 11)
            for check in checks {
                let target = try #require(sema.bindings.isCheckTargetType(for: check))
                guard case .functionType = sema.types.kind(of: target) else {
                    Issue.record("The check target should resolve to a function type")
                    continue
                }
                #expect(sema.bindings.exprType(for: check) == sema.types.booleanType)
            }
        }
    }

    @Test
    func testKnownFunctionSignaturesDoNotRequireErasedChecks() throws {
        let source = """
        typealias Action = (Int) -> Int
        fun plain(x: (Int) -> Int) = x is (Int) -> Int
        fun negated(x: (Int) -> Int) = x !is (Int) -> Int
        fun suspended(x: suspend (Int) -> Int) = x is suspend (Int) -> Int
        fun receiver(x: Int.() -> Int) = x is Int.() -> Int
        fun suspendReceiver(x: suspend Int.() -> Int) = x is suspend Int.() -> Int
        fun nullable(x: ((Int) -> Int)?) = x is (Int) -> Int
        fun nullableTarget(x: ((Int) -> Int)?) = x is ((Int) -> Int)?
        fun nested(x: (Int) -> (Int) -> Int) = x is (Int) -> (Int) -> Int
        fun alias(x: Action) = x is Action
        fun widenedResult(x: (Int) -> Int) = x is (Int) -> Any
        fun branch(x: (Int) -> Int) = when (x) { is (Int) -> Int -> true; else -> false }
        fun negatedBranch(x: (Int) -> Int) = when (x) { !is (Int) -> Int -> true; else -> false }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: "\(ctx.diagnostics.diagnostics)"))
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ERASED-TYPE" })
        }
    }
}
