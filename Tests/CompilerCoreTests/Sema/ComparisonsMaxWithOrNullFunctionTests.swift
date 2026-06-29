#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-COMP-FN-028: Validates that `maxWithOrNull(comparator)` resolves
/// through Sema for the comparator-based aggregate receivers wired through the
/// standard List / Sequence synthetic-member infrastructure.
/// Runtime link names involved: `kk_list_maxWithOrNull`, `kk_sequence_maxWithOrNull`.
@Suite
struct ComparisonsMaxWithOrNullFunctionTests {

    /// `List<T>.maxWithOrNull(Comparator)` and `Sequence<T>.maxWithOrNull(Comparator)`
    /// must type-check end-to-end from user source.
    @Test func testMaxWithOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun pickList(xs: List<Int>, cmp: Comparator<Int>): Int? {
            return xs.maxWithOrNull(cmp)
        }

        fun pickSequence(xs: Sequence<Int>, cmp: Comparator<Int>): Int? {
            return xs.maxWithOrNull(cmp)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected maxWithOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
    }

    /// `List<T>.maxWithOrNull` must be registered with the `kk_list_maxWithOrNull` external link.
    @Test func testListMaxWithOrNullIsRegisteredWithRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let fq = ["kotlin", "collections", "List", "maxWithOrNull"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(links.contains("kk_list_maxWithOrNull"), "List.maxWithOrNull must link to kk_list_maxWithOrNull; found: \(links)")
    }

    /// `Sequence<T>.maxWithOrNull` must be registered with the
    /// `kk_sequence_maxWithOrNull` external link.
    @Test func testSequenceMaxWithOrNullIsRegisteredWithRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let fq = ["kotlin", "sequences", "Sequence", "maxWithOrNull"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(links.contains("kk_sequence_maxWithOrNull"), "Sequence.maxWithOrNull must link to kk_sequence_maxWithOrNull; found: \(links)")
    }
}
#endif
