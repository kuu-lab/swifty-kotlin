#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct WhenLambdaTailInferenceTests {
    @Test
    func nonExhaustiveTailInfersUnitForLambdaAndGenericCall() throws {
        let source = """
        fun <T> invokeBlock(block: () -> T): T = block()

        fun infer() {
            val direct = direct@{ when (1) { 1 -> 42 } }
            val directUnit: () -> Unit = direct
            val throughCall = invokeBlock throughCall@{ when (1) { 1 -> 42 } }
            val callUnit: Unit = throughCall
            val exhaustive = exhaustive@{ when (true) { true -> 3; false -> 4 } }
            val exhaustiveInt: () -> Int = exhaustive
            val nonTail = nonTail@{ when (1) { 1 -> 42 }; 5 }
            val nonTailInt: () -> Int = nonTail
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedReturnTypes: [String: TypeID] = [
                "direct": sema.types.unitType,
                "throughCall": sema.types.unitType,
                "exhaustive": sema.types.intType,
                "nonTail": sema.types.intType,
            ]
            for (label, expectedReturnType) in expectedReturnTypes {
                let lambdas = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                    guard case let .lambdaLiteral(_, _, lambdaLabel?, _) = expr else { return false }
                    return ctx.interner.resolve(lambdaLabel) == label
                }
                #expect(lambdas.count == 1, "Expected one lambda labeled \(label)")
                guard let lambda = lambdas.first,
                      let lambdaType = sema.bindings.exprType(for: lambda),
                      case let .functionType(function) = sema.types.kind(of: lambdaType)
                else {
                    Issue.record("Expected a function type for lambda \(label)")
                    continue
                }
                #expect(
                    function.returnType == expectedReturnType,
                    "Expected \(label) to return \(sema.types.renderType(expectedReturnType)), got \(sema.types.renderType(function.returnType))"
                )
            }
        }
    }

    @Test
    func lambdaTailCarveOutPreservesExpressionAndExhaustivenessChecks() throws {
        let sources = [
            """
            fun infer() {
                val bad: () -> Int = { when (1) { 1 -> 42 } }
            }
            """,
            """
            fun infer() {
                val bad = { (when (1) { 1 -> 42 }) }
            }
            """,
            """
            fun infer() {
                val bad = { when (true) { true -> 42 } }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)

            let explicitlyTypedErrors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(!explicitlyTypedErrors.isEmpty, "A Unit-valued lambda must not satisfy () -> Int")
            #expect(
                !explicitlyTypedErrors.contains(where: { $0.code == "KSWIFTK-SEMA-0004" }),
                "The lambda tail should be treated as a statement before its return type is checked: \(explicitlyTypedErrors)"
            )

            for index in 1 ... 2 {
                let errors = diagnosticsForPath(paths[index], in: ctx).filter { $0.severity == .error }
                #expect(
                    errors.contains(where: { $0.code == "KSWIFTK-SEMA-0004" }),
                    "Case \(index) must still reject a non-exhaustive expression: \(errors)"
                )
            }
        }
    }
}
#endif
