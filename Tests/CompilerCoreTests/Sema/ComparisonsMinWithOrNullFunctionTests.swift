#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-COMP-FN-056: Validates that `minWithOrNull(comparator)` resolves
/// through Sema for the comparator-based aggregate receivers wired through the
/// standard List / Sequence synthetic-member infrastructure.
/// Both List and Sequence implementations are source-backed and therefore have
/// no direct runtime link.
@Suite
struct ComparisonsMinWithOrNullFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun pickList(xs: List<Int>, cmp: Comparator<Int>): Int? {
            return xs.minWithOrNull(cmp)
        }

        fun pickSequence(xs: Sequence<Int>, cmp: Comparator<Int>): Int? {
            return xs.minWithOrNull(cmp)
        }
        """,
        """
        package sample1
        fun noop() {}
        """,
        """
        package sample2
        fun noop() {}
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    /// `List<T>.minWithOrNull(Comparator)` and `Sequence<T>.minWithOrNull(Comparator)`
    /// must type-check end-to-end from user source.
    @Test func testMinWithOrNullFunctionResolvesInSource() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected minWithOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
    }

    /// `List<T>.minWithOrNull` is source-backed and must not have a `kk_list_*` external link.
    @Test func testListMinWithOrNullIsRegisteredWithRuntimeLink() throws {

        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        let fq = ["kotlin", "collections", "List", "minWithOrNull"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(links.isEmpty, "List.minWithOrNull must be source-backed; found external links: \(links)")
    }

    /// `Sequence<T>.minWithOrNull` is source-backed and therefore has no
    /// `kk_sequence_minWithOrNull` external link.
    @Test func testSequenceMinWithOrNullHasNoRuntimeLink() throws {

        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        let fq = ["kotlin", "sequences", "Sequence", "minWithOrNull"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(links.isEmpty, "Sequence.minWithOrNull should have no runtime link; found: \(links)")
    }
}
#endif
