#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ElvisRhsGenericCallInferenceTests {
    @Test
    func infersUnconstrainedGenericRhsFromNonNullableLhs() throws {
        let sources = [
            """
            package elvisRhsGenericCall
            interface Consumer<in T>
            fun <T> buildConsumer(b: Boolean, block: (Consumer<T>) -> Unit): T? = if (b) ("O" as T) else null
            fun expectConsumerString(value: Consumer<String>) {}
            fun <T> maybe(value: T): T? = value
            fun <T> materialize(): T = "K" as T
            fun original(b: Boolean) = buildConsumer(b) { expectConsumerString(it) } ?: materialize()
            fun minimal() = maybe("O") ?: materialize()
            """,
            """
            package elvisRhsGenericCallVariants
            fun <T> materialize(): T = "K" as T
            fun fromTypedLocal(value: String?) = value ?: materialize()
            fun nullableString(): String? = null
            fun fromNullableCall() = nullableString() ?: materialize()
            fun fromNullableLiteral() = (null as String?) ?: materialize()
            fun withExplicitReturnType(): String = maybe("O") ?: materialize()
            fun <T> maybe(value: T): T? = value
            fun withExplicitTypeArguments() = maybe("O") ?: materialize<String>()
            fun <T> identity(value: T): T = value
            fun heterogeneous(value: String?) = value ?: identity(42)
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "got: \(errors.map { "\($0.code): \($0.message)" })")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var materializeCalls: [ExprID] = []
            for path in paths {
                materializeCalls.append(contentsOf: allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return ctx.interner.resolve(name) == "materialize"
                })
            }
            #expect(materializeCalls.count == 7)
            for call in materializeCalls {
                let binding = try #require(sema.bindings.callBinding(for: call))
                #expect(binding.substitutedTypeArguments == [sema.types.stringType])
            }

            let identityCalls = allExprIDs(in: ast, path: paths[1], ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "identity"
            }
            let identityCall = try #require(identityCalls.first)
            let identityBinding = try #require(sema.bindings.callBinding(for: identityCall))
            #expect(identityBinding.substitutedTypeArguments == [sema.types.intType])
        }
    }
}
#endif
