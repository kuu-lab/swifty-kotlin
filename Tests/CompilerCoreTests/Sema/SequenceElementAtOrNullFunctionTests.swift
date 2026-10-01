@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-022: Validates that `Sequence<T>.elementAtOrNull(index)` resolves
/// through Sema and is wired to the runtime entry point `kk_sequence_elementAtOrNull`.
/// The terminal operator returns the element at the given index, or `null` when the
/// index is out of range, without throwing.
@Suite
struct SequenceElementAtOrNullFunctionTests {
    @Test func testSequenceElementAtOrNullResolvesAndReturnsNullableElement() throws {
        let ctx = makeContextFromSource("""
        fun maybeSecond(values: Sequence<Int>): Int? {
            return values.elementAtOrNull(1)
        }

        fun maybeFromGenerated(): String? {
            return sequenceOf("alpha", "beta", "gamma").elementAtOrNull(0)
        }
        """)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            Comment(rawValue: "Expected Sequence.elementAtOrNull(index) to type-check, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")
        )

        let sema = try #require(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", "elementAtOrNull"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            links.isEmpty,
            Comment(rawValue: "Expected Sequence.elementAtOrNull to be backed by source, found: \(links)")
        )
    }

    /// KSP-1341: the whole element family (`elementAt`, `elementAtOrElse`,
    /// `elementAtOrNull`) resolves via the canonical `kotlin.sequences`
    /// source declarations — lazy iterator implementations living in
    /// SequenceConversionsAndSetOps.kt — not via a synthetic stub or an
    /// `@KsSymbolName` external link.
    @Test func testSequenceElementFamilyResolvesToCanonicalSource() throws {
        let ctx = makeContextFromSource("""
        fun at(values: Sequence<Int>): Int {
            return values.elementAt(1)
        }

        fun atOrElse(values: Sequence<Int>): Int {
            return values.elementAtOrElse(9) { -1 }
        }

        fun atOrNull(values: Sequence<Int>): Int? {
            return values.elementAtOrNull(1)
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence element family to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        // Bundled stdlib bodies share the AST with user code (and contain
        // their own `elementAt*` calls on Iterable receivers), so select the
        // user calls by the `values` receiver name.
        let expected: [(name: String, arity: Int)] = [
            ("elementAt", 1),
            ("elementAtOrElse", 2),
            ("elementAtOrNull", 1),
        ]
        for (name, arity) in expected {
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
