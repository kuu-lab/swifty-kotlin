@testable import CompilerCore
import Testing

/// KSP-1351: the whole last family (`last`, `last(predicate)`,
/// `lastOrNull`, `lastOrNull(predicate)`) resolves via the canonical
/// `kotlin.sequences` source declarations — lazy iterator implementations
/// living in SequenceConversionsAndSetOps.kt — not via a synthetic stub or
/// an `@KsSymbolName` external link.
@Suite
struct SequenceLastFunctionTests {
    @Test func testSequenceLastFamilyResolvesToCanonicalSource() throws {
        let ctx = makeContextFromSource("""
        fun final(values: Sequence<Int>): Int {
            return values.last()
        }

        fun finalMatching(values: Sequence<Int>): Int {
            return values.last { it > 1 }
        }

        fun finalOrNull(values: Sequence<Int>): Int? {
            return values.lastOrNull()
        }

        fun finalMatchingOrNull(values: Sequence<Int>): Int? {
            return values.lastOrNull { it > 1 }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence last family to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        // Bundled stdlib bodies share the AST with user code (and contain
        // their own `this.last()` calls on List receivers), so select the
        // user calls by the `values` receiver name.
        for name in ["last", "lastOrNull"] {
            for arity in 0...1 {
                let callExprID = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(receiver, callee, _, arguments, _) = expr,
                          ctx.interner.resolve(callee) == name,
                          arguments.count == arity,
                          case let .nameRef(receiverName, _) = ast.arena.expr(receiver)
                    else { return false }
                    return receiverName == ctx.interner.intern("values")
                }, "Expected \(name) member call with \(arity) args")

                let binding = try #require(sema.bindings.callBinding(for: callExprID))
                let chosenCallee = try #require(binding.chosenCallee)
                let fqName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
                    .map { ctx.interner.resolve($0) }
                #expect(fqName == ["kotlin", "sequences", name])
                #expect(
                    sema.symbols.isSourceBackedSymbol(chosenCallee),
                    "Expected Sequence.\(name) to resolve to bundled source"
                )
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            }
        }
    }
}
