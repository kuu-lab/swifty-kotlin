@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-107: Validates that `Sequence<T>.single` resolves through Sema
/// and gets wired to the runtime entry point `kk_sequence_single`. The synthetic
/// surface signature is `single(): T` and the call is marked as throwing because
/// the operation panics when the sequence is empty or contains more than one
/// element.
@Suite
struct SequenceSingleFunctionTests {
    @Test func testSequenceSingleResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun onlyInt(): Int {
            return sequenceOf(42).single()
        }

        fun onlyString(): String {
            return sequenceOf("only").single()
        }

        fun fromSequence(values: Sequence<String>): String {
            return values.single()
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Sequence.single to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        // Bundled stdlib bodies share the AST with user code, so select the
        // user call by its `values` receiver instead of taking the last call.
        let callExpr = try #require(
            lastExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "single",
                      case let .nameRef(receiverName, _) = ast.arena.expr(receiver)
                else { return false }
                return receiverName == ctx.interner.intern("values")
            },
            "Expected single member call"
        )
        #expect(sema.bindings.exprType(for: callExpr) == sema.types.stringType)

        let memberFQName = ["kotlin", "sequences", "Sequence", "single"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            links.isEmpty,
            "Expected Sequence.single to be backed by source, got: \(links)"
        )
    }

    /// KSP-1357: the whole single family (`single`, `single(predicate)`,
    /// `singleOrNull`, `singleOrNull(predicate)`) resolves via the canonical
    /// `kotlin.sequences` source declarations — lazy iterator implementations
    /// living in SequenceConversionsAndSetOps.kt — not via a synthetic stub or
    /// an `@KsSymbolName` external link.
    @Test func testSequenceSingleFamilyResolvesToCanonicalSource() throws {
        let ctx = makeContextFromSource("""
        fun only(values: Sequence<Int>): Int {
            return values.single()
        }

        fun onlyMatching(values: Sequence<Int>): Int {
            return values.single { it > 1 }
        }

        fun onlyOrNull(values: Sequence<Int>): Int? {
            return values.singleOrNull()
        }

        fun onlyMatchingOrNull(values: Sequence<Int>): Int? {
            return values.singleOrNull { it > 1 }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence single family to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        // Bundled stdlib bodies share the AST with user code (and contain
        // their own `this.single()` calls on List receivers), so select the
        // user calls by the `values` receiver name.
        for name in ["single", "singleOrNull"] {
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
